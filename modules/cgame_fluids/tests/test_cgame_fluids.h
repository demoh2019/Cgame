/**************************************************************************/
/*  test_cgame_fluids.h                                                   */
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

// Regression tests mirroring the GDScript suites test_particle_fluids.gd,
// test_smoke_vfx.gd and test_water_simulation.gd.

#include "../cgame_fft_ocean.h"
#include "../cgame_flip_fluid.h"
#include "../cgame_shallow_water.h"
#include "../cgame_smoke_sim.h"
#include "../cgame_sph_fluid.h"

#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestCgameFluids {

static const real_t SPH_DT = 1.0 / 60.0;

static bool _all_finite_in_box(const Vector<Vector3> &p_pos, const Vector3 &p_lo, const Vector3 &p_hi) {
	for (int i = 0; i < p_pos.size(); i++) {
		const Vector3 &p = p_pos[i];
		if (!Math::is_finite(p.x) || !Math::is_finite(p.y) || !Math::is_finite(p.z)) {
			return false;
		}
		if (p.x < p_lo.x || p.y < p_lo.y || p.z < p_lo.z || p.x > p_hi.x || p.y > p_hi.y || p.z > p_hi.z) {
			return false;
		}
	}
	return true;
}

// --- SPH -------------------------------------------------------------------

TEST_CASE("[CgameSPHFluid] Pool stays bounded and settles near rest density") {
	const Vector3 lo;
	const Vector3 hi(0.6, 1.0, 0.6);
	Ref<CgameSPHFluid> fluid;
	fluid.instantiate();
	fluid->setup(0.1, lo, hi);
	const int added = fluid->add_block(Vector3(0.05, 0.35, 0.05), Vector3(0.55, 0.65, 0.55));
	CHECK(fluid->particle_count() == added);
	CHECK(fluid->get_rest_density() > 100.0);
	bool bounded = true;
	for (int i = 0; i < 120; i++) {
		fluid->step(SPH_DT, 3);
		if (!_all_finite_in_box(fluid->positions(), lo, hi)) {
			bounded = false;
			break;
		}
	}
	CHECK_MESSAGE(bounded, "particles stay finite and inside the box");
	const real_t ratio = fluid->average_density() / fluid->get_rest_density();
	CHECK_MESSAGE(ratio > 0.55, "settled density not collapsed");
	CHECK_MESSAGE(ratio < 1.25, "settled density near rest");
	real_t top = 0.0;
	const Vector<Vector3> pos = fluid->positions();
	for (int i = 0; i < pos.size(); i++) {
		top = MAX(top, pos[i].y);
	}
	CHECK_MESSAGE(top < 0.5, "pool slumps instead of floating");
	CHECK_MESSAGE(fluid->kinetic_energy() < 5.0 * fluid->get_particle_mass() * real_t(added), "pool is calm after settling");
}

TEST_CASE("[CgameSPHFluid] Dam break spreads sideways and collapses") {
	const Vector3 lo;
	const Vector3 hi(1.6, 0.8, 0.4);
	Ref<CgameSPHFluid> fluid;
	fluid.instantiate();
	fluid->setup(0.1, lo, hi);
	fluid->add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.35, 0.65, 0.35));
	real_t start_max_x = 0.0;
	{
		const Vector<Vector3> pos = fluid->positions();
		for (int i = 0; i < pos.size(); i++) {
			start_max_x = MAX(start_max_x, pos[i].x);
		}
	}
	for (int i = 0; i < 90; i++) {
		fluid->step(SPH_DT, 3);
	}
	real_t end_max_x = 0.0;
	real_t top = 0.0;
	const Vector<Vector3> pos = fluid->positions();
	for (int i = 0; i < pos.size(); i++) {
		end_max_x = MAX(end_max_x, pos[i].x);
		top = MAX(top, pos[i].y);
	}
	CHECK(_all_finite_in_box(pos, lo, hi));
	CHECK(end_max_x > start_max_x + 0.5);
	CHECK(top < 0.6);
}

TEST_CASE("[CgameSPHFluid] Moving sphere obstacle couples with the fluid") {
	const Vector3 lo;
	const Vector3 hi(0.8, 0.6, 0.4);
	Ref<CgameSPHFluid> fluid;
	fluid.instantiate();
	fluid->setup(0.1, lo, hi);
	fluid->set_vorticity_epsilon(0.05);
	fluid->add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.75, 0.35, 0.35));
	for (int i = 0; i < 25; i++) {
		fluid->step(SPH_DT, 3);
	}
	const int index = fluid->add_sphere_obstacle(Vector3(0.15, 0.13, 0.2), 0.1, Vector3(1.5, 0.0, 0.0), 2.0);
	const real_t momentum_before = fluid->total_momentum().x;
	for (int i = 0; i < 8; i++) {
		fluid->step(SPH_DT, 3);
	}
	CHECK(_all_finite_in_box(fluid->positions(), lo, hi));
	CHECK_MESSAGE(fluid->total_momentum().x > momentum_before + 0.5, "moving obstacle pushes fluid forward");
	CHECK_MESSAGE(fluid->obstacle_velocity(index).x < 1.5 - 0.05, "obstacle loses momentum to the fluid");
	CHECK_MESSAGE(fluid->obstacle_position(index).x > 0.25, "obstacle advanced");
	int inside = 0;
	const Vector3 centre = fluid->obstacle_position(index);
	const Vector<Vector3> pos = fluid->positions();
	for (int i = 0; i < pos.size(); i++) {
		if (pos[i].distance_to(centre) < 0.1 - 0.02) {
			inside++;
		}
	}
	CHECK_MESSAGE(inside == 0, "no particle inside the sphere");
}

TEST_CASE("[CgameSPHFluid] Runs are deterministic with worker threads") {
	Ref<CgameSPHFluid> a;
	Ref<CgameSPHFluid> b;
	a.instantiate();
	b.instantiate();
	a->setup(0.1, Vector3(), Vector3(0.6, 0.6, 0.4));
	b->setup(0.1, Vector3(), Vector3(0.6, 0.6, 0.4));
	a->add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.25, 0.35, 0.25));
	b->add_block(Vector3(0.05, 0.05, 0.05), Vector3(0.25, 0.35, 0.25));
	a->set_vorticity_epsilon(0.05);
	b->set_vorticity_epsilon(0.05);
	for (int i = 0; i < 15; i++) {
		a->step(SPH_DT, 3);
		b->step(SPH_DT, 3);
	}
	CHECK(a->positions() == b->positions());
	CHECK(a->velocities() == b->velocities());
}

// --- FLIP ------------------------------------------------------------------

static Ref<CgameFLIPFluid> _flip_pool(bool p_compensate) {
	Ref<CgameFLIPFluid> sim;
	sim.instantiate();
	sim->setup(22, 22, 0.1);
	sim->set_compensate_drift(p_compensate);
	sim->add_water_block(Vector2(0.2, 0.2), Vector2(1.2, 1.0));
	return sim;
}

TEST_CASE("[CgameFLIPFluid] Projection reduces divergence") {
	Ref<CgameFLIPFluid> sim = _flip_pool(false);
	CHECK(sim->particle_count() > 100);
	for (int i = 0; i < 4; i++) {
		sim->step(1.0 / 60.0);
	}
	const real_t before = sim->get_last_divergence_before();
	const real_t after = sim->divergence_max();
	CHECK_MESSAGE(before > 0.0, "raw transfer leaves divergence");
	CHECK_MESSAGE(after < before * 0.5, "projection reduces divergence");
	CHECK(Math::is_finite(after));
}

TEST_CASE("[CgameFLIPFluid] Water falls and settles into a calm pool") {
	Ref<CgameFLIPFluid> sim = _flip_pool(true);
	const real_t start_height = sim->average_height();
	for (int i = 0; i < 150; i++) {
		sim->step(1.0 / 60.0);
	}
	CHECK(sim->average_height() < start_height - 0.15);
	real_t highest = 0.0;
	real_t lowest = 100.0;
	bool finite = true;
	int inside_wall = 0;
	const Vector<Vector2> pos = sim->particle_positions();
	for (int i = 0; i < pos.size(); i++) {
		highest = MAX(highest, pos[i].y);
		lowest = MIN(lowest, pos[i].y);
		if (!Math::is_finite(pos[i].x) || !Math::is_finite(pos[i].y)) {
			finite = false;
		}
		if (sim->is_wall(sim->cell_of(pos[i]))) {
			inside_wall++;
		}
	}
	CHECK(finite);
	CHECK(lowest < 0.25);
	CHECK(highest < 1.0);
	CHECK(inside_wall == 0);
	CHECK(sim->kinetic_energy() / real_t(sim->particle_count()) < 0.5);
	CHECK(sim->cell_type_at(Vector2i(0, 0)) == CgameFLIPFluid::CELL_SOLID);
	CHECK(sim->cell_type_at(Vector2i(5, 1)) == CgameFLIPFluid::CELL_FLUID);
	CHECK(sim->cell_type_at(Vector2i(5, 19)) == CgameFLIPFluid::CELL_AIR);
}

TEST_CASE("[CgameFLIPFluid] Destructible wall holds water until removed (dam release)") {
	Ref<CgameFLIPFluid> sim;
	sim.instantiate();
	sim->setup(30, 12, 0.1);
	const int wall_x = 15;
	for (int j = 1; j < 11; j++) {
		sim->set_solid(Vector2i(wall_x, j), true);
	}
	CHECK(sim->cell_type_at(Vector2i(wall_x, 5)) == CgameFLIPFluid::CELL_SOLID);
	sim->add_water_block(Vector2(0.2, 0.2), Vector2(1.3, 0.9));
	const real_t wall_right = real_t(wall_x + 1) * 0.1;
	int leaked = 0;
	int in_wall = 0;
	for (int i = 0; i < 120; i++) {
		sim->step(1.0 / 60.0);
		const Vector<Vector2> pos = sim->particle_positions();
		for (int k = 0; k < pos.size(); k++) {
			if (sim->is_wall(sim->cell_of(pos[k]))) {
				in_wall++;
			}
			if (pos[k].x > wall_right) {
				leaked++;
			}
		}
	}
	CHECK_MESSAGE(in_wall == 0, "particles never inside solids");
	CHECK_MESSAGE(leaked == 0, "intact wall holds the water back");
	for (int j = 1; j < 11; j++) {
		sim->set_solid(Vector2i(wall_x, j), false);
	}
	CHECK(sim->cell_type_at(Vector2i(wall_x, 5)) != CgameFLIPFluid::CELL_SOLID);
	for (int i = 0; i < 180; i++) {
		sim->step(1.0 / 60.0);
		const Vector<Vector2> pos = sim->particle_positions();
		for (int k = 0; k < pos.size(); k++) {
			if (sim->is_wall(sim->cell_of(pos[k]))) {
				in_wall++;
			}
		}
	}
	int beyond = 0;
	const Vector<Vector2> pos = sim->particle_positions();
	for (int k = 0; k < pos.size(); k++) {
		if (pos[k].x > wall_right + 0.3) {
			beyond++;
		}
	}
	CHECK_MESSAGE(beyond * 6 > sim->particle_count(), "water flows through the breach");
	CHECK_MESSAGE(in_wall == 0, "no particle inside solids after the breach");
}

TEST_CASE("[CgameFLIPFluid] Obstacle pushes water and is removable") {
	Ref<CgameFLIPFluid> sim;
	sim.instantiate();
	sim->setup(24, 20, 0.1);
	sim->add_water_block(Vector2(0.2, 0.2), Vector2(2.1, 0.7));
	for (int i = 0; i < 60; i++) {
		sim->step(1.0 / 60.0);
	}
	sim->set_obstacle(Vector2(1.2, 1.4), 0.25, Vector2(0.0, -1.5));
	real_t min_gap = 100.0;
	for (int i = 0; i < 28; i++) {
		sim->step(1.0 / 60.0);
		const Vector<Vector2> pos = sim->particle_positions();
		for (int k = 0; k < pos.size(); k++) {
			min_gap = MIN(min_gap, pos[k].distance_to(sim->get_obstacle_center()));
		}
	}
	CHECK_MESSAGE(min_gap >= 0.25 - 0.001, "particles are held outside the circle");
	CHECK(sim->get_obstacle_center().y < 1.4);
	real_t fastest = 0.0;
	const Vector<Vector2> vel = sim->particle_velocities();
	for (int k = 0; k < vel.size(); k++) {
		fastest = MAX(fastest, vel[k].length());
	}
	CHECK_MESSAGE(fastest > 0.3, "plunging obstacle stirs the water");
	sim->clear_obstacle();
	sim->step(1.0 / 60.0);
	CHECK(!sim->get_obstacle_active());
}

TEST_CASE("[CgameFLIPFluid] Runs are deterministic with worker threads") {
	Ref<CgameFLIPFluid> a = _flip_pool(true);
	Ref<CgameFLIPFluid> b = _flip_pool(true);
	for (int i = 0; i < 40; i++) {
		a->step(1.0 / 60.0);
		b->step(1.0 / 60.0);
	}
	CHECK(a->particle_count() == b->particle_count());
	CHECK(a->particle_positions() == b->particle_positions());
	CHECK(a->particle_velocities() == b->particle_velocities());
}

// --- Smoke -----------------------------------------------------------------

TEST_CASE("[CgameSmokeSim] Hot smoke rises") {
	Ref<CgameSmokeSim> sim;
	sim.instantiate();
	sim->setup(14);
	for (int bz = 5; bz < 10; bz++) {
		for (int by = 2; by < 5; by++) {
			for (int bx = 5; bx < 10; bx++) {
				sim->add_source(Vector3i(bx, by, bz), 1.0, 1.0);
			}
		}
	}
	const real_t y0 = sim->density_centroid().y;
	for (int i = 0; i < 25; i++) {
		sim->step(0.05);
	}
	CHECK(sim->density_centroid().y > y0 + 0.5);
	CHECK(sim->is_finite_state());
	CHECK(sim->total_density() > 0.1);
}

TEST_CASE("[CgameSmokeSim] Obstacle slab blocks smoke") {
	Ref<CgameSmokeSim> sim;
	sim.instantiate();
	sim->setup(14);
	for (int x = 0; x < 14; x++) {
		for (int z = 0; z < 14; z++) {
			sim->set_obstacle(Vector3i(x, 8, z), true);
			sim->set_obstacle(Vector3i(x, 9, z), true);
		}
	}
	sim->add_source(Vector3i(7, 4, 7), 2.0, 1.0);
	for (int i = 0; i < 30; i++) {
		sim->add_source(Vector3i(7, 4, 7), 0.2, 0.5);
		sim->step(0.05);
	}
	real_t above = 0.0;
	const Vector<float> dens = sim->get_field(CgameSmokeSim::FIELD_DENSITY);
	for (int z = 0; z < 14; z++) {
		for (int y = 10; y < 14; y++) {
			for (int x = 0; x < 14; x++) {
				above += dens[sim->index(x, y, z)];
			}
		}
	}
	CHECK(above < 0.001 * MAX(sim->total_density(), real_t(1.0)));
	CHECK(sim->total_density() > 0.5);
	CHECK(sim->get_value(CgameSmokeSim::FIELD_DENSITY, Vector3i(3, 8, 3)) == 0.0);
	sim->add_source(Vector3i(3, 8, 3), 5.0);
	CHECK(sim->get_value(CgameSmokeSim::FIELD_DENSITY, Vector3i(3, 8, 3)) == 0.0);
}

TEST_CASE("[CgameSmokeSim] Wind carries smoke downwind without lifting it") {
	Ref<CgameSmokeSim> sim;
	sim.instantiate();
	sim->setup(16);
	sim->set_buoyancy(0.0);
	sim->set_vorticity_strength(0.0);
	sim->set_wind(Vector3(5.0, 0.0, 0.0));
	sim->add_source(Vector3i(4, 8, 8), 2.0);
	const real_t x0 = sim->density_centroid().x;
	for (int i = 0; i < 12; i++) {
		sim->step(0.05);
	}
	CHECK(sim->density_centroid().x > x0 + 1.0);
	CHECK(Math::abs(sim->density_centroid().y - 8.0) < 0.5);
}

TEST_CASE("[CgameSmokeSim] Fire burns fuel, releases heat and smoke, cold fuel stays") {
	Ref<CgameSmokeSim> hot;
	hot.instantiate();
	hot->setup(12);
	hot->add_source(Vector3i(6, 4, 6), 0.0, 0.6, 1.0);
	const real_t fuel0 = hot->total_fuel();
	const real_t heat0 = hot->total_temperature();
	const real_t dens0 = hot->total_density();
	hot->step(0.05);
	CHECK(hot->total_fuel() < fuel0);
	CHECK(hot->total_temperature() > heat0);
	CHECK(hot->total_density() > dens0);
	Ref<CgameSmokeSim> cold;
	cold.instantiate();
	cold->setup(12);
	cold->add_source(Vector3i(6, 4, 6), 0.0, 0.1, 1.0);
	cold->step(0.05);
	CHECK(Math::abs(cold->total_fuel() - 1.0) < 0.03);
	for (int i = 0; i < 30; i++) {
		hot->step(0.05);
	}
	CHECK(hot->is_finite_state());
}

TEST_CASE("[CgameSmokeSim] Projection reduces divergence") {
	Ref<CgameSmokeSim> sim;
	sim.instantiate();
	sim->setup(12);
	for (int z = 0; z < 12; z++) {
		for (int y = 0; y < 12; y++) {
			for (int x = 0; x < 12; x++) {
				sim->set_velocity(Vector3i(x, y, z), Vector3(Math::sin(x * 1.3 + y * 0.7) * 3.0, Math::cos(y * 1.1 + z * 0.9) * 3.0, Math::sin(z * 0.8 + x * 0.5) * 3.0));
			}
		}
	}
	sim->set_jacobi_iterations(40);
	const real_t before = sim->divergence_rms();
	sim->project();
	const real_t after = sim->divergence_rms();
	CHECK(before > 0.1);
	CHECK(after < before * 0.6);
}

TEST_CASE("[CgameSmokeSim] Simulation is deterministic and exports image slices") {
	Ref<CgameSmokeSim> a;
	Ref<CgameSmokeSim> b;
	a.instantiate();
	b.instantiate();
	a->setup(20);
	b->setup(20);
	for (int i = 0; i < 8; i++) {
		a->add_source(Vector3i(10, 3, 10), 1.0, 1.0);
		b->add_source(Vector3i(10, 3, 10), 1.0, 1.0);
		a->step(0.05);
		b->step(0.05);
	}
	CHECK(a->get_field(CgameSmokeSim::FIELD_DENSITY) == b->get_field(CgameSmokeSim::FIELD_DENSITY));
	CHECK(a->get_field(CgameSmokeSim::FIELD_VELOCITY_Y) == b->get_field(CgameSmokeSim::FIELD_VELOCITY_Y));

	TypedArray<Image> slices = a->density_image_slices();
	CHECK(slices.size() == 20);
	Ref<Image> first = slices[0];
	REQUIRE(first.is_valid());
	CHECK(first->get_width() == 20);
	CHECK(first->get_format() == Image::FORMAT_RGF);
}

// --- Shallow water ---------------------------------------------------------

TEST_CASE("[CgameShallowWater] Flat lake stays at rest") {
	Vector<float> flat;
	flat.resize(32 * 32);
	flat.fill(0.0);
	Ref<CgameShallowWater> lake;
	lake.instantiate();
	lake->setup(32, 32, 1.0, flat);
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 32; x++) {
			lake->add_water(Vector2i(x, y), 1.0);
		}
	}
	for (int i = 0; i < 60; i++) {
		lake->step(0.05);
	}
	bool still = true;
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 32; x++) {
			if (Math::abs(lake->depth_at(Vector2i(x, y)) - 1.0) > 1e-4) {
				still = false;
			}
		}
	}
	CHECK(still);
	CHECK(lake->velocity_at(Vector2i(10, 10)).length() < 1e-4);
}

TEST_CASE("[CgameShallowWater] Water flows downhill and conserves volume") {
	Vector<float> slope;
	slope.resize(32 * 32);
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 32; x++) {
			slope.write[y * 32 + x] = real_t(31 - x) * 0.2;
		}
	}
	Ref<CgameShallowWater> basin;
	basin.instantiate();
	basin->setup(32, 32, 1.0, slope);
	for (int y = 12; y < 20; y++) {
		basin->add_water(Vector2i(2, y), 1.0);
	}
	const real_t v0 = basin->total_volume();
	real_t min_depth = 0.0;
	for (int i = 0; i < 200; i++) {
		basin->step(0.05);
		const Vector<float> depth = basin->get_depth();
		for (int k = 0; k < depth.size(); k++) {
			min_depth = MIN(min_depth, real_t(depth[k]));
		}
	}
	CHECK_MESSAGE(min_depth >= 0.0, "depth never negative");
	CHECK_MESSAGE(Math::abs(basin->total_volume() / v0 - 1.0) < 0.001, "volume conserved (closed boundaries)");
	real_t low_side = 0.0;
	real_t start_side = 0.0;
	for (int y = 0; y < 32; y++) {
		for (int x = 20; x < 32; x++) {
			low_side += basin->depth_at(Vector2i(x, y));
		}
		for (int x = 0; x < 6; x++) {
			start_side += basin->depth_at(Vector2i(x, y));
		}
	}
	CHECK(low_side > start_side);
	CHECK(basin->depth_at(Vector2i(0, 15)) < 1.0);
}

TEST_CASE("[CgameShallowWater] Dam break floods the dry side, conserves volume, is deterministic") {
	Vector<float> flat;
	flat.resize(32 * 32);
	flat.fill(0.0);
	Ref<CgameShallowWater> dam;
	Ref<CgameShallowWater> twin;
	dam.instantiate();
	twin.instantiate();
	dam->setup(32, 32, 1.0, flat);
	twin->setup(32, 32, 1.0, flat);
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 16; x++) {
			dam->add_water(Vector2i(x, y), 2.0);
			twin->add_water(Vector2i(x, y), 2.0);
		}
	}
	const real_t dv = dam->total_volume();
	for (int i = 0; i < 80; i++) {
		dam->step(0.05);
		twin->step(0.05);
	}
	CHECK(dam->depth_at(Vector2i(22, 16)) > 0.01);
	CHECK(dam->depth_at(Vector2i(15, 16)) < 2.0);
	CHECK(Math::abs(dam->total_volume() / dv - 1.0) < 0.001);
	CHECK(dam->velocity_at(Vector2i(16, 16)).x > 0.0);
	CHECK(dam->get_depth() == twin->get_depth());
	Ref<Image> img = dam->depth_image();
	REQUIRE(img.is_valid());
	CHECK(img->get_format() == Image::FORMAT_RF);
	CHECK(img->get_width() == 32);
}

// --- FFT ocean ---------------------------------------------------------------

static Ref<CgameFFTOcean> _make_ocean(int64_t p_seed) {
	Ref<CgameFFTOcean> o;
	o.instantiate();
	o->setup(32, 100.0, Vector2(12.0, 5.0), 4.0, p_seed);
	return o;
}

TEST_CASE("[CgameFFTOcean] fft_1d round trip, DC and delta") {
	float re[8] = { 1.0, 2.0, -3.0, 0.5, 4.0, -1.0, 0.0, 2.5 };
	float im[8] = { 0.0, 1.0, 0.5, -2.0, 0.0, 3.0, 1.0, -1.0 };
	const float re0[8] = { 1.0, 2.0, -3.0, 0.5, 4.0, -1.0, 0.0, 2.5 };
	const float im0[8] = { 0.0, 1.0, 0.5, -2.0, 0.0, 3.0, 1.0, -1.0 };
	CgameFFTOcean::fft_1d_inplace(re, im, 8, false);
	CgameFFTOcean::fft_1d_inplace(re, im, 8, true);
	real_t worst = 0.0;
	for (int i = 0; i < 8; i++) {
		worst = MAX(worst, MAX(Math::abs(re[i] - re0[i]), Math::abs(im[i] - im0[i])));
	}
	CHECK_MESSAGE(worst < 1e-4, "forward+inverse restores the signal");

	float cr[8] = { 1, 1, 1, 1, 1, 1, 1, 1 };
	float ci[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
	CgameFFTOcean::fft_1d_inplace(cr, ci, 8, false);
	CHECK(Math::abs(cr[0] - 8.0) < 1e-4);
	real_t rest = 0.0;
	for (int i = 1; i < 8; i++) {
		rest += Math::abs(cr[i]) + Math::abs(ci[i]);
	}
	CHECK_MESSAGE(rest < 1e-4, "constant has no other bins");

	float dr[8] = { 1, 0, 0, 0, 0, 0, 0, 0 };
	float di[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
	CgameFFTOcean::fft_1d_inplace(dr, di, 8, false);
	bool flat = true;
	for (int i = 0; i < 8; i++) {
		if (Math::abs(dr[i] - 1.0) > 1e-4 || Math::abs(di[i]) > 1e-4) {
			flat = false;
		}
	}
	CHECK_MESSAGE(flat, "FFT of a delta is flat");
}

TEST_CASE("[CgameFFTOcean] Ocean is deterministic, real, zero mean and animated") {
	Ref<CgameFFTOcean> a = _make_ocean(7);
	Ref<CgameFFTOcean> b = _make_ocean(7);
	Ref<CgameFFTOcean> c = _make_ocean(8);
	const Vector<float> ha = a->evaluate(1.5);
	const Vector<float> hb = b->evaluate(1.5);
	const Vector<float> hc = c->evaluate(1.5);
	CHECK(ha.size() == 32 * 32);
	CHECK_MESSAGE(ha == hb, "same seed is deterministic");
	CHECK_MESSAGE(ha != hc, "different seed differs");
	bool finite = true;
	double sum = 0.0;
	real_t lo = Math::INF;
	real_t hi = -Math::INF;
	for (int i = 0; i < ha.size(); i++) {
		if (!Math::is_finite(ha[i])) {
			finite = false;
		}
		sum += ha[i];
		lo = MIN(lo, real_t(ha[i]));
		hi = MAX(hi, real_t(ha[i]));
	}
	CHECK(finite);
	CHECK(hi - lo > 0.001);
	CHECK(Math::abs(sum / double(ha.size())) < 0.01);
	CHECK(a->get_last_max_imag() < 1e-3);
	const Vector<float> h2 = a->evaluate(4.0);
	double diff = 0.0;
	for (int i = 0; i < ha.size(); i++) {
		diff += Math::abs(ha[i] - h2[i]);
	}
	CHECK(diff > 0.01);
	Ref<Image> img = a->displacement_image(2.0);
	REQUIRE(img.is_valid());
	CHECK(img->get_width() == 32);
	CHECK(img->get_height() == 32);
	CHECK(img->get_format() == Image::FORMAT_RF);
	// Tileable sampling wraps around the patch.
	CHECK(Math::abs(a->sample_height(ha, Vector2(10.0, 20.0)) - a->sample_height(ha, Vector2(110.0, 120.0))) < 1e-3);
}

} // namespace TestCgameFluids
