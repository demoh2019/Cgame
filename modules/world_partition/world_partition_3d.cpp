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
	emit_signal(SNAME("cell_loaded"), p_cell);
	return true;
}

void WorldPartition3D::_refresh_processing() {
	if (is_inside_tree()) {
		set_process(!Engine::get_singleton()->is_editor_hint() && (streaming_enabled || !requested_paths.is_empty()));
	}
}

void WorldPartition3D::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY) {
		_refresh_processing();
	} else if (p_what == NOTIFICATION_PROCESS) {
		update_streaming();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		// A future re-entry should report the first resolved observer cell.
		observer_cell_valid = false;
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
	cell_scenes = clean;
	_purge_unused_ready_scenes();
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
	cell_scenes.erase(p_cell);
	_purge_unused_ready_scenes();
}

void WorldPartition3D::clear_cell_scenes() {
	_clear_active_cells();
	pending_cells.clear();
	failed_cells.clear();
	cell_scenes.clear();
	_purge_unused_ready_scenes();
}

int WorldPartition3D::get_configured_cell_count() const {
	return cell_scenes.size();
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
	const bool observer_cell_changed = !observer_cell_valid || observer_cell != center;
	observer_cell = center;
	observer_cell_valid = true;

	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if ((!_within_radius(E.key, center, unload_radius) && !is_prefetch_cell(E.key)) || ObjectDB::get_instance(E.value) == nullptr) {
			unload.push_back(E.key);
		}
	}
	for (const Vector2i &cell : unload) {
		_unload_cell(cell);
	}

	Vector<Vector2i> cancel;
	for (const KeyValue<Vector2i, String> &E : pending_cells) {
		if (!_within_radius(E.key, center, load_radius) && !is_prefetch_cell(E.key)) {
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
	if (observer_cell_changed) {
		emit_signal(SNAME("observer_cell_changed"), observer_cell);
	}
}

bool WorldPartition3D::is_cell_loaded(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	return id != nullptr && ObjectDB::get_instance(*id) != nullptr;
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
	ClassDB::bind_method(D_METHOD("local_position_to_cell", "local_position"), &WorldPartition3D::local_position_to_cell);
	ClassDB::bind_method(D_METHOD("cell_to_local_position", "cell"), &WorldPartition3D::cell_to_local_position);
	ClassDB::bind_method(D_METHOD("get_cells_in_radius", "center", "radius"), &WorldPartition3D::get_cells_in_radius);
	ClassDB::bind_method(D_METHOD("update_streaming"), &WorldPartition3D::update_streaming);
	ClassDB::bind_method(D_METHOD("is_cell_loaded", "cell"), &WorldPartition3D::is_cell_loaded);
	ClassDB::bind_method(D_METHOD("get_cell_node", "cell"), &WorldPartition3D::get_cell_node);
	ClassDB::bind_method(D_METHOD("are_cells_loaded", "center", "radius"), &WorldPartition3D::are_cells_loaded, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_loaded_cell_count"), &WorldPartition3D::get_loaded_cell_count);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldPartition3D::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("get_pending_cell_count"), &WorldPartition3D::get_pending_cell_count);
	ClassDB::bind_method(D_METHOD("get_inflight_request_count"), &WorldPartition3D::get_inflight_request_count);
	ClassDB::bind_method(D_METHOD("get_failed_cell_count"), &WorldPartition3D::get_failed_cell_count);
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
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("observer_cell_changed", PropertyInfo(Variant::VECTOR2I, "cell")));
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
	pending_cells.clear();
	ready_scenes.clear();
}
