// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once
#include <vector>
#include <memory>
namespace boost { namespace container {
// Syntax-only shim: real small_vector has inline storage, this does not. Only the
// interface needs to match for -fsyntax-only.
template <class T, std::size_t N, class Allocator = std::allocator<T>>
class small_vector : public std::vector<T, Allocator> {
public:
    using std::vector<T, Allocator>::vector;
};
}}
