/**************************************************************************/
/*  cgame_facial_animation.cpp                                            */
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

#include "cgame_facial_animation.h"

#include "core/object/class_db.h"
#include "scene/3d/mesh_instance_3d.h"

namespace {

struct ShapeWeight {
	const char *name;
	float weight;
};

struct ShapeSet {
	const char *key;
	Vector<ShapeWeight> shapes;
};

struct AuWeight {
	const char *au;
	float weight;
};

struct Emotion {
	const char *name;
	Vector<AuWeight> aus;
};

const Vector<ShapeSet> &au_shapes() {
	static const Vector<ShapeSet> table = [] {
		Vector<ShapeSet> t;
		const auto add = [&t](const char *p_key, std::initializer_list<ShapeWeight> p_list) {
			ShapeSet s;
			s.key = p_key;
			for (const ShapeWeight &w : p_list) {
				s.shapes.push_back(w);
			}
			t.push_back(s);
		};
		add("AU1", { { "browInnerUp", 1.0f } });
		add("AU2", { { "browOuterUpLeft", 1.0f }, { "browOuterUpRight", 1.0f } });
		add("AU4", { { "browDownLeft", 1.0f }, { "browDownRight", 1.0f } });
		add("AU5", { { "eyeWideLeft", 1.0f }, { "eyeWideRight", 1.0f } });
		add("AU6", { { "cheekSquintLeft", 1.0f }, { "cheekSquintRight", 1.0f }, { "eyeSquintLeft", 0.4f }, { "eyeSquintRight", 0.4f } });
		add("AU7", { { "eyeSquintLeft", 1.0f }, { "eyeSquintRight", 1.0f } });
		add("AU9", { { "noseSneerLeft", 1.0f }, { "noseSneerRight", 1.0f } });
		add("AU10", { { "mouthUpperUpLeft", 1.0f }, { "mouthUpperUpRight", 1.0f } });
		add("AU12", { { "mouthSmileLeft", 1.0f }, { "mouthSmileRight", 1.0f } });
		add("AU15", { { "mouthFrownLeft", 1.0f }, { "mouthFrownRight", 1.0f } });
		add("AU17", { { "mouthShrugLower", 1.0f } });
		add("AU20", { { "mouthStretchLeft", 1.0f }, { "mouthStretchRight", 1.0f } });
		add("AU23", { { "mouthPressLeft", 1.0f }, { "mouthPressRight", 1.0f } });
		add("AU25", { { "mouthLowerDownLeft", 0.4f }, { "mouthLowerDownRight", 0.4f } });
		add("AU26", { { "jawOpen", 1.0f } });
		add("AU45", { { "eyeBlinkLeft", 1.0f }, { "eyeBlinkRight", 1.0f } });
		return t;
	}();
	return table;
}

const Vector<Emotion> &emotions() {
	static const Vector<Emotion> table = [] {
		Vector<Emotion> t;
		const auto add = [&t](const char *p_name, std::initializer_list<AuWeight> p_list) {
			Emotion e;
			e.name = p_name;
			for (const AuWeight &w : p_list) {
				e.aus.push_back(w);
			}
			t.push_back(e);
		};
		add("neutral", {});
		add("happy", { { "AU6", 0.7f }, { "AU12", 0.85f } });
		add("sad", { { "AU1", 0.8f }, { "AU4", 0.4f }, { "AU15", 0.7f }, { "AU17", 0.3f } });
		add("angry", { { "AU4", 0.9f }, { "AU5", 0.3f }, { "AU7", 0.5f }, { "AU9", 0.3f }, { "AU10", 0.3f }, { "AU23", 0.6f } });
		add("fear", { { "AU1", 0.8f }, { "AU2", 0.6f }, { "AU5", 0.8f }, { "AU20", 0.6f }, { "AU26", 0.3f } });
		add("surprise", { { "AU1", 0.8f }, { "AU2", 0.8f }, { "AU5", 0.9f }, { "AU26", 0.6f } });
		add("disgust", { { "AU9", 0.8f }, { "AU10", 0.6f }, { "AU15", 0.3f }, { "AU17", 0.3f } });
		return t;
	}();
	return table;
}

const AuWeight PAIN_AUS[] = { { "AU1", 0.5f }, { "AU4", 0.6f }, { "AU6", 0.4f }, { "AU7", 0.8f }, { "AU20", 0.6f }, { "AU10", 0.3f } };
const AuWeight AGGRESSION_AUS[] = { { "AU4", 0.8f }, { "AU7", 0.4f }, { "AU9", 0.5f }, { "AU10", 0.5f }, { "AU23", 0.5f } };

const Vector<ShapeSet> &viseme_shapes() {
	static const Vector<ShapeSet> table = [] {
		Vector<ShapeSet> t;
		const auto add = [&t](const char *p_key, std::initializer_list<ShapeWeight> p_list) {
			ShapeSet s;
			s.key = p_key;
			for (const ShapeWeight &w : p_list) {
				s.shapes.push_back(w);
			}
			t.push_back(s);
		};
		add("A", { { "mouthPressLeft", 0.7f }, { "mouthPressRight", 0.7f }, { "mouthClose", 0.6f } });
		add("B", { { "jawOpen", 0.15f }, { "mouthStretchLeft", 0.3f }, { "mouthStretchRight", 0.3f } });
		add("C", { { "jawOpen", 0.45f }, { "mouthLowerDownLeft", 0.3f }, { "mouthLowerDownRight", 0.3f } });
		add("D", { { "jawOpen", 0.85f }, { "mouthLowerDownLeft", 0.5f }, { "mouthLowerDownRight", 0.5f }, { "mouthUpperUpLeft", 0.2f }, { "mouthUpperUpRight", 0.2f } });
		add("E", { { "jawOpen", 0.5f }, { "mouthFunnel", 0.5f } });
		add("F", { { "jawOpen", 0.2f }, { "mouthPucker", 0.8f }, { "mouthFunnel", 0.5f } });
		add("G", { { "jawOpen", 0.1f }, { "mouthRollLower", 0.6f }, { "mouthUpperUpLeft", 0.4f }, { "mouthUpperUpRight", 0.4f } });
		add("H", { { "jawOpen", 0.3f }, { "mouthLowerDownLeft", 0.2f }, { "mouthLowerDownRight", 0.2f } });
		add("X", {});
		return t;
	}();
	return table;
}

void add_value(Dictionary &r_weights, const String &p_shape, float p_value) {
	r_weights[p_shape] = float(r_weights.get(p_shape, 0.0f)) + p_value;
}

void add_shapes(Dictionary &r_weights, const Vector<ShapeWeight> &p_shapes, float p_scale) {
	for (const ShapeWeight &s : p_shapes) {
		add_value(r_weights, s.name, s.weight * p_scale);
	}
}

void add_au(Dictionary &r_weights, const String &p_au, float p_scale) {
	for (const ShapeSet &s : au_shapes()) {
		if (p_au == s.key) {
			add_shapes(r_weights, s.shapes, p_scale);
			return;
		}
	}
}

} // namespace

CgameFacialAnimation::CgameFacialAnimation() {
}

float CgameFacialAnimation::_rand(int p_salt, int p_k) const {
	int64_t x = (int64_t(p_k) * 374761393 + int64_t(seed_value) * 668265263 + int64_t(p_salt) * 2246822519LL) & 0x7fffffff;
	x = ((x ^ (x >> 13)) * 1274126177LL) & 0x7fffffff;
	x = (x ^ (x >> 16)) & 0x7fffffff;
	return float(x & 0xffff) / 65536.0f;
}

int CgameFacialAnimation::_upper_bound(const Vector<double> &p_values, double p_value) {
	int lo = 0;
	int hi = p_values.size();
	while (lo < hi) {
		const int mid = (lo + hi) / 2;
		if (p_values[mid] <= p_value) {
			lo = mid + 1;
		} else {
			hi = mid;
		}
	}
	return lo;
}

float CgameFacialAnimation::blink_weight(float p_time) {
	if (p_time < 0.0f) {
		return 0.0f;
	}
	while (blink_starts.is_empty() || blink_starts[blink_starts.size() - 1] <= p_time) {
		const int k = blink_starts.size();
		const double prev = k > 0 ? blink_starts[k - 1] : 0.0;
		const double gap = BLINK_MIN_INTERVAL + (BLINK_MAX_INTERVAL - BLINK_MIN_INTERVAL) * _rand(1, k);
		blink_starts.push_back(prev + gap);
	}
	const int idx = _upper_bound(blink_starts, p_time) - 1;
	if (idx < 0) {
		return 0.0f;
	}
	const float p = (p_time - blink_starts[idx]) / BLINK_DURATION;
	if (p < 0.0f || p > 1.0f) {
		return 0.0f;
	}
	return p < 0.35f ? p / 0.35f : 1.0f - (p - 0.35f) / 0.65f;
}

Vector2 CgameFacialAnimation::_saccade_target(int p_k) const {
	if (p_k < 0) {
		return Vector2();
	}
	return Vector2(_rand(3, p_k) * 2.0f - 1.0f, _rand(4, p_k) * 2.0f - 1.0f);
}

Vector2 CgameFacialAnimation::gaze_at(float p_time) {
	if (p_time < 0.0f) {
		return Vector2();
	}
	while (saccade_starts.is_empty() || saccade_starts[saccade_starts.size() - 1] <= p_time) {
		const int k = saccade_starts.size();
		const double prev = k > 0 ? saccade_starts[k - 1] : 0.0;
		saccade_starts.push_back(prev + SACCADE_MIN_INTERVAL + (SACCADE_MAX_INTERVAL - SACCADE_MIN_INTERVAL) * _rand(2, k));
	}
	const int idx = _upper_bound(saccade_starts, p_time) - 1;
	if (idx < 0) {
		return _saccade_target(-1);
	}
	const Vector2 cur = _saccade_target(idx);
	const Vector2 prev_target = _saccade_target(idx - 1);
	const float s = CLAMP((p_time - saccade_starts[idx]) / SACCADE_TRAVEL, 0.0f, 1.0f);
	return prev_target.lerp(cur, s);
}

void CgameFacialAnimation::_add_gaze(Dictionary &r_weights, float p_time) {
	const Vector2 g = gaze_at(p_time) * SACCADE_AMPLITUDE;
	const float right = MAX(g.x, 0.0f);
	const float left = MAX(-g.x, 0.0f);
	const float up = MAX(g.y, 0.0f);
	const float down = MAX(-g.y, 0.0f);
	add_value(r_weights, "eyeLookOutRight", right);
	add_value(r_weights, "eyeLookInLeft", right);
	add_value(r_weights, "eyeLookInRight", left);
	add_value(r_weights, "eyeLookOutLeft", left);
	for (const char *side : { "Left", "Right" }) {
		add_value(r_weights, String("eyeLookUp") + side, up);
		add_value(r_weights, String("eyeLookDown") + side, down);
	}
}

Dictionary CgameFacialAnimation::evaluate(float p_time, const String &p_emotion, float p_emotion_weight, const Dictionary &p_viseme_weights) {
	Dictionary w;
	for (const Emotion &e : emotions()) {
		if (p_emotion == e.name) {
			for (const AuWeight &a : e.aus) {
				add_au(w, a.au, a.weight * p_emotion_weight);
			}
			break;
		}
	}
	if (additive_pain > 0.0f) {
		for (const AuWeight &a : PAIN_AUS) {
			add_au(w, a.au, a.weight * additive_pain);
		}
	}
	if (additive_aggression > 0.0f) {
		for (const AuWeight &a : AGGRESSION_AUS) {
			add_au(w, a.au, a.weight * additive_aggression);
		}
	}
	for (const KeyValue<Variant, Variant> &kv : p_viseme_weights) {
		const String vname = kv.key;
		for (const ShapeSet &s : viseme_shapes()) {
			if (vname == s.key) {
				add_shapes(w, s.shapes, kv.value);
				break;
			}
		}
	}
	if (blink_enabled) {
		const float b = blink_weight(p_time);
		if (b > 0.0f) {
			for (const char *side : { "Left", "Right" }) {
				const String shape = String("eyeBlink") + side;
				w[shape] = MAX(float(w.get(shape, 0.0f)), b);
			}
		}
	}
	if (saccades_enabled) {
		_add_gaze(w, p_time);
	}
	for (const Variant &key : w.get_key_list()) {
		w[key] = CLAMP(float(w[key]), 0.0f, 1.0f);
	}
	return w;
}

int CgameFacialAnimation::apply_to(MeshInstance3D *p_mesh_instance, const Dictionary &p_weights) const {
	if (!p_mesh_instance || p_mesh_instance->get_mesh().is_null()) {
		return 0;
	}
	int applied = 0;
	for (const KeyValue<Variant, Variant> &kv : p_weights) {
		const int idx = p_mesh_instance->find_blend_shape_by_name(StringName(String(kv.key)));
		if (idx >= 0) {
			p_mesh_instance->set_blend_shape_value(idx, CLAMP(float(kv.value), 0.0f, 1.0f));
			applied++;
		}
	}
	return applied;
}

PackedStringArray CgameFacialAnimation::get_emotion_names() const {
	PackedStringArray names;
	for (const Emotion &e : emotions()) {
		names.push_back(e.name);
	}
	return names;
}

void CgameFacialAnimation::set_seed(int p_seed) {
	seed_value = p_seed;
	blink_starts.clear();
	saccade_starts.clear();
}
int CgameFacialAnimation::get_seed() const {
	return seed_value;
}
void CgameFacialAnimation::set_additive_pain(float p_value) {
	additive_pain = CLAMP(p_value, 0.0f, 1.0f);
}
float CgameFacialAnimation::get_additive_pain() const {
	return additive_pain;
}
void CgameFacialAnimation::set_additive_aggression(float p_value) {
	additive_aggression = CLAMP(p_value, 0.0f, 1.0f);
}
float CgameFacialAnimation::get_additive_aggression() const {
	return additive_aggression;
}
void CgameFacialAnimation::set_blink_enabled(bool p_enabled) {
	blink_enabled = p_enabled;
}
bool CgameFacialAnimation::is_blink_enabled() const {
	return blink_enabled;
}
void CgameFacialAnimation::set_saccades_enabled(bool p_enabled) {
	saccades_enabled = p_enabled;
}
bool CgameFacialAnimation::is_saccades_enabled() const {
	return saccades_enabled;
}

void CgameFacialAnimation::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &CgameFacialAnimation::set_seed);
	ClassDB::bind_method(D_METHOD("get_seed"), &CgameFacialAnimation::get_seed);
	ClassDB::bind_method(D_METHOD("set_additive_pain", "pain"), &CgameFacialAnimation::set_additive_pain);
	ClassDB::bind_method(D_METHOD("get_additive_pain"), &CgameFacialAnimation::get_additive_pain);
	ClassDB::bind_method(D_METHOD("set_additive_aggression", "aggression"), &CgameFacialAnimation::set_additive_aggression);
	ClassDB::bind_method(D_METHOD("get_additive_aggression"), &CgameFacialAnimation::get_additive_aggression);
	ClassDB::bind_method(D_METHOD("set_blink_enabled", "enabled"), &CgameFacialAnimation::set_blink_enabled);
	ClassDB::bind_method(D_METHOD("is_blink_enabled"), &CgameFacialAnimation::is_blink_enabled);
	ClassDB::bind_method(D_METHOD("set_saccades_enabled", "enabled"), &CgameFacialAnimation::set_saccades_enabled);
	ClassDB::bind_method(D_METHOD("is_saccades_enabled"), &CgameFacialAnimation::is_saccades_enabled);
	ClassDB::bind_method(D_METHOD("evaluate", "time", "emotion", "emotion_weight", "viseme_weights"), &CgameFacialAnimation::evaluate, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("blink_weight", "time"), &CgameFacialAnimation::blink_weight);
	ClassDB::bind_method(D_METHOD("gaze_at", "time"), &CgameFacialAnimation::gaze_at);
	ClassDB::bind_method(D_METHOD("apply_to", "mesh_instance", "weights"), &CgameFacialAnimation::apply_to);
	ClassDB::bind_method(D_METHOD("get_emotion_names"), &CgameFacialAnimation::get_emotion_names);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "additive_pain", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_additive_pain", "get_additive_pain");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "additive_aggression", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_additive_aggression", "get_additive_aggression");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "blink_enabled"), "set_blink_enabled", "is_blink_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "saccades_enabled"), "set_saccades_enabled", "is_saccades_enabled");
}
