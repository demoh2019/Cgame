/**************************************************************************/
/*  cgame_utility_ai.cpp                                                  */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "cgame_utility_ai.h"

#include "core/math/math_funcs.h"

double CgameUtilityAI::curve(int p_kind, double p_x, double p_slope, double p_shift) {
	if (!Math::is_finite(p_x) || !Math::is_finite(p_slope) || !Math::is_finite(p_shift)) {
		return 0.0;
	}
	double v = CLAMP(p_x, 0.0, 1.0);
	switch (p_kind) {
		case QUADRATIC: {
			v = v * v;
		} break;
		case INVERSE_QUADRATIC: {
			v = 1.0 - (1.0 - v) * (1.0 - v);
		} break;
		case LOGISTIC: {
			v = 1.0 / (1.0 + Math::exp(-10.0 * p_slope * (v - 0.5 - p_shift)));
		} break;
		case STEP: {
			v = v >= 0.5 + p_shift ? 1.0 : 0.0;
		} break;
		default: {
			v = v * p_slope + p_shift;
		} break;
	}
	return Math::is_finite(v) ? CLAMP(v, 0.0, 1.0) : 0.0;
}

double CgameUtilityAI::combine(const PackedFloat32Array &p_scores) {
	if (p_scores.is_empty()) {
		return 0.0;
	}
	double total = 1.0;
	for (int i = 0; i < p_scores.size(); i++) {
		if (!Math::is_finite(p_scores[i])) {
			return 0.0;
		}
		total *= CLAMP(double(p_scores[i]), 0.0, 1.0);
		if (total <= 0.0) {
			return 0.0;
		}
	}
	const double modification = 1.0 - 1.0 / double(p_scores.size());
	const double make_up = (1.0 - total) * modification;
	return total + make_up * total;
}

int CgameUtilityAI::best(const PackedFloat32Array &p_scores) {
	int index = -1;
	double top = 0.0;
	for (int i = 0; i < p_scores.size(); i++) {
		if (Math::is_finite(p_scores[i]) && double(p_scores[i]) > top) {
			top = p_scores[i];
			index = i;
		}
	}
	return index;
}

double CgameUtilityAI::infected_target_score(double p_distance, double p_leash, double p_health_fraction, bool p_is_current, bool p_noisy) {
	if (!Math::is_finite(p_distance) || p_distance < 0.0 || !Math::is_finite(p_leash) || p_leash <= 0.0) {
		return 0.0;
	}
	if (p_distance > p_leash) {
		// The leash itself is enforced by the chase state; an existing focus is never dropped here.
		return p_is_current ? 0.01 : 0.0;
	}
	double proximity = curve(INVERSE_QUADRATIC, 1.0 - p_distance / p_leash);
	// Never fully zero at the leash edge: perception already gated the candidate.
	proximity = MAX(proximity, 0.02);
	const double weakness = 1.0 - CLAMP(Math::is_finite(p_health_fraction) ? p_health_fraction : 1.0, 0.0, 1.0);
	const double appetite = 1.0 + WOUNDED_BONUS * curve(QUADRATIC, weakness);
	const double focus = 1.0 + (p_is_current ? STICKY_BONUS : 0.0);
	const double lure = 1.0 + (p_noisy ? NOISE_BONUS : 0.0);
	return proximity * appetite * focus * lure;
}

void CgameUtilityAI::_bind_methods() {
	ClassDB::bind_static_method("CgameUtilityAI", D_METHOD("curve", "kind", "x", "slope", "shift"), &CgameUtilityAI::curve, DEFVAL(1.0), DEFVAL(0.0));
	ClassDB::bind_static_method("CgameUtilityAI", D_METHOD("combine", "scores"), &CgameUtilityAI::combine);
	ClassDB::bind_static_method("CgameUtilityAI", D_METHOD("best", "scores"), &CgameUtilityAI::best);
	ClassDB::bind_static_method("CgameUtilityAI", D_METHOD("infected_target_score", "distance", "leash", "health_fraction", "is_current", "noisy"), &CgameUtilityAI::infected_target_score);

	BIND_ENUM_CONSTANT(LINEAR);
	BIND_ENUM_CONSTANT(QUADRATIC);
	BIND_ENUM_CONSTANT(INVERSE_QUADRATIC);
	BIND_ENUM_CONSTANT(LOGISTIC);
	BIND_ENUM_CONSTANT(STEP);
}
