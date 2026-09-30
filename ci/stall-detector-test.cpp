// Off-device test of the video-stall decision logic.
//   clang++ -std=c++17 -I src/ios/Bridge ci/stall-detector-test.cpp -o /tmp/stall-test && /tmp/stall-test
#include "StallDetector.h"
#include <cstdio>
#include <cstdlib>
#include <string>

using namespace StallDetect;

static int g_failed = 0;
#define CHECK(cond, msg) do { if (!(cond)) { std::printf("FAIL %s:%d %s (%s)\n", __FILE__, __LINE__, msg, #cond); g_failed++; } } while (0)

// Drives a Detector at the watchdog's 250 ms poll and remembers what it said.
struct Sim
{
	Detector det;
	Sample s;
	int64_t now = 100000;
	int raises = 0, clears = 0, suspects = 0, notes = 0, dropped = 0;
	Kind lastRaised = Kind::None;
	Rule lastRule = Rule::None;
	std::string lastText;

	Sim()
	{
		s.titleRunning = true; s.gx2Init = true; s.appActive = true; s.paused = false;
		s.availMemMB = 900; s.memLimitMB = 4000; s.frames = 100; s.presented = 100; s.cbRetired = 100; s.pm4 = 1000; s.flipRequests = 100;
		det.Reset(now, true);
	}
	void Step()
	{
		now += 250;
		s.nowMs = now;
		Decision d = det.Update(s);
		Decision m = det.UpdateMemory(s);
		for (const Decision* x : { &d, &m })
		{
			switch (x->action)
			{
			case Action::Raise: raises++; lastRaised = x->kind; lastRule = x->rule; lastText = x->text; break;
			case Action::Clear: clears++; lastText = x->text; break;
			case Action::Suspect: suspects++; break;
			case Action::SuspectDropped: dropped++; break;
			case Action::GuestNote: notes++; lastText = x->text; break;
			default: break;
			}
		}
	}
	// `live` moves frames, presents, retirements and GPU packets like a healthy game at `fps`.
	void Run(double seconds, double fps, bool live = true)
	{
		const int steps = (int)(seconds * 4);
		double acc = 0;
		for (int i = 0; i < steps; i++)
		{
			if (live && fps > 0)
			{
				acc += fps / 4.0;
				while (acc >= 1.0) { acc -= 1.0; s.frames++; s.presented++; s.cbRetired++; s.pm4 += 40; s.flipRequests++; }
			}
			Step();
		}
	}
	bool stalled() const { return det.kind() != Kind::None; }
};

static void healthy_game_is_quiet()
{
	Sim t; t.Run(120, 30);
	CHECK(!t.stalled() && t.raises == 0 && t.suspects == 0, "healthy 30 fps game");
}

static void low_fps_game_is_quiet()
{
	Sim t; t.s.waitClass = WaitClass::GuestWait; t.Run(120, 0.5);
	CHECK(!t.stalled() && t.raises == 0, "game at half a frame per second");
}

static void loading_screen_is_not_a_freeze()
{
	Sim t; t.Run(20, 30);
	t.s.waitClass = WaitClass::GuestIdle; // game sends nothing for a minute
	t.Run(60, 0, false);
	CHECK(!t.stalled() && t.raises == 0, "idle GPU thread while the game loads must not raise");
	CHECK(t.notes >= 1, "but it is logged once as not-a-video-freeze");
	CHECK(t.notes <= 2, "and not spammed");
	t.s.waitClass = WaitClass::None; t.Run(5, 30);
	CHECK(!t.stalled(), "frames resume");
}

static void sync_load_with_gpu_thread_busy_is_not_a_freeze()
{
	// the game keeps the command processor busy (offscreen passes) but flips nothing for a long time
	Sim t; t.Run(20, 30);
	for (int i = 0; i < 240; i++) { t.s.pm4 += 10; t.Step(); }
	CHECK(!t.stalled() && t.raises == 0, "60 s of GPU work with no flip");
}

static void shader_compile_stall_then_recover()
{
	Sim t; t.Run(20, 30);
	t.Run(12, 0, false); // GPU thread stuck in CPU work with no breadcrumb for 12 s (< 15 s window)
	CHECK(!t.stalled(), "a 12 s compile stall is inside the window");
	t.Run(3, 30);
	CHECK(!t.stalled() && t.raises == 0, "recovered without a card");
}

static void background_inactive_locked_never_raise()
{
	Sim t; t.Run(20, 30);
	t.s.appActive = false; t.s.gpuPresumedLost = true; t.s.cbErrorStreak = 40; t.s.drawableFailuresInARow = 500; t.s.drawableFailures = 500;
	t.Run(120, 0, false);
	CHECK(!t.stalled() && t.raises == 0, "nothing is judged while the app is not active");
	// coming back: old failure state is still latched in the counters for a moment
	t.s.appActive = true;
	t.Run(2.5, 0, false);
	t.s.gpuPresumedLost = false; t.s.cbErrorStreak = 0; t.s.drawableFailuresInARow = 0;
	t.Run(20, 30);
	CHECK(!t.stalled() && t.raises == 0, "returning to the foreground with stale failure counters");
}

static void pause_menu_and_save_state()
{
	Sim t; t.Run(20, 30);
	t.s.paused = true; t.Run(90, 0, false);
	CHECK(!t.stalled() && t.raises == 0, "paused");
	t.s.paused = false; t.Run(2, 0, false); // guest threads resuming
	t.Run(10, 30);
	CHECK(!t.stalled() && t.raises == 0, "resume");
}

static void title_start_and_switch_grace()
{
	Sim t; t.s.frames = 0; t.s.presented = 0; t.s.pm4 = 0; t.s.cbRetired = 0; t.s.flipRequests = 0;
	t.det.Reset(t.now, true);
	t.s.waitClass = WaitClass::None;
	t.Run(40, 0, false); // 40 s before the first frame, GPU thread in CPU work
	CHECK(!t.stalled() && t.raises == 0, "boot grace: 40 s with no first frame");
	t.Run(30, 30);
	CHECK(!t.stalled(), "then it runs");
	// title switch: counters of the old renderer, the flag state is wiped
	t.det.Reset(t.now, true);
	t.s.frames = 0;
	t.Run(14, 0, false);
	CHECK(!t.stalled() && t.raises == 0, "switch grace");
}

static void thermal_throttling_lengthens_windows()
{
	Sim t; t.Run(20, 30);
	t.s.windowScale = 2.0;
	t.Run(25, 0, false); // would raise at 15 s + 2 s unscaled
	CHECK(!t.stalled() && t.raises == 0, "windows scale with the thermal state");
}

// Breath of the Wild, v5.8 log botw-1222: heavy loading at 12:22:14 and 12:22:22, frame 467 -> 470 with draw
// calls 2150 -> 5677 inside one frame, 0 command buffers pending, 0 failed, "frames are arriving again" 4 s later.
// The old 4 s rule fired twice on this. Nothing may fire, however long it goes on.
static void botw_heavy_loading_slow_frames()
{
	Sim t; t.Run(30, 30);
	for (int gap = 0; gap < 12; gap++) // a frame every 4 s for 48 s while the GPU thread draws the whole time
	{
		for (int i = 0; i < 16; i++) { t.s.draws += 220; t.Step(); }
		t.s.frames++; t.s.presented++;
	}
	CHECK(!t.stalled() && t.raises == 0 && t.suspects == 0, "slow frames with draw calls climbing");
	// the same but nothing presents at all for 30 s while draws climb (offscreen-only loading pass)
	for (int i = 0; i < 120; i++) { t.s.draws += 220; t.Step(); }
	CHECK(!t.stalled() && t.raises == 0 && t.suspects == 0, "no frame for 30 s with the GPU thread drawing");
	// and the real fault that followed is still immediate
	t.s.gpuError = true; t.s.gpuErrorCode = 3; t.Step();
	CHECK(t.det.kind() == Kind::GpuFault, "the page fault that followed is shown at once");
}

static void drawable_hiccups_are_ignored()
{
	Sim t; t.Run(20, 30);
	// 60 failed acquires in a row over 1 s (rotation), then presenting again
	t.s.drawableFailuresInARow = 60; t.s.drawableFailures += 60; t.Run(1, 0, false);
	t.s.drawableFailuresInARow = 0; t.Run(10, 30);
	CHECK(!t.stalled() && t.raises == 0, "short failure run");

	// rotation: layout changes while the layer has no drawable for 6 s
	t.s.layoutStamp = 77;
	for (int i = 0; i < 24; i++) { t.s.drawableFailures += 15; t.s.drawableFailuresInARow += 15; t.s.frames++; t.Step(); }
	t.s.drawableFailuresInARow = 0; t.Run(10, 30);
	CHECK(!t.stalled() && t.raises == 0, "failures through a rotation");
}

static void occlusion_query_wait_that_completes()
{
	Sim t; t.Run(20, 30);
	t.s.waitClass = WaitClass::Gpu; t.Run(7, 0, false);
	t.s.waitClass = WaitClass::None; t.Run(5, 30);
	CHECK(!t.stalled() && t.raises == 0, "7 s GPU wait that completes");
}

static void memory_eviction_dip_and_real_low_memory()
{
	Sim t; t.Run(20, 30);
	t.s.availMemMB = 120; t.Run(1.5, 30);
	t.s.availMemMB = 800; t.Run(5, 30);
	CHECK(!t.stalled() && t.raises == 0, "a dip under 160 MB for 1.5 s");
	t.s.availMemMB = 120; t.Run(4, 30);
	CHECK(t.stalled() && t.det.kind() == Kind::LowMemory, "sustained low memory warns");
	t.s.availMemMB = 250; t.Run(1, 30);
	CHECK(t.stalled(), "hysteresis keeps the warning up between 160 and 300 MB");
	t.s.availMemMB = 400; t.Run(1, 30);
	CHECK(!t.stalled(), "clears when memory recovers");
}

// Nothing is tuned to one chip: windows follow the median frame time this session measured, memory limits follow the
// process's own memory limit.
static void windows_follow_the_device_speed()
{
	// a slow device: 10 fps is a 100 ms median, 3x the 30 fps reference, so the 15 s window is 45 s there
	Sim slow; slow.Run(30, 10);
	CHECK(slow.det.FrameScale() > 2.9 && slow.det.FrameScale() < 3.3, "median frame time of a 10 fps session");
	slow.Run(40, 0, false);
	CHECK(!slow.stalled() && slow.raises == 0 && slow.suspects == 0, "40 s stall on a 10 fps device is still inside the scaled window");
	slow.Run(15, 0, false);
	CHECK(slow.stalled() && slow.lastRule == Rule::GpuThreadNoProgress, "but a real one is caught after the scaled window + confirmation");

	// a fast device keeps the unscaled floor exactly (this is the A12Z-at-30-fps behaviour, unchanged)
	Sim fast; fast.Run(30, 60);
	CHECK(fast.det.FrameScale() == 1.0, "60 fps never shortens a window");
	fast.Run(16, 0, false);
	CHECK(fast.suspects == 1, "suspected at 15 s on a fast device");
	fast.Run(3, 0, false);
	CHECK(fast.stalled(), "confirmed on a fast device");

	// what this session learned about the device carries into the next title
	Sim carry; carry.Run(30, 10);
	carry.det.Reset(carry.now, true);
	CHECK(carry.det.FrameScale() > 2.9, "the next title starts with the device's measured scale");
	carry.s.frames = 0;
	carry.Run(40, 0, false);
	CHECK(!carry.stalled() && carry.raises == 0, "title-start grace is scaled as well");
}

static void memory_limits_scale_with_the_device()
{
	// a device with a 1.5 GB process limit warns below 60 MB (4%), not 160 MB
	Sim small; small.s.memLimitMB = 1500; small.Run(20, 30);
	small.s.availMemMB = 100; small.Run(10, 30);
	CHECK(!small.stalled(), "100 MB free is fine on a 1.5 GB limit");
	small.s.availMemMB = 50; small.Run(4, 30);
	CHECK(small.det.kind() == Kind::LowMemory, "50 MB free is low on a 1.5 GB limit");
	CHECK(small.lastText.find("1500 MB memory limit") != std::string::npos || small.lastText.find("1500 MB") != std::string::npos, "log states the limit");

	// the same 100 MB on a big device is low
	Sim big; big.s.memLimitMB = 6000; big.Run(20, 30);
	big.s.availMemMB = 100; big.Run(4, 30);
	CHECK(big.det.kind() == Kind::LowMemory, "100 MB free is low on a 6 GB limit");

	// unknown limit: nothing is judged rather than guessed
	Sim unk; unk.s.memLimitMB = 0; unk.Run(20, 30); unk.s.availMemMB = 10; unk.Run(10, 30);
	CHECK(!unk.stalled(), "unknown limit");
}

static void debugger_or_jit_pause_is_a_hiccup()
{
	Sim t; t.Run(20, 30);
	// whole process stopped for 40 s: steady clock jumps, counters unchanged
	t.now += 40000; t.Step();
	t.Run(3, 0, false);
	CHECK(!t.stalled() && t.raises == 0, "process stop is not a stall");
}

static void definite_gpu_fault_is_immediate_and_latched()
{
	Sim t; t.Run(20, 30);
	t.s.gpuError = true; t.s.gpuErrorCode = 3;
	t.Step();
	CHECK(t.stalled() && t.det.kind() == Kind::GpuFault && t.lastRaised == Kind::GpuFault, "raised on the first poll");
	t.Run(30, 30);
	CHECK(t.det.kind() == Kind::GpuFault, "stays until the title ends");
	t.s.gpuError = false; t.det.Reset(t.now, true); t.Step();
	CHECK(!t.stalled(), "reset on title switch");
}

static void gpu_queue_stall_needs_window_confirmation_and_clears()
{
	Sim t; t.Run(20, 30);
	// GPU stops finishing: waits time out, game still sends packets
	t.s.gpuPresumedLost = true;
	for (int i = 0; i < 4 * 7; i++) { t.s.pm4 += 5; t.s.flipRequests++; t.Step(); }
	CHECK(!t.stalled() && t.suspects == 0, "7 s is inside the 8 s window");
	for (int i = 0; i < 4 * 2; i++) { t.s.pm4 += 5; t.Step(); }
	CHECK(t.suspects == 1 && !t.stalled(), "suspected after 8 s, not yet confirmed");
	for (int i = 0; i < 4 * 3; i++) { t.s.pm4 += 5; t.Step(); }
	CHECK(t.stalled() && t.det.kind() == Kind::Picture && t.lastRule == Rule::GpuQueue, "confirmed after the second look");
	CHECK(t.lastText.find("rule=gpu_queue_stalled") != std::string::npos && t.lastText.find(">= 8.0 s") != std::string::npos, "log line names the rule and the threshold");
	// frames resume
	t.s.gpuPresumedLost = false; t.Run(1, 30);
	CHECK(!t.stalled() && t.clears == 1, "auto-clears when frames resume");
	t.Run(30, 30);
	CHECK(!t.stalled() && t.raises == 1, "and does not re-raise");
}

static void gpu_queue_stall_with_idle_guest_is_not_raised()
{
	Sim t; t.Run(20, 30);
	t.s.gpuPresumedLost = true; t.s.waitClass = WaitClass::GuestIdle;
	t.Run(40, 0, false);
	CHECK(!t.stalled() && t.raises == 0, "the game stopped sending: guest side, not a video freeze");
}

static void present_failing_reports_cause()
{
	Sim t; t.Run(20, 30);
	// frames keep being made, the layer never gives a drawable
	for (int i = 0; i < 4 * 12; i++) { t.s.frames += 8; t.s.drawableFailures += 15; t.s.drawableFailuresInARow += 15; t.Step(); }
	CHECK(t.stalled() && t.det.kind() == Kind::ScreenStopped, "screen stopped, memory fine");
	t.s.drawableFailuresInARow = 0; t.s.presented++; t.Run(0.5, 0, false);
	CHECK(!t.stalled(), "clears on the next present");

	Sim u; u.Run(20, 30); u.s.availMemMB = 250;
	for (int i = 0; i < 4 * 12; i++) { u.s.frames += 8; u.s.drawableFailures += 15; u.s.drawableFailuresInARow += 15; u.Step(); }
	CHECK(u.stalled() && u.det.kind() == Kind::ScreenMemory, "same symptom with memory gone is reported as out of memory");
}

static void soft_error_streak()
{
	Sim t; t.Run(20, 30);
	// not-permitted style errors in the foreground that never stop
	t.s.cbErrorStreak = 8; t.s.lastCbErrorCode = 7;
	t.Run(6, 0, false);
	CHECK(t.stalled() && t.det.kind() == Kind::GpuFault && t.lastRule == Rule::CbErrorStreak, "5+ failed command buffers with no success");
	t.s.cbErrorStreak = 0; t.s.cbRetired++; t.Run(1, 30);
	CHECK(!t.stalled(), "a success clears it");
}

static void gpu_thread_no_progress()
{
	Sim t; t.Run(20, 30);
	t.Run(16, 0, false);
	CHECK(t.suspects == 1, "suspected after 15 s");
	t.Run(3, 0, false);
	CHECK(t.stalled() && t.lastRule == Rule::GpuThreadNoProgress, "confirmed");
	t.s.pm4 += 100; t.Step();
	CHECK(!t.stalled(), "a GPU packet dismisses it");
}

int main()
{
	healthy_game_is_quiet();
	botw_heavy_loading_slow_frames();
	low_fps_game_is_quiet();
	loading_screen_is_not_a_freeze();
	sync_load_with_gpu_thread_busy_is_not_a_freeze();
	shader_compile_stall_then_recover();
	background_inactive_locked_never_raise();
	pause_menu_and_save_state();
	title_start_and_switch_grace();
	thermal_throttling_lengthens_windows();
	windows_follow_the_device_speed();
	memory_limits_scale_with_the_device();
	drawable_hiccups_are_ignored();
	occlusion_query_wait_that_completes();
	memory_eviction_dip_and_real_low_memory();
	debugger_or_jit_pause_is_a_hiccup();
	definite_gpu_fault_is_immediate_and_latched();
	gpu_queue_stall_needs_window_confirmation_and_clears();
	gpu_queue_stall_with_idle_guest_is_not_raised();
	present_failing_reports_cause();
	soft_error_streak();
	gpu_thread_no_progress();
	if (g_failed == 0)
		std::printf("all stall-detector tests passed\n");
	return g_failed == 0 ? 0 : 1;
}
