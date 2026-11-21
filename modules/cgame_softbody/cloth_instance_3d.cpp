/**************************************************************************/
/*  cloth_instance_3d.cpp                                                 */
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

#include "cloth_instance_3d.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "scene/3d/skeleton_3d.h"
#include "scene/resources/mesh.h"
#include "servers/rendering/rendering_server.h"

void ClothInstance3D::set_cloth(const Ref<CgameXPBDCloth> &p_cloth) {
	cloth = p_cloth;
	mesh_triangle_count = -1;
	fast_path_ok = false;
	if (cloth.is_valid() && is_inside_tree()) {
		_rebuild_mesh();
	} else if (cloth.is_null()) {
		array_mesh.unref();
		set_mesh(Ref<Mesh>());
	}
}

void ClothInstance3D::set_cloth_skeleton_path(const NodePath &p_path) {
	cloth_skeleton_path = p_path;
}

Skeleton3D *ClothInstance3D::_get_skeleton() const {
	if (cloth_skeleton_path.is_empty() || !is_inside_tree()) {
		return nullptr;
	}
	return Object::cast_to<Skeleton3D>(get_node_or_null(cloth_skeleton_path));
}

void ClothInstance3D::attach_particle_to_bone(int p_particle, const StringName &p_bone, const Vector3 &p_offset) {
	ERR_FAIL_COND(cloth.is_null());
	ERR_FAIL_INDEX(p_particle, cloth->particle_count());
	BoneAttachment attachment;
	attachment.bone = p_bone;
	attachment.offset = p_offset;
	bone_attachments[p_particle] = attachment;
}

void ClothInstance3D::detach_particle_from_bone(int p_particle) {
	if (bone_attachments.erase(p_particle) && cloth.is_valid()) {
		cloth->unpin(p_particle);
	}
}

void ClothInstance3D::clear_bone_attachments() {
	if (cloth.is_valid()) {
		for (const KeyValue<int, BoneAttachment> &kv : bone_attachments) {
			if (kv.key >= 0 && kv.key < cloth->particle_count()) {
				cloth->unpin(kv.key);
			}
		}
	}
	bone_attachments.clear();
}

void ClothInstance3D::set_bone_attachments(const Dictionary &p_map) {
	bone_attachments.clear();
	for (const KeyValue<Variant, Variant> &kv : p_map) {
		BoneAttachment attachment;
		if (kv.value.get_type() == Variant::ARRAY) {
			const Array entry = kv.value;
			ERR_CONTINUE_MSG(entry.is_empty(), "Bone attachment arrays need at least a bone name.");
			attachment.bone = entry[0];
			if (entry.size() > 1) {
				attachment.offset = entry[1];
			}
		} else {
			attachment.bone = kv.value;
		}
		bone_attachments[(int)kv.key] = attachment;
	}
}

Dictionary ClothInstance3D::get_bone_attachments() const {
	Dictionary out;
	for (const KeyValue<int, BoneAttachment> &kv : bone_attachments) {
		Array entry;
		entry.push_back(kv.value.bone);
		entry.push_back(kv.value.offset);
		out[kv.key] = entry;
	}
	return out;
}

void ClothInstance3D::_drive_bone_attachments() {
	if (cloth.is_null() || bone_attachments.is_empty()) {
		return;
	}
	Skeleton3D *skeleton = _get_skeleton();
	if (!skeleton) {
		return;
	}
	const Transform3D skeleton_global = skeleton->get_global_transform();
	for (const KeyValue<int, BoneAttachment> &kv : bone_attachments) {
		const int bone = skeleton->find_bone(kv.value.bone);
		if (bone < 0 || kv.key < 0 || kv.key >= cloth->particle_count()) {
			continue;
		}
		const Transform3D bone_world = skeleton_global * skeleton->get_bone_global_pose(bone);
		cloth->drive(kv.key, bone_world.xform(kv.value.offset));
	}
}

void ClothInstance3D::rebuild_mesh() {
	_rebuild_mesh();
}

void ClothInstance3D::_rebuild_mesh() {
	fast_path_ok = false;
	if (cloth.is_null() || cloth->particle_count() == 0 || cloth->triangles().is_empty()) {
		array_mesh.unref();
		mesh_vertex_count = 0;
		mesh_triangle_count = 0;
		set_mesh(Ref<Mesh>());
		return;
	}
	const Transform3D to_local = (is_inside_tree() ? get_global_transform() : get_transform()).affine_inverse();
	const int n = cloth->particle_count();

	Vector<Vector3> verts;
	verts.resize(n);
	Vector<Vector3> norms = cloth->normals();
	const Vector<Vector3> world_pos = cloth->positions();
	const Basis normal_basis = to_local.basis.inverse().transposed();
	for (int k = 0; k < n; k++) {
		verts.write[k] = to_local.xform(world_pos[k]);
		norms.write[k] = normal_basis.xform(norms[k]).normalized();
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_NORMAL] = norms;
	arrays[Mesh::ARRAY_TEX_UV] = cloth->uvs();
	arrays[Mesh::ARRAY_INDEX] = cloth->triangles();

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, TypedArray<Array>(), Dictionary(), Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE);

	// The in-place update path requires the plain uncompressed layout: float32 positions followed
	// by octahedral normals. Verify it, otherwise fall back to rebuilding every frame.
	RenderingServer *rs = RenderingServer::get_singleton();
	const uint64_t format = mesh->surface_get_format(0);
	vertex_stride = rs->mesh_surface_get_format_vertex_stride(format, n);
	const uint32_t normal_stride = rs->mesh_surface_get_format_normal_tangent_stride(format, n);
	normal_offset_bytes = rs->mesh_surface_get_format_offset(format, n, Mesh::ARRAY_NORMAL);
	fast_path_ok = vertex_stride == 12 && normal_stride == 4 && !(format & Mesh::ARRAY_FLAG_COMPRESS_ATTRIBUTES) && !(format & Mesh::ARRAY_FLAG_USE_2D_VERTICES);
	position_bytes.resize(n * 12);
	normal_bytes.resize(n * 4);

	array_mesh = mesh;
	mesh_vertex_count = n;
	mesh_triangle_count = cloth->triangles().size();
	set_mesh(array_mesh);
}

void ClothInstance3D::_update_mesh() {
	if (cloth.is_null() || array_mesh.is_null()) {
		return;
	}
	const int n = cloth->particle_count();
	if (n != mesh_vertex_count || cloth->triangles().size() != mesh_triangle_count || !fast_path_ok) {
		// Topology changed (tearing) or the layout is not updatable in place.
		_rebuild_mesh();
		return;
	}
	const Transform3D to_local = (is_inside_tree() ? get_global_transform() : get_transform()).affine_inverse();
	AABB bounds;
	cloth->write_vertex_buffers(to_local, position_bytes.ptrw(), normal_bytes.ptrw(), bounds);

	RenderingServer *rs = RenderingServer::get_singleton();
	rs->mesh_surface_update_vertex_region(array_mesh->get_rid(), 0, 0, position_bytes);
	rs->mesh_surface_update_vertex_region(array_mesh->get_rid(), 0, normal_offset_bytes, normal_bytes);
	array_mesh->set_custom_aabb(bounds.grow(0.05));
}

void ClothInstance3D::simulate(real_t p_delta) {
	if (cloth.is_null()) {
		return;
	}
	_drive_bone_attachments();
	cloth->step(p_delta, substeps);
	_update_mesh();
}

void ClothInstance3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			set_physics_process_internal(!Engine::get_singleton()->is_editor_hint());
			if (cloth.is_valid() && array_mesh.is_null()) {
				_rebuild_mesh();
			}
		} break;

		case NOTIFICATION_EXIT_TREE: {
			set_physics_process_internal(false);
		} break;

		case NOTIFICATION_INTERNAL_PHYSICS_PROCESS: {
			if (simulating) {
				simulate(get_physics_process_delta_time());
			}
		} break;
	}
}

void ClothInstance3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cloth", "cloth"), &ClothInstance3D::set_cloth);
	ClassDB::bind_method(D_METHOD("get_cloth"), &ClothInstance3D::get_cloth);
	ClassDB::bind_method(D_METHOD("set_substeps", "substeps"), &ClothInstance3D::set_substeps);
	ClassDB::bind_method(D_METHOD("get_substeps"), &ClothInstance3D::get_substeps);
	ClassDB::bind_method(D_METHOD("set_simulating", "simulating"), &ClothInstance3D::set_simulating);
	ClassDB::bind_method(D_METHOD("is_simulating"), &ClothInstance3D::is_simulating);
	ClassDB::bind_method(D_METHOD("set_cloth_skeleton_path", "path"), &ClothInstance3D::set_cloth_skeleton_path);
	ClassDB::bind_method(D_METHOD("get_cloth_skeleton_path"), &ClothInstance3D::get_cloth_skeleton_path);

	ClassDB::bind_method(D_METHOD("attach_particle_to_bone", "particle", "bone", "offset"), &ClothInstance3D::attach_particle_to_bone, DEFVAL(Vector3()));
	ClassDB::bind_method(D_METHOD("detach_particle_from_bone", "particle"), &ClothInstance3D::detach_particle_from_bone);
	ClassDB::bind_method(D_METHOD("clear_bone_attachments"), &ClothInstance3D::clear_bone_attachments);
	ClassDB::bind_method(D_METHOD("set_bone_attachments", "map"), &ClothInstance3D::set_bone_attachments);
	ClassDB::bind_method(D_METHOD("get_bone_attachments"), &ClothInstance3D::get_bone_attachments);

	ClassDB::bind_method(D_METHOD("rebuild_mesh"), &ClothInstance3D::rebuild_mesh);
	ClassDB::bind_method(D_METHOD("simulate", "delta"), &ClothInstance3D::simulate);
	ClassDB::bind_method(D_METHOD("is_using_fast_update"), &ClothInstance3D::is_using_fast_update);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "substeps", PROPERTY_HINT_RANGE, "1,64,1"), "set_substeps", "get_substeps");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "simulating"), "set_simulating", "is_simulating");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "cloth_skeleton_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Skeleton3D"), "set_cloth_skeleton_path", "get_cloth_skeleton_path");
}
