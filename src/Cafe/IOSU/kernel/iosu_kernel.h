#pragma once
#include "Cafe/IOSU/iosu_ipc_common.h"
#include "Cafe/IOSU/iosu_types_common.h"

namespace iosu
{
	namespace kernel
	{
		using IOSMessage = uint32;

		IOSMsgQueueId IOS_CreateMessageQueue(IOSMessage* messageArray, uint32 messageCount);
		IOS_ERROR IOS_DestroyMessageQueue(IOSMsgQueueId msgQueueId);
		IOS_ERROR IOS_SendMessage(IOSMsgQueueId msgQueueId, IOSMessage message, uint32 flags);
		IOS_ERROR IOS_ReceiveMessage(IOSMsgQueueId msgQueueId, IOSMessage* messageOut, uint32 flags);

		IOS_ERROR IOS_CreateTimer(uint32 startMicroseconds, uint32 repeatMicroseconds, uint32 queueId, uint32 message);
		IOS_ERROR IOS_StopTimer(IOSTimerId timerId);
		IOS_ERROR IOS_DestroyTimer(IOSTimerId timerId);

		IOS_ERROR IOS_RegisterResourceManager(const char* devicePath, IOSMsgQueueId msgQueueId);
		IOS_ERROR IOS_DeviceAssociateId(const char* devicePath, uint32 id);
		// Frees every device handle that is open on the resource manager behind msgQueueId. The handle table is small (96 per
		// process) and a title that stops does not close its handles, so a resource manager that outlives titles has to do it
		void IOS_CloseAllHandlesForQueue(IOSMsgQueueId msgQueueId);
		IOS_ERROR IOS_ResourceReply(IPCCommandBody* cmd, IOS_ERROR result);

		void IPCSubmitFromCOS(uint32 ppcCoreIndex, IPCCommandBody* cmd);

		IOSUModule* GetModule();
	}
}