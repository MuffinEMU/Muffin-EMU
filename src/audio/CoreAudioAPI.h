#pragma once

#include "IAudioAPI.h"

#if HAS_COREAUDIO

// AudioToolbox is a C API, so this header stays includable from plain C++ translation
// units (IAudioAPI.cpp is one). Everything Objective-C -- AVAudioSession, the
// interruption notification observer -- lives in CoreAudioAPI.mm and never leaks out.
#include <AudioToolbox/AudioToolbox.h>

#include <atomic>
#include <memory>
#include <vector>

// iOS output backend, built on an AudioUnit RemoteIO instance.
//
// Cemu's other backends (cubeb, XAudio2, DirectSound) are all unavailable on iOS, so
// before this existed IAudioAPI::GetDevices() returned nothing for every API, no
// DeviceDescription ever matched the configured device, and AXOut_init() died on
// "failed to find selected device" -- which is exactly what the device logs showed.
//
// Two deliberate differences from CubebAPI:
//
//   1. The block queue is a lock-free single-producer/single-consumer ring, not a
//      std::vector behind a shared_mutex. The consumer here is a CoreAudio render
//      callback running on a real-time thread; blocking it on a mutex held by the AX
//      thread is a priority inversion, and on iOS that is audible as clicks rather
//      than theoretical. Producer is AXOut's thread (FeedBlock/NeedAdditionalBlocks),
//      consumer is the render callback, so SPSC is sufficient and no lock is needed.
//   2. Volume is applied in software while copying. RemoteIO has no output volume
//      parameter on iOS (kHALOutputParam_Volume is macOS-only), and inserting a mixer
//      unit just to scale samples would cost an extra format conversion per buffer
//      for no benefit.
class CoreAudioAPI : public IAudioAPI
{
public:
	class CoreAudioDeviceDescription : public DeviceDescription
	{
	public:
		CoreAudioDeviceDescription(std::wstring identifier, const std::wstring& name)
			: DeviceDescription(name), m_identifier(std::move(identifier)) { }

		std::wstring GetIdentifier() const override { return m_identifier; }

	private:
		std::wstring m_identifier;
	};

	using CoreAudioDeviceDescriptionPtr = std::shared_ptr<CoreAudioDeviceDescription>;

	CoreAudioAPI(uint32 samplerate, uint32 channels, uint32 samples_per_block, uint32 bits_per_sample);
	~CoreAudioAPI() override;

	AudioAPI GetType() const override { return CoreAudio; }
	bool NeedAdditionalBlocks() const override;
	bool FeedBlock(sint16* data) override;
	bool Play() override;
	bool Stop() override;
	void SetVolume(sint32 volume) override;

	static std::vector<DeviceDescriptionPtr> GetDevices();

	static bool InitializeStatic();
	static void Destroy();

	// Called by the AVAudioSession interruption handler for every live instance.
	// The system stops the unit underneath us without going through Stop(), so
	// m_isPlaying has to be corrected by hand - otherwise Play() sees "already
	// playing" on resume and returns success without ever restarting anything,
	// which is silent audio that reports itself as working.
	void OnInterruptionBegan();
	void OnInterruptionEnded();

private:
	static OSStatus RenderCallback(void* inRefCon,
								   AudioUnitRenderActionFlags* ioActionFlags,
								   const AudioTimeStamp* inTimeStamp,
								   UInt32 inBusNumber,
								   UInt32 inNumberFrames,
								   AudioBufferList* ioData);

	// Called from the render callback. Fills dst with queued audio, padding whatever
	// it cannot satisfy with silence.
	void ReadFromRing(uint8* dst, size_t bytes);

	size_t QueuedBytes() const;

	AudioComponentInstance m_audioUnit = nullptr;
	bool m_isPlaying = false;
	// Only instances that were actually playing when the interruption arrived get
	// restarted; one that was deliberately stopped must stay stopped.
	bool m_resumeAfterInterruption = false;

	std::vector<uint8> m_ring;
	size_t m_ringCapacity = 0;
	// Monotonically increasing byte counters; the difference is the queued size, and
	// the modulo is the index. Producer only ever advances m_writePos, consumer only
	// ever advances m_readPos, which is what makes the lock unnecessary.
	std::atomic<size_t> m_readPos{0};
	std::atomic<size_t> m_writePos{0};

	// Read by the render callback, written by SetVolume from another thread.
	std::atomic<sint32> m_volumeScale{100};

	// Purely diagnostic: counts render callbacks that ran dry, so an underrun problem
	// is visible in the log instead of being guessed at from "it sounds crackly".
	std::atomic<uint32> m_underrunCount{0};
	std::atomic<uint32> m_underrunLogged{0};
};

#endif // HAS_COREAUDIO
