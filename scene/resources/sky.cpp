/**************************************************************************/
/*  sky.cpp                                                               */
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

#include "sky.h"

#include "core/object/class_db.h"
#include "servers/rendering/rendering_server.h"

void Sky::set_radiance_size(RadianceSize p_size) {
	ERR_FAIL_INDEX(p_size, RADIANCE_SIZE_MAX);
	// The same quality level can be applied repeatedly by Auto. Sending
	// sky_set_radiance_size each time may invalidate the radiance cubemap
	// even though the allocation and lighting resolution did not change.
	if (radiance_uploaded && radiance_size == p_size) {
		return;
	}
	radiance_size = p_size;
	radiance_uploaded = true;
	static const int size[RADIANCE_SIZE_MAX] = {
		32, 64, 128, 256, 512, 1024, 2048
	};
	RS::get_singleton()->sky_set_radiance_size(sky, size[radiance_size]);
}

Sky::RadianceSize Sky::get_radiance_size() const {
	return radiance_size;
}

void Sky::set_process_mode(ProcessMode p_mode) {
	ERR_FAIL_INDEX(p_mode, PROCESS_MODE_REALTIME + 1);
	if (process_mode_uploaded && mode == p_mode) {
		return;
	}
	mode = p_mode;
	process_mode_uploaded = true;
	RS::get_singleton()->sky_set_mode(sky, RSE::SkyMode(mode));
}

Sky::ProcessMode Sky::get_process_mode() const {
	return mode;
}

void Sky::configure_render_budget(RadianceSize p_size, ProcessMode p_mode) {
	ERR_FAIL_INDEX(p_size, RADIANCE_SIZE_MAX);
	ERR_FAIL_INDEX(p_mode, PROCESS_MODE_REALTIME + 1);
	// A single native entrypoint for game profile changes. Each setter
	// skips unchanged values; no sky work is requested for repeated presets.
	set_radiance_size(p_size);
	set_process_mode(p_mode);
}

void Sky::set_material(const Ref<Material> &p_material) {
	if (material_uploaded && sky_material == p_material) {
		return;
	}
	sky_material = p_material;
	material_uploaded = true;
	RID material_rid;
	if (sky_material.is_valid()) {
		material_rid = sky_material->get_rid();
	}
	RS::get_singleton()->sky_set_material(sky, material_rid);
}

Ref<Material> Sky::get_material() const {
	return sky_material;
}

RID Sky::get_rid() const {
	return sky;
}

void Sky::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_radiance_size", "size"), &Sky::set_radiance_size);
	ClassDB::bind_method(D_METHOD("get_radiance_size"), &Sky::get_radiance_size);

	ClassDB::bind_method(D_METHOD("set_process_mode", "mode"), &Sky::set_process_mode);
	ClassDB::bind_method(D_METHOD("get_process_mode"), &Sky::get_process_mode);
	ClassDB::bind_method(D_METHOD("configure_render_budget", "radiance_size", "process_mode"), &Sky::configure_render_budget);

	ClassDB::bind_method(D_METHOD("set_material", "material"), &Sky::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &Sky::get_material);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "sky_material", PROPERTY_HINT_RESOURCE_TYPE, "PanoramaSkyMaterial,ProceduralSkyMaterial,PhysicalSkyMaterial,ShaderMaterial", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "process_mode", PROPERTY_HINT_ENUM, "Automatic,High-Quality,High-Quality Incremental,Real-Time"), "set_process_mode", "get_process_mode");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "radiance_size", PROPERTY_HINT_ENUM, "32,64,128,256,512,1024,2048"), "set_radiance_size", "get_radiance_size");

	BIND_ENUM_CONSTANT(RADIANCE_SIZE_32);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_64);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_128);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_256);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_512);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_1024);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_2048);
	BIND_ENUM_CONSTANT(RADIANCE_SIZE_MAX);

	BIND_ENUM_CONSTANT(PROCESS_MODE_AUTOMATIC);
	BIND_ENUM_CONSTANT(PROCESS_MODE_QUALITY);
	BIND_ENUM_CONSTANT(PROCESS_MODE_INCREMENTAL);
	BIND_ENUM_CONSTANT(PROCESS_MODE_REALTIME);
}

Sky::Sky() {
	sky = RS::get_singleton()->sky_create();
}

Sky::~Sky() {
	ERR_FAIL_NULL(RenderingServer::get_singleton());
	RS::get_singleton()->free_rid(sky);
}
