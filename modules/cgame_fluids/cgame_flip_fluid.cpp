/**************************************************************************/
/*  cgame_flip_fluid.cpp                                                  */
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

#include "cgame_flip_fluid.h"

#include "core/math/math_funcs.h"

CgameFLIPFluid::CgameFLIPFluid() {
	setup(32, 32, 0.1);
}

void CgameFLIPFluid::setup(int p_cols, int p_rows, real_t p_cell_size) {
	ERR_FAIL_COND_MSG(p_cell_size <= 0.0, "CgameFLIPFluid: cell_size must be positive.");
	cols = MAX(p_cols, 4);
	rows = MAX(p_rows, 4);
	cell_size = p_cell_size;
	inv_cs = 1.0 / p_cell_size;
	particle_radius = 0.3 * p_cell_size;
	const int total = cols * rows;
	ppos.clear();
	pvel.clear();
	pprev.clear();
	gv.resize(total * 2);
	gv.fill(0.0);
	gprev.resize(total * 2);
	gprev.fill(0.0);
	gwt.resize(total * 2);
	gwt.fill(0.0);
	s_open.resize(total);
	s_open.fill(0.0);
	wall.resize(total);
	wall.fill(0);
	obst.resize(total);
	obst.fill(0);
	cell_type.resize(total);
	cell_type.fill(0);
	cell_density.resize(total);
	cell_density.fill(0.0);
	rest_particle_density = 0.0;
	last_divergence_before = 0.0;
	obstacle_active = false;
	uint8_t *w = wall.ptrw();
	for (int i = 0; i < cols; i++) {
		for (int j = 0; j < rows; j++) {
			if (i == 0 || j == 0 || i == cols - 1 || j == rows - 1) {
				w[i * rows + j] = 1;
			}
		}
	}
	const real_t pcs = 2.2 * particle_radius;
	pg_cols = int(real_t(cols) * cell_size / pcs) + 2;
	pg_rows = int(real_t(rows) * cell_size / pcs) + 2;
	_rebuild_solids();
	_classify();
}

// --- public API ------------------------------------------------------------

void CgameFLIPFluid::clear_particles() {
	ppos.clear();
	pvel.clear();
	pprev.clear();
	rest_particle_density = 0.0;
	_classify();
}

Vector2i CgameFLIPFluid::cell_of(const Vector2 &p_pos) const {
	return Vector2i(CLAMP(int(Math::floor(p_pos.x * inv_cs)), 0, cols - 1), CLAMP(int(Math::floor(p_pos.y * inv_cs)), 0, rows - 1));
}

int CgameFLIPFluid::cell_type_at(const Vector2i &p_cell) const {
	if (p_cell.x < 0 || p_cell.y < 0 || p_cell.x >= cols || p_cell.y >= rows) {
		return CELL_SOLID;
	}
	return cell_type[p_cell.x * rows + p_cell.y];
}

bool CgameFLIPFluid::is_wall(const Vector2i &p_cell) const {
	if (p_cell.x < 0 || p_cell.y < 0 || p_cell.x >= cols || p_cell.y >= rows) {
		return true;
	}
	return wall[p_cell.x * rows + p_cell.y] != 0;
}

// Turns a cell into a wall or opens it again (destructible barrier). The outer border is permanent.
void CgameFLIPFluid::set_solid(const Vector2i &p_cell, bool p_solid) {
	if (p_cell.x <= 0 || p_cell.y <= 0 || p_cell.x >= cols - 1 || p_cell.y >= rows - 1) {
		return;
	}
	wall.write[p_cell.x * rows + p_cell.y] = p_solid ? 1 : 0;
	_rebuild_solids();
	_classify();
}

void CgameFLIPFluid::set_obstacle(const Vector2 &p_center, real_t p_radius, const Vector2 &p_velocity) {
	obstacle_active = true;
	obstacle_center = p_center;
	obstacle_radius = p_radius;
	obstacle_velocity = p_velocity;
	_rebuild_solids();
}

void CgameFLIPFluid::clear_obstacle() {
	obstacle_active = false;
	_rebuild_solids();
}

// Fills a box with a hex lattice of particles (skipping walls); returns how many were added.
int CgameFLIPFluid::add_water_block(const Vector2 &p_lo, const Vector2 &p_hi) {
	int added = 0;
	const real_t dxp = 2.0 * particle_radius;
	const real_t dyp = Math::sqrt(3.0) * 0.5 * dxp;
	int row_index = 0;
	real_t y = p_lo.y;
	while (y <= p_hi.y) {
		real_t x = p_lo.x + (row_index % 2 == 1 ? 0.5 * dxp : 0.0);
		while (x <= p_hi.x) {
			const Vector2 p(x, y);
			if (!is_wall(cell_of(p))) {
				ppos.push_back(p);
				pprev.push_back(p);
				pvel.push_back(Vector2());
				added++;
			}
			x += dxp;
		}
		y += dyp;
		row_index++;
	}
	return added;
}

void CgameFLIPFluid::step(real_t p_dt) {
	if (ppos.is_empty() || p_dt <= 0.0) {
		return;
	}
	if (obstacle_active) {
		obstacle_center += obstacle_velocity * p_dt;
		_rebuild_solids();
	}
	_integrate(p_dt);
	_push_apart();
	// Each particle only reads and writes its own state here, so chunks are independent.
	Vector2 *pos_w = ppos.ptrw();
	Vector2 *vel_w = pvel.ptrw();
	const Vector2 *prev_r = pprev.ptr();
	CgameFluids::parallel_for(ppos.size(), 256, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			_collide(i, pos_w, vel_w, prev_r);
		}
	});
	_to_grid();
	_update_density();
	_solve_incompressibility();
	_from_grid();
	_classify();
}

// Largest |divergence| over fluid cells of the current grid velocity.
real_t CgameFLIPFluid::divergence_max() const {
	real_t worst = 0.0;
	const float *g = gv.ptr();
	const int *ct = cell_type.ptr();
	for (int i = 1; i < cols - 1; i++) {
		for (int j = 1; j < rows - 1; j++) {
			const int c = i * rows + j;
			if (ct[c] != CELL_FLUID) {
				continue;
			}
			const real_t div = g[2 * (c + rows)] - g[2 * c] + g[2 * (c + 1) + 1] - g[2 * c + 1];
			worst = MAX(worst, Math::abs(div));
		}
	}
	return worst;
}

real_t CgameFLIPFluid::average_height() const {
	if (ppos.is_empty()) {
		return 0.0;
	}
	double acc = 0.0;
	const Vector2 *p = ppos.ptr();
	for (int i = 0; i < ppos.size(); i++) {
		acc += p[i].y;
	}
	return real_t(acc / double(ppos.size()));
}

real_t CgameFLIPFluid::kinetic_energy() const {
	double acc = 0.0;
	const Vector2 *v = pvel.ptr();
	for (int i = 0; i < pvel.size(); i++) {
		acc += 0.5 * v[i].length_squared();
	}
	return real_t(acc);
}

// --- internals -------------------------------------------------------------

void CgameFLIPFluid::_rebuild_solids() {
	obst.fill(0);
	uint8_t *ob = obst.ptrw();
	if (obstacle_active) {
		const real_t r2 = obstacle_radius * obstacle_radius;
		for (int i = 1; i < cols - 1; i++) {
			for (int j = 1; j < rows - 1; j++) {
				const Vector2 d = Vector2((real_t(i) + 0.5) * cell_size, (real_t(j) + 0.5) * cell_size) - obstacle_center;
				if (d.length_squared() < r2) {
					ob[i * rows + j] = 1;
				}
			}
		}
	}
	float *so = s_open.ptrw();
	const uint8_t *w = wall.ptr();
	for (int c = 0; c < cols * rows; c++) {
		so[c] = (w[c] != 0 || ob[c] != 0) ? 0.0 : 1.0;
	}
}

void CgameFLIPFluid::_classify() {
	Vector<int> counts;
	counts.resize(cols * rows);
	counts.fill(0);
	int *cn = counts.ptrw();
	const Vector2 *p = ppos.ptr();
	for (int q = 0; q < ppos.size(); q++) {
		const Vector2i cell = cell_of(p[q]);
		cn[cell.x * rows + cell.y]++;
	}
	int *ct = cell_type.ptrw();
	const float *so = s_open.ptr();
	for (int c = 0; c < cols * rows; c++) {
		if (so[c] == 0.0) {
			ct[c] = CELL_SOLID;
		} else {
			ct[c] = cn[c] > 0 ? CELL_FLUID : CELL_AIR;
		}
	}
}

bool CgameFLIPFluid::_wall_at(const Vector2 &p_pos) const {
	return is_wall(Vector2i(int(Math::floor(p_pos.x * inv_cs)), int(Math::floor(p_pos.y * inv_cs))));
}

void CgameFLIPFluid::_integrate(real_t p_dt) {
	Vector2 *p = ppos.ptrw();
	Vector2 *v = pvel.ptrw();
	Vector2 *pp = pprev.ptrw();
	for (int i = 0; i < ppos.size(); i++) {
		pp[i] = p[i];
		v[i] += gravity * p_dt;
		p[i] += v[i] * p_dt;
	}
}

// Sequential in-place relaxation (order dependent), therefore intentionally serial.
void CgameFLIPFluid::_push_apart() {
	const int count = ppos.size();
	const real_t pcs = 2.2 * particle_radius;
	const real_t inv_pcs = 1.0 / pcs;
	const real_t min_dist = 2.0 * particle_radius;
	const real_t min_dist2 = min_dist * min_dist;
	const int cells = pg_cols * pg_rows;
	Vector<int> cell_ids;
	cell_ids.resize(count);
	for (int it = 0; it < push_iterations; it++) {
		Vector2 *p = ppos.ptrw();
		pg_start.resize(cells + 1);
		pg_start.fill(0);
		int *ps = pg_start.ptrw();
		int *ci = cell_ids.ptrw();
		for (int i = 0; i < count; i++) {
			const int gx = CLAMP(int(p[i].x * inv_pcs), 0, pg_cols - 1);
			const int gy = CLAMP(int(p[i].y * inv_pcs), 0, pg_rows - 1);
			ci[i] = gx * pg_rows + gy;
			ps[ci[i] + 1]++;
		}
		for (int c = 0; c < cells; c++) {
			ps[c + 1] += ps[c];
		}
		pg_items.resize(count);
		int *pi = pg_items.ptrw();
		Vector<int> cursor = pg_start;
		int *cu = cursor.ptrw();
		for (int i = 0; i < count; i++) {
			pi[cu[ci[i]]] = i;
			cu[ci[i]]++;
		}
		for (int i = 0; i < count; i++) {
			const int gx2 = CLAMP(int(p[i].x * inv_pcs), 0, pg_cols - 1);
			const int gy2 = CLAMP(int(p[i].y * inv_pcs), 0, pg_rows - 1);
			for (int ox = MAX(gx2 - 1, 0); ox < MIN(gx2 + 2, pg_cols); ox++) {
				for (int oy = MAX(gy2 - 1, 0); oy < MIN(gy2 + 2, pg_rows); oy++) {
					const int cc = ox * pg_rows + oy;
					for (int e = ps[cc]; e < ps[cc + 1]; e++) {
						const int j = pi[e];
						if (j <= i) {
							continue;
						}
						const Vector2 d = p[j] - p[i];
						const real_t d2 = d.length_squared();
						if (d2 >= min_dist2 || d2 < 1e-12) {
							continue;
						}
						const real_t dl = Math::sqrt(d2);
						const Vector2 push = d * (0.5 * (min_dist - dl) / dl);
						p[i] -= push;
						p[j] += push;
					}
				}
			}
		}
	}
}

// Keeps particle i out of walls (swept test, so thin walls are never tunnelled), out
// of the obstacle circle, and inside the domain.
void CgameFLIPFluid::_collide(int p_i, Vector2 *r_pos, Vector2 *r_vel, const Vector2 *p_prev) const {
	Vector2 p = r_pos[p_i];
	const Vector2 q = p_prev[p_i];
	Vector2 v = r_vel[p_i];
	const Vector2 travel = p - q;
	const real_t dist = travel.length();
	if (dist > 0.5 * cell_size && !_wall_at(q)) {
		const int steps = int(Math::ceil(dist / (0.5 * cell_size)));
		Vector2 last = q;
		for (int n = 1; n <= steps; n++) {
			const Vector2 sample = q + travel * (real_t(n) / real_t(steps));
			if (_wall_at(sample)) {
				const bool hit_x = _wall_at(Vector2(sample.x, last.y));
				const bool hit_y = _wall_at(Vector2(last.x, sample.y));
				if (hit_x || !hit_y) {
					v.x = 0.0;
				}
				if (hit_y || !hit_x) {
					v.y = 0.0;
				}
				p = last;
				break;
			}
			last = sample;
		}
	}
	if (obstacle_active) {
		const Vector2 off = p - obstacle_center;
		const real_t reach = obstacle_radius + particle_radius;
		const real_t l2 = off.length_squared();
		if (l2 < reach * reach) {
			const real_t l = Math::sqrt(l2);
			const Vector2 normal = l > 1e-6 ? off / l : Vector2(0, 1);
			p = obstacle_center + normal * reach;
			const real_t vn = (v - obstacle_velocity).dot(normal);
			if (vn < 0.0) {
				v -= normal * vn;
			}
		}
	}
	if (_wall_at(p)) {
		const Vector2i cell = cell_of(p);
		real_t best = Math::INF;
		Vector2 target = q;
		const real_t eps = 0.01 * cell_size;
		if (!is_wall(cell + Vector2i(-1, 0))) {
			const real_t dd = p.x - (real_t(cell.x) * cell_size - eps);
			if (dd < best) {
				best = dd;
				target = Vector2(real_t(cell.x) * cell_size - eps, p.y);
			}
		}
		if (!is_wall(cell + Vector2i(1, 0))) {
			const real_t dd2 = (real_t(cell.x + 1) * cell_size + eps) - p.x;
			if (dd2 < best) {
				best = dd2;
				target = Vector2(real_t(cell.x + 1) * cell_size + eps, p.y);
			}
		}
		if (!is_wall(cell + Vector2i(0, -1))) {
			const real_t dd3 = p.y - (real_t(cell.y) * cell_size - eps);
			if (dd3 < best) {
				best = dd3;
				target = Vector2(p.x, real_t(cell.y) * cell_size - eps);
			}
		}
		if (!is_wall(cell + Vector2i(0, 1))) {
			const real_t dd4 = (real_t(cell.y + 1) * cell_size + eps) - p.y;
			if (dd4 < best) {
				best = dd4;
				target = Vector2(p.x, real_t(cell.y + 1) * cell_size + eps);
			}
		}
		if (target.x != p.x) {
			v.x = 0.0;
		}
		if (target.y != p.y) {
			v.y = 0.0;
		}
		p = target;
		if (_wall_at(p)) {
			p = q;
		}
	}
	const real_t margin = 0.01 * cell_size;
	const real_t lo = cell_size + margin;
	const real_t hi_x = real_t(cols - 1) * cell_size - margin;
	const real_t hi_y = real_t(rows - 1) * cell_size - margin;
	if (p.x < lo) {
		p.x = lo;
		v.x = 0.0;
	} else if (p.x > hi_x) {
		p.x = hi_x;
		v.x = 0.0;
	}
	if (p.y < lo) {
		p.y = lo;
		v.y = 0.0;
	} else if (p.y > hi_y) {
		p.y = hi_y;
		v.y = 0.0;
	}
	r_pos[p_i] = p;
	r_vel[p_i] = v;
}

// Shared bilinear stencil: node indices and weights for one velocity component.
CgameFLIPFluid::Stencil CgameFLIPFluid::_stencil(const Vector2 &p_pos, int p_comp) const {
	const real_t half = 0.5 * cell_size;
	const real_t dx = p_comp == 0 ? 0.0 : half;
	const real_t dy = p_comp == 0 ? half : 0.0;
	const real_t px = CLAMP(p_pos.x, cell_size, real_t(cols - 1) * cell_size);
	const real_t py = CLAMP(p_pos.y, cell_size, real_t(rows - 1) * cell_size);
	const int x0 = MIN(int(Math::floor((px - dx) * inv_cs)), cols - 2);
	const real_t tx = ((px - dx) - real_t(x0) * cell_size) * inv_cs;
	const int x1 = MIN(x0 + 1, cols - 2);
	const int y0 = MIN(int(Math::floor((py - dy) * inv_cs)), rows - 2);
	const real_t ty = ((py - dy) - real_t(y0) * cell_size) * inv_cs;
	const int y1 = MIN(y0 + 1, rows - 2);
	const real_t sx = 1.0 - tx;
	const real_t sy = 1.0 - ty;
	Stencil s;
	s.node[0] = x0 * rows + y0;
	s.node[1] = x1 * rows + y0;
	s.node[2] = x1 * rows + y1;
	s.node[3] = x0 * rows + y1;
	s.weight[0] = sx * sy;
	s.weight[1] = tx * sy;
	s.weight[2] = tx * ty;
	s.weight[3] = sx * ty;
	return s;
}

void CgameFLIPFluid::_to_grid() {
	gprev = gv;
	gv.fill(0.0);
	gwt.fill(0.0);
	_classify();
	float *g = gv.ptrw();
	float *gw = gwt.ptrw();
	const Vector2 *v = pvel.ptr();
	const Vector2 *p = ppos.ptr();
	for (int comp = 0; comp < 2; comp++) {
		for (int q = 0; q < ppos.size(); q++) {
			const Stencil st = _stencil(p[q], comp);
			const real_t component = comp == 0 ? v[q].x : v[q].y;
			for (int k = 0; k < 4; k++) {
				g[2 * st.node[k] + comp] += component * st.weight[k];
				gw[2 * st.node[k] + comp] += st.weight[k];
			}
		}
	}
	for (int idx = 0; idx < gv.size(); idx++) {
		if (gw[idx] > 0.0) {
			g[idx] /= gw[idx];
		}
	}
	_apply_solid_faces();
}

// Faces touching a solid cell carry the solid's velocity (0 for walls, obstacle velocity for the circle).
void CgameFLIPFluid::_apply_solid_faces() {
	float *g = gv.ptrw();
	const float *so = s_open.ptr();
	const uint8_t *ob = obst.ptr();
	for (int i = 0; i < cols; i++) {
		for (int j = 0; j < rows; j++) {
			const int c = i * rows + j;
			const bool self_solid = so[c] == 0.0;
			const bool left_solid = i > 0 && so[c - rows] == 0.0;
			if (self_solid || left_solid) {
				const bool is_ob = ob[c] != 0 || (i > 0 && ob[c - rows] != 0);
				g[2 * c] = is_ob ? obstacle_velocity.x : 0.0;
			}
			const bool below_solid = j > 0 && so[c - 1] == 0.0;
			if (self_solid || below_solid) {
				const bool is_ob2 = ob[c] != 0 || (j > 0 && ob[c - 1] != 0);
				g[2 * c + 1] = is_ob2 ? obstacle_velocity.y : 0.0;
			}
		}
	}
}

void CgameFLIPFluid::_update_density() {
	cell_density.fill(0.0);
	float *cd = cell_density.ptrw();
	const Vector2 *pp = ppos.ptr();
	const real_t half = 0.5 * cell_size;
	for (int q = 0; q < ppos.size(); q++) {
		const real_t px = CLAMP(pp[q].x, cell_size, real_t(cols - 1) * cell_size);
		const real_t py = CLAMP(pp[q].y, cell_size, real_t(rows - 1) * cell_size);
		const int x0 = CLAMP(int(Math::floor((px - half) * inv_cs)), 0, cols - 2);
		const real_t tx = ((px - half) - real_t(x0) * cell_size) * inv_cs;
		const int x1 = MIN(x0 + 1, cols - 2);
		const int y0 = CLAMP(int(Math::floor((py - half) * inv_cs)), 0, rows - 2);
		const real_t ty = ((py - half) - real_t(y0) * cell_size) * inv_cs;
		const int y1 = MIN(y0 + 1, rows - 2);
		const real_t sx = 1.0 - tx;
		const real_t sy = 1.0 - ty;
		cd[x0 * rows + y0] += sx * sy;
		cd[x1 * rows + y0] += tx * sy;
		cd[x1 * rows + y1] += tx * ty;
		cd[x0 * rows + y1] += sx * ty;
	}
	if (rest_particle_density == 0.0) {
		double acc = 0.0;
		int fluid_cells = 0;
		const int *ct = cell_type.ptr();
		for (int c = 0; c < cols * rows; c++) {
			if (ct[c] == CELL_FLUID) {
				acc += cd[c];
				fluid_cells++;
			}
		}
		if (fluid_cells > 0) {
			rest_particle_density = real_t(acc / double(fluid_cells));
		}
	}
}

// Gauss-Seidel sweeps depend on visiting order, so this stays serial.
void CgameFLIPFluid::_solve_incompressibility() {
	gprev = gv;
	last_divergence_before = divergence_max();
	float *g = gv.ptrw();
	const float *so = s_open.ptr();
	const int *ct = cell_type.ptr();
	const float *cd = cell_density.ptr();
	for (int it = 0; it < pressure_iterations; it++) {
		for (int i = 1; i < cols - 1; i++) {
			for (int j = 1; j < rows - 1; j++) {
				const int c = i * rows + j;
				if (ct[c] != CELL_FLUID) {
					continue;
				}
				const int right = c + rows;
				const int top = c + 1;
				const real_t sx0 = so[c - rows];
				const real_t sx1 = so[right];
				const real_t sy0 = so[c - 1];
				const real_t sy1 = so[top];
				const real_t s_sum = sx0 + sx1 + sy0 + sy1;
				if (s_sum == 0.0) {
					continue;
				}
				real_t div = g[2 * right] - g[2 * c] + g[2 * top + 1] - g[2 * c + 1];
				if (rest_particle_density > 0.0 && compensate_drift) {
					const real_t compression = cd[c] - rest_particle_density;
					if (compression > 0.0) {
						div -= compression;
					}
				}
				const real_t corr = -div / s_sum * over_relaxation;
				g[2 * c] -= sx0 * corr;
				g[2 * right] += sx1 * corr;
				g[2 * c + 1] -= sy0 * corr;
				g[2 * top + 1] += sy1 * corr;
			}
		}
	}
}

void CgameFLIPFluid::_from_grid() {
	const float *g = gv.ptr();
	const float *gp = gprev.ptr();
	const int *ct = cell_type.ptr();
	Vector2 *v = pvel.ptrw();
	const Vector2 *p = ppos.ptr();
	// Pure gather from the grid into the particle's own velocity: chunk-independent.
	CgameFluids::parallel_for(ppos.size(), 256, [&](int p_from, int p_to) {
		for (int q = p_from; q < p_to; q++) {
			for (int comp = 0; comp < 2; comp++) {
				const int offset = comp == 0 ? rows : 1;
				const Stencil st = _stencil(p[q], comp);
				real_t weight_sum = 0.0;
				real_t pic = 0.0;
				real_t corr = 0.0;
				for (int k = 0; k < 4; k++) {
					const int node = st.node[k];
					const real_t w = st.weight[k];
					const int other = MAX(node - offset, 0);
					if (ct[node] != CELL_AIR || ct[other] != CELL_AIR) {
						weight_sum += w;
						pic += w * g[2 * node + comp];
						corr += w * (g[2 * node + comp] - gp[2 * node + comp]);
					}
				}
				if (weight_sum > 0.0) {
					pic /= weight_sum;
					corr /= weight_sum;
					const real_t current = comp == 0 ? v[q].x : v[q].y;
					const real_t blended = (1.0 - flip_ratio) * pic + flip_ratio * (current + corr);
					if (comp == 0) {
						v[q].x = blended;
					} else {
						v[q].y = blended;
					}
				}
			}
		}
	});
}

void CgameFLIPFluid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "cols", "rows", "cell_size"), &CgameFLIPFluid::setup);
	ClassDB::bind_method(D_METHOD("particle_count"), &CgameFLIPFluid::particle_count);
	ClassDB::bind_method(D_METHOD("particle_positions"), &CgameFLIPFluid::particle_positions);
	ClassDB::bind_method(D_METHOD("particle_velocities"), &CgameFLIPFluid::particle_velocities);
	ClassDB::bind_method(D_METHOD("clear_particles"), &CgameFLIPFluid::clear_particles);
	ClassDB::bind_method(D_METHOD("cell_of", "position"), &CgameFLIPFluid::cell_of);
	ClassDB::bind_method(D_METHOD("cell_type_at", "cell"), &CgameFLIPFluid::cell_type_at);
	ClassDB::bind_method(D_METHOD("is_wall", "cell"), &CgameFLIPFluid::is_wall);
	ClassDB::bind_method(D_METHOD("set_solid", "cell", "solid"), &CgameFLIPFluid::set_solid);
	ClassDB::bind_method(D_METHOD("set_obstacle", "center", "radius", "velocity"), &CgameFLIPFluid::set_obstacle, DEFVAL(Vector2()));
	ClassDB::bind_method(D_METHOD("clear_obstacle"), &CgameFLIPFluid::clear_obstacle);
	ClassDB::bind_method(D_METHOD("add_water_block", "lo", "hi"), &CgameFLIPFluid::add_water_block);
	ClassDB::bind_method(D_METHOD("step", "dt"), &CgameFLIPFluid::step);
	ClassDB::bind_method(D_METHOD("divergence_max"), &CgameFLIPFluid::divergence_max);
	ClassDB::bind_method(D_METHOD("average_height"), &CgameFLIPFluid::average_height);
	ClassDB::bind_method(D_METHOD("kinetic_energy"), &CgameFLIPFluid::kinetic_energy);
	ClassDB::bind_method(D_METHOD("get_cell_types"), &CgameFLIPFluid::get_cell_types);
	ClassDB::bind_method(D_METHOD("get_cell_density"), &CgameFLIPFluid::get_cell_density);

	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::INT, cols)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::INT, rows)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::FLOAT, cell_size)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::FLOAT, last_divergence_before)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::BOOL, obstacle_active)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::VECTOR2, obstacle_center)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::FLOAT, obstacle_radius)
	CGF_BIND_READONLY_PROPERTY(CgameFLIPFluid, Variant::VECTOR2, obstacle_velocity)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::FLOAT, particle_radius)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::VECTOR2, gravity)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::FLOAT, flip_ratio)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::INT, pressure_iterations)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::INT, push_iterations)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::FLOAT, over_relaxation)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::BOOL, compensate_drift)
	CGF_BIND_PROPERTY(CgameFLIPFluid, Variant::FLOAT, fluid_density)

	BIND_ENUM_CONSTANT(CELL_FLUID);
	BIND_ENUM_CONSTANT(CELL_AIR);
	BIND_ENUM_CONSTANT(CELL_SOLID);
}
