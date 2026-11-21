/**************************************************************************/
/*  vfx_graph_instance_3d.cpp                                             */
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

#include "vfx_graph_instance_3d.h"

#include "vfx_budget_server.h"

#include "core/config/engine.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/3d/camera_3d.h"
#include "scene/main/viewport.h"
#include "servers/rendering/rendering_server.h"

VFXGraphInstance3D::VFXGraphInstance3D() {
	set_notify_transform(true);
}

VFXGraphInstance3D::~VFXGraphInstance3D() {
	_clear_runtime();
}

void VFXGraphInstance3D::set_asset(const Ref<VFXGraphAsset> &p_asset) {
	asset = p_asset;
}

PackedStringArray VFXGraphInstance3D::get_emitter_names() const {
	PackedStringArray names;
	for (const VFXSim::Emitter *em : system.emitters) {
		names.push_back(em->name);
	}
	return names;
}

Dictionary VFXGraphInstance3D::get_profile() const {
	Dictionary out;
	for (const KeyValue<String, uint64_t> &kv : system.profile) {
		out[kv.key] = (int64_t)kv.value;
	}
	return out;
}

void VFXGraphInstance3D::reset_profile() {
	system.profile.clear();
}

bool VFXGraphInstance3D::is_gpu_active() const {
	return gpu != nullptr && gpu->is_available() && gpu->get_last_path() == "gpu";
}

String VFXGraphInstance3D::get_gpu_path() const {
	if (!use_gpu) {
		return "cpu";
	}
	return gpu != nullptr ? gpu->get_last_path() : String("none");
}

// ---- rendering -------------------------------------------------------------

void VFXGraphInstance3D::_build_renderers() {
	_free_renderers();
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr || asset.is_null()) {
		return;
	}
	const Dictionary defs = asset->get_system()["emitters"];
	for (const VFXSim::Emitter *em : system.emitters) {
		const Dictionary def = defs.has(em->name) && defs[em->name].get_type() == Variant::DICTIONARY ? (Dictionary)defs[em->name] : Dictionary();
		Renderer r;
		r.emitter = em->name;
		r.capacity = em->cap;
		r.buffer.resize(em->cap * 16);
		r.buffer.fill(0.0f);

		r.mesh.instantiate();
		r.mesh->set_size(Size2(1, 1));
		r.material.instantiate();
		r.material->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
		r.material->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
		r.material->set_billboard_mode(BaseMaterial3D::BILLBOARD_ENABLED);
		r.material->set_flag(BaseMaterial3D::FLAG_BILLBOARD_KEEP_SCALE, true);
		r.material->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
		r.material->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
		if (def.has("blend") && String(def["blend"]) == "add") {
			r.material->set_blend_mode(BaseMaterial3D::BLEND_MODE_ADD);
		}
		if (def.has("texture") && def["texture"].get_type() == Variant::OBJECT) {
			const Ref<Texture2D> tex = def["texture"];
			if (tex.is_valid()) {
				r.material->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, tex);
			}
		}
		r.mesh->set_material(r.material);

		r.multimesh = rs->multimesh_create();
		rs->multimesh_allocate_data(r.multimesh, em->cap, RSE::MULTIMESH_TRANSFORM_3D, true);
		rs->multimesh_set_mesh(r.multimesh, r.mesh->get_rid());
		rs->multimesh_set_visible_instances(r.multimesh, 0);
		double half = 100.0;
		if (def.has("bounds") && (def["bounds"].get_type() == Variant::FLOAT || def["bounds"].get_type() == Variant::INT)) {
			half = MAX((double)def["bounds"], 0.001);
		}
		rs->multimesh_set_custom_aabb(r.multimesh, AABB(Vector3(-half, -half, -half), Vector3(half, half, half) * 2.0));

		r.instance = rs->instance_create();
		rs->instance_set_base(r.instance, r.multimesh);
		rs->instance_geometry_set_cast_shadows_setting(r.instance, RSE::SHADOW_CASTING_SETTING_OFF);
		renderers.push_back(r);
	}
	_update_instances_scenario();
	_update_instances_transform();
	_update_instances_visibility();
}

void VFXGraphInstance3D::_free_renderers() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs != nullptr) {
		for (const Renderer &r : renderers) {
			if (r.instance.is_valid()) {
				rs->free_rid(r.instance);
			}
			if (r.multimesh.is_valid()) {
				rs->free_rid(r.multimesh);
			}
		}
	}
	renderers.clear();
}

void VFXGraphInstance3D::_update_instances_scenario() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return;
	}
	const RID scenario = is_inside_tree() && get_world_3d().is_valid() ? get_world_3d()->get_scenario() : RID();
	for (const Renderer &r : renderers) {
		rs->instance_set_scenario(r.instance, scenario);
	}
}

void VFXGraphInstance3D::_update_instances_transform() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr || !is_inside_tree()) {
		return;
	}
	const Transform3D xform = get_global_transform();
	for (const Renderer &r : renderers) {
		rs->instance_set_transform(r.instance, xform);
	}
}

void VFXGraphInstance3D::_update_instances_visibility() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return;
	}
	const bool visible_now = is_inside_tree() && is_visible_in_tree();
	for (const Renderer &r : renderers) {
		rs->instance_set_visible(r.instance, visible_now);
	}
}

void VFXGraphInstance3D::_upload(Renderer &r_renderer) {
	RenderingServer *rs = RenderingServer::get_singleton();
	const VFXSim::Emitter *em = system.get_emitter(r_renderer.emitter);
	if (rs == nullptr || em == nullptr) {
		return;
	}
	float *w = r_renderer.buffer.ptrw();
	const int n = em->count;
	for (int i = 0; i < n; i++) {
		const Vector3 &p = em->pos[i];
		const float s = em->size[i];
		const Color &c = em->col[i];
		float *o = w + i * 16;
		o[0] = s;
		o[1] = 0.0f;
		o[2] = 0.0f;
		o[3] = p.x;
		o[4] = 0.0f;
		o[5] = s;
		o[6] = 0.0f;
		o[7] = p.y;
		o[8] = 0.0f;
		o[9] = 0.0f;
		o[10] = s;
		o[11] = p.z;
		o[12] = c.r;
		o[13] = c.g;
		o[14] = c.b;
		o[15] = c.a;
	}
	rs->multimesh_set_buffer(r_renderer.multimesh, r_renderer.buffer);
	rs->multimesh_set_visible_instances(r_renderer.multimesh, n);
}

// ---- budget ----------------------------------------------------------------

bool VFXGraphInstance3D::_request_budget() {
	VFXBudgetServer *budget = VFXBudgetServer::get_singleton();
	if (budget_category.is_empty() || budget == nullptr) {
		return true;
	}
	Vector3 position;
	Vector3 camera_position;
	if (is_inside_tree()) {
		position = get_global_position();
		const Viewport *viewport = get_viewport();
		const Camera3D *camera = viewport != nullptr ? viewport->get_camera_3d() : nullptr;
		camera_position = camera != nullptr ? camera->get_global_position() : position;
	}
	budget_id = budget->request_id(budget_category, system.total_capacity(), budget_priority, position, camera_position);
	if (budget_id == 0) {
		return false;
	}
	const Callable cb = callable_mp(this, &VFXGraphInstance3D::_on_budget_evicted);
	if (!budget->is_connected(SNAME("evicted"), cb)) {
		budget->connect(SNAME("evicted"), cb);
	}
	return true;
}

void VFXGraphInstance3D::_release_budget() {
	VFXBudgetServer *budget = VFXBudgetServer::get_singleton();
	if (budget != nullptr) {
		const Callable cb = callable_mp(this, &VFXGraphInstance3D::_on_budget_evicted);
		if (budget->is_connected(SNAME("evicted"), cb)) {
			budget->disconnect(SNAME("evicted"), cb);
		}
		if (budget_id != 0) {
			budget->release(budget_id);
		}
	}
	budget_id = 0;
}

void VFXGraphInstance3D::_on_budget_evicted(int p_id, const String &p_category) {
	if (p_id != budget_id) {
		return;
	}
	budget_id = 0; // Already removed on the server side.
	playing = false;
	_finish();
}

// ---- lifecycle -------------------------------------------------------------

void VFXGraphInstance3D::_clear_runtime() {
	_release_budget();
	if (gpu != nullptr) {
		gpu->release(system);
		memdelete(gpu);
		gpu = nullptr;
	}
	system.gpu = nullptr;
	system.clear();
	_free_renderers();
	playing = false;
	done = false;
}

bool VFXGraphInstance3D::play() {
	_clear_runtime();
	if (asset.is_null()) {
		ERR_FAIL_V_MSG(false, "VFXGraphInstance3D: no asset assigned.");
	}
	const PackedStringArray errors = asset->validate();
	if (!errors.is_empty()) {
		ERR_FAIL_V_MSG(false, vformat("VFXGraphInstance3D: invalid graph asset: %s", errors[0]));
	}
	system.create(asset->get_system(), random_seed);
	if (use_gpu) {
		for (VFXSim::Emitter *em : system.emitters) {
			em->lite_curl = true; // Same curl on CPU fallback and GPU.
		}
		gpu = memnew(VFXGpuKernel);
		if (gpu->open()) {
			system.gpu = gpu;
		}
	}
	if (!_request_budget()) {
		system.clear();
		emit_signal(SNAME("rejected"));
		if (one_shot && is_inside_tree()) {
			queue_free();
		}
		return false;
	}
	_build_renderers();
	playing = true;
	done = false;
	set_process(true);
	return true;
}

void VFXGraphInstance3D::stop() {
	if (!playing && system.emitters.is_empty()) {
		return;
	}
	_clear_runtime();
	set_process(false);
}

bool VFXGraphInstance3D::setup(const Dictionary &p_graph, int64_t p_seed) {
	asset = VFXGraphAsset::create_from_dictionary(p_graph);
	random_seed = p_seed;
	return play();
}

void VFXGraphInstance3D::_finish() {
	if (done) {
		return;
	}
	done = true;
	playing = false;
	_release_budget();
	set_process(false);
	emit_signal(SNAME("finished"));
	if (one_shot && is_inside_tree()) {
		queue_free();
	}
}

void VFXGraphInstance3D::step(double p_delta) {
	if (system.emitters.is_empty() || done) {
		return;
	}
	system.budget_left = budget_particles >= 0 ? MAX(budget_particles - system.total_particles(), 0) : -1;
	system.tick(p_delta);
	for (Renderer &r : renderers) {
		_upload(r);
	}
	if (system.is_finished()) {
		_finish();
	}
}

void VFXGraphInstance3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			if (autostart && !Engine::get_singleton()->is_editor_hint() && asset.is_valid() && !playing && !done) {
				play();
			}
		} break;
		case NOTIFICATION_EXIT_TREE: {
			_release_budget();
		} break;
		case NOTIFICATION_ENTER_WORLD: {
			_update_instances_scenario();
			_update_instances_transform();
			_update_instances_visibility();
		} break;
		case NOTIFICATION_EXIT_WORLD: {
			_update_instances_scenario();
		} break;
		case NOTIFICATION_TRANSFORM_CHANGED: {
			_update_instances_transform();
		} break;
		case NOTIFICATION_VISIBILITY_CHANGED: {
			_update_instances_visibility();
		} break;
		case NOTIFICATION_PROCESS: {
			if (playing) {
				step(get_process_delta_time() * time_scale);
			}
		} break;
	}
}

void VFXGraphInstance3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_asset", "asset"), &VFXGraphInstance3D::set_asset);
	ClassDB::bind_method(D_METHOD("get_asset"), &VFXGraphInstance3D::get_asset);
	ClassDB::bind_method(D_METHOD("set_random_seed", "seed"), &VFXGraphInstance3D::set_random_seed);
	ClassDB::bind_method(D_METHOD("get_random_seed"), &VFXGraphInstance3D::get_random_seed);
	ClassDB::bind_method(D_METHOD("set_one_shot", "one_shot"), &VFXGraphInstance3D::set_one_shot);
	ClassDB::bind_method(D_METHOD("is_one_shot"), &VFXGraphInstance3D::is_one_shot);
	ClassDB::bind_method(D_METHOD("set_autostart", "autostart"), &VFXGraphInstance3D::set_autostart);
	ClassDB::bind_method(D_METHOD("is_autostart"), &VFXGraphInstance3D::is_autostart);
	ClassDB::bind_method(D_METHOD("set_use_gpu", "use_gpu"), &VFXGraphInstance3D::set_use_gpu);
	ClassDB::bind_method(D_METHOD("is_using_gpu"), &VFXGraphInstance3D::is_using_gpu);
	ClassDB::bind_method(D_METHOD("set_budget_particles", "budget"), &VFXGraphInstance3D::set_budget_particles);
	ClassDB::bind_method(D_METHOD("get_budget_particles"), &VFXGraphInstance3D::get_budget_particles);
	ClassDB::bind_method(D_METHOD("set_time_scale", "scale"), &VFXGraphInstance3D::set_time_scale);
	ClassDB::bind_method(D_METHOD("get_time_scale"), &VFXGraphInstance3D::get_time_scale);
	ClassDB::bind_method(D_METHOD("set_budget_category", "category"), &VFXGraphInstance3D::set_budget_category);
	ClassDB::bind_method(D_METHOD("get_budget_category"), &VFXGraphInstance3D::get_budget_category);
	ClassDB::bind_method(D_METHOD("set_budget_priority", "priority"), &VFXGraphInstance3D::set_budget_priority);
	ClassDB::bind_method(D_METHOD("get_budget_priority"), &VFXGraphInstance3D::get_budget_priority);

	ClassDB::bind_method(D_METHOD("play"), &VFXGraphInstance3D::play);
	ClassDB::bind_method(D_METHOD("stop"), &VFXGraphInstance3D::stop);
	ClassDB::bind_method(D_METHOD("restart"), &VFXGraphInstance3D::restart);
	ClassDB::bind_method(D_METHOD("setup", "graph", "seed"), &VFXGraphInstance3D::setup, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("step", "delta"), &VFXGraphInstance3D::step);
	ClassDB::bind_method(D_METHOD("is_playing"), &VFXGraphInstance3D::is_playing);
	ClassDB::bind_method(D_METHOD("is_finished"), &VFXGraphInstance3D::is_finished);
	ClassDB::bind_method(D_METHOD("get_particle_count"), &VFXGraphInstance3D::get_particle_count);
	ClassDB::bind_method(D_METHOD("get_emitter_particle_count", "emitter"), &VFXGraphInstance3D::get_emitter_particle_count);
	ClassDB::bind_method(D_METHOD("get_emitter_names"), &VFXGraphInstance3D::get_emitter_names);
	ClassDB::bind_method(D_METHOD("get_attribute", "emitter", "attribute"), &VFXGraphInstance3D::get_attribute);
	ClassDB::bind_method(D_METHOD("get_profile"), &VFXGraphInstance3D::get_profile);
	ClassDB::bind_method(D_METHOD("reset_profile"), &VFXGraphInstance3D::reset_profile);
	ClassDB::bind_method(D_METHOD("is_gpu_active"), &VFXGraphInstance3D::is_gpu_active);
	ClassDB::bind_method(D_METHOD("get_gpu_path"), &VFXGraphInstance3D::get_gpu_path);
	ClassDB::bind_method(D_METHOD("get_budget_id"), &VFXGraphInstance3D::get_budget_id);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "asset", PROPERTY_HINT_RESOURCE_TYPE, "VFXGraphAsset"), "set_asset", "get_asset");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "random_seed"), "set_random_seed", "get_random_seed");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "one_shot"), "set_one_shot", "is_one_shot");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "autostart"), "set_autostart", "is_autostart");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_scale", PROPERTY_HINT_RANGE, "0,8,0.01,or_greater"), "set_time_scale", "get_time_scale");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_gpu"), "set_use_gpu", "is_using_gpu");
	ADD_GROUP("Budget", "budget_");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "budget_particles", PROPERTY_HINT_RANGE, "-1,100000,1,or_greater"), "set_budget_particles", "get_budget_particles");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "budget_category"), "set_budget_category", "get_budget_category");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "budget_priority", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_budget_priority", "get_budget_priority");

	ADD_SIGNAL(MethodInfo("finished"));
	ADD_SIGNAL(MethodInfo("rejected"));
}
