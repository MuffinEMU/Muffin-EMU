#pragma once

#include <ucontext.h>

class Fiber
{
public:
	Fiber(void(*FiberEntryPoint)(void* userParam), void* userParam, void* privateData);
	~Fiber();

	static Fiber* PrepareCurrentThread(void* privateData = nullptr);
	// Returns 0 when the switch happened. Anything else is the errno from a
	// swapcontext that refused, which used to be discarded silently.
	static int Switch(Fiber& targetFiber);
	static void* GetFiberPrivateData();
private:
	Fiber(void* privateData); // fiber from current thread

	ucontext_t* m_ctx{nullptr};
	void* m_privateData;
	void* m_stackPtr{ nullptr };
};