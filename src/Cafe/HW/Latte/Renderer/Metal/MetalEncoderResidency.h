#pragma once

#include <vector>

/// Remembers which resources a render command encoder has already been told to keep resident.
///
/// useResource() is per-encoder state, and the same few textures and buffers are declared again by
/// every draw of a pass. Declaring a resource a second time with the same usage and stages does
/// nothing, so this lets the caller skip the call. Declare() reports whether a call is needed and
/// what it has to carry: a resource seen before with fewer usage or stage bits than now needs one
/// more call with the union of both.
///
/// Every resource it remembers is retained until Reset(), so a resource that is freed and replaced
/// while the encoder is still open can never hand its address to a different resource that would then
/// be mistaken for one already declared. Reset() has to run whenever the encoder it describes ends
/// or a new one begins.
class MetalEncoderResidency
{
public:
    MetalEncoderResidency() : m_slots(INITIAL_SLOTS) {}
    ~MetalEncoderResidency() { Reset(); }
    MetalEncoderResidency(const MetalEncoderResidency&) = delete;
    MetalEncoderResidency& operator=(const MetalEncoderResidency&) = delete;

    /// Returns true when useResource() has to be called, with `usage` and `stages` widened to what
    /// has to be declared (the union with anything declared before).
    bool Declare(MTL::Resource* resource, uint32& usage, uint32& stages)
    {
        if ((m_used + 1) * 2 > m_slots.size())
            Grow();
        size_t index = Probe(resource);
        Slot& slot = m_slots[index];
        if (slot.resource == resource)
        {
            if ((usage & ~slot.usage) == 0 && (stages & ~slot.stages) == 0)
                return false;
            slot.usage |= usage;
            slot.stages |= stages;
            usage = slot.usage;
            stages = slot.stages;
            return true;
        }
        resource->retain();
        slot.resource = resource;
        slot.usage = usage;
        slot.stages = stages;
        m_occupied.push_back(static_cast<uint32>(index));
        m_used++;
        return true;
    }

    void Reset()
    {
        for (uint32 index : m_occupied)
        {
            m_slots[index].resource->release();
            m_slots[index] = {};
        }
        m_occupied.clear();
        m_used = 0;
    }

private:
    struct Slot
    {
        MTL::Resource* resource = nullptr;
        uint32 usage = 0;
        uint32 stages = 0;
    };

    static constexpr size_t INITIAL_SLOTS = 1024; // power of two

    size_t Probe(const MTL::Resource* resource) const
    {
        const size_t mask = m_slots.size() - 1;
        uint64 h = reinterpret_cast<uintptr_t>(resource) >> 4;
        h *= 0x9E3779B97F4A7C15ull;
        size_t index = static_cast<size_t>(h >> 32) & mask;
        while (m_slots[index].resource && m_slots[index].resource != resource)
            index = (index + 1) & mask;
        return index;
    }

    void Grow()
    {
        std::vector<Slot> old(m_slots.size() * 2);
        old.swap(m_slots);
        m_occupied.clear();
        for (const Slot& slot : old)
        {
            if (!slot.resource)
                continue;
            size_t index = Probe(slot.resource);
            m_slots[index] = slot;
            m_occupied.push_back(static_cast<uint32>(index));
        }
    }

    std::vector<Slot> m_slots;
    std::vector<uint32> m_occupied;
    size_t m_used = 0;
};
