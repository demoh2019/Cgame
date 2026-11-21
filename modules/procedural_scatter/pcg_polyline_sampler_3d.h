/**************************************************************************/
/*  pcg_polyline_sampler_3d.h                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Pure-data arc-length sampling along a bounded 3D polyline.
// Unlike path falloff, this generates evenly spaced points ON a route.
class PCGPolylineSampler3D : public RefCounted {
	GDCLASS(PCGPolylineSampler3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_PATH_POINTS = 256;
	static constexpr int MAX_SAMPLES = 4096;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MIN_SPACING = 0.05;
	static constexpr double MAX_SPACING = 10000.0;


	PackedVector3Array sample_positions(const PackedVector3Array &p_path_points,
			double p_spacing, int p_max_samples = MAX_SAMPLES,
			bool p_fit_to_path = true) const;

	// Position and orthonormal tangent-following frame, with local +Z
	// along the route. Central differences soften sharp corners. Handles
	// vertical legs and degenerate loops with deterministic up vectors.
	// Returns no frames when sample_positions rejects the input batch.
	Array sample_transforms(const PackedVector3Array &p_path_points,
			double p_spacing, int p_max_samples = MAX_SAMPLES,
			bool p_fit_to_path = true) const;
};
