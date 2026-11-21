/**************************************************************************/
/*  cgame_world_sharding.h                                                */
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

#include "cgame_server_macros.h"

#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

// World sharding planner: grid regions -> zone servers, load rebalancing with hysteresis, ghost
// (interest) replication near borders and an idempotent two-step player handoff.
class CgameWorldSharding : public RefCounted {
	GDCLASS(CgameWorldSharding, RefCounted);

	double cell_size = 100.0;
	int cols = 4;
	int rows = 4;
	int server_count = 2;
	double border_margin = 15.0;
	double handoff_hysteresis = 3.0;
	double imbalance_ratio = 1.25;
	int max_moves = 8;

	PackedInt32Array region_owner;
	Dictionary entity_owner;
	Dictionary players;
	Dictionary transfers;

	static double _load(const Array &p_loads, int p_region);

protected:
	static void _bind_methods();

public:
	CGAME_ACCESSORS(double, cell_size)
	CGAME_ACCESSORS(int, cols)
	CGAME_ACCESSORS(int, rows)
	CGAME_ACCESSORS(int, server_count)
	CGAME_ACCESSORS(double, border_margin)
	CGAME_ACCESSORS(double, handoff_hysteresis)
	CGAME_ACCESSORS(double, imbalance_ratio)
	CGAME_ACCESSORS(int, max_moves)
	CGAME_ACCESSORS(PackedInt32Array, region_owner)
	CGAME_ACCESSORS(Dictionary, entity_owner)
	CGAME_ACCESSORS(Dictionary, players)
	CGAME_ACCESSORS(Dictionary, transfers)

	void setup(int p_cols, int p_rows, double p_cell, int p_servers);
	int region_count() const;
	int region_of(const Vector2 &p_pos) const;
	int owner_at(const Vector2 &p_pos) const;
	Array server_loads(const Array &p_loads) const;
	void assign_initial(const Array &p_loads);
	Array rebalance(const Array &p_loads);

	void claim_entity(const String &p_entity_id, int p_server);
	int owner_of(const String &p_entity_id) const;
	Array entities_on(int p_server) const;
	Array ghost_servers(const Vector2 &p_pos, int p_owner) const;
	int handoff_needed(const Vector2 &p_player_pos, int p_current_server) const;
	void track_player(const String &p_player_id, const Vector2 &p_pos, int p_server);
	Dictionary update_player(const String &p_player_id, const Vector2 &p_pos);

	String begin_transfer(const String &p_player_id, int p_to_server, const String &p_transfer_id);
	bool send_state(const String &p_transfer_id, const Dictionary &p_payload);
	bool ack_transfer(const String &p_transfer_id);
	bool release_transfer(const String &p_transfer_id);
	bool abort_transfer(const String &p_transfer_id);
};
