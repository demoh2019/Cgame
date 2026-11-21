/**************************************************************************/
/*  cgame_utility_ai.h                                                    */
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

#pragma once

#include "cgame_ai_common.h"

#include "core/object/ref_counted.h"

// Utility AI (Dave Mark's Infinite Axis Utility System): options are scored by
// multiplying normalised considerations shaped by response curves, with a
// compensation factor so options with many considerations are not punished.
class CgameUtilityAI : public RefCounted {
	GDCLASS(CgameUtilityAI, RefCounted);

public:
	enum Response {
		LINEAR,
		QUADRATIC,
		INVERSE_QUADRATIC,
		LOGISTIC,
		STEP,
	};

	static constexpr double WOUNDED_BONUS = 0.35;
	static constexpr double STICKY_BONUS = 0.25;
	static constexpr double NOISE_BONUS = 0.15;

protected:
	static void _bind_methods();

public:
	static double curve(int p_kind, double p_x, double p_slope = 1.0, double p_shift = 0.0);
	static double combine(const PackedFloat32Array &p_scores);
	static int best(const PackedFloat32Array &p_scores);
	static double infected_target_score(double p_distance, double p_leash, double p_health_fraction, bool p_is_current, bool p_noisy);
};

VARIANT_ENUM_CAST(CgameUtilityAI::Response);
