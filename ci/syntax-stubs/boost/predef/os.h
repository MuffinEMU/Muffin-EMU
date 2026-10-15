// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once
// Minimal boost.predef stand-in - see ../../README.md
#if defined(__APPLE__)
  #define BOOST_OS_MACOS 1
  #define BOOST_OS_UNIX 1
#else
  #define BOOST_OS_MACOS 0
  #define BOOST_OS_UNIX 0
#endif
#define BOOST_OS_WINDOWS 0
#define BOOST_OS_LINUX 0
#define BOOST_OS_BSD 0
#define BOOST_OS_IOS 0
