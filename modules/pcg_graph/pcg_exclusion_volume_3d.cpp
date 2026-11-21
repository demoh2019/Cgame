/**************************************************************************/
/*  pcg_exclusion_volume_3d.cpp                                           */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_exclusion_volume_3d.h"

#include "core/object/class_db.h"
#include "scene/main/scene_tree.h"

void PCGExclusionVolume3D::set_shape(Shape p_shape) {
	shape = p_shape;
	update_gizmos();
}

void PCGExclusionVolume3D::set_size(const Vector3 &p_size) {
	size = p_size.abs();
	update_gizmos();
}

void PCGExclusionVolume3D::set_radius(float p_radius) {
	radius = MAX(0.0f, p_radius);
	update_gizmos();
}

AABB PCGExclusionVolume3D::get_world_aabb() const {
	const Transform3D xform = is_inside_tree() ? get_global_transform() : get_transform();
	if (shape == SHAPE_CYLINDER) {
		const Vector3 c = xform.origin;
		return AABB(c - Vector3(radius, size.y * 0.5f, radius), Vector3(radius * 2.0f, size.y, radius * 2.0f));
	}
	return xform.xform(AABB(-size * 0.5f, size));
}

Variant PCGExclusionVolume3D::get_exclusion() const {
	if (shape == SHAPE_CYLINDER) {
		Dictionary cylinder;
		cylinder["center"] = is_inside_tree() ? get_global_position() : get_position();
		cylinder["radius"] = radius;
		return cylinder;
	}
	return get_world_aabb();
}

Array PCGExclusionVolume3D::gather(SceneTree *p_tree, const AABB &p_area, float p_margin) {
	Array out;
	if (p_tree == nullptr) {
		return out;
	}
	const Vector<Node *> nodes = p_tree->get_nodes_in_group(GROUP);
	const AABB area = p_area.grow(p_margin);
	for (Node *node : nodes) {
		PCGExclusionVolume3D *volume = Object::cast_to<PCGExclusionVolume3D>(node);
		if (volume == nullptr || !volume->is_active() || !volume->is_inside_tree()) {
			continue;
		}
		const AABB box = volume->get_world_aabb();
		// Compare on XZ only: exclusions are footprints.
		if (box.position.x > area.position.x + area.size.x || box.position.x + box.size.x < area.position.x ||
				box.position.z > area.position.z + area.size.z || box.position.z + box.size.z < area.position.z) {
			continue;
		}
		out.push_back(volume->get_exclusion());
	}
	return out;
}

void PCGExclusionVolume3D::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		add_to_group(GROUP);
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		remove_from_group(GROUP);
	}
}

void PCGExclusionVolume3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_shape", "shape"), &PCGExclusionVolume3D::set_shape);
	ClassDB::bind_method(D_METHOD("get_shape"), &PCGExclusionVolume3D::get_shape);
	ClassDB::bind_method(D_METHOD("set_size", "size"), &PCGExclusionVolume3D::set_size);
	ClassDB::bind_method(D_METHOD("get_size"), &PCGExclusionVolume3D::get_size);
	ClassDB::bind_method(D_METHOD("set_radius", "radius"), &PCGExclusionVolume3D::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &PCGExclusionVolume3D::get_radius);
	ClassDB::bind_method(D_METHOD("set_active", "active"), &PCGExclusionVolume3D::set_active);
	ClassDB::bind_method(D_METHOD("is_active"), &PCGExclusionVolume3D::is_active);
	ClassDB::bind_method(D_METHOD("get_exclusion"), &PCGExclusionVolume3D::get_exclusion);
	ClassDB::bind_method(D_METHOD("get_world_aabb"), &PCGExclusionVolume3D::get_world_aabb);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "shape", PROPERTY_HINT_ENUM, "Box,Cylinder"), "set_shape", "get_shape");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "size", PROPERTY_HINT_NONE, "suffix:m"), "set_size", "get_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius", PROPERTY_HINT_RANGE, "0,1024,0.1,or_greater,suffix:m"), "set_radius", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "active"), "set_active", "is_active");

	BIND_ENUM_CONSTANT(SHAPE_BOX);
	BIND_ENUM_CONSTANT(SHAPE_CYLINDER);
}
