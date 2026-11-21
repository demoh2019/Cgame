/**************************************************************************/
/*  pcg_point_transform_3d.cpp                                             */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "pcg_point_transform_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

namespace {
// Independent, stable per-point streams, with unsigned 32-bit arithmetic.
// Multiplication deliberately wraps at 32 bits, matching GDScript fallback.
uint32_t avalanche32(uint32_t p_stable_id, uint32_t p_seed, uint32_t p_salt) {
	uint32_t hash = p_stable_id ^ p_seed ^ p_salt;
	hash = (hash ^ (hash >> 16)) * 0x045d9f3bu;
	hash = (hash ^ (hash >> 16)) * 0x045d9f3bu;
	hash ^= hash >> 16;
	return hash;
}

double unit_from_hash(uint32_t p_hash) {
	return (double(p_hash) + 0.5) / 4294967296.0;
}
} // namespace

void PCGPointTransform3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_transforms", "positions", "stable_ids", "seed",
					"max_yaw", "horizontal_min", "horizontal_max", "vertical_min", "vertical_max"),
			&PCGPointTransform3D::generate_transforms, DEFVAL(0),
			DEFVAL(6.283185307179586), DEFVAL(0.85), DEFVAL(1.15), DEFVAL(0.85), DEFVAL(1.15));
}

Array PCGPointTransform3D::generate_transforms(const PackedVector3Array &p_positions,
		const PackedInt64Array &p_stable_ids, int p_seed, double p_max_yaw,
		double p_horizontal_min, double p_horizontal_max,
		double p_vertical_min, double p_vertical_max) const {
	Array result;
	const int count = p_positions.size();
	if (count != p_stable_ids.size() || count > MAX_POINTS ||
			p_seed < 0 || int64_t(p_seed) > MAX_STABLE_ID ||
			!Math::is_finite(p_max_yaw) || p_max_yaw < 0.0 || p_max_yaw > 6.283185307179586 ||
			!Math::is_finite(p_horizontal_min) || !Math::is_finite(p_horizontal_max) ||
			!Math::is_finite(p_vertical_min) || !Math::is_finite(p_vertical_max) ||
			p_horizontal_min < 0.01 || p_horizontal_max > 10.0 ||
			p_vertical_min < 0.01 || p_vertical_max > 10.0 ||
			p_horizontal_min > p_horizontal_max || p_vertical_min > p_vertical_max) {
		return result;
	}
	// Reject invalid tail rows atomically; no partial renderable transforms.
	for (int i = 0; i < count; ++i) {
		const Vector3 point = p_positions[i];
		if (!point.is_finite() ||
				Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE ||
				p_stable_ids[i] < 0 || p_stable_ids[i] > MAX_STABLE_ID) {
			return result;
		}
	}
	result.resize(count);
	for (int i = 0; i < count; ++i) {
		const uint32_t id = uint32_t(p_stable_ids[i]);
		const uint32_t seed = uint32_t(p_seed);
		const double yaw = (unit_from_hash(avalanche32(id, seed, 0x9e3779b9u)) - 0.5) * p_max_yaw;
		const double horizontal = p_horizontal_min +
				unit_from_hash(avalanche32(id, seed, 0x7f4a7c15u)) *
				(p_horizontal_max - p_horizontal_min);
		const double vertical = p_vertical_min +
				unit_from_hash(avalanche32(id, seed, 0x94d049bbu)) *
				(p_vertical_max - p_vertical_min);
		const Basis orientation = Basis(Vector3(0, 1, 0), yaw).scaled(
				Vector3(horizontal, vertical, horizontal));
		result[i] = Transform3D(orientation, p_positions[i]);
	}
	return result;
}
