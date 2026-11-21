/**************************************************************************/
/*  pcg_point_transform_3d.h                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Data-only counterpart of Unreal PCG Transform Points: point-stable
// Y-axis rotation + independent horizontal/vertical scale, no global RNG.
class PCGPointTransform3D : public RefCounted {
	GDCLASS(PCGPointTransform3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_POINTS = 16384;
	static constexpr int64_t MAX_STABLE_ID = 2147483647;
	static constexpr double MAX_COORDINATE = 10000000.0;

	Array generate_transforms(const PackedVector3Array &p_positions,
			const PackedInt64Array &p_stable_ids, int p_seed = 0,
			double p_max_yaw = 6.283185307179586,
			double p_horizontal_min = 0.85, double p_horizontal_max = 1.15,
			double p_vertical_min = 0.85, double p_vertical_max = 1.15) const;
};
