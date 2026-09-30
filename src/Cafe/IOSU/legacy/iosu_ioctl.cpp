#include "Cafe/OS/common/OSCommon.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
#include "iosu_ioctl.h"
#include "util/helpers/ringbuffer.h"

#include "util/helpers/Semaphore.h"

// deprecated IOCTL handling code

RingBuffer<ioQueueEntry_t*, 256> _ioctlRingbuffer[IOS_DEVICE_COUNT];
CounterSemaphore _ioctlRingbufferSemaphore[IOS_DEVICE_COUNT];

std::mutex ioctlMutex;
// Requests a device thread has taken from a ring and not completed yet (guarded by ioctlMutex). iosuIoctl_reset() empties it, and
// a completion that arrives for an entry that is no longer in it belongs to a title that has stopped and must not be delivered:
// the entry and the thread it names live in memory that is gone.
static std::unordered_set<ioQueueEntry_t*> s_inFlight;

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
	while (true)
	{
		_ioctlRingbufferSemaphore[deviceIndex].decrementWithWait();
		// Popping is serialized with iosuIoctl_reset() (which empties the ring and the semaphore under the same mutex). A
		// wake-up whose request was dropped by a reset finds the ring empty and simply waits again.
		std::lock_guard<std::mutex> lock(ioctlMutex);
		if (_ioctlRingbuffer[deviceIndex].HasData() == false)
			continue;
		ioQueueEntry_t* entry = _ioctlRingbuffer[deviceIndex].Pop();
		s_inFlight.insert(entry);
		return entry;
	}
}

ioQueueEntry_t* iosuIoctl_getNextWithTimeout(uint32 deviceIndex, sint32 ms)
{
	if (!_ioctlRingbufferSemaphore[deviceIndex].decrementWithWaitAndTimeout(ms))
		return nullptr; // timeout or spurious wake up
	std::lock_guard<std::mutex> lock(ioctlMutex);
	if (_ioctlRingbuffer[deviceIndex].HasData() == false)
		return nullptr;
	ioQueueEntry_t* entry = _ioctlRingbuffer[deviceIndex].Pop();
	s_inFlight.insert(entry);
	return entry;
}

void iosuIoctl_completeRequest(ioQueueEntry_t* ioQueueEntry, uint32 returnValue)
{
	{
		std::lock_guard<std::mutex> lock(ioctlMutex);
		if (s_inFlight.erase(ioQueueEntry) == 0)
		{
			cemuLog_log(LogType::Force, "IOSU: dropped the completion of a request that belonged to a title that has stopped");
			return;
		}
	}
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
	s_inFlight.clear();
}

uint32 iosuIoctl_getPendingCount()
{
	std::lock_guard<std::mutex> lock(ioctlMutex);
	uint32 count = 0;
	for (sint32 i = 0; i < IOS_DEVICE_COUNT; i++)
		count += _ioctlRingbuffer[i].HasData() ? 1 : 0;
	return count + (uint32)s_inFlight.size();
}

void iosuIoctl_init()
{
	for (sint32 i = 0; i < IOS_DEVICE_COUNT; i++)
	{
		_ioctlRingbuffer[i].Clear();
	}
}
