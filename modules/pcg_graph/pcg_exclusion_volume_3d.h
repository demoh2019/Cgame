/**************************************************************************/
/*  pcg_exclusion_volume_3d.h                                             */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// A volume placed in the scene that keeps PCG content out (Unreal "PCG
// exclusion volume"). PCGComponent3D gathers every volume in the
// "pcg_exclusion_volumes" group that overlaps a cell into the cell's context, and
// PCGExclusionFilterNode removes points inside them.

#include "scene/3d/node_3d.h"

class PCGExclusionVolume3D : public Node3D {
	GDCLASS(PCGExclusionVolume3D, Node3D);

public:
	enum Shape {
		SHAPE_BOX,
		SHAPE_CYLINDER,
	};

	static constexpr const char *GROUP = "pcg_exclusion_volumes";

private:
	Shape shape = SHAPE_BOX;
	Vector3 size = Vector3(8, 8, 8);
	float radius = 4.0;
	bool active = true;

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_shape(Shape p_shape);
	Shape get_shape() const { return shape; }
	void set_size(const Vector3 &p_size);
	Vector3 get_size() const { return size; }
	void set_radius(float p_radius);
	float get_radius() const { return radius; }
	void set_active(bool p_active) { active = p_active; }
	bool is_active() const { return active; }

	// World-space exclusion as understood by PCGContext: an AABB, or {"center", "radius"} (a vertical cylinder).
	Variant get_exclusion() const;
	AABB get_world_aabb() const;
	// Exclusions of every active volume in the tree overlapping `p_area` (grown by `p_margin`).
	static Array gather(SceneTree *p_tree, const AABB &p_area, float p_margin = 0.0);
};

VARIANT_ENUM_CAST(PCGExclusionVolume3D::Shape);
