/**************************************************************************/
/*  cgame_formations.h                                                    */
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

// Group formations: slot layouts in leader space (+X forward, +Y right), minimal
// distance slot assignment (Hungarian / Kuhn-Munkres), smooth formation changes
// and obstacle-aware slot shifting.
class CgameFormations : public RefCounted {
	GDCLASS(CgameFormations, RefCounted);

public:
	enum {
		HUNGARIAN_LIMIT = 64,
	};

private:
	static Vector<int> _hungarian(const Vector<double> &p_cost, int p_n, int p_m);
	static Vector<int> _greedy(const Vector<Vector2> &p_slots, const Vector<Vector2> &p_members);
	static bool _too_close(const Vector2 &p_c, const Vector<Vector2> &p_placed, double p_min_sep);

protected:
	static void _bind_methods();

public:
	static PackedStringArray get_kinds();
	static PackedVector2Array slots(const String &p_kind, int p_count, double p_spacing);
	static PackedVector2Array targets(const Vector2 &p_leader_pos, double p_leader_heading, const String &p_kind, int p_count, double p_spacing);
	static PackedInt32Array assign(const PackedVector2Array &p_slots_world, const PackedVector2Array &p_members);
	static double assignment_cost(const PackedVector2Array &p_slots_world, const PackedVector2Array &p_members, const PackedInt32Array &p_assignment);
	static PackedVector2Array blend(const PackedVector2Array &p_from_slots, const PackedVector2Array &p_to_slots, double p_t);
	static PackedVector2Array smooth(const PackedVector2Array &p_current, const PackedVector2Array &p_goal, double p_dt, double p_rate = 6.0);
	static PackedVector2Array shift_slots(const PackedVector2Array &p_slots_world, const Callable &p_walkable, const Vector2 &p_leader_pos, double p_spacing, int p_rings = 6);
};
