#pragma once
// iOS Phase 0 minimal GLM stub
namespace glm {
    template<typename T> struct tvec2 { T x, y; };
    template<typename T> struct tvec3 { T x, y, z; };
    template<typename T> struct tvec4 { T x, y, z, w; };
    template<typename T> struct tmat4x4 { T m[16]; };
    using vec2 = tvec2<float>;
    using vec3 = tvec3<float>;
    using vec4 = tvec4<float>;
    using mat4 = tmat4x4<float>;
    template<typename T> inline tvec3<T> normalize(const tvec3<T>& v) { return v; }
    template<typename T> inline tvec3<T> cross(const tvec3<T>& a, const tvec3<T>& b) { return tvec3<T>{}; }
    template<typename T> inline T dot(const tvec3<T>& a, const tvec3<T>& b) { return T(0); }
}
