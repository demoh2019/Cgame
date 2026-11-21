/**************************************************************************/
/*  cgame_client_prediction.h                                             */
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
#include "core/string/ustring.h"
#include "core/templates/list.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"

// Server-authoritative movement prediction (Quake / Overwatch / Gabriel Gambetta style).
// The client applies inputs locally at once and keeps them with sequence numbers. When the server
// acknowledges `last_processed_seq` with its authoritative state, reconcile() drops the acknowledged inputs and
// replays the remaining ones on top of the server state. The jump between the old and the re-predicted position
// is folded into a visual offset that decays exponentially; errors above `error_threshold` snap instantly.
class CgameClientPrediction : public RefCounted {
	GDCLASS(CgameClientPrediction, RefCounted);

	struct PendingInput {
		int64_t seq = 0;
		Dictionary input;
		double dt = 0.0;
	};

	Callable apply;
	Dictionary state;
	String position_key = "pos";
	double error_threshold = 2.0;
	double smoothing_rate = 10.0;
	int64_t max_pending = 256;

	int64_t next_seq = 1;
	int64_t last_acked_seq = 0;
	double last_error = 0.0;
	int64_t snaps = 0;
	Variant visual_offset = 0.0;

	List<PendingInput> pending;

	Dictionary _apply(const Dictionary &p_state, const Dictionary &p_input, double p_dt) const;
	static Variant _evaluate(Variant::Operator p_op, const Variant &p_a, const Variant &p_b);
	static double _magnitude(const Variant &p_value);
	static Variant _zero_like(const Variant &p_value);

protected:
	static void _bind_methods();

public:
	void setup(const Callable &p_apply, const Dictionary &p_initial_state, const String &p_position_key = "pos",
			double p_error_threshold = 2.0, double p_smoothing_rate = 10.0);
	int64_t predict(const Dictionary &p_input, double p_dt);
	int64_t pending_count() const { return pending.size(); }
	double reconcile(const Dictionary &p_server_state, int64_t p_last_processed_seq);
	void update(double p_delta);
	double offset_magnitude() const;
	Dictionary visual_state() const;

	Dictionary get_state() const { return state; }
	String get_position_key() const { return position_key; }
	void set_error_threshold(double p_threshold) { error_threshold = p_threshold; }
	double get_error_threshold() const { return error_threshold; }
	void set_smoothing_rate(double p_rate) { smoothing_rate = p_rate; }
	double get_smoothing_rate() const { return smoothing_rate; }
	void set_max_pending(int64_t p_max) { max_pending = p_max; }
	int64_t get_max_pending() const { return max_pending; }
	int64_t get_next_seq() const { return next_seq; }
	int64_t get_last_acked_seq() const { return last_acked_seq; }
	double get_last_error() const { return last_error; }
	int64_t get_snaps() const { return snaps; }
	Variant get_visual_offset() const { return visual_offset; }
};
