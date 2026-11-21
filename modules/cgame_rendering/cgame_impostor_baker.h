/**************************************************************************/
/*  cgame_impostor_baker.h                                                */
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

#include "core/io/image.h"
#include "core/math/aabb.h"
#include "core/templates/hash_map.h"
#include "scene/main/node.h"
#include "scene/resources/image_texture.h"
#include "scene/resources/material.h"
#include "scene/resources/mesh.h"
#include "scene/resources/shader.h"

class Camera3D;
class Node3D;
class SceneTree;
class SubViewport;

// Runtime impostor generation (UE5 Impostor Baker, Unity Amplify Impostors). Each mesh is rendered
// once from FRAMES yaw angles into a horizontal atlas inside an isolated SubViewport world, then
// cached for every far field. Headless servers and tests never bake; fields simply stay hidden.
class CgameImpostorBaker : public Node {
	GDCLASS(CgameImpostorBaker, Node);

public:
	static constexpr int FRAMES = 8;
	static constexpr int RESOLUTION = 128;
	// Process frames to wait after rotating the pivot before the viewport image is read back.
	static constexpr int SETTLE_FRAMES = 3;

private:
	static HashMap<ObjectID, Ref<Texture2D>> cache;
	static HashMap<ObjectID, Vector<Callable>> waiting;
	static ObjectID instance_id;
	static Ref<Shader> impostor_shader;

	Vector<Ref<Mesh>> queue;
	Ref<Mesh> current;
	SubViewport *viewport = nullptr;
	Node3D *pivot = nullptr;
	Ref<Image> atlas;
	int frame_index = 0;
	int settle_left = 0;

	void _start_bake(const Ref<Mesh> &p_mesh);
	void _capture_frame();
	void _finish_bake();
	void _abort_all();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	// Pure helper: square bake extent (x) and vertical center (y) for a bounding box.
	static Vector2 frame_size_for_aabb(const AABB &p_box);
	// Pure helper: pixel width of the atlas.
	static int atlas_width() { return RESOLUTION * FRAMES; }

	static Vector2 frame_size(const Ref<Mesh> &p_mesh);
	static bool can_bake();
	static Ref<Texture2D> get_cached(const Ref<Mesh> &p_mesh);
	static Ref<Shader> get_impostor_shader();
	static Ref<ShaderMaterial> material_for(const Ref<Mesh> &p_mesh, const Ref<Texture2D> &p_atlas);
	// Calls p_done(atlas) once the mesh is baked (immediately when cached).
	static void request(const Ref<Mesh> &p_mesh, SceneTree *p_tree, const Callable &p_done);
	static void clear_cache();
	static int get_cache_size() { return cache.size(); }

	CgameImpostorBaker();
	~CgameImpostorBaker();
};
