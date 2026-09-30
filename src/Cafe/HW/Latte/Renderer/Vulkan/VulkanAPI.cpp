#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"
#define VKFUNC_DEFINE
#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"
#include <numeric> // for std::iota

#if BOOST_OS_LINUX || BOOST_OS_MACOS || BOOST_OS_BSD || BOOST_OS_IOS
#include <dlfcn.h>
#endif

#define VULKAN_API_CPU_BENCHMARK 0	// if 1, Cemu will log the CPU time spent per Vulkan API function

bool g_vulkan_available = false;

#if VULKAN_API_CPU_BENCHMARK != 0
uint64 s_vulkanBenchmarkLastResultsTime = 0;

struct VulkanBenchmarkFuncInfo
{
	std::string funcName;
	uint64 cycles;
	uint32 numCalls;
};

std::vector<VulkanBenchmarkFuncInfo*> s_vulkanBenchmarkFuncs;

template<typename TRet, typename... Args>
auto VkWrapperFuncGenTest(TRet (*func)(Args...), const char* name)
{
	static VulkanBenchmarkFuncInfo _FuncInfo;
	static auto _FuncPtrCopy = func;
	TRet (*newFunc)(Args...);
	if constexpr(std::is_void_v<TRet>)
	{
		newFunc = +[](Args... args) { uint64 t = __rdtsc(); _mm_mfence(); _FuncPtrCopy(args...); _mm_mfence(); _FuncInfo.cycles += (__rdtsc() - t); _FuncInfo.numCalls++; };
	}
	else
		newFunc = +[](Args... args) -> TRet { uint64 t = __rdtsc(); _mm_mfence(); TRet r = _FuncPtrCopy(args...); _mm_mfence(); _FuncInfo.cycles += (__rdtsc() - t); _FuncInfo.numCalls++; return r; };
	if(func && func != newFunc)
		_FuncPtrCopy = func;
	if(_FuncInfo.funcName.empty())
	{
		_FuncInfo = {.funcName = name, .cycles = 0, .numCalls = 0};
		s_vulkanBenchmarkFuncs.emplace_back(&_FuncInfo);
	}
	return newFunc;
};
#endif

// called when a TV SwapBuffers is called
void VulkanBenchmarkPrintResults()
{
#if VULKAN_API_CPU_BENCHMARK != 0
	// note: This could be done by hooking vk present functions
	uint64 currentCycle = __rdtsc();
	uint64 elapsedCycles = currentCycle - s_vulkanBenchmarkLastResultsTime;
	s_vulkanBenchmarkLastResultsTime = currentCycle;
	double elapsedCyclesDbl = (double)elapsedCycles;
	cemuLog_log(LogType::Force, "--- Vulkan API CPU benchmark ---");
	cemuLog_log(LogType::Force, "Elapsed cycles this frame: {:} | Current cycle {:} | NumFunc {:}", elapsedCycles, currentCycle, s_vulkanBenchmarkFuncs.size());

	std::vector<sint32> sortedIndices(s_vulkanBenchmarkFuncs.size());
	std::iota(sortedIndices.begin(), sortedIndices.end(), 0);
	std::sort(sortedIndices.begin(), sortedIndices.end(),
			  [](int32_t a, int32_t b) {
				  return s_vulkanBenchmarkFuncs[a]->cycles > s_vulkanBenchmarkFuncs[b]->cycles;
			  });
	for (sint32 idx : sortedIndices)
	{
		auto& func = s_vulkanBenchmarkFuncs[idx];
		if(func->cycles == 0)
			return;
		cemuLog_log(LogType::Force, "{}: {} cycles ({:.4}%) {} calls", func->funcName.c_str(), func->cycles, ((double)func->cycles / elapsedCyclesDbl) * 100.0, func->numCalls);
		func->cycles = 0;
		func->numCalls = 0;
	}
#endif
}

#if BOOST_OS_WINDOWS

bool InitializeGlobalVulkan()
{
	const auto hmodule = LoadLibraryA("vulkan-1.dll");

	if(g_vulkan_available)
		return true;

	if (hmodule == nullptr)
	{
		cemuLog_log(LogType::Force, "Vulkan loader not available. Outdated graphics driver or Vulkan runtime not installed?");
		return false;
	}

	#define VKFUNC_INIT
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"

	if(!vkEnumerateInstanceVersion)
	{
		cemuLog_log(LogType::Force, "vkEnumerateInstanceVersion not available. Outdated graphics driver or Vulkan runtime?");
		FreeLibrary(hmodule);
		return false;
	}

	g_vulkan_available = true;
	return true;
}

bool InitializeInstanceVulkan(VkInstance instance)
{
	const auto hmodule = GetModuleHandleA("vulkan-1.dll");
	if (hmodule == nullptr)
		return false;

	#define VKFUNC_INSTANCE_INIT
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"

	return true;
}

bool InitializeDeviceVulkan(VkDevice device)
{
	const auto hmodule = GetModuleHandleA("vulkan-1.dll");
	if (hmodule == nullptr)
		return false;

	#define VKFUNC_DEVICE_INIT
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"

#if VULKAN_API_CPU_BENCHMARK != 0
	#define VKFUNC_DEFINE_CUSTOM(__func) __func = VkWrapperFuncGenTest(__func, #__func)
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"
#endif

	return true;
}

#else

void* dlopen_vulkan_loader()
{
#if BOOST_OS_LINUX || BOOST_OS_BSD
	void* vulkan_so = dlopen("libvulkan.so", RTLD_NOW);
	if(!vulkan_so)
		vulkan_so = dlopen("libvulkan.so.1", RTLD_NOW);
#elif BOOST_OS_MACOS || BOOST_OS_IOS
	void* vulkan_so = nullptr;
	// MoltenVK reads its MVK_CONFIG_* settings the first time it initialises, so they have to be in
	// the environment before it is loaded. overwrite=0 lets an explicit setting from the user win.
	// Cemu samples textures through arbitrary component swizzles (Latte swizzles are free on the
	// GPU), so let MoltenVK emulate any swizzle the hardware can't do natively, instead of
	// rejecting it or silently using the identity swizzle.
	setenv("MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE", "1", 0);
	// The other MoltenVK settings, and why they are what they are (the bridge, CemuBridge.mm, sets the first three before initialising the core):
	//  MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0      vkQueueSubmit doesn't wait for Metal encoding. Cemu submits from its own render-worker thread anyway,
	//                                              so this mainly keeps pipeline compiles from stalling the submit. Not verified on device.
	//  MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE=128   Cemu's command buffer ring is larger than MoltenVK's default of 64.
	//  MVK_CONFIG_DEBUG=0                          no extra MoltenVK validation.
	//  MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS       left at MoltenVK's default (off). Cemu updates descriptor sets every draw; argument buffers
	//                                              need Tier 2 for the array sizes it uses and change shader translation, which can't be judged
	//                                              without a device run.
	//  MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS    left off: Cemu re-records command buffers constantly, pre-filling would encode twice.
	//  MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y  left alone: Cemu already handles Y with a negative-height viewport, flipping again would invert the picture.
	//  MVK_CONFIG_USE_METAL_PRIVATE_API            left off: it is the only way to get logicOp, but it calls private Metal API on iOS 27.
#if BOOST_OS_IOS
	// MuffinEMU embeds two MoltenVK builds and chooses one per launch; its bridge names the
	// chosen one here before the engine initializes.
	if (const char* chosen = getenv("MUFFIN_MOLTENVK_PATH"))
		vulkan_so = dlopen(chosen, RTLD_NOW);
#endif
	if (!vulkan_so)
		vulkan_so = dlopen("libMoltenVK.dylib", RTLD_NOW);
    if (!vulkan_so)
        vulkan_so = dlopen("MoltenVK.framework/MoltenVK", RTLD_NOW);
#endif
	return vulkan_so;
}

bool InitializeGlobalVulkan()
{
	void* vulkan_so = dlopen_vulkan_loader();

	if(g_vulkan_available)
		return true;

	if (!vulkan_so)
	{
		cemuLog_log(LogType::Force, "Vulkan loader not available.");
		return false;
	}

	#define VKFUNC_INIT
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"

	if(!vkEnumerateInstanceVersion)
	{
		cemuLog_log(LogType::Force, "vkEnumerateInstanceVersion not available. Outdated graphics driver or Vulkan runtime?");
		return false;
	}

	g_vulkan_available = true;
	return true;
}

bool InitializeInstanceVulkan(VkInstance instance)
{
	void* vulkan_so = dlopen_vulkan_loader();
	if (!vulkan_so)
		return false;

	#define VKFUNC_INSTANCE_INIT
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"
	
	return true;
}

bool InitializeDeviceVulkan(VkDevice device)
{
	void* vulkan_so = dlopen_vulkan_loader();
	if (!vulkan_so)
		return false;

	#define VKFUNC_DEVICE_INIT
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"

#if VULKAN_API_CPU_BENCHMARK != 0
	#define VKFUNC_DEFINE_CUSTOM(__func) __func = VkWrapperFuncGenTest(__func, #__func)
	#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"
#endif

	return true;
}

#endif
