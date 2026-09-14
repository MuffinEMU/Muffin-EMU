// CafeSystem calls back into its host through a SystemImplementation: to recreate the
// render canvas, and - since upstream Cemu's coreinit exit() - when the emulated process
// exits on its own. Desktop Cemu's MainWindow is the only implementation there is, and
// CafeSystem dereferences it without a null check, so on iOS, where nothing registered
// one, either callback was a crash waiting for the first title that triggered it. This is
// the iOS implementation, registered by cemu_bridge_initialize().
#include "Cafe/CafeSystem.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>

static std::atomic_bool sTitleExitedItself{false};
static std::atomic<sint32> sTitleExitStatus{0};

class IOSSystemImplementation final : public CafeSystem::SystemImplementation
{
public:
	void CafeRecreateCanvas() override
	{
		// The canvas is a UIView the Swift side owns for the whole title. There is nothing to
		// rebuild from here, and pretending to would detach the layer the renderer draws into.
		cemuLog_log(LogType::Force, "iOS: the core asked for the render canvas to be recreated - the UIKit surface is kept as it is");
	}

	void CafePPCProcessExit() override
	{
		const sint32 status = CafeSystem::GetForegroundTitleReturnStatus().value_or(0);
		sTitleExitStatus.store(status);
		sTitleExitedItself.store(true);
		cemuLog_log(LogType::Force, "iOS: the title exited on its own (status {})", status);
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

void IOSSystemImplementation_ResetExit()
{
	sTitleExitedItself.store(false);
	sTitleExitStatus.store(0);
}
