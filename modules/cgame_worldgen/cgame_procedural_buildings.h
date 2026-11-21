/**************************************************************************/
/*  cgame_procedural_buildings.h                                          */
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

#include "core/math/rect2i.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class RandomNumberGenerator;

class CgameProceduralBuildings : public RefCounted {
	GDCLASS(CgameProceduralBuildings, RefCounted);

	struct Room {
		int id = 0;
		int floor = 0;
		Rect2i rect;
	};

	struct Door {
		int floor = 0;
		int a = 0;
		int b = 0;
		Vector2i cell_a;
		Vector2i cell_b;
	};

	struct Entrance {
		bool valid = false;
		int room = 0;
		Vector2i cell;
		Vector2i normal;
	};

	static void _split(const Rect2i &p_rect, RandomNumberGenerator &p_rng, Vector<Rect2i> &r_out);
	static Vector<Door> _doors_for_floor(int p_floor, const Vector<Room> &p_rooms, RandomNumberGenerator &p_rng);
	static int _find(const Vector<int> &p_parent, int p_i);
	static Entrance _entrance(const Vector<Room> &p_rooms, const Vector2i &p_footprint, RandomNumberGenerator &p_rng);
	static void _windows_for_floor(int p_floor, const Vector<Room> &p_rooms, const Vector2i &p_footprint, const Entrance &p_entrance, Array &r_out);
	static bool _too_close(const Vector2 &p_cand, const Vector<Vector2> &p_pts, const HashMap<Vector2i, int> &p_grid, double p_cell, double p_d);

protected:
	static void _bind_methods();

public:
	static constexpr int MIN_ROOM = 3;
	static constexpr int MIN_LOT = 4;
	static constexpr double MIN_LOT_SPACING = 6.0;
	static constexpr double LOOP_CHANCE = 0.25;
	static constexpr int BRIDSON_TRIES = 30;

	static Dictionary building(int64_t p_seed, const Vector2i &p_footprint, int p_floors);
	static Array settlement(int64_t p_seed, const Vector2 &p_center, double p_radius, int p_count);
};
