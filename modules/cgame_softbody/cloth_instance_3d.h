/**************************************************************************/
/*  cloth_instance_3d.h                                                   */
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

#pragma once

#include "cgame_xpbd_cloth.h"

#include "scene/3d/mesh_instance_3d.h"

class Skeleton3D;

// Scene node that owns a CgameXPBDCloth, steps it every physics frame, optionally pins cloth
// particles to Skeleton3D bones and keeps an ArrayMesh in sync. Vertex data is streamed to the
// GPU with RenderingServer::mesh_surface_update_vertex_region, so no mesh arrays are rebuilt
// while the topology is unchanged.
class ClothInstance3D : public MeshInstance3D {
	GDCLASS(ClothInstance3D, MeshInstance3D);

	struct BoneAttachment {
		StringName bone;
		Vector3 offset;
	};

	Ref<CgameXPBDCloth> cloth;
	int substeps = 8;
	bool simulating = true;
	NodePath skeleton_path;
	HashMap<int, BoneAttachment> bone_attachments;

	Ref<ArrayMesh> array_mesh;
	int mesh_vertex_count = 0;
	int mesh_triangle_count = -1;
	bool fast_path_ok = false;
	uint32_t vertex_stride = 0;
	uint32_t normal_offset_bytes = 0;
	Vector<uint8_t> position_bytes;
	Vector<uint8_t> normal_bytes;

	void _rebuild_mesh();
	void _update_mesh();
	void _drive_bone_attachments();
	Skeleton3D *_get_skeleton() const;

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_cloth(const Ref<CgameXPBDCloth> &p_cloth);
	Ref<CgameXPBDCloth> get_cloth() const { return cloth; }
	void set_substeps(int p_substeps) { substeps = CLAMP(p_substeps, 1, 64); }
	int get_substeps() const { return substeps; }
	void set_simulating(bool p_simulating) { simulating = p_simulating; }
	bool is_simulating() const { return simulating; }
	void set_skeleton_path(const NodePath &p_path);
	NodePath get_skeleton_path() const { return skeleton_path; }

	// Pins cloth particle `p_particle` to the named bone, offset in bone-local space.
	void attach_particle_to_bone(int p_particle, const StringName &p_bone, const Vector3 &p_offset = Vector3());
	void detach_particle_from_bone(int p_particle);
	void clear_bone_attachments();
	void set_bone_attachments(const Dictionary &p_map);
	Dictionary get_bone_attachments() const;

	// Rebuilds the ArrayMesh from the current cloth state (also done automatically on tearing).
	void rebuild_mesh();
	// Steps the cloth once (what the physics notification does), usable for manual stepping.
	void simulate(real_t p_delta);
	// True when the last mesh refresh used the in-place GPU vertex update path.
	bool is_using_fast_update() const { return fast_path_ok; }

	ClothInstance3D() {}
};
