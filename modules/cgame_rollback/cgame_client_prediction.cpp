/**************************************************************************/
/*  cgame_client_prediction.cpp                                           */
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

#include "cgame_client_prediction.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

Dictionary CgameClientPrediction::_apply(const Dictionary &p_state, const Dictionary &p_input, double p_dt) const {
	ERR_FAIL_COND_V_MSG(!apply.is_valid(), p_state, "CgameClientPrediction: no valid apply callable.");
	Variant args[3] = { p_state.duplicate(true), p_input.duplicate(true), p_dt };
	const Variant *argp[3] = { &args[0], &args[1], &args[2] };
	Variant ret;
	Callable::CallError ce;
	apply.callp(argp, 3, ret, ce);
	ERR_FAIL_COND_V_MSG(ce.error != Callable::CallError::CALL_OK || ret.get_type() != Variant::DICTIONARY, p_state, "CgameClientPrediction: apply callable must return a Dictionary.");
	return ret;
}

Variant CgameClientPrediction::_evaluate(Variant::Operator p_op, const Variant &p_a, const Variant &p_b) {
	Variant r;
	bool valid = false;
	Variant::evaluate(p_op, p_a, p_b, r, valid);
	return valid ? r : Variant(0.0);
}

double CgameClientPrediction::_magnitude(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::INT:
		case Variant::FLOAT:
			return Math::abs(double(p_value));
		case Variant::VECTOR2:
			return double(Vector2(p_value).length());
		case Variant::VECTOR3:
			return double(Vector3(p_value).length());
		case Variant::VECTOR4:
			return double(Vector4(p_value).length());
		default:
			return 0.0;
	}
}

Variant CgameClientPrediction::_zero_like(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::VECTOR2:
			return Vector2();
		case Variant::VECTOR3:
			return Vector3();
		case Variant::VECTOR4:
			return Vector4();
		default:
			return 0.0;
	}
}

void CgameClientPrediction::setup(const Callable &p_apply, const Dictionary &p_initial_state, const String &p_position_key,
		double p_error_threshold, double p_smoothing_rate) {
	apply = p_apply;
	state = p_initial_state.duplicate(true);
	position_key = p_position_key;
	error_threshold = p_error_threshold;
	smoothing_rate = p_smoothing_rate;
	next_seq = 1;
	last_acked_seq = 0;
	pending.clear();
	snaps = 0;
	last_error = 0.0;
	visual_offset = _zero_like(state.get(position_key, 0.0));
}

// Applies `input` locally and queues it. Returns its sequence number (send it to the server).
int64_t CgameClientPrediction::predict(const Dictionary &p_input, double p_dt) {
	int64_t seq = next_seq;
	next_seq++;
	state = _apply(state, p_input, p_dt);
	PendingInput entry;
	entry.seq = seq;
	entry.input = p_input.duplicate(true);
	entry.dt = p_dt;
	pending.push_back(entry);
	if (pending.size() > max_pending) {
		pending.pop_front();
	}
	return seq;
}

// Server ack. Returns the position error (magnitude) between the old prediction and the server-corrected
// re-prediction. Stale acks (older than the last one) are ignored.
double CgameClientPrediction::reconcile(const Dictionary &p_server_state, int64_t p_last_processed_seq) {
	if (p_last_processed_seq < last_acked_seq) {
		return 0.0;
	}
	last_acked_seq = p_last_processed_seq;
	Variant old_pos = state.get(position_key, 0.0);
	while (!pending.is_empty() && pending.front()->get().seq <= p_last_processed_seq) {
		pending.pop_front();
	}
	Dictionary s = p_server_state.duplicate(true);
	for (const PendingInput &e : pending) {
		s = _apply(s, e.input, e.dt);
	}
	state = s;
	Variant new_pos = state.get(position_key, 0.0);
	Variant diff = _evaluate(Variant::OP_SUBTRACT, old_pos, new_pos);
	double err = _magnitude(diff);
	last_error = err;
	if (err > error_threshold) {
		visual_offset = _zero_like(new_pos);
		snaps++;
	} else {
		visual_offset = _evaluate(Variant::OP_ADD, visual_offset, diff);
	}
	return err;
}

// Decays the visual correction offset (call once per rendered frame).
void CgameClientPrediction::update(double p_delta) {
	visual_offset = _evaluate(Variant::OP_MULTIPLY, visual_offset, Math::exp(-smoothing_rate * p_delta));
}

double CgameClientPrediction::offset_magnitude() const {
	return _magnitude(visual_offset);
}

// Predicted state with the smoothed correction offset applied to the position entry.
Dictionary CgameClientPrediction::visual_state() const {
	Dictionary v = state.duplicate(true);
	if (v.has(position_key)) {
		v[position_key] = _evaluate(Variant::OP_ADD, v[position_key], visual_offset);
	}
	return v;
}

void CgameClientPrediction::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "apply", "initial_state", "position_key", "error_threshold", "smoothing_rate"), &CgameClientPrediction::setup, DEFVAL("pos"), DEFVAL(2.0), DEFVAL(10.0));
	ClassDB::bind_method(D_METHOD("predict", "input", "dt"), &CgameClientPrediction::predict);
	ClassDB::bind_method(D_METHOD("pending_count"), &CgameClientPrediction::pending_count);
	ClassDB::bind_method(D_METHOD("reconcile", "server_state", "last_processed_seq"), &CgameClientPrediction::reconcile);
	ClassDB::bind_method(D_METHOD("update", "delta"), &CgameClientPrediction::update);
	ClassDB::bind_method(D_METHOD("offset_magnitude"), &CgameClientPrediction::offset_magnitude);
	ClassDB::bind_method(D_METHOD("visual_state"), &CgameClientPrediction::visual_state);

	ClassDB::bind_method(D_METHOD("get_state"), &CgameClientPrediction::get_state);
	ClassDB::bind_method(D_METHOD("get_position_key"), &CgameClientPrediction::get_position_key);
	ClassDB::bind_method(D_METHOD("set_error_threshold", "threshold"), &CgameClientPrediction::set_error_threshold);
	ClassDB::bind_method(D_METHOD("get_error_threshold"), &CgameClientPrediction::get_error_threshold);
	ClassDB::bind_method(D_METHOD("set_smoothing_rate", "rate"), &CgameClientPrediction::set_smoothing_rate);
	ClassDB::bind_method(D_METHOD("get_smoothing_rate"), &CgameClientPrediction::get_smoothing_rate);
	ClassDB::bind_method(D_METHOD("set_max_pending", "max_pending"), &CgameClientPrediction::set_max_pending);
	ClassDB::bind_method(D_METHOD("get_max_pending"), &CgameClientPrediction::get_max_pending);
	ClassDB::bind_method(D_METHOD("get_next_seq"), &CgameClientPrediction::get_next_seq);
	ClassDB::bind_method(D_METHOD("get_last_acked_seq"), &CgameClientPrediction::get_last_acked_seq);
	ClassDB::bind_method(D_METHOD("get_last_error"), &CgameClientPrediction::get_last_error);
	ClassDB::bind_method(D_METHOD("get_snaps"), &CgameClientPrediction::get_snaps);
	ClassDB::bind_method(D_METHOD("get_visual_offset"), &CgameClientPrediction::get_visual_offset);

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "state"), "", "get_state");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "position_key"), "", "get_position_key");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "error_threshold"), "set_error_threshold", "get_error_threshold");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "smoothing_rate"), "set_smoothing_rate", "get_smoothing_rate");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_pending"), "set_max_pending", "get_max_pending");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "next_seq"), "", "get_next_seq");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "last_acked_seq"), "", "get_last_acked_seq");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "last_error"), "", "get_last_error");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "snaps"), "", "get_snaps");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "visual_offset", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NIL_IS_VARIANT), "", "get_visual_offset");
}
