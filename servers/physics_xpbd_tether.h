/**************************************************************************/
/*  physics_xpbd_tether.h                                                 */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"
#include "core/templates/local_vector.h"

#include <limits>

// Jolt-style long-range cloth attachments. Geodesic rest distance from the
// nearest pinned vertex avoids artificially shortening a folded cloth sheet.
// Topology is prepared only after the pin set changes; solving is O(V) and
// uses no per-frame allocation after the opt-in buffers have been built.
struct PhysicsXPBDTetherEdge {
	uint32_t a = 0;
	uint32_t b = 0;
	real_t length = 0.0;
};

struct PhysicsXPBDTether {
	uint32_t anchor = UINT32_MAX;
	real_t max_length = 0.0;
	real_t lambda = 0.0;
};

namespace PhysicsXPBDTetherInternal {

struct Adjacency {
	uint32_t neighbor;
	real_t length;
};

struct HeapEntry {
	double length;
	uint32_t vertex;
	uint32_t anchor;
};

_FORCE_INLINE_ bool less(const HeapEntry &p_a, const HeapEntry &p_b) {
	if (p_a.length != p_b.length) {
		return p_a.length < p_b.length;
	}
	if (p_a.anchor != p_b.anchor) {
		return p_a.anchor < p_b.anchor;
	}
	return p_a.vertex < p_b.vertex;
}

_FORCE_INLINE_ void push(LocalVector<HeapEntry> &r_heap, const HeapEntry &p_entry) {
	r_heap.push_back(p_entry);
	uint32_t i = r_heap.size() - 1;
	while (i > 0) {
		const uint32_t parent = (i - 1) / 2;
		if (!less(r_heap[i], r_heap[parent])) {
			break;
		}
		SWAP(r_heap[i], r_heap[parent]);
		i = parent;
	}
}

_FORCE_INLINE_ HeapEntry pop(LocalVector<HeapEntry> &r_heap) {
	const HeapEntry top = r_heap[0];
	const uint32_t last = r_heap.size() - 1;
	if (last == 0) {
		r_heap.clear();
		return top;
	}
	r_heap[0] = r_heap[last];
	r_heap.resize(last);
	uint32_t i = 0;
	while (true) {
		const uint32_t left = 2 * i + 1;
		if (left >= r_heap.size()) {
			break;
		}
		const uint32_t right = left + 1;
		uint32_t selected = left;
		if (right < r_heap.size() && less(r_heap[right], r_heap[left])) {
			selected = right;
		}
		if (!less(r_heap[selected], r_heap[i])) {
			break;
		}
		SWAP(r_heap[i], r_heap[selected]);
		i = selected;
	}
	return top;
}

} // namespace PhysicsXPBDTetherInternal

// Multi-source Dijkstra over structural (not bending) mesh edges.
// Input pins refer to physical nodes, after welding duplicate visual vertices.
// output[v].anchor is UINT32_MAX for disconnected components. Tie-breaking
// prefers the lowest-index anchor for deterministic repeated builds.
_FORCE_INLINE_ bool physics_xpbd_build_tethers(uint32_t p_vertex_count,
		const LocalVector<PhysicsXPBDTetherEdge> &p_edges,
		const LocalVector<uint32_t> &p_pins, real_t p_slack,
		LocalVector<PhysicsXPBDTether> &r_output) {
	using namespace PhysicsXPBDTetherInternal;
	if (!Math::is_finite(p_slack) || p_slack < 0.0 ||
			p_vertex_count == 0 || p_pins.is_empty() || p_edges.size() > UINT32_MAX / 2) {
		r_output.reset();
		return false;
	}
	LocalVector<uint32_t> offsets;
	offsets.resize(p_vertex_count + 1);
	for (uint32_t &offset : offsets) {
		offset = 0;
	}
	for (const PhysicsXPBDTetherEdge &edge : p_edges) {
		if (edge.a >= p_vertex_count || edge.b >= p_vertex_count || edge.a == edge.b ||
				!Math::is_finite(edge.length) || edge.length <= 0.0) {
			continue;
		}
		++offsets[edge.a + 1];
		++offsets[edge.b + 1];
	}
	for (uint32_t i = 1; i <= p_vertex_count; ++i) {
		if (offsets[i] > UINT32_MAX - offsets[i - 1]) {
			r_output.reset();
			return false;
		}
		offsets[i] += offsets[i - 1];
	}
	LocalVector<Adjacency> adjacent;
	adjacent.resize(offsets[p_vertex_count]);
	LocalVector<uint32_t> cursor;
	cursor.resize(p_vertex_count);
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		cursor[i] = offsets[i];
	}
	for (const PhysicsXPBDTetherEdge &edge : p_edges) {
		if (edge.a >= p_vertex_count || edge.b >= p_vertex_count || edge.a == edge.b ||
				!Math::is_finite(edge.length) || edge.length <= 0.0) {
			continue;
		}
		adjacent[cursor[edge.a]++] = { edge.b, edge.length };
		adjacent[cursor[edge.b]++] = { edge.a, edge.length };
	}
	const double unreachable = std::numeric_limits<double>::infinity();
	LocalVector<double> distances;
	distances.resize(p_vertex_count);
	r_output.resize(p_vertex_count);
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		distances[i] = unreachable;
		r_output[i] = PhysicsXPBDTether();
	}
	LocalVector<HeapEntry> heap;
	for (uint32_t pin : p_pins) {
		if (pin >= p_vertex_count || r_output[pin].anchor != UINT32_MAX) {
			continue;
		}
		r_output[pin].anchor = pin;
		distances[pin] = 0.0;
		push(heap, { 0.0, pin, pin });
	}
	if (heap.is_empty()) {
		r_output.reset();
		return false;
	}
	while (!heap.is_empty()) {
		const HeapEntry current = pop(heap);
		if (current.length != distances[current.vertex] ||
				current.anchor != r_output[current.vertex].anchor) {
			continue; // Stale decrease-key entry.
		}
		for (uint32_t j = offsets[current.vertex]; j < offsets[current.vertex + 1]; ++j) {
			const Adjacency &edge = adjacent[j];
			const double next = current.length + double(edge.length);
			if (!Math::is_finite(next)) {
				continue;
			}
			if (next < distances[edge.neighbor] ||
					(next == distances[edge.neighbor] && current.anchor < r_output[edge.neighbor].anchor)) {
				distances[edge.neighbor] = next;
				r_output[edge.neighbor].anchor = current.anchor;
				push(heap, { next, edge.neighbor, current.anchor });
			}
		}
	}
	const double multiplier = 1.0 + double(p_slack);
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		const double allowed = distances[i] * multiplier;
		if (r_output[i].anchor != UINT32_MAX && Math::is_finite(allowed) &&
				allowed <= double(std::numeric_limits<real_t>::max())) {
			r_output[i].max_length = real_t(allowed);
		} else {
			r_output[i].anchor = UINT32_MAX;
		}
	}
	return true;
}

// A unilateral XPBD constraint: |free - pinned| <= max_length.
// Lambda is nonpositive and resets each physics step. If stretched, the
// correction moves only the free node; never apply a force to the anchor.
// The complementarity projection avoids compression forces inside the leash.
_FORCE_INLINE_ bool physics_xpbd_solve_tether(Vector3 &r_free, const Vector3 &p_anchor,
		real_t p_inv_mass, real_t p_max_length, real_t p_alpha, real_t &r_lambda) {
	if (!r_free.is_finite() || !p_anchor.is_finite() ||
			!Math::is_finite(p_inv_mass) || !Math::is_finite(p_max_length) ||
			!Math::is_finite(p_alpha) || !Math::is_finite(r_lambda) ||
			p_inv_mass <= 0.0 || p_max_length < 0.0 || p_alpha < 0.0 || r_lambda > 0.0) {
		return false;
	}
	const double dx = double(r_free.x) - double(p_anchor.x);
	const double dy = double(r_free.y) - double(p_anchor.y);
	const double dz = double(r_free.z) - double(p_anchor.z);
	const double length = Math::sqrt(dx * dx + dy * dy + dz * dz);
	if (!(length > 0.0) || !Math::is_finite(length)) {
		return false;
	}
	const double c = length - double(p_max_length);
	if (c <= 0.0 && r_lambda == 0.0) {
		return false;
	}
	const double next_lambda = MIN(0.0, double(r_lambda) -
			(c + double(p_alpha) * double(r_lambda)) / (double(p_inv_mass) + double(p_alpha)));
	if (!Math::is_finite(next_lambda)) {
		return false;
	}
	const double correction = double(p_inv_mass) * (next_lambda - double(r_lambda)) / length;
	const Vector3 next(real_t(double(r_free.x) + dx * correction),
			real_t(double(r_free.y) + dy * correction),
			real_t(double(r_free.z) + dz * correction));
	const real_t next_lambda_t = real_t(next_lambda);
	if (!next.is_finite() || !Math::is_finite(next_lambda_t)) {
		return false;
	}
	r_free = next;
	r_lambda = next_lambda_t;
	return true;
}
