/**************************************************************************/
/*  vfx_graph_instance_3d.h                                               */
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

#include "vfx_gpu_kernel.h"
#include "vfx_graph_asset.h"
#include "vfx_simulation.h"

#include "scene/3d/node_3d.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/material.h"

// Plays a VFXGraphAsset: simulates every emitter natively in this node's local space and draws
// each emitter as one MultiMesh of billboard quads submitted straight to the RenderingServer.
class VFXGraphInstance3D : public Node3D {
	GDCLASS(VFXGraphInstance3D, Node3D);

	struct Renderer {
		String emitter;
		RID multimesh;
		RID instance;
		Ref<QuadMesh> mesh;
		Ref<StandardMaterial3D> material;
		Vector<float> buffer;
		int capacity = 0;
	};

	Ref<VFXGraphAsset> asset;
	int64_t random_seed = 1;
	bool one_shot = false;
	bool autostart = true;
	bool use_gpu = false;
	int budget_particles = -1;
	double time_scale = 1.0;
	String budget_category;
	double budget_priority = 1.0;

	VFXSim::System system;
	VFXGpuKernel *gpu = nullptr;
	Vector<Renderer> renderers;
	bool playing = false;
	bool done = false;
	int budget_id = 0;

	void _build_renderers();
	void _free_renderers();
	void _clear_runtime();
	void _upload(Renderer &r_renderer);
	void _update_instances_transform();
	void _update_instances_visibility();
	void _update_instances_scenario();
	bool _request_budget();
	void _release_budget();
	void _on_budget_evicted(int p_id, const String &p_category);
	void _finish();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_asset(const Ref<VFXGraphAsset> &p_asset);
	Ref<VFXGraphAsset> get_asset() const { return asset; }
	void set_random_seed(int64_t p_seed) { random_seed = p_seed; }
	int64_t get_random_seed() const { return random_seed; }
	void set_one_shot(bool p_one_shot) { one_shot = p_one_shot; }
	bool is_one_shot() const { return one_shot; }
	void set_autostart(bool p_autostart) { autostart = p_autostart; }
	bool is_autostart() const { return autostart; }
	void set_use_gpu(bool p_use_gpu) { use_gpu = p_use_gpu; }
	bool is_using_gpu() const { return use_gpu; }
	void set_budget_particles(int p_budget) { budget_particles = p_budget; }
	int get_budget_particles() const { return budget_particles; }
	void set_time_scale(double p_scale) { time_scale = MAX(p_scale, 0.0); }
	double get_time_scale() const { return time_scale; }
	void set_budget_category(const String &p_category) { budget_category = p_category; }
	String get_budget_category() const { return budget_category; }
	void set_budget_priority(double p_priority) { budget_priority = p_priority; }
	double get_budget_priority() const { return budget_priority; }

	// Builds the simulation from the asset and starts playing. Returns false when the asset is
	// missing/invalid or the global budget rejected the effect.
	bool play();
	void stop();
	bool restart() { return play(); }
	// Convenience: wraps the graph dictionary into an asset, applies the seed and plays.
	bool setup(const Dictionary &p_graph, int64_t p_seed);
	// Advances the simulation and refreshes the MultiMeshes (also called each frame while playing).
	void step(double p_delta);

	bool is_playing() const { return playing; }
	bool is_finished() const { return done; }
	int get_particle_count() const { return system.total_particles(); }
	int get_emitter_particle_count(const String &p_emitter) const { return system.particle_count(p_emitter); }
	PackedStringArray get_emitter_names() const;
	Variant get_attribute(const String &p_emitter, const String &p_attribute) const { return system.attribute(p_emitter, p_attribute); }
	// Accumulated microseconds per module ("<emitter>/<stage>/<index>:<type>").
	Dictionary get_profile() const;
	void reset_profile();
	bool is_gpu_active() const;
	String get_gpu_path() const;
	int get_budget_id() const { return budget_id; }
	// Exposes the live simulation (tests, tools).
	VFXSim::System &get_system() { return system; }
	const VFXSim::System &get_system() const { return system; }

	VFXGraphInstance3D();
	~VFXGraphInstance3D();
};
