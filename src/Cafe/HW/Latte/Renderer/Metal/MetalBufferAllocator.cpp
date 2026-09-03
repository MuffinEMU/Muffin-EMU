#include "Cafe/HW/Latte/Renderer/Metal/MetalBufferAllocator.h"
#include "Cemu/Logging/CemuLogging.h"

MetalBufferChunkedHeap::~MetalBufferChunkedHeap()
{
	for (auto& chunk : m_chunkBuffers)
		chunk->release();
}

uint32 MetalBufferChunkedHeap::allocateNewChunk(uint32 chunkIndex, uint32 minimumAllocationSize)
{
	size_t allocationSize = std::max<size_t>(m_minimumBufferAllocationSize, minimumAllocationSize);
	MTL::Buffer* buffer = m_mtlr->GetDevice()->newBuffer(allocationSize, m_options);
	cemu_assert_debug(buffer);
	cemu_assert_debug(m_chunkBuffers.size() == chunkIndex);
	m_chunkBuffers.emplace_back(buffer);

	return allocationSize;
}

void MetalSynchronizedRingAllocator::addUploadBufferSyncPoint(AllocatorBuffer_t& buffer, uint32 offset)
{
	auto commandBuffer = m_mtlr->GetCurrentCommandBuffer();
	if (commandBuffer == buffer.lastSyncpointCommandBuffer)
		return;
	buffer.lastSyncpointCommandBuffer = commandBuffer;
	buffer.queue_syncPoints.emplace(commandBuffer, offset);
}

void MetalSynchronizedRingAllocator::allocateAdditionalUploadBuffer(uint32 sizeRequiredForAlloc)
{
	// calculate buffer size, should be a multiple of bufferAllocSize that is at least as large as sizeRequiredForAlloc
	uint32 bufferAllocSize = m_minimumBufferAllocSize;
	while (bufferAllocSize < sizeRequiredForAlloc)
		bufferAllocSize += m_minimumBufferAllocSize;

	AllocatorBuffer_t newBuffer{};
	newBuffer.writeIndex = 0;
	newBuffer.basePtr = nullptr;
	newBuffer.mtlBuffer = m_mtlr->GetDevice()->newBuffer(bufferAllocSize, m_options);
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
	allocateAdditionalUploadBuffer(size);

	return AllocateBufferMemory(size, alignment);
}

void MetalSynchronizedRingAllocator::FlushReservation(AllocatorReservation_t& uploadReservation)
{
    if (RequiresFlush())
    {
        uploadReservation.mtlBuffer->didModifyRange(NS::Range(uploadReservation.bufferOffset, uploadReservation.size));
    }
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

	// Release any buffer that has gone fully idle (no pending sync points) for long
	// enough - scanning every buffer, not just m_buffers.back().
	//
	// The old code only ever inspected the last element of m_buffers and popped it
	// with pop_back() once its cleanupCounter reached the threshold. AllocateBufferMemory()
	// does a first-fit scan from the FRONT of m_buffers, so under sustained pressure
	// (e.g. the texture-upload burst during boot, where many GX2 textures are decoded
	// and staged faster than command buffers retire) new buffers get appended to the
	// back to cover the overflow while the earlier ones keep getting reused. Once the
	// burst subsides, an EARLIER buffer can go idle while whatever is currently last
	// in the vector is still in rotation - and that earlier buffer's cleanupCounter
	// climbs right alongside everyone else's (the loop above already tracks it), but
	// the release check below never looked at index i < m_buffers.size()-1. Worse,
	// even a buffer that legitimately becomes "the last one" and starts accumulating
	// idle cycles stops being eligible the moment one more buffer is pushed after it,
	// so a single peak in demand permanently pins every buffer it allocated beyond
	// the first for the rest of the process's life - a monotonically growing amount
	// of staging memory that this function was supposed to be able to shrink back
	// down, but structurally never could except for whichever buffer happened to be
	// last. Iterate back-to-front instead (erasing from the back first keeps earlier
	// indices valid for the rest of the loop) so every idle buffer is eligible, while
	// still always keeping at least one buffer around.
	for (sint32 i = (sint32)m_buffers.size() - 1; i >= 0 && m_buffers.size() > 1; i--)
	{
		auto& buffer = m_buffers[i];
		if (buffer.cleanupCounter >= 1000)
		{
			// release buffer
			buffer.mtlBuffer->release();
			m_buffers.erase(m_buffers.begin() + i);
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
	MTL::CommandBuffer* currentCommandBuffer = m_mtlr->GetCurrentCommandBuffer();
	auto it = std::find_if(m_activeAllocations.begin(), m_activeAllocations.end(), [&uploadReservation](const TrackedAllocation& allocation) { return allocation.allocation.chunkIndex == uploadReservation->bufferIndex && allocation.allocation.offset == uploadReservation->bufferOffset; });
	// This used to be cemu_assert_debug(it != end()) followed unconditionally by
	// it->allocation - a no-op check in Release (CEMU_DEBUG_ASSERT is Debug-only, see
	// CMakeLists.txt) guarding a dereference of end() on the exact path it exists to
	// catch. Two independent real device crashes, both signal 11 inside this exact
	// function at the same instruction offset, both traced back to here - a
	// double-free or a reservation this allocator never tracked in the first place
	// (the actual root cause in whichever caller does this is still unidentified;
	// this only stops the crash, it does not explain why FreeReservation gets called
	// twice on the same reservation). Bail out before the dereference instead of
	// riding it into undefined behaviour - the caller already has no way to detect
	// double-freeing a reservation, so there is nothing sound to do here except not
	// crash. Still returns the pooled AllocatorReservation object itself so at least
	// that part doesn't leak.
	if (it == m_activeAllocations.end())
	{
		cemuLog_log(LogType::Force,
			"MetalSynchronizedHeapAllocator::FreeReservation() called on an allocation "
			"(buffer {}, offset {}) this allocator has no record of - likely a double "
			"free. Skipping the release-queue/active-allocations bookkeeping for it "
			"rather than crashing on an invalid iterator.",
			uploadReservation->bufferIndex, uploadReservation->bufferOffset);
		m_poolAllocatorReservation.freeObj(uploadReservation);
		return;
	}
	m_releaseQueue[currentCommandBuffer].emplace_back(it->allocation);
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
