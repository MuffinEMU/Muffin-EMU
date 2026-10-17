//
//  iOSAudioAPI.h
//  cemuMain
//
//  Created by Stossy11 on 5/3/2026.
//

#pragma once

#include "IAudioAPI.h"
#include "AudioRingBuffer.h"
#include "iOSDeviceDescription.h"
#include <AudioUnit/AudioUnit.h>
#include <TargetConditionals.h>
#include <atomic>
#include <vector>

#if defined(__APPLE__) && TARGET_OS_IOS

class IOSAudioAPI : public IAudioAPI
{
public:
    IOSAudioAPI(uint32 samplerate,
                uint32 channels,
                uint32 samples_per_block,
                uint32 bits_per_sample);

    virtual ~IOSAudioAPI();

    virtual AudioAPI GetType() const override { return IOSAudio; }
    virtual bool Play() override;
    virtual bool Stop() override;
    virtual bool NeedAdditionalBlocks() const override;
    virtual bool FeedBlock(sint16* data) override;

    static std::vector<IAudioAPI::DeviceDescriptionPtr> GetDevices();

private:
    static OSStatus RenderCallback(
        void* inRefCon,
        AudioUnitRenderActionFlags* ioActionFlags,
        const AudioTimeStamp* inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList* ioData);

    // The audio session and the output unit: set up at construction, and again after a media
    // services reset, which leaves every Core Audio object dead and the session settings gone.
    void ConfigureSession();
    const char* CreateAudioUnit(); // nullptr on success, otherwise what failed
    void DisposeAudioUnit();
    void RecreateAfterMediaServicesReset();

    AudioUnit m_audioUnit = nullptr; // replaced only under s_liveDevicesMutex

    // Restarts output after an audio interruption (call, Siri, alarm): iOS stops the unit and
    // deactivates the session, and nothing else brings them back. Observer tokens, retained.
    void RestartAfterInterruption(const char* why, bool onlyIfStopped = false, bool skipIfInterrupted = false);
    void NoteInterruptionBegan();
    // Between an interruption beginning and ending (or the app coming back to the foreground).
    // Main queue only, under s_liveDevicesMutex.
    bool m_interrupted = false;
    void* m_interruptionObserver = nullptr;
    void* m_becameActiveObserver = nullptr;
    void* m_routeChangeObserver = nullptr;
    void* m_mediaResetObserver = nullptr;

    // How much audio to keep queued: the audio delay setting plus any blocks added after underruns,
    // but never less than one hardware callback plus one block, so a callback never finds only
    // part of what it asks for.
    size_t TargetQueuedBytes() const;

    AudioRingBuffer m_buffer;
    std::atomic_bool m_isPlaying = false;
    // Frames iOS asked for in the most recent render callback (the hardware IO buffer, in our rate).
    std::atomic<uint32> m_callbackFrames{0};
    // Render thread only. Set at start and after an underrun: output stays silent until the queue
    // has refilled to TargetQueuedBytes(), instead of playing each scrap as it arrives (crackle).
    bool m_priming = true;

    // Underrun adaptation. A refill that follows an underrun by less than kUnderrunWindowSeconds
    // means the emulator was running and merely late, so one block is added to the target (up to
    // kMaxUnderrunBlocks); a longer gap is a pause or a long stall, which more audio in hand would
    // not have covered, and adds nothing. After kUnderrunDecaySeconds without an underrun one block
    // is taken back, so the delay settles at the lowest level the device holds. The render thread
    // writes; TargetQueuedBytes() reads from either thread.
    static constexpr uint32 kMaxUnderrunBlocks = 4; // 48 ms at 48 kHz on top of the setting
    static constexpr double kUnderrunWindowSeconds = 1.0;
    static constexpr double kUnderrunDecaySeconds = 30.0;
    void NoteRefilled();
    void DecayUnderrunBlocks();
    double SecondsSince(uint64 hostTime) const;
    std::atomic<uint32> m_underrunBlocks{0};
    uint64 m_lastUnderrunHostTime = 0; // render thread only; 0 until the first underrun
    double m_hostTicksPerSecond = 0.0; // mach_absolute_time units
    uint32 m_loggedUnderrunBlocks = 0; // FeedBlock (emulator thread) only
};

#endif // TARGET_OS_IOS
