/**************************************************************************/
/*  cgame_pcg_nodes.cpp                                                   */
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

// Built-in node implementations, point-data helpers and example presets of CgamePCGGraph.

#include "cgame_pcg_graph.h"

#include "core/math/basis.h"
#include "core/math/math_funcs.h"
#include "core/math/transform_3d.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"

#ifdef MODULE_NOISE_ENABLED
#include "modules/noise/fastnoise_lite.h"
#endif

#include <initializer_list>
#include <utility>

namespace {

const char *T_POINTS = "points";
const char *T_SPLINE = "spline";
const char *T_VOLUME = "volume";
const char *T_LANDSCAPE = "landscape";
const char *T_MESHES = "mesh_instances";
const char *T_SCENES = "scene_instances";
const char *T_LAYER = "layer_weights";

Dictionary make_pins(std::initializer_list<std::pair<const char *, const char *>> p_pins) {
	Dictionary d;
	for (const std::pair<const char *, const char *> &p : p_pins) {
		d[String(p.first)] = String(p.second);
	}
	return d;
}

double fparam(const Dictionary &p_params, const char *p_key, double p_default) {
	return (double)p_params.get(p_key, p_default);
}

// Saturating double -> int64 conversion (GDScript int() of a float).
int64_t dbl_to_int(double p_value) {
	if (Math::is_nan(p_value)) {
		return 0;
	}
	if (p_value >= 9.2233720368547758e18) {
		return INT64_MAX;
	}
	if (p_value <= -9.2233720368547758e18) {
		return INT64_MIN;
	}
	return (int64_t)p_value;
}

int64_t grid_key(int p_ix, int p_iy, int p_iz) {
	return ((int64_t)p_ix & 0x1FFFFF) | (((int64_t)p_iy & 0x1FFFFF) << 21) | (((int64_t)p_iz & 0x1FFFFF) << 42);
}

Vector3i cell_of(const Vector3 &p_point, double p_cell, bool p_planar) {
	return Vector3i((int)Math::floor(p_point.x / p_cell), p_planar ? 0 : (int)Math::floor(p_point.y / p_cell), (int)Math::floor(p_point.z / p_cell));
}

typedef HashMap<int64_t, Vector<int>> SpatialGrid;

void grid_add(SpatialGrid &r_grid, const Vector3 &p_point, int p_idx, double p_cell, bool p_planar) {
	const Vector3i c = cell_of(p_point, p_cell, p_planar);
	r_grid[grid_key(c.x, c.y, c.z)].push_back(p_idx);
}

bool grid_near(const SpatialGrid &p_grid, const Vector3 *p_pos, const Vector3 &p_point, double p_dist, double p_cell, bool p_planar) {
	const Vector3i c = cell_of(p_point, p_cell, p_planar);
	const double d2 = p_dist * p_dist;
	const int ylo = p_planar ? 0 : -1;
	const int yhi = p_planar ? 0 : 1;
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = ylo; dy <= yhi; dy++) {
			for (int dz = -1; dz <= 1; dz++) {
				const SpatialGrid::ConstIterator it = p_grid.find(grid_key(c.x + dx, c.y + dy, c.z + dz));
				if (!it) {
					continue;
				}
				for (const int i : it->value) {
					const Vector3 q = p_pos[i];
					double dd;
					if (p_planar) {
						dd = ((double)q.x - (double)p_point.x) * ((double)q.x - (double)p_point.x) + ((double)q.z - (double)p_point.z) * ((double)q.z - (double)p_point.z);
					} else {
						dd = (double)q.distance_squared_to(p_point);
					}
					if (dd < d2) {
						return true;
					}
				}
			}
		}
	}
	return false;
}

struct PruneOrder {
	const float *dens;
	const int64_t *seeds;
	bool operator()(int p_a, int p_b) const {
		if (dens[p_a] != dens[p_b]) {
			return dens[p_a] > dens[p_b];
		}
		if (seeds[p_a] != seeds[p_b]) {
			return seeds[p_a] > seeds[p_b];
		}
		return p_a < p_b;
	}
};

} // namespace

// ---------------------------------------------------------------- registration

void CgamePCGGraph::_register_builtins() {
	_reg("surface_sampler", make_pins({ { "volume", T_VOLUME }, { "landscape", T_LANDSCAPE } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_SURFACE_SAMPLER);
	_reg("spline_sampler", make_pins({ { "spline", T_SPLINE }, { "landscape", T_LANDSCAPE } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_SPLINE_SAMPLER);
	_reg("volume_sampler", make_pins({ { "volume", T_VOLUME } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_VOLUME_SAMPLER);
	_reg("density_noise", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_DENSITY_NOISE);
	_reg("density_filter", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_DENSITY_FILTER);
	_reg("self_pruning", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_SELF_PRUNING);
	_reg("difference", make_pins({ { "in", T_POINTS }, { "other", "points[]" } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_DIFFERENCE);
	_reg("transform_points", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_TRANSFORM_POINTS);
	_reg("attribute_set", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_ATTRIBUTE_SET);
	_reg("merge", make_pins({ { "in", "points[]" } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_MERGE);
	_reg("partition_by_attribute", make_pins({ { "in", T_POINTS } }), make_pins({ { "below", T_POINTS }, { "above", T_POINTS } }), Callable(), BUILTIN_PARTITION_BY_ATTRIBUTE);
	_reg("copy_points", make_pins({ { "source", T_POINTS }, { "target", T_POINTS } }), make_pins({ { "out", T_POINTS } }), Callable(), BUILTIN_COPY_POINTS);
	_reg("constant_volume", Dictionary(), make_pins({ { "out", T_VOLUME } }), Callable(), BUILTIN_CONSTANT_VOLUME);
	_reg("static_mesh_spawner", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_MESHES } }), Callable(), BUILTIN_STATIC_MESH_SPAWNER);
	_reg("instanced_scene_output", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_SCENES } }), Callable(), BUILTIN_INSTANCED_SCENE_OUTPUT);
	_reg("material_layer_output", make_pins({ { "in", T_POINTS } }), make_pins({ { "out", T_LAYER } }), Callable(), BUILTIN_MATERIAL_LAYER_OUTPUT);
}

Dictionary CgamePCGGraph::_exec_builtin(Builtin p_builtin, const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	switch (p_builtin) {
		case BUILTIN_SURFACE_SAMPLER:
			return _n_surface_sampler(p_inputs, p_params, p_ctx);
		case BUILTIN_SPLINE_SAMPLER:
			return _n_spline_sampler(p_inputs, p_params, p_ctx);
		case BUILTIN_VOLUME_SAMPLER:
			return _n_volume_sampler(p_inputs, p_params, p_ctx);
		case BUILTIN_DENSITY_NOISE:
			return _n_density_noise(p_inputs, p_params, p_ctx);
		case BUILTIN_DENSITY_FILTER:
			return _n_density_filter(p_inputs, p_params, p_ctx);
		case BUILTIN_SELF_PRUNING:
			return _n_self_pruning(p_inputs, p_params, p_ctx);
		case BUILTIN_DIFFERENCE:
			return _n_difference(p_inputs, p_params, p_ctx);
		case BUILTIN_TRANSFORM_POINTS:
			return _n_transform_points(p_inputs, p_params, p_ctx);
		case BUILTIN_ATTRIBUTE_SET:
			return _n_attribute_set(p_inputs, p_params, p_ctx);
		case BUILTIN_MERGE:
			return _n_merge(p_inputs, p_params, p_ctx);
		case BUILTIN_PARTITION_BY_ATTRIBUTE:
			return _n_partition_by_attribute(p_inputs, p_params, p_ctx);
		case BUILTIN_COPY_POINTS:
			return _n_copy_points(p_inputs, p_params, p_ctx);
		case BUILTIN_CONSTANT_VOLUME:
			return _n_constant_volume(p_inputs, p_params, p_ctx);
		case BUILTIN_STATIC_MESH_SPAWNER:
			return _n_static_mesh_spawner(p_inputs, p_params, p_ctx);
		case BUILTIN_INSTANCED_SCENE_OUTPUT:
			return _n_instanced_scene_output(p_inputs, p_params, p_ctx);
		case BUILTIN_MATERIAL_LAYER_OUTPUT:
			return _n_material_layer_output(p_inputs, p_params, p_ctx);
		default:
			return Dictionary();
	}
}

// ---------------------------------------------------------------- point data helpers

Dictionary CgamePCGGraph::_assemble(const PackedVector3Array &p_pos, const PackedFloat32Array &p_dens, const PackedFloat32Array &p_scl, const PackedFloat32Array &p_rot, const PackedInt64Array &p_sd, const Dictionary &p_extras) {
	Dictionary attrs;
	attrs["density"] = p_dens;
	attrs["scale"] = p_scl;
	attrs["rotation_y"] = p_rot;
	attrs["seed"] = p_sd;
	const Array keys = p_extras.keys();
	for (int i = 0; i < keys.size(); i++) {
		attrs[keys[i]] = p_extras[keys[i]];
	}
	Dictionary d;
	d["type"] = T_POINTS;
	d["positions"] = p_pos;
	d["attrs"] = attrs;
	return d;
}

Dictionary CgamePCGGraph::_empty_points() {
	return _assemble(PackedVector3Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt64Array(), Dictionary());
}

Dictionary CgamePCGGraph::_in_pts(const Dictionary &p_inputs, const StringName &p_pin) {
	const Variant v = p_inputs.get(p_pin, Variant());
	if (v.get_type() == Variant::DICTIONARY) {
		const Dictionary d = v;
		if (String(d.get("type", "")) == T_POINTS) {
			return d;
		}
	}
	return _empty_points();
}

Dictionary CgamePCGGraph::_select(const Dictionary &p_pts, const Vector<int> &p_idx) {
	const PackedVector3Array pos = p_pts["positions"];
	const Dictionary attrs = p_pts["attrs"];
	PackedVector3Array npos;
	npos.resize(p_idx.size());
	for (int j = 0; j < p_idx.size(); j++) {
		npos.set(j, pos[p_idx[j]]);
	}
	Dictionary out_attrs;
	const Array keys = attrs.keys();
	for (int k = 0; k < keys.size(); k++) {
		const Variant src = attrs[keys[k]];
		if (src.get_type() == Variant::PACKED_INT64_ARRAY) {
			const PackedInt64Array si = src;
			PackedInt64Array di;
			di.resize(p_idx.size());
			for (int j = 0; j < p_idx.size(); j++) {
				di.set(j, si[p_idx[j]]);
			}
			out_attrs[keys[k]] = di;
		} else if (src.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
			const PackedFloat32Array sf = src;
			PackedFloat32Array df;
			df.resize(p_idx.size());
			for (int j = 0; j < p_idx.size(); j++) {
				df.set(j, sf[p_idx[j]]);
			}
			out_attrs[keys[k]] = df;
		}
	}
	Dictionary d;
	d["type"] = T_POINTS;
	d["positions"] = npos;
	d["attrs"] = out_attrs;
	return d;
}

double CgamePCGGraph::_attr_f(const Dictionary &p_attrs, const StringName &p_name, int p_i) {
	const Variant v = p_attrs.get(p_name, Variant());
	if (v.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
		const PackedFloat32Array pf = v;
		return pf[p_i];
	}
	if (v.get_type() == Variant::PACKED_INT64_ARRAY) {
		const PackedInt64Array pi = v;
		return (double)pi[p_i];
	}
	return 0.0;
}

bool CgamePCGGraph::_in_rect(const Rect2 &p_rect, double p_x, double p_z) {
	return p_x >= (double)p_rect.position.x && p_x < (double)p_rect.position.x + (double)p_rect.size.x && p_z >= (double)p_rect.position.y && p_z < (double)p_rect.position.y + (double)p_rect.size.y;
}

// Sampling area in xz: the volume (when given) intersected with the partition cell.
Rect2 CgamePCGGraph::_area(const AABB &p_box, const Dictionary &p_ctx, bool p_use_box) {
	double lox = -BIG;
	double loz = -BIG;
	double hix = BIG;
	double hiz = BIG;
	if (p_use_box) {
		lox = p_box.position.x;
		loz = p_box.position.z;
		hix = p_box.position.x + p_box.size.x;
		hiz = p_box.position.z + p_box.size.z;
	}
	if ((bool)p_ctx.get("has_bounds", false)) {
		const AABB b = p_ctx["bounds"];
		lox = MAX(lox, (double)b.position.x);
		loz = MAX(loz, (double)b.position.z);
		hix = MIN(hix, (double)b.position.x + (double)b.size.x);
		hiz = MIN(hiz, (double)b.position.z + (double)b.size.z);
	}
	return Rect2((real_t)lox, (real_t)loz, (real_t)MAX(hix - lox, 0.0), (real_t)MAX(hiz - loz, 0.0));
}

Variant CgamePCGGraph::_crop(const Variant &p_data, const Rect2 &p_rect) {
	if (p_data.get_type() != Variant::DICTIONARY) {
		return p_data;
	}
	const Dictionary dd = p_data;
	const String t = String(dd.get("type", ""));
	if (t == T_POINTS) {
		const PackedVector3Array pos = dd["positions"];
		Vector<int> idx;
		for (int i = 0; i < pos.size(); i++) {
			if (_in_rect(p_rect, pos[i].x, pos[i].z)) {
				idx.push_back(i);
			}
		}
		return _select(dd, idx);
	}
	if (t == T_LAYER) {
		const PackedVector3Array lp = dd["positions"];
		const PackedFloat32Array lw = dd["weights"];
		PackedVector3Array np;
		PackedFloat32Array nw;
		for (int i = 0; i < lp.size(); i++) {
			if (_in_rect(p_rect, lp[i].x, lp[i].z)) {
				np.push_back(lp[i]);
				nw.push_back(lw[i]);
			}
		}
		Dictionary d;
		d["type"] = T_LAYER;
		d["layer"] = dd["layer"];
		d["positions"] = np;
		d["weights"] = nw;
		return d;
	}
	if (t == T_MESHES || t == T_SCENES) {
		const Array recs = dd["records"];
		Array out_recs;
		for (int i = 0; i < recs.size(); i++) {
			const Dictionary r = recs[i];
			const Array trs = r["transforms"];
			Array kept;
			for (int k = 0; k < trs.size(); k++) {
				const Transform3D tr = trs[k];
				if (_in_rect(p_rect, tr.origin.x, tr.origin.z)) {
					kept.push_back(tr);
				}
			}
			Dictionary nr = r.duplicate();
			nr["transforms"] = kept;
			out_recs.push_back(nr);
		}
		Dictionary d;
		d["type"] = t;
		d["records"] = out_recs;
		return d;
	}
	return p_data;
}

Transform3D CgamePCGGraph::_point_transform(const Vector3 &p_pos, double p_scale, double p_yaw) {
	const Basis b = Basis(Vector3(0, 1, 0), (real_t)p_yaw).scaled(Vector3(1, 1, 1) * (real_t)p_scale);
	return Transform3D(b, p_pos);
}

// ---------------------------------------------------------------- built-in nodes

Dictionary CgamePCGGraph::_n_constant_volume(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Vector3 c = p_params.get("center", Vector3());
	const Vector3 s = p_params.get("size", Vector3(10, 10, 10));
	Dictionary out;
	out["out"] = make_volume(AABB(c - s * 0.5f, s));
	return out;
}

Dictionary CgamePCGGraph::_n_surface_sampler(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	Dictionary result;
	const Variant vol = p_inputs.get("volume", Variant());
	if (vol.get_type() != Variant::DICTIONARY) {
		result["out"] = _empty_points();
		return result;
	}
	const Dictionary vd = vol;
	const AABB box = vd["aabb"];
	const double spacing = MAX(fparam(p_params, "spacing", 2.0), 0.05);
	const double jitter = CLAMP(fparam(p_params, "jitter", 0.5), 0.0, 1.0);
	const double base_density = fparam(p_params, "density", 1.0);
	const int64_t ns = p_ctx["node_seed"];
	const Rect2 area = _area(box, p_ctx, true);
	const Variant ls = p_inputs.get("landscape", Variant());
	PackedVector3Array pos;
	PackedFloat32Array dens;
	PackedFloat32Array scl;
	PackedFloat32Array rot;
	PackedInt64Array sd;
	PackedFloat32Array slope;
	if (area.size.x > 0.0 && area.size.y > 0.0) {
		const int ix0 = (int)Math::floor((double)area.position.x / spacing) - 1;
		const int ix1 = (int)Math::ceil(((double)area.position.x + (double)area.size.x) / spacing) + 1;
		const int iz0 = (int)Math::floor((double)area.position.y / spacing) - 1;
		const int iz1 = (int)Math::ceil(((double)area.position.y + (double)area.size.y) / spacing) + 1;
		for (int ix = ix0; ix <= ix1; ix++) {
			for (int iz = iz0; iz <= iz1; iz++) {
				const int64_t h = hash3(ns, ix, iz);
				const double x = ((double)ix + 0.5 + (rand01(mix64(h + 1)) - 0.5) * jitter) * spacing;
				const double z = ((double)iz + 0.5 + (rand01(mix64(h + 2)) - 0.5) * jitter) * spacing;
				if (!_in_rect(area, x, z)) {
					continue;
				}
				const double y = landscape_height(ls, x, z, box.position.y);
				pos.push_back(Vector3((real_t)x, (real_t)y, (real_t)z));
				dens.push_back((float)base_density);
				scl.push_back(1.0f);
				rot.push_back(0.0f);
				sd.push_back(h);
				slope.push_back(landscape_normal(ls, x, z).y);
			}
		}
	}
	Dictionary extras;
	extras["slope"] = slope;
	result["out"] = _assemble(pos, dens, scl, rot, sd, extras);
	return result;
}

Dictionary CgamePCGGraph::_n_volume_sampler(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	Dictionary result;
	const Variant vol = p_inputs.get("volume", Variant());
	if (vol.get_type() != Variant::DICTIONARY) {
		result["out"] = _empty_points();
		return result;
	}
	const Dictionary vd = vol;
	const AABB box = vd["aabb"];
	const double spacing = MAX(fparam(p_params, "spacing", 2.0), 0.05);
	const double jitter = CLAMP(fparam(p_params, "jitter", 0.5), 0.0, 1.0);
	const int64_t ns = p_ctx["node_seed"];
	const Rect2 area = _area(box, p_ctx, true);
	PackedVector3Array pos;
	PackedFloat32Array dens;
	PackedFloat32Array scl;
	PackedFloat32Array rot;
	PackedInt64Array sd;
	if (area.size.x > 0.0 && area.size.y > 0.0) {
		const double box_end_y = (double)box.position.y + (double)box.size.y;
		const int iy0 = (int)Math::floor((double)box.position.y / spacing) - 1;
		const int iy1 = (int)Math::ceil(box_end_y / spacing) + 1;
		const int ix0 = (int)Math::floor((double)area.position.x / spacing) - 1;
		const int ix1 = (int)Math::ceil(((double)area.position.x + (double)area.size.x) / spacing) + 1;
		const int iz0 = (int)Math::floor((double)area.position.y / spacing) - 1;
		const int iz1 = (int)Math::ceil(((double)area.position.y + (double)area.size.y) / spacing) + 1;
		for (int ix = ix0; ix <= ix1; ix++) {
			for (int iy = iy0; iy <= iy1; iy++) {
				for (int iz = iz0; iz <= iz1; iz++) {
					const int64_t h = mix64(hash3(ns, ix, iz) ^ iy);
					const Vector3 p(
							(real_t)(((double)ix + 0.5 + (rand01(mix64(h + 1)) - 0.5) * jitter) * spacing),
							(real_t)(((double)iy + 0.5 + (rand01(mix64(h + 2)) - 0.5) * jitter) * spacing),
							(real_t)(((double)iz + 0.5 + (rand01(mix64(h + 3)) - 0.5) * jitter) * spacing));
					if (!_in_rect(area, p.x, p.z) || (double)p.y < (double)box.position.y || (double)p.y >= box_end_y) {
						continue;
					}
					pos.push_back(p);
					dens.push_back(1.0f);
					scl.push_back(1.0f);
					rot.push_back(0.0f);
					sd.push_back(h);
				}
			}
		}
	}
	result["out"] = _assemble(pos, dens, scl, rot, sd, Dictionary());
	return result;
}

// mode "along": a point every `spacing` metres at `lateral_offset` from the path.
// mode "around": per step, one point on each side at a random distance in [band_inner, band_outer].
Dictionary CgamePCGGraph::_n_spline_sampler(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	Dictionary result;
	const Variant sp = p_inputs.get("spline", Variant());
	if (sp.get_type() != Variant::DICTIONARY) {
		result["out"] = _empty_points();
		return result;
	}
	const Dictionary sd_ = sp;
	PackedVector3Array line = sd_["points"];
	if ((bool)sd_.get("closed", false) && line.size() > 1) {
		line = line.duplicate();
		line.push_back(line[0]);
	}
	const double spacing = MAX(fparam(p_params, "spacing", 2.0), 0.05);
	const String mode = String(p_params.get("mode", "along"));
	const double lateral = fparam(p_params, "lateral_offset", 0.0);
	const double inner = fparam(p_params, "band_inner", 1.0);
	const double outer = fparam(p_params, "band_outer", 4.0);
	const int64_t ns = p_ctx["node_seed"];
	const Rect2 area = _area(AABB(), p_ctx, false);
	const Variant ls = p_inputs.get("landscape", Variant());
	const bool use_land = ls.get_type() == Variant::DICTIONARY;
	PackedVector3Array pos;
	PackedFloat32Array dens;
	PackedFloat32Array scl;
	PackedFloat32Array rot;
	PackedInt64Array sd;
	if (line.size() >= 2) {
		double total = 0.0;
		Vector<float> cum;
		cum.push_back(0.0f);
		for (int i = 1; i < line.size(); i++) {
			total += line[i - 1].distance_to(line[i]);
			cum.push_back((float)total);
		}
		int seg = 0;
		const int steps = (int)Math::floor(total / spacing);
		for (int k = 0; k <= steps; k++) {
			const double s = (double)k * spacing;
			while (seg < line.size() - 2 && (double)cum[seg + 1] < s) {
				seg++;
			}
			const double seg_len = (double)cum[seg + 1] - (double)cum[seg];
			const double f = seg_len <= 0.0 ? 0.0 : (s - (double)cum[seg]) / seg_len;
			const Vector3 p = line[seg].lerp(line[seg + 1], (real_t)f);
			Vector3 tangent(line[seg + 1].x - line[seg].x, 0.0f, line[seg + 1].z - line[seg].z);
			tangent = tangent.length() > 0.0001 ? tangent.normalized() : Vector3(1, 0, 0);
			const Vector3 side(-tangent.z, 0.0f, tangent.x);
			const double yaw = Math::atan2((double)tangent.x, (double)tangent.z);
			Vector<double> offs;
			if (mode == "around") {
				const int64_t h = hash3(ns, k, 0);
				offs.push_back(Math::lerp(inner, outer, rand01(mix64(h + 1))));
				offs.push_back(-Math::lerp(inner, outer, rand01(mix64(h + 2))));
			} else {
				offs.push_back(lateral);
			}
			int side_i = 0;
			for (const double o : offs) {
				Vector3 q = p + side * (real_t)o;
				side_i++;
				if (!_in_rect(area, q.x, q.z)) {
					continue;
				}
				if (use_land) {
					q.y = (real_t)landscape_height(ls, q.x, q.z, q.y);
				}
				pos.push_back(q);
				dens.push_back(1.0f);
				scl.push_back(1.0f);
				rot.push_back((float)yaw);
				sd.push_back(hash3(ns, k, side_i));
			}
		}
	}
	result["out"] = _assemble(pos, dens, scl, rot, sd, Dictionary());
	return result;
}

Dictionary CgamePCGGraph::_n_density_noise(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const Dictionary attrs = pts["attrs"];
	PackedFloat32Array dens = PackedFloat32Array(attrs["density"]).duplicate();
	const int64_t ns = p_ctx["node_seed"];
	const double frequency = fparam(p_params, "frequency", 0.05);
	const double lo = fparam(p_params, "min_value", 0.0);
	const double hi = fparam(p_params, "max_value", 1.0);
	const bool multiply = String(p_params.get("mode", "set")) == "multiply";
#ifdef MODULE_NOISE_ENABLED
	Ref<FastNoiseLite> noise;
	noise.instantiate();
	noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	noise->set_seed((int)(ns & 0x7FFFFFFF));
	noise->set_frequency((real_t)frequency);
#endif
	for (int i = 0; i < pos.size(); i++) {
#ifdef MODULE_NOISE_ENABLED
		const double n = ((double)noise->get_noise_2d(pos[i].x, pos[i].z) + 1.0) * 0.5;
#else
		// Fallback when the noise module is disabled: deterministic hash value noise.
		const double n = rand01(hash3(ns, (int64_t)Math::floor(pos[i].x * frequency), (int64_t)Math::floor(pos[i].z * frequency)));
#endif
		const double v = Math::lerp(lo, hi, CLAMP(n, 0.0, 1.0));
		dens.set(i, (float)(multiply ? (double)dens[i] * v : v));
	}
	Dictionary out_attrs = attrs.duplicate();
	out_attrs["density"] = dens;
	Dictionary d;
	d["type"] = T_POINTS;
	d["positions"] = pos;
	d["attrs"] = out_attrs;
	Dictionary result;
	result["out"] = d;
	return result;
}

Dictionary CgamePCGGraph::_n_density_filter(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const Dictionary attrs = pts["attrs"];
	const PackedFloat32Array dens = attrs["density"];
	const double lo = fparam(p_params, "min", 0.0);
	const double hi = fparam(p_params, "max", 1.0);
	const bool invert = p_params.get("invert", false);
	Vector<int> idx;
	for (int i = 0; i < dens.size(); i++) {
		const bool inside = (double)dens[i] >= lo && (double)dens[i] <= hi;
		if (inside != invert) {
			idx.push_back(i);
		}
	}
	Dictionary result;
	result["out"] = _select(pts, idx);
	return result;
}

// Greedy min-distance pruning; the highest density (then seed) point wins, so the result is
// independent of point order.
Dictionary CgamePCGGraph::_n_self_pruning(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const Dictionary attrs = pts["attrs"];
	const PackedFloat32Array dens = attrs["density"];
	const PackedInt64Array seeds = attrs["seed"];
	const double dist = MAX(fparam(p_params, "min_distance", 1.0), 0.001);
	const bool planar = p_params.get("planar", false);
	Vector<int> order;
	order.resize(pos.size());
	for (int i = 0; i < pos.size(); i++) {
		order.write[i] = i;
	}
	PruneOrder cmp{ dens.ptr(), seeds.ptr() };
	order.sort_custom<PruneOrder>(cmp);
	SpatialGrid grid;
	Vector<Vector3> kept_pos;
	Vector<int> keep;
	for (const int i : order) {
		if (grid_near(grid, kept_pos.ptr(), pos[i], dist, dist, planar)) {
			continue;
		}
		grid_add(grid, pos[i], kept_pos.size(), dist, planar);
		kept_pos.push_back(pos[i]);
		keep.push_back(i);
	}
	keep.sort();
	Dictionary result;
	result["out"] = _select(pts, keep);
	return result;
}

Dictionary CgamePCGGraph::_n_difference(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const double dist = MAX(fparam(p_params, "distance", 1.0), 0.001);
	const bool planar = p_params.get("planar", true);
	PackedVector3Array others_pos;
	const Array others = p_inputs.get("other", Array());
	for (int i = 0; i < others.size(); i++) {
		if (others[i].get_type() == Variant::DICTIONARY) {
			const Dictionary od = others[i];
			if (String(od.get("type", "")) == T_POINTS) {
				others_pos.append_array(od["positions"]);
			}
		}
	}
	SpatialGrid grid;
	for (int j = 0; j < others_pos.size(); j++) {
		grid_add(grid, others_pos[j], j, dist, planar);
	}
	Vector<int> keep;
	for (int i = 0; i < pos.size(); i++) {
		if (!grid_near(grid, others_pos.ptr(), pos[i], dist, dist, planar)) {
			keep.push_back(i);
		}
	}
	Dictionary result;
	result["out"] = _select(pts, keep);
	return result;
}

Dictionary CgamePCGGraph::_n_transform_points(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const Dictionary attrs = pts["attrs"];
	PackedFloat32Array scl = PackedFloat32Array(attrs["scale"]).duplicate();
	PackedFloat32Array rot = PackedFloat32Array(attrs["rotation_y"]).duplicate();
	const PackedInt64Array seeds = attrs["seed"];
	const double smin = fparam(p_params, "scale_min", 1.0);
	const double smax = fparam(p_params, "scale_max", 1.0);
	const double rmin = Math::deg_to_rad(fparam(p_params, "rot_min_deg", 0.0));
	const double rmax = Math::deg_to_rad(fparam(p_params, "rot_max_deg", 360.0));
	const int64_t ns = p_ctx["node_seed"];
	for (int i = 0; i < scl.size(); i++) {
		const int64_t h = mix64(seeds[i] ^ ns);
		scl.set(i, (float)((double)scl[i] * Math::lerp(smin, smax, rand01(mix64(h + 1)))));
		rot.set(i, (float)((double)rot[i] + Math::lerp(rmin, rmax, rand01(mix64(h + 2)))));
	}
	Dictionary out_attrs = attrs.duplicate();
	out_attrs["scale"] = scl;
	out_attrs["rotation_y"] = rot;
	Dictionary d;
	d["type"] = T_POINTS;
	d["positions"] = pts["positions"];
	d["attrs"] = out_attrs;
	Dictionary result;
	result["out"] = d;
	return result;
}

// params: name (density/scale/rotation_y/custom), value, op (set/add/mul), source (constant/height).
Dictionary CgamePCGGraph::_n_attribute_set(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const Dictionary attrs = pts["attrs"];
	const String attr_name = String(p_params.get("name", "custom"));
	const String op = String(p_params.get("op", "set"));
	const bool from_height = String(p_params.get("source", "constant")) == "height";
	const double value = fparam(p_params, "value", 0.0);
	PackedFloat32Array arr;
	if (attrs.has(attr_name) && ((Variant)attrs[attr_name]).get_type() == Variant::PACKED_FLOAT32_ARRAY) {
		arr = PackedFloat32Array(attrs[attr_name]).duplicate();
	} else {
		arr.resize(pos.size());
		arr.fill(0.0f);
	}
	for (int i = 0; i < pos.size(); i++) {
		const double v = from_height ? value * (double)pos[i].y : value;
		if (op == "add") {
			arr.set(i, (float)((double)arr[i] + v));
		} else if (op == "mul") {
			arr.set(i, (float)((double)arr[i] * v));
		} else {
			arr.set(i, (float)v);
		}
	}
	Dictionary out_attrs = attrs.duplicate();
	out_attrs[attr_name] = arr;
	Dictionary d;
	d["type"] = T_POINTS;
	d["positions"] = pos;
	d["attrs"] = out_attrs;
	Dictionary result;
	result["out"] = d;
	return result;
}

Dictionary CgamePCGGraph::_n_merge(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Array sets = p_inputs.get("in", Array());
	PackedVector3Array pos;
	PackedFloat32Array dens;
	PackedFloat32Array scl;
	PackedFloat32Array rot;
	PackedInt64Array sd;
	Vector<String> custom_keys;
	for (int i = 0; i < sets.size(); i++) {
		if (sets[i].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary s = sets[i];
		if (String(s.get("type", "")) != T_POINTS) {
			continue;
		}
		const Dictionary a = s["attrs"];
		const Array keys = a.keys();
		for (int k = 0; k < keys.size(); k++) {
			const String key = keys[k];
			if (key != "density" && key != "scale" && key != "rotation_y" && key != "seed" && !custom_keys.has(key)) {
				custom_keys.push_back(key);
			}
		}
	}
	Dictionary extras;
	for (const String &k : custom_keys) {
		extras[k] = PackedFloat32Array();
	}
	for (int i = 0; i < sets.size(); i++) {
		if (sets[i].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary d = sets[i];
		if (String(d.get("type", "")) != T_POINTS) {
			continue;
		}
		const PackedVector3Array p = d["positions"];
		const Dictionary a = d["attrs"];
		pos.append_array(p);
		dens.append_array(a["density"]);
		scl.append_array(a["scale"]);
		rot.append_array(a["rotation_y"]);
		sd.append_array(a["seed"]);
		for (const String &k : custom_keys) {
			PackedFloat32Array ea = extras[k];
			if (a.has(k)) {
				ea.append_array(a[k]);
			} else {
				PackedFloat32Array pad;
				pad.resize(p.size());
				pad.fill(0.0f);
				ea.append_array(pad);
			}
			extras[k] = ea;
		}
	}
	Dictionary result;
	result["out"] = _assemble(pos, dens, scl, rot, sd, extras);
	return result;
}

// Splits points on attribute >= threshold ("above") versus < threshold ("below").
Dictionary CgamePCGGraph::_n_partition_by_attribute(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const Dictionary attrs = pts["attrs"];
	const PackedVector3Array pos = pts["positions"];
	const String attr_name = String(p_params.get("attribute", "density"));
	const double thr = fparam(p_params, "threshold", 0.5);
	Vector<int> lo;
	Vector<int> hi;
	for (int i = 0; i < pos.size(); i++) {
		if (_attr_f(attrs, attr_name, i) >= thr) {
			hi.push_back(i);
		} else {
			lo.push_back(i);
		}
	}
	Dictionary result;
	result["below"] = _select(pts, lo);
	result["above"] = _select(pts, hi);
	return result;
}

// Instances every source point onto every target point (target scale/yaw applied).
Dictionary CgamePCGGraph::_n_copy_points(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary src = _in_pts(p_inputs, "source");
	const Dictionary tgt = _in_pts(p_inputs, "target");
	const PackedVector3Array sp = src["positions"];
	const Dictionary sa = src["attrs"];
	const PackedVector3Array tp = tgt["positions"];
	const Dictionary ta = tgt["attrs"];
	PackedVector3Array pos;
	PackedFloat32Array dens;
	PackedFloat32Array scl;
	PackedFloat32Array rot;
	PackedInt64Array sd;
	for (int t = 0; t < tp.size(); t++) {
		const double t_scale = _attr_f(ta, "scale", t);
		const double t_rot = _attr_f(ta, "rotation_y", t);
		const Basis basis(Vector3(0, 1, 0), (real_t)t_rot);
		for (int s = 0; s < sp.size(); s++) {
			pos.push_back(tp[t] + basis.xform(sp[s] * (real_t)t_scale));
			dens.push_back((float)(_attr_f(ta, "density", t) * _attr_f(sa, "density", s)));
			scl.push_back((float)(t_scale * _attr_f(sa, "scale", s)));
			rot.push_back((float)(t_rot + _attr_f(sa, "rotation_y", s)));
			sd.push_back(hash3(dbl_to_int(_attr_f(ta, "seed", t)), dbl_to_int(_attr_f(sa, "seed", s)), 7));
		}
	}
	Dictionary result;
	result["out"] = _assemble(pos, dens, scl, rot, sd, Dictionary());
	return result;
}

// params: mesh_id, or meshes: [{id, weight}] chosen per point by seed. Output records {mesh_id, transforms}.
Dictionary CgamePCGGraph::_n_static_mesh_spawner(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const Dictionary attrs = pts["attrs"];
	const int64_t ns = p_ctx["node_seed"];
	Array meshes = p_params.get("meshes", Array());
	if (meshes.is_empty()) {
		Dictionary m;
		m["id"] = String(p_params.get("mesh_id", "mesh"));
		m["weight"] = 1.0;
		meshes.push_back(m);
	}
	double total_w = 0.0;
	for (int i = 0; i < meshes.size(); i++) {
		const Dictionary m = meshes[i];
		total_w += (double)m.get("weight", 1.0);
	}
	Dictionary buckets;
	Vector<String> order;
	for (int i = 0; i < meshes.size(); i++) {
		const Dictionary m = meshes[i];
		const String mid = String(m["id"]);
		if (!buckets.has(mid)) {
			buckets[mid] = Array();
			order.push_back(mid);
		}
	}
	for (int i = 0; i < pos.size(); i++) {
		const double roll = rand01(mix64(dbl_to_int(_attr_f(attrs, "seed", i)) ^ ns)) * total_w;
		String chosen = order[0];
		double acc = 0.0;
		for (int k = 0; k < meshes.size(); k++) {
			const Dictionary m = meshes[k];
			acc += (double)m.get("weight", 1.0);
			if (roll < acc) {
				chosen = String(m["id"]);
				break;
			}
		}
		Array list = buckets[chosen];
		list.push_back(_point_transform(pos[i], _attr_f(attrs, "scale", i), _attr_f(attrs, "rotation_y", i)));
	}
	Array records;
	for (const String &mid : order) {
		Dictionary r;
		r["mesh_id"] = mid;
		r["transforms"] = buckets[mid];
		records.push_back(r);
	}
	Dictionary d;
	d["type"] = T_MESHES;
	d["records"] = records;
	Dictionary result;
	result["out"] = d;
	return result;
}

Dictionary CgamePCGGraph::_n_instanced_scene_output(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const Dictionary attrs = pts["attrs"];
	Array trs;
	for (int i = 0; i < pos.size(); i++) {
		trs.push_back(_point_transform(pos[i], _attr_f(attrs, "scale", i), _attr_f(attrs, "rotation_y", i)));
	}
	Dictionary rec;
	rec["scene_path"] = String(p_params.get("scene_path", ""));
	rec["transforms"] = trs;
	Array records;
	records.push_back(rec);
	Dictionary d;
	d["type"] = T_SCENES;
	d["records"] = records;
	Dictionary result;
	result["out"] = d;
	return result;
}

// Writes one weight per point to a named material/paint layer (weight = attribute * strength).
Dictionary CgamePCGGraph::_n_material_layer_output(const Dictionary &p_inputs, const Dictionary &p_params, const Dictionary &p_ctx) const {
	const Dictionary pts = _in_pts(p_inputs, "in");
	const PackedVector3Array pos = pts["positions"];
	const Dictionary attrs = pts["attrs"];
	const String src = String(p_params.get("attribute", "density"));
	const double strength = fparam(p_params, "strength", 1.0);
	PackedFloat32Array w;
	w.resize(pos.size());
	for (int i = 0; i < pos.size(); i++) {
		w.set(i, (float)CLAMP(_attr_f(attrs, src, i) * strength, 0.0, 1.0));
	}
	Dictionary d;
	d["type"] = T_LAYER;
	d["layer"] = String(p_params.get("layer", "layer"));
	d["positions"] = pos;
	d["weights"] = w;
	Dictionary result;
	result["out"] = d;
	return result;
}

// ---------------------------------------------------------------- presets (pcg_presets.gd)

namespace {

void preset_link(CgamePCGGraph &p_graph, const String &p_a, const String &p_ap, const String &p_b, const String &p_bp) {
	const String err = p_graph.link(p_a, p_ap, p_b, p_bp);
	if (!err.is_empty()) {
		ERR_PRINT("CgamePCGGraph preset: " + err);
	}
}

Dictionary mesh_entry(const String &p_id, double p_weight) {
	Dictionary d;
	d["id"] = p_id;
	d["weight"] = p_weight;
	return d;
}

} // namespace

// Dense forest with a cleared corridor around the road; steep ground gets rocks instead of trees.
// Inputs: volume, landscape, road (spline). Outputs: trees, rocks, floor.
Ref<CgamePCGGraph> CgamePCGGraph::forest_scatter(int64_t p_graph_seed) {
	Ref<CgamePCGGraph> gr;
	gr.instantiate();
	CgamePCGGraph &g = *gr.ptr();
	g.graph_seed = p_graph_seed;
	(void)g.add_graph_input("in_volume", "volume", "volume");
	(void)g.add_graph_input("in_land", "landscape", "landscape");
	(void)g.add_graph_input("in_road", "road", "spline");
	{
		Dictionary p;
		p["spacing"] = 3.5;
		p["jitter"] = 0.8;
		(void)g.add_node("sample", "surface_sampler", p);
	}
	{
		Dictionary p;
		p["frequency"] = 0.03;
		(void)g.add_node("noise", "density_noise", p);
	}
	{
		Dictionary p;
		p["min"] = 0.4;
		(void)g.add_node("dense", "density_filter", p);
	}
	{
		Dictionary p;
		p["scale_min"] = 0.8;
		p["scale_max"] = 1.4;
		(void)g.add_node("xform", "transform_points", p);
	}
	{
		Dictionary p;
		p["mode"] = "along";
		p["spacing"] = 3.0;
		(void)g.add_node("road_pts", "spline_sampler", p);
	}
	{
		Dictionary p;
		p["distance"] = 7.0;
		p["planar"] = true;
		(void)g.add_node("clear", "difference", p);
	}
	{
		Dictionary p;
		p["min_distance"] = 2.5;
		(void)g.add_node("prune", "self_pruning", p);
	}
	{
		Dictionary p;
		p["attribute"] = "slope";
		p["threshold"] = 0.8;
		(void)g.add_node("slope", "partition_by_attribute", p);
	}
	{
		Dictionary p;
		Array meshes;
		meshes.push_back(mesh_entry("pine", 3.0));
		meshes.push_back(mesh_entry("spruce", 1.0));
		p["meshes"] = meshes;
		(void)g.add_node("trees", "static_mesh_spawner", p);
	}
	{
		Dictionary p;
		p["mesh_id"] = "rock_mossy";
		(void)g.add_node("rocks", "static_mesh_spawner", p);
	}
	{
		Dictionary p;
		p["layer"] = "forest_floor";
		p["strength"] = 1.0;
		(void)g.add_node("floor", "material_layer_output", p);
	}
	(void)g.add_graph_output("out_trees", "trees", "mesh_instances");
	(void)g.add_graph_output("out_rocks", "rocks", "mesh_instances");
	(void)g.add_graph_output("out_floor", "floor", "layer_weights");
	preset_link(g, "in_volume", "out", "sample", "volume");
	preset_link(g, "in_land", "out", "sample", "landscape");
	preset_link(g, "sample", "out", "noise", "in");
	preset_link(g, "noise", "out", "dense", "in");
	preset_link(g, "dense", "out", "xform", "in");
	preset_link(g, "in_road", "out", "road_pts", "spline");
	preset_link(g, "in_land", "out", "road_pts", "landscape");
	preset_link(g, "xform", "out", "clear", "in");
	preset_link(g, "road_pts", "out", "clear", "other");
	preset_link(g, "clear", "out", "prune", "in");
	preset_link(g, "prune", "out", "slope", "in");
	preset_link(g, "slope", "above", "trees", "in");
	preset_link(g, "slope", "below", "rocks", "in");
	preset_link(g, "slope", "above", "floor", "in");
	preset_link(g, "trees", "out", "out_trees", "in");
	preset_link(g, "rocks", "out", "out_rocks", "in");
	preset_link(g, "floor", "out", "out_floor", "in");
	return gr;
}

// Rubble clusters stamped onto each point of interest. Inputs: pois (points). Outputs: debris, ground.
Ref<CgamePCGGraph> CgamePCGGraph::ruins_debris(int64_t p_graph_seed) {
	Ref<CgamePCGGraph> gr;
	gr.instantiate();
	CgamePCGGraph &g = *gr.ptr();
	g.graph_seed = p_graph_seed;
	(void)g.add_graph_input("in_pois", "pois", "points");
	{
		Dictionary p;
		p["center"] = Vector3(0, 1, 0);
		p["size"] = Vector3(14, 2, 14);
		(void)g.add_node("cluster_vol", "constant_volume", p);
	}
	{
		Dictionary p;
		p["spacing"] = 2.2;
		p["jitter"] = 0.9;
		(void)g.add_node("cluster", "surface_sampler", p);
	}
	(void)g.add_node("stamp", "copy_points");
	{
		Dictionary p;
		p["frequency"] = 0.2;
		p["min_value"] = 0.2;
		(void)g.add_node("noise", "density_noise", p);
	}
	{
		Dictionary p;
		p["min"] = 0.35;
		(void)g.add_node("keep", "density_filter", p);
	}
	{
		Dictionary p;
		p["scale_min"] = 0.5;
		p["scale_max"] = 1.6;
		(void)g.add_node("xform", "transform_points", p);
	}
	{
		Dictionary p;
		p["min_distance"] = 1.2;
		(void)g.add_node("prune", "self_pruning", p);
	}
	{
		Dictionary p;
		Array meshes;
		meshes.push_back(mesh_entry("debris_brick", 4.0));
		meshes.push_back(mesh_entry("debris_beam", 1.0));
		meshes.push_back(mesh_entry("rubble_pile", 2.0));
		p["meshes"] = meshes;
		(void)g.add_node("debris", "static_mesh_spawner", p);
	}
	{
		Dictionary p;
		p["layer"] = "rubble_ground";
		(void)g.add_node("ground", "material_layer_output", p);
	}
	(void)g.add_graph_output("out_debris", "debris", "mesh_instances");
	(void)g.add_graph_output("out_ground", "ground", "layer_weights");
	preset_link(g, "cluster_vol", "out", "cluster", "volume");
	preset_link(g, "cluster", "out", "stamp", "source");
	preset_link(g, "in_pois", "out", "stamp", "target");
	preset_link(g, "stamp", "out", "noise", "in");
	preset_link(g, "noise", "out", "keep", "in");
	preset_link(g, "keep", "out", "xform", "in");
	preset_link(g, "xform", "out", "prune", "in");
	preset_link(g, "prune", "out", "debris", "in");
	preset_link(g, "prune", "out", "ground", "in");
	preset_link(g, "debris", "out", "out_debris", "in");
	preset_link(g, "ground", "out", "out_ground", "in");
	return gr;
}

// Boulders ringing each cave mouth, with the opening itself kept clear.
// Inputs: entrances (points). Outputs: rocks.
Ref<CgamePCGGraph> CgamePCGGraph::cave_rocks(int64_t p_graph_seed) {
	Ref<CgamePCGGraph> gr;
	gr.instantiate();
	CgamePCGGraph &g = *gr.ptr();
	g.graph_seed = p_graph_seed;
	(void)g.add_graph_input("in_entrances", "entrances", "points");
	{
		Dictionary p;
		p["center"] = Vector3(0, 1, 0);
		p["size"] = Vector3(16, 2, 16);
		(void)g.add_node("ring_vol", "constant_volume", p);
	}
	{
		Dictionary p;
		p["spacing"] = 1.6;
		p["jitter"] = 0.7;
		(void)g.add_node("ring", "surface_sampler", p);
	}
	(void)g.add_node("stamp", "copy_points");
	{
		Dictionary p;
		p["distance"] = 3.0;
		p["planar"] = true;
		(void)g.add_node("mouth", "difference", p);
	}
	{
		Dictionary p;
		p["frequency"] = 0.15;
		(void)g.add_node("noise", "density_noise", p);
	}
	{
		Dictionary p;
		p["min"] = 0.3;
		(void)g.add_node("keep", "density_filter", p);
	}
	{
		Dictionary p;
		p["scale_min"] = 0.6;
		p["scale_max"] = 2.2;
		(void)g.add_node("xform", "transform_points", p);
	}
	{
		Dictionary p;
		p["min_distance"] = 1.0;
		(void)g.add_node("prune", "self_pruning", p);
	}
	{
		Dictionary p;
		Array meshes;
		meshes.push_back(mesh_entry("cave_boulder", 2.0));
		meshes.push_back(mesh_entry("cave_slab", 1.0));
		p["meshes"] = meshes;
		(void)g.add_node("rocks", "static_mesh_spawner", p);
	}
	(void)g.add_graph_output("out_rocks", "rocks", "mesh_instances");
	preset_link(g, "ring_vol", "out", "ring", "volume");
	preset_link(g, "ring", "out", "stamp", "source");
	preset_link(g, "in_entrances", "out", "stamp", "target");
	preset_link(g, "stamp", "out", "mouth", "in");
	preset_link(g, "in_entrances", "out", "mouth", "other");
	preset_link(g, "mouth", "out", "noise", "in");
	preset_link(g, "noise", "out", "keep", "in");
	preset_link(g, "keep", "out", "xform", "in");
	preset_link(g, "xform", "out", "prune", "in");
	preset_link(g, "prune", "out", "rocks", "in");
	preset_link(g, "rocks", "out", "out_rocks", "in");
	return gr;
}
