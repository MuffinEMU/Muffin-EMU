#pragma once

#include <boost/predef/os.h>
#include <cstdint>

#if BOOST_OS_WINDOWS
#include "Common/windows/platform.h"
#elif BOOST_OS_LINUX || BOOST_OS_BSD
#if BOOST_OS_LINUX
#include <byteswap.h>
#elif BOOST_OS_BSD
#include <endian.h>
#endif
// Android is a Linux to Boost.Predef, but has no X server; its window comes from the Java side
#if !defined(__ANDROID__)
#include <X11/Xlib.h>
#include <X11/extensions/Xrender.h>
#include <X11/Xutil.h>
#endif
#include "Common/unix/platform.h"
#elif BOOST_OS_MACOS || BOOST_OS_IOS
#include <libkern/OSByteOrder.h>
#include "Common/unix/platform.h"
#endif
