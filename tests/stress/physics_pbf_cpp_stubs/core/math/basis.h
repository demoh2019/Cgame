// Minimal affine Basis for standalone Cgame PBF rigid contact compiler tests.
// Not used by any actual engine build: `-Itests/stress/physics_pbf_cpp_stubs`
// is only passed to the isolated header smoke test.
#pragma once

#include "core/math/vector3.h"

struct Basis {
	Vector3 c0 = Vector3(1, 0, 0);
	Vector3 c1 = Vector3(0, 1, 0);
	Vector3 c2 = Vector3(0, 0, 1);

	Basis() = default;
	Basis(const Vector3 &a, const Vector3 &b, const Vector3 &c) : c0(a), c1(b), c2(c) {}
	static Basis from_scale(const Vector3 &p_scale) {
		return Basis(Vector3(p_scale.x,0,0),Vector3(0,p_scale.y,0),Vector3(0,0,p_scale.z));
	}
	bool is_finite() const { return c0.is_finite() && c1.is_finite() && c2.is_finite(); }
	Vector3 xform(const Vector3 &p_v) const {
		return c0*p_v.x+c1*p_v.y+c2*p_v.z;
	}
};
