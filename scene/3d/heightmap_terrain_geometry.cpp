/**************************************************************************/
/*  heightmap_terrain_geometry.cpp                                             */
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

#include "heightmap_terrain_geometry.h"
#include "terrain_geomorph_policy.h"

namespace HeightmapTerrainGeometry {

real_t sample_height(const HeightField &p_field, real_t p_x, real_t p_z) {
	if (!p_field.is_valid()) {
		return 0.0;
	}
	p_x = CLAMP(p_x, real_t(0.0), real_t(p_field.width - 1));
	p_z = CLAMP(p_z, real_t(0.0), real_t(p_field.depth - 1));
	const int x0 = MIN(int(Math::floor(p_x)), p_field.width - 2);
	const int z0 = MIN(int(Math::floor(p_z)), p_field.depth - 2);
	const real_t fx = p_x - real_t(x0);
	const real_t fz = p_z - real_t(z0);
	const real_t h00 = p_field.get(x0, z0);
	const real_t h10 = p_field.get(x0 + 1, z0);
	const real_t h01 = p_field.get(x0, z0 + 1);
	const real_t h11 = p_field.get(x0 + 1, z0 + 1);
	// Split the quad along the same diagonal the chunk mesh uses, so the height seen by the physics
	// and by gameplay code matches the rendered surface exactly.
	if (fx + fz <= real_t(1.0)) {
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz;
	}
	return h11 + (h01 - h11) * (real_t(1.0) - fx) + (h10 - h11) * (real_t(1.0) - fz);
}

Vector3 sample_normal(const HeightField &p_field, int p_x, int p_z, const Params &p_params) {
	if (p_params.normal_override != nullptr && p_field.is_valid()) {
		// Both low and high LODs use the same source-grid tangent frame.
		return p_params.normal_override[p_z * p_field.width + p_x];
	}
	const real_t left = p_field.get(p_x - 1, p_z);
	const real_t right = p_field.get(p_x + 1, p_z);
	const real_t down = p_field.get(p_x, p_z - 1);
	const real_t up = p_field.get(p_x, p_z + 1);
	// Central differences; at the border the clamped lookup turns them into one-sided ones,
	// which needs half the run.
	const real_t run_x = (CLAMP(p_x + 1, 0, p_field.width - 1) - CLAMP(p_x - 1, 0, p_field.width - 1)) * p_params.spacing.x;
	const real_t run_z = (CLAMP(p_z + 1, 0, p_field.depth - 1) - CLAMP(p_z - 1, 0, p_field.depth - 1)) * p_params.spacing.y;
	const real_t slope_x = run_x > 0.0 ? (right - left) * p_params.height_scale / run_x : real_t(0.0);
	const real_t slope_z = run_z > 0.0 ? (up - down) * p_params.height_scale / run_z : real_t(0.0);
	return Vector3(-slope_x, 1.0, -slope_z).normalized();
}

Vector3 sample_normal_bilinear(const HeightField &p_field, real_t p_x, real_t p_z, const Params &p_params) {
	p_x = CLAMP(p_x, real_t(0.0), real_t(p_field.width - 1));
	p_z = CLAMP(p_z, real_t(0.0), real_t(p_field.depth - 1));
	const int x0 = MIN(int(Math::floor(p_x)), p_field.width - 2);
	const int z0 = MIN(int(Math::floor(p_z)), p_field.depth - 2);
	const real_t fx = p_x - real_t(x0);
	const real_t fz = p_z - real_t(z0);
	const Vector3 n00 = sample_normal(p_field, x0, z0, p_params);
	const Vector3 n10 = sample_normal(p_field, x0 + 1, z0, p_params);
	const Vector3 n01 = sample_normal(p_field, x0, z0 + 1, p_params);
	const Vector3 n11 = sample_normal(p_field, x0 + 1, z0 + 1, p_params);
	return (n00.lerp(n10, fx).lerp(n01.lerp(n11, fx), fz)).normalized();
}

void chunk_height_range(const HeightField &p_field, int p_x0, int p_z0, int p_quads, real_t &r_min, real_t &r_max) {
	r_min = Math::INF;
	r_max = -Math::INF;
	for (int z = p_z0; z <= p_z0 + p_quads; z++) {
		for (int x = p_x0; x <= p_x0 + p_quads; x++) {
			const real_t h = p_field.get(x, z);
			r_min = MIN(r_min, h);
			r_max = MAX(r_max, h);
		}
	}
}

real_t geometric_lod_error(const HeightField &p_field, int p_x0, int p_z0,
		int p_quads, int p_stride) {
	if (!p_field.is_valid() || p_quads < 1 || p_stride < 1 ||
			(p_quads % p_stride) != 0 || p_x0 < 0 || p_z0 < 0 ||
			p_x0 >= p_field.width - 1 || p_z0 >= p_field.depth - 1) {
		return 0.0;
	}
	if (p_stride == 1) {
		return 0.0;
	}
	real_t max_error = 0.0;
	const int cells = p_quads / p_stride;
	for (int z = 0; z <= p_quads; z++) {
		for (int x = 0; x <= p_quads; x++) {
			const int ci = MIN(x / p_stride, cells - 1);
			const int cj = MIN(z / p_stride, cells - 1);
			const int sx = p_x0 + ci * p_stride;
			const int sz = p_z0 + cj * p_stride;
			const real_t fx = real_t(x - ci * p_stride) / real_t(p_stride);
			const real_t fz = real_t(z - cj * p_stride) / real_t(p_stride);
			const real_t h00 = p_field.get(sx, sz);
			const real_t h10 = p_field.get(sx + p_stride, sz);
			const real_t h01 = p_field.get(sx, sz + p_stride);
			const real_t h11 = p_field.get(sx + p_stride, sz + p_stride);
			// Reproduce the mesh's actual triangle diagonal, never bilinear.
			const real_t coarse = fx + fz <= 1.0
					? h00 + (h10 - h00) * fx + (h01 - h00) * fz
					: h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz);
			max_error = MAX(max_error,
					Math::abs(p_field.get(p_x0 + x, p_z0 + z) - coarse));
		}
	}
	return max_error;
}

int constrain_lod_by_error(int p_desired, const real_t *p_errors,
		int p_count, real_t p_pixels_per_meter, real_t p_max_pixels) {
	const int desired = CLAMP(p_desired, 0, MAX(0, p_count - 1));
	if (p_errors == nullptr || p_max_pixels <= 0.0 ||
			!Math::is_finite(p_max_pixels) || p_pixels_per_meter <= 0.0 ||
			!Math::is_finite(p_pixels_per_meter)) {
		return desired;
	}
	for (int level = 1; level <= desired; level++) {
		const real_t error = p_errors[level];
		if (!Math::is_finite(error) || error < 0.0 ||
				error * p_pixels_per_meter > p_max_pixels) {
			return level - 1;
		}
	}
	return desired;
}

int lod_stride(int p_lod, int p_quads) {
	int stride = 1 << CLAMP(p_lod, 0, 16);
	while (stride > 1 && (p_quads % stride) != 0) {
		stride >>= 1;
	}
	return MAX(stride, 1);
}

real_t screen_lod_multiplier(real_t p_view_height, real_t p_vertical_fov, real_t p_reference_fov) {
	// Screen-relative detail: high pixel density and narrow FOV keep more
	// triangle detail, but limits protect vertex throughput on large monitors.
	if (!Math::is_finite(p_view_height) || !Math::is_finite(p_vertical_fov) ||
			!Math::is_finite(p_reference_fov) || p_view_height <= 0.0 ||
			p_vertical_fov <= 1.0 || p_vertical_fov >= 179.0 ||
			p_reference_fov <= 1.0 || p_reference_fov >= 179.0) {
		return 1.0;
	}
	const real_t fov = Math::tan(Math::deg_to_rad(p_vertical_fov * real_t(0.5)));
	const real_t reference = Math::tan(Math::deg_to_rad(p_reference_fov * real_t(0.5)));
	return CLAMP((p_view_height / real_t(720.0)) * reference / fov,
			real_t(0.6), real_t(1.65));
}

int select_lod(real_t p_distance, real_t p_base_distance, int p_lod_count, int p_current) {
	const int max_lod = MAX(p_lod_count, 1) - 1;
	if (!(p_base_distance > 0.0) || !Math::is_finite(p_distance)) {
		return 0;
	}
	// Level L covers distances in [base * 2^(L-1), base * 2^L); level 0 is everything below base.
	auto level_for = [&](real_t p_value) {
		int lod = 0;
		real_t limit = p_base_distance;
		while (lod < max_lod && p_value >= limit) {
			lod++;
			limit *= 2.0;
		}
		return lod;
	};
	const int lod = level_for(p_distance);
	if (p_current >= 0 && p_current <= max_lod && p_current != lod) {
		// Keep the current level while the distance is within 10% of its range.
		const real_t low = p_current == 0 ? real_t(0.0) : p_base_distance * real_t(1 << (p_current - 1)) * real_t(0.9);
		const real_t high = p_current == max_lod ? real_t(Math::INF) : p_base_distance * real_t(1 << p_current) * real_t(1.1);
		if (p_distance >= low && p_distance < high) {
			return p_current;
		}
	}
	return lod;
}

bool build_chunk(const HeightField &p_field, int p_x0, int p_z0, int p_quads, int p_stride, const Params &p_params, ChunkMesh &r_mesh) {
	r_mesh = ChunkMesh();
	if (!p_field.is_valid() || p_quads < 1 || p_stride < 1 || (p_quads % p_stride) != 0) {
		return false;
	}
	if (p_x0 < 0 || p_z0 < 0 || p_x0 >= p_field.width - 1 || p_z0 >= p_field.depth - 1) {
		return false;
	}
	const int cells = p_quads / p_stride; // Quads per side at this level of detail.
	const int side = cells + 1;

	const real_t u_scale = real_t(1.0) / real_t(p_field.width - 1);
	const real_t v_scale = real_t(1.0) / real_t(p_field.depth - 1);

	const int body_vertices = side * side;
	const int skirt_vertices = 4 * side;
	r_mesh.vertices.resize(body_vertices + skirt_vertices);
	r_mesh.normals.resize(body_vertices + skirt_vertices);
	r_mesh.uvs.resize(body_vertices + skirt_vertices);
	const bool geomorph = p_params.geomorph_coarse_stride > p_stride &&
			p_params.geomorph_coarse_stride <= p_quads;
	if (geomorph) {
		r_mesh.morph_uv2.resize(body_vertices + skirt_vertices);
	}
	Vector2 *morph_uv = geomorph ? r_mesh.morph_uv2.ptrw() : nullptr;
	Vector3 *vertex = r_mesh.vertices.ptrw();
	Vector3 *normal = r_mesh.normals.ptrw();
	Vector2 *uv = r_mesh.uvs.ptrw();

	real_t min_y = Math::INF;
	real_t max_y = -Math::INF;
	for (int j = 0; j < side; j++) {
		for (int i = 0; i < side; i++) {
			// A chunk that overhangs the border collapses its extra vertices onto the border.
			const int sx = MIN(p_x0 + i * p_stride, p_field.width - 1);
			const int sz = MIN(p_z0 + j * p_stride, p_field.depth - 1);
			const real_t y = p_field.get(sx, sz) * p_params.height_scale + p_params.height_offset;
			const int index = j * side + i;
			vertex[index] = Vector3(p_params.origin.x + real_t(sx) * p_params.spacing.x, y, p_params.origin.y + real_t(sz) * p_params.spacing.y);
			normal[index] = sample_normal(p_field, sx, sz, p_params);
			uv[index] = Vector2(real_t(sx) * u_scale, real_t(sz) * v_scale);
			if (geomorph) {
				const float target = TerrainGeomorphPolicy::coarse_sample(
						i * p_stride, j * p_stride, p_x0, p_z0, p_params.geomorph_coarse_stride,
						[&](int px, int pz) { return float(p_field.get(px, pz)); });
				morph_uv[index] = Vector2(target * p_params.height_scale + p_params.height_offset,
						TerrainGeomorphPolicy::interior_mask(i * p_stride, j * p_stride, p_quads));
			}
			min_y = MIN(min_y, y);
			max_y = MAX(max_y, y);
		}
	}

	// Skirts: one extra row of vertices per edge, dropped by skirt_depth.
	// Edge order: north (j = 0), south (j = cells), west (i = 0), east (i = cells).
	int skirt_start[4];
	for (int e = 0; e < 4; e++) {
		skirt_start[e] = body_vertices + e * side;
		for (int k = 0; k < side; k++) {
			int source;
			switch (e) {
				case 0:
					source = k;
					break;
				case 1:
					source = cells * side + k;
					break;
				case 2:
					source = k * side;
					break;
				default:
					source = k * side + cells;
					break;
			}
			vertex[skirt_start[e] + k] = vertex[source] - Vector3(0, p_params.skirt_depth, 0);
			normal[skirt_start[e] + k] = normal[source];
			uv[skirt_start[e] + k] = uv[source];
			if (geomorph) {
				morph_uv[skirt_start[e] + k] = Vector2(vertex[skirt_start[e] + k].y, 0.0);
			}
		}
	}
	min_y -= MAX(p_params.skirt_depth, real_t(0.0));

	// Indices. Godot treats clockwise triangles (seen from outside) as front faces. The diagonal
	// runs from the (+x, 0) corner to the (0, +z) corner of every quad, matching sample_height().
	PackedInt32Array &indices = r_mesh.indices;
	indices.resize(cells * cells * 6 + 4 * cells * 6);
	int32_t *index_out = indices.ptrw();
	int n = 0;
	for (int j = 0; j < cells; j++) {
		for (int i = 0; i < cells; i++) {
			const int a = j * side + i; // (0, 0)
			const int b = a + 1; // (+x, 0)
			const int c = a + side; // (0, +z)
			const int d = c + 1; // (+x, +z)
			index_out[n++] = a;
			index_out[n++] = b;
			index_out[n++] = c;
			index_out[n++] = b;
			index_out[n++] = d;
			index_out[n++] = c;
		}
	}
	// Skirt quads face outward. For an edge running along increasing k, the outward side differs per edge.
	for (int e = 0; e < 4; e++) {
		for (int k = 0; k < cells; k++) {
			int top0;
			int top1;
			switch (e) {
				case 0:
					top0 = k;
					top1 = k + 1;
					break;
				case 1:
					top0 = cells * side + k;
					top1 = top0 + 1;
					break;
				case 2:
					top0 = k * side;
					top1 = top0 + side;
					break;
				default:
					top0 = k * side + cells;
					top1 = top0 + side;
					break;
			}
			const int bottom0 = skirt_start[e] + k;
			const int bottom1 = skirt_start[e] + k + 1;
			// North and east edges face -z and +x; with these index orders the clockwise side is
			// the outward one for north and east, so south and west use the reverse winding.
			const bool flip = (e == 0 || e == 3);
			if (!flip) {
				index_out[n++] = top0;
				index_out[n++] = top1;
				index_out[n++] = bottom0;
				index_out[n++] = top1;
				index_out[n++] = bottom1;
				index_out[n++] = bottom0;
			} else {
				index_out[n++] = top0;
				index_out[n++] = bottom0;
				index_out[n++] = top1;
				index_out[n++] = top1;
				index_out[n++] = bottom0;
				index_out[n++] = bottom1;
			}
		}
	}

	const Vector3 low = Vector3(p_params.origin.x + real_t(p_x0) * p_params.spacing.x, min_y, p_params.origin.y + real_t(p_z0) * p_params.spacing.y);
	const Vector3 high = Vector3(p_params.origin.x + real_t(MIN(p_x0 + p_quads, p_field.width - 1)) * p_params.spacing.x, max_y, p_params.origin.y + real_t(MIN(p_z0 + p_quads, p_field.depth - 1)) * p_params.spacing.y);
	r_mesh.bounds = AABB(low, high - low);
	return true;
}

} // namespace HeightmapTerrainGeometry
