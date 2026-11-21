/**************************************************************************/
/*  pcg_hlod_proxy_builder_3d.h                                             */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "scene/resources/mesh.h"

// Bounded, merged, genuinely simplified proxy geometry for distant scenery.
// Six silhouette vertices / eight flat-shaded triangles per source object;
// every authored high-poly mesh can be replaced by one shared ArrayMesh.
// Does not change collision, RNG, scene nodes, material assets or source data.
class PCGHLODProxyBuilder3D : public RefCounted {
	GDCLASS(PCGHLODProxyBuilder3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_INPUT_INSTANCES = 8192;
	static constexpr int MAX_PROXY_INSTANCES = 512;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MAX_HALF_EXTENT = 10000.0;
	static constexpr double MAX_BASIS_AXIS = 1000.0;

	Ref<ArrayMesh> build_octahedral_proxy(const Array &p_transforms,
			const PackedVector3Array &p_local_centers,
			const PackedVector3Array &p_local_half_extents,
			int p_max_proxy_instances = MAX_PROXY_INSTANCES) const;
};
