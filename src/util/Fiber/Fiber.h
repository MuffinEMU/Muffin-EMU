#pragma once

// This condition MUST stay in lockstep with the fiber backend selected in
// src/util/CMakeLists.txt (`if(ANDROID OR PLATFORM_IOS)`). It picks the class
// *declaration* every caller compiles against; CMake picks the .cpp that *defines*
// it. When the two disagree the program still links - the mangled names are
// identical either way - so the mismatch is silent and catastrophic.
//
// iOS was added to the CMake condition without being added here. Callers saw
// FiberUContext.h's Fiber (three pointers, 24 bytes) while the linked-in definition
// was FiberFContext.cpp's (48 bytes). coreinit_Thread.cpp holds a `Fiber m_fiber`
// by value inside OSHostThread and allocates the idle fiber with `new Fiber(...)`,
// so every fiber the scheduler built ran a 48-byte constructor over 24 bytes of
// storage - overwriting the rest of OSHostThread, and the heap past a 24-byte
// allocation, before the guest ever ran an instruction.
//
// The three backend .cpp files now include this header instead of their own, so any
// future disagreement is a compile error rather than a corrupted PPC scheduler.
#if BOOST_PLAT_ANDROID || defined(CEMU_PLATFORM_IOS)
#include "FiberFContext.h"
#elif BOOST_OS_WINDOWS
#include "FiberWin.h"
#else
#include "FiberUContext.h"
#endif
