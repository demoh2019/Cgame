/**************************************************************************/
/*  navmesh_stitching.h                                                   */
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
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Tiled navmesh stitching (portal links between tiles), polygon graph and A* + funnel.
// Tiles are Dictionaries: {"origin": Vector2, "size": float, "polygons": Array[PackedVector2Array]}.
class NavMeshStitching : public RefCounted {
	GDCLASS(NavMeshStitching, RefCounted);

	static float _cross(const Vector2 &p_a, const Vector2 &p_b);
	static void _orient(const Vector2 &p_p1, const Vector2 &p_p2, const Vector2 &p_from, Vector2 &r_left, Vector2 &r_right);
	static Vector2 _centroid(const PackedVector2Array &p_poly);
	static int _locate(const Dictionary &p_graph, const Vector2 &p_point);

protected:
	static void _bind_methods();

public:
	static Array stitch(const Dictionary &p_tile_a, const Dictionary &p_tile_b, double p_tolerance);
	static Dictionary build_graph(const Array &p_tiles, double p_tolerance);
	static PackedVector2Array find_path(const Dictionary &p_graph, const Vector2 &p_start, const Vector2 &p_goal);
	static PackedVector2Array funnel(const Array &p_portals);
};
