#pragma once

// Decision logic of the video-stall watchdog, kept free of Cemu, Metal and UIKit so it can be compiled
// and tested on any machine (ci/stall-detector-test.cpp). The watchdog thread in CemuBridge.mm turns the
// live counters into a Sample every 250 ms and acts on the Decision that comes back.
//
// What counts as a frozen picture here, and what does not:
//
//   - The game is not sending GPU work (loading screen, a long synchronous load, a hang on the CPU side):
//     the GPU thread sits in an "idle" or guest wait. That is NOT a video freeze. Nothing is raised, one
//     log line says so.
//   - The GPU is not finishing work (command buffers time out and nothing retires), or frames are being
//     made but the screen cannot take them (the layer hands out no drawables): those ARE video freezes.
//   - A command buffer error that iOS answers by ignoring this app's GPU work is certain and is shown at
//     once. Everything else is a heuristic: it has to hold for a whole window, survive a second
//     confirmation a little later, and is dismissed again by itself when progress resumes.
//
// Every rule is written as "counter X has not changed for N seconds" so each decision can be audited from
// the log line it produces, which carries the rule name, the measured ages and the threshold.

#include <cstdint>
#include <cstdio>

namespace StallDetect
{
	// Numbers are the ones the Swift card switches on (ContentView.swift videoStalledCard).
	enum class Kind : int
	{
		None = 0,
		Picture = 1,       // the GPU stopped finishing frames
		GpuFault = 2,      // command buffer errors, iOS stopped this app's GPU work
		ScreenMemory = 3,  // the screen could not get a frame buffer and memory is nearly gone
		LowMemory = 4,     // warning: little memory left before iOS ends the app (not a freeze)
		ScreenStopped = 5, // frames are made but the screen will not take them
	};

	enum class Rule : uint8_t
	{
		None,
		CbErrorLatched,
		CbErrorStreak,
		GpuQueue,
		PresentFailing,
		GpuThreadNoProgress,
		LowMemory,
		GuestNotSending,
	};

	// What the GPU thread is blocked on (LatteWait::Kind in LatteWaitInfo.h, same values).
	enum class WaitClass : uint8_t
	{
		None = 0,      // running, or blocked somewhere without a breadcrumb
		GuestIdle = 1, // the command ring is empty: the game is not sending work
		GuestWait = 2, // waiting on something the game has to do (semaphore, flip)
		Gpu = 3,       // waiting on the GPU (command buffer, query, readback)
		Display = 4,   // waiting for a screen drawable
	};

	enum class Action : uint8_t
	{
		None,
		Suspect,         // heuristic condition holds for the whole window, now confirming (log only)
		SuspectDropped,  // the condition stopped holding before it was confirmed (log only)
		Raise,           // show the card
		Clear,           // hide the card, frames are back or the title is not being judged any more
		GuestNote,       // the game is not sending work; explicitly not a video freeze (log only)
	};

	struct Thresholds
	{
		// Quiet time after a title starts, after the app comes back, after a resume from pause, after the
		// display layout changes and after the watchdog itself was starved (a debugger stop, JIT enable).
		int64_t settleTitleStartMs = 15000;
		int64_t settleResumeMs = 3000;
		int64_t hiccupMs = 1500;

		int64_t confirmMs = 2000;
		int64_t queueWindowMs = 8000;       // GPU waits timing out, nothing retiring, nothing presented
		int64_t presentWindowMs = 8000;     // drawable requests failing, nothing presented
		int64_t unknownWindowMs = 15000;    // GPU thread makes no progress at all and is not waiting on the game
		int64_t unknownBootWindowMs = 45000; // same, before the first 30 frames
		int64_t streakWindowMs = 3000;
		int64_t streakConfirmMs = 1000;
		uint32_t streakMin = 5;              // consecutive failed command buffers with no success between

		uint32_t failuresInARowMin = 30;
		int64_t failureFreshMs = 1500;       // a failure must have happened this recently to count as "still failing"
		uint32_t screenMemoryBelowMB = 400;  // present failures with less than this free are reported as memory

		int64_t guestNoteMs = 10000;
		int64_t guestNoteRepeatMs = 60000;
		int64_t guestRecentMs = 2000;        // a guest wait seen this recently means the game is involved

		uint32_t lowMemBelowMB = 160;
		uint32_t lowMemClearMB = 300;
		int64_t lowMemHoldMs = 3000;
	};

	struct Sample
	{
		int64_t nowMs = 0;
		// context
		bool titleRunning = false; // a title is booted, not switching, not shut down
		bool gx2Init = false;
		bool paused = false;
		bool appActive = true;
		uint32_t layoutStamp = 0;  // changes when the window size, scale or visible outputs change
		double windowScale = 1.0;  // >1 lengthens every window (thermal throttling)
		// monotonic counters
		uint32_t frames = 0;           // guest swaps that reached the GPU thread
		uint32_t presented = 0;        // frames handed to the screen
		uint32_t drawableFailures = 0;
		uint32_t drawableFailuresInARow = 0;
		uint32_t cbRetired = 0;        // command buffers that finished without error
		uint32_t cbErrorStreak = 0;    // consecutive failed command buffers, reset by a success
		uint32_t pm4 = 0;              // GPU command packets processed
		uint32_t draws = 0;            // draw calls issued (the GPU thread is busy even when no frame completes)
		uint32_t flipRequests = 0;
		uint32_t evictionPasses = 0;
		// state
		bool gpuError = false;         // latched by a definite GPU fault
		int32_t gpuErrorCode = 0;
		int32_t lastCbErrorCode = 0;
		bool gpuPresumedLost = false;  // bounded GPU waits are timing out
		WaitClass waitClass = WaitClass::None;
		uint32_t availMemMB = 0;       // 0 = unknown
	};

	struct Decision
	{
		Action action = Action::None;
		Kind kind = Kind::None;
		Rule rule = Rule::None;
		char text[420] = {0};
	};

	inline const char* RuleName(Rule r)
	{
		switch (r)
		{
		case Rule::CbErrorLatched: return "cb_error_latched";
		case Rule::CbErrorStreak: return "cb_error_streak";
		case Rule::GpuQueue: return "gpu_queue_stalled";
		case Rule::PresentFailing: return "present_failing";
		case Rule::GpuThreadNoProgress: return "gpu_thread_no_progress";
		case Rule::LowMemory: return "low_memory";
		case Rule::GuestNotSending: return "guest_not_sending";
		default: return "none";
		}
	}

	inline const char* WaitName(WaitClass w)
	{
		switch (w)
		{
		case WaitClass::GuestIdle: return "guest idle";
		case WaitClass::GuestWait: return "guest wait";
		case WaitClass::Gpu: return "GPU wait";
		case WaitClass::Display: return "drawable wait";
		default: return "running/unknown";
		}
	}

	class Detector
	{
	public:
		explicit Detector(const Thresholds& t = Thresholds()) : t_(t) { Reset(0, true); }

		// A title started or was replaced: everything learned about the old one is void.
		void Reset(int64_t nowMs, bool titleStart)
		{
			stallKind_ = Kind::None;
			stallRule_ = Rule::None;
			raisedAtMs_ = 0;
			memRaised_ = false;
			memLowSince_ = -1;
			have_ = false;
			suspectRule_ = Rule::None;
			suspectSinceMs_ = 0;
			lastNowMs_ = nowMs;
			settleUntilMs_ = nowMs + (titleStart ? t_.settleTitleStartMs : t_.settleResumeMs);
		}

		Kind kind() const { return stallKind_ != Kind::None ? stallKind_ : (memRaised_ ? Kind::LowMemory : Kind::None); }
		Rule rule() const { return stallKind_ != Kind::None ? stallRule_ : (memRaised_ ? Rule::LowMemory : Rule::None); }
		int64_t raisedAtMs() const { return raisedAtMs_; }
		bool stallRaised() const { return stallKind_ != Kind::None; }

		Decision Update(const Sample& s)
		{
			Decision d;
			const int64_t now = s.nowMs;

			if (!s.titleRunning)
			{
				d = ClearStall(s, "title is not running");
				have_ = false;
				lastNowMs_ = now;
				return d;
			}

			// A definite fault: iOS ignores this app's GPU work from here on. Certain, so no window, no
			// confirmation, and it stays until the title ends (the renderer itself has stopped drawing).
			if (s.gpuError)
			{
				if (stallRule_ != Rule::CbErrorLatched)
				{
					char body[300];
					std::snprintf(body, sizeof(body), "a command buffer failed with code %d and iOS now ignores this app's GPU work; definite, shown immediately (no window, no confirmation)", (int)s.gpuErrorCode);
					d = Raise(s, Kind::GpuFault, Rule::CbErrorLatched, body);
				}
				lastNowMs_ = now;
				return d;
			}
			if (stallRule_ == Rule::CbErrorLatched)
			{
				d = ClearStall(s, "the GPU fault state was reset");
				have_ = false;
				lastNowMs_ = now;
				return d;
			}

			const bool expected = s.gx2Init && !s.paused && s.appActive;
			if (!expected)
			{
				d = ClearStall(s, !s.gx2Init ? "the title has not initialised graphics" : (s.paused ? "the title is paused" : "the app is not active"));
				have_ = false;
				suspectRule_ = Rule::None;
				lastNowMs_ = now;
				return d;
			}

			if (!have_)
			{
				Rebaseline(s, t_.settleResumeMs);
				lastNowMs_ = now;
				return d;
			}
			if (now - lastNowMs_ > t_.hiccupMs || s.layoutStamp != layoutStamp_)
			{
				Rebaseline(s, t_.settleResumeMs);
				lastNowMs_ = now;
				return d;
			}
			lastNowMs_ = now;

			Track(s);

			// A raised heuristic stall is dismissed the moment its own progress signal moves.
			if (stallKind_ != Kind::None)
				return CheckRecovery(s);

			if (now < settleUntilMs_)
			{
				suspectRule_ = Rule::None;
				return d;
			}

			const double scale = s.windowScale < 1.0 ? 1.0 : s.windowScale;
			Candidate c = Evaluate(s, scale);
			if (c.rule != Rule::None)
			{
				if (suspectRule_ != c.rule)
				{
					suspectRule_ = c.rule;
					suspectSinceMs_ = now;
					d.action = Action::Suspect;
					d.kind = c.kind;
					d.rule = c.rule;
					std::snprintf(d.text, sizeof(d.text), "rule=%s SUSPECTED, confirming for %.1f s: %s", RuleName(c.rule), (double)c.confirmMs / 1000.0, c.body);
					return d;
				}
				if (now - suspectSinceMs_ >= c.confirmMs)
				{
					suspectRule_ = Rule::None;
					return Raise(s, c.kind, c.rule, c.body);
				}
				return d;
			}
			if (suspectRule_ != Rule::None)
			{
				d.action = Action::SuspectDropped;
				d.rule = suspectRule_;
				std::snprintf(d.text, sizeof(d.text), "rule=%s suspicion dropped after %.1f s: the condition no longer holds (progress resumed)", RuleName(suspectRule_), (double)(now - suspectSinceMs_) / 1000.0);
				suspectRule_ = Rule::None;
				return d;
			}

			return GuestNote(s, scale);
		}

		// Low memory is a warning about the app being about to be ended, not a frozen picture, so it runs on
		// its own track and only needs the title running and the app in the foreground.
		Decision UpdateMemory(const Sample& s)
		{
			Decision d;
			const int64_t now = s.nowMs;
			const bool judge = s.titleRunning && s.appActive && s.availMemMB != 0;
			if (!judge)
			{
				memLowSince_ = -1;
				if (memRaised_ && !(s.titleRunning && s.appActive))
				{
					memRaised_ = false;
					d.action = Action::Clear;
					d.rule = Rule::LowMemory;
					std::snprintf(d.text, sizeof(d.text), "rule=low_memory cleared: the title or the app is no longer in the foreground");
				}
				return d;
			}
			if (memRaised_)
			{
				if (s.availMemMB >= t_.lowMemClearMB)
				{
					memRaised_ = false;
					memLowSince_ = -1;
					d.action = Action::Clear;
					d.rule = Rule::LowMemory;
					std::snprintf(d.text, sizeof(d.text), "rule=low_memory cleared: %u MB free (clear threshold %u MB)", (unsigned)s.availMemMB, (unsigned)t_.lowMemClearMB);
				}
				return d;
			}
			if (s.availMemMB < t_.lowMemBelowMB)
			{
				if (memLowSince_ < 0)
					memLowSince_ = now;
				if (now - memLowSince_ >= t_.lowMemHoldMs)
				{
					memRaised_ = true;
					d.action = Action::Raise;
					d.kind = Kind::LowMemory;
					d.rule = Rule::LowMemory;
					std::snprintf(d.text, sizeof(d.text), "rule=low_memory CONFIRMED: %u MB free for %.1f s (threshold < %u MB held %.1f s); this is a warning, the picture may still be moving",
						(unsigned)s.availMemMB, (double)(now - memLowSince_) / 1000.0, (unsigned)t_.lowMemBelowMB, (double)t_.lowMemHoldMs / 1000.0);
				}
			}
			else
			{
				memLowSince_ = -1;
			}
			return d;
		}

	private:
		struct Candidate
		{
			Rule rule = Rule::None;
			Kind kind = Kind::None;
			int64_t confirmMs = 0;
			char body[300] = {0};
		};

		static double Sec(int64_t ms) { return (double)ms / 1000.0; }

		void Rebaseline(const Sample& s, int64_t settleMs)
		{
			const int64_t now = s.nowMs;
			have_ = true;
			prevFrames_ = s.frames; tFrames_ = now;
			prevPresented_ = s.presented; tPresented_ = now;
			prevRetired_ = s.cbRetired; tRetired_ = now;
			prevPm4_ = s.pm4; tPm4_ = now;
			prevDraws_ = s.draws;
			prevFlips_ = s.flipRequests; tFlips_ = now;
			prevFailures_ = s.drawableFailures; tFailure_ = now;
			prevEvictions_ = s.evictionPasses;
			presumedLostSince_ = s.gpuPresumedLost ? now : -1;
			streakSince_ = -1;
			layoutStamp_ = s.layoutStamp;
			lastGuestWaitMs_ = -1000000000LL;
			idleNotedAtMs_ = -1;
			suspectRule_ = Rule::None;
			if (now + settleMs > settleUntilMs_)
				settleUntilMs_ = now + settleMs;
		}

		void Track(const Sample& s)
		{
			const int64_t now = s.nowMs;
			if (s.frames != prevFrames_) { prevFrames_ = s.frames; tFrames_ = now; idleNotedAtMs_ = -1; }
			if (s.presented != prevPresented_) { prevPresented_ = s.presented; tPresented_ = now; }
			if (s.cbRetired != prevRetired_) { prevRetired_ = s.cbRetired; tRetired_ = now; }
			if (s.pm4 != prevPm4_) { prevPm4_ = s.pm4; tPm4_ = now; }
			// A long stretch of draws with no finished frame is heavy loading or rendering, which is progress.
			if (s.draws != prevDraws_) { prevDraws_ = s.draws; tPm4_ = now; }
			if (s.flipRequests != prevFlips_) { prevFlips_ = s.flipRequests; tFlips_ = now; }
			if (s.drawableFailures != prevFailures_) { prevFailures_ = s.drawableFailures; tFailure_ = now; }
			// A memory-pressure eviction pass is the GPU thread busy with real work: count it as progress.
			if (s.evictionPasses != prevEvictions_) { prevEvictions_ = s.evictionPasses; tPm4_ = now; }
			if (s.gpuPresumedLost) { if (presumedLostSince_ < 0) presumedLostSince_ = now; }
			else presumedLostSince_ = -1;
			if (s.cbErrorStreak >= t_.streakMin) { if (streakSince_ < 0) streakSince_ = now; }
			else streakSince_ = -1;
			if (s.waitClass == WaitClass::GuestIdle || s.waitClass == WaitClass::GuestWait)
				lastGuestWaitMs_ = now;
		}

		Candidate Evaluate(const Sample& s, double scale) const
		{
			Candidate c;
			const int64_t now = s.nowMs;
			const int64_t ageFrames = now - tFrames_, agePresent = now - tPresented_, ageRetired = now - tRetired_;
			const int64_t agePm4 = now - tPm4_, ageFlips = now - tFlips_, ageFailure = now - tFailure_;
			const bool guestRecent = (now - lastGuestWaitMs_) < t_.guestRecentMs;

			// 1. Command buffers keep failing with none succeeding in between while the app is in the foreground.
			// (Not-permitted errors while in the background are expected; Rebaseline clears them on return.)
			if (streakSince_ >= 0 && now - streakSince_ >= t_.streakWindowMs)
			{
				c.rule = Rule::CbErrorStreak;
				c.kind = Kind::GpuFault;
				c.confirmMs = t_.streakConfirmMs;
				std::snprintf(c.body, sizeof(c.body), "%u command buffers in a row failed (last code %d), none succeeded for %.1f s (need >= %u in a row held >= %.1f s) while the app is in the foreground",
					(unsigned)s.cbErrorStreak, (int)s.lastCbErrorCode, Sec(now - streakSince_), (unsigned)t_.streakMin, Sec(t_.streakWindowMs));
				return c;
			}

			// 2. The GPU is not finishing work: bounded GPU waits keep timing out, nothing retires, nothing is
			// presented, and the game is still handing work over (so this is not a game-side hang).
			const int64_t wq = (int64_t)(t_.queueWindowMs * scale);
			if (presumedLostSince_ >= 0 && now - presumedLostSince_ >= wq && ageRetired >= wq && agePresent >= wq
				&& (agePm4 < wq || ageFlips < wq) && !guestRecent)
			{
				c.rule = Rule::GpuQueue;
				c.kind = Kind::Picture;
				c.confirmMs = t_.confirmMs;
				std::snprintf(c.body, sizeof(c.body), "GPU waits have been timing out for %.1f s, no command buffer finished for %.1f s, no frame presented for %.1f s (each >= %.1f s); the game is still submitting (last GPU packet %.1f s ago, last flip request %.1f s ago); GPU thread: %s",
					Sec(now - presumedLostSince_), Sec(ageRetired), Sec(agePresent), Sec(wq), Sec(agePm4), Sec(ageFlips), WaitName(s.waitClass));
				return c;
			}

			// 3. Frames are being made but the screen takes none of them.
			const int64_t wp = (int64_t)(t_.presentWindowMs * scale);
			if (s.drawableFailuresInARow >= t_.failuresInARowMin && ageFailure < t_.failureFreshMs && agePresent >= wp)
			{
				c.rule = Rule::PresentFailing;
				const bool lowMem = s.availMemMB != 0 && s.availMemMB < t_.screenMemoryBelowMB;
				c.kind = lowMem ? Kind::ScreenMemory : Kind::ScreenStopped;
				c.confirmMs = t_.confirmMs;
				std::snprintf(c.body, sizeof(c.body), "%u drawable requests in a row failed (need >= %u), the latest %.1f s ago (< %.1f s), no frame presented for %.1f s (>= %.1f s); free memory %u MB (%s)",
					(unsigned)s.drawableFailuresInARow, (unsigned)t_.failuresInARowMin, Sec(ageFailure), Sec(t_.failureFreshMs), Sec(agePresent), Sec(wp),
					(unsigned)s.availMemMB, lowMem ? "low, counted as out of memory for the screen" : "not low, cause unknown");
				return c;
			}

			// 4. The GPU thread itself makes no progress and is not waiting for the game. Long window: it has no
			// direct evidence of a cause, so a slow synchronous compile or load must be able to finish first.
			const int64_t wu = (int64_t)((s.frames < 30 ? t_.unknownBootWindowMs : t_.unknownWindowMs) * scale);
			const bool guestSide = s.waitClass == WaitClass::GuestIdle || s.waitClass == WaitClass::GuestWait || guestRecent;
			if (ageFrames >= wu && agePm4 >= wu && agePresent >= wu && ageRetired >= wu && !guestSide)
			{
				c.rule = Rule::GpuThreadNoProgress;
				c.kind = Kind::Picture;
				c.confirmMs = t_.confirmMs;
				std::snprintf(c.body, sizeof(c.body), "no frame for %.1f s, no GPU packet for %.1f s, nothing finished for %.1f s, nothing presented for %.1f s (each >= %.1f s) and the GPU thread is not waiting for the game (%s); cause unverified",
					Sec(ageFrames), Sec(agePm4), Sec(ageRetired), Sec(agePresent), Sec(wu), WaitName(s.waitClass));
				return c;
			}
			return c;
		}

		// No frame for a while, but the GPU thread is waiting for the game: log it once, raise nothing.
		Decision GuestNote(const Sample& s, double scale)
		{
			Decision d;
			const int64_t now = s.nowMs;
			const int64_t ageFrames = now - tFrames_;
			const int64_t wn = (int64_t)(t_.guestNoteMs * scale);
			const bool guestSide = s.waitClass == WaitClass::GuestIdle || s.waitClass == WaitClass::GuestWait || (now - lastGuestWaitMs_) < t_.guestRecentMs;
			if (ageFrames < wn || !guestSide)
				return d;
			if (idleNotedAtMs_ >= 0 && now - idleNotedAtMs_ < t_.guestNoteRepeatMs)
				return d;
			idleNotedAtMs_ = now;
			d.action = Action::GuestNote;
			d.rule = Rule::GuestNotSending;
			std::snprintf(d.text, sizeof(d.text), "rule=guest_not_sending: no frame for %.1f s (note threshold %.1f s) but the GPU thread is waiting on the game (%s), last GPU packet %.1f s ago, last flip request %.1f s ago; a game-side load or hang, NOT a video freeze, no card shown",
				Sec(ageFrames), Sec(wn), WaitName(s.waitClass), Sec(now - tPm4_), Sec(now - tFlips_));
			return d;
		}

		Decision Raise(const Sample& s, Kind kind, Rule rule, const char* body)
		{
			Decision d;
			stallKind_ = kind;
			stallRule_ = rule;
			raisedAtMs_ = s.nowMs;
			raiseFrames_ = s.frames;
			raisePresented_ = s.presented;
			raiseRetired_ = s.cbRetired;
			raisePm4_ = s.pm4;
			raiseDraws_ = s.draws;
			d.action = Action::Raise;
			d.kind = kind;
			d.rule = rule;
			std::snprintf(d.text, sizeof(d.text), "rule=%s CONFIRMED: %s", RuleName(rule), body);
			return d;
		}

		Decision ClearStall(const Sample& s, const char* why)
		{
			Decision d;
			if (stallKind_ == Kind::None)
				return d;
			d.action = Action::Clear;
			d.kind = Kind::None;
			d.rule = stallRule_;
			std::snprintf(d.text, sizeof(d.text), "rule=%s cleared after %.1f s: %s", RuleName(stallRule_), Sec(s.nowMs - raisedAtMs_), why);
			stallKind_ = Kind::None;
			stallRule_ = Rule::None;
			return d;
		}

		Decision CheckRecovery(const Sample& s)
		{
			bool recovered = false;
			char why[200];
			switch (stallRule_)
			{
			case Rule::CbErrorStreak:
				recovered = s.cbErrorStreak < t_.streakMin || s.cbRetired != raiseRetired_;
				std::snprintf(why, sizeof(why), "frames are back: a command buffer finished again (finished %u -> %u, error streak %u)", (unsigned)raiseRetired_, (unsigned)s.cbRetired, (unsigned)s.cbErrorStreak);
				break;
			case Rule::GpuQueue:
				recovered = s.cbRetired != raiseRetired_ || s.presented != raisePresented_;
				std::snprintf(why, sizeof(why), "frames are back: finished %u -> %u, presented %u -> %u", (unsigned)raiseRetired_, (unsigned)s.cbRetired, (unsigned)raisePresented_, (unsigned)s.presented);
				break;
			case Rule::PresentFailing:
				recovered = s.presented != raisePresented_;
				std::snprintf(why, sizeof(why), "frames are back: presented %u -> %u", (unsigned)raisePresented_, (unsigned)s.presented);
				break;
			default:
				recovered = s.frames != raiseFrames_ || s.pm4 != raisePm4_ || s.draws != raiseDraws_ || s.presented != raisePresented_ || s.cbRetired != raiseRetired_;
				std::snprintf(why, sizeof(why), "frames are back: frame %u -> %u, GPU packets %u -> %u, presented %u -> %u", (unsigned)raiseFrames_, (unsigned)s.frames, (unsigned)raisePm4_, (unsigned)s.pm4, (unsigned)raisePresented_, (unsigned)s.presented);
				break;
			}
			if (!recovered)
				return Decision();
			Decision d = ClearStall(s, why);
			// Judge the title afresh from here so the same old numbers cannot re-raise it at once.
			Rebaseline(s, t_.settleResumeMs);
			return d;
		}

		Thresholds t_;
		Kind stallKind_ = Kind::None;
		Rule stallRule_ = Rule::None;
		int64_t raisedAtMs_ = 0;
		uint32_t raiseFrames_ = 0, raisePresented_ = 0, raiseRetired_ = 0, raisePm4_ = 0, raiseDraws_ = 0;
		bool memRaised_ = false;
		int64_t memLowSince_ = -1;

		bool have_ = false;
		int64_t lastNowMs_ = 0;
		int64_t settleUntilMs_ = 0;
		uint32_t layoutStamp_ = 0;
		uint32_t prevFrames_ = 0, prevPresented_ = 0, prevRetired_ = 0, prevPm4_ = 0, prevDraws_ = 0, prevFlips_ = 0, prevFailures_ = 0, prevEvictions_ = 0;
		int64_t tFrames_ = 0, tPresented_ = 0, tRetired_ = 0, tPm4_ = 0, tFlips_ = 0, tFailure_ = 0;
		int64_t presumedLostSince_ = -1, streakSince_ = -1;
		int64_t lastGuestWaitMs_ = -1000000000LL;
		int64_t idleNotedAtMs_ = -1;
		Rule suspectRule_ = Rule::None;
		int64_t suspectSinceMs_ = 0;
	};
}
