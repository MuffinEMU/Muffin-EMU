// Engine C only. The v3.8 bridge reads FPS from iosgui's IOSWindowSystem.cpp, but that file
// also defines WindowSystem::*, which MeloCafe's uikit WindowSystem.mm defines as well. With
// MeloCafe winning, iosgui's copy is out of this build. MeloCafe's WindowSystem discards
// FPS, so this reports 0; the benchmark counts frames from LatteGPUState.frameCounter.
double IOSWindowSystem_GetLastFPS()
{
	return 0.0;
}
