/**************************************************************************/
/*  world_partition_3d.cpp                                                */
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

#include "world_partition_3d.h"

#include "core/config/engine.h"
#include "core/io/resource_loader.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/os/time.h"
#include "scene/main/node.h"
#include "scene/3d/navigation/navigation_region_3d.h"
#include "scene/resources/3d/world_3d.h"
#include "servers/navigation_3d/navigation_server_3d.h"

#include <cstdint>

bool WorldPartition3D::_within_radius(const Vector2i &p_cell, const Vector2i &p_center, int p_radius) {
	const int64_t dx = int64_t(p_cell.x) - p_center.x;
	const int64_t dz = int64_t(p_cell.y) - p_center.y;
	return dx >= -p_radius && dx <= p_radius && dz >= -p_radius && dz <= p_radius;
}

String WorldPartition3D::_get_scene_path(const Vector2i &p_cell) const {
	if (!cell_scenes.has(p_cell)) {
		return String();
	}
	const Variant value = cell_scenes[p_cell];
	if (value.get_type() != Variant::STRING) {
		return String();
	}
	return value;
}

void WorldPartition3D::_unload_cell(const Vector2i &p_cell) {
	const ObjectID *id = active_cells.getptr(p_cell);
	if (id == nullptr) {
		return;
	}

	Node *node = Object::cast_to<Node>(ObjectDB::get_instance(*id));
	if (node != nullptr) {
		node->queue_free();
	}
	active_cells.erase(p_cell);
	_clear_navigation_cell(p_cell);
	physics_pending_cells.erase(p_cell);
	// Gameplay should disarm the associated AI/physics interactions before
	// the scene root is deleted at the end of the frame.
	if (physics_ready_cells.has(p_cell)) {
		physics_ready_cells.erase(p_cell);
		emit_signal(SNAME("cell_physics_unready"), p_cell);
	}
	_refresh_processing();
	emit_signal(SNAME("cell_unloaded"), p_cell);
}

void WorldPartition3D::_clear_active_cells() {
	Vector<Vector2i> coords;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		coords.push_back(E.key);
	}
	for (const Vector2i &cell : coords) {
		_unload_cell(cell);
	}
}

void WorldPartition3D::_poll_requests() {
	Vector<String> finished;
	for (const String &path : requested_paths) {
		const ResourceLoader::ThreadLoadStatus status = ResourceLoader::load_threaded_get_status(path);
		if (status == ResourceLoader::THREAD_LOAD_IN_PROGRESS) {
			continue;
		}
		if (status == ResourceLoader::THREAD_LOAD_LOADED) {
			Ref<PackedScene> scene = ResourceLoader::load_threaded_get(path);
			if (scene.is_valid()) {
				ready_scenes.insert(path, scene);
			} else {
				ERR_PRINT(vformat("WorldPartition3D: loaded resource is not a PackedScene: %s.", path));
			}
		} else {
			if (status == ResourceLoader::THREAD_LOAD_FAILED) {
				// Even failed requests own a user token until their result is collected.
				// Ignoring it would leak a ResourceLoader user-load token for this path.
				ResourceLoader::load_threaded_get(path);
			}
			ERR_PRINT(vformat("WorldPartition3D: failed to load cell scene: %s.", path));
		}
		if (!ready_scenes.has(path)) {
			Vector<Vector2i> failed;
			for (const KeyValue<Vector2i, String> &E : pending_cells) {
				if (E.value == path) {
					failed.push_back(E.key);
				}
			}
			for (const Vector2i &cell : failed) {
				pending_cells.erase(cell);
				failed_cells.insert(cell);
			}
		}
		finished.push_back(path);
	}
	for (const String &path : finished) {
		requested_paths.erase(path);
	}
}

void WorldPartition3D::_purge_unused_ready_scenes() {
	Vector<String> unused;
	for (const KeyValue<String, Ref<PackedScene>> &E : ready_scenes) {
		bool needed = false;
		for (const KeyValue<Vector2i, String> &P : pending_cells) {
			if (P.value == E.key) {
				needed = true;
				break;
			}
		}
		if (!needed) {
			unused.push_back(E.key);
		}
	}
	for (const String &path : unused) {
		ready_scenes.erase(path);
	}
}

bool WorldPartition3D::_instantiate_cell(const Vector2i &p_cell, const Ref<PackedScene> &p_scene) {
	if (p_scene.is_null()) {
		return false;
	}
	Node *root = p_scene->instantiate();
	if (root == nullptr) {
		return false;
	}
	Node3D *instance = Object::cast_to<Node3D>(root);
	if (instance == nullptr) {
		ERR_PRINT("WorldPartition3D: a cell scene must have a Node3D root.");
		memdelete(root);
		return false;
	}

	// Set the final transform before _enter_tree()/ _ready() callbacks run.
	// The root's authored local offset is preserved within its grid cell.
	instance->set_position(instance->get_position() + cell_to_local_position(p_cell));
	add_child(instance);
	active_cells.insert(p_cell, instance->get_instance_id());
	_clear_navigation_cell(p_cell);
	Node *navigation_region = _find_navigation_region(instance);
	if (navigation_region != nullptr) {
		navigation_pending_regions.insert(p_cell, navigation_region->get_instance_id());
	}
	physics_ready_cells.erase(p_cell);
	physics_pending_cells.insert(p_cell, physics_tick_counter + 2);
	_refresh_processing();
	emit_signal(SNAME("cell_loaded"), p_cell);
	return true;
}

Node *WorldPartition3D::_find_navigation_region(Node *p_root) const {
	if (p_root == nullptr) {
		return nullptr;
	}
	NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(p_root);
	if (region != nullptr && region->is_enabled() && region->get_navigation_mesh().is_valid() &&
			region->get_navigation_mesh()->get_polygon_count() > 0) {
		return region;
	}
	for (int i = 0; i < p_root->get_child_count(); i++) {
		Node *found = _find_navigation_region(p_root->get_child(i));
		if (found != nullptr) {
			return found;
		}
	}
	return nullptr;
}

void WorldPartition3D::_clear_navigation_cell(const Vector2i &p_cell) {
	navigation_pending_regions.erase(p_cell);
	const bool was_ready = navigation_ready_regions.has(p_cell);
	navigation_ready_regions.erase(p_cell);
	if (was_ready) {
		emit_signal(SNAME("cell_navigation_unready"), p_cell);
	}
}

bool WorldPartition3D::is_cell_navigation_ready(const Vector2i &p_cell) const {
	if (!streaming_enabled || !is_inside_tree() || !is_cell_physics_ready(p_cell)) {
		return false;
	}
	const ObjectID *id = navigation_ready_regions.getptr(p_cell);
	if (id == nullptr) {
		return false;
	}
	NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(ObjectDB::get_instance(*id));
	if (region == nullptr || !region->is_inside_tree() || region->is_queued_for_deletion() || !region->is_enabled()) {
		return false;
	}
	const Ref<NavigationMesh> mesh = region->get_navigation_mesh();
	if (mesh.is_null() || mesh->get_polygon_count() == 0) {
		return false;
	}
	NavigationServer3D *navigation = NavigationServer3D::get_singleton();
	const RID region_rid = region->get_rid();
	const RID map = region->get_navigation_map();
	return navigation != nullptr && navigation->region_get_enabled(region_rid) &&
			navigation->region_get_map(region_rid) == map && map.is_valid() &&
			navigation->map_get_iteration_id(map) > 0 &&
			navigation->region_get_iteration_id(region_rid) > 0;
}

bool WorldPartition3D::are_cells_navigation_ready(const Vector2i &p_center, int p_radius) const {
	ERR_FAIL_COND_V_MSG(p_radius < 0 || p_radius > 32, false, "WorldPartition3D navigation-ready query radius must be between 0 and 32.");
	const Array cells = get_cells_in_radius(p_center, p_radius);
	if (cells.is_empty()) {
		return false;
	}
	for (int i = 0; i < cells.size(); i++) {
		if (!is_cell_navigation_ready(cells[i])) {
			return false;
		}
	}
	return true;
}

int WorldPartition3D::get_navigation_ready_cell_count() const {
	int result = 0;
	for (const KeyValue<Vector2i, ObjectID> &E : navigation_ready_regions) {
		if (is_cell_navigation_ready(E.key)) {
			result++;
		}
	}
	return result;
}

Array WorldPartition3D::get_navigation_route_cells(const Vector3 &p_from_global, const Vector3 &p_to_global, int p_max_cells) const {
	Array result;
	ERR_FAIL_COND_V_MSG(p_max_cells < 1 || p_max_cells > 256, result, "WorldPartition3D route cell limit must be between 1 and 256.");
	if (!is_inside_tree() || !p_from_global.is_finite() || !p_to_global.is_finite()) {
		return result;
	}
	const Vector3 from = to_local(p_from_global);
	const Vector3 to = to_local(p_to_global);
	if (!from.is_finite() || !to.is_finite() || !Math::is_finite(cell_size) || cell_size <= 0.0) {
		return result;
	}
	const real_t ax = from.x / cell_size;
	const real_t az = from.z / cell_size;
	const real_t bx = to.x / cell_size;
	const real_t bz = to.z / cell_size;
	// Reject out-of-range coordinates instead of silently taking the clamped
	// local_position_to_cell value and declaring an unrelated cell ready.
	if (Math::abs(ax) > 1000000000.0 || Math::abs(az) > 1000000000.0 ||
			Math::abs(bx) > 1000000000.0 || Math::abs(bz) > 1000000000.0) {
		return result;
	}
	Vector2i cell(int(Math::floor(ax)), int(Math::floor(az)));
	const Vector2i last(int(Math::floor(bx)), int(Math::floor(bz)));
	result.push_back(cell);
	if (cell == last) {
		return result;
	}

	const real_t dx = bx - ax;
	const real_t dz = bz - az;
	const int step_x = (dx > 0.0) ? 1 : ((dx < 0.0) ? -1 : 0);
	const int step_z = (dz > 0.0) ? 1 : ((dz < 0.0) ? -1 : 0);
	const real_t abs_dx = Math::abs(dx);
	const real_t abs_dz = Math::abs(dz);
	// 2D supercover DDA: a diagonal grid-corner crossing conservatively
	// includes BOTH side-adjacent cells before the diagonal destination.
	const real_t inf = real_t(1e30);
	real_t t_max_x = step_x == 0 ? inf : (step_x > 0 ? (Math::floor(ax) + 1.0 - ax) : (ax - Math::floor(ax))) / abs_dx;
	real_t t_max_z = step_z == 0 ? inf : (step_z > 0 ? (Math::floor(az) + 1.0 - az) : (az - Math::floor(az))) / abs_dz;
	const real_t t_delta_x = step_x == 0 ? inf : 1.0 / abs_dx;
	const real_t t_delta_z = step_z == 0 ? inf : 1.0 / abs_dz;
	const auto append_cell = [&](const Vector2i &p_cell) -> bool {
		if (result.size() >= p_max_cells) {
			return false;
		}
		result.push_back(p_cell);
		return true;
	};
	// A hard work cap also protects against malformed huge input ranges.
	while (cell != last) {
		if (step_x != 0 && step_z != 0 && Math::is_equal_approx(t_max_x, t_max_z)) {
			if (!append_cell(Vector2i(cell.x + step_x, cell.y)) ||
					!append_cell(Vector2i(cell.x, cell.y + step_z))) {
				return Array(); // Never report a silently truncated corridor.
			}
			cell += Vector2i(step_x, step_z);
			t_max_x += t_delta_x;
			t_max_z += t_delta_z;
		} else if (t_max_x < t_max_z) {
			cell.x += step_x;
			t_max_x += t_delta_x;
		} else {
			cell.y += step_z;
			t_max_z += t_delta_z;
		}
		if (!append_cell(cell)) {
			return Array();
		}
	}
	return result;
}

bool WorldPartition3D::is_navigation_route_ready(const Vector3 &p_from_global, const Vector3 &p_to_global, int p_max_cells) const {
	if (!streaming_enabled || !is_inside_tree()) {
		return false;
	}
	const Array cells = get_navigation_route_cells(p_from_global, p_to_global, p_max_cells);
	if (cells.is_empty()) {
		return false;
	}
	for (int i = 0; i < cells.size(); i++) {
		if (!is_cell_navigation_ready(cells[i])) {
			return false;
		}
	}
	return true;
}

PackedVector3Array WorldPartition3D::get_streamed_navigation_path(const Vector3 &p_from_global, const Vector3 &p_to_global, bool p_optimize, int p_navigation_layers, int p_max_cells) const {
	PackedVector3Array result;
	ERR_FAIL_COND_V_MSG(p_navigation_layers < 1, result, "WorldPartition3D navigation path layers must be a positive bitmask.");
	if (!is_navigation_route_ready(p_from_global, p_to_global, p_max_cells)) {
		return result;
	}
	NavigationServer3D *navigation = NavigationServer3D::get_singleton();
	const Ref<World3D> world = get_world_3d();
	if (navigation == nullptr || world.is_null()) {
		return result;
	}
	const RID map = world->get_navigation_map();
	if (!map.is_valid() || navigation->map_get_iteration_id(map) == 0) {
		return result;
	}
	const Vector<Vector3> route = navigation->map_get_path(map, p_from_global, p_to_global, p_optimize, uint32_t(p_navigation_layers));
	if (route.is_empty()) {
		return result;
	}
	// NavigationServer may return a partial path toward a disconnected point.
	// Never claim destination readiness for a path ending far from the goal.
	const real_t endpoint_tolerance = MAX(real_t(2.0), cell_size * real_t(0.125));
	if (route[0].distance_to(p_from_global) > endpoint_tolerance ||
			route[route.size() - 1].distance_to(p_to_global) > endpoint_tolerance) {
		return result;
	}
	// The returned path may detour outside the straight-line corridor. Verify
	// EVERY actual segment against the streamed regions before exposing it.
	for (int i = 1; i < route.size(); i++) {
		if (!is_navigation_route_ready(route[i - 1], route[i], p_max_cells)) {
			return PackedVector3Array();
		}
	}
	for (const Vector3 &point : route) {
		result.push_back(point);
	}
	return result;
}

int WorldPartition3D::get_navigation_pending_cell_count() const {
	return streaming_enabled && is_inside_tree() ? navigation_pending_regions.size() : 0;
}

bool WorldPartition3D::is_streaming_source_navigation_ready(const String &p_name) const {
	if (!streaming_enabled || !is_inside_tree()) {
		return false;
	}
	for (const StreamingSource &source : streaming_sources) {
		if (source.name == p_name) {
			return source.active && are_cells_navigation_ready(source.center, source.load_radius);
		}
	}
	return false;
}

real_t WorldPartition3D::get_streaming_source_navigation_progress(const String &p_name) const {
	if (!streaming_enabled || !is_inside_tree()) {
		return 0.0;
	}
	for (const StreamingSource &source : streaming_sources) {
		if (source.name != p_name) {
			continue;
		}
		if (!source.active) {
			return 0.0;
		}
		const int width = source.load_radius * 2 + 1;
		int navigation_ready = 0;
		for (int dz = -source.load_radius; dz <= source.load_radius; dz++) {
			for (int dx = -source.load_radius; dx <= source.load_radius; dx++) {
				const Vector2i cell(source.center.x + dx, source.center.y + dz);
				if (is_cell_navigation_ready(cell)) {
					navigation_ready++;
				}
			}
		}
		return real_t(navigation_ready) / real_t(width * width);
	}
	return 0.0;
}

void WorldPartition3D::_update_navigation_readiness() {
	// NavigationServer applies region map changes asynchronously. A scene
	// root's _ready() and our physics activation barrier cannot replace its
	// own iteration counters. Check the actual navigation server here.
	Vector<Vector2i> lost;
	for (const KeyValue<Vector2i, ObjectID> &E : navigation_ready_regions) {
		if (!is_cell_navigation_ready(E.key)) {
			lost.push_back(E.key);
		}
	}
	for (const Vector2i &cell : lost) {
		const ObjectID *id = navigation_ready_regions.getptr(cell);
		const ObjectID region_id = id != nullptr ? *id : ObjectID();
		_clear_navigation_cell(cell);
		// An existing NavigationRegion3D may be temporarily disabled or
		// detached from its map and enabled again without reloading the tile.
		// Keep watching that specific live region for a new server sync.
		NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(ObjectDB::get_instance(region_id));
		if (region != nullptr && !region->is_queued_for_deletion() && is_cell_loaded(cell)) {
			navigation_pending_regions.insert(cell, region_id);
		}
	}
	Vector<Vector2i> available;
	Vector<Vector2i> stale;
	for (const KeyValue<Vector2i, ObjectID> &E : navigation_pending_regions) {
		NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(ObjectDB::get_instance(E.value));
		if (region == nullptr || region->is_queued_for_deletion() || !is_cell_loaded(E.key)) {
			// A script may free a region without unloading its parent cell.
			// Do not keep the physics processor running forever on its ObjectID.
			stale.push_back(E.key);
			continue;
		}
		if (!is_cell_physics_ready(E.key) || !region->is_inside_tree() || !region->is_enabled()) {
			continue;
		}
		const Ref<NavigationMesh> mesh = region->get_navigation_mesh();
		if (mesh.is_null() || mesh->get_polygon_count() == 0) {
			continue;
		}
		NavigationServer3D *navigation = NavigationServer3D::get_singleton();
		if (navigation == nullptr) {
			continue;
		}
		const RID region_rid = region->get_rid();
		const RID map = region->get_navigation_map();
		if (map.is_valid() && navigation->region_get_enabled(region_rid) &&
				navigation->region_get_map(region_rid) == map &&
				navigation->map_get_iteration_id(map) > 0 &&
				navigation->region_get_iteration_id(region_rid) > 0) {
			available.push_back(E.key);
		}
	}
	for (const Vector2i &cell : stale) {
		navigation_pending_regions.erase(cell);
	}
	for (const Vector2i &cell : available) {
		const ObjectID *id = navigation_pending_regions.getptr(cell);
		if (id == nullptr || !is_cell_physics_ready(cell)) {
			continue;
		}
		navigation_ready_regions.insert(cell, *id);
		navigation_pending_regions.erase(cell);
		// Callback handlers may unload other cells. Always recheck each entry.
		emit_signal(SNAME("cell_navigation_ready"), cell);
	}
	_refresh_processing();
}

void WorldPartition3D::_refresh_processing() {
	if (is_inside_tree()) {
		const bool runtime = !Engine::get_singleton()->is_editor_hint();
		set_process(runtime && (streaming_enabled || !requested_paths.is_empty()));
		// Only tick physics while newly loaded cells are waiting to be armed.
		// This keeps normal idle streaming free of a per-physics-tick scan.
		set_physics_process(runtime && streaming_enabled && (!physics_pending_cells.is_empty() ||
				!navigation_pending_regions.is_empty() || !navigation_ready_regions.is_empty()));
	}
}

void WorldPartition3D::_update_physics_readiness() {
	physics_tick_counter++;
	Vector<Vector2i> completed;
	for (const KeyValue<Vector2i, uint64_t> &E : physics_pending_cells) {
		if (E.value <= physics_tick_counter) {
			completed.push_back(E.key);
		}
	}
	for (const Vector2i &cell : completed) {
		physics_pending_cells.erase(cell);
		if (!streaming_enabled || !is_inside_tree() || !is_cell_loaded(cell)) {
			continue;
		}
		Node3D *instance = get_cell_node(cell);
		if (instance == nullptr || instance->is_queued_for_deletion()) {
			continue;
		}
		physics_ready_cells.insert(cell);
		// Callbacks may unload this or other cells. Work from the snapshot,
		// never iterate the pending map while emitting gameplay signals.
		emit_signal(SNAME("cell_physics_ready"), cell);
	}
	_update_navigation_readiness();
	_refresh_processing();
}

void WorldPartition3D::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		// A re-entered streamed world needs a fresh physics barrier even when
		// its child scene instances were preserved outside the scene tree.
		physics_pending_cells.clear();
		physics_ready_cells.clear();
		navigation_pending_regions.clear();
		navigation_ready_regions.clear();
		for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
			Node3D *root = Object::cast_to<Node3D>(ObjectDB::get_instance(E.value));
			if (root != nullptr) {
				physics_pending_cells.insert(E.key, physics_tick_counter + 2);
				Node *region = _find_navigation_region(root);
				if (region != nullptr) {
					navigation_pending_regions.insert(E.key, region->get_instance_id());
				}
			}
		}
		_refresh_processing();
	} else if (p_what == NOTIFICATION_READY) {
		_refresh_processing();
	} else if (p_what == NOTIFICATION_PROCESS) {
		update_streaming();
	} else if (p_what == NOTIFICATION_PHYSICS_PROCESS) {
		_update_physics_readiness();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		// A future re-entry should report the first resolved observer cell.
		observer_cell_valid = false;
		physics_pending_cells.clear();
		physics_ready_cells.clear();
		navigation_pending_regions.clear();
		navigation_ready_regions.clear();
	}
}

void WorldPartition3D::set_cell_size(real_t p_size) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_size) || p_size <= 0, "WorldPartition3D cell_size must be finite and positive.");
	if (Math::is_equal_approx(cell_size, p_size)) {
		return;
	}
	cell_size = p_size;
	observer_cell_valid = false;
	_clear_active_cells();
	pending_cells.clear();
	failed_cells.clear();
}

real_t WorldPartition3D::get_cell_size() const {
	return cell_size;
}

void WorldPartition3D::set_load_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < 0 || p_radius > 32, "WorldPartition3D load_radius must be between 0 and 32.");
	load_radius = p_radius;
	unload_radius = MAX(unload_radius, load_radius);
}

int WorldPartition3D::get_load_radius() const {
	return load_radius;
}

void WorldPartition3D::set_unload_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < load_radius || p_radius > 64, "WorldPartition3D unload_radius must be >= load_radius and <= 64.");
	unload_radius = p_radius;
}

int WorldPartition3D::get_unload_radius() const {
	return unload_radius;
}

void WorldPartition3D::set_prefetch_direction(const Vector2i &p_direction) {
	ERR_FAIL_COND_MSG(p_direction.x < -1 || p_direction.x > 1 || p_direction.y < -1 || p_direction.y > 1, "WorldPartition3D prefetch_direction components must be -1, 0 or 1.");
	prefetch_direction = p_direction;
}

Vector2i WorldPartition3D::get_prefetch_direction() const {
	return prefetch_direction;
}

void WorldPartition3D::set_prefetch_distance(int p_distance) {
	ERR_FAIL_COND_MSG(p_distance < 0 || p_distance > 4, "WorldPartition3D prefetch_distance must be between 0 and 4 cells.");
	prefetch_distance = p_distance;
}

int WorldPartition3D::get_prefetch_distance() const {
	return prefetch_distance;
}

void WorldPartition3D::set_max_new_requests_per_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 128, "WorldPartition3D request budget must be between 1 and 128.");
	max_new_requests_per_frame = p_count;
}

int WorldPartition3D::get_max_new_requests_per_frame() const {
	return max_new_requests_per_frame;
}

void WorldPartition3D::set_max_instances_per_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 128, "WorldPartition3D instance budget must be between 1 and 128.");
	max_instances_per_frame = p_count;
}

int WorldPartition3D::get_max_instances_per_frame() const {
	return max_instances_per_frame;
}

void WorldPartition3D::set_max_instantiation_time_ms(real_t p_milliseconds) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_milliseconds) || p_milliseconds < 0.0 || p_milliseconds > 100.0, "WorldPartition3D instantiation time budget must be between 0 and 100 milliseconds.");
	max_instantiation_time_ms = p_milliseconds;
}

real_t WorldPartition3D::get_max_instantiation_time_ms() const {
	return max_instantiation_time_ms;
}

void WorldPartition3D::set_max_concurrent_requests(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 128, "WorldPartition3D maximum concurrent requests must be between 1 and 128.");
	max_concurrent_requests = p_count;
}

int WorldPartition3D::get_max_concurrent_requests() const {
	return max_concurrent_requests;
}

void WorldPartition3D::set_streaming_enabled(bool p_enabled) {
	if (streaming_enabled == p_enabled) {
		return;
	}
	streaming_enabled = p_enabled;
	if (!streaming_enabled) {
		_clear_active_cells();
		pending_cells.clear();
		failed_cells.clear();
		_purge_unused_ready_scenes();
		_refresh_source_readiness();
	}
	_refresh_processing();
}

bool WorldPartition3D::is_streaming_enabled() const {
	return streaming_enabled;
}

void WorldPartition3D::set_observer_path(const NodePath &p_path) {
	if (observer_path == p_path) {
		return;
	}
	observer_path = p_path;
	observer_cell_valid = false;
}

NodePath WorldPartition3D::get_observer_path() const {
	return observer_path;
}

bool WorldPartition3D::has_observer_cell() const {
	return observer_cell_valid;
}

Vector2i WorldPartition3D::get_observer_cell() const {
	return observer_cell_valid ? observer_cell : Vector2i();
}

void WorldPartition3D::set_cell_scenes(const Dictionary &p_cells) {
	Dictionary clean;
	const Array keys = p_cells.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		const Variant value = p_cells[key];
		if (key.get_type() == Variant::VECTOR2I && value.get_type() == Variant::STRING && !String(value).is_empty()) {
			clean[key] = value;
		}
	}
	_clear_active_cells();
	pending_cells.clear();
	failed_cells.clear();
	pinned_cells.clear();
	cell_scenes = clean;
	_purge_unused_ready_scenes();
	_refresh_source_readiness();
}

Dictionary WorldPartition3D::get_cell_scenes() const {
	return cell_scenes.duplicate();
}

void WorldPartition3D::set_cell_scene(const Vector2i &p_cell, const String &p_scene_path) {
	if (p_scene_path.is_empty()) {
		remove_cell_scene(p_cell);
		return;
	}
	if (_get_scene_path(p_cell) == p_scene_path) {
		return;
	}
	_unload_cell(p_cell);
	pending_cells.erase(p_cell);
	failed_cells.erase(p_cell);
	cell_scenes[p_cell] = p_scene_path;
	_purge_unused_ready_scenes();
}

String WorldPartition3D::get_cell_scene(const Vector2i &p_cell) const {
	return _get_scene_path(p_cell);
}

void WorldPartition3D::remove_cell_scene(const Vector2i &p_cell) {
	_unload_cell(p_cell);
	pending_cells.erase(p_cell);
	failed_cells.erase(p_cell);
	pinned_cells.erase(p_cell);
	cell_scenes.erase(p_cell);
	_purge_unused_ready_scenes();
	_refresh_source_readiness();
}

void WorldPartition3D::clear_cell_scenes() {
	_clear_active_cells();
	pending_cells.clear();
	failed_cells.clear();
	pinned_cells.clear();
	cell_scenes.clear();
	_purge_unused_ready_scenes();
	_refresh_source_readiness();
}

int WorldPartition3D::get_configured_cell_count() const {
	return cell_scenes.size();
}

bool WorldPartition3D::pin_cell(const Vector2i &p_cell) {
	// A duplicate pin is an idempotent operation, not another reservation.
	if (pinned_cells.has(p_cell)) {
		return true;
	}
	ERR_FAIL_COND_V_MSG(_get_scene_path(p_cell).is_empty(), false, "WorldPartition3D cannot pin an unregistered cell.");
	ERR_FAIL_COND_V_MSG(pinned_cells.size() >= MAX_PINNED_CELLS, false, "WorldPartition3D pinned-cell limit (16) reached.");
	pinned_cells.insert(p_cell);
	return true;
}

void WorldPartition3D::unpin_cell(const Vector2i &p_cell) {
	pinned_cells.erase(p_cell);
}

void WorldPartition3D::clear_pinned_cells() {
	pinned_cells.clear();
}

bool WorldPartition3D::is_cell_pinned(const Vector2i &p_cell) const {
	return pinned_cells.has(p_cell);
}

int WorldPartition3D::get_pinned_cell_count() const {
	return pinned_cells.size();
}

bool WorldPartition3D::set_streaming_source_node(const String &p_name, const NodePath &p_node_path, int p_load_radius, int p_unload_radius, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_node_path.is_empty() || p_node_path.get_subname_count() > 0, false, "WorldPartition3D moving source requires a nonempty Node3D path, not a property path.");
	// Reuse all name/radius/priority validation and the eight-source limit.
	// Resolution is deferred to update_streaming(), allowing scene setup before
	// the referenced actor has entered the active SceneTree.
	if (!set_streaming_source(p_name, Vector2i(), p_load_radius, p_unload_radius, p_priority)) {
		return false;
	}
	for (int i = 0; i < streaming_sources.size(); i++) {
		StreamingSource &source = streaming_sources.write[i];
		if (source.name == p_name) {
			source.node_path = p_node_path;
			source.active = false;
			return true;
		}
	}
	return false;
}

bool WorldPartition3D::set_streaming_source(const String &p_name, const Vector2i &p_center, int p_load_radius, int p_unload_radius, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_name.is_empty() || p_name.length() > 64, false, "WorldPartition3D source name must have 1 to 64 characters.");
	ERR_FAIL_COND_V_MSG(p_load_radius < 0 || p_load_radius > 4 || p_unload_radius < p_load_radius || p_unload_radius > 8, false, "WorldPartition3D source radii must satisfy 0 <= load <= 4 and load <= unload <= 8.");
	ERR_FAIL_COND_V_MSG(p_priority < 0 || p_priority > 100, false, "WorldPartition3D source priority must be between 0 and 100.");
	const int64_t x = p_center.x;
	const int64_t z = p_center.y;
	ERR_FAIL_COND_V_MSG(x - p_unload_radius < INT32_MIN || x + p_unload_radius > INT32_MAX || z - p_unload_radius < INT32_MIN || z + p_unload_radius > INT32_MAX, false, "WorldPartition3D source radius would overflow cell coordinates.");

	for (int i = 0; i < streaming_sources.size(); i++) {
		StreamingSource &source = streaming_sources.write[i];
		if (source.name != p_name) {
			continue;
		}
		// Mutate an existing source in place; no extra slot is reserved.
		source.center = p_center;
		source.node_path = NodePath();
		source.active = true;
		source.load_radius = p_load_radius;
		source.unload_radius = p_unload_radius;
		source.priority = p_priority;
		return true;
	}
	ERR_FAIL_COND_V_MSG(streaming_sources.size() >= MAX_STREAMING_SOURCES, false, "WorldPartition3D supports at most eight named streaming sources.");
	StreamingSource source;
	source.name = p_name;
	source.center = p_center;
	source.load_radius = p_load_radius;
	source.unload_radius = p_unload_radius;
	source.priority = p_priority;
	streaming_sources.push_back(source);
	return true;
}

void WorldPartition3D::_update_streaming_source_positions() {
	for (int i = 0; i < streaming_sources.size(); i++) {
		StreamingSource &source = streaming_sources.write[i];
		if (source.node_path.is_empty()) {
			source.active = true;
			continue;
		}
		Node3D *target = Object::cast_to<Node3D>(get_node_or_null(source.node_path));
		if (target == nullptr || !target->is_inside_tree()) {
			// Do not keep loading the actor's stale position after removal.
			source.active = false;
			continue;
		}
		const Vector3 local_position = to_local(target->get_global_position());
		if (!local_position.is_finite()) {
			source.active = false;
			continue;
		}
		source.center = local_position_to_cell(local_position);
		source.active = true;
	}
}

void WorldPartition3D::remove_streaming_source(const String &p_name) {
	for (int i = 0; i < streaming_sources.size(); i++) {
		if (streaming_sources[i].name != p_name) {
			continue;
		}
		const bool was_ready = streaming_sources[i].ready;
		streaming_sources.remove_at(i);
		if (was_ready) {
			emit_signal(SNAME("streaming_source_unready"), p_name);
		}
		return;
	}
}

void WorldPartition3D::clear_streaming_sources() {
	Vector<String> lost;
	for (const StreamingSource &source : streaming_sources) {
		if (source.ready) {
			lost.push_back(source.name);
		}
	}
	streaming_sources.clear();
	for (const String &name : lost) {
		emit_signal(SNAME("streaming_source_unready"), name);
	}
}

Dictionary WorldPartition3D::get_streaming_source(const String &p_name) const {
	Dictionary result;
	for (const StreamingSource &source : streaming_sources) {
		if (source.name == p_name) {
			result["center"] = source.center;
			result["node_path"] = source.node_path;
			result["active"] = source.active;
			result["load_radius"] = source.load_radius;
			result["unload_radius"] = source.unload_radius;
			result["priority"] = source.priority;
			result["ready"] = is_streaming_source_ready(p_name);
			result["progress"] = get_streaming_source_progress(p_name);
			return result;
		}
	}
	return result;
}

Array WorldPartition3D::get_streaming_source_names() const {
	Array result;
	for (const StreamingSource &source : streaming_sources) {
		result.push_back(source.name);
	}
	result.sort();
	return result;
}

int WorldPartition3D::get_streaming_source_count() const {
	return streaming_sources.size();
}

bool WorldPartition3D::is_streaming_source_ready(const String &p_name) const {
	if (!streaming_enabled || !is_inside_tree()) {
		return false;
	}
	for (const StreamingSource &source : streaming_sources) {
		if (source.name == p_name) {
			return source.active && are_cells_loaded(source.center, source.load_radius);
		}
	}
	return false;
}

real_t WorldPartition3D::get_streaming_source_progress(const String &p_name) const {
	if (!streaming_enabled || !is_inside_tree()) {
		return 0.0;
	}
	for (const StreamingSource &source : streaming_sources) {
		if (source.name != p_name) {
			continue;
		}
		if (!source.active) {
			return 0.0;
		}
		int loaded = 0;
		const int width = source.load_radius * 2 + 1;
		for (int dz = -source.load_radius; dz <= source.load_radius; dz++) {
			for (int dx = -source.load_radius; dx <= source.load_radius; dx++) {
				const Vector2i cell(source.center.x + dx, source.center.y + dz);
				if (is_cell_loaded(cell)) {
					loaded++;
				}
			}
		}
		return real_t(loaded) / real_t(width * width);
	}
	return 0.0;
}

void WorldPartition3D::_refresh_source_readiness() {
	// Copy transition names before firing callbacks. Callbacks may register,
	// remove, or move sources, invalidating a reference into streaming_sources.
	Vector<String> became_ready;
	Vector<String> became_unready;
	for (int i = 0; i < streaming_sources.size(); i++) {
		StreamingSource &source = streaming_sources.write[i];
		const bool now_ready = streaming_enabled && is_inside_tree() && source.active && are_cells_loaded(source.center, source.load_radius);
		if (now_ready != source.ready) {
			source.ready = now_ready;
			if (now_ready) {
				became_ready.push_back(source.name);
			} else {
				became_unready.push_back(source.name);
			}
		}
	}
	for (const String &name : became_unready) {
		emit_signal(SNAME("streaming_source_unready"), name);
	}
	for (const String &name : became_ready) {
		emit_signal(SNAME("streaming_source_ready"), name);
	}
}


Vector2i WorldPartition3D::local_position_to_cell(const Vector3 &p_local_position) const {
	if (!p_local_position.is_finite()) {
		return Vector2i();
	}
	// Keep a margin from int32 limits for the subsequent radius calculations.
	const real_t x = CLAMP(Math::floor(p_local_position.x / cell_size), real_t(-1000000000), real_t(1000000000));
	const real_t z = CLAMP(Math::floor(p_local_position.z / cell_size), real_t(-1000000000), real_t(1000000000));
	return Vector2i(int(x), int(z));
}

Vector3 WorldPartition3D::cell_to_local_position(const Vector2i &p_cell) const {
	return Vector3(real_t(p_cell.x) * cell_size, 0, real_t(p_cell.y) * cell_size);
}

Array WorldPartition3D::get_cells_in_radius(const Vector2i &p_center, int p_radius) const {
	Array result;
	ERR_FAIL_COND_V_MSG(p_radius < 0 || p_radius > 32, result, "WorldPartition3D query radius must be between 0 and 32.");
	// Do not overflow Vector2i arithmetic near INT32_MIN / INT32_MAX.
	const int64_t x = p_center.x;
	const int64_t z = p_center.y;
	ERR_FAIL_COND_V_MSG(x - p_radius < INT32_MIN || x + p_radius > INT32_MAX || z - p_radius < INT32_MIN || z + p_radius > INT32_MAX, result, "WorldPartition3D query would overflow cell coordinates.");
	for (int dz = -p_radius; dz <= p_radius; dz++) {
		for (int dx = -p_radius; dx <= p_radius; dx++) {
			result.push_back(p_center + Vector2i(dx, dz));
		}
	}
	return result;
}

void WorldPartition3D::update_streaming() {
	const uint64_t update_started_usec = Time::get_singleton()->get_ticks_usec();
	last_instantiation_attempt_count = 0;
	_poll_requests();
	if (!streaming_enabled || !is_inside_tree() || observer_path.is_empty()) {
		_purge_unused_ready_scenes();
		_refresh_processing();
		last_streaming_update_ms = real_t(Time::get_singleton()->get_ticks_usec() - update_started_usec) / 1000.0;
		return;
	}

	Node3D *observer = Object::cast_to<Node3D>(get_node_or_null(observer_path));
	if (observer == nullptr) {
		_purge_unused_ready_scenes();
		last_streaming_update_ms = real_t(Time::get_singleton()->get_ticks_usec() - update_started_usec) / 1000.0;
		return;
	}

	_update_streaming_source_positions();
	const Vector2i center = local_position_to_cell(to_local(observer->get_global_position()));
	// Predictive prefetch is an extra directional corridor, never a replacement
	// for the square around the observer. Overflow-safe 64-bit arithmetic also
	// handles grids near the limits of signed Vector2i coordinates.
	const auto prefetch_coordinate = [&](int p_step, Vector2i &r_cell) -> bool {
		const int64_t x = int64_t(center.x) + int64_t(prefetch_direction.x) * p_step;
		const int64_t z = int64_t(center.y) + int64_t(prefetch_direction.y) * p_step;
		if (x < INT32_MIN || x > INT32_MAX || z < INT32_MIN || z > INT32_MAX) {
			return false;
		}
		r_cell = Vector2i(int32_t(x), int32_t(z));
		return true;
	};
	const auto is_prefetch_cell = [&](const Vector2i &p_cell) -> bool {
		if (prefetch_direction == Vector2i()) {
			return false;
		}
		for (int step = 1; step <= prefetch_distance; step++) {
			Vector2i candidate;
			if (prefetch_coordinate(step, candidate) && candidate == p_cell) {
				return true;
			}
		}
		return false;
	};
	// An additional source retains cells out to unload_radius and requests
	// new cells within load_radius, independently of the player and pins.
	const auto is_source_cell = [&](const Vector2i &p_cell, bool p_for_unload) -> bool {
		for (const StreamingSource &source : streaming_sources) {
			if (source.active && _within_radius(p_cell, source.center, p_for_unload ? source.unload_radius : source.load_radius)) {
				return true;
			}
		}
		return false;
	};
	const bool observer_cell_changed = !observer_cell_valid || observer_cell != center;
	observer_cell = center;
	observer_cell_valid = true;

	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if ((!_within_radius(E.key, center, unload_radius) && !is_prefetch_cell(E.key) && !pinned_cells.has(E.key) && !is_source_cell(E.key, true)) || ObjectDB::get_instance(E.value) == nullptr) {
			unload.push_back(E.key);
		}
	}
	for (const Vector2i &cell : unload) {
		_unload_cell(cell);
	}

	Vector<Vector2i> cancel;
	for (const KeyValue<Vector2i, String> &E : pending_cells) {
		if (!_within_radius(E.key, center, load_radius) && !is_prefetch_cell(E.key) && !pinned_cells.has(E.key) && !is_source_cell(E.key, false)) {
			cancel.push_back(E.key);
		}
	}
	for (const Vector2i &cell : cancel) {
		pending_cells.erase(cell);
	}

	int new_requests = max_new_requests_per_frame;
	int instances = max_instances_per_frame;
	int attempted_instances = 0;
	const uint64_t start_usec = Time::get_singleton()->get_ticks_usec();
	// The soft wall-time budget prevents a sequence of expensive scene _ready()
	// calls from consuming a large frame. Always allow the first ready cell to
	// instantiate, so tiny budgets cannot starve streaming entirely.
	const auto can_instantiate = [&]() {
		return instances > 0 && (max_instantiation_time_ms <= 0.0 || attempted_instances == 0 ||
				(Time::get_singleton()->get_ticks_usec() - start_usec) < uint64_t(max_instantiation_time_ms * 1000.0));
	};
	// Observer cells always get priority; the corridor is visited only after
	// the normal load radius. Both passes share the exact same resource, scene
	// instantiation and wall-time budgets.
	const auto visit_cell = [&](const Vector2i &cell) {
		if (active_cells.has(cell) || failed_cells.has(cell)) {
			return;
		}
		const String path = _get_scene_path(cell);
		if (path.is_empty()) {
			return;
		}
		if (pending_cells.has(cell)) {
			const Ref<PackedScene> *scene = ready_scenes.getptr(path);
			if (scene != nullptr && can_instantiate()) {
				if (!_instantiate_cell(cell, *scene)) {
					failed_cells.insert(cell);
				}
				pending_cells.erase(cell);
				instances--;
				attempted_instances++;
			}
			return;
		}
		if (ready_scenes.has(path)) {
			pending_cells.insert(cell, path);
			const Ref<PackedScene> *scene = ready_scenes.getptr(path);
			if (scene != nullptr && can_instantiate()) {
				if (!_instantiate_cell(cell, *scene)) {
					failed_cells.insert(cell);
				}
				pending_cells.erase(cell);
				instances--;
				attempted_instances++;
			}
			return;
		}
		if (requested_paths.has(path)) {
			pending_cells.insert(cell, path);
			return;
		}
		if (new_requests <= 0 || requested_paths.size() >= max_concurrent_requests) {
			return;
		}
		const Error err = ResourceLoader::load_threaded_request(path, "PackedScene");
		if (err == OK) {
			requested_paths.insert(path);
			pending_cells.insert(cell, path);
			new_requests--;
		} else {
			ERR_PRINT(vformat("WorldPartition3D: unable to request %s (%d).", path, int(err)));
			failed_cells.insert(cell);
		}
	};

	// Near-first and deterministic for the current observer cell.
	for (int radius = 0; radius <= load_radius; radius++) {
		for (int dz = -radius; dz <= radius; dz++) {
			for (int dx = -radius; dx <= radius; dx++) {
				if (MAX(ABS(dx), ABS(dz)) != radius) {
					continue;
				}
				const int64_t x = int64_t(center.x) + dx;
				const int64_t z = int64_t(center.y) + dz;
				if (x < INT32_MIN || x > INT32_MAX || z < INT32_MIN || z > INT32_MAX) {
					continue;
				}
				visit_cell(Vector2i(int32_t(x), int32_t(z)));
			}
		}
	}

	// Explicitly pinned regions are an independent, bounded streaming source.
	// They retain unloaded/loaded cells beyond the observer's radius and are
	// processed after nearby physics cells but before speculative prefetch.
	// Pins share the same request deduplication and per-frame budgets.
	Vector<Vector2i> pinned_snapshot;
	for (const Vector2i &cell : pinned_cells) {
		pinned_snapshot.push_back(cell);
	}
	// Signal callbacks from _instantiate_cell may pin/unpin cells. Iterate a
	// snapshot, and process surviving pins in a deterministic grid order.
	for (int i = 1; i < pinned_snapshot.size(); i++) {
		const Vector2i value = pinned_snapshot[i];
		int j = i;
		while (j > 0 && (pinned_snapshot[j - 1].x > value.x ||
				(pinned_snapshot[j - 1].x == value.x && pinned_snapshot[j - 1].y > value.y))) {
			pinned_snapshot.write[j] = pinned_snapshot[j - 1];
			j--;
		}
		pinned_snapshot.write[j] = value;
	}
	for (const Vector2i &cell : pinned_snapshot) {
		if (pinned_cells.has(cell)) {
			visit_cell(cell);
		}
	}

	// Named sources are visited after the player and explicit pins, but before
	// speculative lookahead. Higher priorities win the shared frame budgets.
	Vector<StreamingSource> source_snapshot = streaming_sources;
	for (int i = 1; i < source_snapshot.size(); i++) {
		const StreamingSource item = source_snapshot[i];
		int j = i;
		while (j > 0 && (source_snapshot[j - 1].priority < item.priority ||
				(source_snapshot[j - 1].priority == item.priority && source_snapshot[j - 1].name.naturalnocasecmp_to(item.name) > 0))) {
			source_snapshot.write[j] = source_snapshot[j - 1];
			j--;
		}
		source_snapshot.write[j] = item;
	}
	for (const StreamingSource &source : source_snapshot) {
		if (!source.active) {
			continue;
		}
		for (int radius = 0; radius <= source.load_radius; radius++) {
			for (int dz = -radius; dz <= radius; dz++) {
				for (int dx = -radius; dx <= radius; dx++) {
					if (MAX(ABS(dx), ABS(dz)) != radius) {
						continue;
					}
					const int64_t x = int64_t(source.center.x) + dx;
					const int64_t z = int64_t(source.center.y) + dz;
					if (x < INT32_MIN || x > INT32_MAX || z < INT32_MIN || z > INT32_MAX) {
						continue;
					}
					// A cell_loaded callback may mutate the sources while _ready()
					// runs. Skip stale source snapshots after reconfiguration.
					bool still_current = false;
					for (const StreamingSource &current : streaming_sources) {
						if (current.active && current.name == source.name && current.center == source.center &&
								current.node_path == source.node_path &&
								current.load_radius == source.load_radius && current.unload_radius == source.unload_radius &&
								current.priority == source.priority) {
							still_current = true;
							break;
						}
					}
					if (still_current) {
						visit_cell(Vector2i(int32_t(x), int32_t(z)));
					}
				}
			}
		}
	}

	// Optional direction-aware corridor, including cells beyond load_radius.
	// No duplicate requests occur: the core path checks active/pending cells.
	if (prefetch_direction != Vector2i()) {
		for (int step = 1; step <= prefetch_distance; step++) {
			Vector2i ahead;
			if (prefetch_coordinate(step, ahead) && !_within_radius(ahead, center, load_radius)) {
				visit_cell(ahead);
			}
		}
	}
	_purge_unused_ready_scenes();
	last_instantiation_attempt_count = attempted_instances;
	last_streaming_update_ms = real_t(Time::get_singleton()->get_ticks_usec() - update_started_usec) / 1000.0;
	_refresh_source_readiness();
	if (observer_cell_changed) {
		emit_signal(SNAME("observer_cell_changed"), observer_cell);
	}
}

bool WorldPartition3D::is_cell_loaded(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	return id != nullptr && ObjectDB::get_instance(*id) != nullptr;
}

bool WorldPartition3D::is_cell_physics_ready(const Vector2i &p_cell) const {
	if (!streaming_enabled || !is_inside_tree() || !physics_ready_cells.has(p_cell)) {
		return false;
	}
	Node3D *node = get_cell_node(p_cell);
	return node != nullptr && !node->is_queued_for_deletion();
}

bool WorldPartition3D::are_cells_physics_ready(const Vector2i &p_center, int p_radius) const {
	ERR_FAIL_COND_V_MSG(p_radius < 0 || p_radius > 32, false, "WorldPartition3D physics-ready query radius must be between 0 and 32.");
	const Array cells = get_cells_in_radius(p_center, p_radius);
	if (cells.is_empty()) {
		return false;
	}
	for (int i = 0; i < cells.size(); i++) {
		if (!is_cell_physics_ready(cells[i])) {
			return false;
		}
	}
	return true;
}

int WorldPartition3D::get_physics_ready_cell_count() const {
	if (!streaming_enabled || !is_inside_tree()) {
		return 0;
	}
	// Defensive accounting: a game might manually free a streamed scene root
	// before the next streaming update purges its ObjectID.
	int result = 0;
	for (const Vector2i &cell : physics_ready_cells) {
		if (is_cell_physics_ready(cell)) {
			result++;
		}
	}
	return result;
}

Node3D *WorldPartition3D::get_cell_node(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	if (id == nullptr) {
		return nullptr;
	}
	return Object::cast_to<Node3D>(ObjectDB::get_instance(*id));
}

bool WorldPartition3D::are_cells_loaded(const Vector2i &p_center, int p_radius) const {
	ERR_FAIL_COND_V_MSG(p_radius < 0 || p_radius > 32, false, "WorldPartition3D region readiness radius must be between 0 and 32.");
	// A checked 64-bit bounds calculation prevents overflow when testing a
	// region near the limits of Vector2i. All its requested cells must be
	// instantiated; missing or unregistered cells are not considered ready.
	const int64_t low_x = int64_t(p_center.x) - p_radius;
	const int64_t high_x = int64_t(p_center.x) + p_radius;
	const int64_t low_z = int64_t(p_center.y) - p_radius;
	const int64_t high_z = int64_t(p_center.y) + p_radius;
	if (low_x < INT32_MIN || high_x > INT32_MAX || low_z < INT32_MIN || high_z > INT32_MAX) {
		return false;
	}
	for (int dz = -p_radius; dz <= p_radius; dz++) {
		for (int dx = -p_radius; dx <= p_radius; dx++) {
			if (!is_cell_loaded(Vector2i(p_center.x + dx, p_center.y + dz))) {
				return false;
			}
		}
	}
	return true;
}

int WorldPartition3D::get_loaded_cell_count() const {
	return active_cells.size();
}

Array WorldPartition3D::get_loaded_cells() const {
	Array result;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (ObjectDB::get_instance(E.value) != nullptr) {
			result.push_back(E.key);
		}
	}
	return result;
}

int WorldPartition3D::get_pending_cell_count() const {
	return pending_cells.size();
}

int WorldPartition3D::get_inflight_request_count() const {
	return requested_paths.size();
}

int WorldPartition3D::get_failed_cell_count() const {
	return failed_cells.size();
}

void WorldPartition3D::retry_failed_cells() {
	// Explicit recovery for transient IO/network/editor asset errors.
	// Do not automatically retry failed cells every frame: permanent failures
	// would otherwise generate continuous resource requests and log spam.
	// The next update_streaming() call reschedules relevant registered cells.
	failed_cells.clear();
}

real_t WorldPartition3D::get_last_streaming_update_ms() const {
	return last_streaming_update_ms;
}

int WorldPartition3D::get_last_instantiation_attempt_count() const {
	return last_instantiation_attempt_count;
}

void WorldPartition3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &WorldPartition3D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &WorldPartition3D::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_load_radius", "radius"), &WorldPartition3D::set_load_radius);
	ClassDB::bind_method(D_METHOD("get_load_radius"), &WorldPartition3D::get_load_radius);
	ClassDB::bind_method(D_METHOD("set_unload_radius", "radius"), &WorldPartition3D::set_unload_radius);
	ClassDB::bind_method(D_METHOD("get_unload_radius"), &WorldPartition3D::get_unload_radius);
	ClassDB::bind_method(D_METHOD("set_prefetch_direction", "direction"), &WorldPartition3D::set_prefetch_direction);
	ClassDB::bind_method(D_METHOD("get_prefetch_direction"), &WorldPartition3D::get_prefetch_direction);
	ClassDB::bind_method(D_METHOD("set_prefetch_distance", "distance"), &WorldPartition3D::set_prefetch_distance);
	ClassDB::bind_method(D_METHOD("get_prefetch_distance"), &WorldPartition3D::get_prefetch_distance);
	ClassDB::bind_method(D_METHOD("set_max_new_requests_per_frame", "count"), &WorldPartition3D::set_max_new_requests_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_new_requests_per_frame"), &WorldPartition3D::get_max_new_requests_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_instances_per_frame", "count"), &WorldPartition3D::set_max_instances_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_instances_per_frame"), &WorldPartition3D::get_max_instances_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_instantiation_time_ms", "milliseconds"), &WorldPartition3D::set_max_instantiation_time_ms);
	ClassDB::bind_method(D_METHOD("get_max_instantiation_time_ms"), &WorldPartition3D::get_max_instantiation_time_ms);
	ClassDB::bind_method(D_METHOD("set_max_concurrent_requests", "count"), &WorldPartition3D::set_max_concurrent_requests);
	ClassDB::bind_method(D_METHOD("get_max_concurrent_requests"), &WorldPartition3D::get_max_concurrent_requests);
	ClassDB::bind_method(D_METHOD("set_streaming_enabled", "enabled"), &WorldPartition3D::set_streaming_enabled);
	ClassDB::bind_method(D_METHOD("is_streaming_enabled"), &WorldPartition3D::is_streaming_enabled);
	ClassDB::bind_method(D_METHOD("set_observer_path", "path"), &WorldPartition3D::set_observer_path);
	ClassDB::bind_method(D_METHOD("get_observer_path"), &WorldPartition3D::get_observer_path);
	ClassDB::bind_method(D_METHOD("has_observer_cell"), &WorldPartition3D::has_observer_cell);
	ClassDB::bind_method(D_METHOD("get_observer_cell"), &WorldPartition3D::get_observer_cell);
	ClassDB::bind_method(D_METHOD("set_cell_scenes", "scenes"), &WorldPartition3D::set_cell_scenes);
	ClassDB::bind_method(D_METHOD("get_cell_scenes"), &WorldPartition3D::get_cell_scenes);
	ClassDB::bind_method(D_METHOD("set_cell_scene", "cell", "scene_path"), &WorldPartition3D::set_cell_scene);
	ClassDB::bind_method(D_METHOD("get_cell_scene", "cell"), &WorldPartition3D::get_cell_scene);
	ClassDB::bind_method(D_METHOD("remove_cell_scene", "cell"), &WorldPartition3D::remove_cell_scene);
	ClassDB::bind_method(D_METHOD("clear_cell_scenes"), &WorldPartition3D::clear_cell_scenes);
	ClassDB::bind_method(D_METHOD("get_configured_cell_count"), &WorldPartition3D::get_configured_cell_count);
	ClassDB::bind_method(D_METHOD("pin_cell", "cell"), &WorldPartition3D::pin_cell);
	ClassDB::bind_method(D_METHOD("unpin_cell", "cell"), &WorldPartition3D::unpin_cell);
	ClassDB::bind_method(D_METHOD("clear_pinned_cells"), &WorldPartition3D::clear_pinned_cells);
	ClassDB::bind_method(D_METHOD("is_cell_pinned", "cell"), &WorldPartition3D::is_cell_pinned);
	ClassDB::bind_method(D_METHOD("get_pinned_cell_count"), &WorldPartition3D::get_pinned_cell_count);
	ClassDB::bind_method(D_METHOD("set_streaming_source", "name", "center", "load_radius", "unload_radius", "priority"), &WorldPartition3D::set_streaming_source);
	ClassDB::bind_method(D_METHOD("set_streaming_source_node", "name", "node_path", "load_radius", "unload_radius", "priority"), &WorldPartition3D::set_streaming_source_node);
	ClassDB::bind_method(D_METHOD("remove_streaming_source", "name"), &WorldPartition3D::remove_streaming_source);
	ClassDB::bind_method(D_METHOD("clear_streaming_sources"), &WorldPartition3D::clear_streaming_sources);
	ClassDB::bind_method(D_METHOD("get_streaming_source", "name"), &WorldPartition3D::get_streaming_source);
	ClassDB::bind_method(D_METHOD("get_streaming_source_names"), &WorldPartition3D::get_streaming_source_names);
	ClassDB::bind_method(D_METHOD("get_streaming_source_count"), &WorldPartition3D::get_streaming_source_count);
	ClassDB::bind_method(D_METHOD("is_streaming_source_ready", "name"), &WorldPartition3D::is_streaming_source_ready);
	ClassDB::bind_method(D_METHOD("get_streaming_source_progress", "name"), &WorldPartition3D::get_streaming_source_progress);
	ClassDB::bind_method(D_METHOD("local_position_to_cell", "local_position"), &WorldPartition3D::local_position_to_cell);
	ClassDB::bind_method(D_METHOD("cell_to_local_position", "cell"), &WorldPartition3D::cell_to_local_position);
	ClassDB::bind_method(D_METHOD("get_cells_in_radius", "center", "radius"), &WorldPartition3D::get_cells_in_radius);
	ClassDB::bind_method(D_METHOD("update_streaming"), &WorldPartition3D::update_streaming);
	ClassDB::bind_method(D_METHOD("is_cell_loaded", "cell"), &WorldPartition3D::is_cell_loaded);
	ClassDB::bind_method(D_METHOD("is_cell_physics_ready", "cell"), &WorldPartition3D::is_cell_physics_ready);
	ClassDB::bind_method(D_METHOD("are_cells_physics_ready", "center", "radius"), &WorldPartition3D::are_cells_physics_ready, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_physics_ready_cell_count"), &WorldPartition3D::get_physics_ready_cell_count);
	ClassDB::bind_method(D_METHOD("is_cell_navigation_ready", "cell"), &WorldPartition3D::is_cell_navigation_ready);
	ClassDB::bind_method(D_METHOD("are_cells_navigation_ready", "center", "radius"), &WorldPartition3D::are_cells_navigation_ready, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_navigation_ready_cell_count"), &WorldPartition3D::get_navigation_ready_cell_count);
	ClassDB::bind_method(D_METHOD("get_navigation_pending_cell_count"), &WorldPartition3D::get_navigation_pending_cell_count);
	ClassDB::bind_method(D_METHOD("get_navigation_route_cells", "from_global", "to_global", "max_cells"), &WorldPartition3D::get_navigation_route_cells, DEFVAL(64));
	ClassDB::bind_method(D_METHOD("is_navigation_route_ready", "from_global", "to_global", "max_cells"), &WorldPartition3D::is_navigation_route_ready, DEFVAL(64));
	ClassDB::bind_method(D_METHOD("get_streamed_navigation_path", "from_global", "to_global", "optimize", "navigation_layers", "max_cells"), &WorldPartition3D::get_streamed_navigation_path, DEFVAL(true), DEFVAL(1), DEFVAL(64));
	ClassDB::bind_method(D_METHOD("is_streaming_source_navigation_ready", "name"), &WorldPartition3D::is_streaming_source_navigation_ready);
	ClassDB::bind_method(D_METHOD("get_streaming_source_navigation_progress", "name"), &WorldPartition3D::get_streaming_source_navigation_progress);
	ClassDB::bind_method(D_METHOD("get_cell_node", "cell"), &WorldPartition3D::get_cell_node);
	ClassDB::bind_method(D_METHOD("are_cells_loaded", "center", "radius"), &WorldPartition3D::are_cells_loaded, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_loaded_cell_count"), &WorldPartition3D::get_loaded_cell_count);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldPartition3D::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("get_pending_cell_count"), &WorldPartition3D::get_pending_cell_count);
	ClassDB::bind_method(D_METHOD("get_inflight_request_count"), &WorldPartition3D::get_inflight_request_count);
	ClassDB::bind_method(D_METHOD("get_failed_cell_count"), &WorldPartition3D::get_failed_cell_count);
	ClassDB::bind_method(D_METHOD("retry_failed_cells"), &WorldPartition3D::retry_failed_cells);
	ClassDB::bind_method(D_METHOD("get_last_streaming_update_ms"), &WorldPartition3D::get_last_streaming_update_ms);
	ClassDB::bind_method(D_METHOD("get_last_instantiation_attempt_count"), &WorldPartition3D::get_last_instantiation_attempt_count);

	ADD_GROUP("World Grid", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,4096,1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cell_scenes"), "set_cell_scenes", "get_cell_scenes");
	ADD_GROUP("Streaming", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "streaming_enabled"), "set_streaming_enabled", "is_streaming_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "observer_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_observer_path", "get_observer_path");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "load_radius", PROPERTY_HINT_RANGE, "0,32,1"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "unload_radius", PROPERTY_HINT_RANGE, "0,64,1"), "set_unload_radius", "get_unload_radius");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "prefetch_direction"), "set_prefetch_direction", "get_prefetch_direction");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "prefetch_distance", PROPERTY_HINT_RANGE, "0,4,1"), "set_prefetch_distance", "get_prefetch_distance");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_new_requests_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_new_requests_per_frame", "get_max_new_requests_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instances_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_instances_per_frame", "get_max_instances_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_instantiation_time_ms", PROPERTY_HINT_RANGE, "0,100,0.1,suffix:ms"), "set_max_instantiation_time_ms", "get_max_instantiation_time_ms");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_requests", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_concurrent_requests", "get_max_concurrent_requests");

	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_physics_ready", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_physics_unready", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_navigation_ready", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_navigation_unready", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("observer_cell_changed", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("streaming_source_ready", PropertyInfo(Variant::STRING, "name")));
	ADD_SIGNAL(MethodInfo("streaming_source_unready", PropertyInfo(Variant::STRING, "name")));
}

WorldPartition3D::~WorldPartition3D() {
	// ResourceLoader user requests MUST be collected to release their load tokens.
	// A currently running request may block until finished at node destruction.
	for (const String &path : requested_paths) {
		ResourceLoader::load_threaded_get(path);
	}
	requested_paths.clear();
	// Child nodes belong to Node; drop references without touching queued deletions.
	active_cells.clear();
	physics_pending_cells.clear();
	physics_ready_cells.clear();
	navigation_pending_regions.clear();
	navigation_ready_regions.clear();
	pending_cells.clear();
	ready_scenes.clear();
}
