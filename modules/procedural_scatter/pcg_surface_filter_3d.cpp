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
	ClassDB::bind_method(D_METHOD("align_transforms", "transforms", "normals", "max_tilt_degrees"),
			&PCGSurfaceFilter3D::align_transforms, DEFVAL(35.0));
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

	// Only two trigonometric evaluations per batch, not per point.
	// Cosine decreases monotonically over [0, 90] degrees.
	const double min_up_dot = p_max_slope_degrees == 90.0 ? 0.0 :
			Math::cos(Math::deg_to_rad(p_max_slope_degrees));
	const double max_up_dot = p_min_slope_degrees == 0.0 ? 1.0 :
			Math::cos(Math::deg_to_rad(p_min_slope_degrees));
	for (int i = 0; i < count; ++i) {
		const Vector3 position = p_positions[i];
		if (position.y < p_min_height || position.y > p_max_height) {
			continue;
		}
		const Vector3 normal = p_normals[i];
		const double up_dot = double(normal.y) / double(normal.length());
		if (up_dot < min_up_dot || up_dot > max_up_dot) {
			continue;
		}
		result.push_back(i);
		if (result.size() >= p_max_selected) {
			break;
		}
	}
	return result;
}


Array PCGSurfaceFilter3D::align_transforms(const Array &p_transforms,
		const PackedVector3Array &p_normals, double p_max_tilt_degrees) const {
	Array aligned;
	const int count = p_transforms.size();
	if (count != p_normals.size() || count > MAX_CANDIDATES ||
			!Math::is_finite(p_max_tilt_degrees) ||
			p_max_tilt_degrees < 0.0 || p_max_tilt_degrees > 90.0) {
		return aligned;
	}
	// Atomic prevalidation: invalid late normals and malformed Transform3D
	// values cannot leave the caller with a partly aligned batch.
	for (int i = 0; i < count; ++i) {
		if (p_transforms[i].get_type() != Variant::TRANSFORM3D) {
			return Array();
		}
		const Transform3D transform = p_transforms[i];
		const Vector3 n = p_normals[i];
		if (!transform.is_finite() || !n.is_finite() ||
				Math::abs(double(transform.origin.x)) > MAX_COORDINATE ||
				Math::abs(double(transform.origin.y)) > MAX_COORDINATE ||
				Math::abs(double(transform.origin.z)) > MAX_COORDINATE ||
				Math::abs(double(n.x)) > MAX_COORDINATE ||
				Math::abs(double(n.y)) > MAX_COORDINATE ||
				Math::abs(double(n.z)) > MAX_COORDINATE ||
				n.length_squared() <= 1.0e-12 || n.y < 0.0) {
			return Array();
		}
	}
	// All source transforms have been validated; apply a world-space tilt
	// before the original yaw + scale basis. This keeps random yaw and scale
	// unchanged while aligning each prop's local Y up-axis to the terrain.
	const double max_tilt = Math::deg_to_rad(p_max_tilt_degrees);
	aligned.resize(count);
	for (int i = 0; i < count; ++i) {
		const Transform3D original = p_transforms[i];
		const Vector3 target_up = p_normals[i].normalized();
		const Vector3 axis = Vector3::UP.cross(target_up);
		Basis tilt;
		if (max_tilt > 0.0 && axis.length_squared() > 1.0e-12) {
			const double slope = Math::acos(Math::clamp(double(target_up.y), 0.0, 1.0));
			tilt = Basis(axis.normalized(), MIN(slope, max_tilt));
		}
		aligned[i] = Transform3D(tilt * original.basis, original.origin);
	}
	return aligned;
}
