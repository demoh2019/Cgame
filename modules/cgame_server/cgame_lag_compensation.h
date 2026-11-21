/**************************************************************************/
/*  cgame_lag_compensation.h                                              */
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

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"

// Server-side lag compensation (rewind): a short history of every survivor's position lets the
// server judge a PvP swing or shot against where the target was on the attacker's screen, i.e.
// half the round trip plus the client's interpolation delay ago. Rewind is capped so high-ping
// players cannot hit around corners.
class CgameLagCompensation : public RefCounted {
	GDCLASS(CgameLagCompensation, RefCounted);

public:
	static constexpr double HISTORY_SECONDS = 0.5;
	static constexpr double MAX_REWIND = 0.25;
	static constexpr double CLIENT_INTERPOLATION = 0.12;

private:
	struct Sample {
		double time = 0.0;
		Vector3 position;
	};

	HashMap<int, Vector<Sample>> history;

protected:
	static void _bind_methods();

public:
	void record(int p_id, double p_now, const Vector3 &p_position);
	void forget(int p_id);
	void prune(const Dictionary &p_alive_ids);
	int sample_count(int p_id) const;
	static double rewind_for(double p_round_trip);
	Vector3 position_at(int p_id, double p_at, const Vector3 &p_fallback) const;

	static double get_history_seconds() { return HISTORY_SECONDS; }
	static double get_max_rewind() { return MAX_REWIND; }
	static double get_client_interpolation() { return CLIENT_INTERPOLATION; }
};
