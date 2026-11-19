// Minimal standalone substitute for Godot's vector3.h used ONLY by the
// specialized C++ header compiler smoke check. Full engine builds use the
// real core/math/vector3.h and do not include this directory.
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

namespace Math {
inline bool is_finite(double p_x) { return std::isfinite(p_x); }
inline double sqrt(double p_x) { return std::sqrt(p_x); }
} // namespace Math

struct Vector3 {
	real_t x = 0.0;
	real_t y = 0.0;
	real_t z = 0.0;

	Vector3() = default;
	Vector3(real_t p_x, real_t p_y, real_t p_z) :
			x(p_x), y(p_y), z(p_z) {}

	bool is_finite() const {
		return Math::is_finite(x) && Math::is_finite(y) && Math::is_finite(z);
	}
};
