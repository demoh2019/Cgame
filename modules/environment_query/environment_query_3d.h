/**************************************************************************/
/*  environment_query_3d.h                                                */
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

#include "core/io/resource.h"
#include "core/variant/array.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "core/variant/variant.h"

/**
 * Deterministic, physics-independent spatial candidate filter and scorer.
 * Resources store query parameters; callers supply or generate candidates.
 */
class EnvironmentQuery3D : public Resource {
	GDCLASS(EnvironmentQuery3D, Resource);

	PackedVector3Array candidates;
	Vector3 origin;
	Vector3 threat_position;
	bool use_threat = false;
	bool horizontal_only = false;
	double min_distance = 0.0;
	double max_distance = 100.0;
	double desired_distance = 0.0;
	double distance_weight = 1.0;
	double safety_weight = 0.0;
	double min_threat_distance = 0.0;
	int max_results = 0;

protected:
	static void _bind_methods();

public:
	void set_candidates(const PackedVector3Array &p_candidates);
	PackedVector3Array get_candidates() const { return candidates; }

	void set_origin(const Vector3 &p_origin);
	Vector3 get_origin() const { return origin; }
	void set_threat_position(const Vector3 &p_position);
	Vector3 get_threat_position() const { return threat_position; }
	void set_use_threat(bool p_enabled) { use_threat = p_enabled; emit_changed(); }
	bool is_using_threat() const { return use_threat; }
	void set_horizontal_only(bool p_enabled) { horizontal_only = p_enabled; emit_changed(); }
	bool is_horizontal_only() const { return horizontal_only; }

	void set_min_distance(double p_distance);
	double get_min_distance() const { return min_distance; }
	void set_max_distance(double p_distance);
	double get_max_distance() const { return max_distance; }
	void set_desired_distance(double p_distance);
	double get_desired_distance() const { return desired_distance; }
	void set_distance_weight(double p_weight);
	double get_distance_weight() const { return distance_weight; }
	void set_safety_weight(double p_weight);
	double get_safety_weight() const { return safety_weight; }
	void set_min_threat_distance(double p_distance);
	double get_min_threat_distance() const { return min_threat_distance; }
	void set_max_results(int p_max_results);
	int get_max_results() const { return max_results; }

	// Each result dictionary has position, index, score, distance and
	// threat_distance. Descending score, ties broken by input index.
	Array query() const;
	PackedVector3Array query_positions() const;

	// Generates candidates on the XZ plane. Count/size are bounded to avoid
	// accidentally allocating millions of points in the editor.
	static PackedVector3Array sample_ring(const Vector3 &p_center, double p_radius, int p_count, double p_phase = 0.0);
	static PackedVector3Array sample_grid(const Vector3 &p_center, const Vector2 &p_half_extents, double p_spacing, int p_max_points = 4096);
};
