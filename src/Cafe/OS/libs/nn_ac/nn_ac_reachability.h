#pragma once

// Host-device network reachability, as seen by the emulated nn_ac library.
// Thread-safe (single relaxed atomic); safe to call from any thread.
namespace nn_ac
{
	void SetDeviceReachable(bool reachable);
	bool IsDeviceReachable();
	// the console is connected exactly when the device has a network path
	bool IsConsoleConnected();
}
