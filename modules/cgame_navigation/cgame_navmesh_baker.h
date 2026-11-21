/**************************************************************************/
/*  cgame_navmesh_baker.h                                                 */
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

#include "cgame_navigation_util.h"

#include "core/object/ref_counted.h"
#include "core/os/mutex.h"
#include "core/templates/hash_map.h"
#include "core/variant/typed_array.h"
#include "scene/resources/3d/navigation_mesh_source_geometry_data_3d.h"
#include "scene/resources/navigation_mesh.h"

// Thin wrapper that bakes navigation tiles from triangle soups through Godot's own
// NavigationServer3D bake pipeline (Recast). The GDScript baker's config keys are mapped
// onto NavigationMesh properties; results come back both as a NavigationMesh and in the
// 2D polygon tile format used by the GDScript navmesh stack:
//   {"origin": Vector2 (xz), "size": float, "polygons": Array[PackedVector2Array],
//    "heights": Array[PackedFloat32Array], "navigation_mesh": NavigationMesh, "baked": bool}
// Polygons are convex, have positive shoelace area and are clipped to the tile rectangle.
class CgameNavmeshBaker : public RefCounted {
	GDCLASS(CgameNavmeshBaker, RefCounted);

	struct Job {
		Vector<AABB> rects;
		Vector<Ref<NavigationMesh>> meshes;
		Vector<bool> finished;
		int remaining = 0;
		bool synthetic_failure = false;
	};

	Dictionary config;
	HashMap<int, Job> jobs;
	int next_job = 1;
	Mutex mutex;

	float _cf(const String &p_key) const;
	int _ci(const String &p_key) const;
	static Dictionary _default_config();
	Vector<AABB> _rects(const AABB &p_world_bounds) const;
	static float _signed_area(const Vector<Vector2> &p_poly);
	static Vector<Vector3> _clip(const Vector<Vector3> &p_poly, int p_axis, float p_value, bool p_keep_ge);
	static Vector<Vector3> _clip_to_rect(const Vector<Vector3> &p_poly, const Rect2 &p_rect);
	Ref<NavigationMesh> _make_tile_navmesh(const AABB &p_tile_bounds, const Vector<Vector3> &p_triangles, AABB &r_aabb_used) const;
	Dictionary _empty_tile(const AABB &p_bounds) const;
	void _on_tile_baked(int p_job, int p_index);

protected:
	static void _bind_methods();

public:
	void configure(const Dictionary &p_values);
	Dictionary get_config() const { return config; }
	// True when a functioning (non dummy) NavigationServer3D can bake.
	static bool can_bake() { return CgameNavigationUtil::is_server_functional(); }

	// NavigationMesh with the baker config mapped onto its properties.
	Ref<NavigationMesh> make_navigation_mesh() const;
	// Source geometry holding a triangle soup. By default counter-clockwise seen from above is walkable facing (GDScript baker convention); with godot_winding Godot's clockwise front faces are expected.
	static Ref<NavigationMeshSourceGeometryData3D> make_source_geometry(const PackedVector3Array &p_triangles, bool p_godot_winding = false);

	// Synchronous bake of one tile through NavigationServer3D. Returns an empty tile (baked = false) with a dummy server.
	Dictionary bake_tile(const PackedVector3Array &p_triangles, const AABB &p_tile_bounds);
	// Synchronous bake of every tile covering world_bounds.
	Array bake_tiles(const PackedVector3Array &p_triangles, const AABB &p_world_bounds);
	// Asynchronous bake through NavigationServer3D.bake_from_source_geometry_data_async. Returns a job id for poll().
	int bake_async(const PackedVector3Array &p_triangles, const AABB &p_world_bounds);
	// {"done": bool, "tiles": Array[Dictionary]}; tiles are row-major (x fastest) and only filled once done.
	Dictionary poll(int p_job);

	TypedArray<AABB> tile_rects(const AABB &p_world_bounds) const;

	// Pure conversions (no server needed).
	Dictionary navigation_mesh_to_tile(const Ref<NavigationMesh> &p_navigation_mesh, const AABB &p_tile_bounds) const;
	Ref<NavigationMesh> tile_to_navigation_mesh(const Dictionary &p_tile) const;

	CgameNavmeshBaker() { config = _default_config(); }
};
