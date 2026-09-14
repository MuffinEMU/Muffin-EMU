// CafeSystem calls back into its host through a SystemImplementation, for example to
// recreate the render canvas. Desktop Cemu's MainWindow is the only implementation there
// is, and CafeSystem dereferences it without a null check, so on iOS, where nothing
// registered one, the first request was a crash. This is the iOS implementation,
// registered by cemu_bridge_initialize().
//
// The upstream-cemu branch's version also implements CafePPCProcessExit, which only exists
// once upstream Cemu's coreinit exit() is in the core; this branch's core does not have it.
#include "Cafe/CafeSystem.h"
#include "Cemu/Logging/CemuLogging.h"

class IOSSystemImplementation final : public CafeSystem::SystemImplementation
{
public:
	void CafeRecreateCanvas() override
	{
		// The canvas is a UIView the Swift side owns for the whole title. There is nothing to
		// rebuild from here, and pretending to would detach the layer the renderer draws into.
		cemuLog_log(LogType::Force, "iOS: the core asked for the render canvas to be recreated - the UIKit surface is kept as it is");
	}
};

void IOSSystemImplementation_Install()
{
	static IOSSystemImplementation implementation;
	CafeSystem::SetImplementation(&implementation);
}
