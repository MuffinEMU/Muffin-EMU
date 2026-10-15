// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once
#include <cstddef>
#include <functional>
namespace boost {
template <class T> std::size_t hash_value(const T&) { return 0; }
template <class T> struct hash : std::hash<T> {};
template <class T> void hash_combine(std::size_t&, const T&) {}
}
