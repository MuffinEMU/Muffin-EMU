#include <TargetConditionals.h>

#if defined(__APPLE__) && TARGET_OS_IOS

#include "iOSAudioRecorder.h"
#include "AudioRingBuffer.h"
#import <AVFoundation/AVFoundation.h>
#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace
{
	// 1 MiB of 16-bit stereo: about 5.5 seconds at 48 kHz. The writer wakes every 20 ms, so this is
	// a large margin; if it ever fills, the tap drops samples rather than ever waiting.
	constexpr size_t kRingBytes = 1u << 20;

	AudioRingBuffer* s_ring = nullptr; // allocated on first use, kept for the life of the process
	std::atomic<bool> s_active{false};
	std::atomic<uint32_t> s_rate{0};
	std::atomic<uint64_t> s_framesWritten{0};
	std::atomic<bool> s_stopRequested{false};
	std::thread s_writer;
	std::mutex s_controlMutex;
	std::string s_path;

	AVAudioFile* OpenFile(NSURL* url, uint32_t rate)
	{
		NSError* error = nil;
		NSMutableDictionary* settings = [@{
			AVFormatIDKey: @(kAudioFormatMPEG4AAC),
			AVSampleRateKey: @((double)rate),
			AVNumberOfChannelsKey: @2,
			AVEncoderBitRateKey: @256000,
			AVEncoderAudioQualityKey: @(AVAudioQualityMax),
		} mutableCopy];
		AVAudioFile* file = [[AVAudioFile alloc] initForWriting:url settings:settings
		                                           commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
		if (!file)
		{
			// Some rates do not allow 256 kbps; let the encoder pick its own best rate for the quality.
			[settings removeObjectForKey:AVEncoderBitRateKey];
			error = nil;
			file = [[AVAudioFile alloc] initForWriting:url settings:settings
			                              commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
		}
		return file;
	}

	void WriterMain(std::string path)
	{
		@autoreleasepool
		{
			NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
			AVAudioFile* file = nil;
			AVAudioPCMBuffer* pcm = nil;
			constexpr AVAudioFrameCount kChunkFrames = 4096;
			std::vector<int16_t> chunk(kChunkFrames * 2);
			bool failed = false;

			for (;;)
			{
				const bool stopping = s_stopRequested.load(std::memory_order_acquire);
				const size_t bytes = s_ring->read(reinterpret_cast<uint8_t*>(chunk.data()), chunk.size() * sizeof(int16_t));
				if (bytes == 0)
				{
					if (stopping)
						break;
					[NSThread sleepForTimeInterval:0.02];
					continue;
				}
				if (failed)
					continue; // keep draining so the tap never sees a stuck ring
				@autoreleasepool
				{
					if (!file)
					{
						// Opened on the first samples, so the file takes the rate the game really uses.
						const uint32_t rate = s_rate.load(std::memory_order_relaxed);
						file = OpenFile(url, rate ? rate : 48000);
						if (!file)
						{
							failed = true;
							continue;
						}
						pcm = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:kChunkFrames];
					}
					const AVAudioFrameCount frames = (AVAudioFrameCount)(bytes / (2 * sizeof(int16_t)));
					pcm.frameLength = frames;
					float* left = pcm.floatChannelData[0];
					float* right = pcm.floatChannelData[1];
					for (AVAudioFrameCount i = 0; i < frames; ++i)
					{
						left[i] = chunk[i * 2] * (1.0f / 32768.0f);
						right[i] = chunk[i * 2 + 1] * (1.0f / 32768.0f);
					}
					NSError* error = nil;
					if ([file writeFromBuffer:pcm error:&error])
						s_framesWritten.fetch_add(frames, std::memory_order_relaxed);
					else
						failed = true;
				}
			}
			// Releasing the file is what finishes it: the encoder writes the closing data (and, for M4A,
			// the index the file cannot be played without) when the object goes away.
			pcm = nil;
			file = nil;
		}
	}
}

namespace IOSAudioRecorder
{
	void Tap(const int16_t* interleaved, uint32_t frames, uint32_t channels, uint32_t sampleRate)
	{
		if (!s_active.load(std::memory_order_relaxed) || !interleaved || frames == 0 || channels == 0)
			return;
		s_rate.store(sampleRate, std::memory_order_relaxed);
		// Always stereo in the file. More channels than two keep the front pair; one channel is doubled.
		int16_t stereo[1024];
		uint32_t done = 0;
		while (done < frames)
		{
			const uint32_t n = std::min<uint32_t>(frames - done, 512);
			const int16_t* src = interleaved + (size_t)done * channels;
			if (channels == 2)
			{
				s_ring->write(reinterpret_cast<const uint8_t*>(src), (size_t)n * 4);
			}
			else
			{
				for (uint32_t i = 0; i < n; ++i)
				{
					stereo[i * 2] = src[i * channels];
					stereo[i * 2 + 1] = src[i * channels + (channels > 1 ? 1 : 0)];
				}
				s_ring->write(reinterpret_cast<const uint8_t*>(stereo), (size_t)n * 4);
			}
			done += n;
		}
	}

	bool IsActive()
	{
		return s_active.load(std::memory_order_relaxed);
	}

	bool Start(const char* path)
	{
		if (!path || !*path)
			return false;
		std::lock_guard lock(s_controlMutex);
		if (s_active.load())
			return false;
		if (s_writer.joinable())
			s_writer.join();
		if (!s_ring)
			s_ring = new AudioRingBuffer(kRingBytes);
		// Anything left over from a recording that ended badly.
		std::vector<uint8_t> scrap(4096);
		while (s_ring->read(scrap.data(), scrap.size()) > 0) {}
		s_framesWritten = 0;
		s_stopRequested = false;
		s_path = path;
		s_writer = std::thread(WriterMain, s_path);
		s_active.store(true, std::memory_order_release);
		return true;
	}

	void Stop()
	{
		std::lock_guard lock(s_controlMutex);
		if (!s_active.exchange(false))
			return;
		s_stopRequested.store(true, std::memory_order_release);
		if (s_writer.joinable())
			s_writer.join();
	}

	double Seconds()
	{
		const uint32_t rate = s_rate.load(std::memory_order_relaxed);
		return rate ? (double)s_framesWritten.load(std::memory_order_relaxed) / rate : 0.0;
	}
}

#endif
