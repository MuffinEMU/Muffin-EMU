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
