#pragma once
#include <string>
#include "Cafe/HW/Latte/ISA/LatteReg.h"
#include "Cafe/HW/Espresso/Const.h"

namespace GX2
{
	struct GX2PerCoreCBState
	{
		uint32be* bufferPtr;
		uint32 bufferSizeInU32s;
		uint32be* currentWritePtr;
		bool isDisplayList;
	};

	extern GX2PerCoreCBState s_perCoreCBState[Espresso::CORE_COUNT];

	// The per-core command buffer state is host memory: where each core is in the buffer it is filling. A save state records it
	// next to guest memory, because the buffer's contents come back with the restore and the write position has to match them.
	struct GX2CommandStateSnapshot
	{
		struct Core
		{
			uint32 bufferPtr;
			uint32 bufferSizeInU32s;
			uint32 currentWritePtr;
			uint32 isDisplayList;
		};
		Core core[Espresso::CORE_COUNT];
	};
	void GX2CaptureCommandState(GX2CommandStateSnapshot& out);
	// Checks every pointer against guest memory first and changes nothing unless all of it is plausible.
	bool GX2RestoreCommandState(const GX2CommandStateSnapshot& in, std::string& problem);
	// After a restore, with the GPU idle: brings the counters shared with the GPU back in step with the live GPU. `report` is a log line.
	// `gpuWasNotDrained`: the caller could not get the GPU idle before the restore (it was parked on a flip), so commands it had not
	// yet read are dropped rather than run against memory that no longer holds them.
	void GX2ResyncAfterStateLoad(bool gpuWasNotDrained, std::string& report);
};

void gx2WriteGather_submitU32AsBE(uint32 v);
void gx2WriteGather_submitU32AsLE(uint32 v);
void gx2WriteGather_submitU32AsLEArray(uint32* v, uint32 numValues);

uint32 PPCInterpreter_getCurrentCoreIndex();

// gx2WriteGather_submit functions
template <typename ...Targs>
inline void gx2WriteGather_submit_(uint32 coreIndex, uint32be* writePtr)
{
	GX2::s_perCoreCBState[coreIndex].currentWritePtr = writePtr;
	cemu_assert_debug(GX2::s_perCoreCBState[coreIndex].currentWritePtr <= (GX2::s_perCoreCBState[coreIndex].bufferPtr + GX2::s_perCoreCBState[coreIndex].bufferSizeInU32s));
}

template <typename T, typename ...Targs>
inline void gx2WriteGather_submit_(uint32 coreIndex, uint32be* writePtr, const betype<T>& arg, Targs... args)
{
	static_assert(sizeof(betype<T>) == sizeof(uint32be));
	*(betype<T>*)writePtr = arg;
	writePtr++;
	gx2WriteGather_submit_(coreIndex, writePtr, args...);
}

template <typename T, typename ...Targs>
	requires std::is_floating_point_v<T>
inline
void gx2WriteGather_submit_(uint32 coreIndex, uint32be* writePtr, const T& arg, Targs... args)
{
	static_assert(sizeof(T) == sizeof(uint32));
	*writePtr = *(uint32*)&arg;
	writePtr++;
	gx2WriteGather_submit_(coreIndex, writePtr, args...);
}

template <typename T, typename ...Targs>
	requires std::is_base_of_v<Latte::LATTEREG, T>
inline
void gx2WriteGather_submit_(uint32 coreIndex, uint32be* writePtr, const T& arg, Targs... args)
{
	static_assert(sizeof(Latte::LATTEREG) == sizeof(uint32be));
	*writePtr = arg.getRawValue();
	writePtr++;
	gx2WriteGather_submit_(coreIndex, writePtr, args...);
}

template <typename T, typename ...Targs>
	requires (!std::is_base_of_v<Latte::LATTEREG, T>) && (!std::is_floating_point_v<T>)
inline
void gx2WriteGather_submit_(uint32 coreIndex, uint32be* writePtr, const T& arg, Targs... args)
{
	*writePtr = arg;
	writePtr++;
	gx2WriteGather_submit_(coreIndex, writePtr, args...);
}

template <typename ...Targs>
inline void gx2WriteGather_submit(Targs... args)
{
	uint32 coreIndex = PPCInterpreter_getCurrentCoreIndex();
	if (GX2::s_perCoreCBState[coreIndex].currentWritePtr == nullptr)
	{
		cemu_assert_suspicious(); // writing to command buffer without valid write pointer?
		return;
	}
	uint32be* writePtr = GX2::s_perCoreCBState[coreIndex].currentWritePtr;
	gx2WriteGather_submit_(coreIndex, writePtr, std::forward<Targs>(args)...);
}

namespace GX2
{
	void GX2Command_Flush(uint32 numU32sForNextBuffer, bool triggerMarkerInterrupt = true);
	void GX2ReserveCmdSpace(uint32 reservedFreeSpaceInU32);

	uint64 GX2GetLastSubmittedTimeStamp();
	uint64 GX2GetRetiredTimeStamp();
	bool GX2WaitTimeStamp(uint64 tsWait);

	void GX2BeginDisplayList(MEMPTR<void> displayListAddr, uint32 size);
	void GX2BeginDisplayListEx(MEMPTR<void> displayListAddr, uint32 size, bool profiling);
	uint32 GX2EndDisplayList(MEMPTR<void> displayListAddr);

	void GX2CallDisplayList(MPTR addr, uint32 size);
	void GX2DirectCallDisplayList(void* addr, uint32 size);

	bool GX2GetDisplayListWriteStatus();

    void GX2CommandInit();
	void GX2Init_commandBufferPool(void* bufferBase, uint32 bufferSize);
	void GX2Shutdown_commandBufferPool();
    void GX2CommandResetToDefaultState();
}
