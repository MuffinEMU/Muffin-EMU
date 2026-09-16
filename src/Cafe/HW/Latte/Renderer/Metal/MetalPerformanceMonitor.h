#pragma once

class MetalPerformanceMonitor
{
public:
    // Per frame data
    uint32 m_commandBuffers = 0;
    uint32 m_renderPasses = 0;
    uint32 m_clears = 0;
    uint32 m_manualVertexFetchDraws = 0;
    uint32 m_meshDraws = 0;
    uint32 m_triangleFans = 0;
    // Buffer/argument snapshot caching (MetalMemoryManager::GetCachedSnapshot /
    // GetCachedArgumentBuffer). The reuse counters are the ones worth watching: they are
    // the draws that avoided a re-upload or a re-encode entirely, so a low reuse ratio
    // means the cache is paying its comparison cost without earning anything back.
    uint64 m_snapshotBytes = 0;
    uint32 m_snapshotReuses = 0;
    uint32 m_argumentBufferEncodes = 0;
    uint32 m_argumentBufferReuses = 0;

    MetalPerformanceMonitor() = default;
    ~MetalPerformanceMonitor() = default;

    void ResetPerFrameData()
    {
        m_commandBuffers = 0;
        m_renderPasses = 0;
        m_clears = 0;
        m_manualVertexFetchDraws = 0;
        m_meshDraws = 0;
        m_triangleFans = 0;
        m_snapshotBytes = 0;
        m_snapshotReuses = 0;
        m_argumentBufferEncodes = 0;
        m_argumentBufferReuses = 0;
    }
};
