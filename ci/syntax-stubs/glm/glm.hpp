#pragma once
// Syntax-only shim - see ../README.md. The CPU core does not use glm; it only arrives
// through precompiled.h, so shapes need to exist, not to be correct.
#include <cmath>
namespace glm {
template <class T> struct tvec2 { T x{}, y{}; tvec2()=default; tvec2(T a,T b):x(a),y(b){} };
template <class T> struct tvec3 { T x{}, y{}, z{}; tvec3()=default; tvec3(T a,T b,T c):x(a),y(b),z(c){} };
template <class T> struct tvec4 { T x{}, y{}, z{}, w{}; tvec4()=default; tvec4(T a,T b,T c,T d):x(a),y(b),z(c),w(d){} };
using vec2 = tvec2<float>; using vec3 = tvec3<float>; using vec4 = tvec4<float>;
using ivec2 = tvec2<int>;  using ivec3 = tvec3<int>;  using ivec4 = tvec4<int>;
using uvec2 = tvec2<unsigned>; using uvec4 = tvec4<unsigned>;
struct mat4 { float m[16]{}; };
}
