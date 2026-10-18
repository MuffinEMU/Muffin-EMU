//
//  iOSAudioAPI.m
//  cemuMain
//
//  Created by Stossy11 on 5/3/2026.
//

#include <TargetConditionals.h>

#if defined(__APPLE__) && TARGET_OS_IOS

#include "iOSAudioAPI.h"
#include "iOSDeviceDescription.h"
#include "iOSAudioRecorder.h"
#include "config/CemuConfig.h"
#include <algorithm>
#include <cstring>
#include <cmath>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <mach/mach_time.h>
#include <mutex>
#include <set>
#include "Cemu/Logging/CemuLogging.h"

// Devices alive right now. The notification blocks run on the main queue and the device can be
// destroyed on the audio/emulator thread, so a block checks membership under this lock first.
// The same lock covers m_audioUnit, which a media services reset replaces from the main queue
// while Play() and Stop() use it from the emulator thread.
static std::mutex s_liveDevicesMutex;
static std::set<IOSAudioAPI*> s_liveDevices;

#if MUFFIN_AUDIT_HOOKS
// MuffinEMU Audit (tools/audit-app): measures what reaches the device. Defined in ios/Bridge/IOSAuditHooks.cpp.
extern "C" void cemu_audit_audio_note_render(const void* device, const int16_t* samples, uint32_t bytesValid,
                                             uint32_t bytesRequested, uint32_t channels, uint32_t bitsPerSample);
extern "C" void cemu_audit_audio_note_feed_reject(void);
#endif

IOSAudioAPI::IOSAudioAPI(uint32 samplerate,
                         uint32 channels,
                         uint32 samples_per_block,
                         uint32 bits_per_sample)
    : IAudioAPI(samplerate, channels, samples_per_block, bits_per_sample),
      m_buffer((size_t)samples_per_block * channels * (bits_per_sample / 8) * kBlockCount)
{
    mach_timebase_info_data_t timebase{};
    if (mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.numer != 0)
        m_hostTicksPerSecond = 1.0e9 * (double)timebase.denom / (double)timebase.numer;

    ConfigureSession();
    if (const char* failure = CreateAudioUnit())
        throw std::runtime_error(failure);

    {
        std::lock_guard lock(s_liveDevicesMutex);
        s_liveDevices.insert(this);
    }
    IOSAudioAPI* device = this;
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    id interruption = [center addObserverForName:AVAudioSessionInterruptionNotification object:nil
                                           queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* note) {
        NSNumber* type = note.userInfo[AVAudioSessionInterruptionTypeKey];
        if (type && type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan)
            device->NoteInterruptionBegan();
        else if (type && type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded)
            device->RestartAfterInterruption("interruption ended");
    }];
    // Backstop: an interruption that ends while the app is in the background does not always post
    // "ended" (iOS documents this), so coming back to the foreground restarts output as well.
    id becameActive = [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                           queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
        device->RestartAfterInterruption("app became active", /*onlyIfStopped*/ true);
    }];
    // A route or category change (headphones, Bluetooth, AirPlay, the microphone being switched on)
    // usually leaves the unit running, but not always, and nothing else would start it again.
    // Routes also change during a call (receiver, headset); the unit is meant to stay stopped then,
    // so a route change inside an interruption is left to the "ended" and foreground paths.
    id routeChange = [center addObserverForName:AVAudioSessionRouteChangeNotification object:nil
                                          queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
        device->RestartAfterInterruption("route changed", /*onlyIfStopped*/ true, /*skipIfInterrupted*/ true);
    }];
    // The media server can be restarted underneath the app (it crashes now and then, and iOS restarts
    // it after some calls). Every audio unit is dead afterwards and restarting one does nothing, so
    // the unit has to be built again or the game stays silent until the app is relaunched.
    id mediaReset = [center addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil
                                         queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
        device->RecreateAfterMediaServicesReset();
    }];
    m_interruptionObserver = (void*)CFBridgingRetain(interruption);
    m_becameActiveObserver = (void*)CFBridgingRetain(becameActive);
    m_routeChangeObserver = (void*)CFBridgingRetain(routeChange);
    m_mediaResetObserver = (void*)CFBridgingRetain(mediaReset);
}

void IOSAudioAPI::ConfigureSession()
{
    NSError* error = nil;
    AVAudioSession* session = [AVAudioSession sharedInstance];

    if (GetConfig().microphone_enabled) {
        // Keep in step with IOSAudioInputAPI::ConfigureSession (default mode: no earpiece
        // routing, no ducking; A2DP so Bluetooth headphones stay high quality).
        [session setCategory:AVAudioSessionCategoryPlayAndRecord
                        mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionMixWithOthers |
                             AVAudioSessionCategoryOptionDefaultToSpeaker |
                             AVAudioSessionCategoryOptionAllowBluetoothA2DP
                       error:&error];
    }
    else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"muffin.audio.respectSilentMode"]) {
        // Settings > Audio > Respect silent mode: ambient audio is muted by the Ring/Silent switch
        // (or Silent mode in Control Centre), like any game on the App Store.
        [session setCategory:AVAudioSessionCategoryAmbient error:&error];
    }
    else {
        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:&error];
    }
    [session setPreferredSampleRate:m_samplerate error:&error];
    [session setPreferredIOBufferDuration:(double)m_samplesPerBlock / m_samplerate error:&error];
    [session setActive:YES error:&error];
    // What iOS actually granted (it rounds the preferred duration, and other audio can hold it higher).
    // Refreshed by every render callback; this is only the starting guess for the first prime.
    m_callbackFrames = (uint32)std::clamp<long>(std::lround(session.IOBufferDuration * m_samplerate), 0, 8192);
}

const char* IOSAudioAPI::CreateAudioUnit()
{
    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp || AudioComponentInstanceNew(comp, &m_audioUnit) != noErr) {
        m_audioUnit = nullptr;
        return "can't initialize iOS audio unit";
    }

    const uint32 bytesPerSample = m_bitsPerSample / 8;

    AudioStreamBasicDescription format{};
    format.mSampleRate       = m_samplerate;
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = m_channels;
    format.mBitsPerChannel   = m_bitsPerSample;
    format.mFramesPerPacket  = 1;
    format.mBytesPerFrame    = m_channels * bytesPerSample;
    format.mBytesPerPacket   = format.mBytesPerFrame * format.mFramesPerPacket;

    if (AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &format, sizeof(format)) != noErr) {
        DisposeAudioUnit();
        return "can't set iOS audio stream format";
    }

    AURenderCallbackStruct callback{};
    callback.inputProc       = RenderCallback;
    callback.inputProcRefCon = this;

    if (AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callback, sizeof(callback)) != noErr) {
        DisposeAudioUnit();
        return "can't set iOS audio render callback";
    }

    if (AudioUnitInitialize(m_audioUnit) != noErr) {
        DisposeAudioUnit();
        return "can't initialize iOS audio unit";
    }
    return nullptr;
}

void IOSAudioAPI::DisposeAudioUnit()
{
    if (!m_audioUnit)
        return;
    AudioOutputUnitStop(m_audioUnit);
    AudioUnitUninitialize(m_audioUnit);
    AudioComponentInstanceDispose(m_audioUnit);
    m_audioUnit = nullptr;
}

void IOSAudioAPI::NoteInterruptionBegan()
{
    std::lock_guard lock(s_liveDevicesMutex);
    if (s_liveDevices.find(this) != s_liveDevices.end())
        m_interrupted = true;
}

void IOSAudioAPI::RestartAfterInterruption(const char* why, bool onlyIfStopped, bool skipIfInterrupted)
{
    std::lock_guard lock(s_liveDevicesMutex);
    if (s_liveDevices.find(this) == s_liveDevices.end())
        return;
    if (skipIfInterrupted && m_interrupted)
        return;
    // "Ended" and coming back to the foreground both mean the interruption is over (the second is
    // the backstop for an "ended" that never arrives).
    if (!skipIfInterrupted)
        m_interrupted = false;
    if (!m_audioUnit || !m_isPlaying)
        return;
    if (onlyIfStopped)
    {
        UInt32 running = 0;
        UInt32 size = sizeof(running);
        if (AudioUnitGetProperty(m_audioUnit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &running, &size) == noErr && running)
            return; // still playing: an ordinary return to the app, nothing to restart
    }
    NSError* error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    // Stop then start: after an interruption the unit can report itself running while producing
    // nothing, so a plain start is not enough.
    AudioOutputUnitStop(m_audioUnit);
    const OSStatus status = AudioOutputUnitStart(m_audioUnit);
    cemuLog_log(LogType::Force, "iOS audio: output restarted ({}): session {}, unit {}", why,
                error ? "could not be reactivated" : "active", status == noErr ? "running" : "failed to start");
}

void IOSAudioAPI::RecreateAfterMediaServicesReset()
{
    std::lock_guard lock(s_liveDevicesMutex);
    if (s_liveDevices.find(this) == s_liveDevices.end())
        return;
    // The old unit is already dead; disposing it only frees our side. The session's category and
    // preferred settings went with the reset, so they are applied again before the new unit.
    m_interrupted = false;
    DisposeAudioUnit();
    ConfigureSession();
    const char* failure = CreateAudioUnit();
    const char* state = "idle";
    if (failure)
        state = failure;
    else if (m_isPlaying)
        state = AudioOutputUnitStart(m_audioUnit) == noErr ? "running" : "failed to start";
    cemuLog_log(LogType::Force, "iOS audio: media services were reset, output unit rebuilt: {}", state);
}

IOSAudioAPI::~IOSAudioAPI()
{
    {
        std::lock_guard lock(s_liveDevicesMutex);
        s_liveDevices.erase(this);
    }
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if (m_interruptionObserver)
        [center removeObserver:(id)CFBridgingRelease(m_interruptionObserver)];
    if (m_becameActiveObserver)
        [center removeObserver:(id)CFBridgingRelease(m_becameActiveObserver)];
    if (m_routeChangeObserver)
        [center removeObserver:(id)CFBridgingRelease(m_routeChangeObserver)];
    if (m_mediaResetObserver)
        [center removeObserver:(id)CFBridgingRelease(m_mediaResetObserver)];
    m_interruptionObserver = nullptr;
    m_becameActiveObserver = nullptr;
    m_routeChangeObserver = nullptr;
    m_mediaResetObserver = nullptr;
    m_isPlaying = false;
    DisposeAudioUnit();
}

bool IOSAudioAPI::Play()
{
    if (m_isPlaying) return true; // every AX frame lands here; no lock on the common path
    std::lock_guard lock(s_liveDevicesMutex);
    if (!m_audioUnit) return false;

    OSStatus status = AudioOutputUnitStart(m_audioUnit);
    if (status != noErr) {
        return false;
    }

    m_isPlaying = true;
    return true;
}

bool IOSAudioAPI::Stop()
{
    std::lock_guard lock(s_liveDevicesMutex);
    if (!m_audioUnit) return false;
    if (!m_isPlaying) return true;

    if (AudioOutputUnitStop(m_audioUnit) != noErr)
        return false;

    m_isPlaying = false;
    return true;
}

size_t IOSAudioAPI::TargetQueuedBytes() const
{
    const size_t bytesPerFrame = (size_t)m_channels * (m_bitsPerSample / 8);
    const size_t blocks = (size_t)GetTargetQueuedBlocks() + m_underrunBlocks.load(std::memory_order_relaxed);
    const size_t fromSetting = blocks * m_bytesPerBlock;
    const size_t oneCallback = (size_t)m_callbackFrames.load(std::memory_order_relaxed) * bytesPerFrame;
    // Room for one more block is always left, or the queue could never reach the target.
    const size_t ceiling = m_buffer.capacity() - m_bytesPerBlock;
    return std::min(std::max(fromSetting, oneCallback + m_bytesPerBlock), ceiling);
}

bool IOSAudioAPI::NeedAdditionalBlocks() const
{
    return m_buffer.size() < TargetQueuedBytes();
}

bool IOSAudioAPI::FeedBlock(sint16* data)
{
    // Logged here, off the render thread, so a crackle report shows what the device settled on.
    const uint32 underrunBlocks = m_underrunBlocks.load(std::memory_order_relaxed);
    if (underrunBlocks != m_loggedUnderrunBlocks)
    {
        m_loggedUnderrunBlocks = underrunBlocks;
        cemuLog_log(LogType::Force, "iOS audio: queue target is now {} blocks ({} added after underruns)",
                    GetTargetQueuedBlocks() + underrunBlocks, underrunBlocks);
    }
    // "Record audio": a copy of the TV mix, taken before it is queued so playback is untouched. Only the
    // TV device; the GamePad's own stream is not part of the recording. A no-op unless a recording is on
    // ("Record audio", or the audio track of "Record screen").
    if (m_bitsPerSample == 16 && IOSAudioRecorder::WantsTap() && this == g_tvAudio.get())
        IOSAudioRecorder::Tap(data, m_samplesPerBlock, m_channels, m_samplerate);
#if MUFFIN_AUDIT_HOOKS
    const bool accepted = m_buffer.write(reinterpret_cast<const std::uint8_t*>(data), m_bytesPerBlock);
    if (!accepted)
        cemu_audit_audio_note_feed_reject();
    return accepted;
#else
    return m_buffer.write(reinterpret_cast<const std::uint8_t*>(data), m_bytesPerBlock);
#endif
}

double IOSAudioAPI::SecondsSince(uint64 hostTime) const
{
    if (m_hostTicksPerSecond <= 0.0)
        return 0.0;
    return (double)(mach_absolute_time() - hostTime) / m_hostTicksPerSecond;
}

// Render thread: the queue has just refilled to the target after running dry.
void IOSAudioAPI::NoteRefilled()
{
    if (m_lastUnderrunHostTime == 0)
        return; // the first prime at start, not an underrun
    if (SecondsSince(m_lastUnderrunHostTime) > kUnderrunWindowSeconds)
        return; // a pause or a long stall: more audio in hand would not have covered it
    const uint32 blocks = m_underrunBlocks.load(std::memory_order_relaxed);
    if (blocks < kMaxUnderrunBlocks)
        m_underrunBlocks.store(blocks + 1, std::memory_order_relaxed);
}

// Render thread, while playing with blocks added: one comes off per kUnderrunDecaySeconds clean.
void IOSAudioAPI::DecayUnderrunBlocks()
{
    if (m_hostTicksPerSecond <= 0.0 || SecondsSince(m_lastUnderrunHostTime) < kUnderrunDecaySeconds)
        return;
    m_lastUnderrunHostTime = mach_absolute_time(); // the next one waits a full interval again
    m_underrunBlocks.store(m_underrunBlocks.load(std::memory_order_relaxed) - 1, std::memory_order_relaxed);
}

OSStatus IOSAudioAPI::RenderCallback(
    void* inRefCon,
    AudioUnitRenderActionFlags* ioActionFlags,
    const AudioTimeStamp* inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList* ioData)
{
    auto* self = reinterpret_cast<IOSAudioAPI*>(inRefCon);
    if (!self || !ioData)
        return noErr;

    if (ioData->mNumberBuffers == 0)
        return noErr;

    for (UInt32 i = 0; i < ioData->mNumberBuffers; ++i)
        std::memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);

    if (!self->m_isPlaying)
        return noErr;

    auto& outputBuffer = ioData->mBuffers[0];
    const size_t bytesPerFrame = (size_t)self->m_channels * (self->m_bitsPerSample / 8);
    const auto bytesNeeded = std::min<size_t>((size_t)inNumberFrames * bytesPerFrame, outputBuffer.mDataByteSize);
    self->m_callbackFrames.store(inNumberFrames, std::memory_order_relaxed);
    const size_t target = self->TargetQueuedBytes();
    const size_t queued = self->m_buffer.size();

    // Underrun handling. Playing whatever scraps have arrived, padded with silence, turns one late
    // block into a run of tiny gaps (crackle) until the queue happens to build up again. Instead the
    // output stays silent until a full target's worth is queued, then plays on from there.
    if (self->m_priming)
    {
        if (queued < target)
        {
#if MUFFIN_AUDIT_HOOKS
            cemu_audit_audio_note_render(self, static_cast<const int16_t*>(outputBuffer.mData), 0,
                                         (uint32_t)bytesNeeded, (uint32_t)self->m_channels, (uint32_t)self->m_bitsPerSample);
#endif
            return noErr; // already zeroed above
        }
        self->m_priming = false;
        self->NoteRefilled();
    }

    // Latency cap. After a hitch (a shader compile, say) the emulator catches up by producing audio
    // faster than real time, and everything it produces lands on top of the queue. Nothing ever
    // drains that surplus, so the sound would stay that far behind the picture for the rest of the
    // session. Past one callback plus kTrimSlackBlocks of surplus, the oldest audio is dropped back
    // down to the target; this only follows a stall, which was already audible.
    constexpr size_t kTrimSlackBlocks = 6; // 72 ms at 48 kHz
    const size_t highWater = target + (size_t)inNumberFrames * bytesPerFrame + kTrimSlackBlocks * self->m_bytesPerBlock;
    if (queued > highWater)
        self->m_buffer.skip(queued - target);

    const auto copied = self->m_buffer.read(static_cast<std::uint8_t*>(outputBuffer.mData), bytesNeeded);
    if (copied < bytesNeeded)
    {
        std::memset(static_cast<std::uint8_t*>(outputBuffer.mData) + copied, 0, bytesNeeded - copied);
        self->m_priming = true;
        self->m_lastUnderrunHostTime = mach_absolute_time();
    }
    else if (self->m_underrunBlocks.load(std::memory_order_relaxed) != 0)
        self->DecayUnderrunBlocks();
    // TV / GamePad volume. iOS used to ignore it and always played at full level, so 50 (the default) keeps
    // exactly that level; 0 is silent and 100 doubles it, clipped. The desktop backends use volume/100.
    const sint32 volume = std::clamp<sint32>(self->m_volume, 0, 100);
    if (volume != 50 && self->m_bitsPerSample == 16 && copied >= 2)
    {
        const float gain = (float)volume / 50.0f;
        auto* samples = static_cast<int16_t*>(outputBuffer.mData);
        const size_t count = copied / 2;
        for (size_t k = 0; k < count; ++k)
        {
            const int v = (int)lrintf((float)samples[k] * gain);
            samples[k] = (int16_t)std::clamp(v, -32768, 32767);
        }
    }
#if MUFFIN_AUDIT_HOOKS
    cemu_audit_audio_note_render(self, static_cast<const int16_t*>(outputBuffer.mData), (uint32_t)copied,
                                 (uint32_t)bytesNeeded, (uint32_t)self->m_channels, (uint32_t)self->m_bitsPerSample);
#endif

    return noErr;
}

std::vector<IAudioAPI::DeviceDescriptionPtr> IOSAudioAPI::GetDevices()
{
    std::vector<DeviceDescriptionPtr> devs;
    devs.push_back(std::make_shared<IOSDeviceDescription>());
    return devs;
}

#endif
