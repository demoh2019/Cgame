/**************************************************************************/
/*  physics_contact_static_friction.h                                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Simplified PhysX-style static/dynamic Coulomb friction. The material's
// regular coefficient is the dynamic friction coefficient; a space-wide
// multiplier (>= 1) controls the larger static cone. If a candidate impulse
// lies inside the static cone, the solver can stop sliding and stick.
// Otherwise the full dynamic cone is used, not a clamped static impulse.
// Passing multiplier 1 reduces to the legacy single cone.
_FORCE_INLINE_ static real_t godot_physics_clamp_static_friction_2d(real_t p_candidate, real_t p_dynamic_limit, real_t p_static_multiplier) {
	const real_t dynamic_limit = MAX(real_t(0.0), p_dynamic_limit);
	const real_t static_limit = dynamic_limit * MAX(real_t(1.0), p_static_multiplier);
	if (Math::abs(p_candidate) <= static_limit) {
		return p_candidate;
	}
	return CLAMP(p_candidate, -dynamic_limit, dynamic_limit);
}

_FORCE_INLINE_ static Vector3 godot_physics_clamp_static_friction_3d(const Vector3 &p_candidate, real_t p_dynamic_limit, real_t p_static_multiplier) {
	const real_t dynamic_limit = MAX(real_t(0.0), p_dynamic_limit);
	const real_t static_limit = dynamic_limit * MAX(real_t(1.0), p_static_multiplier);
	const real_t candidate_length_squared = p_candidate.length_squared();
	if (candidate_length_squared <= static_limit * static_limit) {
		return p_candidate;
	}
	if (dynamic_limit == real_t(0.0) || candidate_length_squared == real_t(0.0)) {
		return Vector3();
	}
	// The square root is only needed when the static cone fails.
	return p_candidate * (dynamic_limit / Math::sqrt(candidate_length_squared));
}
