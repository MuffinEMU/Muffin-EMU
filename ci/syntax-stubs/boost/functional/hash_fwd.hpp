#pragma once
#include <cstddef>
#include <functional>
namespace boost {
template <class T> std::size_t hash_value(const T&) { return 0; }
template <class T> struct hash : std::hash<T> {};
template <class T> void hash_combine(std::size_t&, const T&) {}
}
