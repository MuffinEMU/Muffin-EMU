// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  IOSScreenRecorder.mm
//  "Record screen" (HOME menu). See IOSScreenRecorder.h.
//
//  Video: the Metal renderer draws the picture it is about to present a second time, with the same
//  shader, into an IOSurface-backed pixel buffer of the game's own render size (BeginFrame hands out that
//  buffer's texture), inside the command buffer it is already building. The command buffer's completion
//  handler gives the buffer to the writer queue (EndFrame). Nothing here waits on the encoder: when it is
//  behind, or the pool has no free buffer, the frame is skipped and counted.
//
//  Which screen: the main output, which shows the TV or the GamePad according to the Screen Layout, so a
//  layout change mid-recording keeps working. The second output (an external display's GamePad) is only
//  used while the main output is not being drawn. The file's size is fixed by the first frame; a later
//  frame of another size is scaled to it by the same draw.
//
//  Audio: the TV mix, copied on the audio thread into a ring of timestamped blocks (the same feed the
//  audio-only recorder taps, see audio/iOSAudioRecorder.h) and appended to an AAC track by a writer thread.
//  Blocks carry the host time they arrived at, like the frames do, so a pause leaves a gap in both.
//
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "IOSScreenRecorder.h"
#include "audio/iOSAudioRecorder.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <thread>

namespace IOSScreenRecorder
{
	std::atomic<bool> g_active{false};
}

namespace
{
	constexpr uint32_t kAudioSlots = 512;
	constexpr uint32_t kAudioSlotFrames = 1024;
	constexpr int kMaxFramesInFlight = 4;
	constexpr double kMinFrameInterval = 0.014; // about 70 per second at most
	constexpr uint32_t kMaxSide = 7680;

	struct AudioSlot
	{
		int16_t pcm[kAudioSlotFrames * 2];
		uint32_t frames;
		double host;
	};

	// Allocated on the first recording and kept for the life of the process: the audio thread may still be
	// inside the sink when it is removed.
	AudioSlot* s_slots = nullptr;
	std::atomic<uint64_t> s_slotWrite{0};
	std::atomic<uint64_t> s_slotRead{0};
	std::atomic<uint32_t> s_audioRate{48000};

	struct Session
	{
		NSString* path = nil;
		dispatch_queue_t queue = nullptr;
		AVAssetWriter* writer = nil;
		AVAssetWriterInput* videoInput = nil;
		AVAssetWriterInput* audioInput = nil;
		AVAssetWriterInputPixelBufferAdaptor* adaptor = nil;
		CVPixelBufferPoolRef pool = nullptr;
		CVMetalTextureCacheRef textureCache = nullptr;
		uint32_t width = 0;
		uint32_t height = 0;
		bool sized = false;
		double base = 0.0;
		double lastCapture = 0.0;
		uint32_t capturedSinceFlush = 0;

		std::atomic<bool> writerReady{false}; // startSession has been called; appends are allowed
		std::atomic<bool> failed{false};
		std::atomic<int> inFlight{0};
		std::atomic<uint32_t> dropped{0};
		std::atomic<uint32_t> appended{0};
		std::atomic<double> seconds{0.0};

		std::atomic<bool> audioStop{false};
		std::thread audioThread;

		~Session()
		{
			if (pool)
				CVPixelBufferPoolRelease(pool);
			if (textureCache)
				CFRelease(textureCache);
		}
	};

	struct FrameToken
	{
		std::shared_ptr<Session> session;
		CVPixelBufferRef buffer = nullptr;
		CVMetalTextureRef texture = nullptr;
		double pts = 0.0;
	};

	std::mutex s_mutex;
	std::shared_ptr<Session> s_session;
	std::atomic<double> s_lastMain{0.0};

	uint32_t EvenSide(uint32_t value)
	{
		return std::max<uint32_t>(16, std::min(value, kMaxSide) & ~1u);
	}

	// Bits per second for a picture of this size at game speed: about a tenth of a bit per pixel per frame
	// for HEVC, more for H.264, within the range an encoder is comfortable with.
	NSInteger BitRate(uint32_t width, uint32_t height, bool hevc)
	{
		const double bitsPerPixel = hevc ? 0.12 : 0.19;
		const double rate = (double)width * height * 30.0 * bitsPerPixel;
		return (NSInteger)std::min(std::max(rate, 4.0e6), 80.0e6);
	}

	void SetUpWriter(const std::shared_ptr<Session>& session)
	{
		@autoreleasepool
		{
			NSURL* url = [NSURL fileURLWithPath:session->path];
			[[NSFileManager defaultManager] removeItemAtURL:url error:nil];
			NSError* error = nil;
			AVAssetWriter* writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:&error];
			if (!writer)
			{
				session->failed = true;
				return;
			}
			NSDictionary* colour = @{
				AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
				AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
				AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
			};
			NSDictionary* (^settings)(NSString*, bool) = ^NSDictionary*(NSString* codec, bool hevc) {
				return @{
					AVVideoCodecKey: codec,
					AVVideoWidthKey: @(session->width),
					AVVideoHeightKey: @(session->height),
					AVVideoColorPropertiesKey: colour,
					AVVideoCompressionPropertiesKey: @{
						AVVideoAverageBitRateKey: @(BitRate(session->width, session->height, hevc)),
						AVVideoMaxKeyFrameIntervalKey: @120,
						AVVideoExpectedSourceFrameRateKey: @60,
						AVVideoAllowFrameReorderingKey: @NO,
					},
				};
			};
			// HEVC where this device can encode it at this size, H.264 otherwise.
			NSDictionary* video = settings(AVVideoCodecTypeHEVC, true);
			if (![writer canApplyOutputSettings:video forMediaType:AVMediaTypeVideo])
				video = settings(AVVideoCodecTypeH264, false);
			AVAssetWriterInput* videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:video];
			videoInput.expectsMediaDataInRealTime = YES;
			AVAssetWriterInputPixelBufferAdaptor* adaptor = [AVAssetWriterInputPixelBufferAdaptor
				assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoInput
				sourcePixelBufferAttributes:@{
					(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
					(id)kCVPixelBufferWidthKey: @(session->width),
					(id)kCVPixelBufferHeightKey: @(session->height),
				}];
			if (![writer canAddInput:videoInput])
			{
				session->failed = true;
				return;
			}
			[writer addInput:videoInput];

			NSDictionary* audioSettings = @{
				AVFormatIDKey: @(kAudioFormatMPEG4AAC),
				AVSampleRateKey: @((double)s_audioRate.load()),
				AVNumberOfChannelsKey: @2,
				AVEncoderBitRateKey: @192000,
			};
			AVAssetWriterInput* audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
			audioInput.expectsMediaDataInRealTime = YES;
			if ([writer canAddInput:audioInput])
				[writer addInput:audioInput];
			else
				audioInput = nil; // video only

			if (![writer startWriting])
			{
				session->failed = true;
				return;
			}
			[writer startSessionAtSourceTime:kCMTimeZero];
			session->writer = writer;
			session->videoInput = videoInput;
			session->audioInput = audioInput;
			session->adaptor = adaptor;
			session->writerReady.store(true, std::memory_order_release);
		}
	}

	void AppendAudio(const std::shared_ptr<Session>& session, const AudioSlot& slot, double& lastEnd)
	{
		const double rate = (double)s_audioRate.load(std::memory_order_relaxed);
		double pts = slot.host - session->base;
		if (pts < 0.0)
			return; // before the first picture
		// Blocks arrive back to back; keep them contiguous unless there was a real gap (the game paused).
		if (lastEnd > 0.0 && std::abs(pts - lastEnd) < 0.05)
			pts = lastEnd;
		lastEnd = pts + slot.frames / rate;

		AudioStreamBasicDescription asbd = {};
		asbd.mSampleRate = rate;
		asbd.mFormatID = kAudioFormatLinearPCM;
		asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
		asbd.mBitsPerChannel = 16;
		asbd.mChannelsPerFrame = 2;
		asbd.mFramesPerPacket = 1;
		asbd.mBytesPerFrame = 4;
		asbd.mBytesPerPacket = 4;
		CMAudioFormatDescriptionRef format = nullptr;
		if (CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, nullptr, 0, nullptr, nullptr, &format) != noErr)
			return;
		const size_t bytes = (size_t)slot.frames * 4;
		CMBlockBufferRef block = nullptr;
		CMSampleBufferRef sample = nullptr;
		if (CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, nullptr, bytes, kCFAllocatorDefault, nullptr, 0, bytes,
		                                       kCMBlockBufferAssureMemoryNowFlag, &block) == noErr
		    && CMBlockBufferReplaceDataBytes(slot.pcm, block, 0, bytes) == noErr)
		{
			CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault, block, format, slot.frames,
				CMTimeMakeWithSeconds(pts, 48000), nullptr, &sample);
		}
		if (sample)
		{
			AVAssetWriterInput* input = session->audioInput;
			// A short wait for the encoder; past that the block is dropped rather than held up.
			for (int i = 0; i < 10 && !input.isReadyForMoreMediaData; ++i)
				std::this_thread::sleep_for(std::chrono::milliseconds(5));
			if (input.isReadyForMoreMediaData && session->writer.status == AVAssetWriterStatusWriting)
				[input appendSampleBuffer:sample];
			CFRelease(sample);
		}
		if (block)
			CFRelease(block);
		CFRelease(format);
	}

	void AudioThreadMain(std::shared_ptr<Session> session)
	{
		double lastEnd = 0.0;
		for (;;)
		{
			const bool stopping = session->audioStop.load(std::memory_order_acquire);
			const uint64_t read = s_slotRead.load(std::memory_order_relaxed);
			if (read == s_slotWrite.load(std::memory_order_acquire))
			{
				if (stopping)
					break;
				std::this_thread::sleep_for(std::chrono::milliseconds(8));
				continue;
			}
			if (session->writerReady.load(std::memory_order_acquire) && session->audioInput)
			{
				@autoreleasepool { AppendAudio(session, s_slots[read % kAudioSlots], lastEnd); }
			}
			s_slotRead.store(read + 1, std::memory_order_release);
		}
	}

	// Audio thread. Copies the block into the ring with its arrival time and returns; nothing else.
	void AudioSink(const int16_t* interleaved, uint32_t frames, uint32_t channels, uint32_t sampleRate)
	{
		if (!interleaved || !frames || !channels || !s_slots)
			return;
		s_audioRate.store(sampleRate, std::memory_order_relaxed);
		const double host = CACurrentMediaTime();
		uint32_t done = 0;
		while (done < frames)
		{
			const uint64_t write = s_slotWrite.load(std::memory_order_relaxed);
			if (write - s_slotRead.load(std::memory_order_acquire) >= kAudioSlots)
				return; // the writer is far behind: drop rather than wait
			AudioSlot& slot = s_slots[write % kAudioSlots];
			const uint32_t n = std::min(frames - done, kAudioSlotFrames);
			const int16_t* src = interleaved + (size_t)done * channels;
			if (channels == 2)
				memcpy(slot.pcm, src, (size_t)n * 4);
			else
			{
				for (uint32_t i = 0; i < n; ++i)
				{
					slot.pcm[i * 2] = src[i * channels];
					slot.pcm[i * 2 + 1] = src[i * channels + (channels > 1 ? 1 : 0)];
				}
			}
			slot.frames = n;
			slot.host = host + (double)done / sampleRate;
			s_slotWrite.store(write + 1, std::memory_order_release);
			done += n;
		}
	}

	void ReleaseToken(FrameToken* token)
	{
		if (token->texture)
			CFRelease(token->texture);
		if (token->buffer)
			CVPixelBufferRelease(token->buffer);
		token->session->inFlight.fetch_sub(1, std::memory_order_relaxed);
		delete token;
	}
}

namespace IOSScreenRecorder
{
	bool Start(const char* path)
	{
		if (!path || !*path)
			return false;
		std::lock_guard lock(s_mutex);
		if (s_session)
			return false;
		if (!s_slots)
			s_slots = new AudioSlot[kAudioSlots];
		auto session = std::make_shared<Session>();
		session->path = [NSString stringWithUTF8String:path];
		session->queue = dispatch_queue_create("muffin.screenrecorder", DISPATCH_QUEUE_SERIAL);
		s_slotRead.store(0);
		s_slotWrite.store(0);
		s_lastMain.store(0.0);
		session->audioThread = std::thread(AudioThreadMain, session);
		s_session = session;
		::IOSAudioRecorder::SetSink(&AudioSink);
		g_active.store(true, std::memory_order_release);
		return true;
	}

	bool Stop()
	{
		std::shared_ptr<Session> session;
		{
			std::lock_guard lock(s_mutex);
			session = std::move(s_session);
			s_session.reset();
			g_active.store(false, std::memory_order_release);
		}
		if (!session)
			return false;
		::IOSAudioRecorder::SetSink(nullptr);
		session->audioStop.store(true, std::memory_order_release);
		if (session->audioThread.joinable())
			session->audioThread.join();
		// Frames already handed to the GPU finish into the file; give them a moment.
		for (int i = 0; i < 600 && session->inFlight.load() > 0; ++i)
			std::this_thread::sleep_for(std::chrono::milliseconds(5));

		__block bool ok = false;
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		dispatch_async(session->queue, ^{
			AVAssetWriter* writer = session->writer;
			if (!writer || writer.status != AVAssetWriterStatusWriting)
			{
				[writer cancelWriting];
				dispatch_semaphore_signal(done);
				return;
			}
			[session->videoInput markAsFinished];
			[session->audioInput markAsFinished];
			[writer finishWritingWithCompletionHandler:^{
				ok = writer.status == AVAssetWriterStatusCompleted;
				dispatch_semaphore_signal(done);
			}];
		});
		dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
		ok = ok && session->appended.load() > 0;
		if (session->dropped.load() > 0)
			NSLog(@"Screen recording skipped %u frame(s) the encoder could not take", session->dropped.load());
		if (!ok)
			[[NSFileManager defaultManager] removeItemAtPath:session->path error:nil];
		return ok;
	}

	double Seconds()
	{
		std::lock_guard lock(s_mutex);
		return s_session ? s_session->seconds.load(std::memory_order_relaxed) : 0.0;
	}

	bool Failed()
	{
		std::lock_guard lock(s_mutex);
		return s_session && s_session->failed.load();
	}

	uint32_t Dropped()
	{
		std::lock_guard lock(s_mutex);
		return s_session ? s_session->dropped.load() : 0;
	}

	bool BeginFrame(void* mtlDevice, bool padView, uint32_t sourceWidth, uint32_t sourceHeight, bool srgb,
	                void** outTexture, void** outToken, uint32_t* outWidth, uint32_t* outHeight)
	{
		const double now = CACurrentMediaTime();
		if (!padView)
			s_lastMain.store(now, std::memory_order_relaxed);
		else if (now - s_lastMain.load(std::memory_order_relaxed) < 0.5)
			return false; // the main output is being drawn; that is the one recorded

		std::shared_ptr<Session> session;
		{
			std::lock_guard lock(s_mutex);
			session = s_session;
		}
		if (!session || session->failed.load(std::memory_order_relaxed) || !sourceWidth || !sourceHeight)
			return false;
		if (session->sized && now - session->lastCapture < kMinFrameInterval)
			return false;

		if (!session->sized)
		{
			id<MTLDevice> device = (__bridge id<MTLDevice>)mtlDevice;
			session->width = EvenSide(sourceWidth);
			session->height = EvenSide(sourceHeight);
			NSDictionary* poolAttributes = @{(id)kCVPixelBufferPoolMinimumBufferCountKey: @3};
			NSDictionary* bufferAttributes = @{
				(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
				(id)kCVPixelBufferWidthKey: @(session->width),
				(id)kCVPixelBufferHeightKey: @(session->height),
				(id)kCVPixelBufferIOSurfacePropertiesKey: @{},
				(id)kCVPixelBufferMetalCompatibilityKey: @YES,
			};
			if (CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)poolAttributes,
			                            (__bridge CFDictionaryRef)bufferAttributes, &session->pool) != kCVReturnSuccess
			    || CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, device, nullptr, &session->textureCache) != kCVReturnSuccess)
			{
				session->failed = true;
				return false;
			}
			session->sized = true;
			session->base = now;
			// The writer is opened on its own queue; frames queued behind it wait their turn there.
			dispatch_async(session->queue, ^{ SetUpWriter(session); });
		}

		if (session->inFlight.load(std::memory_order_relaxed) >= kMaxFramesInFlight)
		{
			session->dropped.fetch_add(1, std::memory_order_relaxed);
			return false;
		}
		NSDictionary* aux = @{(id)kCVPixelBufferPoolAllocationThresholdKey: @6};
		CVPixelBufferRef buffer = nullptr;
		if (CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, session->pool,
		        (__bridge CFDictionaryRef)aux, &buffer) != kCVReturnSuccess || !buffer)
		{
			session->dropped.fetch_add(1, std::memory_order_relaxed);
			return false;
		}
		CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
		CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
		CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);

		NSDictionary* textureAttributes = @{(id)kCVMetalTextureUsage: @(MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead)};
		CVMetalTextureRef cvTexture = nullptr;
		const CVReturn result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, session->textureCache, buffer,
			(__bridge CFDictionaryRef)textureAttributes, srgb ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm,
			session->width, session->height, 0, &cvTexture);
		id<MTLTexture> texture = (result == kCVReturnSuccess && cvTexture) ? CVMetalTextureGetTexture(cvTexture) : nil;
		if (!texture)
		{
			if (cvTexture)
				CFRelease(cvTexture);
			CVPixelBufferRelease(buffer);
			session->dropped.fetch_add(1, std::memory_order_relaxed);
			return false;
		}
		if (++session->capturedSinceFlush >= 240)
		{
			session->capturedSinceFlush = 0;
			CVMetalTextureCacheFlush(session->textureCache, 0);
		}

		session->lastCapture = now;
		session->seconds.store(now - session->base, std::memory_order_relaxed);
		session->inFlight.fetch_add(1, std::memory_order_relaxed);
		auto* token = new FrameToken{session, buffer, cvTexture, now - session->base};
		*outTexture = (__bridge void*)texture;
		*outToken = token;
		*outWidth = session->width;
		*outHeight = session->height;
		return true;
	}

	void EndFrame(void* tokenPointer)
	{
		auto* token = static_cast<FrameToken*>(tokenPointer);
		auto session = token->session;
		dispatch_async(session->queue, ^{
			if (session->writerReady.load(std::memory_order_acquire) && !session->failed.load()
			    && session->writer.status == AVAssetWriterStatusWriting && session->videoInput.isReadyForMoreMediaData)
			{
				if ([session->adaptor appendPixelBuffer:token->buffer withPresentationTime:CMTimeMakeWithSeconds(token->pts, 60000)])
					session->appended.fetch_add(1, std::memory_order_relaxed);
				else
					session->dropped.fetch_add(1, std::memory_order_relaxed);
			}
			else
				session->dropped.fetch_add(1, std::memory_order_relaxed);
			if (session->writerReady.load() && session->writer.status == AVAssetWriterStatusFailed)
				session->failed = true;
			ReleaseToken(token);
		});
	}

	void AbortFrame(void* tokenPointer)
	{
		ReleaseToken(static_cast<FrameToken*>(tokenPointer));
	}
}
