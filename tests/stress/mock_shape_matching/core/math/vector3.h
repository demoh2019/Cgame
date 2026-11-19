// Test-only minimal Vector3 substitute used by the standalone compiler
// check. Not linked into Cgame and not used by the actual physics engine.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

using real_t = float;
inline constexpr float CMP_EPSILON = 0.00001f;
#define _FORCE_INLINE_ inline
#define CLAMP(value, low, high) std::max((low), std::min((value), (high)))
#define MAX(a, b) std::max((a), (b))
#define MIN(a, b) std::min((a), (b))
#define SWAP(a, b) std::swap((a), (b))

namespace Math {
template <typename T>
inline bool is_finite(T v) { return std::isfinite(v); }
template <typename T>
inline T sqrt(T v) { return std::sqrt(v); }
template <typename T>
inline T abs(T v) { return std::abs(v); }
}

struct Vector3 {
	real_t x = 0, y = 0, z = 0;
	constexpr Vector3() = default;
	constexpr Vector3(real_t px, real_t py, real_t pz) : x(px), y(py), z(pz) {}
	Vector3 operator+(const Vector3 &v) const { return Vector3(x + v.x, y + v.y, z + v.z); }
	Vector3 operator-(const Vector3 &v) const { return Vector3(x - v.x, y - v.y, z - v.z); }
	Vector3 operator-() const { return Vector3(-x, -y, -z); }
	Vector3 operator*(real_t s) const { return Vector3(x * s, y * s, z * s); }
	Vector3 operator/(real_t s) const { return Vector3(x / s, y / s, z / s); }
	bool operator==(const Vector3 &v) const { return x == v.x && y == v.y && z == v.z; }
	Vector3 lerp(const Vector3 &v, real_t weight) const { return *this + (v - *this) * weight; }
	real_t dot(const Vector3 &v) const { return x * v.x + y * v.y + z * v.z; }
	Vector3 cross(const Vector3 &v) const {
		return Vector3(y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x);
	}
	real_t length_squared() const { return dot(*this); }
	real_t length() const { return std::sqrt(length_squared()); }
	real_t distance_squared_to(const Vector3 &v) const { return (*this - v).length_squared(); }
	real_t distance_to(const Vector3 &v) const { return std::sqrt(distance_squared_to(v)); }
	bool is_finite() const { return Math::is_finite(x) && Math::is_finite(y) && Math::is_finite(z); }
	Vector3 normalized() const {
		const real_t len = std::sqrt(length_squared());
		return len > 0.0f ? *this / len : Vector3();
	}
	void normalize() { *this = normalized(); }
};
inline Vector3 operator*(real_t s, const Vector3 &v) { return v * s; }
