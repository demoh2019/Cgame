/**************************************************************************/
/*  test_cgame_population_lod.h                                           */
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

#pragma once

#include "../cgame_population_lod.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestCgamePopulationLOD {

static Ref<CgamePopulationLOD> make_lod(int p_seed) {
	Ref<CgamePopulationLOD> p;
	p.instantiate();
	p->setup(10, 10, 64.0, p_seed);
	p->set_dwell_time(1.0);
	p->set_max_herd_size(30);
	return p;
}

static Dictionary comp(const String &p_a, int p_na, const String &p_b = String(), int p_nb = 0) {
	Dictionary d;
	d[p_a] = p_na;
	if (!p_b.is_empty()) {
		d[p_b] = p_nb;
	}
	return d;
}

static void seed_herds(const Ref<CgamePopulationLOD> &p) {
	p->add_herd(11, comp("walker", 12, "runner", 3));
	p->add_herd(55, comp("walker", 20));
	p->add_herd(88, comp("walker", 5, "brute", 2));
	p->add_herd(23, comp("runner", 9));
}

static String snapshot(const Ref<CgamePopulationLOD> &p) {
	String s;
	const PackedInt32Array ids = p->herd_ids();
	for (int i = 0; i < ids.size(); i++) {
		const Dictionary h = p->get_herd(ids[i]);
		s += vformat("%d:%d:%d,", ids[i], int(h["region"]), int(h["count"]));
	}
	return s;
}

TEST_CASE("[CgamePopulationLOD] population and composition are conserved across ticks") {
	Ref<CgamePopulationLOD> p = make_lod(7);
	seed_herds(p);
	const int total0 = p->total_population();
	CHECK(total0 == 51);
	p->add_attractor("noise", p->region_center(75), 10.0, 600.0);
	bool conserved = true;
	for (int i = 0; i < 300; i++) {
		p->tick(1.0);
		if (p->total_population() != total0) {
			conserved = false;
			break;
		}
	}
	CHECK(conserved);
	CHECK(int(p->stats()["migrations"]) > 0);
	CHECK(p->composition_total("brute") == 2);
	CHECK(p->composition_total("walker") == 37);
	CHECK(p->composition_total("runner") == 12);
}

TEST_CASE("[CgamePopulationLOD] herds merge and oversized herds split") {
	Ref<CgamePopulationLOD> m = make_lod(3);
	m->add_herd(44, comp("walker", 10));
	m->add_herd(44, comp("walker", 8));
	m->tick(0.1);
	CHECK(m->herd_count() == 1);
	CHECK(m->abstract_count() == 18);

	Ref<CgamePopulationLOD> s = make_lod(3);
	s->add_herd(44, comp("walker", 50, "runner", 20));
	s->tick(0.1);
	CHECK(s->herd_count() >= 2);
	for (int k = 0; k < 200; k++) {
		s->tick(0.5);
	}
	bool ok_size = true;
	const PackedInt32Array ids = s->herd_ids();
	for (int i = 0; i < ids.size(); i++) {
		if (int(s->get_herd(ids[i])["count"]) > s->get_max_herd_size()) {
			ok_size = false;
		}
	}
	CHECK(ok_size);
	CHECK(s->abstract_count() == 70);
	CHECK(s->composition_total("runner") == 20);
}

TEST_CASE("[CgamePopulationLOD] herds migrate toward attractors") {
	Ref<CgamePopulationLOD> a = make_lod(11);
	a->set_randomness(0.2);
	const int hid = a->add_herd(0, comp("walker", 10));
	const Vector2 target = a->region_center(99);
	a->add_attractor("noise", target, 10.0, 2000.0);
	const real_t d0 = a->region_center(0).distance_to(target);
	for (int i = 0; i < 120; i++) {
		a->tick(1.0);
	}
	const Vector2 pos = a->get_herd(hid)["pos"];
	CHECK(pos.distance_to(target) < d0 * 0.5);
	CHECK(a->attraction(99) > a->attraction(0));
	a->set_night(true);
	CHECK(a->is_night());
}

TEST_CASE("[CgamePopulationLOD] same seed gives the same world, other seeds diverge") {
	Ref<CgamePopulationLOD> p1 = make_lod(99);
	Ref<CgamePopulationLOD> p2 = make_lod(99);
	Ref<CgamePopulationLOD> p3 = make_lod(100);
	Ref<CgamePopulationLOD> all[3] = { p1, p2, p3 };
	for (int k = 0; k < 3; k++) {
		seed_herds(all[k]);
		all[k]->add_attractor("loot", Vector2(300, 300), 5.0, 500.0);
		for (int i = 0; i < 60; i++) {
			all[k]->tick(0.5);
		}
	}
	CHECK(snapshot(p1) == snapshot(p2));
	CHECK(snapshot(p1) != snapshot(p3));
}

TEST_CASE("[CgamePopulationLOD] promotion respects distance and budget, demotion restores the herd") {
	Ref<CgamePopulationLOD> pr = make_lod(5);
	pr->set_promote_radius(100.0);
	pr->set_max_concrete_agents(25);
	pr->add_herd(55, comp("walker", 20, "runner", 10));
	PackedVector2Array player;
	player.push_back(pr->region_center(55) + Vector2(30, 0));
	pr->tick(0.01, player);
	const int before = pr->total_population();
	CHECK(pr->promote(0, player).size() == 0);
	const Array specs = pr->promote(55, player);
	CHECK(specs.size() == 25);
	CHECK(pr->total_population() == before);
	CHECK(pr->get_concrete_count() == 25);
	CHECK(pr->herd_region_count(55) == 5);
	CHECK(pr->promote(55, player).size() == 0);
	bool near_ok = true;
	for (int i = 0; i < specs.size(); i++) {
		const Vector2 sp = Dictionary(specs[i])["position"];
		if (sp.distance_to(pr->region_center(55)) > 64.0) {
			near_ok = false;
		}
	}
	CHECK(near_ok);

	Ref<CgamePopulationLOD> far = make_lod(5);
	far->add_herd(55, comp("walker", 5));
	PackedVector2Array far_only;
	far_only.push_back(Vector2(5000, 5000));
	CHECK(far->promote(55, far_only).size() == 0);
	PackedVector2Array at_herd;
	at_herd.push_back(far->region_center(55));
	CHECK(far->regions_near(at_herd).size() == 1);

	Ref<CgamePopulationLOD> d = make_lod(5);
	d->add_herd(55, comp("walker", 14, "runner", 6));
	PackedVector2Array pl;
	pl.push_back(d->region_center(55));
	d->tick(0.01, pl);
	const Array sp = d->promote(55, pl);
	CHECK(sp.size() == 20);
	CHECK(d->abstract_count() == 0);
	d->demote(sp, 55);
	CHECK(d->abstract_count() == 20);
	CHECK(d->get_concrete_count() == 0);
	CHECK(d->composition_total("walker") == 14);
	CHECK(d->composition_total("runner") == 6);
	Array foreign;
	Dictionary foreign_agent;
	foreign_agent["type"] = "walker";
	foreign.push_back(foreign_agent);
	d->demote(foreign, 40);
	CHECK(d->abstract_count() == 21);
	CHECK(d->get_concrete_count() == 0); // Never negative.
}

TEST_CASE("[CgamePopulationLOD] decay and spawner rules are accounted") {
	Ref<CgamePopulationLOD> r = make_lod(2);
	r->add_herd(30, comp("walker", 10));
	r->set_decay(30, 1.0);
	for (int i = 0; i < 6; i++) {
		r->tick(1.0);
	}
	CHECK(r->abstract_count() < 10);
	CHECK(r->abstract_count() + int(r->stats()["decayed"]) == 10);

	Ref<CgamePopulationLOD> sp = make_lod(2);
	sp->add_spawner(12, "walker", 2.0, 6);
	for (int i = 0; i < 20; i++) {
		sp->tick(1.0);
	}
	CHECK(sp->herd_region_count(12) == 6);
}

TEST_CASE("[CgamePopulationLOD] dynamic sources refresh without multiplying signals") {
	Ref<CgamePopulationLOD> p = make_lod(706);
	const Vector2 first = p->region_center(44);
	const Vector2 second = p->region_center(77);
	p->add_attractor("loot", first, 1.0, 20.0);
	p->set_source_attractor("noise", 4, first, 2.0, 100.0, 0.5);
	for (int i = 0; i < 80; i++) {
		p->set_source_attractor("noise", 4, second, 4.0, 90.0, 0.5);
	}
	CHECK(p->active_attractor_count() == 2);
	CHECK(p->attraction(77) > p->attraction(44));
	p->set_source_attractor("noise", 5, first, 1.0, 30.0, 0.5);
	p->set_source_attractor("night", 4, second, 6.0, 30.0, 0.5);
	CHECK(p->active_attractor_count() == 4);
	const real_t day_pull = p->attraction(77);
	p->set_night(true);
	CHECK(p->attraction(77) > day_pull);
	p->set_night(false);
	CHECK(Math::is_equal_approx(p->attraction(77), day_pull));
	p->tick(0.25);
	CHECK(p->active_attractor_count() == 4);
	p->tick(0.26);
	CHECK(p->active_attractor_count() == 1);
	p->set_source_attractor("noise", 4, first, 2.0, 30.0, 0.5);
	CHECK(p->active_attractor_count() == 2);
	p->clear_attractors();
	CHECK(p->active_attractor_count() == 0);
	p->set_source_attractor("noise", 4, second, 1.0, 30.0, 0.5);
	CHECK(p->active_attractor_count() == 1);
	p->setup(10, 10, 64.0, 706);
	CHECK(p->active_attractor_count() == 0);
}

TEST_CASE("[CgamePopulationLOD] localized attraction retains exact full-grid semantics") {
	Ref<CgamePopulationLOD> p;
	p.instantiate();
	p->setup(48, 36, 32.0, 91, Vector2(-400, -300));
	p->set_night(true);
	LocalVector<real_t> reference;
	reference.resize((uint32_t)p->region_count());
	for (uint32_t r = 0; r < reference.size(); r++) {
		reference[r] = 0.0;
	}
	for (int i = 0; i < 48; i++) {
		const Vector2 centre(-600.0 + (i * 173) % 2100, -500.0 + (i * 251) % 1600);
		const real_t radius = 1.0 + (i * 47) % 460;
		const real_t strength = 0.1 + i * 0.17;
		const String kind = i % 7 == 0 ? "night" : "noise";
		const real_t weight = p->get_kind_weight(kind);
		p->add_attractor(kind, centre, strength, radius);
		for (uint32_t r = 0; r < reference.size(); r++) {
			const real_t distance = p->region_center((int)r).distance_to(centre);
			if (distance < radius) {
				reference[r] += strength * weight * (1.0 - distance / radius);
			}
		}
	}
	real_t max_error = 0.0;
	for (uint32_t r = 0; r < reference.size(); r++) {
		max_error = MAX(max_error, Math::abs(p->attraction((int)r) - reference[r]));
	}
	CHECK(max_error < (real_t)0.0001);
}

TEST_CASE("[CgamePopulationLOD] multiple native nests share their regional agent cap") {
	Ref<CgamePopulationLOD> p = make_lod(772);
	// Block all exits so migration cannot change the tested region mid-tick.
	for (int region = 0; region < p->region_count(); region++) {
		if (region != 44) {
			p->set_blocked(region, true);
		}
	}
	p->add_herd(44, comp("walker", 2));
	p->add_spawner(44, "walker", 4.0, 9);
	p->add_spawner(44, "runner", 4.0, 9);
	p->tick(1.0);
	CHECK(p->herd_region_count(44) == 9);
	CHECK(int(p->stats()["spawned"]) == 7);
	p->tick(1.0);
	CHECK(p->herd_region_count(44) <= 9);
}

} // namespace TestCgamePopulationLOD
