#pragma once

#include <cstdint>

#if defined(CEMU_PLATFORM_IOS)
// iOS build - skip Boost
#include <libkern/OSByteOrder.h>
#include "Common/unix/platform.h"
#else
// Desktop/Android builds
#include <boost/predef/os.h>
#include <boost/predef/platform.h>

#if BOOST_OS_WINDOWS
#include "Common/windows/platform.h"
#elif BOOST_PLAT_ANDROID
#include <byteswap.h>
#include "Common/unix/platform.h"
#elif BOOST_OS_LINUX || BOOST_OS_BSD
#if BOOST_OS_LINUX
#include <byteswap.h>
#elif BOOST_OS_BSD
#include <endian.h>
#endif
#include <X11/Xlib.h>
#include <X11/extensions/Xrender.h>
#include <X11/Xutil.h>
#include "Common/unix/platform.h"
#elif BOOST_OS_MACOS
#include <libkern/OSByteOrder.h>
#include "Common/unix/platform.h"
#endif
#endif
