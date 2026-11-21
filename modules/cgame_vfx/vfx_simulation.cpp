/**************************************************************************/
/*  vfx_simulation.cpp                                                    */
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

#include "vfx_simulation.h"

#include "vfx_gpu_kernel.h"

#include "core/math/math_funcs.h"
#include "core/os/os.h"
#include "scene/resources/gradient.h"

namespace VFXSim {

static const Vector3 OFFSET_A = Vector3(0.0, 0.0, 0.0);
static const Vector3 OFFSET_B = Vector3(31.4, 17.2, 5.9);
static const Vector3 OFFSET_C = Vector3(-12.7, 44.1, 23.3);

// ---- module classification -------------------------------------------------

ModuleType module_type_from_name(const String &p_name) {
	static const struct {
		const char *name;
		ModuleType type;
	} table[] = {
		{ "spawn_rate", MODULE_SPAWN_RATE },
		{ "spawn_burst", MODULE_SPAWN_BURST },
		{ "initial_position_sphere", MODULE_INITIAL_POSITION_SPHERE },
		{ "initial_position_box", MODULE_INITIAL_POSITION_BOX },
		{ "initial_position_cone", MODULE_INITIAL_POSITION_CONE },
		{ "initial_velocity", MODULE_INITIAL_VELOCITY },
		{ "lifetime_random", MODULE_LIFETIME_RANDOM },
		{ "initial_color", MODULE_INITIAL_COLOR },
		{ "initial_size", MODULE_INITIAL_SIZE },
		{ "initial_attribute", MODULE_INITIAL_ATTRIBUTE },
		{ "gravity", MODULE_GRAVITY },
		{ "drag", MODULE_DRAG },
		{ "curl_noise", MODULE_CURL_NOISE },
		{ "vortex", MODULE_VORTEX },
		{ "attractor", MODULE_ATTRACTOR },
		{ "color_over_life", MODULE_COLOR_OVER_LIFE },
		{ "size_over_life", MODULE_SIZE_OVER_LIFE },
		{ "collide_plane", MODULE_COLLIDE_PLANE },
		{ "kill_below_plane", MODULE_KILL_BELOW_PLANE },
	};
	for (const auto &entry : table) {
		if (p_name == entry.name) {
			return entry.type;
		}
	}
	return MODULE_UNKNOWN;
}

bool is_spawn_stage_module(ModuleType p_type) {
	return p_type >= MODULE_SPAWN_RATE && p_type <= MODULE_INITIAL_ATTRIBUTE;
}

bool is_update_stage_module(ModuleType p_type) {
	return p_type >= MODULE_GRAVITY && p_type <= MODULE_KILL_BELOW_PLANE;
}

bool is_post_module(ModuleType p_type) {
	return p_type == MODULE_COLLIDE_PLANE || p_type == MODULE_KILL_BELOW_PLANE;
}

bool is_emission_module(ModuleType p_type) {
	return p_type == MODULE_SPAWN_RATE || p_type == MODULE_SPAWN_BURST;
}

// ---- dictionary helpers ----------------------------------------------------

static real_t _get_float(const Dictionary &p_dict, const String &p_key, real_t p_default) {
	if (!p_dict.has(p_key)) {
		return p_default;
	}
	const Variant v = p_dict[p_key];
	if (v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT) {
		return (real_t)(double)v;
	}
	return p_default;
}

static bool _get_bool(const Dictionary &p_dict, const String &p_key, bool p_default) {
	if (!p_dict.has(p_key)) {
		return p_default;
	}
	const Variant v = p_dict[p_key];
	if (v.get_type() == Variant::BOOL || v.get_type() == Variant::INT) {
		return (bool)v;
	}
	return p_default;
}

static Vector3 _get_vec3(const Dictionary &p_dict, const String &p_key, const Vector3 &p_default) {
	if (!p_dict.has(p_key)) {
		return p_default;
	}
	const Variant v = p_dict[p_key];
	if (v.get_type() == Variant::VECTOR3) {
		return (Vector3)v;
	}
	return p_default;
}

static Color _get_color(const Dictionary &p_dict, const String &p_key, const Color &p_default) {
	if (!p_dict.has(p_key)) {
		return p_default;
	}
	const Variant v = p_dict[p_key];
	if (v.get_type() == Variant::COLOR) {
		return (Color)v;
	}
	return p_default;
}

static void _parse_specs(const Variant &p_spec, Vector<EventSpec> &r_out) {
	LocalVector<Dictionary> dicts;
	if (p_spec.get_type() == Variant::DICTIONARY) {
		dicts.push_back((Dictionary)p_spec);
	} else if (p_spec.get_type() == Variant::ARRAY) {
		const Array arr = p_spec;
		for (int i = 0; i < arr.size(); i++) {
			if (arr[i].get_type() == Variant::DICTIONARY) {
				dicts.push_back((Dictionary)arr[i]);
			}
		}
	}
	for (const Dictionary &d : dicts) {
		EventSpec spec;
		spec.emitter = d.has("emitter") ? String(d["emitter"]) : String();
		spec.count = (int)_get_float(d, "count", 1);
		spec.inherit_velocity = _get_float(d, "inherit_velocity", 0.0);
		r_out.push_back(spec);
	}
}

static void _parse_stops(const Dictionary &p_dict, Module &r_module, bool p_color) {
	if (p_color) {
		Ref<Gradient> gradient;
		if (p_dict.has("gradient")) {
			const Variant gv = p_dict["gradient"];
			if (gv.get_type() == Variant::OBJECT) {
				gradient = gv;
			}
		}
		if (gradient.is_valid()) {
			for (int i = 0; i < GRADIENT_BAKE_SAMPLES; i++) {
				const float t = (float)i / (float)(GRADIENT_BAKE_SAMPLES - 1);
				r_module.stop_t.push_back(t);
				r_module.stop_c.push_back(gradient->get_color_at_offset(t));
			}
			return;
		}
	}
	if (!p_dict.has("stops") || p_dict["stops"].get_type() != Variant::ARRAY) {
		return;
	}
	const Array stops = p_dict["stops"];
	for (int i = 0; i < stops.size(); i++) {
		if (stops[i].get_type() != Variant::ARRAY) {
			continue;
		}
		const Array stop = stops[i];
		if (stop.size() != 2) {
			continue;
		}
		const Variant tv = stop[0];
		const Variant vv = stop[1];
		if (tv.get_type() != Variant::FLOAT && tv.get_type() != Variant::INT) {
			continue;
		}
		if (p_color) {
			if (vv.get_type() != Variant::COLOR) {
				continue;
			}
			r_module.stop_c.push_back((Color)vv);
		} else {
			if (vv.get_type() != Variant::FLOAT && vv.get_type() != Variant::INT) {
				continue;
			}
			r_module.stop_f.push_back((float)(double)vv);
		}
		r_module.stop_t.push_back((float)(double)tv);
	}
}

// ---- noise / curves --------------------------------------------------------

static uint32_t _hash3(int32_t p_x, int32_t p_y, int32_t p_z, uint32_t p_seed) {
	uint32_t h = p_seed ^ ((uint32_t)p_x * 0x9E3779B1u) ^ ((uint32_t)p_y * 0x85EBCA77u) ^ ((uint32_t)p_z * 0xC2B2AE3Du);
	h ^= h >> 15;
	h *= 0x2C1B3C6Du;
	h ^= h >> 12;
	h *= 0x297A2D39u;
	h ^= h >> 15;
	return h;
}

static float _lattice(int32_t p_x, int32_t p_y, int32_t p_z, uint32_t p_seed) {
	return (float)(_hash3(p_x, p_y, p_z, p_seed) & 0xFFFFFFu) / (float)0x7FFFFFu - 1.0f;
}

float noise3(const Vector3 &p_pos, uint32_t p_seed) {
	const float fx = Math::floor(p_pos.x);
	const float fy = Math::floor(p_pos.y);
	const float fz = Math::floor(p_pos.z);
	const int32_t ix = (int32_t)fx;
	const int32_t iy = (int32_t)fy;
	const int32_t iz = (int32_t)fz;
	const float tx = p_pos.x - fx;
	const float ty = p_pos.y - fy;
	const float tz = p_pos.z - fz;
	const float sx = tx * tx * (3.0f - 2.0f * tx);
	const float sy = ty * ty * (3.0f - 2.0f * ty);
	const float sz = tz * tz * (3.0f - 2.0f * tz);
	const float c000 = _lattice(ix, iy, iz, p_seed);
	const float c100 = _lattice(ix + 1, iy, iz, p_seed);
	const float c010 = _lattice(ix, iy + 1, iz, p_seed);
	const float c110 = _lattice(ix + 1, iy + 1, iz, p_seed);
	const float c001 = _lattice(ix, iy, iz + 1, p_seed);
	const float c101 = _lattice(ix + 1, iy, iz + 1, p_seed);
	const float c011 = _lattice(ix, iy + 1, iz + 1, p_seed);
	const float c111 = _lattice(ix + 1, iy + 1, iz + 1, p_seed);
	const float x00 = Math::lerp(c000, c100, sx);
	const float x10 = Math::lerp(c010, c110, sx);
	const float x01 = Math::lerp(c001, c101, sx);
	const float x11 = Math::lerp(c011, c111, sx);
	return Math::lerp(Math::lerp(x00, x10, sy), Math::lerp(x01, x11, sy), sz);
}

static Vector3 _curl_potential(const Vector3 &q, float f) {
	return Vector3(
			Math::sin(q.y * f + 1.3f) * Math::cos(q.z * f + 0.7f),
			Math::sin(q.z * f + 2.1f) * Math::cos(q.x * f + 4.2f),
			Math::sin(q.x * f + 3.3f) * Math::cos(q.y * f + 5.1f));
}

Vector3 curl_lite(const Vector3 &p_pos, float p_frequency) {
	const float e = 0.05f;
	const Vector3 dx = _curl_potential(p_pos + Vector3(e, 0, 0), p_frequency) - _curl_potential(p_pos - Vector3(e, 0, 0), p_frequency);
	const Vector3 dy = _curl_potential(p_pos + Vector3(0, e, 0), p_frequency) - _curl_potential(p_pos - Vector3(0, e, 0), p_frequency);
	const Vector3 dz = _curl_potential(p_pos + Vector3(0, 0, e), p_frequency) - _curl_potential(p_pos - Vector3(0, 0, e), p_frequency);
	return Vector3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0f * e);
}

float sample_stops_float(const Vector<float> &p_t, const Vector<float> &p_v, float p_u) {
	const int n = MIN(p_t.size(), p_v.size());
	if (n == 0) {
		return 1.0f;
	}
	if (p_u <= p_t[0]) {
		return p_v[0];
	}
	for (int i = 1; i < n; i++) {
		if (p_u <= p_t[i]) {
			const float span = MAX(p_t[i] - p_t[i - 1], 0.00001f);
			return Math::lerp(p_v[i - 1], p_v[i], (p_u - p_t[i - 1]) / span);
		}
	}
	return p_v[n - 1];
}

Color sample_stops_color(const Vector<float> &p_t, const Vector<Color> &p_v, float p_u) {
	const int n = MIN(p_t.size(), p_v.size());
	if (n == 0) {
		return Color(1, 1, 1, 1);
	}
	if (p_u <= p_t[0]) {
		return p_v[0];
	}
	for (int i = 1; i < n; i++) {
		if (p_u <= p_t[i]) {
			const float span = MAX(p_t[i] - p_t[i - 1], 0.00001f);
			return p_v[i - 1].lerp(p_v[i], (p_u - p_t[i - 1]) / span);
		}
	}
	return p_v[n - 1];
}

// ---- emitter ---------------------------------------------------------------

void Emitter::init(const String &p_name, const Dictionary &p_definition, uint64_t p_seed) {
	name = p_name;
	cap = MAX((int)_get_float(p_definition, "max_particles", 1000), 1);
	duration = _get_float(p_definition, "duration", 0.0);
	pos.resize_initialized(cap);
	vel.resize_initialized(cap);
	col.resize_initialized(cap);
	base_col.resize_initialized(cap);
	size.resize_initialized(cap);
	base_size.resize_initialized(cap);
	age.resize_initialized(cap);
	life.resize_initialized(cap);
	rng.seed(p_seed);
	noise_seed = (uint32_t)(p_seed ^ (p_seed >> 32));

	if (p_definition.has("attributes") && p_definition["attributes"].get_type() == Variant::DICTIONARY) {
		const Dictionary attrs = p_definition["attributes"];
		for (const Variant &key : attrs.get_key_list()) {
			custom_names.push_back(String(key));
			custom_defaults.push_back((float)_get_float(attrs, String(key), 0.0));
		}
		custom.resize_initialized((uint32_t)custom_names.size() * (uint32_t)cap);
	}
	_parse_modules(p_definition);
}

void Emitter::_parse_modules(const Dictionary &p_definition) {
	if (p_definition.has("events") && p_definition["events"].get_type() == Variant::DICTIONARY) {
		const Dictionary events = p_definition["events"];
		if (events.has("death")) {
			_parse_specs(events["death"], death_events);
		}
	}
	Vector<EventSpec> collision_default;
	if (p_definition.has("events") && p_definition["events"].get_type() == Variant::DICTIONARY) {
		const Dictionary events = p_definition["events"];
		if (events.has("collision")) {
			_parse_specs(events["collision"], collision_default);
		}
	}

	for (int stage = 0; stage < 2; stage++) {
		const String stage_name = stage == 0 ? "spawn" : "update";
		if (!p_definition.has(stage_name) || p_definition[stage_name].get_type() != Variant::ARRAY) {
			continue;
		}
		const Array list = p_definition[stage_name];
		for (int i = 0; i < list.size(); i++) {
			if (list[i].get_type() != Variant::DICTIONARY) {
				continue;
			}
			const Dictionary src = list[i];
			Module m;
			m.type_name = src.has("type") ? String(src["type"]) : String("?");
			m.type = module_type_from_name(m.type_name);
			m.index = i;
			m.key = vformat("%s/%s/%d:%s", name, stage_name, i, m.type_name);
			if (m.type == MODULE_UNKNOWN || (stage == 0) != is_spawn_stage_module(m.type)) {
				continue; // Validation reports these; the runtime simply ignores them.
			}
			switch (m.type) {
				case MODULE_SPAWN_RATE:
					m.f[0] = _get_float(src, "rate", 10.0);
					break;
				case MODULE_SPAWN_BURST:
					m.f[0] = _get_float(src, "time", 0.0);
					m.f[1] = (real_t)(int)_get_float(src, "count", 10);
					break;
				case MODULE_INITIAL_POSITION_SPHERE:
					m.f[0] = _get_float(src, "radius", 1.0);
					m.v0 = _get_vec3(src, "center", Vector3());
					m.flag = _get_bool(src, "surface", false);
					break;
				case MODULE_INITIAL_POSITION_BOX:
					m.v0 = _get_vec3(src, "size", Vector3(1, 1, 1));
					m.v1 = _get_vec3(src, "center", Vector3());
					break;
				case MODULE_INITIAL_POSITION_CONE:
					m.v0 = _get_vec3(src, "axis", Vector3(0, 1, 0));
					m.f[0] = Math::deg_to_rad(_get_float(src, "angle", 30.0));
					m.f[1] = _get_float(src, "height", 1.0);
					m.v1 = _get_vec3(src, "center", Vector3());
					break;
				case MODULE_INITIAL_VELOCITY: {
					m.v0 = _get_vec3(src, "direction", Vector3(0, 1, 0));
					m.f[0] = Math::deg_to_rad(_get_float(src, "spread", 0.0));
					const real_t speed = _get_float(src, "speed", 1.0);
					m.f[1] = _get_float(src, "speed_min", speed);
					m.f[2] = _get_float(src, "speed_max", speed);
					m.f[3] = _get_float(src, "radial", 0.0);
				} break;
				case MODULE_LIFETIME_RANDOM:
					m.f[0] = _get_float(src, "min", 1.0);
					m.f[1] = _get_float(src, "max", 1.0);
					break;
				case MODULE_INITIAL_COLOR:
					m.c0 = _get_color(src, "color", Color(1, 1, 1, 1));
					m.c1 = _get_color(src, "color_b", m.c0);
					break;
				case MODULE_INITIAL_SIZE:
					m.f[0] = _get_float(src, "min", 1.0);
					m.f[1] = _get_float(src, "max", m.f[0]);
					break;
				case MODULE_INITIAL_ATTRIBUTE:
					m.attribute = src.has("attribute") ? String(src["attribute"]) : String();
					m.attribute_slot = custom_names.find(m.attribute);
					m.f[0] = _get_float(src, "min", 0.0);
					m.f[1] = _get_float(src, "max", m.f[0]);
					break;
				case MODULE_GRAVITY:
					m.v0 = _get_vec3(src, "gravity", Vector3(0, -9.81, 0));
					break;
				case MODULE_DRAG:
					m.f[0] = _get_float(src, "drag", 1.0);
					break;
				case MODULE_CURL_NOISE:
					m.f[0] = _get_float(src, "strength", 1.0);
					m.f[1] = _get_float(src, "frequency", 0.5);
					m.v0 = _get_vec3(src, "scroll", Vector3());
					break;
				case MODULE_VORTEX:
					m.v0 = _get_vec3(src, "center", Vector3());
					m.v1 = _get_vec3(src, "axis", Vector3(0, 1, 0)).normalized();
					m.f[0] = _get_float(src, "strength", 1.0);
					m.f[1] = _get_float(src, "pull", 0.0);
					break;
				case MODULE_ATTRACTOR:
					m.v0 = _get_vec3(src, "position", Vector3());
					m.f[0] = _get_float(src, "strength", 5.0);
					m.f[1] = _get_float(src, "radius", 0.0);
					break;
				case MODULE_COLOR_OVER_LIFE:
					_parse_stops(src, m, true);
					break;
				case MODULE_SIZE_OVER_LIFE:
					_parse_stops(src, m, false);
					break;
				case MODULE_COLLIDE_PLANE: {
					m.v0 = _get_vec3(src, "normal", Vector3(0, 1, 0)).normalized();
					m.f[0] = _get_float(src, "offset", 0.0);
					m.f[1] = _get_float(src, "restitution", 0.5);
					m.f[2] = _get_float(src, "friction", 0.0);
					if (src.has("on_event") && src["on_event"].get_type() != Variant::NIL) {
						_parse_specs(src["on_event"], m.events);
					} else {
						m.events = collision_default;
					}
				} break;
				case MODULE_KILL_BELOW_PLANE:
					m.v0 = _get_vec3(src, "normal", Vector3(0, 1, 0)).normalized();
					m.f[0] = _get_float(src, "offset", 0.0);
					break;
				default:
					break;
			}
			if (stage == 0) {
				spawn_mods.push_back(m);
			} else if (is_post_module(m.type)) {
				post_mods.push_back(m);
			} else {
				update_mods.push_back(m);
			}
		}
	}
}

void Emitter::_charge(const String &p_key, uint64_t p_t0) {
	if (!profiling || profile == nullptr) {
		return;
	}
	(*profile)[p_key] += OS::get_singleton()->get_ticks_usec() - p_t0;
}

#define VFX_PROFILE_BEGIN const uint64_t t0 = profiling ? OS::get_singleton()->get_ticks_usec() : 0
#define VFX_PROFILE_END(m_key) \
	if (profiling) {           \
		_charge(m_key, t0);    \
	}

void Emitter::run_update_cpu(double p_dt) {
	const float dt = (float)p_dt;
	for (int i = 0; i < count; i++) {
		age[i] += dt;
	}
	for (const Module &m : update_mods) {
		VFX_PROFILE_BEGIN;
		_update_module(m, p_dt);
		VFX_PROFILE_END(m.key);
	}
	for (int i = 0; i < count; i++) {
		pos[i] += vel[i] * dt;
	}
	for (const Module &m : post_mods) {
		VFX_PROFILE_BEGIN;
		_update_module(m, p_dt);
		VFX_PROFILE_END(m.key);
	}
}

void Emitter::tick(double p_dt) {
	time += p_dt;
	if (count > 0) {
		bool done_on_gpu = false;
		if (gpu != nullptr) {
			VFX_PROFILE_BEGIN;
			done_on_gpu = gpu->step(*this, p_dt);
			VFX_PROFILE_END(name + "/gpu_kernel");
		}
		if (!done_on_gpu) {
			run_update_cpu(p_dt);
		}
		_cull();
	}
	LocalVector<InEvent> pending;
	pending = events_in;
	events_in.clear();
	for (const InEvent &ev : pending) {
		spawn(ev.count, ev.pos, ev.vel);
	}
	for (const Module &m : spawn_mods) {
		if (m.type == MODULE_SPAWN_RATE) {
			VFX_PROFILE_BEGIN;
			if (duration <= 0.0 || time <= duration) {
				accum += (double)m.f[0] * p_dt;
				const int n = (int)Math::floor(accum);
				accum -= (double)n;
				spawn(n, Vector3(), Vector3());
			}
			VFX_PROFILE_END(m.key);
		} else if (m.type == MODULE_SPAWN_BURST) {
			if (!fired.has(m.index) && time >= (double)m.f[0]) {
				fired[m.index] = true;
				spawn((int)m.f[1], Vector3(), Vector3());
			}
		}
	}
}

bool Emitter::spawn_done() const {
	for (const Module &m : spawn_mods) {
		if (m.type == MODULE_SPAWN_RATE && duration <= 0.0) {
			return false;
		}
		if (m.type == MODULE_SPAWN_RATE && time <= duration) {
			return false;
		}
		if (m.type == MODULE_SPAWN_BURST && !fired.has(m.index)) {
			return false;
		}
	}
	return true;
}

bool Emitter::is_finished() const {
	return count == 0 && events_in.is_empty() && spawn_done();
}

void Emitter::queue_event(int p_count, const Vector3 &p_pos, const Vector3 &p_vel) {
	InEvent ev;
	ev.count = p_count;
	ev.pos = p_pos;
	ev.vel = p_vel;
	events_in.push_back(ev);
}

int Emitter::spawn(int p_requested, const Vector3 &p_origin, const Vector3 &p_inherit) {
	int n = MIN(p_requested, cap - count);
	if (budget_left >= 0) {
		n = MIN(n, budget_left);
		budget_left -= MAX(n, 0);
	}
	if (n <= 0) {
		return 0;
	}
	const int start = count;
	count += n;
	total_spawned += n;
	for (int i = start; i < count; i++) {
		pos[i] = p_origin;
		vel[i] = p_inherit;
		col[i] = Color(1, 1, 1, 1);
		size[i] = 1.0f;
		age[i] = 0.0f;
		life[i] = 1.0f;
	}
	for (int k = 0; k < custom_names.size(); k++) {
		const float def = custom_defaults[k];
		for (int i = start; i < count; i++) {
			custom[k * cap + i] = def;
		}
	}
	for (const Module &m : spawn_mods) {
		if (is_emission_module(m.type)) {
			continue;
		}
		VFX_PROFILE_BEGIN;
		_init_module(m, start);
		VFX_PROFILE_END(m.key);
	}
	for (int i = start; i < count; i++) {
		base_col[i] = col[i];
		base_size[i] = size[i];
	}
	return n;
}

void Emitter::_cull() {
	for (int i = count - 1; i >= 0; i--) {
		if (age[i] >= life[i]) {
			_route(death_events, pos[i], vel[i]);
			_remove(i);
		}
	}
}

void Emitter::_remove(int p_index) {
	const int last = count - 1;
	if (p_index != last) {
		pos[p_index] = pos[last];
		vel[p_index] = vel[last];
		col[p_index] = col[last];
		base_col[p_index] = base_col[last];
		size[p_index] = size[last];
		base_size[p_index] = base_size[last];
		age[p_index] = age[last];
		life[p_index] = life[last];
		for (int k = 0; k < custom_names.size(); k++) {
			custom[k * cap + p_index] = custom[k * cap + last];
		}
	}
	count--;
}

void Emitter::_route(const Vector<EventSpec> &p_specs, const Vector3 &p_pos, const Vector3 &p_vel) {
	for (const EventSpec &spec : p_specs) {
		OutEvent ev;
		ev.emitter = spec.emitter;
		ev.count = spec.count;
		ev.pos = p_pos;
		ev.vel = p_vel * spec.inherit_velocity;
		out_events.push_back(ev);
	}
}

void Emitter::route_collision(const Module &p_module, const Vector3 &p_pos, const Vector3 &p_vel) {
	_route(p_module.events, p_pos, p_vel);
}

Vector3 Emitter::_unit_vector() {
	const real_t z = rng.random(-1.0, 1.0);
	const real_t phi = rng.randf() * Math::TAU;
	const real_t r = Math::sqrt(MAX(1.0 - z * z, 0.0));
	return Vector3(r * Math::cos(phi), z, r * Math::sin(phi));
}

Vector3 Emitter::_cone_dir(const Vector3 &p_axis, real_t p_half_angle) {
	const Vector3 a = p_axis.normalized();
	const real_t cos_t = Math::lerp((real_t)Math::cos(p_half_angle), (real_t)1.0, (real_t)rng.randf());
	const real_t sin_t = Math::sqrt(MAX(1.0 - cos_t * cos_t, 0.0));
	const real_t phi = rng.randf() * Math::TAU;
	const Vector3 helper = Math::abs(a.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
	const Vector3 u = a.cross(helper).normalized();
	const Vector3 w = a.cross(u);
	return a * cos_t + (u * Math::cos(phi) + w * Math::sin(phi)) * sin_t;
}

void Emitter::_init_module(const Module &m, int p_start) {
	switch (m.type) {
		case MODULE_INITIAL_POSITION_SPHERE: {
			for (int i = p_start; i < count; i++) {
				const real_t r = m.flag ? m.f[0] : m.f[0] * Math::pow((real_t)rng.randf(), (real_t)(1.0 / 3.0));
				pos[i] += m.v0 + _unit_vector() * r;
			}
		} break;
		case MODULE_INITIAL_POSITION_BOX: {
			for (int i = p_start; i < count; i++) {
				const real_t x = rng.random(-0.5, 0.5) * m.v0.x;
				const real_t y = rng.random(-0.5, 0.5) * m.v0.y;
				const real_t z = rng.random(-0.5, 0.5) * m.v0.z;
				pos[i] += m.v1 + Vector3(x, y, z);
			}
		} break;
		case MODULE_INITIAL_POSITION_CONE: {
			for (int i = p_start; i < count; i++) {
				const Vector3 d = _cone_dir(m.v0, m.f[0]);
				pos[i] += m.v1 + d * (rng.randf() * m.f[1]);
			}
		} break;
		case MODULE_INITIAL_VELOCITY: {
			for (int i = p_start; i < count; i++) {
				const Vector3 d = m.f[0] > 0.0 ? _cone_dir(m.v0, m.f[0]) : m.v0.normalized();
				vel[i] += d * (real_t)rng.random(m.f[1], m.f[2]);
				if (m.f[3] != 0.0) {
					vel[i] += _unit_vector() * m.f[3];
				}
			}
		} break;
		case MODULE_LIFETIME_RANDOM: {
			for (int i = p_start; i < count; i++) {
				life[i] = (float)rng.random(m.f[0], m.f[1]);
			}
		} break;
		case MODULE_INITIAL_COLOR: {
			for (int i = p_start; i < count; i++) {
				col[i] = m.c0.lerp(m.c1, rng.randf());
			}
		} break;
		case MODULE_INITIAL_SIZE: {
			for (int i = p_start; i < count; i++) {
				size[i] = (float)rng.random(m.f[0], m.f[1]);
			}
		} break;
		case MODULE_INITIAL_ATTRIBUTE: {
			if (m.attribute_slot >= 0) {
				float *data = custom.ptr() + m.attribute_slot * cap;
				for (int i = p_start; i < count; i++) {
					data[i] = (float)rng.random(m.f[0], m.f[1]);
				}
			}
		} break;
		default:
			break;
	}
}

Vector3 Emitter::_curl(const Vector3 &p_pos, real_t p_frequency) {
	if (lite_curl) {
		return curl_lite(p_pos, p_frequency);
	}
	const real_t e = 0.05;
	const Vector3 ex(e, 0, 0);
	const Vector3 ey(0, e, 0);
	const Vector3 ez(0, 0, e);
	const real_t f = p_frequency;
	auto pot = [&](const Vector3 &p, const Vector3 &offset) -> real_t {
		return noise3((p + offset) * f, noise_seed);
	};
	const real_t dc_dy = pot(p_pos + ey, OFFSET_C) - pot(p_pos - ey, OFFSET_C);
	const real_t db_dz = pot(p_pos + ez, OFFSET_B) - pot(p_pos - ez, OFFSET_B);
	const real_t da_dz = pot(p_pos + ez, OFFSET_A) - pot(p_pos - ez, OFFSET_A);
	const real_t dc_dx = pot(p_pos + ex, OFFSET_C) - pot(p_pos - ex, OFFSET_C);
	const real_t db_dx = pot(p_pos + ex, OFFSET_B) - pot(p_pos - ex, OFFSET_B);
	const real_t da_dy = pot(p_pos + ey, OFFSET_A) - pot(p_pos - ey, OFFSET_A);
	return Vector3(dc_dy - db_dz, da_dz - dc_dx, db_dx - da_dy) / (2.0 * e);
}

void Emitter::_update_module(const Module &m, double p_dt) {
	const real_t dt = (real_t)p_dt;
	switch (m.type) {
		case MODULE_GRAVITY: {
			const Vector3 step = m.v0 * dt;
			for (int i = 0; i < count; i++) {
				vel[i] += step;
			}
		} break;
		case MODULE_DRAG: {
			const real_t k = Math::exp(-m.f[0] * dt);
			for (int i = 0; i < count; i++) {
				vel[i] *= k;
			}
		} break;
		case MODULE_CURL_NOISE: {
			const Vector3 shift = m.v0 * (real_t)time;
			const real_t scale = m.f[0] * dt;
			for (int i = 0; i < count; i++) {
				vel[i] += _curl(pos[i] + shift, m.f[1]) * scale;
			}
		} break;
		case MODULE_VORTEX: {
			for (int i = 0; i < count; i++) {
				const Vector3 r = pos[i] - m.v0;
				const Vector3 tangent = m.v1.cross(r);
				const real_t len = tangent.length();
				if (len > 0.0001) {
					vel[i] += tangent / len * (m.f[0] * dt);
				}
				if (m.f[1] != 0.0) {
					vel[i] -= (r - m.v1 * r.dot(m.v1)).normalized() * (m.f[1] * dt);
				}
			}
		} break;
		case MODULE_ATTRACTOR: {
			for (int i = 0; i < count; i++) {
				const Vector3 to = m.v0 - pos[i];
				const real_t dist = to.length();
				if (dist < 0.0001 || (m.f[1] > 0.0 && dist > m.f[1])) {
					continue;
				}
				const real_t falloff = m.f[1] <= 0.0 ? 1.0 : 1.0 - dist / m.f[1];
				vel[i] += to / dist * (m.f[0] * falloff * dt);
			}
		} break;
		case MODULE_COLOR_OVER_LIFE: {
			for (int i = 0; i < count; i++) {
				const float u = CLAMP(age[i] / MAX(life[i], 0.0001f), 0.0f, 1.0f);
				const Color c = m.stop_t.is_empty() ? Color(1, 1, 1, 1) : sample_stops_color(m.stop_t, m.stop_c, u);
				col[i] = base_col[i] * c;
			}
		} break;
		case MODULE_SIZE_OVER_LIFE: {
			if (!m.stop_t.is_empty()) {
				for (int i = 0; i < count; i++) {
					const float u = CLAMP(age[i] / MAX(life[i], 0.0001f), 0.0f, 1.0f);
					size[i] = base_size[i] * sample_stops_float(m.stop_t, m.stop_f, u);
				}
			}
		} break;
		case MODULE_COLLIDE_PLANE: {
			const Vector3 &n = m.v0;
			for (int i = 0; i < count; i++) {
				const real_t d = n.dot(pos[i]) - m.f[0];
				const real_t vn = n.dot(vel[i]);
				if (d < 0.0 && vn < 0.0) {
					pos[i] -= n * d;
					const Vector3 normal_v = n * vn;
					const Vector3 tangent_v = (vel[i] - normal_v) * (1.0 - m.f[2]);
					vel[i] = tangent_v - normal_v * m.f[1];
					route_collision(m, pos[i], vel[i]);
				}
			}
		} break;
		case MODULE_KILL_BELOW_PLANE: {
			for (int i = 0; i < count; i++) {
				if (m.v0.dot(pos[i]) - m.f[0] < 0.0) {
					age[i] = life[i] + 1.0f;
				}
			}
		} break;
		default:
			break;
	}
}

#undef VFX_PROFILE_BEGIN
#undef VFX_PROFILE_END

// ---- system ----------------------------------------------------------------

void System::clear() {
	for (Emitter *em : emitters) {
		memdelete(em);
	}
	emitters.clear();
	emitter_index.clear();
	profile.clear();
	time = 0.0;
}

void System::create(const Dictionary &p_asset, int64_t p_seed) {
	clear();
	seed_value = p_seed;
	budget_left = -1;
	Dictionary defs;
	if (p_asset.has("emitters") && p_asset["emitters"].get_type() == Variant::DICTIONARY) {
		defs = p_asset["emitters"];
	} else {
		defs["main"] = p_asset;
	}
	int idx = 0;
	for (const Variant &key : defs.get_key_list()) {
		if (defs[key].get_type() != Variant::DICTIONARY) {
			continue;
		}
		Emitter *em = memnew(Emitter);
		em->profile = &profile;
		em->init(String(key), defs[key], (uint64_t)(p_seed * 1000003 + idx * 7919 + 17));
		emitter_index[em->name] = (int)emitters.size();
		emitters.push_back(em);
		idx++;
	}
}

void System::tick(double p_dt) {
	for (Emitter *em : emitters) {
		em->budget_left = budget_left;
		em->gpu = gpu;
		em->tick(p_dt);
		budget_left = em->budget_left;
		for (const OutEvent &ev : em->out_events) {
			Emitter *target = get_emitter(ev.emitter);
			if (target != nullptr) {
				target->queue_event(ev.count, ev.pos, ev.vel);
			}
		}
		em->out_events.clear();
	}
	time += p_dt;
}

Emitter *System::get_emitter(const String &p_name) const {
	const HashMap<String, int>::ConstIterator it = emitter_index.find(p_name);
	return it ? emitters[it->value] : nullptr;
}

int System::particle_count(const String &p_emitter) const {
	const Emitter *em = get_emitter(p_emitter);
	return em ? em->count : 0;
}

int System::total_particles() const {
	int total = 0;
	for (const Emitter *em : emitters) {
		total += em->count;
	}
	return total;
}

int System::total_capacity() const {
	int total = 0;
	for (const Emitter *em : emitters) {
		total += em->cap;
	}
	return total;
}

bool System::is_finished() const {
	for (const Emitter *em : emitters) {
		if (!em->is_finished()) {
			return false;
		}
	}
	return true;
}

Variant System::attribute(const String &p_emitter, const String &p_attr) const {
	const Emitter *em = get_emitter(p_emitter);
	if (em == nullptr) {
		return Variant();
	}
	if (p_attr == "position" || p_attr == "velocity") {
		PackedVector3Array out;
		out.resize(em->count);
		const LocalVector<Vector3> &src = p_attr == "position" ? em->pos : em->vel;
		for (int i = 0; i < em->count; i++) {
			out.write[i] = src[i];
		}
		return out;
	}
	if (p_attr == "color") {
		PackedColorArray out;
		out.resize(em->count);
		for (int i = 0; i < em->count; i++) {
			out.write[i] = em->col[i];
		}
		return out;
	}
	const float *src = nullptr;
	if (p_attr == "size") {
		src = em->size.ptr();
	} else if (p_attr == "age") {
		src = em->age.ptr();
	} else if (p_attr == "lifetime") {
		src = em->life.ptr();
	} else {
		const int slot = em->custom_names.find(p_attr);
		if (slot >= 0) {
			src = em->custom.ptr() + slot * em->cap;
		}
	}
	if (src == nullptr) {
		return Variant();
	}
	PackedFloat32Array out;
	out.resize(em->count);
	for (int i = 0; i < em->count; i++) {
		out.write[i] = src[i];
	}
	return out;
}

} // namespace VFXSim
