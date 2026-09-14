// Pause and resume for a running title.
//
// The core has no pause of its own - MeloCafe's app only ever shut a title down - but
// iOS needs one: the app goes to the background, a sheet covers the game, a call comes
// in. This suspends every active guest thread under the scheduler lock and resumes them
// again, using only coreinit functions the core already exports, so the core itself is
// untouched. It is the same mechanism cemu-ios-muffin's own core used.
//
// IMPORTANT for any caller that needs the title to actually be STOPPED, not just marked
// to stop (save states are the reason this note exists): IOSTitlePause_Pause() returning
// does NOT mean every core has stopped executing PPC instructions yet. It suspends each
// guest thread's scheduling state, but a thread that is already mid-timeslice on a core
// keeps running - and keeps touching guest memory - until that core reaches its own next
// reschedule point (see __OSSuspendThreadInternal()'s own "todo - if thread is still
// running find a way to cancel it's timeslice immediately" in coreinit_Thread.cpp). This
// is fine for backgrounding (nothing reads memory from another thread while paused here),
// but a caller that dumps or overwrites guest memory from a different thread - see
// IOSSaveState.cpp - must additionally poll coreinit::__OSAllCoresIdle() (and, separately,
// wait for the GPU command queue to drain) before it is actually safe to touch anything.
#include "Cafe/CafeSystem.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
// __OSLockScheduler/__OSUnlockScheduler are declared at global scope here, not in coreinit.
#include "Cafe/OS/libs/coreinit/coreinit_Scheduler.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>

static std::atomic_bool sTitlePaused{false};

bool IOSTitlePause_Pause()
{
	if (!CafeSystem::IsTitleRunning() || sTitlePaused.exchange(true))
		return false;
	__OSLockScheduler();
	for (sint32 i = 0; i < activeThreadCount; i++)
	{
		auto thread = reinterpret_cast<OSThread_t*>(memory_getPointerFromVirtualOffset(activeThread[i]));
		coreinit::__OSSuspendThreadNolock(thread);
	}
	__OSUnlockScheduler();
	cemuLog_log(LogType::Force, "iOS: title paused ({} guest threads suspended)", activeThreadCount);
	return true;
}

bool IOSTitlePause_Resume()
{
	if (!sTitlePaused.exchange(false))
		return false;
	if (!CafeSystem::IsTitleRunning())
		return false;
	__OSLockScheduler();
	for (sint32 i = 0; i < activeThreadCount; i++)
	{
		auto thread = reinterpret_cast<OSThread_t*>(memory_getPointerFromVirtualOffset(activeThread[i]));
		coreinit::__OSResumeThreadInternal(thread, 1);
	}
	__OSUnlockScheduler();
	cemuLog_log(LogType::Force, "iOS: title resumed");
	return true;
}

bool IOSTitlePause_IsPaused()
{
	return sTitlePaused.load();
}

// A title that shuts down while paused must not leave the flag set for the next one.
void IOSTitlePause_Forget()
{
	sTitlePaused.store(false);
}
