#include "Cafe/HW/Latte/Renderer/Metal/MetalCommon.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalMemoryManager.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalVoidVertexPipeline.h"

#include "CafeSystem.h"
#include "Cemu/Logging/CemuLogging.h"
#include "Common/precompiled.h"
#include "HW/MMU/MMU.h"
#include "config/CemuConfig.h"

#include "Cafe/HW/Latte/Core/LatteBufferCache.h"

#include <cstring>

MetalMemoryManager::~MetalMemoryManager()
{
    // The argument snapshots hold a retain on every resource they recorded and on the
    // encoder itself (see GetCachedArgumentBuffer below), so they have to be given back
    // here - this object outlives individual draws, which is what makes the caching work
    // and also what makes it the owner of those retains.
    for (auto& snapshot : m_argumentSnapshots)
    {
        for (const auto& binding : snapshot.bindings)
            if (binding.resource)
                static_cast<NS::Object*>(binding.resource)->release();
        if (snapshot.encoder)
            snapshot.encoder->release();
    }
    if (m_bufferCache)
    {
        m_bufferCache->release();
    }
    if (m_importedMemoryBuffer)
    {
        m_importedMemoryBuffer->release();
    }
}

MetalSynchronizedHeapAllocator::AllocatorReservation* MetalMemoryManager::GetCachedSnapshot(uint32 slot, const void* data, uint32 size, uint32 firstByte)
{
    cemu_assert_debug(slot < SnapshotCount && firstByte <= size);
    // Make sure a command buffer exists before the allocation is made, so the reservation
    // is attributed to one and CleanupBuffers() can retire it in order.
    m_mtlr->GetCommandBuffer();
    auto& snapshot = m_snapshots[slot];
    const auto* source = static_cast<const uint8*>(data);
    const uint32 copySize = size - firstByte;
    // A content comparison, not a dirty flag: the guest can write the same bytes back, and
    // an emulator has no reliable notification for "this range did not really change".
    // memcmp over a range already in a mapped device buffer is far cheaper than the
    // re-upload it avoids.
    if (snapshot.allocation && snapshot.firstByte <= firstByte && snapshot.endByte >= size &&
        std::memcmp(snapshot.allocation->memPtr + firstByte, source + firstByte, copySize) == 0)
    {
        m_mtlr->GetPerformanceMonitor().m_snapshotReuses++;
        return snapshot.allocation;
    }

    if (snapshot.allocation)
        m_snapshotAllocator.FreeReservation(snapshot.allocation);
    snapshot.allocation = m_snapshotAllocator.AllocateBufferMemory(std::max(size, 1u), 256);
    snapshot.firstByte = firstByte;
    snapshot.endByte = size;
    if (!snapshot.allocation)
    {
        // Out of buffer memory. The reuse check above starts with a null test, so leaving
        // the slot empty simply means the next call re-tries the upload.
        return nullptr;
    }
    std::memcpy(snapshot.allocation->memPtr + firstByte, source + firstByte, copySize);
    m_snapshotAllocator.FlushReservation(snapshot.allocation);
    m_mtlr->GetPerformanceMonitor().m_snapshotBytes += copySize;
    return snapshot.allocation;
}

MetalSynchronizedHeapAllocator::AllocatorReservation* MetalMemoryManager::GetCachedArgumentBuffer(uint32 stage, MTL::ArgumentEncoder* encoder, const MetalArgumentBindings& bindings)
{
    cemu_assert_debug(stage < METAL_SHADER_TYPE_TOTAL);
    m_mtlr->GetCommandBuffer();
    auto& snapshot = m_argumentSnapshots[stage];
    // Same encoder (so the same layout) and the same complete set of bindings means the
    // encoded buffer would come out byte-identical - skip the encode entirely. Note the
    // CALLER still has to re-declare residency (useResource) for every encoder even on
    // this path; only the encoding is cached, not the residency.
    if (snapshot.encoder == encoder && snapshot.bindings == bindings)
    {
        m_mtlr->GetPerformanceMonitor().m_argumentBufferReuses++;
        return snapshot.allocation;
    }

    if (snapshot.allocation)
        m_snapshotAllocator.FreeReservation(snapshot.allocation);
    if (snapshot.encoder != encoder)
    {
        if (snapshot.encoder)
            snapshot.encoder->release();
        snapshot.encoder = encoder->retain();
    }

    // Retain the new set BEFORE releasing the old one: a resource present in both would
    // otherwise hit refcount zero in between and be deallocated while still bound.
    for (const auto& binding : bindings)
        if (binding.resource)
            static_cast<NS::Object*>(binding.resource)->retain();
    for (const auto& binding : snapshot.bindings)
        if (binding.resource)
            static_cast<NS::Object*>(binding.resource)->release();
    snapshot.bindings = bindings;
    const uint32 alignment = std::max<uint32>(256, static_cast<uint32>(encoder->alignment()));
    snapshot.allocation = m_snapshotAllocator.AllocateBufferMemory(static_cast<uint32>(encoder->encodedLength()), alignment);
    auto* allocation = snapshot.allocation;
    if (!allocation)
    {
        // Out of buffer memory. The bindings and encoder recorded above still describe
        // what this slot holds (nothing), so the cache stays consistent and the caller
        // skips the draw.
        return nullptr;
    }
    std::memset(allocation->memPtr, 0, allocation->size);
    encoder->setArgumentBuffer(allocation->mtlBuffer, allocation->bufferOffset);
    for (uint32 index = 0; index < bindings.size(); ++index)
    {
        const auto& binding = bindings[index];
        switch (binding.type)
        {
            case MetalArgumentBinding::Type::Unused:
                break;
            case MetalArgumentBinding::Type::Buffer:
                encoder->setBuffer(static_cast<MTL::Buffer*>(binding.resource), binding.value, index);
                break;
            case MetalArgumentBinding::Type::Texture:
                encoder->setTexture(static_cast<MTL::Texture*>(binding.resource), index);
                break;
            case MetalArgumentBinding::Type::Sampler:
                encoder->setSamplerState(static_cast<MTL::SamplerState*>(binding.resource), index);
                break;
            case MetalArgumentBinding::Type::Constant:
                if (void* constant = encoder->constantData(index))
                    *static_cast<uint32*>(constant) = static_cast<uint32>(binding.value);
                break;
        }
    }

    m_snapshotAllocator.FlushReservation(allocation);
    m_mtlr->GetPerformanceMonitor().m_argumentBufferEncodes++;
    return allocation;
}

void* MetalMemoryManager::AcquireTextureUploadBuffer(size_t size)
{
    if (m_textureUploadBuffer.size() < size)
    {
        m_textureUploadBuffer.resize(size);
    }

    return m_textureUploadBuffer.data();
}

void MetalMemoryManager::ReleaseTextureUploadBuffer(uint8* mem)
{
    cemu_assert_debug(m_textureUploadBuffer.data() == mem);
    m_textureUploadBuffer.clear();
}

void MetalMemoryManager::InitBufferCache(size_t size)
{
    cemu_assert_debug(!m_bufferCache);

    m_metalBufferCacheMode = g_current_game_profile->GetBufferCacheMode();

    if (m_metalBufferCacheMode == MetalBufferCacheMode::Auto)
    {
        // TODO: do this for all unified memory systems?
        if (m_mtlr->IsAppleGPU())
        {
            switch (CafeSystem::GetForegroundTitleId())
            {
            // The Legend of Zelda: Wind Waker HD
            case 0x0005000010143600: // EUR
            case 0x0005000010143500: // USA
            case 0x0005000010143400: // JPN
                // TODO: use host instead?
                m_metalBufferCacheMode = MetalBufferCacheMode::Host;
                break;
            default:
                m_metalBufferCacheMode = MetalBufferCacheMode::Host;
                break;
            }
        }
        else
        {
            m_metalBufferCacheMode = MetalBufferCacheMode::DevicePrivate;
        }
    }

    // First, try to import the host memory as a buffer
    if (m_metalBufferCacheMode == MetalBufferCacheMode::Host)
    {
        if (m_mtlr->HasUnifiedMemory())
        {
            m_importedMemBaseAddress = mmuRange_MEM2.getBase();
               m_hostAllocationSize = mmuRange_MEM2.getSize();
            m_importedMemoryBuffer = m_mtlr->GetDevice()->newBuffer(memory_getPointerFromVirtualOffset(m_importedMemBaseAddress), m_hostAllocationSize, MTL::ResourceStorageModeShared, nullptr);
            if (!m_importedMemoryBuffer)
            {
                cemuLog_log(LogType::Force, "Failed to import host memory as a buffer, using device shared mode instead");
                m_metalBufferCacheMode = MetalBufferCacheMode::DeviceShared;
                m_importedMemBaseAddress = 0;
                m_hostAllocationSize = 0;
            }
        }
        else
        {
            cemuLog_log(LogType::Force, "Host buffer cache mode is only available on unified memory systems, using device shared mode instead");
            m_metalBufferCacheMode = MetalBufferCacheMode::DeviceShared;
        }
    }

    if (!m_bufferCache)
        m_bufferCache = m_mtlr->GetDevice()->newBuffer(size, (m_metalBufferCacheMode == MetalBufferCacheMode::DevicePrivate ? MTL::ResourceStorageModePrivate : MTL::ResourceStorageModeShared));
    if (!m_bufferCache)
    {
        // 164 MB in a single allocation, made when a title starts, and on iOS it competes
        // with the recompiler's arena - this is the likeliest allocation in the renderer to
        // actually fail. The imported-memory buffer above is checked and falls back; this
        // one was not, and cemu_assert_debug() compiles to nothing in a release build, so a
        // failure here did not surface here at all. The binding paths already substitute a
        // placeholder for a null cache, but UploadToBufferCache() and CopyBufferCache()
        // wrote straight through contents(), so the first guest buffer upload dereferenced
        // null and the crash looked like a fault in the upload rather than an allocation
        // that never succeeded. Keep it null, say so once, and let those paths skip.
        cemuLog_log(LogType::Force,
            "Metal: failed to allocate the {} MB GPU buffer cache. Nothing will render; this is an out-of-memory condition, not a shader or pipeline fault",
            size / (1024 * 1024));
    }

    if (m_metalBufferCacheMode == MetalBufferCacheMode::DeviceShared)
        m_sharedTracker.Initialize(size);
    
    LatteBufferCache_hostSetVolatilityTracking(m_metalBufferCacheMode == MetalBufferCacheMode::Host);

#ifdef CEMU_DEBUG_ASSERT
    if (m_bufferCache)
        m_bufferCache->setLabel(GetLabel("Buffer cache", m_bufferCache));
    if (m_importedMemoryBuffer)
        m_importedMemoryBuffer->setLabel(GetLabel("Imported memory buffer", m_importedMemoryBuffer));
#endif
}

void MetalMemoryManager::UploadToBufferCache(const void* data, size_t offset, size_t size)
{
    if (size == 0)
        return;
    if (!m_bufferCache)
        return; // buffer cache allocation failed at init - see InitBufferCache()
    cemu_assert_debug((offset + size) <= m_bufferCache->length());

    if (m_metalBufferCacheMode == MetalBufferCacheMode::DevicePrivate || SharedCacheBusy(offset, size))
    {
        auto blitCommandEncoder = m_mtlr->GetBlitCommandEncoder();

        auto allocation = m_stagingAllocator.AllocateBufferMemory(size, 1);
        if (!allocation.mtlBuffer)
            return; // out of staging memory - skip the upload rather than write through null
        memcpy(allocation.memPtr, data, size);
        m_stagingAllocator.FlushReservation(allocation);

        blitCommandEncoder->copyFromBuffer(allocation.mtlBuffer, allocation.bufferOffset, m_bufferCache, offset, size);
        TrackSharedCache(m_bufferCache, offset, size, true);

        //m_mtlr->CopyBufferToBuffer(allocation.mtlBuffer, allocation.bufferOffset, m_bufferCache, offset, size, ALL_MTL_RENDER_STAGES, ALL_MTL_RENDER_STAGES);
    }
    else
    {
        memcpy((uint8*)m_bufferCache->contents() + offset, data, size);
        NotifyBufferCacheRangeModified(offset, size);
    }

}

void MetalMemoryManager::CopyBufferCache(size_t srcOffset, size_t dstOffset, size_t size)
{
    if (size == 0 || srcOffset == dstOffset)
        return;
    if (!m_bufferCache)
        return; // buffer cache allocation failed at init - see InitBufferCache()
    if (m_metalBufferCacheMode == MetalBufferCacheMode::DevicePrivate ||
        SharedCacheBusy(srcOffset, size, true) || SharedCacheBusy(dstOffset, size))
    {
        m_mtlr->CopyBufferToBuffer(m_bufferCache, srcOffset, m_bufferCache, dstOffset, size, ALL_MTL_RENDER_STAGES, ALL_MTL_RENDER_STAGES);
        TrackSharedCache(m_bufferCache, srcOffset, size);
        TrackSharedCache(m_bufferCache, dstOffset, size, true);
    }
    else
    {
        memcpy((uint8*)m_bufferCache->contents() + dstOffset, (uint8*)m_bufferCache->contents() + srcOffset, size);
        NotifyBufferCacheRangeModified(dstOffset, size);
    }

}

bool MetalMemoryManager::SharedCacheBusy(size_t offset, size_t size, bool writesOnly) const
{
    return m_sharedTracker.Busy(offset, size, writesOnly);
}

void MetalMemoryManager::TrackSharedCache(MTL::Buffer* buffer, size_t offset, size_t size, bool write)
{
    if (m_metalBufferCacheMode == MetalBufferCacheMode::DeviceShared && buffer == m_bufferCache && size)
        m_sharedTracker.Mark(m_mtlr->GetCommandBuffer(), offset, size, write);
}

void MetalMemoryManager::NotifyBufferCacheRangeModified(size_t offset, size_t size)
{
    NotifyBufferRangeModified(m_bufferCache, offset, size);
}

void MetalMemoryManager::NotifyImportedMemoryRangeModified(size_t offset, size_t size)
{
    NotifyBufferRangeModified(m_importedMemoryBuffer, offset, size);
}

void MetalMemoryManager::NotifyBufferRangeModified(MTL::Buffer* buffer, size_t offset, size_t size)
{
    if (!buffer || size == 0 || buffer->storageMode() != MTL::StorageModeManaged)
        return;

    size_t bufferLength = buffer->length();
    if (offset >= bufferLength)
        return;

    size = std::min(size, bufferLength - offset);
    buffer->didModifyRange(NS::Range(offset, size));
}
