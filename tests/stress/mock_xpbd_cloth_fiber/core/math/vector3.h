// Minimal Vector3 ABI for standalone testing of the actual cloth fiber
// helper. Test-only; never compiled into Cgame.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

#if defined(TEST_REAL_T_DOUBLE)
using real_t = double;
#else
using real_t = float;
#endif

#define _FORCE_INLINE_ inline
#define CLAMP(value, lo, hi) std::max((lo), std::min((value), (hi)))
#define MIN(a, b) std::min((a), (b))

namespace Math {
template <typename T>
inline bool is_finite(T p_value) { return std::isfinite(p_value); }
}

struct Vector3 {
	real_t x = 0, y = 0, z = 0;
	constexpr Vector3() = default;
	constexpr Vector3(real_t p_x, real_t p_y, real_t p_z) : x(p_x), y(p_y), z(p_z) {}
	bool is_finite() const {
		return Math::is_finite(x) && Math::is_finite(y) && Math::is_finite(z);
	}
};
