/**************************************************************************/
/*  cgame_sph_fluid.cpp                                                   */
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

#include "cgame_sph_fluid.h"

#include "core/math/math_funcs.h"

CgameSPHFluid::CgameSPHFluid() {
	setup(0.1, Vector3(), Vector3(2.0, 2.0, 2.0));
}

void CgameSPHFluid::setup(real_t p_spacing, const Vector3 &p_bounds_min, const Vector3 &p_bounds_max) {
	ERR_FAIL_COND_MSG(p_spacing <= 0.0, "CgameSPHFluid: spacing must be positive.");
	ERR_FAIL_COND_MSG(p_bounds_max.x <= p_bounds_min.x || p_bounds_max.y <= p_bounds_min.y || p_bounds_max.z <= p_bounds_min.z, "CgameSPHFluid: bounds_max must be larger than bounds_min on every axis.");
	spacing = p_spacing;
	kernel_radius = 2.0 * p_spacing;
	bounds_min = p_bounds_min;
	bounds_max = p_bounds_max;
	wall_margin = 0.02 * p_spacing;
	particle_mass = BASE_DENSITY * p_spacing * p_spacing * p_spacing;
	h2 = kernel_radius * kernel_radius;
	const double h9 = Math::pow((double)kernel_radius, 9.0);
	const double h6 = Math::pow((double)kernel_radius, 6.0);
	poly6_coef = real_t(315.0 / (64.0 * Math::PI * h9));
	spiky_coef = real_t(45.0 / (Math::PI * h6));
	const real_t dq = 0.2 * kernel_radius;
	const real_t dq_t = h2 - dq * dq;
	dq_w = poly6_coef * dq_t * dq_t * dq_t;
	gx = int(Math::ceil((bounds_max.x - bounds_min.x) / kernel_radius)) + 1;
	gy = int(Math::ceil((bounds_max.y - bounds_min.y) / kernel_radius)) + 1;
	gz = int(Math::ceil((bounds_max.z - bounds_min.z) / kernel_radius)) + 1;
	clear_particles();
	ob_center.clear();
	ob_next.clear();
	ob_radius.clear();
	ob_vel.clear();
	ob_mass.clear();
	ob_impulse.clear();
	_calibrate_rest_density();
}

// Rest density is the density a particle has inside a perfect lattice of the chosen spacing.
void CgameSPHFluid::_calibrate_rest_density() {
	double acc = 0.0;
	const int reach = int(Math::ceil(kernel_radius / spacing));
	for (int ix = -reach; ix <= reach; ix++) {
		for (int iy = -reach; iy <= reach; iy++) {
			for (int iz = -reach; iz <= reach; iz++) {
				const double d2 = double(ix * ix + iy * iy + iz * iz) * spacing * spacing;
				if (d2 < h2) {
					const double t = h2 - d2;
					acc += t * t * t;
				}
			}
		}
	}
	rest_density = real_t(particle_mass * poly6_coef * acc);
}

void CgameSPHFluid::add_particle(const Vector3 &p_pos, const Vector3 &p_vel) {
	pos.push_back(p_pos);
	vel.push_back(p_vel);
	pred.push_back(p_pos);
	dens.push_back(rest_density);
	lam.push_back(0.0);
	omega.push_back(Vector3());
}

// Fills the axis-aligned box [lo, hi] with a cubic lattice; returns the number added.
int CgameSPHFluid::add_block(const Vector3 &p_lo, const Vector3 &p_hi) {
	int added = 0;
	const int nx = int(Math::floor((p_hi.x - p_lo.x) / spacing + 0.001)) + 1;
	const int ny = int(Math::floor((p_hi.y - p_lo.y) / spacing + 0.001)) + 1;
	const int nz = int(Math::floor((p_hi.z - p_lo.z) / spacing + 0.001)) + 1;
	for (int ix = 0; ix < nx; ix++) {
		for (int iy = 0; iy < ny; iy++) {
			for (int iz = 0; iz < nz; iz++) {
				add_particle(p_lo + Vector3(ix, iy, iz) * spacing);
				added++;
			}
		}
	}
	return added;
}

void CgameSPHFluid::clear_particles() {
	pos.clear();
	vel.clear();
	pred.clear();
	dens.clear();
	lam.clear();
	omega.clear();
}

real_t CgameSPHFluid::average_density() const {
	const int n = dens.size();
	if (n == 0) {
		return 0.0;
	}
	const float *d = dens.ptr();
	double acc = 0.0;
	for (int i = 0; i < n; i++) {
		acc += d[i];
	}
	return real_t(acc / double(n));
}

// Adds a sphere obstacle. mass <= 0 makes it kinematic (velocity never changes);
// otherwise fluid impulses change its velocity (two-way coupling). Returns its index.
int CgameSPHFluid::add_sphere_obstacle(const Vector3 &p_center, real_t p_radius, const Vector3 &p_velocity, real_t p_mass) {
	ob_center.push_back(p_center);
	ob_next.push_back(p_center);
	ob_radius.push_back(p_radius);
	ob_vel.push_back(p_velocity);
	ob_mass.push_back(p_mass);
	ob_impulse.push_back(Vector3());
	return ob_center.size() - 1;
}

Vector3 CgameSPHFluid::obstacle_position(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, ob_center.size(), Vector3());
	return ob_center[p_index];
}

Vector3 CgameSPHFluid::obstacle_velocity(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, ob_vel.size(), Vector3());
	return ob_vel[p_index];
}

real_t CgameSPHFluid::kinetic_energy() const {
	double acc = 0.0;
	const Vector3 *v = vel.ptr();
	for (int i = 0; i < vel.size(); i++) {
		acc += 0.5 * particle_mass * v[i].length_squared();
	}
	return real_t(acc);
}

Vector3 CgameSPHFluid::total_momentum() const {
	Vector3 acc;
	const Vector3 *v = vel.ptr();
	for (int i = 0; i < vel.size(); i++) {
		acc += v[i];
	}
	return acc * particle_mass;
}

void CgameSPHFluid::step(real_t p_dt, int p_iterations) {
	const int count = pos.size();
	if (count == 0 || p_dt <= 0.0) {
		return;
	}
	const int ob_n = ob_center.size();
	{
		Vector3 *oc = ob_center.ptrw();
		Vector3 *on = ob_next.ptrw();
		const Vector3 *ov = ob_vel.ptr();
		Vector3 *oi = ob_impulse.ptrw();
		for (int k = 0; k < ob_n; k++) {
			on[k] = oc[k] + ov[k] * p_dt;
			oi[k] = Vector3();
		}
	}
	{
		Vector3 *v = vel.ptrw();
		Vector3 *pr = pred.ptrw();
		const Vector3 *p = pos.ptr();
		// Serial: collisions accumulate reaction impulses on shared obstacles.
		for (int i = 0; i < count; i++) {
			v[i] += gravity * p_dt;
			pr[i] = _collide(p[i] + v[i] * p_dt, p_dt);
		}
	}
	_build_neighbors();
	const real_t inv_scale = particle_mass / rest_density;
	Vector<Vector3> delta;
	delta.resize(count);
	for (int it = 0; it < MAX(p_iterations, 1); it++) {
		_solve_lambdas(count, inv_scale);
		Vector3 *dl = delta.ptrw();
		CgameFluids::parallel_for(count, 64, [&](int p_from, int p_to) {
			for (int i = p_from; i < p_to; i++) {
				dl[i] = _position_delta(i, inv_scale);
			}
		});
		Vector3 *pr = pred.ptrw();
		for (int i = 0; i < count; i++) {
			pr[i] = _collide(pr[i] + dl[i], p_dt);
		}
	}
	const real_t inv_dt = 1.0 / p_dt;
	{
		Vector3 *v = vel.ptrw();
		const Vector3 *pr = pred.ptr();
		const Vector3 *p = pos.ptr();
		for (int i = 0; i < count; i++) {
			Vector3 nv = (pr[i] - p[i]) * inv_dt;
			const real_t speed = nv.length();
			if (speed > MAX_SPEED) {
				nv *= MAX_SPEED / speed;
			}
			v[i] = nv;
		}
	}
	_apply_vorticity_and_viscosity(count, p_dt);
	{
		Vector3 *p = pos.ptrw();
		const Vector3 *pr = pred.ptr();
		for (int i = 0; i < count; i++) {
			p[i] = pr[i];
		}
	}
	{
		Vector3 *oc = ob_center.ptrw();
		const Vector3 *on = ob_next.ptr();
		Vector3 *ov = ob_vel.ptrw();
		const float *om = ob_mass.ptr();
		const Vector3 *oi = ob_impulse.ptr();
		for (int k = 0; k < ob_n; k++) {
			if (om[k] > 0.0) {
				ov[k] += oi[k] / om[k];
				if (obstacle_gravity) {
					ov[k] += gravity * p_dt;
				}
			}
			oc[k] = on[k];
		}
	}
}

// --- internals -------------------------------------------------------------

int CgameSPHFluid::_cell_index(const Vector3 &p_pos) const {
	const int cx = CLAMP(int((p_pos.x - bounds_min.x) / kernel_radius), 0, gx - 1);
	const int cy = CLAMP(int((p_pos.y - bounds_min.y) / kernel_radius), 0, gy - 1);
	const int cz = CLAMP(int((p_pos.z - bounds_min.z) / kernel_radius), 0, gz - 1);
	return (cz * gy + cy) * gx + cx;
}

void CgameSPHFluid::_build_neighbors() {
	const int count = pred.size();
	const int cells = gx * gy * gz;
	const Vector3 *pr = pred.ptr();

	grid_start.resize(cells + 1);
	grid_start.fill(0);
	cell_of.resize(count);
	int *gs = grid_start.ptrw();
	int *co = cell_of.ptrw();
	for (int i = 0; i < count; i++) {
		const int c = _cell_index(pr[i]);
		co[i] = c;
		gs[c + 1]++;
	}
	for (int c = 0; c < cells; c++) {
		gs[c + 1] += gs[c];
	}
	grid_items.resize(count);
	int *gi = grid_items.ptrw();
	{
		Vector<int> cursor = grid_start;
		int *cu = cursor.ptrw();
		for (int i = 0; i < count; i++) {
			const int c = co[i];
			gi[cu[c]] = i;
			cu[c]++;
		}
	}

	// Visits every neighbour j of particle i inside the kernel radius, in a fixed
	// (grid) order, so counting and filling passes see identical sequences.
	const real_t h2_local = h2;
	const int gx_l = gx, gy_l = gy, gz_l = gz;
	auto visit = [&](int p_i, auto &&p_fn) {
		const Vector3 pi = pr[p_i];
		const int cell = co[p_i];
		const int cx = cell % gx_l;
		const int cy = (cell / gx_l) % gy_l;
		const int cz = cell / (gx_l * gy_l);
		for (int oz = MAX(cz - 1, 0); oz < MIN(cz + 2, gz_l); oz++) {
			for (int oy = MAX(cy - 1, 0); oy < MIN(cy + 2, gy_l); oy++) {
				for (int ox = MAX(cx - 1, 0); ox < MIN(cx + 2, gx_l); ox++) {
					const int cc = (oz * gy_l + oy) * gx_l + ox;
					for (int e = gs[cc]; e < gs[cc + 1]; e++) {
						const int j = gi[e];
						if (j != p_i && pi.distance_squared_to(pr[j]) < h2_local) {
							p_fn(j);
						}
					}
				}
			}
		}
	};

	nb_start.resize(count + 1);
	int *ns = nb_start.ptrw();
	CgameFluids::parallel_for(count, 128, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			int n = 0;
			visit(i, [&](int) { n++; });
			ns[i + 1] = n;
		}
	});
	ns[0] = 0;
	for (int i = 0; i < count; i++) {
		ns[i + 1] += ns[i];
	}
	nb_idx.resize(ns[count]);
	int *ni = nb_idx.ptrw();
	CgameFluids::parallel_for(count, 128, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			int w = ns[i];
			visit(i, [&](int p_j) { ni[w++] = p_j; });
		}
	});
}

Vector3 CgameSPHFluid::_grad_spiky(const Vector3 &p_d, real_t p_r) const {
	const real_t span = kernel_radius - p_r;
	return p_d * (-spiky_coef * span * span / p_r);
}

void CgameSPHFluid::_solve_lambdas(int p_count, real_t p_inv_scale) {
	const real_t self_t = h2;
	const real_t self_w = poly6_coef * self_t * self_t * self_t;
	const Vector3 *pr = pred.ptr();
	const int *ns = nb_start.ptr();
	const int *ni = nb_idx.ptr();
	float *dn = dens.ptrw();
	float *lm = lam.ptrw();
	CgameFluids::parallel_for(p_count, 64, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			const Vector3 pi = pr[i];
			real_t rho = particle_mass * self_w;
			Vector3 grad_own;
			real_t grad_sq = 0.0;
			for (int e = ns[i]; e < ns[i + 1]; e++) {
				const Vector3 d = pi - pr[ni[e]];
				const real_t r2 = d.length_squared();
				const real_t t = h2 - r2;
				rho += particle_mass * poly6_coef * t * t * t;
				const real_t r = Math::sqrt(r2);
				if (r > 1e-9) {
					const Vector3 g = _grad_spiky(d, r) * p_inv_scale;
					grad_own += g;
					grad_sq += g.length_squared();
				}
			}
			grad_sq += grad_own.length_squared();
			dn[i] = rho;
			real_t c_val = rho / rest_density - 1.0;
			if (c_val < 0.0) {
				c_val *= attraction;
			}
			lm[i] = -c_val / (grad_sq + relaxation);
		}
	});
}

Vector3 CgameSPHFluid::_position_delta(int p_i, real_t p_inv_scale) const {
	const Vector3 *pr = pred.ptr();
	const int *ns = nb_start.ptr();
	const int *ni = nb_idx.ptr();
	const float *lm = lam.ptr();
	const Vector3 pi = pr[p_i];
	Vector3 acc;
	for (int e = ns[p_i]; e < ns[p_i + 1]; e++) {
		const int j = ni[e];
		const Vector3 d = pi - pr[j];
		const real_t r2 = d.length_squared();
		const real_t r = Math::sqrt(r2);
		if (r < 1e-9) {
			continue;
		}
		const real_t t = h2 - r2;
		const real_t w = poly6_coef * t * t * t;
		const real_t ratio = w / dq_w;
		const real_t r4 = ratio * ratio * ratio * ratio;
		const real_t s_corr = -tensile_k * r4;
		acc += _grad_spiky(d, r) * (lm[p_i] + lm[j] + s_corr);
	}
	return acc * p_inv_scale;
}

void CgameSPHFluid::_apply_vorticity_and_viscosity(int p_count, real_t p_dt) {
	const real_t inv_scale = particle_mass / rest_density;
	const Vector3 *pr = pred.ptr();
	const int *ns = nb_start.ptr();
	const int *ni = nb_idx.ptr();
	const float *dn = dens.ptr();
	Vector3 *vl = vel.ptrw();
	Vector3 *om = omega.ptrw();
	const bool use_vorticity = vorticity_epsilon > 0.0;

	Vector<Vector3> corrected;
	corrected.resize(p_count);
	Vector3 *cr = corrected.ptrw();

	if (use_vorticity) {
		CgameFluids::parallel_for(p_count, 64, [&](int p_from, int p_to) {
			for (int i = p_from; i < p_to; i++) {
				Vector3 w_acc;
				for (int e = ns[i]; e < ns[i + 1]; e++) {
					const int j = ni[e];
					const Vector3 d = pr[i] - pr[j];
					const real_t r = d.length();
					if (r > 1e-9) {
						w_acc += (vl[j] - vl[i]).cross(_grad_spiky(d, r)) * inv_scale;
					}
				}
				om[i] = w_acc;
			}
		});
	}
	CgameFluids::parallel_for(p_count, 64, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			Vector3 nv = vl[i];
			Vector3 visc;
			Vector3 eta;
			for (int e = ns[i]; e < ns[i + 1]; e++) {
				const int j = ni[e];
				const Vector3 d = pr[i] - pr[j];
				const real_t r2 = d.length_squared();
				const real_t r = Math::sqrt(r2);
				const real_t t = h2 - r2;
				const real_t w = poly6_coef * t * t * t;
				visc += (vl[j] - vl[i]) * (w * particle_mass / MAX(dn[j], real_t(1e-6)));
				if (use_vorticity && r > 1e-9) {
					eta += _grad_spiky(d, r) * ((om[j].length() - om[i].length()) * inv_scale);
				}
			}
			nv += visc * xsph_c;
			if (use_vorticity && eta.length() > 1e-6) {
				const Vector3 n_dir = eta.normalized();
				nv += n_dir.cross(om[i]) * (vorticity_epsilon * p_dt);
			}
			cr[i] = nv;
		}
	});
	for (int i = 0; i < p_count; i++) {
		vl[i] = cr[i];
	}
}

// Keeps a position inside the box and outside all sphere obstacles; pushes on
// obstacles accumulate the reaction impulse (momentum conservation).
Vector3 CgameSPHFluid::_collide(const Vector3 &p_pos, real_t p_dt) {
	Vector3 out = p_pos.clamp(bounds_min + Vector3(1, 1, 1) * wall_margin, bounds_max - Vector3(1, 1, 1) * wall_margin);
	const int ob_n = ob_center.size();
	if (ob_n == 0) {
		return out;
	}
	const Vector3 *on = ob_next.ptr();
	const float *orad = ob_radius.ptr();
	Vector3 *oi = ob_impulse.ptrw();
	for (int k = 0; k < ob_n; k++) {
		const Vector3 offset = out - on[k];
		const real_t reach = orad[k] + wall_margin;
		const real_t l2 = offset.length_squared();
		if (l2 < reach * reach) {
			const real_t l = Math::sqrt(l2);
			const Vector3 normal = l > 1e-6 ? offset / l : Vector3(0, 1, 0);
			const Vector3 surface = on[k] + normal * reach;
			oi[k] -= (surface - out) * (particle_mass / p_dt);
			out = surface;
		}
	}
	return out;
}

void CgameSPHFluid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "spacing", "bounds_min", "bounds_max"), &CgameSPHFluid::setup);
	ClassDB::bind_method(D_METHOD("add_particle", "position", "velocity"), &CgameSPHFluid::add_particle, DEFVAL(Vector3()));
	ClassDB::bind_method(D_METHOD("add_block", "lo", "hi"), &CgameSPHFluid::add_block);
	ClassDB::bind_method(D_METHOD("clear_particles"), &CgameSPHFluid::clear_particles);
	ClassDB::bind_method(D_METHOD("particle_count"), &CgameSPHFluid::particle_count);
	ClassDB::bind_method(D_METHOD("positions"), &CgameSPHFluid::positions);
	ClassDB::bind_method(D_METHOD("velocities"), &CgameSPHFluid::velocities);
	ClassDB::bind_method(D_METHOD("average_density"), &CgameSPHFluid::average_density);
	ClassDB::bind_method(D_METHOD("add_sphere_obstacle", "center", "radius", "velocity", "mass"), &CgameSPHFluid::add_sphere_obstacle, DEFVAL(Vector3()), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("obstacle_position", "index"), &CgameSPHFluid::obstacle_position);
	ClassDB::bind_method(D_METHOD("obstacle_velocity", "index"), &CgameSPHFluid::obstacle_velocity);
	ClassDB::bind_method(D_METHOD("obstacle_count"), &CgameSPHFluid::obstacle_count);
	ClassDB::bind_method(D_METHOD("kinetic_energy"), &CgameSPHFluid::kinetic_energy);
	ClassDB::bind_method(D_METHOD("total_momentum"), &CgameSPHFluid::total_momentum);
	ClassDB::bind_method(D_METHOD("step", "dt", "iterations"), &CgameSPHFluid::step, DEFVAL(4));

	CGF_BIND_READONLY_PROPERTY(CgameSPHFluid, Variant::FLOAT, spacing)
	CGF_BIND_READONLY_PROPERTY(CgameSPHFluid, Variant::FLOAT, kernel_radius)
	CGF_BIND_READONLY_PROPERTY(CgameSPHFluid, Variant::FLOAT, particle_mass)
	CGF_BIND_READONLY_PROPERTY(CgameSPHFluid, Variant::FLOAT, rest_density)
	CGF_BIND_READONLY_PROPERTY(CgameSPHFluid, Variant::VECTOR3, bounds_min)
	CGF_BIND_READONLY_PROPERTY(CgameSPHFluid, Variant::VECTOR3, bounds_max)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::FLOAT, wall_margin)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::VECTOR3, gravity)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::FLOAT, xsph_c)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::FLOAT, vorticity_epsilon)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::FLOAT, relaxation)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::FLOAT, tensile_k)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::FLOAT, attraction)
	CGF_BIND_PROPERTY(CgameSPHFluid, Variant::BOOL, obstacle_gravity)
}
