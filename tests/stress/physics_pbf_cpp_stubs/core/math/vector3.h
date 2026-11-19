// Standalone PBF kernel compiler stub. This file is used ONLY with
// -Itests/stress/physics_pbf_cpp_stubs for float/double smoke tests.
// The native Godot engine always compiles its real core/math/vector3.h.
#pragma once

#include <cmath>

#ifndef _FORCE_INLINE_
#define _FORCE_INLINE_ inline
#endif

#ifdef CGAME_USE_DOUBLE
using real_t = double;
#else
using real_t = float;
#endif

#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef CLAMP
#define CLAMP(m_value, m_min, m_max) (MIN(MAX(m_value, m_min), m_max))
#endif

namespace Math {
constexpr double PI = 3.14159265358979323846264338327950288;
inline double sqrt(double p_value) { return std::sqrt(p_value); }
inline bool is_finite(double p_value) { return std::isfinite(p_value); }
} // namespace Math

struct Vector3 {
	real_t x = 0.0;
	real_t y = 0.0;
	real_t z = 0.0;
	Vector3() = default;
	Vector3(real_t p_x, real_t p_y, real_t p_z) : x(p_x), y(p_y), z(p_z) {}
	bool is_finite() const {
		return Math::is_finite(x) && Math::is_finite(y) && Math::is_finite(z);
	}
};
