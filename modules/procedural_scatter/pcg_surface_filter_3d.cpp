/**************************************************************************/
/*  pcg_surface_filter_3d.cpp                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_surface_filter_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void PCGSurfaceFilter3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("filter_indices", "positions", "normals", "min_slope_degrees",
					"max_slope_degrees", "min_height", "max_height", "max_selected"),
			&PCGSurfaceFilter3D::filter_indices, DEFVAL(0.0), DEFVAL(90.0),
			DEFVAL(-MAX_COORDINATE), DEFVAL(MAX_COORDINATE), DEFVAL(MAX_SELECTED));
}

PackedInt32Array PCGSurfaceFilter3D::filter_indices(const PackedVector3Array &p_positions,
		const PackedVector3Array &p_normals, double p_min_slope_degrees,
		double p_max_slope_degrees, double p_min_height, double p_max_height,
		int p_max_selected) const {
	PackedInt32Array result;
	const int count = p_positions.size();
	if (count != p_normals.size() || count > MAX_CANDIDATES ||
			p_max_selected < 0 || p_max_selected > MAX_SELECTED ||
			!Math::is_finite(p_min_slope_degrees) ||
			!Math::is_finite(p_max_slope_degrees) ||
			p_min_slope_degrees < 0.0 || p_max_slope_degrees > 90.0 ||
			p_min_slope_degrees > p_max_slope_degrees ||
			!Math::is_finite(p_min_height) || !Math::is_finite(p_max_height) ||
			p_min_height < -MAX_COORDINATE || p_max_height > MAX_COORDINATE ||
			p_min_height > p_max_height) {
		return result;
	}

	// Validate the whole buffer before selecting anything. A bad late point
	// must not produce a partly populated visual scene.
	for (int i = 0; i < count; ++i) {
		const Vector3 position = p_positions[i];
		const Vector3 normal = p_normals[i];
		if (!position.is_finite() || !normal.is_finite() ||
				Math::abs(double(position.x)) > MAX_COORDINATE ||
				Math::abs(double(position.y)) > MAX_COORDINATE ||
				Math::abs(double(position.z)) > MAX_COORDINATE ||
				Math::abs(double(normal.x)) > MAX_COORDINATE ||
				Math::abs(double(normal.y)) > MAX_COORDINATE ||
				Math::abs(double(normal.z)) > MAX_COORDINATE ||
				normal.length_squared() <= 1.0e-12) {
			return PackedInt32Array();
		}
	}
	if (p_max_selected == 0) {
		return result;
	}

	// acos-based slope handles non-unit input normals and inclusive ranges,
	// including perfectly flat (0 deg) and vertical (90 deg) surfaces.
	for (int i = 0; i < count; ++i) {
		const Vector3 position = p_positions[i];
		if (position.y < p_min_height || position.y > p_max_height) {
			continue;
		}
		const Vector3 normal = p_normals[i];
		const double cos_angle = Math::clamp(double(normal.y) / double(normal.length()), -1.0, 1.0);
		const double angle = Math::rad_to_deg(Math::acos(cos_angle));
		if (angle < p_min_slope_degrees || angle > p_max_slope_degrees) {
			continue;
		}
		result.push_back(i);
		if (result.size() >= p_max_selected) {
			break;
		}
	}
	return result;
}
