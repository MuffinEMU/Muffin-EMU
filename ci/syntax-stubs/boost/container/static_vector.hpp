// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once
#include <vector>
#include <memory>
namespace boost { namespace container {
template <class T, std::size_t N, class Allocator = std::allocator<T>>
class static_vector : public std::vector<T, Allocator> {
public:
    using std::vector<T, Allocator>::vector;
    static constexpr std::size_t static_capacity = N;
};
}}
