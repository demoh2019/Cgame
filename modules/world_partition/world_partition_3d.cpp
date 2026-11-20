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
#include "scene/main/node.h"

#include <cstdint>

bool WorldPartition3D::_within_radius(const Vector2i &p_cell, const Vector2i &p_center, int p_radius) {
	const int64_t dx = int64_t(p_cell.x) - p_center.x;
	const int64_t dz = int64_t(p_cell.y) - p_center.y;
	return dx >= -p_radius && dx <= p_radius && dz >= -p_radius && dz <= p_radius;
}

void WorldPartition3D::_append_source_center(const NodePath &p_path, Vector<Vector2i> &r_centers) const {
	if (p_path.is_empty()) {
		return;
	}
	Node3D *observer = Object::cast_to<Node3D>(get_node_or_null(p_path));
	if (observer == nullptr) {
		return;
	}
	const Vector2i center = local_position_to_cell(to_local(observer->get_global_position()));
	if (!r_centers.has(center)) {
		r_centers.push_back(center);
	}
}

bool WorldPartition3D::_within_any_radius(const Vector2i &p_cell, const Vector<Vector2i> &p_centers, int p_radius) const {
	for (const Vector2i &center : p_centers) {
		if (_within_radius(p_cell, center, p_radius)) {
			return true;
		}
	}
	return false;
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

void WorldPartition3D::_capture_cell_state(const Vector2i &p_cell, Node *p_instance) {
	if (p_instance == nullptr || !p_instance->has_method(SNAME("capture_streaming_state"))) {
		return;
	}
	const Variant result = p_instance->call(SNAME("capture_streaming_state"));
	if (result.get_type() != Variant::DICTIONARY) {
		WARN_PRINT(vformat("WorldPartition3D: cell %s capture_streaming_state() must return a Dictionary.", p_cell));
		return;
	}
	const Dictionary state = result;
	if (state.is_empty()) {
		saved_cell_states.erase(p_cell);
	} else {
		saved_cell_states.insert(p_cell, state.duplicate(true));
	}
}

void WorldPartition3D::_restore_cell_state(const Vector2i &p_cell, Node *p_instance) {
	const Dictionary *state = saved_cell_states.getptr(p_cell);
	if (p_instance != nullptr && state != nullptr && p_instance->has_method(SNAME("restore_streaming_state"))) {
		// Pass a defensive copy; scripts cannot mutate the saved value implicitly.
		p_instance->call(SNAME("restore_streaming_state"), state->duplicate(true));
	}
}

void WorldPartition3D::_unload_cell(const Vector2i &p_cell) {
	const ObjectID *id = active_cells.getptr(p_cell);
	if (id == nullptr) {
		return;
	}

	Node *node = Object::cast_to<Node>(ObjectDB::get_instance(*id));
	if (node != nullptr) {
		_capture_cell_state(p_cell, node);
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
	// Restoring after _ready() allows scene scripts to create their visuals first.
	_restore_cell_state(p_cell, instance);
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
	}
}

void WorldPartition3D::set_cell_size(real_t p_size) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_size) || p_size <= 0, "WorldPartition3D cell_size must be finite and positive.");
	if (Math::is_equal_approx(cell_size, p_size)) {
		return;
	}
	cell_size = p_size;
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

void WorldPartition3D::set_max_unloads_per_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 128, "WorldPartition3D unload budget must be between 1 and 128.");
	max_unloads_per_frame = p_count;
}

int WorldPartition3D::get_max_unloads_per_frame() const {
	return max_unloads_per_frame;
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
	observer_path = p_path;
}

NodePath WorldPartition3D::get_observer_path() const {
	return observer_path;
}

void WorldPartition3D::set_additional_observer_paths(const Array &p_paths) {
	ERR_FAIL_COND_MSG(p_paths.size() > 16, "WorldPartition3D supports at most 16 additional observer paths.");
	Array clean;
	for (int i = 0; i < p_paths.size(); i++) {
		if (p_paths[i].get_type() != Variant::NODE_PATH) {
			continue;
		}
		const NodePath path = p_paths[i];
		if (!path.is_empty() && !clean.has(path)) {
			clean.push_back(path);
		}
	}
	additional_observer_paths = clean;
}

Array WorldPartition3D::get_additional_observer_paths() const {
	return additional_observer_paths.duplicate();
}

void WorldPartition3D::set_pinned_cells(const Array &p_cells) {
	ERR_FAIL_COND_MSG(p_cells.size() > 128, "WorldPartition3D supports at most 128 pinned cells.");
	Vector<Vector2i> clean;
	for (int i = 0; i < p_cells.size(); i++) {
		if (p_cells[i].get_type() != Variant::VECTOR2I) {
			continue;
		}
		const Vector2i cell = p_cells[i];
		if (!clean.has(cell)) {
			clean.push_back(cell);
		}
	}
	const bool had_pins = !pinned_cells.is_empty();
	pinned_cells = clean;
	if (pinned_cells.is_empty() && had_pins) {
		unload_after_last_pin_removed = true;
	} else if (!pinned_cells.is_empty()) {
		unload_after_last_pin_removed = false;
	}
}

void WorldPartition3D::pin_cell(const Vector2i &p_cell) {
	if (pinned_cells.has(p_cell)) {
		return;
	}
	ERR_FAIL_COND_MSG(pinned_cells.size() >= 128, "WorldPartition3D supports at most 128 pinned cells.");
	pinned_cells.push_back(p_cell);
	unload_after_last_pin_removed = false;
}

void WorldPartition3D::unpin_cell(const Vector2i &p_cell) {
	if (pinned_cells.has(p_cell)) {
		pinned_cells.erase(p_cell);
		unload_after_last_pin_removed = true;
	}
}

void WorldPartition3D::clear_pinned_cells() {
	if (!pinned_cells.is_empty()) {
		pinned_cells.clear();
		unload_after_last_pin_removed = true;
	}
}

bool WorldPartition3D::is_cell_pinned(const Vector2i &p_cell) const {
	return pinned_cells.has(p_cell);
}

Array WorldPartition3D::get_pinned_cells() const {
	Array cells;
	for (const Vector2i &cell : pinned_cells) {
		cells.push_back(cell);
	}
	return cells;
}

int WorldPartition3D::get_pinned_cell_count() const {
	return pinned_cells.size();
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

void WorldPartition3D::_stream_candidate_cell(const Vector2i &p_cell, int &r_new_requests, int &r_instances) {
	// Shared request and instance budgets for pinned and observer cells.
	if (active_cells.has(p_cell) || failed_cells.has(p_cell)) {
		return;
	}
	const String path = _get_scene_path(p_cell);
	if (path.is_empty()) {
		return;
	}
	if (pending_cells.has(p_cell)) {
		const Ref<PackedScene> *scene = ready_scenes.getptr(path);
		if (scene != nullptr && r_instances > 0) {
			if (!_instantiate_cell(p_cell, *scene)) {
				failed_cells.insert(p_cell);
			}
			pending_cells.erase(p_cell);
			r_instances--;
		}
		return;
	}
	if (ready_scenes.has(path)) {
		pending_cells.insert(p_cell, path);
		const Ref<PackedScene> *scene = ready_scenes.getptr(path);
		if (r_instances > 0 && scene != nullptr) {
			if (!_instantiate_cell(p_cell, *scene)) {
				failed_cells.insert(p_cell);
			}
			pending_cells.erase(p_cell);
			r_instances--;
		}
		return;
	}
	if (requested_paths.has(path)) {
		pending_cells.insert(p_cell, path);
		return;
	}
	if (r_new_requests <= 0 || requested_paths.size() >= max_concurrent_requests) {
		return;
	}
	const Error err = ResourceLoader::load_threaded_request(path, "PackedScene");
	if (err == OK) {
		requested_paths.insert(path);
		pending_cells.insert(p_cell, path);
		r_new_requests--;
	} else {
		ERR_PRINT(vformat("WorldPartition3D: unable to request %s (%d).", path, int(err)));
		failed_cells.insert(p_cell);
	}
}

void WorldPartition3D::set_cell_state(const Vector2i &p_cell, const Dictionary &p_state) {
	if (p_state.is_empty()) {
		saved_cell_states.erase(p_cell);
	} else {
		saved_cell_states.insert(p_cell, p_state.duplicate(true));
	}
	_restore_cell_state(p_cell, get_cell_instance(p_cell));
}

Dictionary WorldPartition3D::get_cell_state(const Vector2i &p_cell) const {
	const Dictionary *state = saved_cell_states.getptr(p_cell);
	return state != nullptr ? state->duplicate(true) : Dictionary();
}

bool WorldPartition3D::has_cell_state(const Vector2i &p_cell) const {
	return saved_cell_states.has(p_cell);
}

void WorldPartition3D::erase_cell_state(const Vector2i &p_cell) {
	saved_cell_states.erase(p_cell);
}

void WorldPartition3D::clear_cell_states() {
	saved_cell_states.clear();
}

Dictionary WorldPartition3D::snapshot_cell_states() {
	// Include gameplay changes in cells still resident, not only those unloaded.
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
		_capture_cell_state(E.key, instance);
	}
	Dictionary snapshot;
	for (const KeyValue<Vector2i, Dictionary> &E : saved_cell_states) {
		snapshot[E.key] = E.value.duplicate(true);
	}
	return snapshot;
}

void WorldPartition3D::load_cell_states(const Dictionary &p_states) {
	HashMap<Vector2i, Dictionary> accepted;
	const Array keys = p_states.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		const Variant value = p_states[key];
		if (key.get_type() == Variant::VECTOR2I && value.get_type() == Variant::DICTIONARY) {
			const Dictionary state = value;
			if (!state.is_empty()) {
				accepted.insert(key, state.duplicate(true));
			}
		}
	}
	saved_cell_states = accepted;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
		_restore_cell_state(E.key, instance);
	}
}

int WorldPartition3D::get_cell_state_count() const {
	return saved_cell_states.size();
}

void WorldPartition3D::update_streaming() {
	_poll_requests();
	if (!streaming_enabled || !is_inside_tree()) {
		_purge_unused_ready_scenes();
		_refresh_processing();
		return;
	}

	// The legacy primary source is first, followed by optional camera, co-op or
	// prefetch sources. Multiple observers within one cell share a center.
	Vector<Vector2i> centers;
	_append_source_center(observer_path, centers);
	for (int i = 0; i < additional_observer_paths.size(); i++) {
		const NodePath path = additional_observer_paths[i];
		_append_source_center(path, centers);
	}
	if (!centers.is_empty()) {
		// With a valid observer, ordinary distance-based eviction runs normally.
		unload_after_last_pin_removed = false;
	}
	if (centers.is_empty() && pinned_cells.is_empty() && !unload_after_last_pin_removed) {
		// Preserve cells if all observer nodes disappear temporarily without
		// an explicit pin release (e.g., a brief scene-tree reparenting).
		_purge_unused_ready_scenes();
		if (observer_path.is_empty() && additional_observer_paths.is_empty()) {
			_refresh_processing();
		}
		return;
	}

	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if ((!pinned_cells.has(E.key) && !_within_any_radius(E.key, centers, unload_radius)) || ObjectDB::get_instance(E.value) == nullptr) {
			unload.push_back(E.key);
		}
	}
	// Spreading large unload bursts across frames avoids deleting hundreds of
	// scene hierarchies after a teleport. Explicit clears still unload all cells.
	int removed = 0;
	for (const Vector2i &cell : unload) {
		if (removed >= max_unloads_per_frame) {
			break;
		}
		_unload_cell(cell);
		removed++;
	}

	Vector<Vector2i> cancel;
	for (const KeyValue<Vector2i, String> &E : pending_cells) {
		if (!pinned_cells.has(E.key) && !_within_any_radius(E.key, centers, load_radius)) {
			cancel.push_back(E.key);
		}
	}
	for (const Vector2i &cell : cancel) {
		pending_cells.erase(cell);
	}

	int new_requests = max_new_requests_per_frame;
	int instances = max_instances_per_frame;
	// Priority-pinned gameplay cells share this node's global resource budgets.
	for (const Vector2i &cell : pinned_cells) {
		_stream_candidate_cell(cell, new_requests, instances);
	}
	// Visit the closest ring of every source before requesting farther cells.
	// Primary still wins ties at a given radius; budgets remain global.
	for (int radius = 0; radius <= load_radius; radius++) {
		for (const Vector2i &center : centers) {
			for (int dz = -radius; dz <= radius; dz++) {
				for (int dx = -radius; dx <= radius; dx++) {
					if (MAX(ABS(dx), ABS(dz)) != radius) {
						continue;
					}
					const Vector2i cell = center + Vector2i(dx, dz);
					_stream_candidate_cell(cell, new_requests, instances);
				}
			}
		}
	}
	_purge_unused_ready_scenes();
	if (centers.is_empty() && pinned_cells.is_empty() && active_cells.is_empty() && pending_cells.is_empty()) {
		unload_after_last_pin_removed = false;
	}
}

Node3D *WorldPartition3D::get_cell_instance(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	if (id == nullptr) {
		return nullptr;
	}
	// Never keep or expose a stale instance pointer after a scene was removed.
	return Object::cast_to<Node3D>(ObjectDB::get_instance(*id));
}

bool WorldPartition3D::is_cell_loaded(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	return id != nullptr && ObjectDB::get_instance(*id) != nullptr;
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

void WorldPartition3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &WorldPartition3D::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &WorldPartition3D::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_load_radius", "radius"), &WorldPartition3D::set_load_radius);
	ClassDB::bind_method(D_METHOD("get_load_radius"), &WorldPartition3D::get_load_radius);
	ClassDB::bind_method(D_METHOD("set_unload_radius", "radius"), &WorldPartition3D::set_unload_radius);
	ClassDB::bind_method(D_METHOD("get_unload_radius"), &WorldPartition3D::get_unload_radius);
	ClassDB::bind_method(D_METHOD("set_max_new_requests_per_frame", "count"), &WorldPartition3D::set_max_new_requests_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_new_requests_per_frame"), &WorldPartition3D::get_max_new_requests_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_instances_per_frame", "count"), &WorldPartition3D::set_max_instances_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_instances_per_frame"), &WorldPartition3D::get_max_instances_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_unloads_per_frame", "count"), &WorldPartition3D::set_max_unloads_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_unloads_per_frame"), &WorldPartition3D::get_max_unloads_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_concurrent_requests", "count"), &WorldPartition3D::set_max_concurrent_requests);
	ClassDB::bind_method(D_METHOD("get_max_concurrent_requests"), &WorldPartition3D::get_max_concurrent_requests);
	ClassDB::bind_method(D_METHOD("set_streaming_enabled", "enabled"), &WorldPartition3D::set_streaming_enabled);
	ClassDB::bind_method(D_METHOD("is_streaming_enabled"), &WorldPartition3D::is_streaming_enabled);
	ClassDB::bind_method(D_METHOD("set_observer_path", "path"), &WorldPartition3D::set_observer_path);
	ClassDB::bind_method(D_METHOD("get_observer_path"), &WorldPartition3D::get_observer_path);
	ClassDB::bind_method(D_METHOD("set_additional_observer_paths", "paths"), &WorldPartition3D::set_additional_observer_paths);
	ClassDB::bind_method(D_METHOD("get_additional_observer_paths"), &WorldPartition3D::get_additional_observer_paths);
	ClassDB::bind_method(D_METHOD("set_pinned_cells", "cells"), &WorldPartition3D::set_pinned_cells);
	ClassDB::bind_method(D_METHOD("pin_cell", "cell"), &WorldPartition3D::pin_cell);
	ClassDB::bind_method(D_METHOD("unpin_cell", "cell"), &WorldPartition3D::unpin_cell);
	ClassDB::bind_method(D_METHOD("clear_pinned_cells"), &WorldPartition3D::clear_pinned_cells);
	ClassDB::bind_method(D_METHOD("is_cell_pinned", "cell"), &WorldPartition3D::is_cell_pinned);
	ClassDB::bind_method(D_METHOD("get_pinned_cells"), &WorldPartition3D::get_pinned_cells);
	ClassDB::bind_method(D_METHOD("get_pinned_cell_count"), &WorldPartition3D::get_pinned_cell_count);
	ClassDB::bind_method(D_METHOD("set_cell_state", "cell", "state"), &WorldPartition3D::set_cell_state);
	ClassDB::bind_method(D_METHOD("get_cell_state", "cell"), &WorldPartition3D::get_cell_state);
	ClassDB::bind_method(D_METHOD("has_cell_state", "cell"), &WorldPartition3D::has_cell_state);
	ClassDB::bind_method(D_METHOD("erase_cell_state", "cell"), &WorldPartition3D::erase_cell_state);
	ClassDB::bind_method(D_METHOD("clear_cell_states"), &WorldPartition3D::clear_cell_states);
	ClassDB::bind_method(D_METHOD("snapshot_cell_states"), &WorldPartition3D::snapshot_cell_states);
	ClassDB::bind_method(D_METHOD("load_cell_states", "states"), &WorldPartition3D::load_cell_states);
	ClassDB::bind_method(D_METHOD("get_cell_state_count"), &WorldPartition3D::get_cell_state_count);
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
	ClassDB::bind_method(D_METHOD("get_cell_instance", "cell"), &WorldPartition3D::get_cell_instance);
	ClassDB::bind_method(D_METHOD("get_loaded_cell_count"), &WorldPartition3D::get_loaded_cell_count);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldPartition3D::get_loaded_cells);

	ADD_GROUP("World Grid", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,4096,1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cell_scenes"), "set_cell_scenes", "get_cell_scenes");
	ADD_GROUP("Streaming", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "streaming_enabled"), "set_streaming_enabled", "is_streaming_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "observer_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_observer_path", "get_observer_path");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "additional_observer_paths"), "set_additional_observer_paths", "get_additional_observer_paths");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "pinned_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_pinned_cells", "get_pinned_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "load_radius", PROPERTY_HINT_RANGE, "0,32,1"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "unload_radius", PROPERTY_HINT_RANGE, "0,64,1"), "set_unload_radius", "get_unload_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_new_requests_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_new_requests_per_frame", "get_max_new_requests_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instances_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_instances_per_frame", "get_max_instances_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_unloads_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_unloads_per_frame", "get_max_unloads_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_requests", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_concurrent_requests", "get_max_concurrent_requests");

	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
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
