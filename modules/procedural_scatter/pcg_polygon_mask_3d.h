/**************************************************************************/
/*  pcg_polygon_mask_3d.h                                                  */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Smooth point density against a simple closed polygon in horizontal XZ.
// Data-only, deterministic, no scene access or global RNG.
class PCGPolygonMask3D : public RefCounted {
	GDCLASS(PCGPolygonMask3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_CANDIDATES = 16384;
	static constexpr int MAX_VERTICES = 256;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MAX_FEATHER = 10000.0;

	// Zero within/on polygon, smoothstep to one outside by feather_distance.
	// invert=true flips the factors to create a keep-inside biome.
	PackedFloat32Array sample_factors(const PackedVector3Array &p_positions,
			const PackedVector3Array &p_polygon,
			double p_feather_distance = 0.0, bool p_invert = false) const;
};
