#include "Cemu/Logging/IOSLiveLog.h"

#if defined(CEMU_PLATFORM_IOS)

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>

namespace
{
	// Sized for one boot, not one session. A cold boot of a real title logs a few
	// hundred lines (RPL link, the HLE export scan, module load, the active-settings
	// block); 1024 covers that with headroom while capping the worst case at well under
	// a megabyte. That ceiling matters more here than in a desktop build: under
	// LiveContainer this process shares a memory budget with the host, and being killed
	// for footprint while diagnosing a black screen would be its own joke.
	constexpr size_t kMaxLines = 1024;
	constexpr size_t kMaxLineLength = 400;

	struct LiveLog
	{
		std::mutex mutex;
		std::deque<std::string> lines;
		// Monotonically increasing across evictions. The UI's cursor is a sequence
		// number, not an index, so eviction cannot make it silently point at the wrong
		// line - the arithmetic below detects the gap instead.
		uint64_t nextSequence = 0;
		uint64_t firstSequence = 0;
		std::chrono::steady_clock::time_point origin = std::chrono::steady_clock::now();
	};

	// Function-local static, deliberately. cemu_bridge_install_early_crash_handler() is
	// a constructor(101) and pushes into this before most of the ~90 linked libraries'
	// static initializers have run; a namespace-scope object would be a static
	// initialization order dependency waiting to bite. This form is initialized on first
	// use and thread-safe per the standard.
	LiveLog& Get()
	{
		static LiveLog s_log;
		return s_log;
	}

	// Separate from the struct so the disabled path never touches Get() and therefore
	// never has to construct it.
	std::atomic<bool> s_enabled{true};
}

void ios_live_log_set_enabled(bool enabled)
{
	s_enabled.store(enabled, std::memory_order_relaxed);
}

bool ios_live_log_is_enabled(void)
{
	return s_enabled.load(std::memory_order_relaxed);
}

void ios_live_log_push(const char* line)
{
	if (!line || !s_enabled.load(std::memory_order_relaxed))
		return;

	LiveLog& log = Get();

	// Stamped here, on the emitting thread, rather than at drain time. The whole point
	// of the elapsed column is to show WHERE a boot stalls, and a timestamp applied when
	// the UI happened to poll would put every line of a five-second stall at the moment
	// the stall ended.
	const auto now = std::chrono::steady_clock::now();
	const auto wall = std::chrono::system_clock::now();

	double elapsed;
	{
		// Reading `origin` needs the lock: ios_live_log_begin_run() moves it.
		std::lock_guard<std::mutex> lock(log.mutex);
		elapsed = std::chrono::duration<double>(now - log.origin).count();
	}

	const auto wallTime = std::chrono::system_clock::to_time_t(wall);
	std::tm wallParts{};
	localtime_r(&wallTime, &wallParts);
	const int millis = (int)std::chrono::duration_cast<std::chrono::milliseconds>(
		wall - std::chrono::time_point_cast<std::chrono::seconds>(wall)).count();

	char prefix[64];
	snprintf(prefix, sizeof(prefix), "%02d:%02d:%02d.%03d +%7.3fs ",
		wallParts.tm_hour, wallParts.tm_min, wallParts.tm_sec, millis, elapsed);

	std::string entry(prefix);

	// Engine lines arrive with their own trailing newlines in a few places (the
	// shader-error paths use "\n" inside the format string). One log line should be one
	// row in the overlay, so fold any embedded newline into a space rather than letting
	// it split the entry when the UI splits on '\n' at the other end.
	const size_t inputLength = strlen(line);
	const size_t copyLength = inputLength > kMaxLineLength ? kMaxLineLength : inputLength;
	entry.reserve(entry.size() + copyLength + 16);
	for (size_t i = 0; i < copyLength; i++)
		entry.push_back((line[i] == '\n' || line[i] == '\r') ? ' ' : line[i]);
	if (inputLength > kMaxLineLength)
		entry.append(" [...]");

	std::lock_guard<std::mutex> lock(log.mutex);
	log.lines.emplace_back(std::move(entry));
	log.nextSequence++;
	while (log.lines.size() > kMaxLines)
	{
		log.lines.pop_front();
		log.firstSequence++;
	}
}

void ios_live_log_begin_run(void)
{
	LiveLog& log = Get();
	std::lock_guard<std::mutex> lock(log.mutex);
	log.lines.clear();
	log.origin = std::chrono::steady_clock::now();
	// The sequence counter deliberately does NOT reset. A reader holding a cursor from
	// the previous run would otherwise see the new run's first line as "already read".
	log.firstSequence = log.nextSequence;
}

const char* ios_live_log_drain(uint64_t* inoutCursor, uint64_t* outDropped)
{
	// Thread-local so two callers on different threads cannot hand each other a
	// half-overwritten buffer. In practice only the main thread drains.
	static thread_local std::string s_out;
	s_out.clear();
	if (outDropped)
		*outDropped = 0;
	if (!inoutCursor)
		return s_out.c_str();

	LiveLog& log = Get();
	std::lock_guard<std::mutex> lock(log.mutex);

	uint64_t cursor = *inoutCursor;
	if (cursor < log.firstSequence)
	{
		// Lines went past while the reader was away (or the overlay was only just
		// opened). Say so rather than pretending the stream is contiguous.
		if (outDropped)
			*outDropped = log.firstSequence - cursor;
		cursor = log.firstSequence;
	}
	else if (cursor > log.nextSequence)
	{
		// Only reachable if a run began and the reader kept a stale-but-higher cursor.
		cursor = log.firstSequence;
	}

	for (uint64_t seq = cursor; seq < log.nextSequence; seq++)
	{
		if (!s_out.empty())
			s_out.push_back('\n');
		s_out.append(log.lines[(size_t)(seq - log.firstSequence)]);
	}

	*inoutCursor = log.nextSequence;
	return s_out.c_str();
}

#else // !CEMU_PLATFORM_IOS

// Defined rather than left out so the declarations in the header always have a body on
// every platform this file is compiled into, and so the TU is not empty (which some
// toolchains warn about when archiving).
void ios_live_log_set_enabled(bool) {}
bool ios_live_log_is_enabled(void) { return false; }
void ios_live_log_push(const char*) {}
void ios_live_log_begin_run(void) {}
const char* ios_live_log_drain(uint64_t*, uint64_t* outDropped)
{
	if (outDropped)
		*outDropped = 0;
	return "";
}

#endif
