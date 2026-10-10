#include "Cafe/HW/Latte/Renderer/Metal/MetalBufferAllocator.h"
#include "Cemu/Logging/CemuLogging.h"
#include <chrono>

MetalBufferChunkedHeap::~MetalBufferChunkedHeap()
{
	for (auto& chunk : m_chunkBuffers)
		chunk->release();
}

uint32 MetalBufferChunkedHeap::allocateNewChunk(uint32 chunkIndex, uint32 minimumAllocationSize)
{
	size_t allocationSize = std::max<size_t>(m_minimumBufferAllocationSize, minimumAllocationSize);
	MTL::Buffer* buffer = m_mtlr->GetDevice()->newBuffer(allocationSize, m_options);
	if (!buffer)
	{
		// Report the failure; a zero chunk size tells ChunkedHeap it could not grow.
		uint32 numChunks = 0;
		size_t totalSize = 0, freeSize = 0;
		GetStats(numChunks, totalSize, freeSize);
		cemuLog_log(LogType::Force,
			"Metal: buffer allocation failed, wanted {} bytes (minimum {}); {} chunks, {} MB total, {} MB free",
			allocationSize, minimumAllocationSize, numChunks, totalSize / (1024 * 1024), freeSize / (1024 * 1024));
		return 0;
	}
	cemu_assert_debug(m_chunkBuffers.size() == chunkIndex);
	m_chunkBuffers.emplace_back(buffer);

	return allocationSize;
}

void MetalSynchronizedRingAllocator::addUploadBufferSyncPoint(AllocatorBuffer_t& buffer, uint32 offset)
{
	auto commandBuffer = m_mtlr->GetCurrentCommandBuffer();
	if (!buffer.queue_syncPoints.empty() && buffer.queue_syncPoints.back().commandBuffer == commandBuffer)
		return;
	buffer.queue_syncPoints.emplace(commandBuffer, offset);
}

#if BOOST_OS_IOS
// Defined in CemuBridge.mm: writes where the address space and the footprint stand into the crash log.
void IOSBridge_LogAllocationFailure(const char* what, uint64 wantedBytes);
#endif

void MetalSynchronizedRingAllocator::allocateAdditionalUploadBuffer(uint32 sizeRequiredForAlloc)
{
	// After a failure the device keeps refusing for a while (the log showed over a thousand failed attempts in
	// 0.3 s, one per skipped upload, each trying six sizes). Until the pause ends, a request at least as large
	// as the one that failed is refused without asking again; a smaller one still gets its chance below.
	const auto now = std::chrono::steady_clock::now();
	if (m_consecutiveFailures > 0 && now < m_retryNotBefore && sizeRequiredForAlloc >= m_failedRequiredSize)
	{
		m_skippedWhilePaused++;
		return;
	}

	// calculate buffer size, should be a multiple of bufferAllocSize that is at least as large as sizeRequiredForAlloc
	uint32 bufferAllocSize = m_minimumBufferAllocSize;
	while (bufferAllocSize < sizeRequiredForAlloc)
		bufferAllocSize += m_minimumBufferAllocSize;

	MTL::Buffer* mtlBuffer = m_mtlr->GetDevice()->newBuffer(bufferAllocSize, m_options);
	// When the usual chunk (a multiple of the minimum size) cannot be had, settle for less: halve the request
	// down to what this allocation needs, rounded to 1 MB, before giving up.
	uint32 attemptSize = bufferAllocSize;
	uint32 lastTried = bufferAllocSize;
	while (!mtlBuffer && attemptSize > sizeRequiredForAlloc)
	{
		const uint32 previousAttemptSize = attemptSize;
		attemptSize = std::max<uint32>(sizeRequiredForAlloc, attemptSize / 2);
		attemptSize = (attemptSize + 0xFFFFF) & ~0xFFFFFu;
		if (attemptSize < sizeRequiredForAlloc)
			attemptSize = sizeRequiredForAlloc;
		// Rounding up to 1 MB can land on the size that just failed (a request below 1 MB, at 1 MB): nothing
		// smaller is left to try, and without this the loop retried that size for as long as memory stayed short.
		if (attemptSize >= previousAttemptSize)
			break;
		mtlBuffer = m_mtlr->GetDevice()->newBuffer(attemptSize, m_options);
		lastTried = attemptSize;
		if (attemptSize <= sizeRequiredForAlloc)
			break;
	}
	if (mtlBuffer)
		bufferAllocSize = attemptSize;
	// A small request must not fail because a 1 MB chunk cannot be had (16-byte mip levels were being skipped):
	// keep halving, in 16 KB steps, down to what the request needs.
	if (!mtlBuffer)
	{
		const uint32 floorSize = std::max<uint32>(0x4000, (sizeRequiredForAlloc + 0x3FFF) & ~0x3FFFu);
		uint32 smallSize = lastTried;
		while (!mtlBuffer && smallSize > floorSize)
		{
			smallSize = std::max<uint32>(floorSize, ((smallSize / 2) + 0x3FFF) & ~0x3FFFu);
			mtlBuffer = m_mtlr->GetDevice()->newBuffer(smallSize, m_options);
		}
		if (mtlBuffer)
			bufferAllocSize = smallSize;
	}
	if (!mtlBuffer)
	{
		// Out of memory: leave the list alone so AllocateBufferMemory() reports the failure, and ask the GPU
		// thread to drop unused textures at the end of the frame. The upload that needed this is skipped.
		static uint32 s_failures = 0;
		if (s_failures++ < 8 || (s_failures % 500) == 0)
			cemuLog_log(LogType::Force, "Metal: staging buffer allocation failed, wanted {} bytes ({} failures so far, {} requests refused during the pauses)", bufferAllocSize, s_failures, m_skippedWhilePaused);
#if BOOST_OS_IOS
		if (s_failures <= 3)
			IOSBridge_LogAllocationFailure("Metal staging buffer", bufferAllocSize);
#endif
		// pause: 250 ms, doubling for every failure in a row up to 2 s (about 15 to 120 frames at 60 fps)
		m_consecutiveFailures = std::min<uint32>(m_consecutiveFailures + 1, 16);
		m_failedRequiredSize = sizeRequiredForAlloc;
		m_retryNotBefore = now + std::chrono::milliseconds(std::min<uint32>(2000, 250u << std::min<uint32>(m_consecutiveFailures - 1, 3)));
		LatteWait::Get().evictionRequested.store(true);
		return;
	}
	m_consecutiveFailures = 0;

	AllocatorBuffer_t newBuffer{};
	newBuffer.writeIndex = 0;
	newBuffer.basePtr = nullptr;
	newBuffer.mtlBuffer = mtlBuffer;
	newBuffer.basePtr = (uint8*)newBuffer.mtlBuffer->contents();
	newBuffer.size = bufferAllocSize;
	newBuffer.index = (uint32)m_buffers.size();
	m_buffers.push_back(newBuffer);
}

MetalSynchronizedRingAllocator::AllocatorReservation_t MetalSynchronizedRingAllocator::AllocateBufferMemory(uint32 size, uint32 alignment)
{
	if (alignment < 128)
		alignment = 128;
	size = (size + 127) & ~127;

	for (auto& itr : m_buffers)
	{
		// align pointer
		uint32 alignmentPadding = (alignment - (itr.writeIndex % alignment)) % alignment;
		uint32 distanceToSyncPoint;
		if (!itr.queue_syncPoints.empty())
		{
			if (itr.queue_syncPoints.front().offset < itr.writeIndex)
				distanceToSyncPoint = 0xFFFFFFFF;
			else
				distanceToSyncPoint = itr.queue_syncPoints.front().offset - itr.writeIndex;
		}
		else
			distanceToSyncPoint = 0xFFFFFFFF;
		uint32 spaceNeeded = alignmentPadding + size;
		if (spaceNeeded > distanceToSyncPoint)
			continue; // not enough space in current buffer
		if ((itr.writeIndex + spaceNeeded) > itr.size)
		{
			// wrap-around
			spaceNeeded = size;
			alignmentPadding = 0;
			// check if there is enough space in current buffer after wrap-around
			if (!itr.queue_syncPoints.empty())
			{
				distanceToSyncPoint = itr.queue_syncPoints.front().offset - 0;
				if (spaceNeeded > distanceToSyncPoint)
					continue;
			}
			else if (spaceNeeded > itr.size)
				continue;
			itr.writeIndex = 0;
		}
		addUploadBufferSyncPoint(itr, itr.writeIndex);
		itr.writeIndex += alignmentPadding;
		uint32 offset = itr.writeIndex;
		itr.writeIndex += size;
		itr.cleanupCounter = 0;
		MetalSynchronizedRingAllocator::AllocatorReservation_t res;
		res.mtlBuffer = itr.mtlBuffer;
		res.memPtr = itr.basePtr + offset;
		res.bufferOffset = offset;
		res.size = size;
		res.bufferIndex = itr.index;

		return res;
	}

	// allocate new buffer
	size_t bufferCountBefore = m_buffers.size();
	allocateAdditionalUploadBuffer(size);
	if (m_buffers.size() == bufferCountBefore && releaseIdleBuffers())
	{
		// The device refused a new buffer. The ring keeps idle buffers around for a thousand cleanups; give those
		// back now and try once more, instead of skipping an upload while memory sits unused in the ring.
		bufferCountBefore = m_buffers.size();
		m_consecutiveFailures = 0; // memory was just given back: the pause must not swallow this retry
		allocateAdditionalUploadBuffer(size);
	}
	if (m_buffers.size() == bufferCountBefore)
	{
		// The heap could not grow; return an empty reservation (null mtlBuffer) rather than recurse.
		cemuLog_logOnce(LogType::Force, "Metal: could not reserve {} bytes of staging memory (alignment {})", size, alignment);
		return AllocatorReservation_t{};
	}

	return AllocateBufferMemory(size, alignment);
}

void MetalSynchronizedRingAllocator::FlushReservation(AllocatorReservation_t& uploadReservation)
{
    if (RequiresFlush())
    {
        uploadReservation.mtlBuffer->didModifyRange(NS::Range(uploadReservation.bufferOffset, uploadReservation.size));
    }
}

// Releases every buffer no command buffer is using any more. Only called when the device has just refused a new
// buffer; a buffer with a pending sync point (including one handed out in the command buffer being recorded) stays.
bool MetalSynchronizedRingAllocator::releaseIdleBuffers()
{
	bool releasedAny = false;
	for (sint32 i = (sint32)m_buffers.size() - 1; i >= 0; i--)
	{
		if (!m_buffers[i].queue_syncPoints.empty())
			continue;
		m_buffers[i].mtlBuffer->release();
		m_buffers.erase(m_buffers.begin() + i);
		for (size_t j = (size_t)i; j < m_buffers.size(); j++)
			m_buffers[j].index = (uint32)j;
		releasedAny = true;
	}
	return releasedAny;
}

void MetalSynchronizedRingAllocator::CleanupBuffer(MTL::CommandBuffer* latestFinishedCommandBuffer)
{
	for (auto& itr : m_buffers)
	{
		while (!itr.queue_syncPoints.empty() && latestFinishedCommandBuffer == itr.queue_syncPoints.front().commandBuffer)
		{
			itr.queue_syncPoints.pop();
		}
		if (itr.queue_syncPoints.empty())
			itr.cleanupCounter++;
	}

	// Check every buffer, from the back so erasing keeps earlier indices valid.
	for (sint32 i = (sint32)m_buffers.size() - 1; i >= 0 && m_buffers.size() > 1; i--)
	{
		auto& buffer = m_buffers[i];
		if (buffer.cleanupCounter >= 1000)
		{
			buffer.mtlBuffer->release();
			m_buffers.erase(m_buffers.begin() + i);
			// .index must stay equal to the position in m_buffers, so renumber the following buffers.
			for (size_t j = (size_t)i; j < m_buffers.size(); j++)
				m_buffers[j].index = (uint32)j;
		}
	}
}

MTL::Buffer* MetalSynchronizedRingAllocator::GetBufferByIndex(uint32 index) const
{
	return m_buffers[index].mtlBuffer;
}

void MetalSynchronizedRingAllocator::GetStats(uint32& numBuffers, size_t& totalBufferSize, size_t& freeBufferSize) const
{
	numBuffers = (uint32)m_buffers.size();
	totalBufferSize = 0;
	freeBufferSize = 0;
	for (auto& itr : m_buffers)
	{
		totalBufferSize += itr.size;
		// calculate free space in buffer
		uint32 distanceToSyncPoint;
		if (!itr.queue_syncPoints.empty())
		{
			if (itr.queue_syncPoints.front().offset < itr.writeIndex)
				distanceToSyncPoint = (itr.size - itr.writeIndex) + itr.queue_syncPoints.front().offset; // size with wrap-around
			else
				distanceToSyncPoint = itr.queue_syncPoints.front().offset - itr.writeIndex;
		}
		else
			distanceToSyncPoint = itr.size;
		freeBufferSize += distanceToSyncPoint;
	}
}

/* MetalSynchronizedHeapAllocator */

MetalSynchronizedHeapAllocator::AllocatorReservation* MetalSynchronizedHeapAllocator::AllocateBufferMemory(uint32 size, uint32 alignment)
{
	CHAddr addr = m_chunkedHeap.alloc(size, alignment);
	if (!addr.isValid() || !m_chunkedHeap.GetChunkPtr(addr.chunkIndex))
	{
		// Out of memory. GetBufferByIndex() below would index m_chunkBuffers with
		// 0xFFFFFFFF and memPtr would be an offset from nullptr, so hand back nothing
		// and let the caller skip the work. Callers of this function all treat a null
		// reservation as "not bound".
		cemuLog_logOnce(LogType::Force, "Metal: could not reserve {} bytes of buffer memory (alignment {})", size, alignment);
		return nullptr;
	}
	m_activeAllocations.emplace_back(addr);
	AllocatorReservation* res = m_poolAllocatorReservation.allocObj();
	res->bufferIndex = addr.chunkIndex;
	res->bufferOffset = addr.offset;
	res->size = size;
	res->mtlBuffer = m_chunkedHeap.GetBufferByIndex(addr.chunkIndex);
	res->memPtr = m_chunkedHeap.GetChunkPtr(addr.chunkIndex) + addr.offset;

	return res;
}

void MetalSynchronizedHeapAllocator::FreeReservation(AllocatorReservation* uploadReservation)
{
	// put the allocation on a delayed release queue for the current command buffer
	// Never key the release on a command buffer that has already finished and been released: the entry would
	// never be processed (a leak), or be hit by a new command buffer that reuses the address.
	MTL::CommandBuffer* currentCommandBuffer = m_mtlr->GetCommandBufferToRetireOn();
	auto it = std::find_if(m_activeAllocations.begin(), m_activeAllocations.end(), [&uploadReservation](const TrackedAllocation& allocation) { return allocation.allocation.chunkIndex == uploadReservation->bufferIndex && allocation.allocation.offset == uploadReservation->bufferOffset; });
	if (it == m_activeAllocations.end())
	{
		// cemu_assert_debug() alone is a no-op in Release, and the two lines below
		// dereferenced end() unconditionally - a real double-free crash (confirmed on
		// device, signal 11 in this exact function). Skip the bookkeeping instead.
		cemuLog_log(LogType::Force,
			"MetalSynchronizedHeapAllocator::FreeReservation() called on an allocation "
			"(buffer {}, offset {}) this allocator has no record of - likely a double "
			"free. Skipping it rather than dereferencing an invalid iterator.",
			uploadReservation->bufferIndex, uploadReservation->bufferOffset);
		// Not returned to the pool: it was already, and pushing it a second time would hand the same object to
		// two different allocations later.
		return;
	}
	if (currentCommandBuffer)
		m_releaseQueue[currentCommandBuffer].emplace_back(it->allocation);
	else
		m_chunkedHeap.free(it->allocation);
	m_activeAllocations.erase(it);
	m_poolAllocatorReservation.freeObj(uploadReservation);
}

void MetalSynchronizedHeapAllocator::FlushReservation(AllocatorReservation* uploadReservation)
{
	if (m_chunkedHeap.RequiresFlush())
	{
	    uploadReservation->mtlBuffer->didModifyRange(NS::Range(uploadReservation->bufferOffset, uploadReservation->size));
	}
}

void MetalSynchronizedHeapAllocator::CleanupBuffer(MTL::CommandBuffer* latestFinishedCommandBuffer)
{
    auto it = m_releaseQueue.find(latestFinishedCommandBuffer);
    if (it == m_releaseQueue.end())
        return;

    // release allocations
	for (auto& addr : it->second)
		m_chunkedHeap.free(addr);
	m_releaseQueue.erase(it);
}

void MetalSynchronizedHeapAllocator::GetStats(uint32& numBuffers, size_t& totalBufferSize, size_t& freeBufferSize) const
{
	m_chunkedHeap.GetStats(numBuffers, totalBufferSize, freeBufferSize);
}
