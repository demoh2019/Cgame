/**************************************************************************/
/*  cgame_smoke_sim.cpp                                                   */
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

#include "cgame_smoke_sim.h"

#include "core/math/math_funcs.h"
#include "scene/resources/image_texture.h"

CgameSmokeSim::CgameSmokeSim() {
	setup(DEFAULT_SIZE);
}

void CgameSmokeSim::setup(int p_grid_size) {
	size = MAX(4, p_grid_size);
	cell_count = size * size * size;
	Vector<float> *fields[] = { &vx, &vy, &vz, &density, &temperature, &fuel, &s0, &s1, &s2, &pressure, &div_buf, &ox, &oy, &oz, &om };
	for (Vector<float> *f : fields) {
		f->resize(cell_count);
		f->fill(0.0);
	}
	obstacle.resize(cell_count);
	obstacle.fill(0);
}

int CgameSmokeSim::_slice_chunk() const {
	// Tiny grids are cheaper to run serially than to dispatch.
	return size < 16 ? size : 2;
}

Vector<float> *CgameSmokeSim::_field_ptr(Field p_field) {
	switch (p_field) {
		case FIELD_DENSITY:
			return &density;
		case FIELD_TEMPERATURE:
			return &temperature;
		case FIELD_FUEL:
			return &fuel;
		case FIELD_VELOCITY_X:
			return &vx;
		case FIELD_VELOCITY_Y:
			return &vy;
		case FIELD_VELOCITY_Z:
			return &vz;
	}
	return nullptr;
}

const Vector<float> *CgameSmokeSim::_field_ptr(Field p_field) const {
	return const_cast<CgameSmokeSim *>(this)->_field_ptr(p_field);
}

bool CgameSmokeSim::in_bounds(const Vector3i &p_cell) const {
	return p_cell.x >= 0 && p_cell.y >= 0 && p_cell.z >= 0 && p_cell.x < size && p_cell.y < size && p_cell.z < size;
}

void CgameSmokeSim::clear() {
	vx.fill(0.0);
	vy.fill(0.0);
	vz.fill(0.0);
	density.fill(0.0);
	temperature.fill(0.0);
	fuel.fill(0.0);
}

void CgameSmokeSim::add_source(const Vector3i &p_cell, real_t p_density, real_t p_temperature, real_t p_fuel, const Vector3 &p_velocity) {
	if (!in_bounds(p_cell)) {
		return;
	}
	const int i = _idx(p_cell.x, p_cell.y, p_cell.z);
	if (obstacle[i] != 0) {
		return;
	}
	density.write[i] += p_density;
	temperature.write[i] += p_temperature;
	fuel.write[i] += p_fuel;
	vx.write[i] += p_velocity.x;
	vy.write[i] += p_velocity.y;
	vz.write[i] += p_velocity.z;
}

void CgameSmokeSim::set_obstacle(const Vector3i &p_cell, bool p_solid) {
	if (!in_bounds(p_cell)) {
		return;
	}
	const int i = _idx(p_cell.x, p_cell.y, p_cell.z);
	obstacle.write[i] = p_solid ? 1 : 0;
	if (p_solid) {
		_kill_cell(i);
	}
}

bool CgameSmokeSim::is_obstacle(const Vector3i &p_cell) const {
	return in_bounds(p_cell) && obstacle[_idx(p_cell.x, p_cell.y, p_cell.z)] != 0;
}

void CgameSmokeSim::_kill_cell(int p_i) {
	vx.write[p_i] = 0.0;
	vy.write[p_i] = 0.0;
	vz.write[p_i] = 0.0;
	density.write[p_i] = 0.0;
	temperature.write[p_i] = 0.0;
	fuel.write[p_i] = 0.0;
}

void CgameSmokeSim::step(real_t p_dt) {
	if (p_dt <= 0.0) {
		return;
	}
	_apply_forces(p_dt);
	_vorticity_confinement(p_dt);
	_combust(p_dt);
	project();
	_advect(vx, s0, p_dt);
	_advect(vy, s1, p_dt);
	_advect(vz, s2, p_dt);
	SWAP(vx, s0);
	SWAP(vy, s1);
	SWAP(vz, s2);
	project();
	_advect(density, s0, p_dt);
	SWAP(density, s0);
	_advect(temperature, s0, p_dt);
	SWAP(temperature, s0);
	_advect(fuel, s0, p_dt);
	SWAP(fuel, s0);
	_decay(p_dt);
	_enforce_obstacles();
}

void CgameSmokeSim::_apply_forces(real_t p_dt) {
	const real_t drag = CLAMP(wind_drag * p_dt, real_t(0.0), real_t(1.0));
	const uint8_t *ob = obstacle.ptr();
	float *px = vx.ptrw();
	float *py = vy.ptrw();
	float *pz = vz.ptrw();
	const float *t = temperature.ptr();
	const float *d = density.ptr();
	CgameFluids::parallel_for(cell_count, 4096, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			if (ob[i] != 0) {
				continue;
			}
			px[i] += (wind.x - px[i]) * drag;
			py[i] += (wind.y - py[i]) * drag;
			pz[i] += (wind.z - pz[i]) * drag;
			py[i] += (buoyancy * t[i] - weight * d[i]) * p_dt;
			px[i] = CLAMP(px[i], -max_speed, max_speed);
			py[i] = CLAMP(py[i], -max_speed, max_speed);
			pz[i] = CLAMP(pz[i], -max_speed, max_speed);
		}
	});
}

void CgameSmokeSim::_combust(real_t p_dt) {
	const real_t frac = 1.0 - Math::exp(-burn_rate * p_dt);
	const uint8_t *ob = obstacle.ptr();
	float *fu = fuel.ptrw();
	float *te = temperature.ptrw();
	float *de = density.ptrw();
	CgameFluids::parallel_for(cell_count, 4096, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			const real_t f = fu[i];
			if (f <= 0.0 || te[i] < ignition_temperature || ob[i] != 0) {
				continue;
			}
			const real_t burnt = f * frac;
			fu[i] = f - burnt;
			te[i] += burnt * heat_yield;
			de[i] += burnt * smoke_yield;
		}
	});
}

void CgameSmokeSim::_decay(real_t p_dt) {
	const real_t t_k = Math::exp(-cooling * p_dt);
	const real_t d_k = Math::exp(-density_decay * p_dt);
	float *te = temperature.ptrw();
	float *de = density.ptrw();
	CgameFluids::parallel_for(cell_count, 4096, [&](int p_from, int p_to) {
		for (int i = p_from; i < p_to; i++) {
			te[i] *= t_k;
			de[i] *= d_k;
		}
	});
}

void CgameSmokeSim::_enforce_obstacles() {
	for (int i = 0; i < cell_count; i++) {
		if (obstacle[i] != 0) {
			_kill_cell(i);
		}
	}
}

// Clamped fetch.
float CgameSmokeSim::_clamped(const float *p_f, int p_x, int p_y, int p_z) const {
	return p_f[CLAMP(p_x, 0, size - 1) + size * (CLAMP(p_y, 0, size - 1) + size * CLAMP(p_z, 0, size - 1))];
}

void CgameSmokeSim::_vorticity_confinement(real_t p_dt) {
	if (vorticity_strength <= 0.0) {
		return;
	}
	const int n = size;
	const float *fx = vx.ptr();
	const float *fy = vy.ptr();
	const float *fz = vz.ptr();
	float *pox = ox.ptrw();
	float *poy = oy.ptrw();
	float *poz = oz.ptrw();
	float *pom = om.ptrw();
	CgameFluids::parallel_for(n, _slice_chunk(), [&](int p_from, int p_to) {
		for (int z = p_from; z < p_to; z++) {
			for (int y = 0; y < n; y++) {
				for (int x = 0; x < n; x++) {
					const int i = _idx(x, y, z);
					const real_t wx = (_clamped(fz, x, y + 1, z) - _clamped(fz, x, y - 1, z) - _clamped(fy, x, y, z + 1) + _clamped(fy, x, y, z - 1)) * 0.5;
					const real_t wy = (_clamped(fx, x, y, z + 1) - _clamped(fx, x, y, z - 1) - _clamped(fz, x + 1, y, z) + _clamped(fz, x - 1, y, z)) * 0.5;
					const real_t wz = (_clamped(fy, x + 1, y, z) - _clamped(fy, x - 1, y, z) - _clamped(fx, x, y + 1, z) + _clamped(fx, x, y - 1, z)) * 0.5;
					pox[i] = wx;
					poy[i] = wy;
					poz[i] = wz;
					pom[i] = Math::sqrt(wx * wx + wy * wy + wz * wz);
				}
			}
		}
	});
	const uint8_t *ob = obstacle.ptr();
	float *wvx = vx.ptrw();
	float *wvy = vy.ptrw();
	float *wvz = vz.ptrw();
	const real_t k = vorticity_strength * p_dt;
	CgameFluids::parallel_for(n - 2, _slice_chunk(), [&](int p_from, int p_to) {
		for (int z = p_from + 1; z < p_to + 1; z++) {
			for (int y = 1; y < n - 1; y++) {
				for (int x = 1; x < n - 1; x++) {
					const int i = _idx(x, y, z);
					if (ob[i] != 0) {
						continue;
					}
					real_t gx = (pom[_idx(x + 1, y, z)] - pom[_idx(x - 1, y, z)]) * 0.5;
					real_t gy = (pom[_idx(x, y + 1, z)] - pom[_idx(x, y - 1, z)]) * 0.5;
					real_t gz = (pom[_idx(x, y, z + 1)] - pom[_idx(x, y, z - 1)]) * 0.5;
					const real_t len = Math::sqrt(gx * gx + gy * gy + gz * gz);
					if (len < 1e-5) {
						continue;
					}
					gx /= len;
					gy /= len;
					gz /= len;
					const real_t wx = pox[i];
					const real_t wy = poy[i];
					const real_t wz = poz[i];
					wvx[i] += k * (gy * wz - gz * wy);
					wvy[i] += k * (gz * wx - gx * wz);
					wvz[i] += k * (gx * wy - gy * wx);
				}
			}
		}
	});
}

float CgameSmokeSim::_sample(const float *p_f, real_t p_x, real_t p_y, real_t p_z) const {
	const real_t hi = real_t(size - 1);
	p_x = CLAMP(p_x, real_t(0.0), hi);
	p_y = CLAMP(p_y, real_t(0.0), hi);
	p_z = CLAMP(p_z, real_t(0.0), hi);
	const int x0 = int(p_x);
	const int y0 = int(p_y);
	const int z0 = int(p_z);
	const int x1 = MIN(x0 + 1, size - 1);
	const int y1 = MIN(y0 + 1, size - 1);
	const int z1 = MIN(z0 + 1, size - 1);
	const real_t fx = p_x - x0;
	const real_t fy = p_y - y0;
	const real_t fz = p_z - z0;
	const int n = size;
	const int b00 = x0 + n * (y0 + n * z0);
	const int b10 = x1 + n * (y0 + n * z0);
	const int b01 = x0 + n * (y1 + n * z0);
	const int b11 = x1 + n * (y1 + n * z0);
	const int t00 = x0 + n * (y0 + n * z1);
	const int t10 = x1 + n * (y0 + n * z1);
	const int t01 = x0 + n * (y1 + n * z1);
	const int t11 = x1 + n * (y1 + n * z1);
	const real_t a = Math::lerp(Math::lerp(p_f[b00], p_f[b10], fx), Math::lerp(p_f[b01], p_f[b11], fx), fy);
	const real_t b = Math::lerp(Math::lerp(p_f[t00], p_f[t10], fx), Math::lerp(p_f[t01], p_f[t11], fx), fy);
	return Math::lerp(a, b, fz);
}

real_t CgameSmokeSim::sample(Field p_field, const Vector3 &p_position) const {
	const Vector<float> *f = _field_ptr(p_field);
	ERR_FAIL_NULL_V(f, 0.0);
	return _sample(f->ptr(), p_position.x, p_position.y, p_position.z);
}

// Stam semi-Lagrangian advection: trace each cell centre back along the velocity field.
void CgameSmokeSim::_advect(const Vector<float> &p_src, Vector<float> &r_dst, real_t p_dt) {
	const int n = size;
	const float *src = p_src.ptr();
	float *dst = r_dst.ptrw();
	const uint8_t *ob = obstacle.ptr();
	const float *fx = vx.ptr();
	const float *fy = vy.ptr();
	const float *fz = vz.ptr();
	CgameFluids::parallel_for(n, _slice_chunk(), [&](int p_from, int p_to) {
		for (int z = p_from; z < p_to; z++) {
			for (int y = 0; y < n; y++) {
				for (int x = 0; x < n; x++) {
					const int i = x + n * (y + n * z);
					if (ob[i] != 0) {
						dst[i] = 0.0;
						continue;
					}
					dst[i] = _sample(src, x - p_dt * fx[i], y - p_dt * fy[i], z - p_dt * fz[i]);
				}
			}
		}
	});
}

float CgameSmokeSim::_nvel(const float *p_f, const uint8_t *p_obs, int p_i, int p_x, int p_y, int p_z) const {
	if (p_x < 0 || p_y < 0 || p_z < 0 || p_x >= size || p_y >= size || p_z >= size) {
		return p_f[p_i];
	}
	const int j = p_x + size * (p_y + size * p_z);
	if (p_obs[j] != 0) {
		return 0.0;
	}
	return p_f[j];
}

void CgameSmokeSim::_compute_divergence() {
	const int n = size;
	const float *fx = vx.ptr();
	const float *fy = vy.ptr();
	const float *fz = vz.ptr();
	const uint8_t *ob = obstacle.ptr();
	float *dv = div_buf.ptrw();
	CgameFluids::parallel_for(n, _slice_chunk(), [&](int p_from, int p_to) {
		for (int z = p_from; z < p_to; z++) {
			for (int y = 0; y < n; y++) {
				for (int x = 0; x < n; x++) {
					const int i = x + n * (y + n * z);
					if (ob[i] != 0) {
						dv[i] = 0.0;
						continue;
					}
					dv[i] = 0.5 * (_nvel(fx, ob, i, x + 1, y, z) - _nvel(fx, ob, i, x - 1, y, z) + _nvel(fy, ob, i, x, y + 1, z) - _nvel(fy, ob, i, x, y - 1, z) + _nvel(fz, ob, i, x, y, z + 1) - _nvel(fz, ob, i, x, y, z - 1));
				}
			}
		}
	});
}

// Root-mean-square divergence over fluid cells (0 = incompressible).
real_t CgameSmokeSim::divergence_rms() {
	_compute_divergence();
	double s = 0.0;
	int c = 0;
	const float *dv = div_buf.ptr();
	const uint8_t *ob = obstacle.ptr();
	for (int i = 0; i < cell_count; i++) {
		if (ob[i] == 0) {
			s += double(dv[i]) * double(dv[i]);
			c++;
		}
	}
	return real_t(Math::sqrt(s / MAX(1.0, double(c))));
}

// Pressure projection: solve laplacian(p) = div(v) with Jacobi and subtract grad(p).
void CgameSmokeSim::project() {
	_compute_divergence();
	const int n = size;
	const uint8_t *ob = obstacle.ptr();
	const float *dv = div_buf.ptr();
	pressure.fill(0.0);
	static const int dx[6] = { 1, -1, 0, 0, 0, 0 };
	static const int dy[6] = { 0, 0, 1, -1, 0, 0 };
	static const int dz[6] = { 0, 0, 0, 0, 1, -1 };
	for (int it = 0; it < jacobi_iterations; it++) {
		const float *pr = pressure.ptr();
		float *out = s0.ptrw();
		CgameFluids::parallel_for(n, _slice_chunk(), [&](int p_from, int p_to) {
			for (int z = p_from; z < p_to; z++) {
				for (int y = 0; y < n; y++) {
					for (int x = 0; x < n; x++) {
						const int i = x + n * (y + n * z);
						if (ob[i] != 0) {
							out[i] = 0.0;
							continue;
						}
						real_t sum = 0.0;
						int cnt = 0;
						for (int d = 0; d < 6; d++) {
							const int nx = x + dx[d];
							const int ny = y + dy[d];
							const int nz = z + dz[d];
							if (nx < 0 || ny < 0 || nz < 0 || nx >= n || ny >= n || nz >= n) {
								cnt++;
								continue;
							}
							const int j = nx + n * (ny + n * nz);
							if (ob[j] != 0) {
								continue;
							}
							cnt++;
							sum += pr[j];
						}
						out[i] = cnt > 0 ? (sum - dv[i]) / real_t(cnt) : real_t(0.0);
					}
				}
			}
		});
		SWAP(pressure, s0);
	}
	const float *pr = pressure.ptr();
	float *wvx = vx.ptrw();
	float *wvy = vy.ptrw();
	float *wvz = vz.ptrw();
	// Pressure value at a neighbour; out of grid -> 0, solid neighbour -> own pressure.
	auto pn = [&](int p_i, int p_x, int p_y, int p_z) -> real_t {
		if (p_x < 0 || p_y < 0 || p_z < 0 || p_x >= n || p_y >= n || p_z >= n) {
			return 0.0;
		}
		const int j = p_x + n * (p_y + n * p_z);
		if (ob[j] != 0) {
			return pr[p_i];
		}
		return pr[j];
	};
	CgameFluids::parallel_for(n, _slice_chunk(), [&](int p_from, int p_to) {
		for (int z = p_from; z < p_to; z++) {
			for (int y = 0; y < n; y++) {
				for (int x = 0; x < n; x++) {
					const int i = x + n * (y + n * z);
					if (ob[i] != 0) {
						continue;
					}
					wvx[i] -= 0.5 * (pn(i, x + 1, y, z) - pn(i, x - 1, y, z));
					wvy[i] -= 0.5 * (pn(i, x, y + 1, z) - pn(i, x, y - 1, z));
					wvz[i] -= 0.5 * (pn(i, x, y, z + 1) - pn(i, x, y, z - 1));
				}
			}
		}
	});
}

double CgameSmokeSim::_sum(const Vector<float> &p_f) const {
	double s = 0.0;
	const float *f = p_f.ptr();
	for (int i = 0; i < p_f.size(); i++) {
		s += f[i];
	}
	return s;
}

real_t CgameSmokeSim::max_temperature() const {
	real_t m = 0.0;
	const float *t = temperature.ptr();
	for (int i = 0; i < cell_count; i++) {
		m = MAX(m, real_t(t[i]));
	}
	return m;
}

// Density-weighted centre of mass in cell coordinates.
Vector3 CgameSmokeSim::density_centroid() const {
	double total = 0.0;
	double cx = 0.0, cy = 0.0, cz = 0.0;
	const float *d = density.ptr();
	for (int z = 0; z < size; z++) {
		for (int y = 0; y < size; y++) {
			for (int x = 0; x < size; x++) {
				const double v = d[_idx(x, y, z)];
				total += v;
				cx += x * v;
				cy += y * v;
				cz += z * v;
			}
		}
	}
	if (total > 1e-9) {
		return Vector3(real_t(cx / total), real_t(cy / total), real_t(cz / total));
	}
	return Vector3();
}

bool CgameSmokeSim::is_finite_state() const {
	const Vector<float> *fields[] = { &vx, &vy, &vz, &density, &temperature, &fuel };
	for (const Vector<float> *f : fields) {
		const float *p = f->ptr();
		for (int i = 0; i < f->size(); i++) {
			if (!Math::is_finite(p[i])) {
				return false;
			}
		}
	}
	return true;
}

Vector<float> CgameSmokeSim::get_field(Field p_field) const {
	const Vector<float> *f = _field_ptr(p_field);
	ERR_FAIL_NULL_V(f, Vector<float>());
	return *f;
}

real_t CgameSmokeSim::get_value(Field p_field, const Vector3i &p_cell) const {
	ERR_FAIL_COND_V(!in_bounds(p_cell), 0.0);
	const Vector<float> *f = _field_ptr(p_field);
	ERR_FAIL_NULL_V(f, 0.0);
	return (*f)[_idx(p_cell.x, p_cell.y, p_cell.z)];
}

void CgameSmokeSim::set_velocity(const Vector3i &p_cell, const Vector3 &p_velocity) {
	if (!in_bounds(p_cell)) {
		return;
	}
	const int i = _idx(p_cell.x, p_cell.y, p_cell.z);
	vx.write[i] = p_velocity.x;
	vy.write[i] = p_velocity.y;
	vz.write[i] = p_velocity.z;
}

Vector3 CgameSmokeSim::get_velocity(const Vector3i &p_cell) const {
	ERR_FAIL_COND_V(!in_bounds(p_cell), Vector3());
	const int i = _idx(p_cell.x, p_cell.y, p_cell.z);
	return Vector3(vx[i], vy[i], vz[i]);
}

// One RG float image per z slice (R = density, G = temperature) for ImageTexture3D.create.
Vector<Ref<Image>> CgameSmokeSim::_make_slices() const {
	Vector<Ref<Image>> out;
	const int n = size;
	const float *d = density.ptr();
	const float *t = temperature.ptr();
	for (int z = 0; z < n; z++) {
		Vector<uint8_t> raw;
		raw.resize(n * n * 2 * int(sizeof(float)));
		float *dst = reinterpret_cast<float *>(raw.ptrw());
		for (int y = 0; y < n; y++) {
			for (int x = 0; x < n; x++) {
				const int i = x + n * (y + n * z);
				const int o = 2 * (x + n * y);
				dst[o] = d[i];
				dst[o + 1] = t[i];
			}
		}
		out.push_back(Image::create_from_data(n, n, false, Image::FORMAT_RGF, raw));
	}
	return out;
}

TypedArray<Image> CgameSmokeSim::density_image_slices() const {
	TypedArray<Image> out;
	const Vector<Ref<Image>> slices = _make_slices();
	for (const Ref<Image> &img : slices) {
		out.push_back(img);
	}
	return out;
}

Ref<ImageTexture3D> CgameSmokeSim::to_image3d() const {
	Ref<ImageTexture3D> tex;
	tex.instantiate();
	const Error err = tex->create(Image::FORMAT_RGF, size, size, size, false, _make_slices());
	if (err != OK) {
		return Ref<ImageTexture3D>();
	}
	return tex;
}

// Refreshes an existing texture in place (cheaper than re-creating it every frame).
void CgameSmokeSim::update_image3d(const Ref<ImageTexture3D> &p_texture) const {
	ERR_FAIL_COND(p_texture.is_null());
	p_texture->update(_make_slices());
}

void CgameSmokeSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "grid_size"), &CgameSmokeSim::setup);
	ClassDB::bind_method(D_METHOD("index", "x", "y", "z"), &CgameSmokeSim::index);
	ClassDB::bind_method(D_METHOD("in_bounds", "cell"), &CgameSmokeSim::in_bounds);
	ClassDB::bind_method(D_METHOD("clear"), &CgameSmokeSim::clear);
	ClassDB::bind_method(D_METHOD("add_source", "cell", "density", "temperature", "fuel", "velocity"), &CgameSmokeSim::add_source, DEFVAL(0.0), DEFVAL(0.0), DEFVAL(Vector3()));
	ClassDB::bind_method(D_METHOD("set_obstacle", "cell", "solid"), &CgameSmokeSim::set_obstacle);
	ClassDB::bind_method(D_METHOD("is_obstacle", "cell"), &CgameSmokeSim::is_obstacle);
	ClassDB::bind_method(D_METHOD("step", "dt"), &CgameSmokeSim::step);
	ClassDB::bind_method(D_METHOD("project"), &CgameSmokeSim::project);
	ClassDB::bind_method(D_METHOD("sample", "field", "position"), &CgameSmokeSim::sample);
	ClassDB::bind_method(D_METHOD("get_field", "field"), &CgameSmokeSim::get_field);
	ClassDB::bind_method(D_METHOD("get_value", "field", "cell"), &CgameSmokeSim::get_value);
	ClassDB::bind_method(D_METHOD("set_velocity", "cell", "velocity"), &CgameSmokeSim::set_velocity);
	ClassDB::bind_method(D_METHOD("get_velocity", "cell"), &CgameSmokeSim::get_velocity);
	ClassDB::bind_method(D_METHOD("divergence_rms"), &CgameSmokeSim::divergence_rms);
	ClassDB::bind_method(D_METHOD("total_density"), &CgameSmokeSim::total_density);
	ClassDB::bind_method(D_METHOD("total_temperature"), &CgameSmokeSim::total_temperature);
	ClassDB::bind_method(D_METHOD("total_fuel"), &CgameSmokeSim::total_fuel);
	ClassDB::bind_method(D_METHOD("max_temperature"), &CgameSmokeSim::max_temperature);
	ClassDB::bind_method(D_METHOD("density_centroid"), &CgameSmokeSim::density_centroid);
	ClassDB::bind_method(D_METHOD("is_finite_state"), &CgameSmokeSim::is_finite_state);
	ClassDB::bind_method(D_METHOD("density_image_slices"), &CgameSmokeSim::density_image_slices);
	ClassDB::bind_method(D_METHOD("to_image3d"), &CgameSmokeSim::to_image3d);
	ClassDB::bind_method(D_METHOD("update_image3d", "texture"), &CgameSmokeSim::update_image3d);

	CGF_BIND_READONLY_PROPERTY(CgameSmokeSim, Variant::INT, size)
	CGF_BIND_READONLY_PROPERTY(CgameSmokeSim, Variant::INT, cell_count)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::VECTOR3, wind)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, wind_drag)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, buoyancy)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, weight)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, vorticity_strength)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, cooling)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, density_decay)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, ignition_temperature)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, burn_rate)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, heat_yield)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, smoke_yield)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::INT, jacobi_iterations)
	CGF_BIND_PROPERTY(CgameSmokeSim, Variant::FLOAT, max_speed)

	BIND_ENUM_CONSTANT(FIELD_DENSITY);
	BIND_ENUM_CONSTANT(FIELD_TEMPERATURE);
	BIND_ENUM_CONSTANT(FIELD_FUEL);
	BIND_ENUM_CONSTANT(FIELD_VELOCITY_X);
	BIND_ENUM_CONSTANT(FIELD_VELOCITY_Y);
	BIND_ENUM_CONSTANT(FIELD_VELOCITY_Z);
	BIND_CONSTANT(DEFAULT_SIZE);
}
