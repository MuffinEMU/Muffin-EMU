#include "Cafe/OS/common/OSCommon.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
#include "iosu_ioctl.h"
#include "util/helpers/ringbuffer.h"

#include "util/helpers/Semaphore.h"

// deprecated IOCTL handling code

RingBuffer<ioQueueEntry_t*, 256> _ioctlRingbuffer[IOS_DEVICE_COUNT];
CounterSemaphore _ioctlRingbufferSemaphore[IOS_DEVICE_COUNT];

std::mutex ioctlMutex;

sint32 iosuIoctl_pushAndWait(uint32 ioctlHandle, ioQueueEntry_t* ioQueueEntry)
{
	if (ioctlHandle != IOS_DEVICE_ACT && ioctlHandle != IOS_DEVICE_ACP_MAIN && ioctlHandle != IOS_DEVICE_MCP && ioctlHandle != IOS_DEVICE_BOSS && ioctlHandle != IOS_DEVICE_NIM && ioctlHandle != IOS_DEVICE_FPD)
	{
		cemuLog_logDebug(LogType::Force, "Unsupported IOSU device {}", ioctlHandle);
		cemu_assert_debug(false);
		return 0;
	}
	__OSLockScheduler();
	ioctlMutex.lock();
	ioQueueEntry->ppcThread = coreinit::OSGetCurrentThread();
	
	_ioctlRingbuffer[ioctlHandle].Push(ioQueueEntry);
	ioctlMutex.unlock();
	_ioctlRingbufferSemaphore[ioctlHandle].increment();
	coreinit::__OSSuspendThreadInternal(coreinit::OSGetCurrentThread());
	if (ioQueueEntry->isCompleted == false)
		assert_dbg();
	__OSUnlockScheduler();
	return ioQueueEntry->returnValue;
}

ioQueueEntry_t* iosuIoctl_getNextWithWait(uint32 deviceIndex)
{
	_ioctlRingbufferSemaphore[deviceIndex].decrementWithWait();
	if (_ioctlRingbuffer[deviceIndex].HasData() == false)
		assert_dbg();
	return _ioctlRingbuffer[deviceIndex].Pop();
}

ioQueueEntry_t* iosuIoctl_getNextWithTimeout(uint32 deviceIndex, sint32 ms)
{
	if (!_ioctlRingbufferSemaphore[deviceIndex].decrementWithWaitAndTimeout(ms))
		return nullptr; // timeout or spurious wake up
	if (_ioctlRingbuffer[deviceIndex].HasData() == false)
		return nullptr;
	return _ioctlRingbuffer[deviceIndex].Pop();
}

void iosuIoctl_completeRequest(ioQueueEntry_t* ioQueueEntry, uint32 returnValue)
{
	ioQueueEntry->returnValue = returnValue;
	ioQueueEntry->isCompleted = true;
	coreinit::OSResumeThread(ioQueueEntry->ppcThread);
}

// Drops requests that were queued for a stopped title and not yet picked up: the entries live on that title's stack, so
// handing one to a device thread after its memory is gone would write to unmapped memory. A request a device thread is
// already working on cannot be recalled here.
void iosuIoctl_reset()
{
	std::lock_guard<std::mutex> lock(ioctlMutex);
	for (sint32 i = 0; i < IOS_DEVICE_COUNT; i++)
	{
		_ioctlRingbuffer[i].Clear();
		_ioctlRingbufferSemaphore[i].reset();
	}
}

uint32 iosuIoctl_getPendingCount()
{
	std::lock_guard<std::mutex> lock(ioctlMutex);
	uint32 count = 0;
	for (sint32 i = 0; i < IOS_DEVICE_COUNT; i++)
		count += _ioctlRingbuffer[i].HasData() ? 1 : 0;
	return count;
}

void iosuIoctl_init()
{
	for (sint32 i = 0; i < IOS_DEVICE_COUNT; i++)
	{
		_ioctlRingbuffer[i].Clear();
	}
}
