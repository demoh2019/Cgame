/**************************************************************************/
/*  cgame_facial_animation.h                                              */
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

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class MeshInstance3D;

// Procedural facial animation on ARKit-style blend shape names: emotion presets built from FACS
// action units, additive pain/aggression layers, viseme mixing, deterministic blinks and saccades.
// Mirrors scripts/client/facial_animation.gd. Output is a Dictionary of blend shape name to weight.
class CgameFacialAnimation : public RefCounted {
	GDCLASS(CgameFacialAnimation, RefCounted);

	int seed_value = 1;
	float additive_pain = 0.0f;
	float additive_aggression = 0.0f;
	bool blink_enabled = true;
	bool saccades_enabled = true;
	Vector<double> blink_starts;
	Vector<double> saccade_starts;

	float _rand(int p_salt, int p_k) const;
	Vector2 _saccade_target(int p_k) const;
	static int _upper_bound(const Vector<double> &p_values, double p_value);
	void _add_gaze(Dictionary &r_weights, float p_time);

protected:
	static void _bind_methods();

public:
	static constexpr float BLINK_DURATION = 0.2f;
	static constexpr float BLINK_MIN_INTERVAL = 2.0f;
	static constexpr float BLINK_MAX_INTERVAL = 6.0f;
	static constexpr float SACCADE_MIN_INTERVAL = 0.4f;
	static constexpr float SACCADE_MAX_INTERVAL = 2.0f;
	static constexpr float SACCADE_TRAVEL = 0.04f;
	static constexpr float SACCADE_AMPLITUDE = 0.35f;

	void set_seed(int p_seed);
	int get_seed() const;
	void set_additive_pain(float p_value);
	float get_additive_pain() const;
	void set_additive_aggression(float p_value);
	float get_additive_aggression() const;
	void set_blink_enabled(bool p_enabled);
	bool is_blink_enabled() const;
	void set_saccades_enabled(bool p_enabled);
	bool is_saccades_enabled() const;

	Dictionary evaluate(float p_time, const String &p_emotion, float p_emotion_weight, const Dictionary &p_viseme_weights);
	float blink_weight(float p_time);
	Vector2 gaze_at(float p_time);
	int apply_to(MeshInstance3D *p_mesh_instance, const Dictionary &p_weights) const;
	PackedStringArray get_emotion_names() const;

	CgameFacialAnimation();
};
