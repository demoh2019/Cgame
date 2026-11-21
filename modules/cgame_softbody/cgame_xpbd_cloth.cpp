/**************************************************************************/
/*  cgame_xpbd_cloth.cpp                                                  */
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

#include "cgame_xpbd_cloth.h"

#include "core/object/class_db.h"
#include "scene/resources/mesh.h"

static const real_t EPS = 0.0000001;

void CgameXPBDCloth::_add_constraint(int p_a, int p_b, int p_kind, int p_mid) {
	ca.push_back(p_a);
	cb.push_back(p_b);
	cmid.push_back(p_mid);
	crest.push_back(rest_pos[p_a].distance_to(rest_pos[p_b]));
	ckind.push_back((uint8_t)p_kind);
}

void CgameXPBDCloth::setup_grid(int p_width_cells, int p_height_cells, real_t p_spacing, const Transform3D &p_origin, real_t p_particle_mass) {
	cols = MAX(p_width_cells, 1) + 1;
	rows = MAX(p_height_cells, 1) + 1;
	const int n = cols * rows;
	pos.resize(n);
	prev.resize(n);
	vel.resize(n);
	rest_pos.resize(n);
	uv.resize(n);
	inv_mass.resize(n);
	base_inv_mass.resize(n);
	pin_mode.resize(n);
	pin_pos.resize(n);
	drive_from.resize(n);
	pin_fn.clear();
	pin_fn.resize(n);

	const float w = 1.0f / MAX((float)p_particle_mass, 0.000001f);
	for (int j = 0; j < rows; j++) {
		for (int i = 0; i < cols; i++) {
			const int k = j * cols + i;
			const Vector3 p = p_origin.xform(Vector3(i * p_spacing, -j * p_spacing, 0.0));
			pos.write[k] = p;
			prev.write[k] = p;
			rest_pos.write[k] = p;
			vel.write[k] = Vector3();
			pin_pos.write[k] = p;
			drive_from.write[k] = p;
			uv.write[k] = Vector2(real_t(i) / real_t(cols - 1), real_t(j) / real_t(rows - 1));
			inv_mass.write[k] = w;
			base_inv_mass.write[k] = w;
			pin_mode.write[k] = PIN_FREE;
		}
	}

	ca.clear();
	cb.clear();
	cmid.clear();
	crest.clear();
	ckind.clear();
	tris.clear();
	tri_cell.clear();
	torn_count = 0;

	for (int j = 0; j < rows; j++) {
		for (int i = 0; i < cols; i++) {
			const int k = j * cols + i;
			if (i + 1 < cols) {
				_add_constraint(k, k + 1, KIND_STRETCH, -1);
			}
			if (j + 1 < rows) {
				_add_constraint(k, k + cols, KIND_STRETCH, -1);
			}
			if (i + 1 < cols && j + 1 < rows) {
				_add_constraint(k, k + cols + 1, KIND_SHEAR, -1);
				_add_constraint(k + 1, k + cols, KIND_SHEAR, -1);
				const int cell = j * (cols - 1) + i;
				// a=k, b=k+1, c=k+cols, d=k+cols+1; counter-clockwise seen from local +Z.
				tris.push_back(k);
				tris.push_back(k + cols);
				tris.push_back(k + cols + 1);
				tri_cell.push_back(cell);
				tris.push_back(k);
				tris.push_back(k + cols + 1);
				tris.push_back(k + 1);
				tri_cell.push_back(cell);
			}
			if (i + 2 < cols) {
				_add_constraint(k, k + 2, KIND_BEND, k + 1);
			}
			if (j + 2 < rows) {
				_add_constraint(k, k + 2 * cols, KIND_BEND, k + cols);
			}
		}
	}
}

int CgameXPBDCloth::stretch_constraint_count() const {
	int c = 0;
	for (int k = 0; k < ckind.size(); k++) {
		if (ckind[k] == KIND_STRETCH) {
			c++;
		}
	}
	return c;
}

real_t CgameXPBDCloth::max_stretch_error() const {
	real_t worst = 0.0;
	for (int c = 0; c < ca.size(); c++) {
		if (ckind[c] != KIND_STRETCH) {
			continue;
		}
		const real_t e = Math::abs(pos[ca[c]].distance_to(pos[cb[c]]) / crest[c] - 1.0);
		worst = MAX(worst, e);
	}
	return worst;
}

void CgameXPBDCloth::pin(int p_index, const Vector3 &p_world_pos) {
	ERR_FAIL_INDEX(p_index, pos.size());
	pin_mode.write[p_index] = PIN_FIXED;
	pin_pos.write[p_index] = p_world_pos;
	inv_mass.write[p_index] = 0.0f;
	pos.write[p_index] = p_world_pos;
	prev.write[p_index] = p_world_pos;
	vel.write[p_index] = Vector3();
}

void CgameXPBDCloth::attach(int p_index, const Callable &p_target_fn) {
	ERR_FAIL_INDEX(p_index, pos.size());
	ERR_FAIL_COND_MSG(!p_target_fn.is_valid(), "Cloth attach target must be a valid Callable.");
	pin_mode.write[p_index] = PIN_CALLABLE;
	pin_fn.write[p_index] = p_target_fn;
	inv_mass.write[p_index] = 0.0f;
	const Variant ret = p_target_fn.call();
	const Vector3 p = ret.get_type() == Variant::VECTOR3 ? Vector3(ret) : pos[p_index];
	pin_pos.write[p_index] = p;
	pos.write[p_index] = p;
	prev.write[p_index] = p;
	vel.write[p_index] = Vector3();
}

void CgameXPBDCloth::drive(int p_index, const Vector3 &p_world_pos) {
	ERR_FAIL_INDEX(p_index, pos.size());
	if (pin_mode[p_index] != PIN_DRIVEN) {
		// First drive call snaps the particle; later calls glide toward the target during step().
		pin_mode.write[p_index] = PIN_DRIVEN;
		inv_mass.write[p_index] = 0.0f;
		pos.write[p_index] = p_world_pos;
		prev.write[p_index] = p_world_pos;
		drive_from.write[p_index] = p_world_pos;
		vel.write[p_index] = Vector3();
	}
	pin_pos.write[p_index] = p_world_pos;
}

void CgameXPBDCloth::unpin(int p_index) {
	ERR_FAIL_INDEX(p_index, pos.size());
	pin_mode.write[p_index] = PIN_FREE;
	pin_fn.write[p_index] = Callable();
	inv_mass.write[p_index] = base_inv_mass[p_index];
}

bool CgameXPBDCloth::is_pinned(int p_index) const {
	ERR_FAIL_INDEX_V(p_index, pos.size(), false);
	return pin_mode[p_index] != PIN_FREE;
}

int CgameXPBDCloth::add_sphere(const Vector3 &p_center, real_t p_radius) {
	sphere_c.push_back(p_center);
	sphere_r.push_back(p_radius);
	return sphere_c.size() - 1;
}

void CgameXPBDCloth::set_sphere_center(int p_index, const Vector3 &p_center) {
	ERR_FAIL_INDEX(p_index, sphere_c.size());
	sphere_c.write[p_index] = p_center;
}

int CgameXPBDCloth::add_capsule(const Vector3 &p_a, const Vector3 &p_b, real_t p_radius) {
	cap_a.push_back(p_a);
	cap_b.push_back(p_b);
	cap_r.push_back(p_radius);
	return cap_a.size() - 1;
}

void CgameXPBDCloth::set_capsule(int p_index, const Vector3 &p_a, const Vector3 &p_b) {
	ERR_FAIL_INDEX(p_index, cap_a.size());
	cap_a.write[p_index] = p_a;
	cap_b.write[p_index] = p_b;
}

int CgameXPBDCloth::add_plane(const Vector3 &p_normal, real_t p_offset) {
	plane_n.push_back(p_normal.normalized());
	plane_d.push_back(p_offset);
	return plane_n.size() - 1;
}

void CgameXPBDCloth::clear_colliders() {
	sphere_c.clear();
	sphere_r.clear();
	cap_a.clear();
	cap_b.clear();
	cap_r.clear();
	plane_n.clear();
	plane_d.clear();
}

void CgameXPBDCloth::set_particle(int p_index, const Vector3 &p_world_pos) {
	ERR_FAIL_INDEX(p_index, pos.size());
	pos.write[p_index] = p_world_pos;
	prev.write[p_index] = p_world_pos;
	vel.write[p_index] = Vector3();
}

void CgameXPBDCloth::step(real_t p_dt, int p_substeps) {
	if (p_dt <= 0.0 || pos.is_empty()) {
		return;
	}
	const int sub = MAX(p_substeps, 1);
	const real_t sdt = p_dt / real_t(sub);

	{
		const uint8_t *mode = pin_mode.ptr();
		const Vector3 *p = pos.ptr();
		Vector3 *from = drive_from.ptrw();
		for (int k = 0; k < pos.size(); k++) {
			if (mode[k] == PIN_DRIVEN) {
				from[k] = p[k];
			}
		}
	}

	for (int s = 0; s < sub; s++) {
		_integrate(sdt, real_t(s + 1) / real_t(sub));
		for (int it = 0; it < MAX(iterations, 1); it++) {
			_solve_constraints(sdt);
		}
		if (self_collision_enabled) {
			_solve_self_collision();
		}
		_collide();
		const float *w = inv_mass.ptr();
		const Vector3 *p = pos.ptr();
		const Vector3 *pv = prev.ptr();
		Vector3 *v = vel.ptrw();
		for (int k = 0; k < pos.size(); k++) {
			if (w[k] > 0.0f) {
				v[k] = (p[k] - pv[k]) / sdt;
			}
		}
	}
	if (tear_threshold > 0.0) {
		_tear();
	}
}

void CgameXPBDCloth::_integrate(real_t p_sdt, real_t p_drive_t) {
	const int n = pos.size();
	// Callables may re-enter this object, so resolve them before taking raw pointers.
	for (int k = 0; k < n; k++) {
		if (pin_mode[k] == PIN_CALLABLE) {
			const Variant ret = pin_fn[k].call();
			if (ret.get_type() == Variant::VECTOR3) {
				pin_pos.write[k] = ret;
			}
		}
	}
	const real_t damp = CLAMP(drag * p_sdt, 0.0, 1.0);
	const uint8_t *mode = pin_mode.ptr();
	const Vector3 *target = pin_pos.ptr();
	const Vector3 *from = drive_from.ptr();
	Vector3 *p = pos.ptrw();
	Vector3 *pv = prev.ptrw();
	Vector3 *v = vel.ptrw();
	for (int k = 0; k < n; k++) {
		if (mode[k] != PIN_FREE) {
			Vector3 t = target[k];
			if (mode[k] == PIN_DRIVEN) {
				t = from[k].lerp(target[k], p_drive_t);
			}
			pv[k] = t;
			p[k] = t;
			v[k] = Vector3();
			continue;
		}
		Vector3 nv = v[k] + gravity * p_sdt;
		nv += (wind - nv) * damp;
		pv[k] = p[k];
		p[k] += nv * p_sdt;
		v[k] = nv;
	}
}

void CgameXPBDCloth::_solve_constraints(real_t p_sdt) {
	const real_t inv_dt2 = 1.0 / (p_sdt * p_sdt);
	const real_t alpha_family[3] = { compliance_stretch * inv_dt2, compliance_shear * inv_dt2, compliance_bend * inv_dt2 };
	const int count = ca.size();
	const int *a_idx = ca.ptr();
	const int *b_idx = cb.ptr();
	const float *rest = crest.ptr();
	const uint8_t *kind = ckind.ptr();
	const float *w_inv = inv_mass.ptr();
	Vector3 *p = pos.ptrw();
	for (int c = 0; c < count; c++) {
		const int a = a_idx[c];
		const int b = b_idx[c];
		const real_t wa = w_inv[a];
		const real_t wb = w_inv[b];
		const real_t w = wa + wb;
		if (w == 0.0) {
			continue;
		}
		const Vector3 d = p[a] - p[b];
		const real_t dist = d.length();
		if (dist < EPS) {
			continue;
		}
		const real_t alpha = alpha_family[kind[c]];
		const real_t s = -(dist - rest[c]) / (w + alpha);
		const Vector3 n = d / dist;
		p[a] += n * (s * wa);
		p[b] -= n * (s * wb);
	}
}

void CgameXPBDCloth::_collide() {
	if (sphere_c.is_empty() && cap_a.is_empty() && plane_n.is_empty()) {
		return;
	}
	const int n = pos.size();
	const float *w = inv_mass.ptr();
	Vector3 *p = pos.ptrw();
	Vector3 *pv = prev.ptrw();

	auto contact = [&](int k, const Vector3 &p_n, real_t p_depth) {
		p[k] += p_n * p_depth;
		if (friction > 0.0) {
			const Vector3 dp = p[k] - pv[k];
			const Vector3 tangential = dp - p_n * dp.dot(p_n);
			pv[k] += tangential * friction;
		}
	};

	for (int k = 0; k < n; k++) {
		if (w[k] == 0.0f) {
			continue;
		}
		for (int s = 0; s < sphere_c.size(); s++) {
			const real_t min_d = sphere_r[s] + collision_margin;
			const Vector3 d = p[k] - sphere_c[s];
			const real_t l2 = d.length_squared();
			if (l2 < min_d * min_d) {
				const real_t l = Math::sqrt(l2);
				const Vector3 nrm = l > EPS ? d / l : Vector3(0, 1, 0);
				contact(k, nrm, min_d - l);
			}
		}
		for (int s = 0; s < cap_a.size(); s++) {
			const real_t min_d = cap_r[s] + collision_margin;
			const Vector3 a = cap_a[s];
			const Vector3 ab = cap_b[s] - a;
			const real_t denom = ab.length_squared();
			real_t t = 0.0;
			if (denom > EPS) {
				t = CLAMP((p[k] - a).dot(ab) / denom, 0.0, 1.0);
			}
			const Vector3 d = p[k] - (a + ab * t);
			const real_t l2 = d.length_squared();
			if (l2 < min_d * min_d) {
				const real_t l = Math::sqrt(l2);
				const Vector3 nrm = l > EPS ? d / l : Vector3(0, 1, 0);
				contact(k, nrm, min_d - l);
			}
		}
		for (int s = 0; s < plane_n.size(); s++) {
			const real_t dist = plane_n[s].dot(p[k]) - plane_d[s] - collision_margin;
			if (dist < 0.0) {
				contact(k, plane_n[s], -dist);
			}
		}
	}
}

void CgameXPBDCloth::_solve_self_collision() {
	const real_t cell = MAX(thickness, 0.0001);
	const int n = pos.size();
	for (KeyValue<uint64_t, LocalVector<int>> &kv : grid) {
		kv.value.clear();
	}
	Vector3 *p = pos.ptrw();
	const float *w = inv_mass.ptr();
	const Vector3 *rest = rest_pos.ptr();
	for (int k = 0; k < n; k++) {
		const uint64_t key = _cell_key((int64_t)Math::floor(p[k].x / cell), (int64_t)Math::floor(p[k].y / cell), (int64_t)Math::floor(p[k].z / cell));
		grid[key].push_back(k);
	}
	const real_t min2 = thickness * thickness;
	for (int i = 0; i < n; i++) {
		const int64_t cx = (int64_t)Math::floor(p[i].x / cell);
		const int64_t cy = (int64_t)Math::floor(p[i].y / cell);
		const int64_t cz = (int64_t)Math::floor(p[i].z / cell);
		for (int dx = -1; dx <= 1; dx++) {
			for (int dy = -1; dy <= 1; dy++) {
				for (int dz = -1; dz <= 1; dz++) {
					HashMap<uint64_t, LocalVector<int>>::Iterator it = grid.find(_cell_key(cx + dx, cy + dy, cz + dz));
					if (!it) {
						continue;
					}
					const LocalVector<int> &bucket = it->value;
					for (uint32_t bi = 0; bi < bucket.size(); bi++) {
						const int j = bucket[bi];
						if (j <= i) {
							continue;
						}
						const real_t wsum = w[i] + w[j];
						if (wsum == 0.0) {
							continue;
						}
						// Particles that start closer than the thickness are neighbours, not contacts.
						if (rest[i].distance_squared_to(rest[j]) < min2) {
							continue;
						}
						const Vector3 d = p[j] - p[i];
						const real_t l2 = d.length_squared();
						if (l2 >= min2) {
							continue;
						}
						const real_t l = Math::sqrt(l2);
						const Vector3 dir = l > EPS ? d / l : Vector3(0, 1, 0);
						const real_t corr = (thickness - l) / wsum;
						p[i] -= dir * (corr * w[i]);
						p[j] += dir * (corr * w[j]);
					}
				}
			}
		}
	}
}

bool CgameXPBDCloth::_cell_torn(int p_cell, const HashSet<int64_t> &p_torn) const {
	const int ci = p_cell % (cols - 1);
	const int cj = p_cell / (cols - 1);
	const int v00 = cj * cols + ci;
	const int v10 = v00 + 1;
	const int v01 = v00 + cols;
	const int v11 = v01 + 1;
	return p_torn.has(_edge_key(v00, v10)) || p_torn.has(_edge_key(v01, v11)) || p_torn.has(_edge_key(v00, v01)) || p_torn.has(_edge_key(v10, v11));
}

void CgameXPBDCloth::_tear() {
	HashSet<int64_t> torn;
	for (int c = 0; c < ca.size(); c++) {
		if (ckind[c] != KIND_STRETCH) {
			continue;
		}
		const real_t l = pos[ca[c]].distance_to(pos[cb[c]]);
		if (l > crest[c] * tear_threshold) {
			torn.insert(_edge_key(ca[c], cb[c]));
		}
	}
	if (torn.is_empty()) {
		return;
	}
	Vector<int> na;
	Vector<int> nb;
	Vector<int> nm;
	Vector<float> nr;
	Vector<uint8_t> nk;
	for (int c = 0; c < ca.size(); c++) {
		const int a = ca[c];
		const int b = cb[c];
		const int kind = ckind[c];
		bool dead = false;
		if (kind == KIND_STRETCH) {
			dead = torn.has(_edge_key(a, b));
		} else if (kind == KIND_BEND) {
			const int m = cmid[c];
			dead = torn.has(_edge_key(a, m)) || torn.has(_edge_key(m, b));
		} else {
			const int ci = MIN(a % cols, b % cols);
			const int cj = MIN(a / cols, b / cols);
			dead = _cell_torn(cj * (cols - 1) + ci, torn);
		}
		if (dead) {
			torn_count++;
			continue;
		}
		na.push_back(a);
		nb.push_back(b);
		nm.push_back(cmid[c]);
		nr.push_back(crest[c]);
		nk.push_back((uint8_t)kind);
	}
	ca = na;
	cb = nb;
	cmid = nm;
	crest = nr;
	ckind = nk;

	Vector<int> nt;
	Vector<int> ntc;
	for (int t = 0; t < tri_cell.size(); t++) {
		if (_cell_torn(tri_cell[t], torn)) {
			continue;
		}
		nt.push_back(tris[t * 3]);
		nt.push_back(tris[t * 3 + 1]);
		nt.push_back(tris[t * 3 + 2]);
		ntc.push_back(tri_cell[t]);
	}
	tris = nt;
	tri_cell = ntc;
}

Vector<Vector3> CgameXPBDCloth::normals() const {
	Vector<Vector3> out;
	out.resize(pos.size());
	Vector3 *o = out.ptrw();
	for (int k = 0; k < out.size(); k++) {
		o[k] = Vector3();
	}
	const Vector3 *p = pos.ptr();
	for (int t = 0; t + 2 < tris.size(); t += 3) {
		const int a = tris[t];
		const int b = tris[t + 1];
		const int c = tris[t + 2];
		const Vector3 fn = (p[b] - p[a]).cross(p[c] - p[a]);
		o[a] += fn;
		o[b] += fn;
		o[c] += fn;
	}
	for (int k = 0; k < out.size(); k++) {
		o[k] = o[k].length_squared() > EPS ? o[k].normalized() : Vector3(0, 0, 1);
	}
	return out;
}

Ref<ArrayMesh> CgameXPBDCloth::build_mesh(uint64_t p_flags) const {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	if (tris.is_empty()) {
		return mesh;
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = pos;
	arrays[Mesh::ARRAY_NORMAL] = normals();
	arrays[Mesh::ARRAY_TEX_UV] = uv;
	arrays[Mesh::ARRAY_INDEX] = tris;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, TypedArray<Array>(), Dictionary(), p_flags);
	return mesh;
}

void CgameXPBDCloth::write_vertex_buffers(const Transform3D &p_xform, uint8_t *r_positions, uint8_t *r_normals, AABB &r_aabb) const {
	const int n = pos.size();
	if (n == 0) {
		r_aabb = AABB();
		return;
	}
	const Vector<Vector3> nrm = normals();
	const Vector3 *p = pos.ptr();
	const Vector3 *nr = nrm.ptr();
	const Basis nb = p_xform.basis.inverse().transposed();
	Vector3 lo;
	Vector3 hi;
	for (int k = 0; k < n; k++) {
		const Vector3 lp = p_xform.xform(p[k]);
		const float f[3] = { (float)lp.x, (float)lp.y, (float)lp.z };
		memcpy(r_positions + k * 12, f, 12);
		if (k == 0) {
			lo = lp;
			hi = lp;
		} else {
			lo = lo.min(lp);
			hi = hi.max(lp);
		}
		const Vector3 ln = nb.xform(nr[k]).normalized();
		const Vector2 oct = ln.octahedron_encode();
		const uint16_t e[2] = {
			(uint16_t)CLAMP(oct.x * 65535, 0, 65535),
			(uint16_t)CLAMP(oct.y * 65535, 0, 65535),
		};
		memcpy(r_normals + k * 4, e, 4);
	}
	r_aabb = AABB(lo, hi - lo);
}

void CgameXPBDCloth::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &CgameXPBDCloth::set_gravity);
	ClassDB::bind_method(D_METHOD("get_gravity"), &CgameXPBDCloth::get_gravity);
	ClassDB::bind_method(D_METHOD("set_wind", "wind"), &CgameXPBDCloth::set_wind);
	ClassDB::bind_method(D_METHOD("get_wind"), &CgameXPBDCloth::get_wind);
	ClassDB::bind_method(D_METHOD("set_drag", "drag"), &CgameXPBDCloth::set_drag);
	ClassDB::bind_method(D_METHOD("get_drag"), &CgameXPBDCloth::get_drag);
	ClassDB::bind_method(D_METHOD("set_compliance_stretch", "compliance"), &CgameXPBDCloth::set_compliance_stretch);
	ClassDB::bind_method(D_METHOD("get_compliance_stretch"), &CgameXPBDCloth::get_compliance_stretch);
	ClassDB::bind_method(D_METHOD("set_compliance_shear", "compliance"), &CgameXPBDCloth::set_compliance_shear);
	ClassDB::bind_method(D_METHOD("get_compliance_shear"), &CgameXPBDCloth::get_compliance_shear);
	ClassDB::bind_method(D_METHOD("set_compliance_bend", "compliance"), &CgameXPBDCloth::set_compliance_bend);
	ClassDB::bind_method(D_METHOD("get_compliance_bend"), &CgameXPBDCloth::get_compliance_bend);
	ClassDB::bind_method(D_METHOD("set_iterations", "iterations"), &CgameXPBDCloth::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &CgameXPBDCloth::get_iterations);
	ClassDB::bind_method(D_METHOD("set_collision_margin", "margin"), &CgameXPBDCloth::set_collision_margin);
	ClassDB::bind_method(D_METHOD("get_collision_margin"), &CgameXPBDCloth::get_collision_margin);
	ClassDB::bind_method(D_METHOD("set_friction", "friction"), &CgameXPBDCloth::set_friction);
	ClassDB::bind_method(D_METHOD("get_friction"), &CgameXPBDCloth::get_friction);
	ClassDB::bind_method(D_METHOD("set_tear_threshold", "threshold"), &CgameXPBDCloth::set_tear_threshold);
	ClassDB::bind_method(D_METHOD("get_tear_threshold"), &CgameXPBDCloth::get_tear_threshold);
	ClassDB::bind_method(D_METHOD("set_self_collision_enabled", "enabled"), &CgameXPBDCloth::set_self_collision_enabled);
	ClassDB::bind_method(D_METHOD("is_self_collision_enabled"), &CgameXPBDCloth::is_self_collision_enabled);
	ClassDB::bind_method(D_METHOD("set_thickness", "thickness"), &CgameXPBDCloth::set_thickness);
	ClassDB::bind_method(D_METHOD("get_thickness"), &CgameXPBDCloth::get_thickness);
	ClassDB::bind_method(D_METHOD("get_torn_count"), &CgameXPBDCloth::get_torn_count);

	ClassDB::bind_method(D_METHOD("setup_grid", "width_cells", "height_cells", "spacing", "origin", "particle_mass"), &CgameXPBDCloth::setup_grid, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("particle_count"), &CgameXPBDCloth::particle_count);
	ClassDB::bind_method(D_METHOD("constraint_count"), &CgameXPBDCloth::constraint_count);
	ClassDB::bind_method(D_METHOD("stretch_constraint_count"), &CgameXPBDCloth::stretch_constraint_count);
	ClassDB::bind_method(D_METHOD("columns"), &CgameXPBDCloth::columns);
	ClassDB::bind_method(D_METHOD("rows"), &CgameXPBDCloth::row_count);
	ClassDB::bind_method(D_METHOD("index_of", "i", "j"), &CgameXPBDCloth::index_of);
	ClassDB::bind_method(D_METHOD("max_stretch_error"), &CgameXPBDCloth::max_stretch_error);

	ClassDB::bind_method(D_METHOD("pin", "index", "world_pos"), &CgameXPBDCloth::pin);
	ClassDB::bind_method(D_METHOD("attach", "index", "target_fn"), &CgameXPBDCloth::attach);
	ClassDB::bind_method(D_METHOD("drive", "index", "world_pos"), &CgameXPBDCloth::drive);
	ClassDB::bind_method(D_METHOD("unpin", "index"), &CgameXPBDCloth::unpin);
	ClassDB::bind_method(D_METHOD("is_pinned", "index"), &CgameXPBDCloth::is_pinned);

	ClassDB::bind_method(D_METHOD("add_sphere", "center", "radius"), &CgameXPBDCloth::add_sphere);
	ClassDB::bind_method(D_METHOD("set_sphere_center", "index", "center"), &CgameXPBDCloth::set_sphere_center);
	ClassDB::bind_method(D_METHOD("add_capsule", "a", "b", "radius"), &CgameXPBDCloth::add_capsule);
	ClassDB::bind_method(D_METHOD("set_capsule", "index", "a", "b"), &CgameXPBDCloth::set_capsule);
	ClassDB::bind_method(D_METHOD("add_plane", "normal", "offset"), &CgameXPBDCloth::add_plane);
	ClassDB::bind_method(D_METHOD("clear_colliders"), &CgameXPBDCloth::clear_colliders);

	ClassDB::bind_method(D_METHOD("set_particle", "index", "world_pos"), &CgameXPBDCloth::set_particle);
	ClassDB::bind_method(D_METHOD("positions"), &CgameXPBDCloth::positions);
	ClassDB::bind_method(D_METHOD("velocities"), &CgameXPBDCloth::velocities);
	ClassDB::bind_method(D_METHOD("triangles"), &CgameXPBDCloth::triangles);
	ClassDB::bind_method(D_METHOD("uvs"), &CgameXPBDCloth::uvs);

	ClassDB::bind_method(D_METHOD("step", "dt", "substeps"), &CgameXPBDCloth::step, DEFVAL(8));
	ClassDB::bind_method(D_METHOD("normals"), &CgameXPBDCloth::normals);
	ClassDB::bind_method(D_METHOD("build_mesh", "flags"), &CgameXPBDCloth::build_mesh, DEFVAL(0));

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "gravity", PROPERTY_HINT_NONE, "suffix:m/s²"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "wind", PROPERTY_HINT_NONE, "suffix:m/s"), "set_wind", "get_wind");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "drag", PROPERTY_HINT_RANGE, "0,20,0.001,or_greater"), "set_drag", "get_drag");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compliance_stretch", PROPERTY_HINT_RANGE, "0,1,0.000001,or_greater"), "set_compliance_stretch", "get_compliance_stretch");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compliance_shear", PROPERTY_HINT_RANGE, "0,1,0.000001,or_greater"), "set_compliance_shear", "get_compliance_shear");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "compliance_bend", PROPERTY_HINT_RANGE, "0,1,0.000001,or_greater"), "set_compliance_bend", "get_compliance_bend");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,16,1,or_greater"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_margin", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater,suffix:m"), "set_collision_margin", "get_collision_margin");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "friction", PROPERTY_HINT_RANGE, "0,1,0.001"), "set_friction", "get_friction");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tear_threshold", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), "set_tear_threshold", "get_tear_threshold");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "self_collision_enabled"), "set_self_collision_enabled", "is_self_collision_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "thickness", PROPERTY_HINT_RANGE, "0.0001,1,0.001,or_greater,suffix:m"), "set_thickness", "get_thickness");

	BIND_ENUM_CONSTANT(KIND_STRETCH);
	BIND_ENUM_CONSTANT(KIND_SHEAR);
	BIND_ENUM_CONSTANT(KIND_BEND);
}
