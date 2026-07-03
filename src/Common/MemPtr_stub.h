#pragma once
// iOS Phase 0: Complete MemPtr stub
// Provides MEMPTR class with all necessary methods

#if defined(CEMU_PLATFORM_IOS)

// Null pointer marker
class MEMPTR_NULL_t {};
constexpr MEMPTR_NULL_t MEMNULL;

// MEMPTR template - minimal but functional
template<typename T = void>
class MEMPTR {
public:
    MEMPTR() : m_address(0) {}
    MEMPTR(MEMPTR_NULL_t) : m_address(0) {}
    explicit MEMPTR(uint32_t addr) : m_address(addr) {}
    explicit MEMPTR(T* ptr) : m_address((uint32_t)ptr) {}

    // Operators
    T* operator->() {
        if (m_address == 0) return nullptr;
        return (T*)m_address;
    }

    T& operator*() {
        return *((T*)m_address);
    }

    explicit operator bool() const { return m_address != 0; }
    bool operator!() const { return m_address == 0; }
    bool operator==(const MEMPTR& other) const { return m_address == other.m_address; }
    bool operator==(std::nullptr_t) const { return m_address == 0; }
    bool operator!=(const MEMPTR& other) const { return m_address != other.m_address; }
    bool operator!=(std::nullptr_t) const { return m_address != 0; }

    bool operator<(const MEMPTR& other) const { return m_address < other.m_address; }
    bool operator>(const MEMPTR& other) const { return m_address > other.m_address; }
    bool operator<=(const MEMPTR& other) const { return m_address <= other.m_address; }
    bool operator>=(const MEMPTR& other) const { return m_address >= other.m_address; }

    // Common methods
    bool IsNull() const { return m_address == 0; }
    bool IsValid() const { return m_address != 0; }

    T* GetPtr() const { return (T*)m_address; }
    uint32_t GetMPTR() const { return m_address; }
    uint32_t GetAddress() const { return m_address; }

    void SetMPTR(uint32_t addr) { m_address = addr; }
    void SetNull() { m_address = 0; }

    // Cast operators
    template<typename T2>
    operator MEMPTR<T2>() const {
        return MEMPTR<T2>(m_address);
    }

    operator uint32_t() const { return m_address; }

private:
    uint32_t m_address;
};

// Specialization for void
template<>
class MEMPTR<void> {
public:
    MEMPTR() : m_address(0) {}
    MEMPTR(MEMPTR_NULL_t) : m_address(0) {}
    explicit MEMPTR(uint32_t addr) : m_address(addr) {}

    explicit operator bool() const { return m_address != 0; }
    bool operator!() const { return m_address == 0; }
    bool operator==(const MEMPTR& other) const { return m_address == other.m_address; }
    bool operator==(std::nullptr_t) const { return m_address == 0; }
    bool operator!=(const MEMPTR& other) const { return m_address != other.m_address; }
    bool operator!=(std::nullptr_t) const { return m_address != 0; }

    bool IsNull() const { return m_address == 0; }
    uint32_t GetMPTR() const { return m_address; }
    void* GetPtr() const { return (void*)m_address; }

    template<typename T>
    operator MEMPTR<T>() const {
        return MEMPTR<T>(m_address);
    }

private:
    uint32_t m_address;
};

// Type aliases
using string_view = std::string_view;

// Simple type for struct size assertion (Phase 0 stub)
template<int size>
struct MEMPTR_SIZE_CHECK {};

#endif // CEMU_PLATFORM_IOS
