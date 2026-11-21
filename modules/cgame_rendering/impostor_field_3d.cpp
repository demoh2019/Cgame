/**************************************************************************/
/*  impostor_field_3d.cpp                                                 */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "impostor_field_3d.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"

#include "cgame_impostor_baker.h"

#include "scene/main/scene_tree.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/multimesh.h"

float ImpostorField3D::range_factor = 2.2f;

float ImpostorField3D::range_factor_for_level(int p_level) {
	// Performance draws no impostors; higher tiers reach further.
	static const float factors[4] = { 0.0f, 1.8f, 2.2f, 2.8f };
	return factors[CLAMP(p_level, 0, 3)];
}

float ImpostorField3D::end_distance_for(float p_mesh_range, float p_range_factor) {
	return p_mesh_range * p_range_factor;
}

void ImpostorField3D::configure(int p_level) {
	range_factor = range_factor_for_level(p_level);
}

float ImpostorField3D::end_distance(float p_mesh_range) {
	return end_distance_for(p_mesh_range, range_factor);
}

void ImpostorField3D::set_source_mesh(const Ref<Mesh> &p_mesh) {
	source_mesh = p_mesh;
	baked = false;
	bake_requested = false;
}

void ImpostorField3D::set_placements(const TypedArray<Transform3D> &p_placements) {
	placements.clear();
	placements.resize(p_placements.size());
	for (int i = 0; i < p_placements.size(); i++) {
		placements.write[i] = p_placements[i];
	}
}

TypedArray<Transform3D> ImpostorField3D::get_placements() const {
	TypedArray<Transform3D> result;
	result.resize(placements.size());
	for (int i = 0; i < placements.size(); i++) {
		result[i] = placements[i];
	}
	return result;
}

void ImpostorField3D::set_mesh_range(float p_range) {
	mesh_range = MAX(0.0f, p_range);
}

void ImpostorField3D::set_fade_margin(float p_margin) {
	fade_margin = MAX(0.0f, p_margin);
}

bool ImpostorField3D::rebuild() {
	baked = false;
	bake_requested = false;
	set_visible(false);
	if (source_mesh.is_null() || placements.is_empty() || range_factor <= 1.0f) {
		set_multimesh(Ref<MultiMesh>());
		return false;
	}
	const Vector2 size = CgameImpostorBaker::frame_size(source_mesh);
	Ref<QuadMesh> quad;
	quad.instantiate();
	quad->set_size(Vector2(size.x, size.x));

	Ref<MultiMesh> multimesh;
	multimesh.instantiate();
	multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	multimesh->set_mesh(quad);
	multimesh->set_instance_count(placements.size());
	AABB box(placements[0].origin, Vector3());
	for (int i = 0; i < placements.size(); i++) {
		multimesh->set_instance_transform(i, placements[i]);
		box.expand_to(placements[i].origin);
	}
	set_multimesh(multimesh);
	set_custom_aabb(box.grow(size.x));
	set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	set_visibility_range_begin(mesh_range);
	set_visibility_range_begin_margin(fade_margin);
	set_visibility_range_end(end_distance(mesh_range));
	set_visibility_range_end_margin(fade_margin * 2.0f);
	set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
	// Hidden until its atlas is baked; chunks are often built before they join the tree.
	if (is_inside_tree()) {
		_request_bake();
	}
	return true;
}

void ImpostorField3D::_request_bake() {
	if (bake_requested || baked || source_mesh.is_null() || get_multimesh().is_null()) {
		return;
	}
	bake_requested = true;
	CgameImpostorBaker::request(source_mesh, get_tree(), callable_mp(this, &ImpostorField3D::_on_baked));
}

void ImpostorField3D::_on_baked(const Ref<Texture2D> &p_atlas) {
	if (source_mesh.is_null()) {
		return;
	}
	set_material_override(CgameImpostorBaker::material_for(source_mesh, p_atlas));
	baked = true;
	set_visible(true);
}

ImpostorField3D *ImpostorField3D::add(Node3D *p_parent, const Ref<Mesh> &p_mesh, const TypedArray<Transform3D> &p_transforms, float p_mesh_range, float p_fade_margin) {
	if (p_parent == nullptr || p_mesh.is_null() || p_transforms.is_empty() || range_factor <= 1.0f) {
		return nullptr;
	}
	ImpostorField3D *field = memnew(ImpostorField3D);
	field->set_name("ImpostorField");
	field->set_source_mesh(p_mesh);
	field->set_placements(p_transforms);
	field->set_mesh_range(p_mesh_range);
	field->set_fade_margin(p_fade_margin);
	field->rebuild();
	p_parent->add_child(field);
	return field;
}

void ImpostorField3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			_request_bake();
		} break;
	}
}

void ImpostorField3D::_bind_methods() {
	ClassDB::bind_static_method("ImpostorField3D", D_METHOD("configure", "level"), &ImpostorField3D::configure);
	ClassDB::bind_static_method("ImpostorField3D", D_METHOD("get_range_factor"), &ImpostorField3D::get_range_factor);
	ClassDB::bind_static_method("ImpostorField3D", D_METHOD("end_distance", "mesh_range"), &ImpostorField3D::end_distance);
	ClassDB::bind_static_method("ImpostorField3D", D_METHOD("add", "parent", "mesh", "transforms", "mesh_range", "fade_margin"), &ImpostorField3D::add, DEFVAL(8.0f));

	ClassDB::bind_method(D_METHOD("set_source_mesh", "mesh"), &ImpostorField3D::set_source_mesh);
	ClassDB::bind_method(D_METHOD("get_source_mesh"), &ImpostorField3D::get_source_mesh);
	ClassDB::bind_method(D_METHOD("set_placements", "placements"), &ImpostorField3D::set_placements);
	ClassDB::bind_method(D_METHOD("get_placements"), &ImpostorField3D::get_placements);
	ClassDB::bind_method(D_METHOD("set_mesh_range", "range"), &ImpostorField3D::set_mesh_range);
	ClassDB::bind_method(D_METHOD("get_mesh_range"), &ImpostorField3D::get_mesh_range);
	ClassDB::bind_method(D_METHOD("set_fade_margin", "margin"), &ImpostorField3D::set_fade_margin);
	ClassDB::bind_method(D_METHOD("get_fade_margin"), &ImpostorField3D::get_fade_margin);
	ClassDB::bind_method(D_METHOD("rebuild"), &ImpostorField3D::rebuild);
	ClassDB::bind_method(D_METHOD("is_baked"), &ImpostorField3D::is_baked);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "source_mesh", PROPERTY_HINT_RESOURCE_TYPE, "Mesh"), "set_source_mesh", "get_source_mesh");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "placements", PROPERTY_HINT_ARRAY_TYPE, "Transform3D"), "set_placements", "get_placements");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mesh_range", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:m"), "set_mesh_range", "get_mesh_range");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fade_margin", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:m"), "set_fade_margin", "get_fade_margin");
}
