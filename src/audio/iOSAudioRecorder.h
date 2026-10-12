#pragma once

#include <TargetConditionals.h>

#if defined(__APPLE__) && TARGET_OS_IOS

#include <cstdint>

// Records the TV audio mix to an M4A (AAC) file. The iOS audio device calls Tap() with every block
// it is fed; while a recording is on, the samples are copied into a lock-free ring and a background
// thread encodes them with AVAudioFile. Nothing here touches what the player hears.
namespace IOSAudioRecorder
{
	// A second listener for the same feed (the screen recorder's audio track). Called on the audio thread
	// with each block, so it must copy and return. nullptr removes it.
	using Sink = void (*)(const int16_t* interleaved, uint32_t frames, uint32_t channels, uint32_t sampleRate);
	void SetSink(Sink sink);

	// Audio thread. Cheap when nothing is listening (a few relaxed atomic loads).
	void Tap(const int16_t* interleaved, uint32_t frames, uint32_t channels, uint32_t sampleRate);
	bool IsActive();
	// True while a recording or a sink wants the feed.
	bool WantsTap();

	// Starts a recording to `path` (an .m4a file; the folder must exist). False when one is already on.
	bool Start(const char* path);
	// Stops, drains and closes the file so it is complete and playable. Blocks until that is done.
	void Stop();
	// Seconds of audio written so far.
	double Seconds();
}

#endif
