/**************************************************************************/
/*  ai_threat_table_2d.h                                                    */
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

#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Server-facing, opt-in MMO-style threat arithmetic over caller-owned
// dictionaries: peer_id -> hate value. State remains owned by each NPC;
// this class itself never allocates or retains a per-player threat ledger.
// The game is responsible for validating actual damage and visibility.
class AIThreatTable2D : public RefCounted {
	GDCLASS(AIThreatTable2D, RefCounted);

	static constexpr int MAX_TARGETS = 5;
	static constexpr double MAX_VALUE = 10000.0;
	static constexpr double DECAY_PER_SECOND = 0.75;
	static constexpr double SWITCH_MARGIN = 1.25;

	static bool _valid_threat(const Variant &p_amount, double &r_value);

protected:
	static void _bind_methods();

public:
	// Dictionary is a reference-counted container; methods mutate the
	// supplied table in place, and do not copy or persist it.
	bool record(Dictionary p_entries, int64_t p_peer_id, double p_damage) const;
	// Modify a single existing target's threat without creating new aggro.
	// Factor must be finite and in [0, 1], with zero forgetting the target.
	bool scale(Dictionary p_entries, int64_t p_peer_id, double p_factor) const;
	void decay(Dictionary p_entries, double p_delta) const;
	int64_t pick(Dictionary p_entries, const Dictionary &p_players, const Vector2 &p_origin, double p_leash, int64_t p_current_target = -1) const;
};
