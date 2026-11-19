// Minimal test-only vector for compiling real FEM kernel headers.
#pragma once
#include <cmath>
#include <cstdint>
#ifdef CGAME_USE_DOUBLE
using real_t = double;
#else
using real_t = float;
#endif
#define _FORCE_INLINE_ inline
#define MAX(a,b) ((a) > (b) ? (a) : (b))

namespace Math {
inline bool is_finite(double v) { return std::isfinite(v); }
inline double sqrt(double v) { return std::sqrt(v); }
inline double abs(double v) { return std::abs(v); }
inline double log(double v) { return std::log(v); }
}

struct Vector3 {
	real_t x = 0, y = 0, z = 0;
	Vector3() = default;
	Vector3(real_t p_x, real_t p_y, real_t p_z) : x(p_x), y(p_y), z(p_z) {}
	bool is_finite() const { return Math::is_finite(x) && Math::is_finite(y) && Math::is_finite(z); }
	const real_t &operator[](int i) const { return i == 0 ? x : (i == 1 ? y : z); }
	real_t &operator[](int i) { return i == 0 ? x : (i == 1 ? y : z); }
};
