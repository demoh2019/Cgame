/**************************************************************************/
/*  cgame_shader_warmup.cpp                                               */
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

#include "cgame_shader_warmup.h"

#include "core/object/class_db.h"

#include "core/io/dir_access.h"
#include "core/io/resource_loader.h"
#include "scene/3d/camera_3d.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/material.h"
#include "servers/display/display_server.h"
#include "servers/rendering/rendering_server.h"

Vector3 CgameShaderWarmup::slot_position(int p_index, float p_camera_near) {
	return Vector3((float)(p_index % GRID_COLUMNS) * 0.003f - 0.012f, Math::floor((float)p_index / (float)GRID_COLUMNS) * 0.003f, -(p_camera_near + 0.05f));
}

PackedStringArray CgameShaderWarmup::default_shader_dirs() {
	PackedStringArray dirs;
	dirs.push_back("res://assets/shaders");
	dirs.push_back("res://shaders");
	return dirs;
}

PackedStringArray CgameShaderWarmup::shader_paths(const PackedStringArray &p_dirs) {
	const PackedStringArray dirs = p_dirs.is_empty() ? default_shader_dirs() : p_dirs;
	Vector<String> found;
	for (const String &dir : dirs) {
		if (!DirAccess::dir_exists_absolute(dir)) {
			continue;
		}
		const Vector<String> files = ResourceLoader::list_directory(dir);
		for (const String &file : files) {
			const String name = file.trim_suffix(".remap");
			if (name.ends_with(".gdshader")) {
				found.push_back(dir + "/" + name);
			}
		}
	}
	found.sort();
	PackedStringArray result;
	for (const String &path : found) {
		result.push_back(path);
	}
	return result;
}

TypedArray<Shader> CgameShaderWarmup::spatial_shaders(const PackedStringArray &p_dirs) {
	TypedArray<Shader> shaders;
	for (const String &path : shader_paths(p_dirs)) {
		// Directory indexes can outlive deleted shader sources (.uid/.remap).
		if (!ResourceLoader::exists(path, "Shader")) {
			continue;
		}
		Ref<Shader> shader = ResourceLoader::load(path);
		if (shader.is_valid() && shader->get_mode() == Shader::MODE_SPATIAL) {
			shaders.push_back(shader);
		}
	}
	return shaders;
}

CgameShaderWarmup *CgameShaderWarmup::start(Camera3D *p_camera, const PackedStringArray &p_dirs) {
	if (p_camera == nullptr) {
		return nullptr;
	}
	DisplayServer *ds = DisplayServer::get_singleton();
	if (ds == nullptr || ds->get_name() == "headless") {
		return nullptr;
	}
	return start_with_shaders(p_camera, spatial_shaders(p_dirs));
}

CgameShaderWarmup *CgameShaderWarmup::start_with_shaders(Camera3D *p_camera, const TypedArray<Shader> &p_shaders) {
	if (p_camera == nullptr) {
		return nullptr;
	}
	CgameShaderWarmup *rig = memnew(CgameShaderWarmup);
	rig->set_name("ShaderWarmup");
	Ref<QuadMesh> quad;
	quad.instantiate();
	quad->set_size(Vector2(0.002f, 0.002f));
	int slot = 0;
	for (int i = 0; i < p_shaders.size(); i++) {
		Ref<Shader> shader = p_shaders[i];
		if (shader.is_null() || shader->get_mode() != Shader::MODE_SPATIAL) {
			continue;
		}
		Ref<ShaderMaterial> material;
		material.instantiate();
		material->set_shader(shader);
		MeshInstance3D *instance = memnew(MeshInstance3D);
		instance->set_mesh(quad);
		instance->set_material_override(material);
		instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_ON); // Shadow pipeline too.
		instance->set_position(slot_position(slot, p_camera->get_near()));
		rig->add_child(instance);
		slot++;
	}
	p_camera->add_child(rig);
	return rig;
}

Dictionary CgameShaderWarmup::get_pipeline_compile_counters() {
	Dictionary counters;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return counters;
	}
	const int64_t canvas = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS);
	const int64_t mesh = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_MESH);
	const int64_t surface = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE);
	const int64_t draw = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW);
	const int64_t specialization = (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION);
	counters["canvas"] = canvas;
	counters["mesh"] = mesh;
	counters["surface"] = surface;
	counters["draw"] = draw;
	counters["specialization"] = specialization;
	counters["total"] = canvas + mesh + surface + draw + specialization;
	return counters;
}

int CgameShaderWarmup::get_pipeline_compile_total() {
	return (int)(int64_t)get_pipeline_compile_counters().get("total", 0);
}

void CgameShaderWarmup::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			set_process(true);
		} break;
		case NOTIFICATION_PROCESS: {
			frames_left--;
			if (frames_left <= 0) {
				queue_free();
			}
		} break;
	}
}

void CgameShaderWarmup::_bind_methods() {
	BIND_CONSTANT(FRAMES_VISIBLE);
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("default_shader_dirs"), &CgameShaderWarmup::default_shader_dirs);
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("shader_paths", "dirs"), &CgameShaderWarmup::shader_paths, DEFVAL(PackedStringArray()));
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("spatial_shaders", "dirs"), &CgameShaderWarmup::spatial_shaders, DEFVAL(PackedStringArray()));
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("start", "camera", "dirs"), &CgameShaderWarmup::start, DEFVAL(PackedStringArray()));
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("start_with_shaders", "camera", "shaders"), &CgameShaderWarmup::start_with_shaders);
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("get_pipeline_compile_counters"), &CgameShaderWarmup::get_pipeline_compile_counters);
	ClassDB::bind_static_method("CgameShaderWarmup", D_METHOD("get_pipeline_compile_total"), &CgameShaderWarmup::get_pipeline_compile_total);
	ClassDB::bind_method(D_METHOD("get_frames_left"), &CgameShaderWarmup::get_frames_left);
}
