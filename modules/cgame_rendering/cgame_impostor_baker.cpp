/**************************************************************************/
/*  cgame_impostor_baker.cpp                                              */
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

#include "cgame_impostor_baker.h"

#include "core/object/class_db.h"

#include "core/math/math_funcs.h"
#include "scene/3d/camera_3d.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/world_environment.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"
#include "scene/main/window.h"
#include "scene/resources/environment.h"
#include "servers/display/display_server.h"

HashMap<ObjectID, Ref<Texture2D>> CgameImpostorBaker::cache;
HashMap<ObjectID, Vector<Callable>> CgameImpostorBaker::waiting;
ObjectID CgameImpostorBaker::instance_id;
Ref<Shader> CgameImpostorBaker::impostor_shader;

// Octant-style impostor (UE5 Impostor Baker / SpeedTree billboard LOD): a camera-facing cylindrical
// quad that picks the baked yaw frame matching the view direction in the instance's own space.
static const char *IMPOSTOR_SHADER_CODE = R"GDSHADER(shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform vec2 quad_size = vec2(1.0); // Square bake extent (x) and vertical center (y).
uniform float alpha_cut = 0.45;

varying flat float frame_index;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	mat3 basis = mat3(MODEL_MATRIX);
	float sx = length(basis[0]);
	float sy = length(basis[1]);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 fwd = length(to_cam) > 0.0001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec2 local = vec2(UV.x - 0.5, 0.5 - UV.y) * quad_size.x;
	VERTEX = origin + right * local.x * sx + vec3(0.0, 1.0, 0.0) * (local.y + quad_size.y) * sy;
	NORMAL = fwd;
	// View direction expressed in the instance's unscaled local frame.
	vec3 ld = vec3(dot(fwd, basis[0] / sx), 0.0, dot(fwd, basis[2] / max(length(basis[2]), 0.0001)));
	float a = atan(ld.x, ld.z);
	frame_index = mod(round(-a / (TAU / frames)), frames);
}

void fragment() {
	vec2 uv = vec2((frame_index + UV.x) / frames, UV.y);
	vec4 c = texture(atlas, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
)GDSHADER";

Vector2 CgameImpostorBaker::frame_size_for_aabb(const AABB &p_box) {
	const float horizontal = Vector2(p_box.size.x, p_box.size.z).length();
	const float extent = MAX(MAX(horizontal, p_box.size.y), 0.05f) * 1.05f;
	return Vector2(extent, p_box.position.y + p_box.size.y * 0.5f);
}

Vector2 CgameImpostorBaker::frame_size(const Ref<Mesh> &p_mesh) {
	if (p_mesh.is_null()) {
		return Vector2(1.0, 0.5);
	}
	return frame_size_for_aabb(p_mesh->get_aabb());
}

bool CgameImpostorBaker::can_bake() {
	DisplayServer *ds = DisplayServer::get_singleton();
	return ds != nullptr && ds->get_name() != "headless";
}

Ref<Texture2D> CgameImpostorBaker::get_cached(const Ref<Mesh> &p_mesh) {
	if (p_mesh.is_null()) {
		return Ref<Texture2D>();
	}
	HashMap<ObjectID, Ref<Texture2D>>::Iterator it = cache.find(p_mesh->get_instance_id());
	return it ? it->value : Ref<Texture2D>();
}

Ref<Shader> CgameImpostorBaker::get_impostor_shader() {
	if (impostor_shader.is_null()) {
		impostor_shader.instantiate();
		impostor_shader->set_code(IMPOSTOR_SHADER_CODE);
	}
	return impostor_shader;
}

Ref<ShaderMaterial> CgameImpostorBaker::material_for(const Ref<Mesh> &p_mesh, const Ref<Texture2D> &p_atlas) {
	Ref<ShaderMaterial> material;
	material.instantiate();
	material->set_shader(get_impostor_shader());
	material->set_shader_parameter("atlas", p_atlas);
	material->set_shader_parameter("frames", (float)FRAMES);
	material->set_shader_parameter("quad_size", frame_size(p_mesh));
	return material;
}

void CgameImpostorBaker::request(const Ref<Mesh> &p_mesh, SceneTree *p_tree, const Callable &p_done) {
	if (p_mesh.is_null()) {
		return;
	}
	const ObjectID key = p_mesh->get_instance_id();
	HashMap<ObjectID, Ref<Texture2D>>::Iterator cached = cache.find(key);
	if (cached) {
		Variant atlas = cached->value;
		const Variant *args[1] = { &atlas };
		Variant ret;
		Callable::CallError err;
		p_done.callp(args, 1, ret, err);
		return;
	}
	if (p_tree == nullptr || !can_bake()) {
		return;
	}
	HashMap<ObjectID, Vector<Callable>>::Iterator pending = waiting.find(key);
	if (pending) {
		pending->value.push_back(p_done);
		return;
	}
	Vector<Callable> callbacks;
	callbacks.push_back(p_done);
	waiting.insert(key, callbacks);

	CgameImpostorBaker *baker = Object::cast_to<CgameImpostorBaker>(ObjectDB::get_instance(instance_id));
	if (baker == nullptr) {
		baker = memnew(CgameImpostorBaker);
		baker->set_name("ImpostorBaker");
		instance_id = baker->get_instance_id();
		p_tree->get_root()->call_deferred("add_child", baker);
	}
	baker->queue.push_back(p_mesh);
}

void CgameImpostorBaker::clear_cache() {
	cache.clear();
	waiting.clear();
}

void CgameImpostorBaker::_start_bake(const Ref<Mesh> &p_mesh) {
	current = p_mesh;
	const Vector2 size = frame_size(p_mesh);
	const AABB box = p_mesh->get_aabb();

	viewport = memnew(SubViewport);
	viewport->set_size(Vector2i(RESOLUTION, RESOLUTION));
	viewport->set_transparent_background(true);
	viewport->set_use_own_world_3d(true);
	viewport->set_update_mode(SubViewport::UPDATE_ALWAYS);

	Ref<Environment> env;
	env.instantiate();
	env->set_background(Environment::BG_CLEAR_COLOR);
	// Flat ambient bake: scene lights shade the impostor at runtime, not twice.
	env->set_ambient_source(Environment::AMBIENT_SOURCE_COLOR);
	env->set_ambient_light_color(Color(1, 1, 1));
	env->set_ambient_light_energy(1.0);
	WorldEnvironment *world_env = memnew(WorldEnvironment);
	world_env->set_environment(env);
	viewport->add_child(world_env);

	pivot = memnew(Node3D);
	viewport->add_child(pivot);
	MeshInstance3D *model = memnew(MeshInstance3D);
	model->set_mesh(p_mesh);
	const Vector3 center = box.get_center();
	model->set_position(Vector3(-center.x, 0.0, -center.z));
	pivot->add_child(model);

	Camera3D *camera = memnew(Camera3D);
	camera->set_orthogonal(size.x, 0.01f, size.x * 4.0f);
	camera->set_position(Vector3(0.0, size.y, size.x * 2.0f));
	viewport->add_child(camera);
	add_child(viewport);

	atlas = Image::create_empty(RESOLUTION * FRAMES, RESOLUTION, false, Image::FORMAT_RGBA8);
	frame_index = 0;
	pivot->set_rotation(Vector3(0, 0, 0));
	settle_left = SETTLE_FRAMES;
}

void CgameImpostorBaker::_capture_frame() {
	Ref<Image> shot = viewport->get_texture()->get_image();
	if (shot.is_valid() && !shot->is_empty()) {
		shot->convert(Image::FORMAT_RGBA8);
		atlas->blit_rect(shot, Rect2i(Vector2i(), shot->get_size()), Vector2i(frame_index * RESOLUTION, 0));
	}
	frame_index++;
	if (frame_index >= FRAMES) {
		_finish_bake();
		return;
	}
	pivot->set_rotation(Vector3(0.0, Math::TAU * (float)frame_index / (float)FRAMES, 0.0));
	settle_left = SETTLE_FRAMES;
}

void CgameImpostorBaker::_finish_bake() {
	viewport->queue_free();
	viewport = nullptr;
	pivot = nullptr;
	atlas->generate_mipmaps();
	Ref<Texture2D> texture = ImageTexture::create_from_image(atlas);
	atlas.unref();
	const ObjectID key = current->get_instance_id();
	cache.insert(key, texture);
	HashMap<ObjectID, Vector<Callable>>::Iterator pending = waiting.find(key);
	if (pending) {
		const Vector<Callable> callbacks = pending->value;
		waiting.remove(pending);
		for (const Callable &callback : callbacks) {
			if (!callback.is_valid()) {
				continue;
			}
			Variant arg = texture;
			const Variant *args[1] = { &arg };
			Variant ret;
			Callable::CallError err;
			callback.callp(args, 1, ret, err);
		}
	}
	current.unref();
}

void CgameImpostorBaker::_abort_all() {
	for (const Ref<Mesh> &mesh : queue) {
		if (mesh.is_valid()) {
			waiting.erase(mesh->get_instance_id());
		}
	}
	if (current.is_valid()) {
		waiting.erase(current->get_instance_id());
	}
	queue.clear();
	current.unref();
}

void CgameImpostorBaker::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			set_process(true);
		} break;
		case NOTIFICATION_PROCESS: {
			if (current.is_null()) {
				if (queue.is_empty()) {
					return;
				}
				Ref<Mesh> next = queue[0];
				queue.remove_at(0);
				if (next.is_valid()) {
					_start_bake(next);
				}
				return;
			}
			settle_left--;
			if (settle_left <= 0 && viewport != nullptr) {
				_capture_frame();
			}
		} break;
		case NOTIFICATION_PREDELETE: {
			if (instance_id == get_instance_id()) {
				instance_id = ObjectID();
			}
			_abort_all();
		} break;
	}
}

void CgameImpostorBaker::_bind_methods() {
	BIND_CONSTANT(FRAMES);
	BIND_CONSTANT(RESOLUTION);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("frame_size", "mesh"), &CgameImpostorBaker::frame_size);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("can_bake"), &CgameImpostorBaker::can_bake);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("get_cached", "mesh"), &CgameImpostorBaker::get_cached);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("get_impostor_shader"), &CgameImpostorBaker::get_impostor_shader);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("material_for", "mesh", "atlas"), &CgameImpostorBaker::material_for);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("request", "mesh", "tree", "done"), &CgameImpostorBaker::request);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("clear_cache"), &CgameImpostorBaker::clear_cache);
	ClassDB::bind_static_method("CgameImpostorBaker", D_METHOD("get_cache_size"), &CgameImpostorBaker::get_cache_size);
}

CgameImpostorBaker::CgameImpostorBaker() {
}

CgameImpostorBaker::~CgameImpostorBaker() {
}
