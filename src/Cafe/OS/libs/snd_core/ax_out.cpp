#include "Cafe/OS/libs/snd_core/ax.h"
#include "Cafe/OS/libs/snd_core/ax_internal.h"
#include "Cafe/HW/MMU/MMU.h"
#include "audio/IAudioAPI.h"
//#include "ax.h"
#include "config/CemuConfig.h"

namespace snd_core
{
	uint32 numProcessedFrames = 0;

	void resetNumProcessedFrames()
	{
		numProcessedFrames = 0;
	}

	uint32 getNumProcessedFrames()
	{
		return numProcessedFrames;
	}

	sint32 __AXMode[AX_DEV_COUNT]; // audio mode (AX_MODE_*) per device


	bool AVMGetTVAudioMode(uint32be* tvAudioMode)
	{
		// 0 -> mono
		// 1,2 -> stereo
		// 3 -> surround
		// 4 -> unknown mode
		switch (GetConfig().tv_channels)
		{
		case kMono:
			*tvAudioMode = 0;
			break;
		case kSurround:
#if BOOST_OS_IOS || BOOST_PLAT_ANDROID
			// iOS output is stereo: the audio session never asks the route for more than two channels,
			// so a six-channel mix (centre dialogue included) has no proper way down to the speakers.
			// Let the game make its own stereo mix instead, as it does for a stereo TV.
			*tvAudioMode = 2;
#else
			*tvAudioMode = 3;
#endif
			break;
		default:
			*tvAudioMode = 2;
			break;
		}

		return true;
	}

	bool AVMGetDRCSystemAudioMode(uint32be* drcAudioMode)
	{
		*drcAudioMode = 1; // apparently the default is Stereo(?), MH3U exits if AXGetDeviceMode doesn't return 0 (DRCSystemAudioMode must return 1 to set DRC mode to 0)
		return true;
	}

	sint32 __AXOutTVOutputChannelCount;
	sint32 __AXOutDRCOutputChannelCount;

	void __AXSetTVMode(sint32 mode)
	{
		cemu_assert(mode == AX_MODE_STEREO || mode == AX_MODE_6CH || mode == AX_MODE_MONO);
		__AXMode[AX_DEV_TV] = mode;
	}

	void __AXSetDeviceMode(sint32 device, sint32 mode)
	{
		if (device == AX_DEV_TV)
			__AXMode[AX_DEV_TV] = mode;
		else if (device == AX_DEV_DRC)
			__AXMode[AX_DEV_DRC] = mode;
		else if (device == AX_DEV_RMT)
			__AXMode[AX_DEV_RMT] = mode;
		else
		{
			cemu_assert_debug(false);
		}
	}

	sint32 AXGetDeviceMode(sint32 device)
	{
		if (device == AX_DEV_TV || device == AX_DEV_DRC || device == AX_DEV_RMT)
			return __AXMode[device];
		cemu_assert_debug(false);
		return 0;
	}

	void _AXOutInitDeviceModes()
	{
		// TV mode
		uint32be tvAudioMode;
		AVMGetTVAudioMode(&tvAudioMode);
		if (tvAudioMode == 0)
		{
			// mono
			__AXSetTVMode(AX_MODE_MONO);
			__AXOutTVOutputChannelCount = 1;
		}
		else if (tvAudioMode == 1 || tvAudioMode == 2)
		{
			// stereo
			__AXSetTVMode(AX_MODE_STEREO);
			__AXOutTVOutputChannelCount = 2;
		}
		else if (tvAudioMode == 3)
		{
			// surround (6ch)
			__AXSetTVMode(AX_MODE_6CH);
			__AXOutTVOutputChannelCount = 6;
		}
		else
		{
			assert_dbg();
		}
		// DRC mode
		uint32be drcAudioMode;
		AVMGetDRCSystemAudioMode(&drcAudioMode);
		if (drcAudioMode == 0)
		{
			// mono
			__AXSetDeviceMode(1, AX_MODE_MONO);
			__AXOutDRCOutputChannelCount = 1;
		}
		else if (drcAudioMode == 2)
		{
			// surround
			__AXSetDeviceMode(1, AX_MODE_SURROUND);
			__AXOutDRCOutputChannelCount = 2; // output channel count still 2 for DRC 'surround'
		}
		else if (drcAudioMode == 1)
		{
			// stereo
			__AXSetDeviceMode(1, AX_MODE_STEREO);
			__AXOutDRCOutputChannelCount = 2;
		}
		else
		{
			assert_dbg();
		}
	}

	void AXOut_Init()
	{
		_AXOutInitDeviceModes();
	}

	extern SysAllocator<sint32, AX_SAMPLES_MAX * AX_TV_CHANNEL_COUNT> __AXTVBuffer48;
	extern SysAllocator<sint32, AX_SAMPLES_MAX* AX_DRC_CHANNEL_COUNT * 2> __AXDRCBuffer48;

	sint16 __buf_AXTVDMABuffers_0[AX_SAMPLES_MAX * AX_TV_CHANNEL_COUNT];
	sint16 __buf_AXTVDMABuffers_1[AX_SAMPLES_MAX * AX_TV_CHANNEL_COUNT];
	sint16 __buf_AXTVDMABuffers_2[AX_SAMPLES_MAX * AX_TV_CHANNEL_COUNT];
	sint16* __AXTVDMABuffers[3] = {__buf_AXTVDMABuffers_0, __buf_AXTVDMABuffers_1, __buf_AXTVDMABuffers_2};

	#define AX_FRAMES_PER_GROUP		(4)

	sint16 tempTVChannelData[AX_SAMPLES_MAX * AX_TV_CHANNEL_COUNT * AX_FRAMES_PER_GROUP] = {};
	sint32 tempAudioBlockCounter = 0;


	sint16 __buf_AXDRCDMABuffers_0[AX_SAMPLES_MAX * 6];
	sint16 __buf_AXDRCDMABuffers_1[AX_SAMPLES_MAX * 6];
	sint16 __buf_AXDRCDMABuffers_2[AX_SAMPLES_MAX * 6];
	sint16* __AXDRCDMABuffers[3] = { __buf_AXDRCDMABuffers_0, __buf_AXDRCDMABuffers_1, __buf_AXDRCDMABuffers_2 };

	sint16 tempDRCChannelData[AX_SAMPLES_MAX * 6 * AX_FRAMES_PER_GROUP] = {};
	sint32 tempDRCAudioBlockCounter = 0;

	static sint16 _AXOutClampS16(sint32 v)
	{
		return (sint16)std::clamp<sint32>(v, -32768, 32767);
	}

	// Writes one AX frame (numSamples sample frames of srcChannels, big-endian) into a staging block as
	// dstChannels, in host order. The two differ when the output device was opened with another layout
	// than the one AX mixes in: the GamePad is always mixed in stereo whatever its channel setting says,
	// and a channel setting can change while a title is running. Copied as they are, the samples would
	// land in the wrong slots and play as noise.
	static void _AXOutStageFrame(sint16* dst, const sint16* srcBE, sint32 numSamples, sint32 srcChannels, sint32 dstChannels)
	{
		if (srcChannels == dstChannels)
		{
			for (sint32 i = 0; i < numSamples * srcChannels; ++i)
				dst[i] = _swapEndianS16(srcBE[i]);
			return;
		}
		for (sint32 i = 0; i < numSamples; ++i)
		{
			const sint16* in = srcBE + i * srcChannels;
			sint32 left, right;
			if (srcChannels == 1)
			{
				left = right = _swapEndianS16(in[0]);
			}
			else if (srcChannels < 6)
			{
				left = _swapEndianS16(in[0]);
				right = _swapEndianS16(in[1]);
			}
			else
			{
				// staging order is FL FR FC LFE BL BR (see AXOut_SubmitTVFrame). Centre and surrounds at -3 dB, LFE left out
				const sint32 centre = (sint32)_swapEndianS16(in[2]) * 181 / 256;
				left = (sint32)_swapEndianS16(in[0]) + centre + (sint32)_swapEndianS16(in[4]) * 181 / 256;
				right = (sint32)_swapEndianS16(in[1]) + centre + (sint32)_swapEndianS16(in[5]) * 181 / 256;
			}
			sint16* out = dst + i * dstChannels;
			if (dstChannels == 1)
			{
				out[0] = _AXOutClampS16((left + right) / 2);
				continue;
			}
			out[0] = _AXOutClampS16(left);
			out[1] = _AXOutClampS16(right);
			for (sint32 c = 2; c < dstChannels; ++c)
				out[c] = 0;
		}
	}

	// Staging blocks hold AX_FRAMES_PER_GROUP frames of up to 6 channels; anything else fed to a device is out of range.
	static sint32 _AXOutDeviceChannels(const AudioAPIPtr& device, sint32 srcChannels)
	{
		if (!device)
			return srcChannels;
		const sint32 channels = device->GetChannels();
		return (channels >= 1 && channels <= 6) ? channels : srcChannels;
	}

	void AIInitDMA(sint16* sampleData, sint32 size)
	{
		sint32 sampleCount = size / sizeof(sint16); // sample count in total (summed up for all channels)

		if (sndGeneric.initParam.frameLength != 0)
		{
			cemu_assert(false);
		}

		std::shared_lock lock(g_audioMutex);

		const sint32 srcChannels = sampleCount / AX_SAMPLES_PER_3MS_48KHZ;
		const sint32 channels = _AXOutDeviceChannels(g_tvAudio, srcChannels);
		sint16* outputChannel = tempTVChannelData + AX_SAMPLES_PER_3MS_48KHZ * tempAudioBlockCounter * channels;
		_AXOutStageFrame(outputChannel, sampleData, AX_SAMPLES_PER_3MS_48KHZ, srcChannels, channels);

		tempAudioBlockCounter++;
		if (tempAudioBlockCounter == AX_FRAMES_PER_GROUP)
		{
			if(g_tvAudio)
				g_tvAudio->FeedBlock(tempTVChannelData);

			tempAudioBlockCounter = 0;
		}
	}

	sint32 AIGetSamplesPerChannel(uint32 device)
	{
		// TV and DRC output the same number of samples
		return AX_SAMPLES_PER_3MS_48KHZ;
	}

	sint32 AIGetChannelCount(uint32 device)
	{
		if (__AXMode[device] == AX_MODE_6CH)
			return 6;
		if (__AXMode[device] == AX_MODE_STEREO)
			return 2;
		// default to mono
		return 1;
	}

	sint16* AIGetCurrentDMABuffer(uint32 device)
	{
		if (device == AX_DEV_TV)
			return __AXTVDMABuffers[0];
		else if (device == AX_DEV_DRC)
			return __AXDRCDMABuffers[0];
		cemu_assert_debug(false);
		return nullptr;
	}

	void AXOut_SubmitTVFrame(sint32 frameIndex)
	{
		sint32 numSamples = AIGetSamplesPerChannel(AX_DEV_TV);
		if (__AXMode[AX_DEV_TV] == AX_MODE_6CH)
		{
			sint32* inputChannel0 = __AXTVBuffer48.GetPtr() + numSamples * 0;
			sint32* inputChannel1 = __AXTVBuffer48.GetPtr() + numSamples * 1;
			sint32* inputChannel2 = __AXTVBuffer48.GetPtr() + numSamples * 2;
			sint32* inputChannel3 = __AXTVBuffer48.GetPtr() + numSamples * 3;
			sint32* inputChannel4 = __AXTVBuffer48.GetPtr() + numSamples * 4;
			sint32* inputChannel5 = __AXTVBuffer48.GetPtr() + numSamples * 5;
			sint16* dmaOutputBuffer = AIGetCurrentDMABuffer(AX_DEV_TV);
			for (sint32 i = 0; i < numSamples; i++)
			{
				/*
				* DirectSound surround order
				LEFT				0
				RIGHT				1
				SUR_LEFT			2
				SUR_RIGHT			3
				CH_FC				4
				CH_LFE				5
				=>
				Front Left - FL			0
				Front Right - FR		1
				Front Center - FC		2
				Low Frequency - LF		3
				Back Left - BL			4
				Back Right - BR			5
				*/
				dmaOutputBuffer[0] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel0), -32768), 32767));
				dmaOutputBuffer[1] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel1), -32768), 32767));

				dmaOutputBuffer[4] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel2), -32768), 32767));
				dmaOutputBuffer[5] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel3), -32768), 32767));

				dmaOutputBuffer[2] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel4), -32768), 32767));
				dmaOutputBuffer[3] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel5), -32768), 32767));
				dmaOutputBuffer += 6;
				// next sample
				inputChannel0++;
				inputChannel1++;
				inputChannel2++;
				inputChannel3++;
				inputChannel4++;
				inputChannel5++;
			}
			AIInitDMA(__AXTVDMABuffers[frameIndex], numSamples * 6 * sizeof(sint16)); // 6ch output
		}
		else if (__AXMode[AX_DEV_TV] == AX_MODE_STEREO)
		{
			sint32* inputChannel0 = __AXTVBuffer48.GetPtr() + numSamples * 0;
			sint32* inputChannel1 = __AXTVBuffer48.GetPtr() + numSamples * 1;
			sint16* dmaOutputBuffer = __AXTVDMABuffers[frameIndex];
			for (sint32 i = 0; i < numSamples; i++)
			{
				dmaOutputBuffer[0] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel0), -32768), 32767));
				dmaOutputBuffer[1] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel1), -32768), 32767));
				dmaOutputBuffer += 2;
				// next sample
				inputChannel0++;
				inputChannel1++;
			}
			AIInitDMA(__AXTVDMABuffers[frameIndex], numSamples * 2 * sizeof(sint16)); // 2ch output
		}
		else if (__AXMode[AX_DEV_TV] == AX_MODE_MONO)
		{
			sint32* inputChannel0 = __AXTVBuffer48.GetPtr() + numSamples * 0;
			sint16* dmaOutputBuffer = __AXTVDMABuffers[frameIndex];
			for (sint32 i = 0; i < numSamples; i++)
			{
				dmaOutputBuffer[0] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel0), -32768), 32767));
				dmaOutputBuffer++;
				// next sample
				inputChannel0++;
			}
			AIInitDMA(__AXTVDMABuffers[frameIndex], numSamples * 1 * sizeof(sint16)); // 1ch (output as stereo)
		}
		else
			assert_dbg();
	}

	void AIInitDRCDMA(sint16* sampleData, sint32 size)
	{
		sint32 sampleCount = size / sizeof(sint16); // sample count in total (summed up for all channels)

		if (sndGeneric.initParam.frameLength != 0)
		{
			cemu_assert(false);
		}

		std::shared_lock lock(g_audioMutex);

		const sint32 srcChannels = sampleCount / AX_SAMPLES_PER_3MS_48KHZ;
		const sint32 channels = _AXOutDeviceChannels(g_padAudio, srcChannels);
		sint16* outputChannel = tempDRCChannelData + AX_SAMPLES_PER_3MS_48KHZ * tempDRCAudioBlockCounter * channels;
		_AXOutStageFrame(outputChannel, sampleData, AX_SAMPLES_PER_3MS_48KHZ, srcChannels, channels);

		tempDRCAudioBlockCounter++;
		if (tempDRCAudioBlockCounter == AX_FRAMES_PER_GROUP)
		{
			if (g_padAudio)
				g_padAudio->FeedBlock(tempDRCChannelData);

			tempDRCAudioBlockCounter = 0;
		}
	}

	void AXOut_SubmitDRCFrame(sint32 frameIndex)
	{
		sint32 numSamples = AIGetSamplesPerChannel(AX_DEV_DRC);
		if (__AXMode[AX_DEV_DRC] == AX_MODE_6CH)
		{
			sint32* inputChannel0 = __AXDRCBuffer48.GetPtr() + numSamples * 0;
			sint32* inputChannel1 = __AXDRCBuffer48.GetPtr() + numSamples * 1;
			sint32* inputChannel2 = __AXDRCBuffer48.GetPtr() + numSamples * 2;
			sint32* inputChannel3 = __AXDRCBuffer48.GetPtr() + numSamples * 3;
			sint16* dmaOutputBuffer = AIGetCurrentDMABuffer(AX_DEV_DRC);
			for (sint32 i = 0; i < numSamples; i++)
			{
				dmaOutputBuffer[0] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel0), -32768), 32767));
				dmaOutputBuffer[1] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel1), -32768), 32767));

				dmaOutputBuffer[4] = 0;
				dmaOutputBuffer[5] = 0;

				dmaOutputBuffer[2] = 0;
				dmaOutputBuffer[3] = 0;
				dmaOutputBuffer += 6;
				// next sample
				inputChannel0++;
				inputChannel1++;
				inputChannel2++;
				inputChannel3++;
			}
			AIInitDRCDMA(__AXDRCDMABuffers[frameIndex], numSamples * 6 * sizeof(sint16)); // 6ch output
		}
		else if (__AXMode[AX_DEV_DRC] == AX_MODE_STEREO)
		{
			sint32* inputChannel0 = __AXDRCBuffer48.GetPtr() + numSamples * 0;
			sint32* inputChannel1 = __AXDRCBuffer48.GetPtr() + numSamples * 1;
			sint16* dmaOutputBuffer = __AXDRCDMABuffers[frameIndex];
			for (sint32 i = 0; i < numSamples; i++)
			{
				dmaOutputBuffer[0] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel0), -32768), 32767));
				dmaOutputBuffer[1] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel1), -32768), 32767));
				dmaOutputBuffer += 2;
				// next sample
				inputChannel0++;
				inputChannel1++;
			}

			AIInitDRCDMA(__AXDRCDMABuffers[frameIndex], numSamples * 2 * sizeof(sint16)); // 2ch output
		}
		else if (__AXMode[AX_DEV_DRC] == AX_MODE_MONO)
		{
			sint32* inputChannel0 = __AXDRCBuffer48.GetPtr() + numSamples * 0;
			sint16* dmaOutputBuffer = __AXDRCDMABuffers[frameIndex];
			for (sint32 i = 0; i < numSamples; i++)
			{
				// write mono input as stereo output
				dmaOutputBuffer[1] = dmaOutputBuffer[0] = _swapEndianS16((sint16)std::min(std::max(_swapEndianS32(*inputChannel0), -32768), 32767));
				dmaOutputBuffer += 2;
				// next sample
				inputChannel0++;
			}
			AIInitDRCDMA(__AXDRCDMABuffers[frameIndex], numSamples * 2 * sizeof(sint16)); // 1ch (output as stereo)
		}
		else
			assert_dbg();
	}

	/* AX output */

	uint32 numQueuedFramesSndGeneric = 0;

	void AXOut_init()
	{

		numQueuedFramesSndGeneric = 0;

		std::unique_lock lock(g_audioMutex);
		auto& config = GetConfig();

		// Output channel counts. On iOS both devices are opened as mono or stereo, to match the stereo
		// route (see AVMGetTVAudioMode). Anything the device and the AX mix disagree on is converted
		// when the frames are staged (_AXOutStageFrame).
		auto deviceChannels = [](AudioChannels setting) -> sint32 {
			const sint32 channels = CemuConfig::AudioChannelsToNChannels(setting);
#if BOOST_OS_IOS || BOOST_PLAT_ANDROID
			return std::min<sint32>(channels, 2);
#else
			return channels;
#endif
		};

		if (!config.tv_audio_enabled && g_tvAudio)
		{
			g_tvAudio->Stop();
			g_tvAudio.reset();
		}
		if (config.tv_audio_enabled && !g_tvAudio)
		{
			try
			{
				g_tvAudio = IAudioAPI::CreateDeviceFromConfig(IAudioAPI::AudioType::TV, 48000, deviceChannels(config.tv_channels), snd_core::AX_SAMPLES_PER_3MS_48KHZ * AX_FRAMES_PER_GROUP, 16);
			}
			catch (std::runtime_error& ex)
			{
				cemuLog_log(LogType::Force, "can't initialize tv audio: {}", ex.what());
			}
		}

		g_padVolume = config.pad_volume;
		if (!config.pad_audio_enabled && g_padAudio)
		{
			g_padAudio->Stop();
			g_padAudio.reset();
		}
		if (config.pad_audio_enabled && !g_padAudio)
		{
			try
			{
				g_padAudio = IAudioAPI::CreateDeviceFromConfig(IAudioAPI::AudioType::Gamepad, 48000, deviceChannels(config.pad_channels), snd_core::AX_SAMPLES_PER_3MS_48KHZ * AX_FRAMES_PER_GROUP, 16);
			}
			catch (std::runtime_error& ex)
			{
				cemuLog_log(LogType::Force, "can't initialize pad audio: {}", ex.what());
			}
		}
	}

	void AXOut_reset()
	{
		std::unique_lock lock(g_audioMutex);
		if (g_tvAudio)
		{
			g_tvAudio->Stop();
			g_tvAudio.reset();
		}
		if (g_padAudio)
		{
			g_padAudio->Stop();
			g_padAudio.reset();
		}
		if (g_portalAudio)
		{
			g_portalAudio->Stop();
			g_portalAudio.reset();
		}
		// the staging buffers fill four blocks before anything is written out. Stopped part way through, the next title
		// would start out of phase and play the samples the last one left behind
		tempAudioBlockCounter = 0;
		tempDRCAudioBlockCounter = 0;
		memset(tempTVChannelData, 0, sizeof(tempTVChannelData));
		memset(tempDRCChannelData, 0, sizeof(tempDRCChannelData));
	}

	void AXOut_updateDevicePlayState(bool isPlaying)
	{
		std::shared_lock lock(g_audioMutex);
		if (g_tvAudio)
		{
			if (isPlaying)
				g_tvAudio->Play();
			else
				g_tvAudio->Stop();
		}

		if (g_padAudio)
		{
			if (isPlaying)
				g_padAudio->Play();
			else
				g_padAudio->Stop();
		}

		if (g_portalAudio)
		{
			if (isPlaying)
				g_portalAudio->Play();
			else
				g_portalAudio->Stop();
		}
	}

	// called periodically to check for AX updates
	void AXOut_update()
	{
		constexpr static auto kTimeout = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::milliseconds(((IAudioAPI::kBlockCount * 3) / 4) * (AX_FRAMES_PER_GROUP * 3)));
		constexpr static auto kWaitDuration = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::milliseconds(3));
		constexpr static auto kWaitDurationFast = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::microseconds(2900));
		constexpr static auto kWaitDurationMinimum = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::microseconds(1700));

		// if we haven't buffered any blocks, we will wait less time than usual
		bool additional_blocks_required = false;
		{
			const std::shared_lock lock(g_audioMutex, std::try_to_lock);
			if (lock)
				additional_blocks_required = (g_tvAudio && g_tvAudio->NeedAdditionalBlocks()) || (g_padAudio && g_padAudio->NeedAdditionalBlocks());
		}

		const auto wait_duration = additional_blocks_required ? kWaitDurationFast : kWaitDuration;

		// s_ax_interval_timer increases by the wait period
		// it can lag behind by multiple periods (up to kTimeout) if there is minor stutter in the CPU thread
		// s_last_check is always set to the timestamp at the time of firing
		// it's used to enforce the minimum wait delay (we want to avoid calling AX update in quick succession because other threads may need to do work first) 

		static auto s_ax_interval_timer = now_cached() - kWaitDuration;
		static auto s_last_check = now_cached();

		const auto now = now_cached();
		const auto diff = (now - s_ax_interval_timer);

		if (diff < wait_duration)
			return;

		// handle minimum wait time (1.7MS)
		if ((now - s_last_check) < kWaitDurationMinimum)
			return;
		s_last_check = now;

		// if we're too far behind, skip forward
		if (diff >= kTimeout)
			s_ax_interval_timer = (now - wait_duration);
		else
			s_ax_interval_timer += wait_duration;


		if (snd_core::isInitialized())
		{
			if (numQueuedFramesSndGeneric == snd_core::getNumProcessedFrames())
			{
				AXOut_updateDevicePlayState(true);
				snd_core::AXIst_QueueFrame();
				numQueuedFramesSndGeneric++;
			}
		}
	}

}
