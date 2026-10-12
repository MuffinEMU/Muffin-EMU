// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  IOSScreenRecorder.h
//  "Record screen" (HOME menu): saves the picture the game is showing, at 1080p or the game's own
//  render resolution if that is higher, with the game's sound, to an MP4. See IOSScreenRecorder.mm for how.
//
#pragma once

#include <TargetConditionals.h>

#if defined(__APPLE__) && TARGET_OS_IOS

#include <atomic>
#include <cstdint>

namespace IOSScreenRecorder
{
	// True from Start() until Stop(). The Metal present path reads this once per frame and does nothing else
	// while it is false.
	extern std::atomic<bool> g_active;

	// Starts a recording to `path` (an .mp4 file; the folder must exist). False when one is already on.
	// The file itself is created when the first frame arrives, because the picture's size is only known then.
	bool Start(const char* path);
	// Stops, waits for the frames still on the GPU, and finishes the file. Blocks, so call it off the main
	// thread. True when a playable file with video was written; the file is removed otherwise.
	bool Stop();
	double Seconds();
	// The writer hit an error (storage full, for one). The caller should Stop().
	bool Failed();
	// Frames skipped because the encoder could not keep up.
	uint32_t Dropped();

	// GPU thread, once per presented output. On true, `outTexture` is a BGRA render target of the recording's
	// size (outWidth x outHeight) to draw the picture into, and `outToken` must be given back to EndFrame
	// when the GPU has finished with it (or AbortFrame if the draw was never encoded).
	bool BeginFrame(void* mtlDevice, bool padView, uint32_t sourceWidth, uint32_t sourceHeight, bool srgb,
	                void** outTexture, void** outToken, uint32_t* outWidth, uint32_t* outHeight);
	void EndFrame(void* token);
	void AbortFrame(void* token);
}

#endif
