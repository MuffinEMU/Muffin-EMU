//
//  MuffinBenchCommon.h
//  Helpers every engine's benchmark shim shares verbatim, so no engine answers a
//  question like "may this process run generated code" differently from another.
//
#pragma once
#include <cstdint>
#include <cstddef>
#include <unistd.h>

extern "C" int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

// CS_DEBUGGED (0x10000000) is what waives the code-signing check at instruction fetch.
// It is what a JIT enabler produces, and without it generated code is fatal on iOS.
static inline bool mbench_common_process_is_debugged()
{
    uint32_t flags = 0;
    return csops(getpid(), 0 /* CS_OPS_STATUS */, &flags, sizeof(flags)) == 0 && (flags & 0x10000000u) != 0;
}

#ifndef MBENCH_COMMIT
#define MBENCH_COMMIT "unknown"
#endif
