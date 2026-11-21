/**************************************************************************/
/*  cgame_smoke_sim.h                                                     */
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

// Volumetric smoke / fire simulation on a small 3D grid.
//
// Algorithm: Jos Stam, "Stable Fluids" (SIGGRAPH 1999) semi-Lagrangian advection and
// pressure projection (Jacobi relaxation); buoyancy and vorticity confinement after
// Fedkiw, Stam & Jensen, "Visual Simulation of Smoke" (SIGGRAPH 2001) and the
// GPU Gems 3 ch.30 (Crane, Llamas, Tariq) description of the same pipeline. Fire is a
// simple fuel -> heat + smoke reaction. Independent implementation written from those
// published papers (the papers describe algorithms, not code); no third-party source
// code is copied.
//
// Units: cells and seconds. Cell centres sit at integer coordinates. Faces of the grid
// are open (zero pressure), obstacle voxels are solid walls.

#include "cgame_fluids_common.h"

#include "core/io/image.h"
#include "core/math/vector3.h"
#include "core/math/vector3i.h"
#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class ImageTexture3D;

class CgameSmokeSim : public RefCounted {
	GDCLASS(CgameSmokeSim, RefCounted);

public:
	enum Field {
		FIELD_DENSITY,
		FIELD_TEMPERATURE,
		FIELD_FUEL,
		FIELD_VELOCITY_X,
		FIELD_VELOCITY_Y,
		FIELD_VELOCITY_Z,
	};

	static constexpr int DEFAULT_SIZE = 24;

private:
	int size = DEFAULT_SIZE;
	int cell_count = 0;
	Vector3 wind;
	real_t wind_drag = 1.5; // How fast velocity relaxes toward wind (1/s).
	real_t buoyancy = 30.0; // Upward acceleration per unit temperature.
	real_t weight = 0.0; // Downward acceleration per unit density.
	real_t vorticity_strength = 2.0;
	real_t cooling = 0.8; // Temperature decay rate (1/s).
	real_t density_decay = 0.05;
	real_t ignition_temperature = 0.4;
	real_t burn_rate = 4.0; // Fraction of fuel burnt per second.
	real_t heat_yield = 2.0; // Temperature released per unit fuel burnt.
	real_t smoke_yield = 1.0; // Density released per unit fuel burnt.
	int jacobi_iterations = 16;
	real_t max_speed = 40.0;

	Vector<float> vx, vy, vz;
	Vector<float> density, temperature, fuel;
	Vector<uint8_t> obstacle;

	Vector<float> s0, s1, s2;
	Vector<float> pressure;
	Vector<float> div_buf;
	Vector<float> ox, oy, oz, om;

	_FORCE_INLINE_ int _idx(int p_x, int p_y, int p_z) const { return p_x + size * (p_y + size * p_z); }
	int _slice_chunk() const;
	Vector<float> *_field_ptr(Field p_field);
	const Vector<float> *_field_ptr(Field p_field) const;

	void _kill_cell(int p_i);
	void _apply_forces(real_t p_dt);
	void _combust(real_t p_dt);
	void _decay(real_t p_dt);
	void _enforce_obstacles();
	void _vorticity_confinement(real_t p_dt);
	float _clamped(const float *p_f, int p_x, int p_y, int p_z) const;
	float _sample(const float *p_f, real_t p_x, real_t p_y, real_t p_z) const;
	void _advect(const Vector<float> &p_src, Vector<float> &r_dst, real_t p_dt);
	float _nvel(const float *p_f, const uint8_t *p_obs, int p_i, int p_x, int p_y, int p_z) const;
	void _compute_divergence();
	double _sum(const Vector<float> &p_f) const;
	Vector<Ref<Image>> _make_slices() const;

protected:
	static void _bind_methods();

public:
	void setup(int p_grid_size);

	int index(int p_x, int p_y, int p_z) const { return _idx(p_x, p_y, p_z); }
	bool in_bounds(const Vector3i &p_cell) const;
	void clear();

	void add_source(const Vector3i &p_cell, real_t p_density, real_t p_temperature = 0.0, real_t p_fuel = 0.0, const Vector3 &p_velocity = Vector3());
	void set_obstacle(const Vector3i &p_cell, bool p_solid);
	bool is_obstacle(const Vector3i &p_cell) const;

	void step(real_t p_dt);
	void project();

	real_t sample(Field p_field, const Vector3 &p_position) const;
	Vector<float> get_field(Field p_field) const;
	real_t get_value(Field p_field, const Vector3i &p_cell) const;
	void set_velocity(const Vector3i &p_cell, const Vector3 &p_velocity);
	Vector3 get_velocity(const Vector3i &p_cell) const;

	real_t divergence_rms();
	real_t total_density() const { return real_t(_sum(density)); }
	real_t total_temperature() const { return real_t(_sum(temperature)); }
	real_t total_fuel() const { return real_t(_sum(fuel)); }
	real_t max_temperature() const;
	Vector3 density_centroid() const;
	bool is_finite_state() const;

	TypedArray<Image> density_image_slices() const;
	Ref<ImageTexture3D> to_image3d() const;
	void update_image3d(const Ref<ImageTexture3D> &p_texture) const;

	CGF_GETTER(int, size)
	CGF_GETTER(int, cell_count)
	CGF_ACCESSOR_REF(Vector3, wind)
	CGF_ACCESSOR(real_t, wind_drag)
	CGF_ACCESSOR(real_t, buoyancy)
	CGF_ACCESSOR(real_t, weight)
	CGF_ACCESSOR(real_t, vorticity_strength)
	CGF_ACCESSOR(real_t, cooling)
	CGF_ACCESSOR(real_t, density_decay)
	CGF_ACCESSOR(real_t, ignition_temperature)
	CGF_ACCESSOR(real_t, burn_rate)
	CGF_ACCESSOR(real_t, heat_yield)
	CGF_ACCESSOR(real_t, smoke_yield)
	CGF_ACCESSOR(int, jacobi_iterations)
	CGF_ACCESSOR(real_t, max_speed)

	CgameSmokeSim();
};

VARIANT_ENUM_CAST(CgameSmokeSim::Field);
