/**************************************************************************/
/*  cgame_flip_fluid.h                                                    */
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

// 2D FLIP/PIC fluid on a MAC (staggered) grid with solid cells and a moving circle obstacle.
//
// Method: Zhu & Bridson, "Animating Sand as a Fluid", SIGGRAPH 2005 (FLIP) and
// Harlow & Welch 1965 (MAC grid / PIC).
// The structure of the step (particle push-apart, particle-to-grid transfer with
// bilinear weights, Gauss-Seidel pressure projection with over-relaxation, density
// based drift compensation, PIC/FLIP blend on the way back) follows Matthias Müller's
// "Ten Minute Physics" tutorial 18 "How to write a FLIP water/fluid simulation",
// https://github.com/matthias-research/pages (MIT License, Copyright (c) 2022
// Matthias Müller). Re-written in C++ with y-up coordinates, interleaved velocity
// storage, destructible walls (set_solid) and an obstacle that is also a particle
// collider. Velocity grid: component 0 = u on left cell faces, component 1 = v on
// bottom cell faces, index = (i * rows + j) * 2 + component.

#include "cgame_fluids_common.h"

#include "core/math/vector2.h"
#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"

class CgameFLIPFluid : public RefCounted {
	GDCLASS(CgameFLIPFluid, RefCounted);

public:
	enum CellType {
		CELL_FLUID = 0,
		CELL_AIR = 1,
		CELL_SOLID = 2,
	};

private:
	int cols = 32;
	int rows = 32;
	real_t cell_size = 0.1;
	real_t inv_cs = 10.0;
	real_t particle_radius = 0.03;

	Vector2 gravity = Vector2(0.0, -9.81);
	real_t flip_ratio = 0.9;
	int pressure_iterations = 40;
	int push_iterations = 2;
	real_t over_relaxation = 1.9;
	bool compensate_drift = true;
	real_t fluid_density = 1000.0;

	bool obstacle_active = false;
	Vector2 obstacle_center;
	real_t obstacle_radius = 0.0;
	Vector2 obstacle_velocity;

	real_t last_divergence_before = 0.0;

	Vector<Vector2> ppos;
	Vector<Vector2> pvel;
	Vector<Vector2> pprev;

	Vector<float> gv;
	Vector<float> gprev;
	Vector<float> gwt;
	Vector<float> s_open;
	Vector<uint8_t> wall;
	Vector<uint8_t> obst;
	Vector<int> cell_type;
	Vector<float> cell_density;
	real_t rest_particle_density = 0.0;

	int pg_cols = 0;
	int pg_rows = 0;
	Vector<int> pg_start;
	Vector<int> pg_items;

	struct Stencil {
		int node[4];
		real_t weight[4];
	};

	void _rebuild_solids();
	void _classify();
	bool _wall_at(const Vector2 &p_pos) const;
	void _integrate(real_t p_dt);
	void _push_apart();
	void _collide(int p_i, Vector2 *r_pos, Vector2 *r_vel, const Vector2 *p_prev) const;
	Stencil _stencil(const Vector2 &p_pos, int p_comp) const;
	void _to_grid();
	void _apply_solid_faces();
	void _update_density();
	void _solve_incompressibility();
	void _from_grid();

protected:
	static void _bind_methods();

public:
	void setup(int p_cols, int p_rows, real_t p_cell_size);

	int particle_count() const { return ppos.size(); }
	Vector<Vector2> particle_positions() const { return ppos; }
	Vector<Vector2> particle_velocities() const { return pvel; }
	void clear_particles();

	Vector2i cell_of(const Vector2 &p_pos) const;
	int cell_type_at(const Vector2i &p_cell) const;
	bool is_wall(const Vector2i &p_cell) const;
	void set_solid(const Vector2i &p_cell, bool p_solid);

	void set_obstacle(const Vector2 &p_center, real_t p_radius, const Vector2 &p_velocity = Vector2());
	void clear_obstacle();

	int add_water_block(const Vector2 &p_lo, const Vector2 &p_hi);

	void step(real_t p_dt);

	real_t divergence_max() const;
	real_t average_height() const;
	real_t kinetic_energy() const;

	// Per-cell classification and particle density (index = i * rows + j).
	Vector<int> get_cell_types() const { return cell_type; }
	Vector<float> get_cell_density() const { return cell_density; }

	CGF_GETTER(int, cols)
	CGF_GETTER(int, rows)
	CGF_GETTER(real_t, cell_size)
	CGF_GETTER(real_t, last_divergence_before)
	CGF_GETTER(bool, obstacle_active)
	CGF_GETTER(Vector2, obstacle_center)
	CGF_GETTER(real_t, obstacle_radius)
	CGF_GETTER(Vector2, obstacle_velocity)
	CGF_ACCESSOR(real_t, particle_radius)
	CGF_ACCESSOR_REF(Vector2, gravity)
	CGF_ACCESSOR(real_t, flip_ratio)
	CGF_ACCESSOR(int, pressure_iterations)
	CGF_ACCESSOR(int, push_iterations)
	CGF_ACCESSOR(real_t, over_relaxation)
	CGF_ACCESSOR(bool, compensate_drift)
	CGF_ACCESSOR(real_t, fluid_density)

	CgameFLIPFluid();
};

VARIANT_ENUM_CAST(CgameFLIPFluid::CellType);
