#pragma once

// Deferred release of recompiler code that has been invalidated.
//
// Why it is not simply "release it": a thread can still be running, or be parked inside, code the game has just
// invalidated. Two ways, and they need different answers.
//
//  1. Running. The thread runs recompiled code on a PPC core host thread. It leaves that code (back to the
//     interpreter loop, into the scheduler, or into an idle wait) at least once per time slice. So a range
//     retired at time T is safe from running threads once every host thread has passed such a point after T
//     (quiescent state based reclamation). A host thread that is parked in an idle wait counts as having passed.
//
//  2. Parked. Recompiled code calls HLE functions directly (PPCRecompiler_virtualHLE), and an HLE call can block,
//     which switches fibers with the caller's native frame, return address into the code, still on its stack.
//     That thread is not running, so (1) says nothing about it. Each such call therefore pins the 4 KB block of
//     its return address for as long as the call lasts, and the pin is only dropped once the host thread that
//     finished the call has passed a quiescent point, because after the call returns the thread runs the
//     rest of the code's epilogue on whatever host thread resumed it.
//
// A range is handed back when both hold: every host thread has passed a quiescent point since it was retired,
// and no pin lies on any block the range touches. The ordering that makes this sound is spelled out next to each
// operation. This header has no engine dependencies so it can be tested on its own
// (tools/audit-app/Tests/jit_reclaim_test.cpp).

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

namespace jitreclaim
{
constexpr int kMaxHosts = 8;
constexpr unsigned kPinShift = 12; // pins are per 4 KB of arena

struct Pending
{
	size_t begin = 0; // byte offset in the arena
	size_t size = 0;
	void* a = nullptr; // caller's payload (the region's aliases)
	void* b = nullptr;
	int kind = 0;
	uint64_t snap[kMaxHosts] = {};
	int snapHosts = 0;
};

class Reclaimer
{
  public:
	// Sizes the pin table for an arena of this many bytes and forgets all state.
	void init(size_t arenaBytes)
	{
		std::lock_guard lock(m_mutex);
		const size_t blocks = (arenaBytes >> kPinShift) + 1;
		m_pins.reset(new std::atomic<uint32_t>[blocks]);
		for (size_t i = 0; i < blocks; i++)
			m_pins[i].store(0, std::memory_order_relaxed);
		m_blocks = blocks;
		resetLocked();
		m_active.store(true, std::memory_order_release);
	}

	// Shutdown: nothing is running any more. Forgets pending ranges, hosts and pins (pins left behind by
	// threads that never came back from a call are dropped with the rest).
	void reset()
	{
		std::lock_guard lock(m_mutex);
		for (size_t i = 0; i < m_blocks; i++)
			m_pins[i].store(0, std::memory_order_relaxed);
		resetLocked();
	}

	bool active() const { return m_active.load(std::memory_order_relaxed); }

	// Something that can run guest code is not registered, so nothing can be proven about it: never free again
	// (until reset). Returns true the first time.
	bool poison() { return !m_poisoned.exchange(true); }
	bool poisoned() const { return m_poisoned.load(std::memory_order_relaxed); }

	// ---- host side (a PPC core's host thread) ----

	// Once per host thread, before it runs any guest code. -1 if there is no slot left, in which case the caller
	// must poison().
	int registerHost()
	{
		const int slot = m_hosts.fetch_add(1);
		if (slot >= kMaxHosts)
		{
			m_hosts.fetch_sub(1);
			return -1;
		}
		m_idle[slot].store(false);
		return slot;
	}

	// This host thread is not executing recompiled code and holds no pointer into it. Drops the pins it was
	// keeping for finished calls, then counts a pass. The last load pairs with retire(): once a reclaimer has
	// seen this pass, everything the retiring thread did before retire() (the jump table reset) is visible
	// to this host thread, so it cannot fetch an invalidated entry afterwards.
	void quiescent(int host)
	{
		auto& mine = m_deferred[host];
		for (uint32_t block : mine)
			m_pins[block].fetch_sub(1);
		mine.clear();
		m_passes[host].fetch_add(1);
		(void)m_retireSeq.load();
	}

	// The host thread is about to wait with nothing to run, or has stopped waiting. Same visibility argument
	// as quiescent(): the store is sequentially consistent, and the load after it pairs with retire().
	void setIdle(int host, bool idle)
	{
		m_idle[host].store(idle);
		(void)m_retireSeq.load();
	}

	static constexpr uint32_t kNoPin = 0xFFFFFFFFu;

	// An HLE call was made from code at arena offset `offset`. Returns the token for unpinLater().
	uint32_t pin(size_t offset)
	{
		const size_t block = offset >> kPinShift;
		if (block >= m_blocks)
			return kNoPin;
		m_pins[block].fetch_add(1);
		return (uint32_t)block;
	}

	// The call has returned, on this host thread. The pin stays until this host thread's next quiescent point.
	void unpinLater(int host, uint32_t token)
	{
		if (token != kNoPin)
			m_deferred[host].push_back(token);
	}

	// ---- retiring side ----

	// `begin`/`size` is the range (arena byte offsets); a and b are carried to the free callback. The caller
	// has already made the code unreachable (jump table entries reset) and holds whatever lock orders that
	// against threads looking entries up.
	void retire(size_t begin, size_t size, void* a, void* b, int kind)
	{
		Pending p;
		p.begin = begin;
		p.size = size;
		p.a = a;
		p.b = b;
		p.kind = kind;
		m_retireSeq.fetch_add(1);
		const int hosts = std::min(m_hosts.load(), kMaxHosts);
		p.snapHosts = hosts;
		for (int i = 0; i < hosts; i++)
			p.snap[i] = m_passes[i].load();
		std::lock_guard lock(m_mutex);
		m_list.push_back(p);
		m_pendingBytes.fetch_add(size);
		m_pendingCount.fetch_add(1);
	}

	// Calls freeFn(const Pending&) for every range that is now safe and returns the bytes freed. freeFn runs
	// without this class's lock held.
	template <class F>
	size_t reclaim(F&& freeFn)
	{
		if (m_poisoned.load() || m_pendingCount.load(std::memory_order_relaxed) == 0)
			return 0;
		std::vector<Pending> ready;
		{
			std::lock_guard lock(m_mutex);
			// Hosts are checked before pins: a pin taken before a host's pass is visible once that pass is.
			size_t kept = 0;
			for (size_t i = 0; i < m_list.size(); i++)
			{
				if (isSafeLocked(m_list[i]))
					ready.push_back(m_list[i]);
				else
					m_list[kept++] = m_list[i];
			}
			m_list.resize(kept);
		}
		size_t bytes = 0;
		for (const Pending& p : ready)
		{
			freeFn(p);
			bytes += p.size;
		}
		if (!ready.empty())
		{
			m_pendingBytes.fetch_sub(bytes);
			m_pendingCount.fetch_sub((uint32_t)ready.size());
		}
		return bytes;
	}

	// Shutdown only, with no guest code running anywhere: everything goes.
	template <class F>
	size_t drainAll(F&& freeFn)
	{
		std::vector<Pending> all;
		{
			std::lock_guard lock(m_mutex);
			all.swap(m_list);
		}
		size_t bytes = 0;
		for (const Pending& p : all)
		{
			freeFn(p);
			bytes += p.size;
		}
		m_pendingBytes.store(0);
		m_pendingCount.store(0);
		return bytes;
	}

	uint64_t pendingBytes() const { return m_pendingBytes.load(std::memory_order_relaxed); }
	uint32_t pendingCount() const { return m_pendingCount.load(std::memory_order_relaxed); }
	int hostCount() const { return std::min(m_hosts.load(), kMaxHosts); }
	uint32_t pinsOnBlock(size_t block) const { return block < m_blocks ? m_pins[block].load() : 0; }

  private:
	void resetLocked()
	{
		m_list.clear();
		m_pendingBytes.store(0);
		m_pendingCount.store(0);
		m_hosts.store(0);
		m_poisoned.store(false);
		for (int i = 0; i < kMaxHosts; i++)
		{
			m_passes[i].store(0);
			m_idle[i].store(false);
			m_deferred[i].clear();
		}
	}

	bool isSafeLocked(const Pending& p) const
	{
		for (int i = 0; i < p.snapHosts; i++)
		{
			if (m_passes[i].load() == p.snap[i] && !m_idle[i].load())
				return false;
		}
		if (p.size == 0)
			return true;
		const size_t first = p.begin >> kPinShift;
		const size_t last = (p.begin + p.size - 1) >> kPinShift;
		for (size_t block = first; block <= last && block < m_blocks; block++)
		{
			if (m_pins[block].load() != 0)
				return false;
		}
		return true;
	}

	std::mutex m_mutex;
	std::vector<Pending> m_list;
	std::unique_ptr<std::atomic<uint32_t>[]> m_pins;
	size_t m_blocks = 0;
	std::atomic<bool> m_active{false};
	std::atomic<bool> m_poisoned{false};
	std::atomic<int> m_hosts{0};
	std::atomic<uint64_t> m_passes[kMaxHosts];
	std::atomic<bool> m_idle[kMaxHosts];
	std::vector<uint32_t> m_deferred[kMaxHosts]; // only ever touched by the owning host thread
	std::atomic<uint64_t> m_retireSeq{0};
	std::atomic<uint64_t> m_pendingBytes{0};
	std::atomic<uint32_t> m_pendingCount{0};
};
} // namespace jitreclaim
