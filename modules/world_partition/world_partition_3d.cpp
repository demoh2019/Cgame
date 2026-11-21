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
#include "scene/3d/physics/collision_object_3d.h"
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/3d/navigation/navigation_region_3d.h"

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

bool WorldPartition3D::_has_residency_claim(const Vector2i &p_cell) const {
	return pinned_cells.has(p_cell) || cell_lease_counts.has(p_cell);
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

bool WorldPartition3D::_is_cell_layer_enabled(const Vector2i &p_cell) const {
	const String layer = get_cell_layer(p_cell);
	return layer.is_empty() || is_layer_enabled(layer);
}

void WorldPartition3D::_notify_cell_activating(const Vector2i &p_cell, Node *p_instance) {
	// Runs after scene instantiation, _ready() and gameplay state restoration.
	// NavigationServer3D geometry still needs a physics tick before path queries.
	if (p_instance != nullptr && p_instance->has_method(SNAME("streaming_activated"))) {
		p_instance->call(SNAME("streaming_activated"), p_cell);
	}
	emit_signal(SNAME("cell_activated"), p_cell);
}

void WorldPartition3D::_notify_cell_deactivating(const Vector2i &p_cell, Node *p_instance) {
	// queue_free() is deferred, so disable physics/navigation participation
	// before the scene can remain alive until the end of the frame.
	if (p_instance != nullptr && p_instance->has_method(SNAME("streaming_deactivating"))) {
		p_instance->call(SNAME("streaming_deactivating"), p_cell);
	}
	emit_signal(SNAME("cell_deactivating"), p_cell);
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
	const Dictionary previous = get_cell_state(p_cell);
	if (state.is_empty()) {
		saved_cell_states.erase(p_cell);
	} else {
		saved_cell_states.insert(p_cell, state.duplicate(true));
	}
	const Dictionary updated = get_cell_state(p_cell);
	if (previous != updated) {
		emit_signal(SNAME("cell_state_changed"), p_cell, updated);
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
		// Capture motion BEFORE callbacks can freeze a body for deferred deletion.
		_capture_cell_physics_state(p_cell, node);
		_notify_cell_deactivating(p_cell, node);
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
	_restore_cell_physics_state(p_cell, instance);
	_notify_cell_activating(p_cell, instance);
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

int WorldPartition3D::acquire_cell_lease(const Vector2i &p_cell) {
	ERR_FAIL_COND_V_MSG(cell_leases.size() >= 256, 0, "WorldPartition3D allows at most 256 active cell leases.");
	for (int attempt = 0; attempt < 257; attempt++) {
		const int token = next_cell_lease_token;
		// Wrap without signed-integer overflow. Active tokens are never recycled.
		next_cell_lease_token = token == INT32_MAX ? 1 : token + 1;
		if (cell_leases.has(token)) {
			continue;
		}
		cell_leases.insert(token, p_cell);
		const int *count = cell_lease_counts.getptr(p_cell);
		cell_lease_counts.insert(p_cell, count != nullptr ? *count + 1 : 1);
		unload_after_last_pin_removed = false;
		return token;
	}
	ERR_FAIL_V_MSG(0, "WorldPartition3D could not allocate a unique cell lease token.");
}

bool WorldPartition3D::release_cell_lease(int p_lease_token) {
	const Vector2i *cell = cell_leases.getptr(p_lease_token);
	if (cell == nullptr) {
		return false;
	}
	const Vector2i cell_coord = *cell;
	cell_leases.erase(p_lease_token);
	const int *count = cell_lease_counts.getptr(cell_coord);
	if (count != nullptr) {
		if (*count <= 1) {
			cell_lease_counts.erase(cell_coord);
		} else {
			cell_lease_counts.insert(cell_coord, *count - 1);
		}
	}
	// Recheck eligibility even if no observer remains.
	unload_after_last_pin_removed = true;
	return true;
}

void WorldPartition3D::clear_cell_leases() {
	if (!cell_leases.is_empty()) {
		cell_leases.clear();
		cell_lease_counts.clear();
		unload_after_last_pin_removed = true;
	}
}

int WorldPartition3D::get_cell_lease_count(const Vector2i &p_cell) const {
	const int *count = cell_lease_counts.getptr(p_cell);
	return count != nullptr ? *count : 0;
}

int WorldPartition3D::get_cell_lease_count_total() const {
	return cell_leases.size();
}

int WorldPartition3D::get_leased_cell_count() const {
	return cell_lease_counts.size();
}

Array WorldPartition3D::get_cell_route(const Vector2i &p_from, const Vector2i &p_to) const {
	// A four-connected straight grid corridor. It prefetches cells, not
	// obstacle-aware path planning; NavigationServer3D computes actual paths.
	// Limit allocations and work from untrusted or very distant coordinates.
	const int64_t dx = int64_t(p_to.x) - int64_t(p_from.x);
	const int64_t dz = int64_t(p_to.y) - int64_t(p_from.y);
	const int64_t ax = dx < 0 ? -dx : dx;
	const int64_t az = dz < 0 ? -dz : dz;
	ERR_FAIL_COND_V_MSG(ax + az + 1 > 64, Array(), "WorldPartition3D route is limited to 64 cells; use shorter waypoints.");

	Array cells;
	Vector2i cell = p_from;
	cells.push_back(cell);
	const int step_x = dx > 0 ? 1 : -1;
	const int step_z = dz > 0 ? 1 : -1;
	int64_t ix = 0;
	int64_t iz = 0;
	while (ix < ax || iz < az) {
		// Compare normalized progress without division; never skip an edge
		// neighbor. The generated route is deterministic on all platforms.
		if (ix >= ax || (iz < az && (2 * iz + 1) * ax < (2 * ix + 1) * az)) {
			cell.y += step_z;
			iz++;
		} else {
			cell.x += step_x;
			ix++;
		}
		cells.push_back(cell);
	}
	return cells;
}

Array WorldPartition3D::acquire_cell_route(const Vector2i &p_from, const Vector2i &p_to) {
	const Array cells = get_cell_route(p_from, p_to);
	if (cells.is_empty()) {
		return Array();
	}
	ERR_FAIL_COND_V_MSG(int64_t(cell_leases.size()) + cells.size() > 256, Array(), "WorldPartition3D route exceeds available lease token capacity.");
	for (int i = 0; i < cells.size(); i++) {
		const Vector2i cell = cells[i];
		if (!_is_cell_layer_enabled(cell)) {
			// A disabled gameplay layer is a hard gate; do not claim an
			// untraversable route or partially retain its other cells.
			return Array();
		}
	}
	Array tokens;
	for (int i = 0; i < cells.size(); i++) {
		const int token = acquire_cell_lease(cells[i]);
		if (token == 0) {
			release_cell_route(tokens);
			return Array();
		}
		tokens.push_back(token);
	}
	return tokens;
}

int WorldPartition3D::release_cell_route(const Array &p_tokens) {
	int released = 0;
	for (int i = 0; i < p_tokens.size(); i++) {
		if (p_tokens[i].get_type() == Variant::INT && release_cell_lease(int(p_tokens[i]))) {
			released++;
		}
	}
	return released;
}

void WorldPartition3D::set_cell_layers(const Dictionary &p_layers) {
	Dictionary clean;
	const Array keys = p_layers.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		const Variant value = p_layers[key];
		if (key.get_type() == Variant::VECTOR2I && value.get_type() == Variant::STRING && !String(value).is_empty()) {
			clean[key] = value;
		}
	}
	cell_layers = clean;
	layer_update_needed = true;
}

Dictionary WorldPartition3D::get_cell_layers() const {
	return cell_layers.duplicate();
}

void WorldPartition3D::set_cell_layer(const Vector2i &p_cell, const String &p_layer) {
	if (p_layer.is_empty()) {
		clear_cell_layer(p_cell);
		return;
	}
	if (get_cell_layer(p_cell) == p_layer) {
		return;
	}
	cell_layers[p_cell] = p_layer;
	layer_update_needed = true;
}

String WorldPartition3D::get_cell_layer(const Vector2i &p_cell) const {
	if (!cell_layers.has(p_cell)) {
		return String();
	}
	return cell_layers[p_cell];
}

void WorldPartition3D::clear_cell_layer(const Vector2i &p_cell) {
	if (cell_layers.has(p_cell)) {
		cell_layers.erase(p_cell);
		layer_update_needed = true;
	}
}

void WorldPartition3D::set_layer_states(const Dictionary &p_states) {
	const Dictionary before = layer_states.duplicate();
	Dictionary clean;
	const Array keys = p_states.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		const Variant value = p_states[key];
		if (key.get_type() == Variant::STRING && !String(key).is_empty() && value.get_type() == Variant::BOOL) {
			clean[key] = value;
		}
	}
	layer_states = clean;
	layer_update_needed = true;
	// Bulk save-game imports emit one event per changed effective layer,
	// including enabled-by-default layers whose explicit false entry vanished.
	const Array previous_names = before.keys();
	for (int i = 0; i < previous_names.size(); i++) {
		const String name = previous_names[i];
		const bool was_enabled = before[name];
		const bool now_enabled = is_layer_enabled(name);
		if (was_enabled != now_enabled) {
			emit_signal(SNAME("layer_state_changed"), name, now_enabled);
		}
	}
	const Array names = clean.keys();
	for (int i = 0; i < names.size(); i++) {
		const String name = names[i];
		if (!before.has(name) && !bool(clean[name])) {
			emit_signal(SNAME("layer_state_changed"), name, false);
		}
	}
}

Dictionary WorldPartition3D::get_layer_states() const {
	return layer_states.duplicate();
}

void WorldPartition3D::set_layer_enabled(const String &p_layer, bool p_enabled) {
	ERR_FAIL_COND_MSG(p_layer.is_empty(), "WorldPartition3D layer name must be nonempty.");
	if (is_layer_enabled(p_layer) == p_enabled) {
		return;
	}
	layer_states[p_layer] = p_enabled;
	layer_update_needed = true;
	emit_signal(SNAME("layer_state_changed"), p_layer, p_enabled);
}

bool WorldPartition3D::is_layer_enabled(const String &p_layer) const {
	if (p_layer.is_empty() || !layer_states.has(p_layer)) {
		return true;
	}
	return layer_states[p_layer];
}

bool WorldPartition3D::is_cell_layer_enabled(const Vector2i &p_cell) const {
	return _is_cell_layer_enabled(p_cell);
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
	if (!_is_cell_layer_enabled(p_cell) || active_cells.has(p_cell) || failed_cells.has(p_cell)) {
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

bool WorldPartition3D::_valid_body_path(const String &p_path) {
	if (p_path.is_empty() || p_path.contains("..")) {
		return false;
	}
	const NodePath path = NodePath(p_path);
	return !path.is_absolute() && path.get_subname_count() == 0;
}

bool WorldPartition3D::_valid_body_state(const Dictionary &p_state) {
	if (!p_state.has("transform") || !p_state.has("linear_velocity") || !p_state.has("angular_velocity") || !p_state.has("sleeping") || !p_state.has("freeze")) {
		return false;
	}
	const Variant transform = p_state["transform"];
	const Variant linear = p_state["linear_velocity"];
	const Variant angular = p_state["angular_velocity"];
	const Variant sleeping = p_state["sleeping"];
	const Variant frozen = p_state["freeze"];
	if (transform.get_type() != Variant::TRANSFORM3D || linear.get_type() != Variant::VECTOR3 || angular.get_type() != Variant::VECTOR3 || sleeping.get_type() != Variant::BOOL || frozen.get_type() != Variant::BOOL) {
		return false;
	}
	const Transform3D body_transform = transform;
	const Vector3 linear_velocity = linear;
	const Vector3 angular_velocity = angular;
	return body_transform.is_finite() && linear_velocity.is_finite() && angular_velocity.is_finite();
}

void WorldPartition3D::_capture_cell_physics_state(const Vector2i &p_cell, Node *p_instance) {
	if (!persist_rigid_bodies || p_instance == nullptr) {
		return;
	}
	Dictionary states;
	Vector<Node *> stack;
	stack.push_back(p_instance);
	while (!stack.is_empty()) {
		Node *node = stack[stack.size() - 1];
		stack.remove_at(stack.size() - 1);
		RigidBody3D *body = Object::cast_to<RigidBody3D>(node);
		if (body != nullptr && bool(body->get_meta(SNAME("streaming_persistent"), false))) {
			// A stable scene-relative NodePath survives PackedScene reinstantiation.
			const String path = String(p_instance->get_path_to(body));
			Dictionary record;
			record["transform"] = body->get_transform();
			record["linear_velocity"] = body->get_linear_velocity();
			record["angular_velocity"] = body->get_angular_velocity();
			record["sleeping"] = body->is_sleeping();
			record["freeze"] = body->is_freeze_enabled();
			if (_valid_body_state(record)) {
				states[path] = record;
			}
		}
		if (states.size() >= 128) {
			break;
		}
		for (int i = 0; i < node->get_child_count(); i++) {
			stack.push_back(node->get_child(i));
		}
	}
	if (states.is_empty()) {
		saved_cell_physics_states.erase(p_cell);
	} else {
		saved_cell_physics_states.insert(p_cell, states.duplicate(true));
	}
}

void WorldPartition3D::_restore_cell_physics_state(const Vector2i &p_cell, Node *p_instance) {
	if (!persist_rigid_bodies || p_instance == nullptr) {
		return;
	}
	const Dictionary *states = saved_cell_physics_states.getptr(p_cell);
	if (states == nullptr) {
		return;
	}
	const Array paths = states->keys();
	for (int i = 0; i < paths.size(); i++) {
		const Variant key = paths[i];
		if (key.get_type() != Variant::STRING || String(key).is_empty()) {
			continue;
		}
		const String path_text = key;
		// A checkpoint must not traverse outside the cell root or access
		// node properties through subnames.
		if (!_valid_body_path(path_text)) {
			continue;
		}
		const NodePath path = NodePath(path_text);
		RigidBody3D *body = Object::cast_to<RigidBody3D>(p_instance->get_node_or_null(path));
		if (body == nullptr || (body != p_instance && !p_instance->is_ancestor_of(body)) || !bool(body->get_meta(SNAME("streaming_persistent"), false))) {
			continue;
		}
		const Dictionary record = (*states)[key];
		if (!_valid_body_state(record)) {
			continue;
		}
		body->set_freeze_enabled(bool(record["freeze"]));
		body->set_transform(record["transform"]);
		body->set_linear_velocity(record["linear_velocity"]);
		body->set_angular_velocity(record["angular_velocity"]);
		body->set_sleeping(bool(record["sleeping"]));
	}
}

void WorldPartition3D::set_persist_rigid_bodies(bool p_enabled) {
	persist_rigid_bodies = p_enabled;
}

bool WorldPartition3D::is_persisting_rigid_bodies() const {
	return persist_rigid_bodies;
}

Dictionary WorldPartition3D::get_cell_physics_state(const Vector2i &p_cell) const {
	const Dictionary *states = saved_cell_physics_states.getptr(p_cell);
	return states != nullptr ? states->duplicate(true) : Dictionary();
}

Dictionary WorldPartition3D::snapshot_cell_physics_states() {
	if (persist_rigid_bodies) {
		for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
			Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
			_capture_cell_physics_state(E.key, instance);
		}
	}
	Dictionary snapshot;
	for (const KeyValue<Vector2i, Dictionary> &E : saved_cell_physics_states) {
		snapshot[E.key] = E.value.duplicate(true);
	}
	return snapshot;
}

void WorldPartition3D::load_cell_physics_states(const Dictionary &p_states) {
	HashMap<Vector2i, Dictionary> accepted;
	const Array cells = p_states.keys();
	for (int i = 0; i < cells.size(); i++) {
		const Variant cell = cells[i];
		const Variant raw = p_states[cell];
		if (cell.get_type() != Variant::VECTOR2I || raw.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary candidates = raw;
		const Array names = candidates.keys();
		Dictionary valid;
		for (int j = 0; j < names.size() && valid.size() < 128; j++) {
			const Variant name = names[j];
			if (name.get_type() != Variant::STRING || !_valid_body_path(String(name)) || candidates[name].get_type() != Variant::DICTIONARY) {
				continue;
			}
			const Dictionary record = candidates[name];
			if (_valid_body_state(record)) {
				valid[name] = record.duplicate(true);
			}
		}
		if (!valid.is_empty()) {
			accepted.insert(cell, valid);
		}
	}
	saved_cell_physics_states = accepted;
	if (persist_rigid_bodies) {
		for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
			Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
			_restore_cell_physics_state(E.key, instance);
		}
	}
}

void WorldPartition3D::clear_cell_physics_states() {
	saved_cell_physics_states.clear();
}

int WorldPartition3D::get_cell_physics_state_count() const {
	return saved_cell_physics_states.size();
}

void WorldPartition3D::set_cell_state(const Vector2i &p_cell, const Dictionary &p_state) {
	const Dictionary previous = get_cell_state(p_cell);
	if (p_state.is_empty()) {
		saved_cell_states.erase(p_cell);
	} else {
		saved_cell_states.insert(p_cell, p_state.duplicate(true));
	}
	Node3D *instance = get_cell_instance(p_cell);
	if (p_state.is_empty() && instance != nullptr && instance->has_method(SNAME("restore_streaming_state"))) {
		// Loading a save without a cell record resets its active gameplay scene.
		instance->call(SNAME("restore_streaming_state"), Dictionary());
	} else {
		_restore_cell_state(p_cell, instance);
	}
	const Dictionary updated = get_cell_state(p_cell);
	if (previous != updated) {
		emit_signal(SNAME("cell_state_changed"), p_cell, updated);
	}
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
		if (instance != nullptr && instance->has_method(SNAME("restore_streaming_state"))) {
			// A missing save record means default state, not the previous session.
			const Dictionary *state = saved_cell_states.getptr(E.key);
			instance->call(SNAME("restore_streaming_state"), state != nullptr ? state->duplicate(true) : Dictionary());
		}
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
	if (centers.is_empty() && pinned_cells.is_empty() && cell_leases.is_empty() && !unload_after_last_pin_removed && !layer_update_needed) {
		// Preserve cells if all observer nodes disappear temporarily without
		// an explicit pin release (e.g., a brief scene-tree reparenting).
		_purge_unused_ready_scenes();
		if (observer_path.is_empty() && additional_observer_paths.is_empty()) {
			_refresh_processing();
		}
		return;
	}

	// If no observer remains, preserve unrelated cells unless the last pin was
	// explicitly released. A layer deactivation still removes its own cells.
	const bool distance_eviction = !centers.is_empty() || !pinned_cells.is_empty() || !cell_leases.is_empty() || unload_after_last_pin_removed;
	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (!_is_cell_layer_enabled(E.key) || (distance_eviction && !_has_residency_claim(E.key) && !_within_any_radius(E.key, centers, unload_radius)) || ObjectDB::get_instance(E.value) == nullptr) {
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
		if (!_is_cell_layer_enabled(E.key) || (distance_eviction && !_has_residency_claim(E.key) && !_within_any_radius(E.key, centers, load_radius))) {
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
	// Independent lease owners share the same budgets. Iterate distinct cells
	// once, regardless of how many systems retain a single location.
	for (const KeyValue<Vector2i, int> &E : cell_lease_counts) {
		if (!pinned_cells.has(E.key)) {
			_stream_candidate_cell(E.key, new_requests, instances);
		}
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
	bool disabled_active = false;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (!_is_cell_layer_enabled(E.key)) {
			disabled_active = true;
			break;
		}
	}
	if (!disabled_active) {
		layer_update_needed = false;
	}
	if (centers.is_empty() && pinned_cells.is_empty() && cell_leases.is_empty() && active_cells.is_empty() && pending_cells.is_empty()) {
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

Dictionary WorldPartition3D::get_cell_simulation_stats(const Vector2i &p_cell) const {
	Dictionary counts;
	counts["collision_objects"] = 0;
	counts["collision_shapes"] = 0;
	counts["navigation_regions"] = 0;

	Node3D *root = get_cell_instance(p_cell);
	if (root == nullptr) {
		return counts;
	}
	// Count only on explicit request. Never walk the entire scene tree in the
	// per-frame streamer: physics/nav instrumentation is a diagnostic tool.
	int collision_objects = 0;
	int collision_shapes = 0;
	int navigation_regions = 0;
	Vector<Node *> traversal;
	traversal.push_back(root);
	while (!traversal.is_empty()) {
		Node *node = traversal[traversal.size() - 1];
		traversal.remove_at(traversal.size() - 1);
		if (Object::cast_to<CollisionObject3D>(node) != nullptr) {
			collision_objects++;
		}
		if (Object::cast_to<CollisionShape3D>(node) != nullptr) {
			collision_shapes++;
		}
		if (Object::cast_to<NavigationRegion3D>(node) != nullptr) {
			navigation_regions++;
		}
		for (int i = 0; i < node->get_child_count(); i++) {
			traversal.push_back(node->get_child(i));
		}
	}
	counts["collision_objects"] = collision_objects;
	counts["collision_shapes"] = collision_shapes;
	counts["navigation_regions"] = navigation_regions;
	return counts;
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
	ClassDB::bind_method(D_METHOD("acquire_cell_lease", "cell"), &WorldPartition3D::acquire_cell_lease);
	ClassDB::bind_method(D_METHOD("release_cell_lease", "lease_token"), &WorldPartition3D::release_cell_lease);
	ClassDB::bind_method(D_METHOD("clear_cell_leases"), &WorldPartition3D::clear_cell_leases);
	ClassDB::bind_method(D_METHOD("get_cell_lease_count", "cell"), &WorldPartition3D::get_cell_lease_count);
	ClassDB::bind_method(D_METHOD("get_cell_lease_count_total"), &WorldPartition3D::get_cell_lease_count_total);
	ClassDB::bind_method(D_METHOD("get_leased_cell_count"), &WorldPartition3D::get_leased_cell_count);
	ClassDB::bind_method(D_METHOD("get_cell_route", "from_cell", "to_cell"), &WorldPartition3D::get_cell_route);
	ClassDB::bind_method(D_METHOD("acquire_cell_route", "from_cell", "to_cell"), &WorldPartition3D::acquire_cell_route);
	ClassDB::bind_method(D_METHOD("release_cell_route", "tokens"), &WorldPartition3D::release_cell_route);
	ClassDB::bind_method(D_METHOD("set_cell_layers", "layers"), &WorldPartition3D::set_cell_layers);
	ClassDB::bind_method(D_METHOD("get_cell_layers"), &WorldPartition3D::get_cell_layers);
	ClassDB::bind_method(D_METHOD("set_cell_layer", "cell", "layer"), &WorldPartition3D::set_cell_layer);
	ClassDB::bind_method(D_METHOD("get_cell_layer", "cell"), &WorldPartition3D::get_cell_layer);
	ClassDB::bind_method(D_METHOD("clear_cell_layer", "cell"), &WorldPartition3D::clear_cell_layer);
	ClassDB::bind_method(D_METHOD("set_layer_states", "states"), &WorldPartition3D::set_layer_states);
	ClassDB::bind_method(D_METHOD("get_layer_states"), &WorldPartition3D::get_layer_states);
	ClassDB::bind_method(D_METHOD("set_layer_enabled", "layer", "enabled"), &WorldPartition3D::set_layer_enabled);
	ClassDB::bind_method(D_METHOD("is_layer_enabled", "layer"), &WorldPartition3D::is_layer_enabled);
	ClassDB::bind_method(D_METHOD("is_cell_layer_enabled", "cell"), &WorldPartition3D::is_cell_layer_enabled);
	ClassDB::bind_method(D_METHOD("set_cell_state", "cell", "state"), &WorldPartition3D::set_cell_state);
	ClassDB::bind_method(D_METHOD("get_cell_state", "cell"), &WorldPartition3D::get_cell_state);
	ClassDB::bind_method(D_METHOD("has_cell_state", "cell"), &WorldPartition3D::has_cell_state);
	ClassDB::bind_method(D_METHOD("erase_cell_state", "cell"), &WorldPartition3D::erase_cell_state);
	ClassDB::bind_method(D_METHOD("clear_cell_states"), &WorldPartition3D::clear_cell_states);
	ClassDB::bind_method(D_METHOD("snapshot_cell_states"), &WorldPartition3D::snapshot_cell_states);
	ClassDB::bind_method(D_METHOD("load_cell_states", "states"), &WorldPartition3D::load_cell_states);
	ClassDB::bind_method(D_METHOD("get_cell_state_count"), &WorldPartition3D::get_cell_state_count);
	ClassDB::bind_method(D_METHOD("set_persist_rigid_bodies", "enabled"), &WorldPartition3D::set_persist_rigid_bodies);
	ClassDB::bind_method(D_METHOD("is_persisting_rigid_bodies"), &WorldPartition3D::is_persisting_rigid_bodies);
	ClassDB::bind_method(D_METHOD("get_cell_physics_state", "cell"), &WorldPartition3D::get_cell_physics_state);
	ClassDB::bind_method(D_METHOD("snapshot_cell_physics_states"), &WorldPartition3D::snapshot_cell_physics_states);
	ClassDB::bind_method(D_METHOD("load_cell_physics_states", "states"), &WorldPartition3D::load_cell_physics_states);
	ClassDB::bind_method(D_METHOD("clear_cell_physics_states"), &WorldPartition3D::clear_cell_physics_states);
	ClassDB::bind_method(D_METHOD("get_cell_physics_state_count"), &WorldPartition3D::get_cell_physics_state_count);
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
	ClassDB::bind_method(D_METHOD("get_cell_simulation_stats", "cell"), &WorldPartition3D::get_cell_simulation_stats);

	ADD_GROUP("World Grid", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,4096,1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cell_scenes"), "set_cell_scenes", "get_cell_scenes");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cell_layers"), "set_cell_layers", "get_cell_layers");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "layer_states"), "set_layer_states", "get_layer_states");
	ADD_GROUP("Streaming", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "streaming_enabled"), "set_streaming_enabled", "is_streaming_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "persist_rigid_bodies"), "set_persist_rigid_bodies", "is_persisting_rigid_bodies");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "observer_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_observer_path", "get_observer_path");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "additional_observer_paths"), "set_additional_observer_paths", "get_additional_observer_paths");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "pinned_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_pinned_cells", "get_pinned_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "load_radius", PROPERTY_HINT_RANGE, "0,32,1"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "unload_radius", PROPERTY_HINT_RANGE, "0,64,1"), "set_unload_radius", "get_unload_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_new_requests_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_new_requests_per_frame", "get_max_new_requests_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instances_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_instances_per_frame", "get_max_instances_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_unloads_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_unloads_per_frame", "get_max_unloads_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_requests", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_concurrent_requests", "get_max_concurrent_requests");

	ADD_SIGNAL(MethodInfo("cell_activated", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_deactivating", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_state_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::DICTIONARY, "state")));
	ADD_SIGNAL(MethodInfo("layer_state_changed", PropertyInfo(Variant::STRING, "layer"), PropertyInfo(Variant::BOOL, "enabled")));
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
