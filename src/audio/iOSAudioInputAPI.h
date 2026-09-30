//
//  iOSAudioInputAPI.h
//  cemuMain
//
//  Created by Codex on 7/15/2026.
//

#pragma once

#include "IAudioInputAPI.h"
#include "AudioRingBuffer.h"
#include <AudioUnit/AudioUnit.h>
#include <TargetConditionals.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

#if defined(__APPLE__) && TARGET_OS_IOS

class IOSAudioInputAPI : public IAudioInputAPI
{
public:
	class IOSAudioInputDeviceDescription final : public DeviceDescription
	{
	public:
		IOSAudioInputDeviceDescription()
			: DeviceDescription(L"iOS Default Microphone") {}

		std::wstring GetIdentifier() const override { return L"default"; }
	};

	IOSAudioInputAPI(uint32 samplerate,
	                 uint32 channels,
	                 uint32 samples_per_block,
	                 uint32 bits_per_sample);
	~IOSAudioInputAPI();

	AudioInputAPI GetType() const override { return IOSAudio; }

	bool ConsumeBlock(sint16* data) override;
	bool Play() override;
	bool Stop() override;
	bool IsPlaying() const override { return m_isPlaying; }

	static std::vector<DeviceDescriptionPtr> GetDevices();

private:
	// Shared with the notification blocks so that a late notification can never touch a
	// destroyed object: the destructor nulls `self` under the mutex.
	struct NotificationControl
	{
		std::mutex mutex;
		IOSAudioInputAPI* self = nullptr;
	};

	static void ConfigureSession(uint32 samplerate, uint32 samplesPerBlock);
	void HandleInterruption(bool began);
	void HandleRouteChange();

	static OSStatus InputCallback(void* inRefCon,
	                              AudioUnitRenderActionFlags* ioActionFlags,
	                              const AudioTimeStamp* inTimeStamp,
	                              UInt32 inBusNumber,
	                              UInt32 inNumberFrames,
	                              AudioBufferList* ioData);

	AudioUnit m_audioUnit = nullptr;

    AudioRingBuffer m_buffer;
	std::vector<uint8> m_captureBuffer;
	std::atomic_bool m_isPlaying = false;
	// What the game asked for (Play/Stop), as opposed to m_isPlaying, which is what the audio
	// unit is actually doing. They differ across interruptions and route changes.
	std::atomic_bool m_wantPlaying = false;
	std::atomic_bool m_interrupted = false;
	// Set by anything that makes already-captured audio stale (start, interruption, route
	// change); the consumer (ConsumeBlock) drains the ring buffer, keeping it single-consumer.
	std::atomic_bool m_flushRequested = false;

	std::shared_ptr<NotificationControl> m_notificationControl;
	void* m_interruptionObserver = nullptr; // retained id<NSObject>
	void* m_routeObserver = nullptr;        // retained id<NSObject>
};

#endif // TARGET_OS_IOS
