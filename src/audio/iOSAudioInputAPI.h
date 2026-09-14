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
};

#endif // TARGET_OS_IOS
