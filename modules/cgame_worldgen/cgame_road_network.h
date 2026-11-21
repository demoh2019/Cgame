/**************************************************************************/
/*  cgame_road_network.h                                                  */
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
#include "core/variant/callable.h"
#include "core/variant/typed_array.h"

class CgameRoadNetwork : public RefCounted {
	GDCLASS(CgameRoadNetwork, RefCounted);

public:
	struct Edge {
		int a = 0;
		int b = 0;
		double length = 0.0;
	};

private:
	static Vector<Edge> _delaunay_edges(const PackedVector2Array &p_sites);
	static Vector<Edge> _all_edges(const PackedVector2Array &p_sites);
	static Vector<Edge> _kruskal(int p_n, const Vector<Edge> &p_edges);
	static Edge _make_edge(const PackedVector2Array &p_sites, int p_a, int p_b);
	static int _find(Vector<int> &r_parent, int p_i);

protected:
	static void _bind_methods();

public:
	static constexpr double SAMPLE_STEP = 4.0;

	static TypedArray<Dictionary> connect_sites(const PackedVector2Array &p_sites, double p_extra_edge_ratio = 0.15, int64_t p_seed = 0);
	static double route_cost(const Vector2 &p_a, const Vector2 &p_b, const Callable &p_height_at, double p_slope_penalty);
};
