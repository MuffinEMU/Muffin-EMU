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
#include <mutex>
#include <set>
#include "Cemu/Logging/CemuLogging.h"

// Devices alive right now. The notification blocks run on the main queue and the device can be
// destroyed on the audio/emulator thread, so a block checks membership under this lock first.
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
    else {
        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:&error];
    }
    [session setPreferredSampleRate:samplerate error:&error];
    [session setPreferredIOBufferDuration:(double)samples_per_block / samplerate error:&error];
    [session setActive:YES error:&error];
    
    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp || AudioComponentInstanceNew(comp, &m_audioUnit) != noErr)
        throw std::runtime_error("can't initialize iOS audio unit");
    
    auto disposeAudioUnitOnError = [this]() {
        AudioComponentInstanceDispose(m_audioUnit);
        m_audioUnit = nullptr;
    };
    
    const uint32 bytesPerSample = bits_per_sample / 8;
    
    AudioStreamBasicDescription format{};
    format.mSampleRate       = samplerate;
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = m_channels;
    format.mBitsPerChannel   = bits_per_sample;
    format.mFramesPerPacket  = 1;
    format.mBytesPerFrame    = m_channels * bytesPerSample;
    format.mBytesPerPacket   = format.mBytesPerFrame * format.mFramesPerPacket;
    
    if (AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &format, sizeof(format)) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't set iOS audio stream format");
    }
    
    AURenderCallbackStruct callback{};
    callback.inputProc       = RenderCallback;
    callback.inputProcRefCon = this;
    
    if (AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callback, sizeof(callback)) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't set iOS audio render callback");
    }
    
    if (AudioUnitInitialize(m_audioUnit) != noErr) {
        disposeAudioUnitOnError();
        throw std::runtime_error("can't initialize iOS audio unit");
    }

    {
        std::lock_guard lock(s_liveDevicesMutex);
        s_liveDevices.insert(this);
    }
    IOSAudioAPI* device = this;
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    id interruption = [center addObserverForName:AVAudioSessionInterruptionNotification object:nil
                                           queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* note) {
        NSNumber* type = note.userInfo[AVAudioSessionInterruptionTypeKey];
        if (type && type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded)
            device->RestartAfterInterruption("interruption ended");
    }];
    // Backstop: an interruption that ends while the app is in the background does not always post
    // "ended" (iOS documents this), so coming back to the foreground restarts output as well.
    id becameActive = [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                           queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
        device->RestartAfterInterruption("app became active", /*onlyIfStopped*/ true);
    }];
    m_interruptionObserver = (void*)CFBridgingRetain(interruption);
    m_becameActiveObserver = (void*)CFBridgingRetain(becameActive);
}

void IOSAudioAPI::RestartAfterInterruption(const char* why, bool onlyIfStopped)
{
    std::lock_guard lock(s_liveDevicesMutex);
    if (s_liveDevices.find(this) == s_liveDevices.end() || !m_audioUnit || !m_isPlaying)
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
    m_interruptionObserver = nullptr;
    m_becameActiveObserver = nullptr;
    if (m_audioUnit) {
        m_isPlaying = false;
        AudioOutputUnitStop(m_audioUnit);
        AudioUnitUninitialize(m_audioUnit);
        AudioComponentInstanceDispose(m_audioUnit);
        m_audioUnit = nullptr;
    }
}

bool IOSAudioAPI::Play()
{
    if (!m_audioUnit) return false;
    if (m_isPlaying) return true;
    
    OSStatus status = AudioOutputUnitStart(m_audioUnit);
    if (status != noErr) {
        return false;
    }
    
    m_isPlaying = true;
    return true;
}

bool IOSAudioAPI::Stop()
{
    if (!m_audioUnit) return false;
    if (!m_isPlaying) return true;
    
    if (AudioOutputUnitStop(m_audioUnit) != noErr)
        return false;
    
    m_isPlaying = false;
    return true;
}

bool IOSAudioAPI::NeedAdditionalBlocks() const
{
    return m_buffer.size() < (size_t)GetTargetQueuedBlocks() * m_bytesPerBlock;
}

bool IOSAudioAPI::FeedBlock(sint16* data)
{
    // "Record audio": a copy of the TV mix, taken before it is queued so playback is untouched. Only the
    // TV device; the GamePad's own stream is not part of the recording. A no-op unless a recording is on.
    if (m_bitsPerSample == 16 && IOSAudioRecorder::IsActive() && this == g_tvAudio.get())
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
    const auto bytesNeeded = std::min<size_t>((size_t)inNumberFrames * self->m_channels * (self->m_bitsPerSample / 8), outputBuffer.mDataByteSize);
    const auto copied = self->m_buffer.read(static_cast<std::uint8_t*>(outputBuffer.mData), bytesNeeded);
    if (copied < bytesNeeded)
        std::memset(static_cast<std::uint8_t*>(outputBuffer.mData) + copied, 0, bytesNeeded - copied);
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
