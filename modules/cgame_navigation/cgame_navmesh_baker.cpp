/**************************************************************************/
/*  cgame_navmesh_baker.cpp                                               */
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

#include "cgame_navmesh_baker.h"

#include "cgame_navigation_util.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"

Dictionary CgameNavmeshBaker::_default_config() {
	Dictionary d;
	d["cell_size"] = 0.3;
	d["cell_height"] = 0.2;
	d["agent_height"] = 2.0;
	d["agent_radius"] = 0.5;
	d["agent_max_climb"] = 0.4;
	d["agent_max_slope_deg"] = 45.0;
	d["region_min_area"] = 8;
	d["max_verts_per_poly"] = 6;
	d["tile_size"] = 16.0;
	d["max_simplification_error"] = 1.3;
	return d;
}

float CgameNavmeshBaker::_cf(const String &p_key) const {
	return config.get(p_key, 0.0);
}

int CgameNavmeshBaker::_ci(const String &p_key) const {
	return config.get(p_key, 0);
}

void CgameNavmeshBaker::configure(const Dictionary &p_values) {
	if (config.is_empty()) {
		config = _default_config();
	}
	config.merge(p_values, true);
}

Ref<NavigationMesh> CgameNavmeshBaker::make_navigation_mesh() const {
	Dictionary cfg = config.is_empty() ? _default_config() : config;
	Ref<NavigationMesh> nm;
	nm.instantiate();
	nm->set_sample_partition_type(NavigationMesh::SAMPLE_PARTITION_MONOTONE);
	nm->set_cell_size(cfg.get("cell_size", 0.3));
	nm->set_cell_height(cfg.get("cell_height", 0.2));
	nm->set_agent_height(cfg.get("agent_height", 2.0));
	nm->set_agent_radius(cfg.get("agent_radius", 0.5));
	nm->set_agent_max_climb(cfg.get("agent_max_climb", 0.4));
	nm->set_agent_max_slope(cfg.get("agent_max_slope_deg", 45.0));
	// The GDScript baker counts region_min_area in voxels; Godot squares region_min_size to get voxels.
	nm->set_region_min_size(Math::sqrt(MAX(0.0f, float(cfg.get("region_min_area", 8)))));
	nm->set_region_merge_size(0.0);
	nm->set_vertices_per_polygon(CLAMP(int(cfg.get("max_verts_per_poly", 6)), 3, 12));
	nm->set_edge_max_error(cfg.get("max_simplification_error", 1.3));
	nm->set_edge_max_length(0.0);
	nm->set_border_size(0.0);
	return nm;
}

Ref<NavigationMeshSourceGeometryData3D> CgameNavmeshBaker::make_source_geometry(const PackedVector3Array &p_triangles, bool p_godot_winding) {
	Ref<NavigationMeshSourceGeometryData3D> data;
	data.instantiate();
	int face_count = p_triangles.size() / 3;
	if (face_count == 0) {
		return data;
	}
	if (p_godot_winding) {
		// Godot mesh convention (clockwise front faces); add_faces flips the winding for Recast.
		PackedVector3Array faces;
		for (int i = 0; i < face_count * 3; i++) {
			faces.push_back(p_triangles[i]);
		}
		data->add_faces(faces, Transform3D());
		return data;
	}
	// GDScript baker convention: counter-clockwise seen from above (+y normal) is walkable-facing,
	// which is what Recast expects, so the indices are used as given.
	Vector<float> vertices;
	Vector<int> indices;
	for (int i = 0; i < face_count * 3; i++) {
		vertices.push_back(p_triangles[i].x);
		vertices.push_back(p_triangles[i].y);
		vertices.push_back(p_triangles[i].z);
		indices.push_back(i);
	}
	data->set_vertices(vertices);
	data->set_indices(indices);
	return data;
}

Dictionary CgameNavmeshBaker::_empty_tile(const AABB &p_bounds) const {
	Dictionary tile;
	tile["origin"] = Vector2(p_bounds.position.x, p_bounds.position.z);
	tile["size"] = p_bounds.size.x;
	tile["polygons"] = Array();
	tile["heights"] = Array();
	tile["navigation_mesh"] = Ref<NavigationMesh>();
	tile["baked"] = false;
	return tile;
}

float CgameNavmeshBaker::_signed_area(const Vector<Vector2> &p_poly) {
	float a = 0.0f;
	int cnt = p_poly.size();
	for (int i = 0; i < cnt; i++) {
		const Vector2 &p = p_poly[i];
		const Vector2 &q = p_poly[(i + 1) % cnt];
		a += p.x * q.y - q.x * p.y;
	}
	return a * 0.5f;
}

Vector<Vector3> CgameNavmeshBaker::_clip(const Vector<Vector3> &p_poly, int p_axis, float p_value, bool p_keep_ge) {
	Vector<Vector3> out;
	int cnt = p_poly.size();
	float sgn = p_keep_ge ? 1.0f : -1.0f;
	for (int i = 0; i < cnt; i++) {
		Vector3 p = p_poly[i];
		Vector3 q = p_poly[(i + 1) % cnt];
		float dp = (p[p_axis] - p_value) * sgn;
		float dq = (q[p_axis] - p_value) * sgn;
		if (dp >= 0.0f) {
			out.push_back(p);
		}
		if ((dp >= 0.0f) != (dq >= 0.0f)) {
			Vector3 ip = p.lerp(q, dp / (dp - dq));
			ip[p_axis] = p_value;
			out.push_back(ip);
		}
	}
	return out;
}

Vector<Vector3> CgameNavmeshBaker::_clip_to_rect(const Vector<Vector3> &p_poly, const Rect2 &p_rect) {
	float x0 = p_rect.position.x;
	float x1 = p_rect.position.x + p_rect.size.x;
	float z0 = p_rect.position.y;
	float z1 = p_rect.position.y + p_rect.size.y;
	Vector<Vector3> snapped;
	for (int k = 0; k < p_poly.size(); k++) {
		Vector3 p = p_poly[k];
		if (Math::abs(p.x - x0) < 1e-4f) {
			p.x = x0;
		}
		if (Math::abs(p.x - x1) < 1e-4f) {
			p.x = x1;
		}
		if (Math::abs(p.z - z0) < 1e-4f) {
			p.z = z0;
		}
		if (Math::abs(p.z - z1) < 1e-4f) {
			p.z = z1;
		}
		snapped.push_back(p);
	}
	Vector<Vector3> out = _clip(snapped, 0, x0, true);
	out = _clip(out, 0, x1, false);
	out = _clip(out, 2, z0, true);
	out = _clip(out, 2, z1, false);
	Vector<Vector3> clean;
	for (int k = 0; k < out.size(); k++) {
		if (clean.is_empty() || Math::abs(clean[clean.size() - 1].x - out[k].x) > 1e-5f || Math::abs(clean[clean.size() - 1].z - out[k].z) > 1e-5f) {
			clean.push_back(out[k]);
		}
	}
	while (clean.size() > 1 && Math::abs(clean[0].x - clean[clean.size() - 1].x) <= 1e-5f && Math::abs(clean[0].z - clean[clean.size() - 1].z) <= 1e-5f) {
		clean.remove_at(clean.size() - 1);
	}
	return clean;
}

Vector<AABB> CgameNavmeshBaker::_rects(const AABB &p_world_bounds) const {
	float ts = MAX(_cf("tile_size"), 1.0f);
	int nx = MAX(1, (int)Math::ceil(p_world_bounds.size.x / ts - 0.0001f));
	int nz = MAX(1, (int)Math::ceil(p_world_bounds.size.z / ts - 0.0001f));
	Vector<AABB> rects;
	for (int iz = 0; iz < nz; iz++) {
		for (int ix = 0; ix < nx; ix++) {
			rects.push_back(AABB(Vector3(p_world_bounds.position.x + ix * ts, p_world_bounds.position.y, p_world_bounds.position.z + iz * ts), Vector3(ts, p_world_bounds.size.y, ts)));
		}
	}
	return rects;
}

TypedArray<AABB> CgameNavmeshBaker::tile_rects(const AABB &p_world_bounds) const {
	TypedArray<AABB> out;
	for (const AABB &r : _rects(p_world_bounds)) {
		out.push_back(r);
	}
	return out;
}

Ref<NavigationMesh> CgameNavmeshBaker::_make_tile_navmesh(const AABB &p_tile_bounds, const Vector<Vector3> &p_triangles, AABB &r_aabb_used) const {
	Ref<NavigationMesh> nm = make_navigation_mesh();
	float cs = nm->get_cell_size();
	// Same overscan as the GDScript baker: agent radius + 3 cells so erosion and ledges match across tile edges.
	int border = (int)Math::ceil(nm->get_agent_radius() / cs - 0.001f) + 3;
	float grow = border * cs;
	float y_min = p_tile_bounds.position.y;
	float y_size = p_tile_bounds.size.y;
	if (y_size <= 0.0f) {
		float lo = Math::INF;
		float hi = -Math::INF;
		for (int i = 0; i < p_triangles.size(); i++) {
			lo = MIN(lo, p_triangles[i].y);
			hi = MAX(hi, p_triangles[i].y);
		}
		if (lo > hi) {
			lo = 0.0f;
			hi = 0.0f;
		}
		y_min = lo - 1.0f;
		y_size = (hi - lo) + nm->get_agent_height() + 2.0f;
	}
	r_aabb_used = AABB(Vector3(p_tile_bounds.position.x - grow, y_min, p_tile_bounds.position.z - grow), Vector3(p_tile_bounds.size.x + grow * 2.0f, y_size, p_tile_bounds.size.z + grow * 2.0f));
	nm->set_filter_baking_aabb(r_aabb_used);
	return nm;
}

Dictionary CgameNavmeshBaker::navigation_mesh_to_tile(const Ref<NavigationMesh> &p_navigation_mesh, const AABB &p_tile_bounds) const {
	Dictionary tile = _empty_tile(p_tile_bounds);
	ERR_FAIL_COND_V(p_navigation_mesh.is_null(), tile);
	Vector<Vector3> verts = p_navigation_mesh->get_vertices();
	Rect2 rect(p_tile_bounds.position.x, p_tile_bounds.position.z, p_tile_bounds.size.x, p_tile_bounds.size.z);
	Array polys;
	Array heights;
	for (int pi = 0; pi < p_navigation_mesh->get_polygon_count(); pi++) {
		Vector<int> idx = p_navigation_mesh->get_polygon(pi);
		Vector<Vector3> raw;
		bool valid = true;
		for (int k = 0; k < idx.size(); k++) {
			if (idx[k] < 0 || idx[k] >= verts.size()) {
				valid = false;
				break;
			}
			raw.push_back(verts[idx[k]]);
		}
		if (!valid || raw.size() < 3) {
			continue;
		}
		Vector<Vector2> flat;
		for (const Vector3 &v : raw) {
			flat.push_back(Vector2(v.x, v.z));
		}
		if (_signed_area(flat) < 0.0f) {
			raw.reverse();
		}
		Vector<Vector3> clipped = p_tile_bounds.size.x > 0.0f && p_tile_bounds.size.z > 0.0f ? _clip_to_rect(raw, rect) : raw;
		if (clipped.size() < 3) {
			continue;
		}
		PackedVector2Array p2;
		PackedFloat32Array hs;
		for (const Vector3 &v : clipped) {
			p2.push_back(Vector2(v.x, v.z));
			hs.push_back(v.y);
		}
		Vector<Vector2> check;
		for (int k = 0; k < p2.size(); k++) {
			check.push_back(p2[k]);
		}
		if (_signed_area(check) < 1e-4f) {
			continue;
		}
		polys.push_back(p2);
		heights.push_back(hs);
	}
	tile["polygons"] = polys;
	tile["heights"] = heights;
	return tile;
}

Ref<NavigationMesh> CgameNavmeshBaker::tile_to_navigation_mesh(const Dictionary &p_tile) const {
	Ref<NavigationMesh> mesh;
	mesh.instantiate();
	Array polys = p_tile.get("polygons", Array());
	Array hts = p_tile.get("heights", Array());
	Vector<Vector3> verts;
	HashMap<Vector3i, int> lookup;
	Vector<Vector<int>> index_sets;
	for (int pi = 0; pi < polys.size(); pi++) {
		PackedVector2Array poly = polys[pi];
		PackedFloat32Array hs;
		if (pi < hts.size()) {
			hs = hts[pi];
		}
		Vector<int> idxs;
		for (int k = 0; k < poly.size(); k++) {
			float y = k < hs.size() ? hs[k] : 0.0f;
			Vector3i key(Math::round(poly[k].x * 1000.0f), Math::round(y * 1000.0f), Math::round(poly[k].y * 1000.0f));
			HashMap<Vector3i, int>::Iterator it = lookup.find(key);
			if (!it) {
				lookup[key] = verts.size();
				verts.push_back(Vector3(poly[k].x, y, poly[k].y));
				idxs.push_back(verts.size() - 1);
			} else {
				idxs.push_back(it->value);
			}
		}
		index_sets.push_back(idxs);
	}
	mesh->set_vertices(verts);
	for (const Vector<int> &idxs : index_sets) {
		mesh->add_polygon(idxs);
	}
	return mesh;
}

Dictionary CgameNavmeshBaker::bake_tile(const PackedVector3Array &p_triangles, const AABB &p_tile_bounds) {
	if (!CgameNavigationUtil::is_server_functional()) {
		return _empty_tile(p_tile_bounds);
	}
	AABB used;
	Ref<NavigationMesh> nm = _make_tile_navmesh(p_tile_bounds, p_triangles, used);
	Ref<NavigationMeshSourceGeometryData3D> source = make_source_geometry(p_triangles);
	NavigationServer3D::get_singleton()->bake_from_source_geometry_data(nm, source);
	Dictionary tile = navigation_mesh_to_tile(nm, p_tile_bounds);
	tile["navigation_mesh"] = tile_to_navigation_mesh(tile);
	tile["baked"] = true;
	return tile;
}

Array CgameNavmeshBaker::bake_tiles(const PackedVector3Array &p_triangles, const AABB &p_world_bounds) {
	Array out;
	for (const AABB &r : _rects(p_world_bounds)) {
		out.push_back(bake_tile(p_triangles, r));
	}
	return out;
}

void CgameNavmeshBaker::_on_tile_baked(int p_job, int p_index) {
	MutexLock lock(mutex);
	HashMap<int, Job>::Iterator it = jobs.find(p_job);
	if (!it || p_index < 0 || p_index >= it->value.finished.size() || it->value.finished[p_index]) {
		return;
	}
	it->value.finished.write[p_index] = true;
	it->value.remaining--;
}

int CgameNavmeshBaker::bake_async(const PackedVector3Array &p_triangles, const AABB &p_world_bounds) {
	int job_id;
	Vector<AABB> rects = _rects(p_world_bounds);
	Vector<Ref<NavigationMesh>> meshes;
	Vector<Ref<NavigationMeshSourceGeometryData3D>> sources;
	bool functional = CgameNavigationUtil::is_server_functional();
	{
		MutexLock lock(mutex);
		job_id = next_job++;
		Job job;
		job.rects = rects;
		job.synthetic_failure = !functional;
		job.meshes.resize(rects.size());
		job.finished.resize(rects.size());
		job.remaining = functional ? rects.size() : 0;
		for (int i = 0; i < rects.size(); i++) {
			AABB used;
			job.meshes.write[i] = functional ? _make_tile_navmesh(rects[i], p_triangles, used) : Ref<NavigationMesh>();
			job.finished.write[i] = !functional;
			meshes.push_back(job.meshes[i]);
		}
		jobs[job_id] = job;
	}
	if (functional) {
		Ref<NavigationMeshSourceGeometryData3D> source = make_source_geometry(p_triangles);
		for (int i = 0; i < rects.size(); i++) {
			Callable cb = callable_mp(this, &CgameNavmeshBaker::_on_tile_baked).bind(job_id, i);
			NavigationServer3D::get_singleton()->bake_from_source_geometry_data_async(meshes[i], source, cb);
		}
	}
	return job_id;
}

Dictionary CgameNavmeshBaker::poll(int p_job) {
	Dictionary out;
	Job job;
	{
		MutexLock lock(mutex);
		HashMap<int, Job>::Iterator it = jobs.find(p_job);
		if (!it) {
			out["done"] = true;
			out["tiles"] = Array();
			return out;
		}
		if (it->value.remaining > 0) {
			out["done"] = false;
			out["tiles"] = Array();
			return out;
		}
		job = it->value;
		jobs.remove(it);
	}
	Array tiles;
	for (int i = 0; i < job.rects.size(); i++) {
		if (job.synthetic_failure || job.meshes[i].is_null()) {
			tiles.push_back(_empty_tile(job.rects[i]));
			continue;
		}
		Dictionary tile = navigation_mesh_to_tile(job.meshes[i], job.rects[i]);
		tile["navigation_mesh"] = tile_to_navigation_mesh(tile);
		tile["baked"] = true;
		tiles.push_back(tile);
	}
	out["done"] = true;
	out["tiles"] = tiles;
	return out;
}

void CgameNavmeshBaker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "values"), &CgameNavmeshBaker::configure);
	ClassDB::bind_method(D_METHOD("get_config"), &CgameNavmeshBaker::get_config);
	ClassDB::bind_static_method("CgameNavmeshBaker", D_METHOD("can_bake"), &CgameNavmeshBaker::can_bake);
	ClassDB::bind_method(D_METHOD("make_navigation_mesh"), &CgameNavmeshBaker::make_navigation_mesh);
	ClassDB::bind_static_method("CgameNavmeshBaker", D_METHOD("make_source_geometry", "triangles", "godot_winding"), &CgameNavmeshBaker::make_source_geometry, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("bake_tile", "triangles", "tile_bounds"), &CgameNavmeshBaker::bake_tile);
	ClassDB::bind_method(D_METHOD("bake_tiles", "triangles", "world_bounds"), &CgameNavmeshBaker::bake_tiles);
	ClassDB::bind_method(D_METHOD("bake_async", "triangles", "world_bounds"), &CgameNavmeshBaker::bake_async);
	ClassDB::bind_method(D_METHOD("poll", "job"), &CgameNavmeshBaker::poll);
	ClassDB::bind_method(D_METHOD("tile_rects", "world_bounds"), &CgameNavmeshBaker::tile_rects);
	ClassDB::bind_method(D_METHOD("navigation_mesh_to_tile", "navigation_mesh", "tile_bounds"), &CgameNavmeshBaker::navigation_mesh_to_tile);
	ClassDB::bind_method(D_METHOD("tile_to_navigation_mesh", "tile"), &CgameNavmeshBaker::tile_to_navigation_mesh);
}
