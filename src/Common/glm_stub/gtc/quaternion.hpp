#pragma once
namespace glm {
    template<typename T> struct tquat { T x, y, z, w; };
    using quat = tquat<float>;
}
