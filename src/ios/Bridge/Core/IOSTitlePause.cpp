// Pause and resume for a running title.
//
// The core has no pause of its own - MeloCafe's app only ever shut a title down - but
// iOS needs one: the app goes to the background, a sheet covers the game, a call comes
// in. This suspends every active guest thread under the scheduler lock and resumes them
// again, using only coreinit functions the core already exports, so the core itself is
// untouched. It is the same mechanism cemu-ios-muffin's own core used.
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
