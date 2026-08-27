//
//  CoreAudioAPI.mm
//  iOS audio output for Cemu, on AudioUnit RemoteIO + AVAudioSession.
//
//  Why this file exists: every audio backend Cemu ships is desktop-only, so on iOS
//  IAudioAPI had no available API at all. GetDevices() returned an empty list for
//  every enum value, CreateDeviceFromConfig() therefore never matched the configured
//  device, and AXOut_init() logged "can't initialize tv audio: failed to find
//  selected device" on every boot. Titles ran silent. This is the missing backend.
//
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include "audio/CoreAudioAPI.h"

#if HAS_COREAUDIO

#include "Common/precompiled.h"

#include <algorithm>
#include <mutex>
#include <vector>

namespace
{
	// Live instances, so the AVAudioSession interruption handler can restart them.
	// Cemu makes at most three (TV, gamepad, portal), and they are created/destroyed
	// on title boot/shutdown, not per frame, so a plain mutex here costs nothing and
	// is never touched by the render callback.
	std::mutex g_instanceMutex;
	std::vector<CoreAudioAPI*> g_instances;

	id g_interruptionObserver = nil;
	id g_mediaResetObserver = nil;
	bool g_sessionConfigured = false;

	// Preferred hardware buffer. 10 ms is the usual game-audio compromise: long
	// enough that the CPU is woken ~100x/sec instead of ~350x/sec at the 2.9 ms
	// minimum (which matters on battery), short enough to sit comfortably inside the
	// 24 ms that Cemu's default audio delay of 2 blocks keeps queued.
	constexpr double kPreferredIOBufferDuration = 0.010;

	bool ActivateAudioSession()
	{
		AVAudioSession* session = [AVAudioSession sharedInstance];
		NSError* error = nil;

		// Playback: keeps audio alive when the ringer switch is on silent, which is
		// what a game is expected to do. Not mixing with others by default, so Cemu
		// gets the full output route.
		if (![session setCategory:AVAudioSessionCategoryPlayback
					   withOptions:0
							 error:&error])
		{
			cemuLog_log(LogType::Force, "CoreAudio: could not set the playback category: {}",
				error ? [[error localizedDescription] UTF8String] : "unknown error");
			return false;
		}

		error = nil;
		if (![session setPreferredSampleRate:48000.0 error:&error])
		{
			// Not fatal. The unit is configured at 48 kHz regardless and iOS resamples.
			cemuLog_log(LogType::Force, "CoreAudio: could not request a 48 kHz hardware rate ({}), continuing - "
				"the OS will resample.",
				error ? [[error localizedDescription] UTF8String] : "unknown error");
		}

		error = nil;
		if (![session setPreferredIOBufferDuration:kPreferredIOBufferDuration error:&error])
		{
			cemuLog_log(LogType::Force, "CoreAudio: could not request a {:.0f} ms IO buffer ({}), continuing with "
				"the system default.",
				kPreferredIOBufferDuration * 1000.0,
				error ? [[error localizedDescription] UTF8String] : "unknown error");
		}

		error = nil;
		if (![session setActive:YES error:&error])
		{
			cemuLog_log(LogType::Force, "CoreAudio: could not activate the audio session: {}",
				error ? [[error localizedDescription] UTF8String] : "unknown error");
			return false;
		}

		return true;
	}

	void NotifyInterruptionBegan()
	{
		std::lock_guard<std::mutex> lock(g_instanceMutex);
		for (CoreAudioAPI* instance : g_instances)
			instance->OnInterruptionBegan();
	}

	void NotifyInterruptionEnded()
	{
		std::lock_guard<std::mutex> lock(g_instanceMutex);
		for (CoreAudioAPI* instance : g_instances)
			instance->OnInterruptionEnded();
	}
}

bool CoreAudioAPI::InitializeStatic()
{
	if (g_sessionConfigured)
		return true;

	if (!ActivateAudioSession())
		return false;

	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];

	// An incoming call, a Siri invocation or another app taking the route stops our
	// unit. Without this the audio never comes back for the rest of the session,
	// which reads on device as "audio randomly died".
	g_interruptionObserver =
		[center addObserverForName:AVAudioSessionInterruptionNotification
							object:[AVAudioSession sharedInstance]
							 queue:nil
						usingBlock:^(NSNotification* note) {
			NSNumber* typeValue = note.userInfo[AVAudioSessionInterruptionTypeKey];
			if (!typeValue)
				return;

			const AVAudioSessionInterruptionType type =
				(AVAudioSessionInterruptionType)[typeValue unsignedIntegerValue];

			if (type == AVAudioSessionInterruptionTypeBegan)
			{
				// The system has already stopped our units by this point. Record that
				// so the resume path knows which ones to bring back.
				NotifyInterruptionBegan();
				cemuLog_log(LogType::Force, "CoreAudio: audio session interrupted - output paused.");
				return;
			}

			NSNumber* optionsValue = note.userInfo[AVAudioSessionInterruptionOptionKey];
			const bool shouldResume =
				optionsValue &&
				([optionsValue unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) != 0;

			if (!shouldResume)
			{
				cemuLog_log(LogType::Force, "CoreAudio: interruption ended but the system did not ask us to "
					"resume - leaving output stopped.");
				return;
			}

			if (!ActivateAudioSession())
			{
				cemuLog_log(LogType::Force, "CoreAudio: interruption ended but the session would not reactivate.");
				return;
			}

			NotifyInterruptionEnded();
			cemuLog_log(LogType::Force, "CoreAudio: interruption ended - output resumed.");
		}];

	// Media services resetting invalidates every AudioUnit we hold. Recovering means
	// tearing down and rebuilding the units, which only AXOut can do. Say so plainly
	// rather than silently producing silence.
	g_mediaResetObserver =
		[center addObserverForName:AVAudioSessionMediaServicesWereResetNotification
							object:[AVAudioSession sharedInstance]
							 queue:nil
						usingBlock:^(NSNotification* note) {
			(void)note;
			cemuLog_log(LogType::Force, "CoreAudio: the system reset media services. Every audio unit this "
				"process holds is now invalid and audio will stay silent until the title is restarted.");
		}];

	g_sessionConfigured = true;
	cemuLog_log(LogType::Force, "CoreAudio: audio session active (hardware rate {:.0f} Hz, IO buffer {:.1f} ms).",
		[[AVAudioSession sharedInstance] sampleRate],
		[[AVAudioSession sharedInstance] IOBufferDuration] * 1000.0);
	return true;
}

void CoreAudioAPI::Destroy()
{
	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
	if (g_interruptionObserver)
	{
		[center removeObserver:g_interruptionObserver];
		g_interruptionObserver = nil;
	}
	if (g_mediaResetObserver)
	{
		[center removeObserver:g_mediaResetObserver];
		g_mediaResetObserver = nil;
	}

	if (g_sessionConfigured)
	{
		NSError* error = nil;
		[[AVAudioSession sharedInstance] setActive:NO
									   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
											 error:&error];
		g_sessionConfigured = false;
	}
}

std::vector<IAudioAPI::DeviceDescriptionPtr> CoreAudioAPI::GetDevices()
{
	// iOS does not let an app pick an output device - the system owns routing
	// (speaker, headphones, AirPods, CarPlay) and switches underneath us. Exposing a
	// route list here would be offering a choice that cannot be honoured, so there is
	// exactly one device and it means "wherever iOS is sending audio right now".
	std::vector<DeviceDescriptionPtr> result;
	result.emplace_back(std::make_shared<CoreAudioDeviceDescription>(L"default", L"Default Device"));
	return result;
}

CoreAudioAPI::CoreAudioAPI(uint32 samplerate, uint32 channels, uint32 samples_per_block, uint32 bits_per_sample)
	: IAudioAPI(samplerate, channels, samples_per_block, bits_per_sample)
{
	if (bits_per_sample != 16)
		throw std::runtime_error(fmt::format("CoreAudio backend only handles 16-bit samples, was asked for {}", bits_per_sample));

	m_ringCapacity = (size_t)m_bytesPerBlock * kBlockCount;
	m_ring.resize(m_ringCapacity);

	AudioComponentDescription desc = {};
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;

	AudioComponent component = AudioComponentFindNext(nullptr, &desc);
	if (!component)
		throw std::runtime_error("CoreAudio: no RemoteIO audio component on this device");

	OSStatus status = AudioComponentInstanceNew(component, &m_audioUnit);
	if (status != noErr || !m_audioUnit)
		throw std::runtime_error(fmt::format("CoreAudio: could not create the output unit (OSStatus {})", (sint32)status));

	AudioStreamBasicDescription format = {};
	format.mSampleRate = (Float64)samplerate;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mFramesPerPacket = 1;
	format.mChannelsPerFrame = channels;
	format.mBitsPerChannel = bits_per_sample;
	format.mBytesPerFrame = channels * (bits_per_sample / 8);
	format.mBytesPerPacket = format.mBytesPerFrame;

	// Bus 0 is the hardware output; its *input* scope is what we feed.
	status = AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat,
								  kAudioUnitScope_Input, 0, &format, sizeof(format));
	if (status != noErr)
	{
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
		throw std::runtime_error(fmt::format("CoreAudio: the output unit rejected {} channel 16-bit PCM at {} Hz (OSStatus {})",
			channels, samplerate, (sint32)status));
	}

	AURenderCallbackStruct callback = {};
	callback.inputProc = &CoreAudioAPI::RenderCallback;
	callback.inputProcRefCon = this;
	status = AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_SetRenderCallback,
								  kAudioUnitScope_Input, 0, &callback, sizeof(callback));
	if (status != noErr)
	{
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
		throw std::runtime_error(fmt::format("CoreAudio: could not install the render callback (OSStatus {})", (sint32)status));
	}

	status = AudioUnitInitialize(m_audioUnit);
	if (status != noErr)
	{
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
		throw std::runtime_error(fmt::format("CoreAudio: could not initialize the output unit (OSStatus {})", (sint32)status));
	}

	{
		std::lock_guard<std::mutex> lock(g_instanceMutex);
		g_instances.push_back(this);
	}

	cemuLog_log(LogType::Force, "CoreAudio: output unit ready ({} ch, {} Hz, {} byte blocks, {} ms of queue capacity).",
		channels, samplerate, m_bytesPerBlock,
		(m_ringCapacity * 1000) / (size_t)(samplerate * channels * (bits_per_sample / 8)));
}

CoreAudioAPI::~CoreAudioAPI()
{
	{
		std::lock_guard<std::mutex> lock(g_instanceMutex);
		g_instances.erase(std::remove(g_instances.begin(), g_instances.end(), this), g_instances.end());
	}

	if (m_audioUnit)
	{
		Stop();
		// Uninitialize before dispose so the render callback is guaranteed to have
		// stopped before `this` goes away.
		AudioUnitUninitialize(m_audioUnit);
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
	}

	const uint32 underruns = m_underrunCount.load(std::memory_order_relaxed);
	if (underruns > 0)
	{
		cemuLog_log(LogType::Force, "CoreAudio: output unit closed after {} underrun(s) - if that number is large, "
			"the emulator was not producing audio fast enough to keep up with real time.", underruns);
	}
}

size_t CoreAudioAPI::QueuedBytes() const
{
	const size_t writePos = m_writePos.load(std::memory_order_acquire);
	const size_t readPos = m_readPos.load(std::memory_order_acquire);
	return writePos - readPos;
}

bool CoreAudioAPI::NeedAdditionalBlocks() const
{
	return QueuedBytes() < (size_t)GetAudioDelay() * m_bytesPerBlock;
}

bool CoreAudioAPI::FeedBlock(sint16* data)
{
	const size_t writePos = m_writePos.load(std::memory_order_relaxed);
	const size_t readPos = m_readPos.load(std::memory_order_acquire);
	const size_t queued = writePos - readPos;

	if (queued + m_bytesPerBlock > m_ringCapacity)
	{
		// Same policy as the other backends: drop rather than block the AX thread.
		cemuLog_logDebug(LogType::Force, "CoreAudio: dropped a block, the output queue is full");
		return false;
	}

	const uint8* src = (const uint8*)data;
	const size_t offset = writePos % m_ringCapacity;
	const size_t firstChunk = std::min((size_t)m_bytesPerBlock, m_ringCapacity - offset);
	memcpy(m_ring.data() + offset, src, firstChunk);
	if (firstChunk < m_bytesPerBlock)
		memcpy(m_ring.data(), src + firstChunk, m_bytesPerBlock - firstChunk);

	// Release: the copy above must be visible before the render callback can see the
	// new write position and start reading those bytes.
	m_writePos.store(writePos + m_bytesPerBlock, std::memory_order_release);
	return true;
}

void CoreAudioAPI::ReadFromRing(uint8* dst, size_t bytes)
{
	const size_t readPos = m_readPos.load(std::memory_order_relaxed);
	const size_t writePos = m_writePos.load(std::memory_order_acquire);
	const size_t available = writePos - readPos;
	const size_t copied = std::min(available, bytes);

	if (copied > 0)
	{
		const size_t offset = readPos % m_ringCapacity;
		const size_t firstChunk = std::min(copied, m_ringCapacity - offset);
		memcpy(dst, m_ring.data() + offset, firstChunk);
		if (firstChunk < copied)
			memcpy(dst + firstChunk, m_ring.data(), copied - firstChunk);

		m_readPos.store(readPos + copied, std::memory_order_release);
	}

	if (copied < bytes)
	{
		memset(dst + copied, 0, bytes - copied);
		m_underrunCount.fetch_add(1, std::memory_order_relaxed);
	}

	const sint32 volume = m_volumeScale.load(std::memory_order_relaxed);
	if (volume != 100 && copied > 0)
	{
		sint16* samples = (sint16*)dst;
		const size_t sampleCount = copied / sizeof(sint16);
		for (size_t i = 0; i < sampleCount; ++i)
			samples[i] = (sint16)(((sint32)samples[i] * volume) / 100);
	}
}

OSStatus CoreAudioAPI::RenderCallback(void* inRefCon,
									  AudioUnitRenderActionFlags* ioActionFlags,
									  const AudioTimeStamp* inTimeStamp,
									  UInt32 inBusNumber,
									  UInt32 inNumberFrames,
									  AudioBufferList* ioData)
{
	(void)inTimeStamp;
	(void)inBusNumber;
	(void)inNumberFrames;

	CoreAudioAPI* thisptr = (CoreAudioAPI*)inRefCon;

	// This runs on a real-time thread: no allocation, no locks, no logging.
	for (UInt32 i = 0; i < ioData->mNumberBuffers; ++i)
	{
		AudioBuffer& buffer = ioData->mBuffers[i];
		thisptr->ReadFromRing((uint8*)buffer.mData, (size_t)buffer.mDataByteSize);
	}

	(void)ioActionFlags;
	return noErr;
}

bool CoreAudioAPI::Play()
{
	if (!m_audioUnit)
		return false;
	if (m_isPlaying)
		return true;

	const OSStatus status = AudioOutputUnitStart(m_audioUnit);
	if (status != noErr)
	{
		cemuLog_log(LogType::Force, "CoreAudio: could not start output (OSStatus {})", (sint32)status);
		return false;
	}

	m_isPlaying = true;
	m_playing = true;
	return true;
}

bool CoreAudioAPI::Stop()
{
	if (!m_audioUnit)
		return false;
	if (!m_isPlaying)
		return true;

	const OSStatus status = AudioOutputUnitStop(m_audioUnit);
	if (status != noErr)
	{
		cemuLog_log(LogType::Force, "CoreAudio: could not stop output (OSStatus {})", (sint32)status);
		return false;
	}

	m_isPlaying = false;
	m_playing = false;
	return true;
}

void CoreAudioAPI::OnInterruptionBegan()
{
	// Not a Stop() call: the unit is already stopped by the system, and asking
	// CoreAudio to stop an interrupted unit just returns an error. Only the local
	// bookkeeping needs correcting.
	m_resumeAfterInterruption = m_isPlaying;
	m_isPlaying = false;
	m_playing = false;
}

void CoreAudioAPI::OnInterruptionEnded()
{
	if (!m_resumeAfterInterruption)
		return;
	m_resumeAfterInterruption = false;
	Play();
}

void CoreAudioAPI::SetVolume(sint32 volume)
{
	IAudioAPI::SetVolume(volume);
	m_volumeScale.store(std::clamp<sint32>(volume, 0, 100), std::memory_order_relaxed);
}

#endif // HAS_COREAUDIO
