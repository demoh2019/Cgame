/**************************************************************************/
/*  test_cgame_vfx.h                                                      */
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

#include "../vfx_bindings.h"
#include "../vfx_budget_server.h"
#include "../vfx_gpu_kernel.h"
#include "../vfx_graph_asset.h"
#include "../vfx_graph_instance_3d.h"
#include "../vfx_presets.h"
#include "../vfx_simulation.h"

#include "core/object/callable_mp.h"
#include "scene/resources/gradient.h"
#include "tests/test_macros.h"

namespace TestCgameVFX {

static Dictionary D(std::initializer_list<std::pair<String, Variant>> p_items) {
	Dictionary d;
	for (const std::pair<String, Variant> &item : p_items) {
		d[item.first] = item.second;
	}
	return d;
}

static Array A(std::initializer_list<Variant> p_items) {
	Array a;
	for (const Variant &v : p_items) {
		a.push_back(v);
	}
	return a;
}

static Dictionary life(double p_value) {
	return D({ { "type", "lifetime_random" }, { "min", p_value }, { "max", p_value } });
}

static Dictionary burst(int p_count) {
	return D({ { "type", "spawn_burst" }, { "count", p_count } });
}

// Single-emitter system asset, mirroring the GDScript test helper.
static Dictionary one(const Array &p_spawn, const Array &p_update, const Dictionary &p_extra = Dictionary()) {
	Dictionary em = D({ { "max_particles", 500 }, { "spawn", p_spawn }, { "update", p_update } });
	em.merge(p_extra, true);
	return D({ { "emitters", D({ { "main", em } }) } });
}

static PackedVector3Array positions(const VFXSim::System &p_sys, const String &p_emitter) {
	return p_sys.attribute(p_emitter, "position");
}

static PackedVector3Array velocities(const VFXSim::System &p_sys, const String &p_emitter) {
	return p_sys.attribute(p_emitter, "velocity");
}

class SpawnRecorder : public Object {
	GDCLASS(SpawnRecorder, Object);

public:
	Vector<String> effects;
	Vector<Vector3> positions;
	Vector<Dictionary> params;

	void record(const String &p_effect, const Vector3 &p_pos, const Dictionary &p_params) {
		effects.push_back(p_effect);
		positions.push_back(p_pos);
		params.push_back(p_params);
	}
};

TEST_CASE("[VFX] Spawn rate and burst counts") {
	VFXSim::System sys;
	sys.create(one(A({ D({ { "type", "spawn_rate" }, { "rate", 10.0 } }), life(100.0) }), A({})), 1);
	sys.tick(1.0);
	CHECK(sys.particle_count("main") == 10); // Rate 10/s over 1s.
	sys.tick(0.5);
	CHECK(sys.particle_count("main") == 15); // Fractional accumulation.

	sys.create(one(A({ burst(25), life(100.0) }), A({})), 1);
	sys.tick(0.1);
	sys.tick(0.1);
	CHECK(sys.particle_count("main") == 25); // Burst fires once.

	sys.create(one(A({ D({ { "type", "spawn_burst" }, { "count", 5 }, { "time", 0.25 } }), life(100.0) }), A({})), 1);
	sys.tick(0.1);
	CHECK(sys.particle_count("main") == 0); // Delayed burst waits for its time.
	sys.tick(0.2);
	CHECK(sys.particle_count("main") == 5);

	sys.create(one(A({ D({ { "type", "spawn_rate" }, { "rate", 100.0 } }), life(100.0) }), A({}), D({ { "duration", 0.5 } })), 1);
	for (int i = 0; i < 20; i++) {
		sys.tick(0.1);
	}
	CHECK(sys.particle_count("main") == 50); // Emission stops once the duration elapsed.
}

TEST_CASE("[VFX] Lifetime death and finished state") {
	VFXSim::System sys;
	sys.create(one(A({ burst(5), life(0.5) }), A({})), 1);
	sys.tick(0.1);
	sys.tick(0.3);
	CHECK(sys.particle_count("main") == 5); // Alive before lifetime.
	CHECK_FALSE(sys.is_finished());
	sys.tick(0.3);
	CHECK(sys.particle_count("main") == 0); // Dead after lifetime.
	CHECK(sys.is_finished());
}

TEST_CASE("[VFX] Gravity and drag integration") {
	VFXSim::System sys;
	sys.create(one(A({ burst(1), life(10.0) }), A({ D({ { "type", "gravity" }, { "gravity", Vector3(0, -10, 0) } }) })), 1);
	for (int i = 0; i < 11; i++) {
		sys.tick(0.1);
	}
	PackedVector3Array v = velocities(sys, "main");
	PackedVector3Array p = positions(sys, "main");
	REQUIRE(v.size() == 1);
	CHECK(v[0].y == doctest::Approx(-10.0).epsilon(0.001));
	CHECK(p[0].y == doctest::Approx(-5.5).epsilon(0.001));

	sys.create(one(A({ burst(1), life(10.0), D({ { "type", "initial_velocity" }, { "direction", Vector3(1, 0, 0) }, { "speed", 10.0 } }) }), A({ D({ { "type", "drag" }, { "drag", 1.0 } }) })), 1);
	for (int i = 0; i < 11; i++) {
		sys.tick(0.1);
	}
	v = velocities(sys, "main");
	REQUIRE(v.size() == 1);
	CHECK(v[0].x == doctest::Approx(10.0 * Math::exp(-1.0)).epsilon(0.001)); // Exponential decay.
}

TEST_CASE("[VFX] Over-life curves and gradients") {
	VFXSim::System sys;
	Array color_stops = A({ A({ 0.0, Color(1, 0, 0, 1) }), A({ 1.0, Color(0, 0, 1, 1) }) });
	Array size_stops = A({ A({ 0.0, 1.0 }), A({ 1.0, 3.0 }) });
	sys.create(one(A({ burst(1), life(1.0) }), A({ D({ { "type", "color_over_life" }, { "stops", color_stops } }), D({ { "type", "size_over_life" }, { "stops", size_stops } }) })), 1);
	sys.tick(0.0);
	sys.tick(0.5);
	PackedColorArray c = sys.attribute("main", "color");
	PackedFloat32Array s = sys.attribute("main", "size");
	REQUIRE(c.size() == 1);
	CHECK(c[0].r == doctest::Approx(0.5).epsilon(0.001));
	CHECK(c[0].b == doctest::Approx(0.5).epsilon(0.001));
	CHECK(s[0] == doctest::Approx(2.0).epsilon(0.001));

	Ref<Gradient> gradient;
	gradient.instantiate();
	gradient->set_color(0, Color(0, 0, 0, 1));
	gradient->set_color(1, Color(1, 1, 1, 1));
	sys.create(one(A({ burst(1), life(1.0) }), A({ D({ { "type", "color_over_life" }, { "gradient", gradient } }) })), 1);
	sys.tick(0.0);
	sys.tick(0.5);
	c = sys.attribute("main", "color");
	REQUIRE(c.size() == 1);
	CHECK(c[0].r == doctest::Approx(0.5).epsilon(0.02)); // Gradient resource sampled.
}

TEST_CASE("[VFX] Collision events spawn in the secondary emitter") {
	Dictionary asset = D({ { "emitters", D({ { "spark", D({ { "max_particles", 10 },
														  { "spawn", A({ burst(1), life(5.0), D({ { "type", "initial_position_sphere" }, { "radius", 0.0 }, { "center", Vector3(0, 1, 0) } }), D({ { "type", "initial_velocity" }, { "direction", Vector3(0, -1, 0) }, { "speed", 5.0 } }) }) },
														  { "update", A({ D({ { "type", "collide_plane" }, { "normal", Vector3(0, 1, 0) }, { "offset", 0.0 }, { "restitution", 0.5 }, { "on_event", D({ { "emitter", "puff" }, { "count", 3 } }) } }) }) } }) },
										  { "puff", D({ { "max_particles", 20 }, { "spawn", A({ life(5.0) }) }, { "update", A({}) } }) } }) } });
	VFXSim::System sys;
	sys.create(asset, 3);
	sys.tick(0.1);
	CHECK(sys.particle_count("puff") == 0); // No event before impact.
	sys.tick(0.5);
	PackedVector3Array v = velocities(sys, "spark");
	PackedVector3Array p = positions(sys, "spark");
	REQUIRE(v.size() == 1);
	CHECK(v[0].y == doctest::Approx(2.5).epsilon(0.001)); // Bounce reflects with restitution.
	CHECK(p[0].y == doctest::Approx(0.0).epsilon(0.001)); // Pushed back onto the plane.
	CHECK(sys.particle_count("puff") == 3);

	Dictionary death = D({ { "emitters", D({ { "a", D({ { "max_particles", 10 }, { "spawn", A({ burst(2), life(0.1) }) }, { "update", A({}) }, { "events", D({ { "death", D({ { "emitter", "b" }, { "count", 4 } }) } }) } }) },
											{ "b", D({ { "max_particles", 50 }, { "spawn", A({ life(5.0) }) }, { "update", A({}) } }) } }) } });
	sys.create(death, 3);
	for (int i = 0; i < 4; i++) {
		sys.tick(0.05);
	}
	CHECK(sys.particle_count("b") == 8); // Death events route to emitter b.

	sys.create(one(A({ burst(3), life(10.0), D({ { "type", "initial_position_sphere" }, { "radius", 0.0 }, { "center", Vector3(0, -1, 0) } }) }), A({ D({ { "type", "kill_below_plane" }, { "offset", 0.0 } }) })), 1);
	sys.tick(0.1);
	sys.tick(0.1);
	CHECK(sys.particle_count("main") == 0); // kill_below_plane removes particles.
}

TEST_CASE("[VFX] Collision inherit_velocity and event arrays") {
	Dictionary asset = D({ { "emitters", D({ { "a", D({ { "max_particles", 4 }, { "spawn", A({ burst(1), life(5.0), D({ { "type", "initial_position_sphere" }, { "radius", 0.0 }, { "center", Vector3(0, 1, 0) } }), D({ { "type", "initial_velocity" }, { "direction", Vector3(0, -1, 0) }, { "speed", 4.0 } }) }) },
											   { "update", A({ D({ { "type", "collide_plane" }, { "restitution", 1.0 } }) }) },
											   { "events", D({ { "collision", A({ D({ { "emitter", "b" }, { "count", 1 }, { "inherit_velocity", 0.5 } }), D({ { "emitter", "c" }, { "count", 2 } }) }) } }) } }) },
										   { "b", D({ { "max_particles", 4 }, { "spawn", A({ life(5.0) }) }, { "update", A({}) } }) },
										   { "c", D({ { "max_particles", 4 }, { "spawn", A({ life(5.0) }) }, { "update", A({}) } }) } }) } });
	VFXSim::System sys;
	sys.create(asset, 9);
	sys.tick(0.1);
	sys.tick(0.5);
	CHECK(sys.particle_count("b") == 1);
	CHECK(sys.particle_count("c") == 2); // Emitter-level "collision" events apply to collide_plane.
	PackedVector3Array bv = velocities(sys, "b");
	REQUIRE(bv.size() == 1);
	CHECK(bv[0].y == doctest::Approx(2.0).epsilon(0.001)); // Inherits half of the reflected velocity.
}

TEST_CASE("[VFX] Caps, determinism and custom attributes") {
	VFXSim::System sys;
	sys.create(D({ { "emitters", D({ { "main", D({ { "max_particles", 10 }, { "spawn", A({ burst(100), life(5.0) }) }, { "update", A({}) } }) } }) } }), 1);
	sys.tick(0.1);
	CHECK(sys.particle_count("main") == 10); // max_particles cap.

	Dictionary noisy = one(A({ D({ { "type", "spawn_rate" }, { "rate", 50.0 } }), D({ { "type", "lifetime_random" }, { "min", 1.0 }, { "max", 2.0 } }), D({ { "type", "initial_position_sphere" }, { "radius", 2.0 } }), D({ { "type", "initial_velocity" }, { "speed_min", 1.0 }, { "speed_max", 3.0 }, { "spread", 40.0 } }) }),
			A({ D({ { "type", "curl_noise" }, { "strength", 2.0 } }), D({ { "type", "vortex" }, { "strength", 1.0 } }), D({ { "type", "attractor" }, { "position", Vector3(1, 1, 1) } }), D({ { "type", "gravity" } }) }),
			D({ { "attributes", D({ { "heat", 0.5 } }) } }));
	VFXSim::System s1;
	VFXSim::System s2;
	VFXSim::System s3;
	s1.create(noisy, 42);
	s2.create(noisy, 42);
	s3.create(noisy, 43);
	for (int i = 0; i < 20; i++) {
		s1.tick(0.05);
		s2.tick(0.05);
		s3.tick(0.05);
	}
	CHECK(s1.particle_count("main") > 0);
	CHECK(Variant(positions(s1, "main")) == Variant(positions(s2, "main"))); // Same seed, identical.
	CHECK(Variant(positions(s1, "main")) != Variant(positions(s3, "main"))); // Different seed differs.
	PackedFloat32Array heat = s1.attribute("main", "heat");
	CHECK(heat.size() == s1.particle_count("main"));
	REQUIRE(heat.size() > 0);
	CHECK(heat[0] == doctest::Approx(0.5).epsilon(0.0001));
	CHECK(s1.attribute("main", "missing").get_type() == Variant::NIL);
}

TEST_CASE("[VFX] Per-module profile") {
	Dictionary noisy = one(A({ D({ { "type", "spawn_rate" }, { "rate", 50.0 } }), life(2.0), D({ { "type", "initial_position_sphere" }, { "radius", 2.0 } }), D({ { "type", "initial_velocity" }, { "speed", 1.0 } }) }),
			A({ D({ { "type", "curl_noise" } }), D({ { "type", "vortex" } }), D({ { "type", "attractor" } }), D({ { "type", "gravity" } }) }));
	VFXSim::System sys;
	sys.create(noisy, 5);
	for (int i = 0; i < 10; i++) {
		sys.tick(0.05);
	}
	CHECK(sys.profile.size() >= 6);
	bool has_gravity = false;
	for (const KeyValue<String, uint64_t> &kv : sys.profile) {
		if (kv.key.contains("gravity")) {
			has_gravity = true;
		}
	}
	CHECK(has_gravity);
}

TEST_CASE("[VFX] Budget limits the live particle count") {
	VFXSim::System sys;
	sys.create(one(A({ burst(20), life(5.0) }), A({})), 7);
	sys.budget_left = 5;
	sys.tick(0.1);
	CHECK(sys.particle_count("main") == 5);
	CHECK(sys.budget_left == 0);
}

TEST_CASE("[VFXGraphAsset] Validation") {
	Ref<VFXGraphAsset> good = VFXGraphAsset::create_from_dictionary(VFXPresets::lightning_sparks(3));
	CHECK(good->is_valid());
	CHECK(good->get_emitter_count() == 2);
	CHECK(good->has_emitter("embers"));
	CHECK(good->get_total_max_particles() == 220);

	Ref<VFXGraphAsset> bare = VFXGraphAsset::create_from_dictionary(D({ { "max_particles", 8 }, { "spawn", A({ burst(1) }) } }));
	CHECK(bare->is_valid());
	CHECK(bare->get_emitter_names()[0] == "main");

	CHECK(VFXGraphAsset::validate_graph(D({ { "emitters", Dictionary() } })).size() == 1);
	CHECK(!VFXGraphAsset::validate_graph(one(A({ D({ { "type", "does_not_exist" } }) }), A({}))).is_empty());
	CHECK(!VFXGraphAsset::validate_graph(one(A({ D({ { "type", "gravity" } }) }), A({}))).is_empty()); // Update module in the spawn stage.
	CHECK(!VFXGraphAsset::validate_graph(one(A({ D({ { "type", "spawn_rate" }, { "rate", "fast" } }) }), A({}))).is_empty());
	CHECK(!VFXGraphAsset::validate_graph(one(A({ D({ { "type", "initial_attribute" }, { "attribute", "heat" } }) }), A({}))).is_empty());
	CHECK(VFXGraphAsset::validate_graph(one(A({ D({ { "type", "initial_attribute" }, { "attribute", "heat" } }) }), A({}), D({ { "attributes", D({ { "heat", 1.0 } }) } }))).is_empty());
	CHECK(!VFXGraphAsset::validate_graph(one(A({}), A({ D({ { "type", "color_over_life" }, { "stops", A({ A({ 0.5, Color() }), A({ 0.1, Color() }) }) } }) }))).is_empty()); // Descending stops.
	CHECK(!VFXGraphAsset::validate_graph(one(A({}), A({ D({ { "type", "collide_plane" }, { "on_event", D({ { "emitter", "ghost" } }) } }) }))).is_empty()); // Unknown target.
	CHECK(!VFXGraphAsset::validate_graph(one(A({}), A({}), D({ { "events", D({ { "birth", D({ { "emitter", "main" } }) } }) } }))).is_empty());
	CHECK(VFXGraphAsset::get_module_names().size() == 19);
}

TEST_CASE("[VFXBudgetServer] Tier caps, admission and eviction") {
	VFXBudgetServer *server = memnew(VFXBudgetServer);
	CHECK(server->get_tier() == VFXBudgetServer::TIER_MEDIUM);
	CHECK(server->get_max_effects("combat") == 24);
	CHECK(server->get_max_particles("combat") == 2400);
	server->set_tier(VFXBudgetServer::TIER_LOW);
	CHECK(server->get_max_effects("combat") == 10);
	server->set_tier(VFXBudgetServer::TIER_ULTRA);
	CHECK(server->get_max_effects("combat") == 72);
	CHECK(server->get_max_total_particles() == 18000);
	server->set_tier(VFXBudgetServer::TIER_MEDIUM);

	const Vector3 cam;
	CHECK(server->request_id("ui", 10, 1.0, Vector3(200, 0, 0), cam) == 0); // Too far for the tier.
	CHECK(server->request("ui", 10000, 1.0, cam, cam) == false); // Larger than the category cap.
	int first = 0;
	for (int i = 0; i < 8; i++) {
		const int id = server->request_id("ui", 10, 1.0, cam, cam);
		CHECK(id > 0);
		if (i == 0) {
			first = id;
		}
	}
	CHECK(server->get_active_effects("ui") == 8);
	CHECK(server->get_active_particles("ui") == 80);
	CHECK(server->request("ui", 10, 0.5, cam, cam) == false); // Lower priority cannot evict.
	const int winner = server->request_id("ui", 10, 5.0, cam, cam);
	CHECK(winner > 0);
	CHECK(server->get_active_effects("ui") == 8);
	CHECK_FALSE(server->is_live(first)); // Oldest of the lowest-value effects was evicted.
	CHECK(server->is_live(winner));
	server->release(winner);
	CHECK(server->get_active_effects("ui") == 7);
	const Dictionary stats = server->get_stats();
	CHECK((int)stats["evicted"] == 1);
	CHECK((int)stats["released"] == 1);
	CHECK((int)stats["rejected"] >= 3);
	server->clear();
	CHECK(server->get_active_particles() == 0);

	// A distant effect is worth less than a near one with the same priority.
	CHECK(server->value_of(1.0, Vector3(100, 0, 0), cam) < server->value_of(1.0, Vector3(1, 0, 0), cam));
	memdelete(server);
}

TEST_CASE("[VFXGraphInstance3D] Simulates, caps and finishes one-shot effects") {
	VFXGraphInstance3D *node = memnew(VFXGraphInstance3D);
	CHECK(node->setup(one(A({ burst(12), life(5.0) }), A({})), 7));
	node->step(0.1);
	CHECK(node->get_particle_count() == 12);
	CHECK(node->get_emitter_particle_count("main") == 12);
	CHECK(node->get_emitter_names().size() == 1);
	CHECK(node->is_playing());
	memdelete(node);

	VFXGraphInstance3D *capped = memnew(VFXGraphInstance3D);
	capped->set_budget_particles(5);
	CHECK(capped->setup(one(A({ burst(20), life(5.0) }), A({})), 7));
	capped->step(0.1);
	CHECK(capped->get_particle_count() == 5);
	memdelete(capped);

	VFXGraphInstance3D *shot = memnew(VFXGraphInstance3D);
	shot->set_one_shot(true);
	CHECK(shot->setup(one(A({ burst(3), life(0.2) }), A({})), 7));
	shot->step(0.1);
	CHECK_FALSE(shot->is_finished());
	for (int i = 0; i < 4; i++) {
		shot->step(0.1);
	}
	CHECK(shot->is_finished());
	CHECK(shot->get_particle_count() == 0);
	memdelete(shot);

	VFXGraphInstance3D *invalid = memnew(VFXGraphInstance3D);
	ERR_PRINT_OFF;
	CHECK_FALSE(invalid->play()); // No asset assigned.
	CHECK_FALSE(invalid->setup(one(A({ D({ { "type", "bogus" } }) }), A({})), 1));
	ERR_PRINT_ON;
	memdelete(invalid);
}

TEST_CASE("[VFXGraphInstance3D] Budget server admission") {
	VFXBudgetServer *server = VFXBudgetServer::get_singleton();
	if (server == nullptr) {
		return; // Module singleton not registered in this build configuration.
	}
	server->clear();
	server->set_category_limits("vfx_test", 1, 100);
	server->set_tier(VFXBudgetServer::TIER_MEDIUM);
	VFXGraphInstance3D *a = memnew(VFXGraphInstance3D);
	a->set_budget_category("vfx_test");
	a->set_budget_priority(1.0);
	CHECK(a->setup(one(A({ burst(2), life(5.0) }), A({}), D({ { "max_particles", 40 } })), 1));
	CHECK(a->get_budget_id() > 0);
	CHECK(server->get_active_particles("vfx_test") == 40);

	VFXGraphInstance3D *b = memnew(VFXGraphInstance3D);
	b->set_budget_category("vfx_test");
	b->set_budget_priority(0.1);
	ERR_PRINT_OFF;
	CHECK_FALSE(b->setup(one(A({ burst(2), life(5.0) }), A({}), D({ { "max_particles", 40 } })), 1)); // Rejected: category is full.
	ERR_PRINT_ON;
	CHECK(b->get_budget_id() == 0);

	a->stop();
	CHECK(server->get_active_effects("vfx_test") == 0);
	memdelete(a);
	memdelete(b);
}

TEST_CASE("[VFXGraphInstance3D] GPU request falls back to the CPU kernel") {
	VFXGraphInstance3D *node = memnew(VFXGraphInstance3D);
	node->set_use_gpu(true);
	CHECK(node->setup(one(A({ burst(16), life(5.0) }), A({ D({ { "type", "gravity" } }), D({ { "type", "curl_noise" } }) })), 11));
	for (int i = 0; i < 5; i++) {
		node->step(0.05);
	}
	CHECK(node->get_particle_count() == 16); // Works with or without a compute device.
	CHECK((node->get_gpu_path() == "gpu" || node->get_gpu_path() == "cpu" || node->get_gpu_path() == "none"));
	memdelete(node);
}

TEST_CASE("[VFXGpuKernel] Compute source generation") {
	Dictionary asset = D({ { "emitters", D({ { "spark", D({ { "max_particles", 10 },
														  { "update", A({ D({ { "type", "gravity" }, { "gravity", Vector3(0, -14, 0) } }), D({ { "type", "curl_noise" }, { "strength", 2.0 } }), D({ { "type", "color_over_life" }, { "stops", A({ A({ 0.0, Color(1, 0, 0, 1) }), A({ 1.0, Color(0, 0, 1, 0) }) }) } }), D({ { "type", "collide_plane" }, { "on_event", D({ { "emitter", "puff" } }) } }) }) } }) },
										  { "puff", D({ { "max_particles", 10 } }) } }) } });
	VFXSim::System sys;
	sys.create(asset, 1);
	VFXSim::Emitter *spark = sys.get_emitter("spark");
	REQUIRE(spark != nullptr);
	const String src = VFXGpuKernel::generate_compute_source(*spark);
	CHECK(src.begins_with("#[compute]"));
	CHECK(src.contains("#version 450"));
	CHECK(src.contains("local_size_x = 64"));
	CHECK(src.contains("const uint MAX_PARTICLES = 10u;"));
	CHECK(src.contains("const bool ROUTE_DEATH = false;"));
	CHECK(src.contains("cn_curl"));
	CHECK(src.contains("color_curve_2"));
	CHECK(src.contains("emit_event(1u, p, v);")); // Collision slot 1.
	CHECK(src.contains("v += vec3(0.00000000, -14.00000000, 0.00000000) * dt;"));
	CHECK_FALSE(src.contains("{{"));
	CHECK(VFXGpuKernel::generate_compute_source(*spark, true).contains("const bool ROUTE_DEATH = true;"));

	VFXSim::Emitter *puff = sys.get_emitter("puff");
	REQUIRE(puff != nullptr);
	const String plain = VFXGpuKernel::generate_compute_source(*puff);
	CHECK_FALSE(plain.contains("cn_curl"));
	CHECK_FALSE(plain.contains("emit_event(1u"));

	// The shared analytic curl is divergence free enough to be finite and deterministic.
	const Vector3 a = VFXSim::curl_lite(Vector3(1, 2, 3), 0.5f);
	const Vector3 b = VFXSim::curl_lite(Vector3(1, 2, 3), 0.5f);
	CHECK(a == b);
	CHECK(a.is_finite());
}

TEST_CASE("[VFXPresets] Lightning sparks") {
	CHECK(VFXPresets::get_spark_count(0) == 0);
	CHECK(VFXPresets::get_spark_count(3) == 110);
	CHECK(VFXPresets::get_spark_count(99) == 110);

	Node3D *holder = memnew(Node3D);
	CHECK(VFXPresets::spawn(holder, VFXPresets::lightning_sparks(0), Vector3(), 1) == nullptr); // Performance spawns nothing.
	CHECK(VFXPresets::spawn(nullptr, VFXPresets::lightning_sparks(3), Vector3(), 1) == nullptr);
	CHECK(VFXPresets::spawn(holder, VFXPresets::lightning_sparks(3), Vector3(NAN, 0, 0), 1) == nullptr);
	memdelete(holder);

	VFXSim::System sys;
	sys.create(VFXPresets::lightning_sparks(3), 5);
	sys.tick(0.02);
	CHECK(sys.particle_count("sparks") == 110); // Ultra burst size.
	int embers = 0;
	for (int i = 0; i < 40; i++) {
		sys.tick(0.03);
		embers = MAX(embers, sys.particle_count("embers"));
	}
	CHECK(embers > 0); // Sparks hitting the ground spawn embers.
	const PackedVector3Array p = positions(sys, "sparks");
	bool below = false;
	for (const Vector3 &pos : p) {
		if (pos.y < -0.01f) {
			below = true;
		}
	}
	CHECK_FALSE(below); // Sparks never sink through the ground.

	Node3D *root = memnew(Node3D);
	VFXGraphInstance3D *node = VFXPresets::spawn(root, VFXPresets::lightning_sparks(2), Vector3(3, 1, 4), 9);
	REQUIRE(node != nullptr);
	CHECK(node->get_parent() == root);
	CHECK(node->is_one_shot());
	node->step(0.02);
	CHECK(node->get_emitter_particle_count("sparks") == 70);
	memdelete(root);
}

TEST_CASE("[VFXBindings] Event mapping, sequences and cue events") {
	SpawnRecorder recorder;
	const Callable spawn = callable_mp(&recorder, &SpawnRecorder::record);

	Ref<VFXBindings> bindings;
	bindings.instantiate();
	bindings->register_binding("hit", D({ { "effect", "spark" }, { "offset", Vector3(0, 1, 0) }, { "params", D({ { "size", D({ { "from", "damage" }, { "scale", 0.1 }, { "min", 0.5 }, { "max", 2.0 } }) }, { "tint", Color(1, 0, 0, 1) } }) } }));
	bindings->register_binding("hit", D({ { "effect", "limited" }, { "min_interval", 1.0 } }));
	CHECK(bindings->has_binding("hit"));
	CHECK_FALSE(bindings->has_binding("miss"));
	CHECK(bindings->get_binding_count() == 2);

	const Dictionary event = D({ { "type", "hit" }, { "payload", D({ { "damage", 30.0 } }) }, { "position", Vector3(1, 2, 3) } });
	CHECK(bindings->handle(event, spawn) == 2);
	REQUIRE(recorder.effects.size() == 2);
	CHECK(recorder.effects[0] == "spark");
	CHECK(recorder.positions[0] == Vector3(1, 3, 3));
	CHECK((double)recorder.params[0]["size"] == doctest::Approx(2.0)); // Clamped to max.
	CHECK((Color)recorder.params[0]["tint"] == Color(1, 0, 0, 1));
	CHECK(bindings->handle(event, spawn) == 1); // "limited" is throttled by min_interval.
	bindings->tick(1.5);
	CHECK(bindings->handle(event, spawn) == 2);
	CHECK(bindings->handle(D({ { "type", "unknown" } }), spawn) == 0);

	Dictionary mapped = VFXBindings::map_params(D({ { "a", D({ { "from", "x" }, { "scale", 2.0 }, { "offset", 1.0 } }) }, { "b", D({ { "from", "missing" }, { "default", 7.0 } }) }, { "c", D({ { "value", 3 } }) } }), D({ { "x", 4.0 } }));
	CHECK((double)mapped["a"] == doctest::Approx(9.0));
	CHECK((double)mapped["b"] == doctest::Approx(7.0));
	CHECK((int)mapped["c"] == 3);

	recorder.effects.clear();
	recorder.positions.clear();
	recorder.params.clear();
	bindings->register_sequence("combo", A({ D({ { "t", 0.5 }, { "effect", "second" }, { "offset", Vector3(0, 1, 0) } }), D({ { "t", 0.0 }, { "effect", "first" } }) }));
	bindings->register_binding("combo_start", D({ { "sequence", "combo" } }));
	CHECK(bindings->handle(D({ { "type", "combo_start" }, { "position", Vector3(5, 0, 0) } }), spawn) == 1);
	REQUIRE(recorder.effects.size() == 1);
	CHECK(recorder.effects[0] == "first"); // Entries are sorted by time and t=0 fires immediately.
	CHECK(bindings->get_active_sequence_count() == 1);
	bindings->tick(0.6);
	REQUIRE(recorder.effects.size() == 2);
	CHECK(recorder.effects[1] == "second");
	CHECK(recorder.positions[1] == Vector3(5, 1, 0));
	CHECK(bindings->get_active_sequence_count() == 0);

	recorder.effects.clear();
	recorder.positions.clear();
	recorder.params.clear();
	bindings->register_binding("fx.impact", D({ { "effect", "boom" }, { "params", D({ { "power", D({ { "from", "magnitude" } }) } }) } }));
	const Array cues = A({ D({ { "tag", "fx.impact" }, { "event", "executed" }, { "stacks", 0 }, { "magnitude", 2.5 }, { "priority", 0 }, { "count", 1 } }),
			D({ { "tag", "fx.impact" }, { "event", "updated" }, { "magnitude", 1.0 } }) });
	CHECK(bindings->handle_cue_events(cues, spawn, Vector3(0, 2, 0)) == 1); // "updated" cues are skipped.
	REQUIRE(recorder.effects.size() == 1);
	CHECK(recorder.effects[0] == "boom");
	CHECK(recorder.positions[0] == Vector3(0, 2, 0));
	CHECK((double)recorder.params[0]["power"] == doctest::Approx(2.5));
}

} // namespace TestCgameVFX
