/**************************************************************************/
/*  cgame_off_mesh_link_generator.h                                       */
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
#include "core/templates/rid.h"
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

// Automatic off-mesh link generation from a heightfield.
// Traversals the walkable grid cannot express (ledge drops, small climbs, short gaps) become
// explicit links. Links can optionally be created on a NavigationServer3D map as server links
// (the same primitive NavigationLink3D uses).
//
// Link kinds:
//   "drop" - one-way ledge down between adjacent walkable cells (gap > walk_step, <= max_drop).
//   "jump" - bidirectional climb between adjacent walkable cells (gap in (walk_step, max_jump_up]).
//   "gap"  - bidirectional hop over 1..max_gap unwalkable cells between walkable cells of similar height.
class CgameOffMeshLinkGenerator : public RefCounted {
	GDCLASS(CgameOffMeshLinkGenerator, RefCounted);

public:
	struct Link {
		Vector2i from;
		Vector2i to;
		String kind;
		bool bidirectional = false;
	};

private:
	int grid_width = 0;
	int grid_height = 0;
	Vector<float> heights;
	Vector<uint8_t> walkable_cells;
	Vector<Link> last_links;
	Vector<RID> server_links;

	bool _in(const Vector2i &p_cell) const;
	bool _is_walkable(const Vector2i &p_cell) const;
	float _height_at(const Vector2i &p_cell) const;
	void _step_link(Vector<Link> &r_links, const Vector2i &p_a, const Vector2i &p_b, float p_dh, float p_max_drop, float p_max_jump_up, float p_walk_step) const;
	void _gap_link(Vector<Link> &r_links, const Vector2i &p_a, const Vector2i &p_dir, float p_h0, float p_max_jump_up, int p_max_gap) const;
	Vector<Link> _generate(float p_max_drop, float p_max_jump_up, int p_max_gap, float p_walk_step) const;
	static Array _links_to_array(const Vector<Link> &p_links);
	static Vector<Link> _array_to_links(const Array &p_links);

protected:
	static void _bind_methods();

public:
	// Samples `height_at(x, y) -> float` and `walkable(x, y) -> bool` callables, then generates links.
	Array generate(int p_width, int p_height, const Callable &p_height_at, const Callable &p_walkable, float p_max_drop = 3.0, float p_max_jump_up = 1.2, int p_max_gap = 2, float p_walk_step = 0.5);
	// Same, from row-major arrays (no callable overhead).
	Array generate_from_arrays(int p_width, int p_height, const PackedFloat32Array &p_heights, const PackedByteArray &p_walkable, float p_max_drop = 3.0, float p_max_jump_up = 1.2, int p_max_gap = 2, float p_walk_step = 0.5);

	// World-space start/end of a link dictionary using the last generated heightfield.
	Dictionary link_world_positions(const Dictionary &p_link, const Vector2 &p_origin_xz, real_t p_cell_size) const;

	// Creates NavigationServer3D links on the map for the given (or last generated) links. Returns links created.
	int create_links_on_map(const RID &p_map, const Vector2 &p_origin_xz, real_t p_cell_size, const Array &p_links = Array(), uint32_t p_navigation_layers = 1, real_t p_enter_cost = 0.0, real_t p_travel_cost = 1.0);
	void clear_map_links();
	int get_map_link_count() const { return server_links.size(); }
	Array get_last_links() const { return _links_to_array(last_links); }

	~CgameOffMeshLinkGenerator();
};
