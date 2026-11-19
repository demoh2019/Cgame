/**************************************************************************/
/*  physics_fem_lumped_mass.h                                             */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_convex_star.h"

#include <limits>
#include <utility>

// Lumped mass from constant-density linear tetrahedral basis functions:
//
//   m_i = (total_mass / sum(tet_volume)) * sum(tets containing i) tet_volume/4
//
// This is a mass discretization, not a new elastic force/constraint. The
// fractions include pinned nodes; pinning affects mobility, not mass.
// Therefore total sum(m_i) remains total_mass even if some nodes are pinned.
//
// The convex tetra cooker already rejects overlapping/inverted elements;
// this routine also checks all indices, distinct corners, finite rest volumes
// and nonzero participation of every physical node. The result is computed
// into local staging arrays and committed ATOMICALLY, so failure preserves
// the old output buffers. Allocation occurs only when preparing the mesh.
//
// r_fractions are independent of total_mass. The caller caches them for
// future unpin operations and scales nonpinned inverse masses on mass edits.
_FORCE_INLINE_ bool physics_fem_build_lumped_masses(
		uint32_t p_vertex_count,
		const LocalVector<PhysicsFEMConvexTetra> &p_tets,
		real_t p_total_mass,
		LocalVector<double> &r_fractions,
		LocalVector<real_t> &r_inverse_masses) {
	if (p_vertex_count < 4 || p_vertex_count > 2048 || p_tets.is_empty() ||
			!(p_total_mass > 0.0) || !Math::is_finite(p_total_mass)) {
		return false;
	}

	LocalVector<double> masses;
	masses.resize(p_vertex_count);
	for (double &mass : masses) {
		mass = 0.0;
	}
	double total_volume = 0.0;
	for (const PhysicsFEMConvexTetra &tet : p_tets) {
		const uint32_t vertex[4] = { tet.a, tet.b, tet.c, tet.d };
		for (int i = 0; i < 4; ++i) {
			if (vertex[i] >= p_vertex_count) {
				return false;
			}
			for (int j = i + 1; j < 4; ++j) {
				if (vertex[i] == vertex[j]) {
					return false;
				}
			}
		}
		const double volume = tet.rest.volume;
		if (!(volume > 0.0) || !Math::is_finite(volume)) {
			return false;
		}
		total_volume += volume;
		if (!Math::is_finite(total_volume)) {
			return false;
		}
		const double lump = volume * 0.25;
		for (int i = 0; i < 4; ++i) {
			masses[vertex[i]] += lump;
			if (!Math::is_finite(masses[vertex[i]])) {
				return false;
			}
		}
	}
	if (!(total_volume > 0.0) || !Math::is_finite(total_volume)) {
		return false;
	}

	LocalVector<double> fractions;
	LocalVector<real_t> inverse_masses;
	fractions.resize(p_vertex_count);
	inverse_masses.resize(p_vertex_count);
	double fraction_sum = 0.0;
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		const double fraction = masses[i] / total_volume;
		if (!(fraction > 0.0) || !Math::is_finite(fraction)) {
			return false; // Do not silently assign infinite mass to unused nodes.
		}
		const double inverse = 1.0 / (double(p_total_mass) * fraction);
		if (!(inverse > 0.0) || !Math::is_finite(inverse) ||
				inverse > double(std::numeric_limits<real_t>::max())) {
			return false;
		}
		const real_t packed_inverse = real_t(inverse);
		if (!(packed_inverse > 0.0) || !Math::is_finite(packed_inverse)) {
			return false;
		}
		fractions[i] = fraction;
		inverse_masses[i] = packed_inverse;
		fraction_sum += fraction;
	}
	if (!Math::is_finite(fraction_sum) ||
			Math::abs(fraction_sum - 1.0) > 1.0e-8) {
		return false;
	}
	r_fractions = std::move(fractions);
	r_inverse_masses = std::move(inverse_masses);
	return true;
}

// Reconstruct an unpinned node's inverse mass after set_total_mass() and
// unpin operations. Caller leaves pins at inverse mass 0. Never multiplies
// float32 inverse masses by an arbitrarily large vertex count.
_FORCE_INLINE_ bool physics_fem_unpinned_inverse_mass(
		const LocalVector<double> &p_mass_fractions,
		uint32_t p_vertex_index, real_t p_total_mass,
		real_t &r_inverse_mass) {
	if (p_vertex_index >= p_mass_fractions.size() ||
			!(p_total_mass > 0.0) || !Math::is_finite(p_total_mass)) {
		return false;
	}
	const double fraction = p_mass_fractions[p_vertex_index];
	if (!(fraction > 0.0) || !Math::is_finite(fraction)) {
		return false;
	}
	const double inverse = 1.0 / (double(p_total_mass) * fraction);
	if (!(inverse > 0.0) || !Math::is_finite(inverse) ||
			inverse > double(std::numeric_limits<real_t>::max())) {
		return false;
	}
	const real_t packed_inverse = real_t(inverse);
	if (!(packed_inverse > 0.0) || !Math::is_finite(packed_inverse)) {
		return false;
	}
	r_inverse_mass = packed_inverse;
	return true;
}
