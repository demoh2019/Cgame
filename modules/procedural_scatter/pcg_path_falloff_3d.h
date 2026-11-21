/**************************************************************************/
/*  pcg_path_falloff_3d.h                                                   */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Deterministic data-only density mask from a 3D polyline projected to XZ.
// Useful for PCG roads, footpaths and biome transitions. No scene access.
class PCGPathFalloff3D : public RefCounted {
	GDCLASS(PCGPathFalloff3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_CANDIDATES = 16384;
	static constexpr int MAX_PATH_POINTS = 256;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MAX_RADIUS = 10000.0;

	PackedFloat32Array sample_factors(const PackedVector3Array &p_positions,
			const PackedVector3Array &p_path_points, double p_inner_radius,
			double p_outer_radius) const;
};
