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
