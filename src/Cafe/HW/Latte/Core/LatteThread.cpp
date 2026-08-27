#include "Cafe/HW/Latte/ISA/RegDefines.h"
#include "Cafe/OS/libs/gx2/GX2.h" // todo - remove dependency
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Core/LatteDraw.h"
#include "Cafe/HW/Latte/Core/LatteShader.h"
#include "Cafe/HW/Latte/Core/LatteAsyncCommands.h"
#include "Cafe/GameProfile/GameProfile.h"
#include "Cafe/GraphicPack/GraphicPack2.h"
#include "WindowSystem.h"

#include "Cafe/HW/Latte/Core/LatteBufferCache.h"

#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cafe/HW/Latte/Core/LatteTexture.h"
#include "util/helpers/helpers.h"

#include <imgui.h>
#include "config/ActiveSettings.h"

#include "Cafe/CafeSystem.h"

LatteGPUState_t LatteGPUState = {};

std::atomic_bool sLatteThreadRunning = false;
std::atomic_bool sLatteThreadFinishedInit = false;

void LatteThread_Exit();

void Latte_LoadInitialRegisters()
{
	LatteGPUState.contextNew.CB_TARGET_MASK.set_MASK(0xFFFFFFFF);
	LatteGPUState.contextNew.VGT_MULTI_PRIM_IB_RESET_INDX.set_RESTART_INDEX(0xFFFFFFFF);
	LatteGPUState.contextNew.VGT_DMA_NUM_INSTANCES.set_NUM_INSTANCES(1);
	LatteGPUState.contextRegister[Latte::REGADDR::PA_CL_CLIP_CNTL] = 0;
	*(float*)&LatteGPUState.contextRegister[mmDB_DEPTH_CLEAR] = 1.0f;
}

extern bool gx2WriteGatherInited;

LatteTextureView* osScreenTVTex[2] = { nullptr };
LatteTextureView* osScreenDRCTex[2] = { nullptr };

LatteTextureView* LatteHandleOSScreen_getOrCreateScreenTex(MPTR physAddress, uint32 width, uint32 height, uint32 pitch)
{
	LatteTextureView* texView = LatteTextureViewLookupCache::lookup(physAddress, width, height, 1, pitch, 0, 1, 0, 1, Latte::E_GX2SURFFMT::R8_G8_B8_A8_UNORM, Latte::E_DIM::DIM_2D);
	if (texView)
		return texView;
	return LatteTexture_CreateTexture(Latte::E_DIM::DIM_2D, physAddress, 0, Latte::E_GX2SURFFMT::R8_G8_B8_A8_UNORM, width, height, 1, pitch, 1, 0, Latte::E_HWTILEMODE::TM_LINEAR_ALIGNED, false);
}

void LatteHandleOSScreen_prepareTextures()
{
	osScreenTVTex[0] = LatteHandleOSScreen_getOrCreateScreenTex(LatteGPUState.osScreen.screen[0].physPtr, 1280, 720, 1280);
	osScreenTVTex[1] = LatteHandleOSScreen_getOrCreateScreenTex(LatteGPUState.osScreen.screen[0].physPtr + 1280 * 720 * 4, 1280, 720, 1280);
	osScreenDRCTex[0] = LatteHandleOSScreen_getOrCreateScreenTex(LatteGPUState.osScreen.screen[1].physPtr, 854, 480, 0x380);
	osScreenDRCTex[1] = LatteHandleOSScreen_getOrCreateScreenTex(LatteGPUState.osScreen.screen[1].physPtr + 896 * 480 * 4, 854, 480, 0x380);
}

void LatteRenderTarget_copyToBackbuffer(LatteTextureView* textureView, bool isPadView);

bool LatteHandleOSScreen_TV()
{
	if (!LatteGPUState.osScreen.screen[0].isEnabled)
		return false;
	if (LatteGPUState.osScreen.screen[0].flipExecuteCount == LatteGPUState.osScreen.screen[0].flipRequestCount)
		return false;
	LatteHandleOSScreen_prepareTextures();

	sint32 bufferDisplayTV = (LatteGPUState.osScreen.screen[0].flipRequestCount & 1) ^ 1;
	sint32 bufferDisplayDRC = (LatteGPUState.osScreen.screen[1].flipRequestCount & 1) ^ 1;

	const uint32 bufferIndexTV = (bufferDisplayTV);
	const uint32 bufferIndexDRC = bufferDisplayDRC;

	LatteTexture_ReloadData(osScreenTVTex[bufferIndexTV]->baseTexture);

	// TV screen
	LatteRenderTarget_copyToBackbuffer(osScreenTVTex[bufferIndexTV]->baseTexture->baseView, false);
	
	if (LatteGPUState.osScreen.screen[0].flipExecuteCount != LatteGPUState.osScreen.screen[0].flipRequestCount)
		LatteGPUState.osScreen.screen[0].flipExecuteCount.store(LatteGPUState.osScreen.screen[0].flipRequestCount);
	return true;
}

bool LatteHandleOSScreen_DRC()
{
	if (!LatteGPUState.osScreen.screen[1].isEnabled)
		return false;
	if (LatteGPUState.osScreen.screen[1].flipExecuteCount == LatteGPUState.osScreen.screen[1].flipRequestCount)
		return false;
	LatteHandleOSScreen_prepareTextures();

	sint32 bufferDisplayDRC = (LatteGPUState.osScreen.screen[1].flipRequestCount & 1) ^ 1;

	const uint32 bufferIndexDRC = bufferDisplayDRC;

	LatteTexture_ReloadData(osScreenDRCTex[bufferIndexDRC]->baseTexture);

	// GamePad screen
	LatteRenderTarget_copyToBackbuffer(osScreenDRCTex[bufferIndexDRC]->baseTexture->baseView, true);

	if (LatteGPUState.osScreen.screen[1].flipExecuteCount != LatteGPUState.osScreen.screen[1].flipRequestCount)
		LatteGPUState.osScreen.screen[1].flipExecuteCount.store(LatteGPUState.osScreen.screen[1].flipRequestCount);
	return true;
}

// Counts OSScreen scanouts. The heartbeat below reads this to tell whether
// anything is still reaching the display during the pre-GX2Init phase.
std::atomic<uint64> sOSScreenSwapCount = 0;

void LatteThread_HandleOSScreen()
{
	bool swapTV = LatteHandleOSScreen_TV();
	bool swapDRC = LatteHandleOSScreen_DRC();
	if(swapTV || swapDRC)
	{
		sOSScreenSwapCount++;
		g_renderer->SwapBuffers(swapTV, swapDRC);
	}
}

// Progress heartbeat.
//
// Deliberately on its own thread rather than in the frame path. A title that
// freezes after presenting one frame never swaps again, so a counter living in
// the swap path goes silent at exactly the moment it is needed and reports a
// freeze as an absence of output - which is indistinguishable from a log that
// simply ended. This thread keeps printing regardless of what the emulated CPU
// or GPU are doing, so the log itself separates the two failure modes:
//
//   GX2 frames climbing slowly   -> running past the first frame, just slow
//   GX2 frames pinned, GX2Init reached -> stalled after handing over to GX2
//   GX2Init never reached, OSScreen/flips climbing -> still in OSScreen boot
//   every counter frozen         -> a real deadlock, not slowness
//
// This matters most under the forced interpreter, where "slow enough to look
// hung" is the expected case and cannot otherwise be told apart from hung.
std::thread sLatteHeartbeatThread;
std::atomic_bool sLatteHeartbeatRunning = false;

void LatteThread_HeartbeatEntry()
{
	SetThreadName("LatteHeartbeat");
	const auto startTime = std::chrono::steady_clock::now();
	auto lastTime = startTime;
	uint64 lastFrameCount = 0;
	uint64 lastOSScreenCount = 0;
	uint32 lastFlipRequestCount = 0;
	while (sLatteHeartbeatRunning)
	{
		std::this_thread::sleep_for(std::chrono::milliseconds(250));
		const auto now = std::chrono::steady_clock::now();
		if (now - lastTime < std::chrono::seconds(3))
			continue;
		const double windowSeconds = std::chrono::duration<double>(now - lastTime).count();
		const uint64 frameCount = LatteGPUState.frameCounter;
		const uint64 osScreenCount = sOSScreenSwapCount.load();
		// Written by the emulated CPU, so it moving while nothing else does means the
		// guest is alive and the stall is on our side, not the title's.
		const uint32 flipRequestCount = LatteGPUState.osScreen.screen[0].flipRequestCount;
		cemuLog_log(LogType::Force,
			"Heartbeat: {:.1f}s - GX2Init {}, GX2 frames {} (+{}, {:.2f} fps), OSScreen scanouts {} (+{}), guest flip requests {} (+{})",
			std::chrono::duration<double>(now - startTime).count(),
			LatteGPUState.gx2InitCalled ? "reached" : "NOT reached",
			frameCount, frameCount - lastFrameCount,
			(double)(frameCount - lastFrameCount) / windowSeconds,
			osScreenCount, osScreenCount - lastOSScreenCount,
			flipRequestCount, flipRequestCount - lastFlipRequestCount);
		lastFrameCount = frameCount;
		lastOSScreenCount = osScreenCount;
		lastFlipRequestCount = flipRequestCount;
		lastTime = now;
	}
}

int Latte_ThreadEntry()
{
	SetThreadName("LatteThread");

	// g_renderer can be null here if construction failed (confirmed possible via a
	// live device crash inside MetalRenderer::MetalRenderer() - now caught with
	// @try/@catch at the iOS bridge call sites rather than left to crash the whole
	// app, since M2's actual exit criteria is the interpreter/OS-HLE stack, not
	// working rendering - that's the separate M3 milestone). Two different callers
	// spin-wait on this thread signaling completion before they proceed
	// (Latte_Start()'s own `while (!sLatteThreadFinishedInit)`, and separately
	// PrepareExecutable()'s `while (g_isGPUInitFinished == false)`) - so without a
	// renderer, this must still signal both flags immediately and return, rather
	// than dereference g_renderer or simply bail without signaling and leave the
	// callers hanging in yet another indefinite freeze.
	if (!g_renderer)
	{
		sLatteThreadFinishedInit = true;
		g_isGPUInitFinished = true;
		return 0;
	}

	sint32 w,h;
	WindowSystem::GetWindowPhysSize(w,h);

	// renderer
	g_renderer->Initialize();
	RendererOutputShader::InitializeStatic();

	LatteTiming_Init();
	LatteTexture_init();
	LatteTC_Init();
	LatteBufferCache_init(164 * 1024 * 1024);
	LatteQuery_Init();
	LatteSHRC_Init();
	LatteStreamout_InitCache();

	g_renderer->renderTarget_setViewport(0, 0, w, h, 0.0f, 1.0f);
	
	// enable GLSL gl_PointSize support
	// glEnable(GL_PROGRAM_POINT_SIZE); // breaks shader caching on AMD (as of 2018)
	
	LatteGPUState.glVendor = GLVENDOR_UNKNOWN;
	switch(g_renderer->GetVendor())
	{
	case GfxVendor::AMD: 
		LatteGPUState.glVendor = GLVENDOR_AMD;
		break;
	case GfxVendor::Intel:
		LatteGPUState.glVendor = GLVENDOR_INTEL; 
		break;
	case GfxVendor::Nvidia: 
		LatteGPUState.glVendor = GLVENDOR_NVIDIA; 
		break;
	case GfxVendor::Apple:
		LatteGPUState.glVendor = GLVENDOR_APPLE;
	default:
		break;
	}

	sLatteThreadFinishedInit = true;

	// register debug handler
	if (cemuLog_isLoggingEnabled(LogType::OpenGLLogging))
		g_renderer->EnableDebugMode();

	// wait till a game is started
	while( true )
	{
		if( CafeSystem::IsTitleRunning() )
			break;

		g_renderer->DrawEmptyFrame(true);
		g_renderer->DrawEmptyFrame(false);
		g_renderer->CancelScreenshotRequest(); // keep the screenshot request queue empty
		std::this_thread::sleep_for(std::chrono::milliseconds(1000/60));
	}

	g_renderer->DrawEmptyFrame(true);

	// before doing anything with game specific shaders, we need to wait for graphic packs to finish loading
	GraphicPack2::WaitUntilReady();
	cemuLog_log(LogType::Force, "LatteThread: graphic packs ready");
	// if legacy packs are enabled we cannot use the colorbuffer resolution optimization
	LatteGPUState.allowFramebufferSizeOptimization = true;
	for(auto& pack : GraphicPack2::GetActiveGraphicPacks())
	{
		if(pack->AllowRendertargetSizeOptimization())
			continue;
		for(auto& rule : pack->GetTextureRules())
		{
			if(rule.filter_settings.width >= 0 || rule.filter_settings.height >= 0 || rule.filter_settings.depth >= 0 ||
				rule.overwrite_settings.width >= 0 || rule.overwrite_settings.height >= 0 || rule.overwrite_settings.depth >= 0)
			{
				LatteGPUState.allowFramebufferSizeOptimization = false;
				cemuLog_log(LogType::Force, "Graphic pack \"{}\" prevents rendertarget size optimization. This warning can be ignored and is intended for graphic pack developers", pack->GetName());
				break;
			}
		}
	}
	// load disk shader cache
    LatteShaderCache_Load();
	cemuLog_log(LogType::Force, "LatteThread: shader cache loaded");
	// init registers
	Latte_LoadInitialRegisters();
	// let CPU thread know the GPU is done initializing
	g_isGPUInitFinished = true;
	// Everything from DrawEmptyFrame() down to here is silent at Force level, so a
	// stall anywhere in it looks identical from a log: the empty frame stays on
	// screen and the log simply stops. These three breadcrumbs make the last line
	// printed name the stage that did not finish. This one also matters on its own
	// terms - for a title that never calls GX2Init (OSScreen-only homebrew), the
	// loop below is the only thing that ever scans OSScreen out, so "entering" it
	// is the point where such a title can first put a pixel on the display.
	cemuLog_log(LogType::Force, "LatteThread: entering the OSScreen scanout loop, waiting on GX2Init()");
	// wait until CPU has called GX2Init()
	while (LatteGPUState.gx2InitCalled == 0)
	{
		std::this_thread::yield();
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
		LatteThread_HandleOSScreen();
		if (Latte_GetStopSignal())
			LatteThread_Exit();
	}
	cemuLog_log(LogType::Force, "LatteThread: GX2Init() reached - handing over to the command ringbuffer, GX2 frames start here");
	LatteCP_ProcessRingbuffer();
	cemu_assert_debug(false); // should never reach
	return 0;
}

std::thread sLatteThread;
std::mutex sLatteThreadStateMutex;

// initializes GPU thread which in turn also activates graphic packs
// does not return until the thread finished initialization
void Latte_Start()
{
	std::unique_lock _lock(sLatteThreadStateMutex);
	cemu_assert_debug(!sLatteThreadRunning);
	sLatteThreadRunning = true;
	sLatteThreadFinishedInit = false;
	sLatteThread = std::thread(Latte_ThreadEntry);
	// Assigning over a still-joinable std::thread calls std::terminate, so make sure
	// a heartbeat left over from a previous launch is reaped before starting another.
	if (sLatteHeartbeatThread.joinable())
	{
		sLatteHeartbeatRunning = false;
		sLatteHeartbeatThread.join();
	}
	sLatteHeartbeatRunning = true;
	sLatteHeartbeatThread = std::thread(LatteThread_HeartbeatEntry);
	// wait until initialized
	while (!sLatteThreadFinishedInit)
	{
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
}

void Latte_Stop()
{
	std::unique_lock _lock(sLatteThreadStateMutex);
	if (!sLatteThreadRunning)
		return;
	sLatteThreadRunning = false;
	_lock.unlock();
	if (sLatteHeartbeatRunning)
	{
		sLatteHeartbeatRunning = false;
		if (sLatteHeartbeatThread.joinable())
			sLatteHeartbeatThread.join();
	}
	sLatteThread.join();
}

bool Latte_GetStopSignal()
{
	return !sLatteThreadRunning;
}

void LatteThread_Exit()
{
	if (g_renderer)
		g_renderer->Shutdown();
    // clean up vertex/uniform cache
    LatteBufferCache_UnloadAll();
	// clean up texture cache
	LatteTC_UnloadAllTextures();
	// clean up runtime shader cache
    LatteSHRC_UnloadAll();
    // close disk cache
    LatteShaderCache_Close();
	RendererOutputShader::ShutdownStatic();
    // destroy renderer but make sure that g_renderer remains valid until the destructor has finished
	if (g_renderer)
	{
		Renderer* renderer = g_renderer.get();
		delete renderer;
		g_renderer.release();
	}
	// reset GPU7 state
	std::memset(&LatteGPUState, 0, sizeof(LatteGPUState));
	#if BOOST_OS_WINDOWS
	ExitThread(0);
	#else
	pthread_exit(nullptr);
	#endif
	cemu_assert_unimplemented();
}
