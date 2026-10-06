// CafeSystem calls back into its host through a SystemImplementation: to recreate the
// render canvas, and - since upstream Cemu's coreinit exit() - when the emulated process
// exits on its own. Desktop Cemu's MainWindow is the only implementation there is, and
// CafeSystem dereferences it without a null check, so on iOS, where nothing registered
// one, either callback was a crash waiting for the first title that triggered it. This is
// the iOS implementation, registered by cemu_bridge_initialize().
//
// Title switching. The Wii U Menu starts a game by calling coreinit's __LaunchByTitleId,
// which (src/Cafe/OS/libs/coreinit/coreinit_Misc.cpp, OSLauncherThread) runs on a helper
// thread: ShutdownTitle() -> PrepareForegroundTitle() -> RequestRecreateCanvas() ->
// LaunchForegroundTitle(). Desktop Cemu answers RequestRecreateCanvas by destroying its
// canvas and creating a new one on the UI thread, blocking the launcher until that is
// done; creating the canvas is also what builds the renderer again, because ShutdownTitle()
// stops the GPU thread and the GPU thread's exit destroys g_renderer. The iOS equivalent is
// IOSBridge_RecreateRenderSurface() (CemuBridge.mm): rebuild the renderer and re-initialize
// the layers on the main thread and wait. The UIKit view itself stays - Swift owns it for
// the whole session, exactly as it is kept between two ordinary launches.
#include "Cafe/CafeSystem.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>

// Defined in CemuBridge.mm (plain C++ linkage). Blocks until the renderer and layers exist.
bool IOSBridge_RecreateRenderSurface();
// Defined in CemuBridge.mm: lets the app apply the per-game settings of the title the Wii U Menu is switching to.
void IOSBridge_TitleSwitching(uint64 titleId);

static std::atomic_bool sTitleExitedItself{false};
static std::atomic<sint32> sTitleExitStatus{0};
static std::atomic_bool sTitleSwitchFailed{false};
static std::atomic_bool sSystemAppletRequested{false};

// Defined in sysapp.cpp
bool _SYSIsSystemApplicationTitleId(uint64 titleId);

class IOSSystemImplementation final : public CafeSystem::SystemImplementation
{
public:
	void CafeRecreateCanvas() override
	{
		cemuLog_log(LogType::Force, "iOS: title switch - rebuilding the renderer on the existing UIKit surface");
		if (!IOSBridge_RecreateRenderSurface())
			cemuLog_log(LogType::Force, "iOS: title switch - the renderer could not be rebuilt, the next title may not draw");
	}

	void CafePPCProcessExit() override
	{
		// The switch itself never reports an exit (OSLauncherThread does not call this), but a
		// stray exit from a thread of the outgoing title must not end the incoming one.
		if (CafeSystem::IsTitleSwitchInProgress())
		{
			cemuLog_log(LogType::Force, "iOS: ignoring a process exit that arrived during a title switch");
			return;
		}
		const sint32 status = CafeSystem::GetForegroundTitleReturnStatus().value_or(0);
		sTitleExitStatus.store(status);
		sTitleExitedItself.store(true);
		cemuLog_log(LogType::Force, "iOS: the title exited on its own (status {})", status);
	}

	void CafeTitleSwitching(TitleId titleId) override
	{
		IOSBridge_TitleSwitching((uint64)titleId);
	}

	void CafeTitleSwitchFailed(TitleId titleId) override
	{
		cemuLog_log(LogType::Force, "iOS: the title switch to {:016x} failed - the previous title is already shut down", (uint64)titleId);
		sTitleSwitchFailed.store(true);
		sSystemAppletRequested.store(_SYSIsSystemApplicationTitleId((uint64)titleId));
		sTitleExitStatus.store(-1);
		sTitleExitedItself.store(true);
	}
};

void IOSSystemImplementation_Install()
{
	static IOSSystemImplementation implementation;
	CafeSystem::SetImplementation(&implementation);
}

bool IOSSystemImplementation_TitleExited(int* statusOut)
{
	if (statusOut)
		*statusOut = sTitleExitStatus.load();
	return sTitleExitedItself.load();
}

// True when the last failed title switch was a request to open a Wii U system application
// (Account Settings, System Settings, ...), which MuffinEMU can't run.
bool IOSSystemImplementation_SystemAppletRequested()
{
	return sSystemAppletRequested.load();
}

bool IOSSystemImplementation_TitleSwitchFailed()
{
	return sTitleSwitchFailed.load();
}

// The core hit something it cannot continue from (out of address space for a game thread). Marks the
// title as ended so the UI stops it, with a reason (a string literal) the status text can show.
static std::atomic<const char*> sFatalReason{nullptr};

void IOSSystemImplementation_ReportFatal(const char* reason)
{
	sFatalReason.store(reason);
	sTitleExitStatus.store(-1);
	sTitleExitedItself.store(true);
}

const char* IOSSystemImplementation_FatalReason()
{
	return sFatalReason.load();
}

void IOSSystemImplementation_ResetExit()
{
	sFatalReason.store(nullptr);
	sTitleExitedItself.store(false);
	sTitleExitStatus.store(0);
	sTitleSwitchFailed.store(false);
	sSystemAppletRequested.store(false);
}
