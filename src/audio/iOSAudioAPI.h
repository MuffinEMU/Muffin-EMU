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

    AudioUnit m_audioUnit = nullptr;

    // Restarts output after an audio interruption (call, Siri, alarm): iOS stops the unit and
    // deactivates the session, and nothing else brings them back. Observer tokens, retained.
    void RestartAfterInterruption(const char* why, bool onlyIfStopped = false);
    void* m_interruptionObserver = nullptr;
    void* m_becameActiveObserver = nullptr;

    // How much audio to keep queued: the audio delay setting, but never less than one hardware
    // callback plus one block, so a callback never finds only part of what it asks for.
    size_t TargetQueuedBytes() const;

    AudioRingBuffer m_buffer;
    std::atomic_bool m_isPlaying = false;
    // Frames iOS asked for in the most recent render callback (the hardware IO buffer, in our rate).
    std::atomic<uint32> m_callbackFrames{0};
    // Render thread only. Set at start and after an underrun: output stays silent until the queue
    // has refilled to TargetQueuedBytes(), instead of playing each scrap as it arrives (crackle).
    bool m_priming = true;
};

#endif // TARGET_OS_IOS
