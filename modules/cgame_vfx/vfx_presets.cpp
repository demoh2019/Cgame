/**************************************************************************/
/*  vfx_presets.cpp                                                       */
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

#include "vfx_presets.h"

#include "core/object/class_db.h"

static Dictionary _module(const char *p_type) {
	Dictionary d;
	d["type"] = p_type;
	return d;
}

static Array _stops_f(std::initializer_list<std::pair<double, double>> p_stops) {
	Array out;
	for (const std::pair<double, double> &s : p_stops) {
		Array stop;
		stop.push_back(s.first);
		stop.push_back(s.second);
		out.push_back(stop);
	}
	return out;
}

static Array _stops_c(std::initializer_list<std::pair<double, Color>> p_stops) {
	Array out;
	for (const std::pair<double, Color> &s : p_stops) {
		Array stop;
		stop.push_back(s.first);
		stop.push_back(s.second);
		out.push_back(stop);
	}
	return out;
}

int VFXPresets::get_spark_count(int p_level) {
	static const int counts[4] = { 0, 40, 70, 110 };
	return counts[CLAMP(p_level, 0, 3)];
}

Dictionary VFXPresets::lightning_sparks(int p_level) {
	const int sparks = get_spark_count(p_level);

	Array sp_spawn;
	Dictionary burst = _module("spawn_burst");
	burst["count"] = sparks;
	sp_spawn.push_back(burst);
	Dictionary life = _module("lifetime_random");
	life["min"] = 0.6;
	life["max"] = 1.3;
	sp_spawn.push_back(life);
	Dictionary pos = _module("initial_position_sphere");
	pos["radius"] = 0.4;
	pos["center"] = Vector3(0, 0.3, 0);
	sp_spawn.push_back(pos);
	Dictionary vel = _module("initial_velocity");
	vel["direction"] = Vector3(0, 1, 0);
	vel["spread"] = 70.0;
	vel["speed_min"] = 4.0;
	vel["speed_max"] = 11.0;
	sp_spawn.push_back(vel);
	Dictionary size = _module("initial_size");
	size["min"] = 0.05;
	size["max"] = 0.12;
	sp_spawn.push_back(size);

	Array sp_update;
	Dictionary gravity = _module("gravity");
	gravity["gravity"] = Vector3(0, -14.0, 0);
	sp_update.push_back(gravity);
	Dictionary drag = _module("drag");
	drag["drag"] = 0.6;
	sp_update.push_back(drag);
	Dictionary color = _module("color_over_life");
	color["stops"] = _stops_c({ { 0.0, Color(1.6, 1.6, 2.2, 1.0) }, { 0.35, Color(1.4, 0.8, 0.3, 1.0) }, { 1.0, Color(0.6, 0.15, 0.05, 0.0) } });
	sp_update.push_back(color);
	Dictionary shrink = _module("size_over_life");
	shrink["stops"] = _stops_f({ { 0.0, 1.0 }, { 1.0, 0.3 } });
	sp_update.push_back(shrink);
	Dictionary collide = _module("collide_plane");
	collide["normal"] = Vector3(0, 1, 0);
	collide["offset"] = 0.0;
	collide["restitution"] = 0.35;
	collide["friction"] = 0.3;
	Dictionary on_event;
	on_event["emitter"] = "embers";
	on_event["count"] = 1;
	collide["on_event"] = on_event;
	sp_update.push_back(collide);

	Dictionary sparks_emitter;
	sparks_emitter["max_particles"] = sparks;
	sparks_emitter["spawn"] = sp_spawn;
	sparks_emitter["update"] = sp_update;

	Array em_spawn;
	Dictionary em_life = _module("lifetime_random");
	em_life["min"] = 0.4;
	em_life["max"] = 0.9;
	em_spawn.push_back(em_life);
	Dictionary em_size = _module("initial_size");
	em_size["min"] = 0.04;
	em_size["max"] = 0.07;
	em_spawn.push_back(em_size);
	Dictionary em_vel = _module("initial_velocity");
	em_vel["direction"] = Vector3(0, 1, 0);
	em_vel["spread"] = 50.0;
	em_vel["speed_min"] = 0.3;
	em_vel["speed_max"] = 1.2;
	em_spawn.push_back(em_vel);

	Array em_update;
	Dictionary em_drag = _module("drag");
	em_drag["drag"] = 2.0;
	em_update.push_back(em_drag);
	Dictionary em_color = _module("color_over_life");
	em_color["stops"] = _stops_c({ { 0.0, Color(1.2, 0.5, 0.15, 0.9) }, { 1.0, Color(0.3, 0.05, 0.0, 0.0) } });
	em_update.push_back(em_color);

	Dictionary embers_emitter;
	embers_emitter["max_particles"] = sparks;
	embers_emitter["spawn"] = em_spawn;
	embers_emitter["update"] = em_update;

	Dictionary emitters;
	emitters["sparks"] = sparks_emitter;
	emitters["embers"] = embers_emitter;
	Dictionary out;
	out["emitters"] = emitters;
	return out;
}

VFXGraphInstance3D *VFXPresets::spawn(Node3D *p_parent, const Variant &p_asset, const Vector3 &p_at, int64_t p_seed) {
	if (p_parent == nullptr || !p_at.is_finite()) {
		return nullptr;
	}
	Ref<VFXGraphAsset> asset;
	if (p_asset.get_type() == Variant::DICTIONARY) {
		asset = VFXGraphAsset::create_from_dictionary(p_asset);
	} else if (p_asset.get_type() == Variant::OBJECT) {
		asset = p_asset;
	}
	if (asset.is_null() || !asset->has_particles()) {
		return nullptr;
	}
	bool any = false;
	for (const String &name : asset->get_emitter_names()) {
		const Dictionary def = asset->get_emitter(name);
		const int cap = def.has("max_particles") ? (int)def["max_particles"] : 0;
		if (cap > 0) {
			any = true;
		}
	}
	if (!any) {
		return nullptr;
	}
	VFXGraphInstance3D *node = memnew(VFXGraphInstance3D);
	node->set_one_shot(true);
	node->set_autostart(false);
	node->set_name("VFXGraphEffect");
	p_parent->add_child(node);
	if (node->is_inside_tree()) {
		node->set_global_position(p_at);
	} else {
		node->set_position(p_at);
	}
	node->set_asset(asset);
	node->set_random_seed(p_seed);
	node->play();
	return node;
}

void VFXPresets::_bind_methods() {
	ClassDB::bind_static_method("VFXPresets", D_METHOD("get_spark_count", "level"), &VFXPresets::get_spark_count);
	ClassDB::bind_static_method("VFXPresets", D_METHOD("lightning_sparks", "level"), &VFXPresets::lightning_sparks);
	ClassDB::bind_static_method("VFXPresets", D_METHOD("spawn", "parent", "asset", "at", "seed"), &VFXPresets::spawn);
}
