#pragma once

#if BOOST_OS_WINDOWS

#endif

class Fiber
{
public:
	Fiber(void(*FiberEntryPoint)(void* userParam), void* userParam, void* privateData);
	~Fiber();

	static Fiber* PrepareCurrentThread(void* privateData = nullptr);
	static void Switch(Fiber& targetFiber);
	static void* GetFiberPrivateData();

	// A fiber's stack is a 2 MB allocation, which fails when the process runs out of address space.
	// The host can register a hook to free memory (called once, then the allocation is retried) and one
	// to report the failure; a fiber whose stack could not be allocated is not valid and never runs.
	static void SetStackFailureHandlers(void (*relieveMemory)(), void (*failed)());
	bool IsValid() const { return m_valid; }

    void* m_implData{nullptr};
private:
	Fiber(void* privateData); // fiber from current thread

	void* m_privateData;
	void* m_stackPtr{ nullptr };
	bool m_valid{ true };
};
