/**************************************************************************/
/*  vfx_simulation.h                                                      */
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

#include "core/math/color.h"
#include "core/math/random_pcg.h"
#include "core/math/vector3.h"
#include "core/string/ustring.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/templates/rid.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

class VFXGpuKernel;

// Native CPU simulation core of the VFX graph (structure-of-arrays, no scene dependencies).
// Mirrors the GDScript reference implementation module by module; see VFXGraphAsset for the
// asset format.
namespace VFXSim {

enum ModuleType {
	MODULE_SPAWN_RATE,
	MODULE_SPAWN_BURST,
	MODULE_INITIAL_POSITION_SPHERE,
	MODULE_INITIAL_POSITION_BOX,
	MODULE_INITIAL_POSITION_CONE,
	MODULE_INITIAL_VELOCITY,
	MODULE_LIFETIME_RANDOM,
	MODULE_INITIAL_COLOR,
	MODULE_INITIAL_SIZE,
	MODULE_INITIAL_ATTRIBUTE,
	MODULE_GRAVITY,
	MODULE_DRAG,
	MODULE_CURL_NOISE,
	MODULE_VORTEX,
	MODULE_ATTRACTOR,
	MODULE_COLOR_OVER_LIFE,
	MODULE_SIZE_OVER_LIFE,
	MODULE_COLLIDE_PLANE,
	MODULE_KILL_BELOW_PLANE,
	MODULE_UNKNOWN,
};

// Number of baked samples used when a Gradient resource is converted to color stops.
static constexpr int GRADIENT_BAKE_SAMPLES = 32;

// Resolves a module type name ("gravity", ...). Returns MODULE_UNKNOWN for unrecognised names.
ModuleType module_type_from_name(const String &p_name);
bool is_spawn_stage_module(ModuleType p_type);
bool is_update_stage_module(ModuleType p_type);
bool is_post_module(ModuleType p_type);
bool is_emission_module(ModuleType p_type);

struct EventSpec {
	String emitter;
	int count = 1;
	real_t inherit_velocity = 0.0;
};

struct Module {
	ModuleType type = MODULE_UNKNOWN;
	String type_name;
	String key; // "<emitter>/<stage>/<index>:<type>" used for profiling.
	int index = 0; // Index inside the stage list.
	Vector3 v0;
	Vector3 v1;
	Vector3 v2;
	real_t f[6] = {};
	bool flag = false;
	Color c0;
	Color c1;
	String attribute;
	int attribute_slot = -1;
	Vector<float> stop_t;
	Vector<float> stop_f;
	Vector<Color> stop_c;
	Vector<EventSpec> events; // Collision routing (collide_plane only).
	int gpu_slot = -1; // Event slot assigned by the GPU planner.
};

struct OutEvent {
	String emitter;
	int count = 0;
	Vector3 pos;
	Vector3 vel;
};

struct InEvent {
	int count = 0;
	Vector3 pos;
	Vector3 vel;
};

// Value-noise based vector potential used by the CPU curl_noise module.
float noise3(const Vector3 &p_pos, uint32_t p_seed);
// Analytic divergence-free curl shared with the GPU kernel ("curl lite").
Vector3 curl_lite(const Vector3 &p_pos, float p_frequency);
float sample_stops_float(const Vector<float> &p_t, const Vector<float> &p_v, float p_u);
Color sample_stops_color(const Vector<float> &p_t, const Vector<Color> &p_v, float p_u);

struct Emitter {
	String name;
	int cap = 0;
	int count = 0;
	LocalVector<Vector3> pos;
	LocalVector<Vector3> vel;
	LocalVector<Color> col;
	LocalVector<Color> base_col;
	LocalVector<float> size;
	LocalVector<float> base_size;
	LocalVector<float> age;
	LocalVector<float> life;
	Vector<String> custom_names;
	Vector<float> custom_defaults;
	LocalVector<float> custom; // Flat custom attribute storage: slot * cap + index.
	RandomPCG rng;
	uint32_t noise_seed = 0;
	double time = 0.0;
	double accum = 0.0;
	double duration = 0.0;
	HashMap<int, bool> fired;
	LocalVector<InEvent> events_in;
	LocalVector<OutEvent> out_events;
	Vector<EventSpec> death_events;
	LocalVector<Module> spawn_mods;
	LocalVector<Module> update_mods;
	LocalVector<Module> post_mods;
	HashMap<String, uint64_t> *profile = nullptr;
	int budget_left = -1;
	int total_spawned = 0;
	bool profiling = true;
	bool lite_curl = false; // Use the analytic curl shared with the GPU kernel.
	VFXGpuKernel *gpu = nullptr;

	// Device resources owned by the GPU kernel (invalid until built).
	bool gpu_failed = false;
	RID gpu_shader;
	RID gpu_pipeline;
	RID gpu_particle_buffer;
	RID gpu_event_buffer;
	RID gpu_uniform_set;

	void init(const String &p_name, const Dictionary &p_definition, uint64_t p_seed);
	void tick(double p_dt);
	bool spawn_done() const;
	bool is_finished() const;
	void queue_event(int p_count, const Vector3 &p_pos, const Vector3 &p_vel);
	int spawn(int p_requested, const Vector3 &p_origin, const Vector3 &p_inherit);

	// Runs the update/integrate/post stages on the CPU (reference kernel).
	void run_update_cpu(double p_dt);

	void route_collision(const Module &p_module, const Vector3 &p_pos, const Vector3 &p_vel);

private:
	void _charge(const String &p_key, uint64_t p_t0);
	void _parse_modules(const Dictionary &p_definition);
	void _cull();
	void _remove(int p_index);
	void _route(const Vector<EventSpec> &p_specs, const Vector3 &p_pos, const Vector3 &p_vel);
	Vector3 _unit_vector();
	Vector3 _cone_dir(const Vector3 &p_axis, real_t p_half_angle);
	void _init_module(const Module &p_module, int p_start);
	void _update_module(const Module &p_module, double p_dt);
	Vector3 _curl(const Vector3 &p_pos, real_t p_frequency);
};

class System {
public:
	LocalVector<Emitter *> emitters;
	HashMap<String, int> emitter_index;
	HashMap<String, uint64_t> profile;
	double time = 0.0;
	int budget_left = -1;
	int64_t seed_value = 0;
	VFXGpuKernel *gpu = nullptr;

	// asset is {"emitters": {name: emitter_def}} (or a bare emitter definition, named "main").
	void create(const Dictionary &p_asset, int64_t p_seed);
	void clear();
	void tick(double p_dt);
	int particle_count(const String &p_emitter) const;
	int total_particles() const;
	bool is_finished() const;
	int total_capacity() const;
	Emitter *get_emitter(const String &p_name) const;
	Variant attribute(const String &p_emitter, const String &p_attr) const;
	~System() { clear(); }
};

} // namespace VFXSim
