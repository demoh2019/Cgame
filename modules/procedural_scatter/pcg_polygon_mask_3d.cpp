/**************************************************************************/
/*  pcg_polygon_mask_3d.cpp                                                */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_polygon_mask_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

namespace {

struct PointXZ {
	double x;
	double z;
};

static double cross_xz(const PointXZ &a, const PointXZ &b, const PointXZ &c) {
	return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x);
}

static bool on_segment(const PointXZ &a, const PointXZ &b, const PointXZ &p) {
	return cross_xz(a, b, p) == 0.0 &&
			p.x >= MIN(a.x, b.x) && p.x <= MAX(a.x, b.x) &&
			p.z >= MIN(a.z, b.z) && p.z <= MAX(a.z, b.z);
}

static bool intersects(const PointXZ &a, const PointXZ &b,
		const PointXZ &c, const PointXZ &d) {
	const double o1 = cross_xz(a, b, c);
	const double o2 = cross_xz(a, b, d);
	const double o3 = cross_xz(c, d, a);
	const double o4 = cross_xz(c, d, b);
	if (((o1 > 0.0 && o2 < 0.0) || (o1 < 0.0 && o2 > 0.0)) &&
			((o3 > 0.0 && o4 < 0.0) || (o3 < 0.0 && o4 > 0.0))) {
		return true;
	}
	return (o1 == 0.0 && on_segment(a, b, c)) ||
			(o2 == 0.0 && on_segment(a, b, d)) ||
			(o3 == 0.0 && on_segment(c, d, a)) ||
			(o4 == 0.0 && on_segment(c, d, b));
}

} // namespace

void PCGPolygonMask3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sample_factors", "positions", "polygon", "feather_distance", "invert"),
			&PCGPolygonMask3D::sample_factors, DEFVAL(0.0), DEFVAL(false));
}

PackedFloat32Array PCGPolygonMask3D::sample_factors(
		const PackedVector3Array &p_positions, const PackedVector3Array &p_polygon,
		double p_feather_distance, bool p_invert) const {
	PackedFloat32Array empty;
	const int vertex_count = p_polygon.size();
	if (p_positions.size() > MAX_CANDIDATES ||
			vertex_count < 3 || vertex_count > MAX_VERTICES ||
			!Math::is_finite(p_feather_distance) ||
			p_feather_distance < 0.0 || p_feather_distance > MAX_FEATHER) {
		return empty;
	}

	// All inputs are checked before any mask is generated. Y is ignored
	// for 2D coverage but must still be finite to avoid corrupt batches.
	for (const Vector3 &p : p_positions) {
		if (!p.is_finite() ||
				Math::abs(double(p.x)) > MAX_COORDINATE ||
				Math::abs(double(p.y)) > MAX_COORDINATE ||
				Math::abs(double(p.z)) > MAX_COORDINATE) {
			return empty;
		}
	}
	for (const Vector3 &p : p_polygon) {
		if (!p.is_finite() ||
				Math::abs(double(p.x)) > MAX_COORDINATE ||
				Math::abs(double(p.y)) > MAX_COORDINATE ||
				Math::abs(double(p.z)) > MAX_COORDINATE) {
			return empty;
		}
	}
	double min_x = MAX_COORDINATE;
	double max_x = -MAX_COORDINATE;
	double min_z = MAX_COORDINATE;
	double max_z = -MAX_COORDINATE;
	const PointXZ base = { double(p_polygon[0].x), double(p_polygon[0].z) };
	double twice_area = 0.0;
	for (int i = 0; i < vertex_count; ++i) {
		const Vector3 a = p_polygon[i];
		const Vector3 b = p_polygon[(i + 1) % vertex_count];
		const double ax = double(a.x), az = double(a.z);
		const double bx = double(b.x), bz = double(b.z);
		const double dx = bx - ax, dz = bz - az;
		// Reject closing duplicates, zero-length edges and collapsed loops.
		if (dx * dx + dz * dz <= 1.0e-12) {
			return empty;
		}
		twice_area += (ax - base.x) * (bz - base.z) -
				(bx - base.x) * (az - base.z);
		min_x = MIN(min_x, ax);
		max_x = MAX(max_x, ax);
		min_z = MIN(min_z, az);
		max_z = MAX(max_z, az);
	}
	if (Math::abs(twice_area) <= 1.0e-8) {
		return empty;
	}

	// A polygon must be simple (no self-crossings or nonadjacent
	// touching edges). This pre-pass is bounded by 256*256 edge pairs.
	// Adjacent segments share one vertex by definition.
	for (int i = 0; i < vertex_count; ++i) {
		const Vector3 va = p_polygon[i];
		const Vector3 vb = p_polygon[(i + 1) % vertex_count];
		const PointXZ a = { double(va.x), double(va.z) };
		const PointXZ b = { double(vb.x), double(vb.z) };
		for (int j = i + 1; j < vertex_count; ++j) {
			if ((i + 1) % vertex_count == j ||
					(j + 1) % vertex_count == i) {
				continue;
			}
			const Vector3 vc = p_polygon[j];
			const Vector3 vd = p_polygon[(j + 1) % vertex_count];
			const PointXZ c = { double(vc.x), double(vc.z) };
			const PointXZ d = { double(vd.x), double(vd.z) };
			if (intersects(a, b, c, d)) {
				return empty;
			}
		}
	}

	PackedFloat32Array result;
	result.resize(p_positions.size());
	const double feather_squared = p_feather_distance * p_feather_distance;
	for (int i = 0; i < p_positions.size(); ++i) {
		const Vector3 p = p_positions[i];
		const double x = double(p.x), z = double(p.z);
		// A cheap expanded-bounds test avoids all polygon edges for most
		// distant biome points. It is valid for both inverted modes.
		if (x < min_x - p_feather_distance ||
				x > max_x + p_feather_distance ||
				z < min_z - p_feather_distance ||
				z > max_z + p_feather_distance) {
			result.set(i, p_invert ? 0.0f : 1.0f);
			continue;
		}
		bool inside = false;
		double nearest_squared = 1.0e30;
		for (int edge = 0; edge < vertex_count; ++edge) {
			const Vector3 a = p_polygon[edge];
			const Vector3 b = p_polygon[(edge + 1) % vertex_count];
			const double ax = double(a.x), az = double(a.z);
			const double bx = double(b.x), bz = double(b.z);
			const double dx = bx - ax, dz = bz - az;
			const double len_squared = dx * dx + dz * dz;
			const double t = Math::clamp(((x - ax) * dx + (z - az) * dz) /
					len_squared, 0.0, 1.0);
			const double ex = x - (ax + dx * t);
			const double ez = z - (az + dz * t);
			nearest_squared = MIN(nearest_squared, ex * ex + ez * ez);
			// Even-odd crossing on a half-open Z interval. Points directly
			// on any edge are handled by nearest_squared below.
			if ((az > z) != (bz > z) &&
					x < ax + (z - az) * dx / dz) {
				inside = !inside;
			}
		}

		double outside_factor = 0.0;
		if (!inside && nearest_squared > 1.0e-12) {
			if (p_feather_distance == 0.0 || nearest_squared >= feather_squared) {
				outside_factor = 1.0;
			} else {
				const double t = Math::sqrt(nearest_squared) / p_feather_distance;
				outside_factor = t * t * (3.0 - 2.0 * t);
			}
		}
		result.set(i, float(p_invert ? 1.0 - outside_factor : outside_factor));
	}
	return result;
}
