// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once
#include <string>
namespace boost { namespace nowide {
inline std::string narrow(const std::wstring&){ return {}; }
inline std::string narrow(const wchar_t*){ return {}; }
inline std::wstring widen(const std::string&){ return {}; }
inline std::wstring widen(const char*){ return {}; }
}}
