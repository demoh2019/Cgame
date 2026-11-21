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
#include "scene/3d/navigation/navigation_link_3d.h"
#include "scene/3d/navigation/navigation_region_3d.h"
#include "scene/3d/physics/collision_object_3d.h"
#include "scene/3d/physics/collision_shape_3d.h"
#include "scene/3d/physics/rigid_body_3d.h"
#include "scene/main/node.h"

#include <cstdint>
#include <limits>

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

bool WorldPartition3D::_has_residency_claim(const Vector2i &p_cell) const {
	return pinned_cells.has(p_cell) || cell_lease_counts.has(p_cell);
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
	// Scene scripts may enable regions in streaming_activated(). Re-apply an
	// explicit gameplay gate after that callback, before subscribers run.
	// Enabled cells are left alone so the distance-based navigation tier owns them.
	if (navigation_cell_states.has(p_cell)) {
		_apply_cell_navigation_state(p_cell, p_instance);
	}
	_apply_cell_navigation_links(p_cell, p_instance);
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
		_capture_cell_object_states(p_cell, node);
		_notify_cell_deactivating(p_cell, node);
		_capture_cell_state(p_cell, node);
		node->queue_free();
	}
	active_cells.erase(p_cell);
	_invalidate_cell_path_cache(false);
	cell_creation_physics_frames.erase(p_cell);
	active_detail_levels.erase(p_cell);
	active_simulation_cells.erase(p_cell);
	active_physics_cells.erase(p_cell);
	physics_enabled_frames.erase(p_cell);
	active_navigation_cells.erase(p_cell);
	navigation_enabled_frames.erase(p_cell);
	navigation_dirty_cells.erase(p_cell);
	navigation_mesh_revisions.erase(p_cell);
	navigation_mesh_generation++;
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
	// O(pending + ready) instead of rescanning every pending cell per scene.
	HashSet<String> pending_paths;
	for (const KeyValue<Vector2i, String> &E : pending_cells) {
		pending_paths.insert(E.value);
	}
	Vector<String> unused;
	for (const KeyValue<String, Ref<PackedScene>> &E : ready_scenes) {
		if (!pending_paths.has(E.key)) {
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
	// Set the streaming LOD before _ready(): scripts can build far cells
	// cheaply instead of generating full foliage then immediately deleting it.
	if (instance->has_method(SNAME("set_streaming_lod"))) {
		const int level = observer_cell_valid ? _cell_detail_level(p_cell, observer_cell) : 0;
		instance->call(SNAME("set_streaming_lod"), level);
		active_detail_levels.insert(p_cell, level);
	}
	// Let script roots initialize activation state before _ready(), without
	// imposing any scene-tree-wide process_mode changes on games that opt out.
	const bool simulation_active = observer_cell_valid ? _cell_simulation_active(p_cell, observer_cell) : true;
	active_simulation_cells.insert(p_cell, simulation_active);
	if (instance->has_method(SNAME("set_streaming_simulation_active"))) {
		instance->call(SNAME("set_streaming_simulation_active"), simulation_active);
	}
	// Initial physics state is known before _ready(): procedurally authored
	// colliders can start filtered out without an activation flash.
	const bool physics_active = observer_cell_valid ? _cell_physics_active(p_cell, observer_cell) : true;
	active_physics_cells.insert(p_cell, physics_active);
	if (physics_active) {
		physics_enabled_frames.insert(p_cell, Engine::get_singleton()->get_physics_frames());
	}
	if (instance->has_method(SNAME("set_streaming_physics_active"))) {
		instance->call(SNAME("set_streaming_physics_active"), physics_active);
	}
	// Let a navmesh-owning script build a region only if the native navigation
	// tier is active, with no momentary server registration in a dormant cell.
	const bool navigation_active = observer_cell_valid ? _cell_navigation_active(p_cell, observer_cell) : true;
	active_navigation_cells.insert(p_cell, navigation_active);
	navigation_mesh_revisions.insert(p_cell, 0);
	if (navigation_active) {
		navigation_enabled_frames.insert(p_cell, Engine::get_singleton()->get_physics_frames());
	}
	if (instance->has_method(SNAME("set_streaming_navigation_active"))) {
		instance->call(SNAME("set_streaming_navigation_active"), navigation_active);
	}
	add_child(instance);
	active_cells.insert(p_cell, instance->get_instance_id());
	_invalidate_cell_path_cache(false);
	navigation_mesh_generation++;
	cell_creation_physics_frames.insert(p_cell, Engine::get_singleton()->get_physics_frames());
	// Restoring after _ready() lets scene scripts create their visuals first.
	_restore_cell_state(p_cell, instance);
	_restore_cell_physics_state(p_cell, instance);
	_restore_cell_object_states(p_cell, instance, false);
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
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		// A future re-entry should report the first resolved observer cell.
		observer_cell_valid = false;
		predicted_cell_valid = false;
		navigation_schedule_valid = false;
		last_navigation_rebuild_frame = UINT64_MAX;
		navigation_selected.clear();
		navigation_consumed.clear();
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
		predicted_cell_valid = false;
		_purge_unused_ready_scenes();
	}
	_refresh_processing();
}

bool WorldPartition3D::is_streaming_enabled() const {
	return streaming_enabled;
}

void WorldPartition3D::set_detail_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < -1 || p_radius > 32, "WorldPartition3D detail_radius must be -1 (disabled) or 0 to 32.");
	detail_radius = p_radius;
}

int WorldPartition3D::get_detail_radius() const {
	return detail_radius;
}

void WorldPartition3D::set_detail_hysteresis_cells(int p_hysteresis) {
	ERR_FAIL_COND_MSG(p_hysteresis < 0 || p_hysteresis > 8, "WorldPartition3D detail_hysteresis_cells must be between 0 and 8.");
	detail_hysteresis_cells = p_hysteresis;
}

int WorldPartition3D::get_detail_hysteresis_cells() const {
	return detail_hysteresis_cells;
}

void WorldPartition3D::set_max_detail_transitions_per_frame(int p_budget) {
	ERR_FAIL_COND_MSG(p_budget < 1 || p_budget > 128, "WorldPartition3D detail transition budget must be 1 to 128.");
	max_detail_transitions_per_frame = p_budget;
}

int WorldPartition3D::get_max_detail_transitions_per_frame() const {
	return max_detail_transitions_per_frame;
}

int WorldPartition3D::get_cell_detail_level(const Vector2i &p_cell) const {
	const int *level = active_detail_levels.getptr(p_cell);
	return level != nullptr && is_cell_loaded(p_cell) ? *level : -1;
}

int WorldPartition3D::get_distant_cell_count() const {
	int count = 0;
	for (const KeyValue<Vector2i, int> &E : active_detail_levels) {
		if (E.value == 1 && is_cell_loaded(E.key)) {
			count++;
		}
	}
	return count;
}

int WorldPartition3D::_cell_detail_level(const Vector2i &p_cell, const Vector2i &p_center, int p_previous_level) const {
	// Pinned gameplay locations always retain full detail. New cells have no
	// previous state and are classified using the unexpanded inner radius.
	if (detail_radius < 0 || _has_residency_claim(p_cell) || _is_cell_required_by_important_source(p_cell) || _within_radius(p_cell, p_center, detail_radius)) {
		return 0;
	}
	// Only an already-near cell enjoys the wider demotion threshold.
	// A distant cell must cross the original inner radius to promote, giving
	// us two different boundaries and preventing back-and-forth LOD thrash.
	if (p_previous_level == 0 && _within_radius(p_cell, p_center, detail_radius + detail_hysteresis_cells)) {
		return 0;
	}
	return 1;
}

void WorldPartition3D::_refresh_cell_detail(const Vector2i &p_center) {
	int budget = max_detail_transitions_per_frame;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (budget <= 0) {
			break;
		}
		int *previous = active_detail_levels.getptr(E.key);
		if (previous == nullptr) {
			continue;
		}
		const int next_level = _cell_detail_level(E.key, p_center, *previous);
		if (*previous == next_level) {
			continue;
		}
		Node *node = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
		if (node == nullptr || !node->has_method(SNAME("set_streaming_lod"))) {
			continue;
		}
		*previous = next_level;
		node->call(SNAME("set_streaming_lod"), next_level);
		emit_signal(SNAME("cell_detail_changed"), E.key, next_level);
		budget--;
	}
}

bool WorldPartition3D::_cell_simulation_active(const Vector2i &p_cell, const Vector2i &p_center, bool p_previously_active) const {
	if (simulation_radius < 0 || _has_residency_claim(p_cell) || _within_radius(p_cell, p_center, simulation_radius)) {
		return true;
	}
	// Extra margin applies only to already-active cells. Inactive cells
	// enter simulation strictly within the inner radius.
	return p_previously_active && _within_radius(p_cell, p_center, simulation_radius + simulation_hysteresis_cells);
}

void WorldPartition3D::_refresh_cell_simulation(const Vector2i &p_center) {
	int budget = max_simulation_transitions_per_frame;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (budget <= 0) {
			break;
		}
		bool *previous = active_simulation_cells.getptr(E.key);
		if (previous == nullptr) {
			continue;
		}
		const bool next = _cell_simulation_active(E.key, p_center, *previous);
		if (*previous == next) {
			continue;
		}
		Node3D *node = Object::cast_to<Node3D>(ObjectDB::get_instance(E.value));
		if (node == nullptr || node->is_queued_for_deletion()) {
			continue;
		}
		*previous = next;
		if (node->has_method(SNAME("set_streaming_simulation_active"))) {
			node->call(SNAME("set_streaming_simulation_active"), next);
		}
		emit_signal(SNAME("cell_simulation_changed"), E.key, next);
		budget--;
	}
}

void WorldPartition3D::set_simulation_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < -1 || p_radius > 32, "WorldPartition3D simulation_radius must be -1 (disabled) or 0 to 32.");
	simulation_radius = p_radius;
}

int WorldPartition3D::get_simulation_radius() const {
	return simulation_radius;
}

void WorldPartition3D::set_simulation_hysteresis_cells(int p_cells) {
	ERR_FAIL_COND_MSG(p_cells < 0 || p_cells > 8, "WorldPartition3D simulation_hysteresis_cells must be between 0 and 8.");
	simulation_hysteresis_cells = p_cells;
}

int WorldPartition3D::get_simulation_hysteresis_cells() const {
	return simulation_hysteresis_cells;
}

void WorldPartition3D::set_max_simulation_transitions_per_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 64, "WorldPartition3D simulation transition budget must be between 1 and 64.");
	max_simulation_transitions_per_frame = p_count;
}

int WorldPartition3D::get_max_simulation_transitions_per_frame() const {
	return max_simulation_transitions_per_frame;
}

bool WorldPartition3D::is_cell_simulation_active(const Vector2i &p_cell) const {
	const bool *active = active_simulation_cells.getptr(p_cell);
	return active != nullptr && *active && get_cell_instance(p_cell) != nullptr;
}

int WorldPartition3D::get_simulation_active_cell_count() const {
	int result = 0;
	for (const KeyValue<Vector2i, bool> &E : active_simulation_cells) {
		if (E.value && get_cell_instance(E.key) != nullptr) {
			result++;
		}
	}
	return result;
}

bool WorldPartition3D::_is_cell_required_by_important_source(const Vector2i &p_cell) const {
	for (const KeyValue<String, StreamingSource> &E : streaming_sources) {
		if (E.value.priority < 2) {
			continue; // Ordinary quest preload must not awaken distant collision.
		}
		const Vector2i center = local_position_to_cell(to_local(E.value.global_position));
		if (_within_radius(p_cell, center, E.value.radius)) {
			return true;
		}
	}
	return false;
}

bool WorldPartition3D::_cell_physics_active(const Vector2i &p_cell, const Vector2i &p_center, bool p_previously_active) const {
	if (physics_radius < 0 || _has_residency_claim(p_cell) || _is_cell_required_by_important_source(p_cell) || _within_radius(p_cell, p_center, physics_radius)) {
		return true;
	}
	return p_previously_active && _within_radius(p_cell, p_center, physics_radius + physics_hysteresis_cells);
}

void WorldPartition3D::_refresh_cell_physics(const Vector2i &p_center) {
	int budget = max_physics_transitions_per_frame;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (budget <= 0) {
			break;
		}
		bool *previous = active_physics_cells.getptr(E.key);
		if (previous == nullptr) {
			continue;
		}
		const bool next = _cell_physics_active(E.key, p_center, *previous);
		if (*previous == next) {
			continue;
		}
		Node3D *root = Object::cast_to<Node3D>(ObjectDB::get_instance(E.value));
		if (root == nullptr || root->is_queued_for_deletion()) {
			continue;
		}
		*previous = next;
		if (next) {
			physics_enabled_frames.insert(E.key, Engine::get_singleton()->get_physics_frames());
		} else {
			physics_enabled_frames.erase(E.key);
		}
		if (root->has_method(SNAME("set_streaming_physics_active"))) {
			root->call(SNAME("set_streaming_physics_active"), next);
		}
		emit_signal(SNAME("cell_physics_changed"), E.key, next);
		budget--;
	}
}

void WorldPartition3D::set_physics_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < -1 || p_radius > 32, "WorldPartition3D physics_radius must be -1 (disabled) or 0 to 32.");
	physics_radius = p_radius;
}

int WorldPartition3D::get_physics_radius() const {
	return physics_radius;
}

void WorldPartition3D::set_physics_hysteresis_cells(int p_cells) {
	ERR_FAIL_COND_MSG(p_cells < 0 || p_cells > 8, "WorldPartition3D physics_hysteresis_cells must be between 0 and 8.");
	physics_hysteresis_cells = p_cells;
}

int WorldPartition3D::get_physics_hysteresis_cells() const {
	return physics_hysteresis_cells;
}

void WorldPartition3D::set_max_physics_transitions_per_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 64, "WorldPartition3D physics transition budget must be between 1 and 64.");
	max_physics_transitions_per_frame = p_count;
}

int WorldPartition3D::get_max_physics_transitions_per_frame() const {
	return max_physics_transitions_per_frame;
}

bool WorldPartition3D::is_cell_physics_active(const Vector2i &p_cell) const {
	const bool *active = active_physics_cells.getptr(p_cell);
	return active != nullptr && *active && get_cell_instance(p_cell) != nullptr;
}

int WorldPartition3D::get_physics_active_cell_count() const {
	int result = 0;
	for (const KeyValue<Vector2i, bool> &E : active_physics_cells) {
		if (E.value && get_cell_instance(E.key) != nullptr) {
			result++;
		}
	}
	return result;
}

bool WorldPartition3D::is_cell_physics_ready(const Vector2i &p_cell) const {
	if (!is_cell_physics_active(p_cell)) {
		return false;
	}
	const uint64_t *enabled_frame = physics_enabled_frames.getptr(p_cell);
	if (enabled_frame == nullptr || Engine::get_singleton()->get_physics_frames() <= *enabled_frame) {
		return false; // At least one completed physics step since enabling.
	}
	Node3D *root = get_cell_instance(p_cell);
	if (root == nullptr) {
		return false;
	}
	if (root->has_method(SNAME("is_streaming_physics_ready"))) {
		const Variant result = root->call(SNAME("is_streaming_physics_ready"));
		return result.get_type() == Variant::BOOL && bool(result);
	}
	return true;
}

bool WorldPartition3D::is_streaming_source_physics_ready(const String &p_name) const {
	if (!is_streaming_source_ready(p_name)) {
		return false;
	}
	const StreamingSource *source = streaming_sources.getptr(p_name);
	if (source == nullptr) {
		return false;
	}
	const Vector2i center = local_position_to_cell(to_local(source->global_position));
	for (int dz = -source->radius; dz <= source->radius; dz++) {
		for (int dx = -source->radius; dx <= source->radius; dx++) {
			const Vector2i cell = center + Vector2i(dx, dz);
			if (!_get_scene_path(cell).is_empty() && !is_cell_physics_ready(cell)) {
				return false;
			}
		}
	}
	return true;
}

bool WorldPartition3D::_cell_navigation_active(const Vector2i &p_cell, const Vector2i &p_center, bool p_previous) const {
	if (navigation_radius < 0 || _has_residency_claim(p_cell) || _is_cell_required_by_important_source(p_cell) || _within_radius(p_cell, p_center, navigation_radius)) {
		return true;
	}
	return p_previous && _within_radius(p_cell, p_center, navigation_radius + navigation_hysteresis_cells);
}

void WorldPartition3D::_refresh_cell_navigation(const Vector2i &p_center) {
	int budget = max_navigation_transitions_per_frame;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if (budget <= 0) {
			break;
		}
		bool *previous = active_navigation_cells.getptr(E.key);
		if (previous == nullptr) {
			continue;
		}
		const bool next = _cell_navigation_active(E.key, p_center, *previous);
		if (*previous == next) {
			continue;
		}
		Node3D *root = Object::cast_to<Node3D>(ObjectDB::get_instance(E.value));
		if (root == nullptr || root->is_queued_for_deletion()) {
			continue;
		}
		*previous = next;
		if (next) {
			navigation_enabled_frames.insert(E.key, Engine::get_singleton()->get_physics_frames());
		} else {
			navigation_enabled_frames.erase(E.key);
		}
		if (root->has_method(SNAME("set_streaming_navigation_active"))) {
			root->call(SNAME("set_streaming_navigation_active"), next);
		}
		if (next && navigation_cell_states.has(E.key)) {
			// A scene script may re-enable regions in the tier callback; an
			// explicit gameplay gate always wins.
			_apply_cell_navigation_state(E.key, root);
		}
		navigation_mesh_generation++;
		emit_signal(SNAME("cell_navigation_changed"), E.key, next);
		budget--;
	}
}

void WorldPartition3D::set_navigation_radius(int p_radius) {
	ERR_FAIL_COND_MSG(p_radius < -1 || p_radius > 32, "WorldPartition3D navigation_radius must be -1 or 0 to 32.");
	navigation_radius = p_radius;
}

int WorldPartition3D::get_navigation_radius() const {
	return navigation_radius;
}

void WorldPartition3D::set_navigation_hysteresis_cells(int p_cells) {
	ERR_FAIL_COND_MSG(p_cells < 0 || p_cells > 8, "WorldPartition3D navigation_hysteresis_cells must be 0 to 8.");
	navigation_hysteresis_cells = p_cells;
}

int WorldPartition3D::get_navigation_hysteresis_cells() const {
	return navigation_hysteresis_cells;
}

void WorldPartition3D::set_max_navigation_transitions_per_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 64, "WorldPartition3D navigation transition budget must be 1 to 64.");
	max_navigation_transitions_per_frame = p_count;
}

int WorldPartition3D::get_max_navigation_transitions_per_frame() const {
	return max_navigation_transitions_per_frame;
}

bool WorldPartition3D::is_cell_navigation_active(const Vector2i &p_cell) const {
	const bool *value = active_navigation_cells.getptr(p_cell);
	return value != nullptr && *value && get_cell_instance(p_cell) != nullptr;
}

int WorldPartition3D::get_navigation_active_cell_count() const {
	int count = 0;
	for (const KeyValue<Vector2i, bool> &E : active_navigation_cells) {
		if (E.value && get_cell_instance(E.key) != nullptr) {
			count++;
		}
	}
	return count;
}

bool WorldPartition3D::is_cell_navigation_ready(const Vector2i &p_cell) const {
	if (!is_cell_navigation_active(p_cell) || navigation_dirty_cells.has(p_cell)) {
		return false; // Dirty tile is not safe for path reuse or fast travel.
	}
	const uint64_t *enabled_frame = navigation_enabled_frames.getptr(p_cell);
	if (enabled_frame == nullptr) {
		return false;
	}
	const uint64_t current_frame = Engine::get_singleton()->get_physics_frames();
	if (current_frame < *enabled_frame || current_frame - *enabled_frame < 2) {
		return false; // Allow scene setup and two physics-frame server synchronizations.
	}
	Node3D *root = get_cell_instance(p_cell);
	if (root == nullptr) {
		return false;
	}
	if (root->has_method(SNAME("is_streaming_navigation_ready"))) {
		const Variant result = root->call(SNAME("is_streaming_navigation_ready"));
		return result.get_type() == Variant::BOOL && bool(result);
	}
	return true; // Legacy scenes are not required to author a navigation mesh.
}

bool WorldPartition3D::is_streaming_source_navigation_ready(const String &p_name) const {
	if (!is_streaming_source_ready(p_name)) {
		return false;
	}
	const StreamingSource *source = streaming_sources.getptr(p_name);
	if (source == nullptr) {
		return false;
	}
	const Vector2i center = local_position_to_cell(to_local(source->global_position));
	for (int dz = -source->radius; dz <= source->radius; dz++) {
		for (int dx = -source->radius; dx <= source->radius; dx++) {
			const Vector2i cell = center + Vector2i(dx, dz);
			if (!_get_scene_path(cell).is_empty() && !is_cell_navigation_ready(cell)) {
				return false;
			}
		}
	}
	return true;
}

void WorldPartition3D::set_max_navigation_rebuilds_per_physics_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 16, "WorldPartition3D navigation mesh rebuild budget must be 1 to 16.");
	max_navigation_rebuilds_per_physics_frame = p_count;
}

int WorldPartition3D::get_max_navigation_rebuilds_per_physics_frame() const {
	return max_navigation_rebuilds_per_physics_frame;
}

bool WorldPartition3D::mark_cell_navigation_dirty(const Vector2i &p_cell) {
	Node3D *root = get_cell_instance(p_cell);
	if (!streaming_enabled || root == nullptr || !root->has_method(SNAME("rebuild_streaming_navigation_mesh"))) {
		return false; // Opt-in scenes only; do not queue unloaded/stale regions.
	}
	if (navigation_dirty_cells.has(p_cell)) {
		return true; // Coalesce repeated changes to the same navigation tile.
	}
	if (navigation_dirty_cells.size() >= MAX_DIRTY_NAVIGATION_CELLS) {
		return false;
	}
	navigation_dirty_cells.insert(p_cell);
	navigation_mesh_generation++; // Invalidate cached routes immediately, not only after rebuild.
	return true;
}

int WorldPartition3D::get_navigation_dirty_cell_count() const {
	return navigation_dirty_cells.size();
}

int WorldPartition3D::get_cell_navigation_revision(const Vector2i &p_cell) const {
	const int *revision = navigation_mesh_revisions.getptr(p_cell);
	return revision != nullptr && get_cell_instance(p_cell) != nullptr ? *revision : -1;
}

int64_t WorldPartition3D::get_navigation_mesh_generation() const {
	return navigation_mesh_generation;
}

void WorldPartition3D::_refresh_dirty_navigation_cells(const Vector2i &p_center) {
	if (navigation_dirty_cells.is_empty()) {
		return;
	}
	const uint64_t frame = Engine::get_singleton()->get_physics_frames();
	if (last_navigation_rebuild_frame == frame) {
		return; // Re-entrant update_streaming() calls cannot bypass the budget.
	}
	last_navigation_rebuild_frame = frame;
	HashSet<Vector2i> attempted;
	for (int attempt = 0; attempt < max_navigation_rebuilds_per_physics_frame; attempt++) {
		bool found = false;
		Vector2i best;
		uint64_t best_distance = UINT64_MAX;
		for (const Vector2i &cell : navigation_dirty_cells) {
			if (attempted.has(cell) || !is_cell_navigation_active(cell)) {
				continue;
			}
			Node3D *root = get_cell_instance(cell);
			if (root == nullptr || !root->has_method(SNAME("rebuild_streaming_navigation_mesh"))) {
				continue;
			}
			const int64_t dx = int64_t(cell.x) - int64_t(p_center.x);
			const int64_t dz = int64_t(cell.y) - int64_t(p_center.y);
			const uint64_t distance = uint64_t(dx < 0 ? -dx : dx) + uint64_t(dz < 0 ? -dz : dz);
			if (!found || distance < best_distance ||
					(distance == best_distance && (cell.x < best.x || (cell.x == best.x && cell.y < best.y)))) {
				found = true;
				best = cell;
				best_distance = distance;
			}
		}
		if (!found) {
			return;
		}
		attempted.insert(best);
		Node3D *root = get_cell_instance(best);
		if (root == nullptr) {
			continue;
		}
		const Variant result = root->call(SNAME("rebuild_streaming_navigation_mesh"));
		if (result.get_type() != Variant::BOOL || !bool(result)) {
			continue; // Keep dirty; retry next physics frame, always fail closed.
		}
		navigation_dirty_cells.erase(best);
		navigation_enabled_frames.insert(best, frame);
		navigation_mesh_generation++;
		int *revision = navigation_mesh_revisions.getptr(best);
		if (revision != nullptr && *revision < INT32_MAX) {
			(*revision)++;
			emit_signal(SNAME("cell_navigation_mesh_rebuilt"), best, *revision);
		}
	}
}

void WorldPartition3D::set_max_navigation_updates_per_physics_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 64, "WorldPartition3D navigation update budget must be 1 to 64 per physics frame.");
	max_navigation_updates_per_physics_frame = p_count;
}

int WorldPartition3D::get_max_navigation_updates_per_physics_frame() const {
	return max_navigation_updates_per_physics_frame;
}

bool WorldPartition3D::register_navigation_agent(const String &p_name, Node3D *p_agent, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_name.is_empty() || p_name.length() > 64, false, "Navigation agent name must contain 1 to 64 characters.");
	ERR_FAIL_COND_V_MSG(p_agent == nullptr, false, "Navigation agent must be a Node3D.");
	ERR_FAIL_COND_V_MSG(p_priority < 0 || p_priority > 3, false, "Navigation priority must be 0 to 3.");
	ERR_FAIL_COND_V_MSG(!navigation_agents.has(p_name) && navigation_agents.size() >= MAX_NAVIGATION_AGENTS, false, "WorldPartition3D has reached its 128-agent limit.");
	// One live Node3D may have only one registered name, so aliases cannot
	// claim multiple path/steering grants under different IDs.
	for (const KeyValue<String, NavigationAgentEntry> &E : navigation_agents) {
		if (E.key != p_name && E.value.node_id == p_agent->get_instance_id()) {
			return false;
		}
	}
	NavigationAgentEntry next;
	next.node_id = p_agent->get_instance_id();
	next.priority = p_priority;
	const NavigationAgentEntry *previous = navigation_agents.getptr(p_name);
	if (previous != nullptr && previous->node_id == next.node_id) {
		next.last_selected_frame = previous->last_selected_frame;
	}
	navigation_agents.insert(p_name, next);
	// Existing frame reservations deliberately do not reset; upserts cannot
	// spend extra slots by repeatedly registering during the same frame.
	return true;
}

bool WorldPartition3D::unregister_navigation_agent_if_owner(const String &p_name, Node3D *p_agent) {
	const NavigationAgentEntry *entry = navigation_agents.getptr(p_name);
	if (entry == nullptr || p_agent == nullptr || entry->node_id != p_agent->get_instance_id()) {
		return false;
	}
	navigation_agents.erase(p_name);
	return true;
}

void WorldPartition3D::unregister_navigation_agent(const String &p_name) {
	navigation_agents.erase(p_name);
	// Do not clear existing frame reservations: deregister/re-register must not
	// circumvent the per-physics-frame budget.
}

bool WorldPartition3D::has_navigation_agent(const String &p_name) const {
	return navigation_agents.has(p_name);
}

int WorldPartition3D::get_navigation_agent_count() const {
	return navigation_agents.size();
}

bool WorldPartition3D::set_navigation_agent_priority(const String &p_name, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_priority < 0 || p_priority > 3, false, "Navigation priority must be 0 to 3.");
	NavigationAgentEntry *entry = navigation_agents.getptr(p_name);
	if (entry == nullptr) {
		return false;
	}
	entry->priority = p_priority;
	return true;
}

int WorldPartition3D::get_navigation_agent_priority(const String &p_name) const {
	const NavigationAgentEntry *entry = navigation_agents.getptr(p_name);
	return entry != nullptr ? entry->priority : -1;
}

void WorldPartition3D::_schedule_navigation_updates() {
	const uint64_t frame = Engine::get_singleton()->get_physics_frames();
	if (navigation_schedule_valid && navigation_schedule_frame == frame) {
		return;
	}
	navigation_schedule_frame = frame;
	navigation_schedule_valid = true;
	navigation_selected.clear();
	navigation_consumed.clear();

	Vector<String> candidates;
	Vector<String> stale;
	for (const KeyValue<String, NavigationAgentEntry> &E : navigation_agents) {
		Node3D *node = Object::cast_to<Node3D>(ObjectDB::get_instance(E.value.node_id));
		if (node == nullptr || node->is_queued_for_deletion()) {
			stale.push_back(E.key);
			continue;
		}
		if (!node->is_inside_tree() || !node->is_physics_processing() || !node->can_process()) {
			continue;
		}
		const Vector2i cell = local_position_to_cell(to_local(node->get_global_position()));
		if (!is_cell_simulation_active(cell) || !is_cell_physics_active(cell)) {
			continue; // Never spend navigation work on a dormant streamed cell.
		}
		candidates.push_back(E.key);
	}
	for (const String &name : stale) {
		navigation_agents.erase(name);
	}
	candidates.sort(); // Stable tie-break independent of HashMap iteration.
	const int budget = MIN(max_navigation_updates_per_physics_frame, candidates.size());
	for (int slot = 0; slot < budget; slot++) {
		int best_index = -1;
		for (int i = 0; i < candidates.size(); i++) {
			if (navigation_selected.has(candidates[i])) {
				continue;
			}
			const NavigationAgentEntry *entry = navigation_agents.getptr(candidates[i]);
			if (entry == nullptr) {
				continue;
			}
			if (best_index < 0) {
				best_index = i;
				continue;
			}
			const NavigationAgentEntry *best = navigation_agents.getptr(candidates[best_index]);
			if (entry->priority > best->priority ||
					(entry->priority == best->priority && entry->last_selected_frame < best->last_selected_frame)) {
				best_index = i;
			}
		}
		if (best_index < 0) {
			break;
		}
		const String &name = candidates[best_index];
		navigation_selected.insert(name);
		NavigationAgentEntry *entry = navigation_agents.getptr(name);
		entry->last_selected_frame = frame;
	}
}

bool WorldPartition3D::try_acquire_navigation_update(const String &p_name) {
	if (!streaming_enabled || !is_inside_tree() || !navigation_agents.has(p_name)) {
		return false;
	}
	_schedule_navigation_updates();
	if (!navigation_selected.has(p_name) || navigation_consumed.has(p_name)) {
		return false;
	}
	NavigationAgentEntry *entry = navigation_agents.getptr(p_name);
	Node3D *node = entry != nullptr ? Object::cast_to<Node3D>(ObjectDB::get_instance(entry->node_id)) : nullptr;
	if (node == nullptr || node->is_queued_for_deletion() || !node->is_inside_tree() || !node->is_physics_processing() || !node->can_process()) {
		return false;
	}
	const Vector2i cell = local_position_to_cell(to_local(node->get_global_position()));
	if (!is_cell_simulation_active(cell) || !is_cell_physics_active(cell)) {
		return false;
	}
	navigation_consumed.insert(p_name);
	return true;
}

int WorldPartition3D::get_navigation_updates_used_this_frame() const {
	return navigation_schedule_valid && navigation_schedule_frame == Engine::get_singleton()->get_physics_frames() ? navigation_consumed.size() : 0;
}

void WorldPartition3D::set_observer_path(const NodePath &p_path) {
	if (observer_path == p_path) {
		return;
	}
	observer_path = p_path;
	observer_cell_valid = false;
	predicted_cell_valid = false;
}

NodePath WorldPartition3D::get_observer_path() const {
	return observer_path;
}

void WorldPartition3D::set_predictive_velocity(const Vector3 &p_velocity) {
	ERR_FAIL_COND_MSG(!p_velocity.is_finite(), "WorldPartition3D predictive_velocity must have finite components.");
	// Keep calculations bounded even if game code supplies pathological velocities.
	const real_t speed = p_velocity.length();
	ERR_FAIL_COND_MSG(!Math::is_finite(speed), "WorldPartition3D predictive_velocity magnitude must be finite.");
	predictive_velocity = speed > 512.0 ? p_velocity * (512.0 / speed) : p_velocity;
}

Vector3 WorldPartition3D::get_predictive_velocity() const {
	return predictive_velocity;
}

void WorldPartition3D::set_predictive_lookahead_seconds(real_t p_seconds) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_seconds) || p_seconds < 0.0 || p_seconds > 5.0, "WorldPartition3D lookahead must be between 0 and 5 seconds.");
	predictive_lookahead_seconds = p_seconds;
	if (p_seconds == 0.0) {
		predicted_cell_valid = false;
	}
}

real_t WorldPartition3D::get_predictive_lookahead_seconds() const {
	return predictive_lookahead_seconds;
}

void WorldPartition3D::set_predictive_max_distance(real_t p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance) || p_distance < 0.0 || p_distance > 128.0, "WorldPartition3D maximum prediction distance must be between 0 and 128 world units.");
	predictive_max_distance = p_distance;
	if (p_distance == 0.0) {
		predicted_cell_valid = false;
	}
}

real_t WorldPartition3D::get_predictive_max_distance() const {
	return predictive_max_distance;
}

bool WorldPartition3D::has_predicted_cell() const {
	return predicted_cell_valid;
}

Vector2i WorldPartition3D::get_predicted_cell() const {
	return predicted_cell_valid ? predicted_cell : Vector2i();
}

bool WorldPartition3D::has_observer_cell() const {
	return observer_cell_valid;
}

Vector2i WorldPartition3D::get_observer_cell() const {
	return observer_cell_valid ? observer_cell : Vector2i();
}

// Exact planar triangle-vs-disc distance: obstacle clearance must account
// for triangle edges, not merely triangle centers (which can miss collision).
static real_t _world_partition_point_segment_distance_squared(const Vector2 &p, const Vector2 &a, const Vector2 &b) {
	const Vector2 edge = b - a;
	const real_t length_squared = edge.length_squared();
	if (length_squared <= CMP_EPSILON) {
		return p.distance_squared_to(a);
	}
	const real_t fraction = CLAMP((p - a).dot(edge) / length_squared, (real_t)0.0, (real_t)1.0);
	return p.distance_squared_to(a + edge * fraction);
}

static bool _world_partition_triangle_overlaps_disc(const Vector2 &a, const Vector2 &b, const Vector2 &c, const Vector2 &center, real_t p_radius) {
	const real_t signed_ab = (b - a).cross(center - a);
	const real_t signed_bc = (c - b).cross(center - b);
	const real_t signed_ca = (a - c).cross(center - c);
	// Conservatively include boundary points regardless of triangle winding.
	const bool inside = (signed_ab >= 0.0 && signed_bc >= 0.0 && signed_ca >= 0.0) ||
			(signed_ab <= 0.0 && signed_bc <= 0.0 && signed_ca <= 0.0);
	if (inside) {
		return true;
	}
	const real_t radius_squared = p_radius * p_radius;
	return _world_partition_point_segment_distance_squared(center, a, b) <= radius_squared ||
			_world_partition_point_segment_distance_squared(center, b, c) <= radius_squared ||
			_world_partition_point_segment_distance_squared(center, c, a) <= radius_squared;
}

// Shared with both the complete builder and incremental replacement:
// their slope and circle-clearance behavior must stay bit-for-bit identical.
static bool _world_partition_navigation_triangle_allowed(const PackedVector3Array &p_vertices, const int p_indices[3], const PackedVector3Array &p_blockers, real_t p_agent_radius, real_t p_minimum_up) {
	const Vector3 &v0 = p_vertices[p_indices[0]];
	const Vector3 &v1 = p_vertices[p_indices[1]];
	const Vector3 &v2 = p_vertices[p_indices[2]];
	const Vector3 normal = (v1 - v0).cross(v2 - v0);
	const real_t length = normal.length();
	if (length <= CMP_EPSILON || normal.y < length * p_minimum_up) {
		return false;
	}
	const Vector2 p0(v0.x, v0.z);
	const Vector2 p1(v1.x, v1.z);
	const Vector2 p2(v2.x, v2.z);
	const real_t min_x = MIN(p0.x, MIN(p1.x, p2.x));
	const real_t max_x = MAX(p0.x, MAX(p1.x, p2.x));
	const real_t min_z = MIN(p0.y, MIN(p1.y, p2.y));
	const real_t max_z = MAX(p0.y, MAX(p1.y, p2.y));
	for (int i = 0; i < p_blockers.size(); i++) {
		const Vector3 &blocker = p_blockers[i];
		const real_t radius = blocker.z + p_agent_radius;
		if (blocker.x < min_x - radius || blocker.x > max_x + radius || blocker.y < min_z - radius || blocker.y > max_z + radius) {
			continue;
		}
		if (_world_partition_triangle_overlaps_disc(p0, p1, p2, Vector2(blocker.x, blocker.y), radius)) {
			return false;
		}
	}
	return true;
}

static uint64_t _world_partition_triangle_id(int p_a, int p_b, int p_c) {
	// Resolution is at most 32, thus all vertex indices are smaller than
	// 1089 < 2^11. Keep all three ordered indices in an exact 64-bit key.
	return (uint64_t(p_a) << 22) | (uint64_t(p_b) << 11) | uint64_t(p_c);
}

Ref<NavigationMesh> WorldPartition3D::build_navigation_tile(const PackedVector3Array &p_vertices, int p_resolution, const PackedVector3Array &p_blockers, real_t p_agent_radius, real_t p_max_slope_degrees) const {
	last_navigation_tile_retested_triangles = 0;
	ERR_FAIL_COND_V_MSG(p_resolution < 2 || p_resolution > MAX_NAVMESH_TILE_RESOLUTION, Ref<NavigationMesh>(), "Navigation tile resolution must be 2 to 32.");
	const int stride = p_resolution + 1;
	ERR_FAIL_COND_V_MSG(p_vertices.size() != stride * stride, Ref<NavigationMesh>(), "Navigation tile vertices must contain (resolution+1)^2 samples in Z-major, then X-major order.");
	ERR_FAIL_COND_V_MSG(p_blockers.size() > MAX_NAVMESH_TILE_BLOCKERS, Ref<NavigationMesh>(), "Navigation tile supports up to 256 circular blockers.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_agent_radius) || p_agent_radius < 0.0 || p_agent_radius > 8.0, Ref<NavigationMesh>(), "Navigation agent clearance radius must be 0 to 8.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_max_slope_degrees) || p_max_slope_degrees < 0.0 || p_max_slope_degrees > 89.0, Ref<NavigationMesh>(), "Maximum navigation slope must be 0 to 89 degrees.");
	for (int i = 0; i < p_vertices.size(); i++) {
		ERR_FAIL_COND_V_MSG(!p_vertices[i].is_finite(), Ref<NavigationMesh>(), "Non-finite sampled navigation vertex.");
	}
	for (int i = 0; i < p_blockers.size(); i++) {
		ERR_FAIL_COND_V_MSG(!p_blockers[i].is_finite() || p_blockers[i].z < 0.0 || p_blockers[i].z > 16.0, Ref<NavigationMesh>(), "Circular blocker must be finite and have a radius of 0 to 16.");
	}
	Ref<NavigationMesh> navigation_mesh;
	navigation_mesh.instantiate();
	navigation_mesh->set_vertices(p_vertices);
	const real_t minimum_up = Math::cos(Math::deg_to_rad(p_max_slope_degrees));
	for (int z = 0; z < p_resolution; z++) {
		for (int x = 0; x < p_resolution; x++) {
			const int a = z * stride + x;
			const int b = a + 1;
			const int c = a + stride;
			const int d = c + 1;
			const int triangles[2][3] = { { a, c, b }, { b, c, d } };
			for (int triangle_index = 0; triangle_index < 2; triangle_index++) {
				const int *indexes = triangles[triangle_index];
				last_navigation_tile_retested_triangles++;
				if (_world_partition_navigation_triangle_allowed(p_vertices, indexes, p_blockers, p_agent_radius, minimum_up)) {
					Vector<int> polygon;
					polygon.push_back(indexes[0]);
					polygon.push_back(indexes[1]);
					polygon.push_back(indexes[2]);
					navigation_mesh->add_polygon(polygon);
				}
			}
		}
	}
	return navigation_mesh;
}

Ref<NavigationMesh> WorldPartition3D::patch_navigation_tile(const Ref<NavigationMesh> &p_previous, int p_resolution, const PackedVector3Array &p_previous_blockers, const PackedVector3Array &p_blockers, real_t p_agent_radius, real_t p_max_slope_degrees) const {
	last_navigation_tile_retested_triangles = 0;
	ERR_FAIL_COND_V_MSG(p_previous.is_null(), Ref<NavigationMesh>(), "An incremental patch requires a prior valid NavigationMesh.");
	ERR_FAIL_COND_V_MSG(p_resolution < 2 || p_resolution > MAX_NAVMESH_TILE_RESOLUTION, Ref<NavigationMesh>(), "Navigation tile patch resolution must be 2 to 32.");
	ERR_FAIL_COND_V_MSG(p_previous_blockers.size() > MAX_NAVMESH_TILE_BLOCKERS || p_blockers.size() > MAX_NAVMESH_TILE_BLOCKERS, Ref<NavigationMesh>(), "Navigation tile patch accepts at most 256 old and 256 new blockers.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_agent_radius) || p_agent_radius < 0.0 || p_agent_radius > 8.0, Ref<NavigationMesh>(), "Navigation tile patch agent radius must be 0 to 8.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_max_slope_degrees) || p_max_slope_degrees < 0.0 || p_max_slope_degrees > 89.0, Ref<NavigationMesh>(), "Navigation tile patch slope must be 0 to 89 degrees.");
	const int stride = p_resolution + 1;
	const PackedVector3Array vertices = p_previous->get_vertices();
	ERR_FAIL_COND_V_MSG(vertices.size() != stride * stride, Ref<NavigationMesh>(), "Previous NavigationMesh vertex count does not match the requested tile resolution.");
	for (int i = 0; i < vertices.size(); i++) {
		ERR_FAIL_COND_V_MSG(!vertices[i].is_finite(), Ref<NavigationMesh>(), "Previous NavMesh contains non-finite terrain vertices.");
	}
	for (int i = 0; i < p_previous_blockers.size(); i++) {
		ERR_FAIL_COND_V_MSG(!p_previous_blockers[i].is_finite() || p_previous_blockers[i].z < 0.0 || p_previous_blockers[i].z > 16.0, Ref<NavigationMesh>(), "Previous blocker must have finite coordinates and radius 0 to 16.");
	}
	for (int i = 0; i < p_blockers.size(); i++) {
		ERR_FAIL_COND_V_MSG(!p_blockers[i].is_finite() || p_blockers[i].z < 0.0 || p_blockers[i].z > 16.0, Ref<NavigationMesh>(), "New blocker must have finite coordinates and radius 0 to 16.");
	}

	// The caller must provide the same terrain, agent radius and slope policy
	// as the original build. Validate the original topology before reusing it.
	// A foreign or malformed mesh is safely rebuilt in full, not trusted.
	HashSet<uint64_t> existing_triangles;
	const int polygon_count = p_previous->get_polygon_count();
	if (polygon_count > 2 * p_resolution * p_resolution) {
		return build_navigation_tile(vertices, p_resolution, p_blockers, p_agent_radius, p_max_slope_degrees);
	}
	for (int i = 0; i < polygon_count; i++) {
		const Vector<int> polygon = p_previous->get_polygon(i);
		if (polygon.size() != 3) {
			return build_navigation_tile(vertices, p_resolution, p_blockers, p_agent_radius, p_max_slope_degrees);
		}
		const int first = polygon[0];
		const int second = polygon[1];
		const int third = polygon[2];
		if (first < 0 || first >= vertices.size() || second < 0 || second >= vertices.size() || third < 0 || third >= vertices.size()) {
			return build_navigation_tile(vertices, p_resolution, p_blockers, p_agent_radius, p_max_slope_degrees);
		}
		const int row = first / stride;
		const int column = first % stride;
		const bool upper_triangle = row < p_resolution && column < p_resolution && second == first + stride && third == first + 1;
		const bool lower_triangle = row < p_resolution && column > 0 && second == first + stride - 1 && third == first + stride;
		const uint64_t id = _world_partition_triangle_id(first, second, third);
		if ((!upper_triangle && !lower_triangle) || existing_triangles.has(id)) {
			return build_navigation_tile(vertices, p_resolution, p_blockers, p_agent_radius, p_max_slope_degrees);
		}
		existing_triangles.insert(id);
	}

	// Match blockers as a multiset so order changes alone are cache hits and
	// duplicate footprints are tracked accurately. Bound worst case to 256^2.
	HashSet<int> consumed_new;
	real_t min_x = std::numeric_limits<real_t>::max();
	real_t min_z = std::numeric_limits<real_t>::max();
	real_t max_x = -std::numeric_limits<real_t>::max();
	real_t max_z = -std::numeric_limits<real_t>::max();
	bool changed = false;
	auto add_dirty_footprint = [&](const Vector3 &p_blocker) {
		const real_t radius = p_blocker.z + p_agent_radius;
		min_x = MIN(min_x, p_blocker.x - radius);
		min_z = MIN(min_z, p_blocker.y - radius);
		max_x = MAX(max_x, p_blocker.x + radius);
		max_z = MAX(max_z, p_blocker.y + radius);
		changed = true;
	};
	for (int old_i = 0; old_i < p_previous_blockers.size(); old_i++) {
		bool matched = false;
		for (int new_i = 0; new_i < p_blockers.size(); new_i++) {
			if (!consumed_new.has(new_i) && p_previous_blockers[old_i] == p_blockers[new_i]) {
				consumed_new.insert(new_i);
				matched = true;
				break;
			}
		}
		if (!matched) {
			add_dirty_footprint(p_previous_blockers[old_i]);
		}
	}
	for (int new_i = 0; new_i < p_blockers.size(); new_i++) {
		if (!consumed_new.has(new_i)) {
			add_dirty_footprint(p_blockers[new_i]);
		}
	}
	if (!changed) {
		// Immutable cache hit: caller can retain the same NavigationMesh Ref.
		return p_previous;
	}
	if (!Math::is_finite(min_x) || !Math::is_finite(min_z) || !Math::is_finite(max_x) || !Math::is_finite(max_z)) {
		return build_navigation_tile(vertices, p_resolution, p_blockers, p_agent_radius, p_max_slope_degrees);
	}

	// Reconstruct polygons in canonical grid order. Triangles wholly outside
	// the changed region reuse the old walkability mask with zero geometry
	// tests, while overlapping triangles use the same filter as a full bake.
	Ref<NavigationMesh> refreshed;
	refreshed.instantiate();
	refreshed->set_vertices(vertices);
	const real_t min_up = Math::cos(Math::deg_to_rad(p_max_slope_degrees));
	for (int z = 0; z < p_resolution; z++) {
		for (int x = 0; x < p_resolution; x++) {
			const int a = z * stride + x;
			const int b = a + 1;
			const int c = a + stride;
			const int d = c + 1;
			const int triangles[2][3] = { { a, c, b }, { b, c, d } };
			for (int t = 0; t < 2; t++) {
				const int *indices = triangles[t];
				const Vector3 &v0 = vertices[indices[0]];
				const Vector3 &v1 = vertices[indices[1]];
				const Vector3 &v2 = vertices[indices[2]];
				const real_t triangle_min_x = MIN(v0.x, MIN(v1.x, v2.x));
				const real_t triangle_max_x = MAX(v0.x, MAX(v1.x, v2.x));
				const real_t triangle_min_z = MIN(v0.z, MIN(v1.z, v2.z));
				const real_t triangle_max_z = MAX(v0.z, MAX(v1.z, v2.z));
				const bool touches_change = !(triangle_max_x < min_x || triangle_min_x > max_x || triangle_max_z < min_z || triangle_min_z > max_z);
				bool keep = false;
				if (touches_change) {
					last_navigation_tile_retested_triangles++;
					keep = _world_partition_navigation_triangle_allowed(vertices, indices, p_blockers, p_agent_radius, min_up);
				} else {
					keep = existing_triangles.has(_world_partition_triangle_id(indices[0], indices[1], indices[2]));
				}
				if (keep) {
					Vector<int> polygon;
					polygon.push_back(indices[0]);
					polygon.push_back(indices[1]);
					polygon.push_back(indices[2]);
					refreshed->add_polygon(polygon);
				}
			}
		}
	}
	return refreshed;
}

int WorldPartition3D::get_last_navigation_tile_retested_triangle_count() const {
	return last_navigation_tile_retested_triangles;
}

void WorldPartition3D::_invalidate_cell_path_cache(bool p_registered_topology) {
	if (p_registered_topology) {
		cell_registration_revision++;
		cell_path_cache.clear(); // Registered paths and live-only paths both changed.
		return;
	}
	cell_loading_revision++;
	// Loading or unloading changes only paths constrained to live scene roots.
	// Keep configured-graph routes valid for the quest compass and planners.
	Vector<String> stale;
	for (const KeyValue<String, CellPathCacheEntry> &E : cell_path_cache) {
		if (E.value.loaded_only) {
			stale.push_back(E.key);
		}
	}
	for (const String &key : stale) {
		cell_path_cache.erase(key);
	}
}

void WorldPartition3D::set_max_cell_path_cache_entries(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 0 || p_count > MAX_CELL_PATH_CACHE_ENTRIES, "Cell route cache size must be 0 to 128.");
	if (max_cell_path_cache_entries != p_count) {
		max_cell_path_cache_entries = p_count;
		cell_path_cache.clear(); // Reject stale evictions after a capacity change.
	}
}

int WorldPartition3D::get_max_cell_path_cache_entries() const {
	return max_cell_path_cache_entries;
}

int WorldPartition3D::get_cell_path_cache_entry_count() const {
	return cell_path_cache.size();
}

int WorldPartition3D::get_cell_path_cache_hit_count() const {
	return cell_path_cache_hits;
}

int WorldPartition3D::get_cell_path_cache_miss_count() const {
	return cell_path_cache_misses;
}

void WorldPartition3D::clear_cell_path_cache() {
	cell_path_cache.clear();
	cell_path_cache_hits = 0;
	cell_path_cache_misses = 0;
	cell_path_cache_serial = 0;
}

Array WorldPartition3D::find_cell_path(const Vector2i &p_from, const Vector2i &p_to, bool p_loaded_only) const {
	// Full signed coordinates + the loaded-only flag form a collision-free
	// identity. Never key on a 32-bit hash alone (different maps can collide).
	const String key = vformat("%d,%d;%d,%d;%d", p_from.x, p_from.y, p_to.x, p_to.y, int(p_loaded_only));
	if (max_cell_path_cache_entries > 0) {
		CellPathCacheEntry *cached = cell_path_cache.getptr(key);
		if (cached != nullptr) {
			bool valid = cached->registration_revision == cell_registration_revision &&
					(!p_loaded_only || cached->loaded_revision == cell_loading_revision);
			if (valid && p_loaded_only) {
				// User scripts may queue_free a child scene without asking the native
				// streamer. Do not return a cached live route through that root.
				for (int i = 0; i < cached->route.size(); i++) {
					const Vector2i route_cell = cached->route[i];
					if (get_cell_instance(route_cell) == nullptr) {
						valid = false;
						break;
					}
				}
			}
			if (valid) {
				cached->last_access = ++cell_path_cache_serial;
				if (cell_path_cache_hits < INT32_MAX) {
					cell_path_cache_hits++;
				}
				// Godot Array is reference-counted. Never share the internal cached
				// Array with scripts, which are free to append/erase/reorder cells.
				return cached->route.duplicate();
			}
			cell_path_cache.erase(key);
		}
	}
	if (cell_path_cache_misses < INT32_MAX) {
		cell_path_cache_misses++;
	}
	const Array route = _find_cell_path_uncached(p_from, p_to, p_loaded_only);
	if (max_cell_path_cache_entries > 0) {
		if (cell_path_cache.size() >= max_cell_path_cache_entries) {
			bool found = false;
			String oldest_key;
			uint64_t oldest_access = UINT64_MAX;
			for (const KeyValue<String, CellPathCacheEntry> &E : cell_path_cache) {
				if (!found || E.value.last_access < oldest_access ||
						(E.value.last_access == oldest_access && E.key < oldest_key)) {
					found = true;
					oldest_key = E.key;
					oldest_access = E.value.last_access;
				}
			}
			if (found) {
				cell_path_cache.erase(oldest_key);
			}
		}
		CellPathCacheEntry fresh;
		fresh.route = route.duplicate();
		fresh.registration_revision = cell_registration_revision;
		fresh.loaded_revision = cell_loading_revision;
		fresh.last_access = ++cell_path_cache_serial;
		fresh.loaded_only = p_loaded_only;
		cell_path_cache.insert(key, fresh);
	}
	return route;
}

Array WorldPartition3D::_find_cell_path_uncached(const Vector2i &p_from, const Vector2i &p_to, bool p_loaded_only) const {
	Array result;
	// A valid route must begin and end on registered cells, including singleton
	// paths. A 'loaded only' route cannot cross a queued-for-free scene root.
	if (_get_scene_path(p_from).is_empty() || _get_scene_path(p_to).is_empty()) {
		return result;
	}
	if (p_loaded_only && (get_cell_instance(p_from) == nullptr || get_cell_instance(p_to) == nullptr)) {
		return result;
	}
	if (p_from == p_to) {
		result.push_back(p_from);
		return result;
	}

	Vector<Vector2i> frontier;
	HashSet<Vector2i> visited;
	HashMap<Vector2i, Vector2i> predecessor;
	frontier.push_back(p_from);
	visited.insert(p_from);
	const Vector2i directions[4] = { Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1) };
	int cursor = 0;
	while (cursor < frontier.size()) {
		const Vector2i current = frontier[cursor++];
		for (int i = 0; i < 4; i++) {
			// Check in 64-bit before converting back to 32-bit cell coordinates:
			// callers may legitimately register cells near the integer limits.
			const int64_t nx = int64_t(current.x) + directions[i].x;
			const int64_t nz = int64_t(current.y) + directions[i].y;
			if (nx < std::numeric_limits<int32_t>::min() || nx > std::numeric_limits<int32_t>::max() ||
					nz < std::numeric_limits<int32_t>::min() || nz > std::numeric_limits<int32_t>::max()) {
				continue;
			}
			const Vector2i neighbor{ int32_t(nx), int32_t(nz) };
			if (visited.has(neighbor) || _get_scene_path(neighbor).is_empty() || (p_loaded_only && get_cell_instance(neighbor) == nullptr)) {
				continue;
			}
			if (visited.size() >= MAX_PATH_SEARCH_CELLS) {
				// Fail closed rather than blow the frame budget on a large connected
				// grid. A chunked/hierarchical planner can relax this bound later.
				return Array();
			}
			visited.insert(neighbor);
			predecessor.insert(neighbor, current);
			if (neighbor == p_to) {
				Vector<Vector2i> reverse;
				Vector2i step = p_to;
				reverse.push_back(step);
				while (step != p_from) {
					const Vector2i *previous = predecessor.getptr(step);
					if (previous == nullptr || reverse.size() >= MAX_PATH_SEARCH_CELLS) {
						return Array();
					}
					step = *previous;
					reverse.push_back(step);
				}
				for (int j = reverse.size() - 1; j >= 0; j--) {
					result.push_back(reverse[j]);
				}
				return result;
			}
			frontier.push_back(neighbor);
		}
	}
	return result; // Disconnected or no passable loaded cell corridor.
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
	_invalidate_cell_path_cache(true);
	// Keep pins for retained registrations; prevent stale pins from keeping
	// a future replacement scene loaded under the same grid coordinate.
	Vector<Vector2i> stale_pins;
	for (const Vector2i &cell : pinned_cells) {
		if (!cell_scenes.has(cell)) {
			stale_pins.push_back(cell);
		}
	}
	for (const Vector2i &cell : stale_pins) {
		pinned_cells.erase(cell);
	}
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
	_invalidate_cell_path_cache(true);
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
	_invalidate_cell_path_cache(true);
	pinned_cells.erase(p_cell);
	_purge_unused_ready_scenes();
}

void WorldPartition3D::clear_cell_scenes() {
	_clear_active_cells();
	pending_cells.clear();
	failed_cells.clear();
	cell_scenes.clear();
	_invalidate_cell_path_cache(true);
	pinned_cells.clear();
	_purge_unused_ready_scenes();
}

bool WorldPartition3D::pin_cell(const Vector2i &p_cell) {
	ERR_FAIL_COND_V_MSG(_get_scene_path(p_cell).is_empty(), false, "WorldPartition3D cannot pin an unregistered cell.");
	if (pinned_cells.has(p_cell)) {
		return false;
	}
	ERR_FAIL_COND_V_MSG(pinned_cells.size() >= MAX_PINNED_CELLS, false, "WorldPartition3D supports at most 128 pinned cells.");
	pinned_cells.push_back(p_cell);
	unload_after_claim_released = false;
	return true;
}

void WorldPartition3D::unpin_cell(const Vector2i &p_cell) {
	if (pinned_cells.has(p_cell)) {
		pinned_cells.erase(p_cell);
		unload_after_claim_released = true;
	}
}

void WorldPartition3D::set_pinned_cells(const Array &p_cells) {
	ERR_FAIL_COND_MSG(p_cells.size() > MAX_PINNED_CELLS, "WorldPartition3D supports at most 128 pinned cells.");
	// Keep order, drop duplicates, non-cells and unregistered coordinates.
	Vector<Vector2i> clean;
	for (int i = 0; i < p_cells.size(); i++) {
		if (p_cells[i].get_type() != Variant::VECTOR2I) {
			continue;
		}
		const Vector2i cell = p_cells[i];
		if (!_get_scene_path(cell).is_empty() && !clean.has(cell)) {
			clean.push_back(cell);
		}
	}
	bool removed_any = false;
	for (const Vector2i &cell : pinned_cells) {
		if (!clean.has(cell)) {
			removed_any = true;
			break;
		}
	}
	pinned_cells = clean;
	if (removed_any) {
		unload_after_claim_released = true;
	}
}

void WorldPartition3D::clear_pinned_cells() {
	if (!pinned_cells.is_empty()) {
		pinned_cells.clear();
		unload_after_claim_released = true;
	}
}

bool WorldPartition3D::is_cell_pinned(const Vector2i &p_cell) const {
	return pinned_cells.has(p_cell);
}

Array WorldPartition3D::get_pinned_cells() const {
	Array result;
	for (const Vector2i &cell : pinned_cells) {
		result.push_back(cell);
	}
	return result;
}

int WorldPartition3D::get_pinned_cell_count() const {
	return pinned_cells.size();
}

int WorldPartition3D::acquire_cell_lease(const Vector2i &p_cell) {
	ERR_FAIL_COND_V_MSG(cell_leases.size() >= MAX_CELL_LEASES, 0, "WorldPartition3D allows at most 256 active cell leases.");
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
		unload_after_claim_released = false;
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
	unload_after_claim_released = true;
	return true;
}

void WorldPartition3D::clear_cell_leases() {
	if (!cell_leases.is_empty()) {
		cell_leases.clear();
		cell_lease_counts.clear();
		unload_after_claim_released = true;
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
	ERR_FAIL_COND_V_MSG(int64_t(cell_leases.size()) + cells.size() > MAX_CELL_LEASES, Array(), "WorldPartition3D route exceeds available lease token capacity.");
	for (int i = 0; i < cells.size(); i++) {
		const Vector2i cell = cells[i];
		if (!_is_cell_layer_enabled(cell) || !is_cell_navigation_enabled(cell)) {
			// Gameplay layers and navigation switches both gate routes. Failed
			// reservations never keep partial corridor token leases.
			return Array();
		}
	}
	for (int i = 1; i < cells.size(); i++) {
		const Vector2i previous = cells[i - 1];
		const Vector2i current = cells[i];
		if (!_is_route_connection_open(previous, current)) {
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

void WorldPartition3D::_apply_loaded_navigation_link(const Vector2i &p_cell, const String &p_link_path, bool p_enabled) {
	if (!_valid_body_path(p_link_path) || p_link_path.length() > 256) {
		return;
	}
	Node *root = get_cell_instance(p_cell);
	if (root == nullptr) {
		return;
	}
	const NodePath path(p_link_path);
	NavigationLink3D *link = Object::cast_to<NavigationLink3D>(root->get_node_or_null(path));
	if (link != nullptr && root->is_ancestor_of(link)) {
		link->set_enabled(p_enabled);
	}
}

void WorldPartition3D::_apply_cell_navigation_links(const Vector2i &p_cell, Node *p_instance) {
	if (p_instance == nullptr || !navigation_link_states.has(p_cell)) {
		return;
	}
	const Dictionary state = navigation_link_states[p_cell];
	const Array paths = state.keys();
	for (int i = 0; i < paths.size(); i++) {
		const String path = paths[i];
		_apply_loaded_navigation_link(p_cell, path, false);
	}
}

bool WorldPartition3D::is_cell_navigation_link_enabled(const Vector2i &p_cell, const String &p_link_path) const {
	if (!navigation_link_states.has(p_cell)) {
		return true;
	}
	const Dictionary states = navigation_link_states[p_cell];
	return !states.has(p_link_path);
}

void WorldPartition3D::set_cell_navigation_link_enabled(const Vector2i &p_cell, const String &p_link_path, bool p_enabled) {
	ERR_FAIL_COND_MSG(!_valid_body_path(p_link_path) || p_link_path.length() > 256, "WorldPartition3D navigation link path must be a safe relative NodePath of at most 256 characters.");
	if (is_cell_navigation_link_enabled(p_cell, p_link_path) == p_enabled) {
		return;
	}
	Dictionary states = navigation_link_states.get(p_cell, Dictionary());
	if (p_enabled) {
		states.erase(p_link_path);
	} else {
		ERR_FAIL_COND_MSG(states.size() >= 128, "WorldPartition3D permits a maximum of 128 disabled navigation links per cell.");
		states[p_link_path] = false;
	}
	if (states.is_empty()) {
		navigation_link_states.erase(p_cell);
	} else {
		navigation_link_states[p_cell] = states;
	}
	_apply_loaded_navigation_link(p_cell, p_link_path, p_enabled);
	emit_signal(SNAME("cell_navigation_link_state_changed"), p_cell, p_link_path, p_enabled);
}

void WorldPartition3D::set_navigation_link_states(const Dictionary &p_states) {
	Dictionary clean;
	const Array cells = p_states.keys();
	for (int i = 0; i < cells.size() && clean.size() < 4096; i++) {
		const Variant cell = cells[i];
		if (cell.get_type() != Variant::VECTOR2I || p_states[cell].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary entries = p_states[cell];
		Dictionary validated;
		const Array paths = entries.keys();
		for (int j = 0; j < paths.size() && validated.size() < 128; j++) {
			const Variant key = paths[j];
			if (key.get_type() != Variant::STRING || !_valid_body_path(String(key)) || String(key).length() > 256 || entries[key].get_type() != Variant::BOOL || bool(entries[key])) {
				continue;
			}
			validated[key] = false;
		}
		if (!validated.is_empty()) {
			clean[cell] = validated;
		}
	}
	const Dictionary previous = navigation_link_states.duplicate(true);
	navigation_link_states = clean;
	const Array old_cells = previous.keys();
	for (int i = 0; i < old_cells.size(); i++) {
		const Vector2i cell = old_cells[i];
		const Dictionary old_entries = previous[cell];
		const Dictionary now = clean.get(cell, Dictionary());
		const Array keys = old_entries.keys();
		for (int j = 0; j < keys.size(); j++) {
			const String path = keys[j];
			if (!now.has(path)) {
				_apply_loaded_navigation_link(cell, path, true);
				emit_signal(SNAME("cell_navigation_link_state_changed"), cell, path, true);
			}
		}
	}
	const Array new_cells = clean.keys();
	for (int i = 0; i < new_cells.size(); i++) {
		const Vector2i cell = new_cells[i];
		const Dictionary entries = clean[cell];
		const Dictionary old_entries = previous.get(cell, Dictionary());
		const Array keys = entries.keys();
		for (int j = 0; j < keys.size(); j++) {
			const String path = keys[j];
			_apply_loaded_navigation_link(cell, path, false);
			if (!old_entries.has(path)) {
				emit_signal(SNAME("cell_navigation_link_state_changed"), cell, path, false);
			}
		}
	}
}

Dictionary WorldPartition3D::get_navigation_link_states() const {
	return navigation_link_states.duplicate(true);
}

int WorldPartition3D::get_disabled_navigation_link_count() const {
	int total = 0;
	const Array cells = navigation_link_states.keys();
	for (int i = 0; i < cells.size(); i++) {
		const Dictionary cell_states = navigation_link_states[cells[i]];
		total += cell_states.size();
	}
	return total;
}

void WorldPartition3D::set_route_connection_link(const Vector2i &p_from, const Vector2i &p_to, const String &p_link_path) {
	const int64_t dx = int64_t(p_to.x) - int64_t(p_from.x);
	const int64_t dy = int64_t(p_to.y) - int64_t(p_from.y);
	const int64_t ax = dx < 0 ? -dx : dx;
	const int64_t ay = dy < 0 ? -dy : dy;
	ERR_FAIL_COND_MSG(ax + ay != 1, "WorldPartition3D route connection must join orthogonally adjacent cells.");
	ERR_FAIL_COND_MSG(!_valid_body_path(p_link_path) || p_link_path.length() > 256, "WorldPartition3D route connection requires a safe scene-relative NavigationLink3D path.");
	Dictionary from_links = route_connection_links.get(p_from, Dictionary());
	ERR_FAIL_COND_MSG(!from_links.has(p_to) && from_links.size() >= 128, "WorldPartition3D route connection registry allows at most 128 edges per source cell.");
	from_links[p_to] = p_link_path;
	route_connection_links[p_from] = from_links;
}

void WorldPartition3D::clear_route_connection_link(const Vector2i &p_from, const Vector2i &p_to) {
	if (!route_connection_links.has(p_from)) {
		return;
	}
	Dictionary from_links = route_connection_links[p_from];
	from_links.erase(p_to);
	if (from_links.is_empty()) {
		route_connection_links.erase(p_from);
	} else {
		route_connection_links[p_from] = from_links;
	}
}

String WorldPartition3D::get_route_connection_link(const Vector2i &p_from, const Vector2i &p_to) const {
	if (!route_connection_links.has(p_from)) {
		return String();
	}
	const Dictionary from_links = route_connection_links[p_from];
	return from_links.get(p_to, String());
}

bool WorldPartition3D::_is_route_connection_open(const Vector2i &p_from, const Vector2i &p_to) const {
	const String forward = get_route_connection_link(p_from, p_to);
	if (!forward.is_empty() && !is_cell_navigation_link_enabled(p_from, forward)) {
		return false;
	}
	const String reverse = get_route_connection_link(p_to, p_from);
	if (!reverse.is_empty() && !is_cell_navigation_link_enabled(p_to, reverse)) {
		return false;
	}
	return true;
}

void WorldPartition3D::_apply_cell_navigation_state(const Vector2i &p_cell, Node *p_instance) {
	if (p_instance == nullptr) {
		return;
	}
	// A coarse, cell-wide navigation switch. This does not bake meshes or
	// alter physics colliders, and does not poll nodes each streaming tick.
	const bool enabled = is_cell_navigation_enabled(p_cell);
	if (enabled) {
		// Re-enabling a gate must not wake regions of a cell that the
		// distance-based navigation tier currently keeps dormant.
		const bool *tier_active = active_navigation_cells.getptr(p_cell);
		if (tier_active != nullptr && !*tier_active) {
			return;
		}
	}
	Vector<Node *> nodes;
	nodes.push_back(p_instance);
	int visited = 0;
	while (!nodes.is_empty() && visited++ < 4096) {
		Node *node = nodes[nodes.size() - 1];
		nodes.remove_at(nodes.size() - 1);
		if (NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(node)) {
			region->set_enabled(enabled);
		}
		for (int i = 0; i < node->get_child_count(); i++) {
			nodes.push_back(node->get_child(i));
		}
	}
}

bool WorldPartition3D::is_cell_navigation_enabled(const Vector2i &p_cell) const {
	if (!navigation_cell_states.has(p_cell)) {
		return true;
	}
	return bool(navigation_cell_states[p_cell]);
}

void WorldPartition3D::set_cell_navigation_enabled(const Vector2i &p_cell, bool p_enabled) {
	if (is_cell_navigation_enabled(p_cell) == p_enabled) {
		return;
	}
	// Only disabled entries are stored; absent entries always mean enabled.
	if (p_enabled) {
		navigation_cell_states.erase(p_cell);
	} else {
		navigation_cell_states[p_cell] = false;
	}
	_apply_cell_navigation_state(p_cell, get_cell_instance(p_cell));
	emit_signal(SNAME("cell_navigation_state_changed"), p_cell, p_enabled);
}

void WorldPartition3D::set_navigation_cell_states(const Dictionary &p_states) {
	Dictionary clean;
	const Array cells = p_states.keys();
	for (int i = 0; i < cells.size(); i++) {
		const Variant cell = cells[i];
		const Variant value = p_states[cell];
		if (cell.get_type() == Variant::VECTOR2I && value.get_type() == Variant::BOOL && !bool(value)) {
			clean[cell] = false;
		}
	}
	const Dictionary previous = navigation_cell_states;
	navigation_cell_states = clean;
	// Notify only effective changes. Missing cells are enabled by default.
	const Array previous_cells = previous.keys();
	for (int i = 0; i < previous_cells.size(); i++) {
		const Vector2i cell = previous_cells[i];
		if (!clean.has(cell)) {
			_apply_cell_navigation_state(cell, get_cell_instance(cell));
			emit_signal(SNAME("cell_navigation_state_changed"), cell, true);
		}
	}
	const Array current_cells = clean.keys();
	for (int i = 0; i < current_cells.size(); i++) {
		const Vector2i cell = current_cells[i];
		_apply_cell_navigation_state(cell, get_cell_instance(cell));
		if (!previous.has(cell)) {
			emit_signal(SNAME("cell_navigation_state_changed"), cell, false);
		}
	}
}

Dictionary WorldPartition3D::get_navigation_cell_states() const {
	return navigation_cell_states.duplicate(true);
}

int WorldPartition3D::get_disabled_navigation_cell_count() const {
	return navigation_cell_states.size();
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

bool WorldPartition3D::_valid_object_state(const Dictionary &p_state) {
	// Deliberately accept only small, serializable value-only records. Do not
	// allow Node, Object, RID, Array or nested Dictionary instances in saves.
	if (p_state.size() > 32) {
		return false;
	}
	const Array keys = p_state.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		if (key.get_type() != Variant::STRING) {
			return false;
		}
		const String name = key;
		if (name.is_empty() || name.length() > 64) {
			return false;
		}
		const Variant value = p_state[key];
		switch (value.get_type()) {
			case Variant::NIL:
			case Variant::BOOL:
			case Variant::INT:
			case Variant::VECTOR2I:
			case Variant::VECTOR3I:
				break;
			case Variant::FLOAT:
				if (!Math::is_finite(double(value))) {
					return false;
				}
				break;
			case Variant::STRING:
				if (String(value).length() > 1024) {
					return false;
				}
				break;
			case Variant::VECTOR2: {
				const Vector2 vec = value;
				if (!vec.is_finite()) {
					return false;
				}
			} break;
			case Variant::VECTOR3: {
				const Vector3 vec = value;
				if (!vec.is_finite()) {
					return false;
				}
			} break;
			default:
				return false;
		}
	}
	return true;
}

void WorldPartition3D::_capture_cell_object_states(const Vector2i &p_cell, Node *p_instance) {
	if (!persist_streaming_objects || p_instance == nullptr) {
		return;
	}
	Dictionary captured;
	Vector<Node *> stack;
	stack.push_back(p_instance);
	int visited = 0;
	while (!stack.is_empty() && visited++ < 4096 && captured.size() < 128) {
		Node *node = stack[stack.size() - 1];
		stack.remove_at(stack.size() - 1);
		if (node != p_instance && node->is_in_group(SNAME("streaming_stateful")) && node->has_method(SNAME("capture_streaming_object_state"))) {
			const Variant result = node->call(SNAME("capture_streaming_object_state"));
			if (result.get_type() == Variant::DICTIONARY) {
				const Dictionary state = result;
				const String path = String(p_instance->get_path_to(node));
				if (!state.is_empty() && _valid_body_path(path) && _valid_object_state(state)) {
					captured[path] = state.duplicate(true);
				}
			}
		}
		for (int i = 0; i < node->get_child_count(); i++) {
			stack.push_back(node->get_child(i));
		}
	}
	const Dictionary previous = get_cell_object_states(p_cell);
	if (captured.is_empty()) {
		saved_cell_object_states.erase(p_cell);
	} else {
		saved_cell_object_states.insert(p_cell, captured);
	}
	const Dictionary latest = get_cell_object_states(p_cell);
	if (previous != latest) {
		emit_signal(SNAME("cell_object_state_changed"), p_cell, latest);
	}
}

void WorldPartition3D::_restore_cell_object_states(const Vector2i &p_cell, Node *p_instance, bool p_reset_missing) {
	if (!persist_streaming_objects || p_instance == nullptr) {
		return;
	}
	const Dictionary *saved = saved_cell_object_states.getptr(p_cell);
	Vector<Node *> stack;
	stack.push_back(p_instance);
	int visited = 0;
	while (!stack.is_empty() && visited++ < 4096) {
		Node *node = stack[stack.size() - 1];
		stack.remove_at(stack.size() - 1);
		if (node != p_instance && node->is_in_group(SNAME("streaming_stateful")) && node->has_method(SNAME("restore_streaming_object_state"))) {
			const String path = String(p_instance->get_path_to(node));
			if (_valid_body_path(path) && saved != nullptr && saved->has(path)) {
				const Variant value = (*saved)[path];
				if (value.get_type() == Variant::DICTIONARY) {
					const Dictionary record = value;
					if (_valid_object_state(record)) {
						node->call(SNAME("restore_streaming_object_state"), record.duplicate(true));
					}
				}
			} else if (p_reset_missing) {
				node->call(SNAME("restore_streaming_object_state"), Dictionary());
			}
		}
		for (int i = 0; i < node->get_child_count(); i++) {
			stack.push_back(node->get_child(i));
		}
	}
}

void WorldPartition3D::set_persist_streaming_objects(bool p_enabled) {
	persist_streaming_objects = p_enabled;
}

bool WorldPartition3D::is_persisting_streaming_objects() const {
	return persist_streaming_objects;
}

Dictionary WorldPartition3D::get_cell_object_states(const Vector2i &p_cell) const {
	const Dictionary *state = saved_cell_object_states.getptr(p_cell);
	return state != nullptr ? state->duplicate(true) : Dictionary();
}

Dictionary WorldPartition3D::capture_cell_object_states(const Vector2i &p_cell) {
	_capture_cell_object_states(p_cell, get_cell_instance(p_cell));
	return get_cell_object_states(p_cell);
}

Dictionary WorldPartition3D::snapshot_cell_object_states() {
	// Explicit snapshot captures still-loaded interactive objects.
	if (persist_streaming_objects) {
		for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
			Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
			_capture_cell_object_states(E.key, instance);
		}
	}
	Dictionary result;
	for (const KeyValue<Vector2i, Dictionary> &E : saved_cell_object_states) {
		result[E.key] = E.value.duplicate(true);
	}
	return result;
}

void WorldPartition3D::load_cell_object_states(const Dictionary &p_states) {
	HashMap<Vector2i, Dictionary> accepted;
	const Array cells = p_states.keys();
	for (int i = 0; i < cells.size(); i++) {
		const Variant cell = cells[i];
		if (cell.get_type() != Variant::VECTOR2I || p_states[cell].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary source = p_states[cell];
		Dictionary safe;
		const Array names = source.keys();
		for (int j = 0; j < names.size() && safe.size() < 128; j++) {
			const Variant path = names[j];
			if (path.get_type() != Variant::STRING || !_valid_body_path(String(path)) || source[path].get_type() != Variant::DICTIONARY) {
				continue;
			}
			const Dictionary record = source[path];
			if (!record.is_empty() && _valid_object_state(record)) {
				safe[path] = record.duplicate(true);
			}
		}
		if (!safe.is_empty()) {
			accepted.insert(cell, safe);
		}
	}
	saved_cell_object_states = accepted;
	if (persist_streaming_objects) {
		// Missing saved records actively reset loaded objects to their defaults,
		// avoiding previous-session state leaking into a fresh checkpoint.
		for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
			Node *instance = Object::cast_to<Node>(ObjectDB::get_instance(E.value));
			_restore_cell_object_states(E.key, instance, true);
		}
	}
}

void WorldPartition3D::clear_cell_object_states() {
	saved_cell_object_states.clear();
}

int WorldPartition3D::get_cell_object_state_count() const {
	return saved_cell_object_states.size();
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

bool WorldPartition3D::set_streaming_source(const String &p_name, const Vector3 &p_global_position, int p_radius, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_name.is_empty() || p_name.length() > 64, false, "WorldPartition3D source name must contain 1 to 64 characters.");
	ERR_FAIL_COND_V_MSG(!p_global_position.is_finite(), false, "WorldPartition3D source position must be finite.");
	ERR_FAIL_COND_V_MSG(p_radius < 0 || p_radius > 1, false, "WorldPartition3D source radius must be 0 or 1 cell.");
	ERR_FAIL_COND_V_MSG(p_priority < 0 || p_priority > 3, false, "WorldPartition3D source priority must be between 0 and 3.");
	ERR_FAIL_COND_V_MSG(!streaming_sources.has(p_name) && streaming_sources.size() >= MAX_STREAMING_SOURCES, false, "WorldPartition3D supports at most 8 additional sources.");
	StreamingSource source;
	source.global_position = p_global_position;
	source.radius = p_radius;
	source.priority = p_priority;
	streaming_sources.insert(p_name, source);
	return true;
}

bool WorldPartition3D::set_streaming_source_priority(const String &p_name, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_priority < 0 || p_priority > 3, false, "WorldPartition3D source priority must be between 0 and 3.");
	StreamingSource *source = streaming_sources.getptr(p_name);
	if (source == nullptr) {
		return false;
	}
	source->priority = p_priority;
	return true;
}

int WorldPartition3D::get_streaming_source_priority(const String &p_name) const {
	const StreamingSource *source = streaming_sources.getptr(p_name);
	return source != nullptr ? source->priority : -1;
}

void WorldPartition3D::remove_streaming_source(const String &p_name) {
	streaming_sources.erase(p_name);
}

void WorldPartition3D::clear_streaming_sources() {
	streaming_sources.clear();
}

bool WorldPartition3D::has_streaming_source(const String &p_name) const {
	return streaming_sources.has(p_name);
}

int WorldPartition3D::get_streaming_source_count() const {
	return streaming_sources.size();
}

Vector2i WorldPartition3D::get_streaming_source_cell(const String &p_name) const {
	const StreamingSource *source = streaming_sources.getptr(p_name);
	return source != nullptr ? local_position_to_cell(to_local(source->global_position)) : Vector2i();
}

int WorldPartition3D::_count_source_cells(const String &p_name, int p_kind) const {
	const StreamingSource *source = streaming_sources.getptr(p_name);
	if (source == nullptr) {
		return 0;
	}
	const Vector2i center = local_position_to_cell(to_local(source->global_position));
	// A source whose destination cell is unregistered cannot be ready, even
	// when some neighbors have valid scenes. Fail closed for safe fast travel.
	if (_get_scene_path(center).is_empty()) {
		return 0;
	}
	int count = 0;
	for (int dz = -source->radius; dz <= source->radius; dz++) {
		for (int dx = -source->radius; dx <= source->radius; dx++) {
			const Vector2i cell = center + Vector2i(dx, dz);
			if (_get_scene_path(cell).is_empty()) {
				continue; // Sparse worlds do not require missing neighbors.
			}
			if (p_kind == 0 || (p_kind == 1 && get_cell_instance(cell) != nullptr) || (p_kind == 2 && failed_cells.has(cell))) {
				count++;
			}
		}
	}
	return count;
}

int WorldPartition3D::get_streaming_source_cell_count(const String &p_name) const {
	return _count_source_cells(p_name, 0);
}

int WorldPartition3D::get_streaming_source_loaded_cell_count(const String &p_name) const {
	return _count_source_cells(p_name, 1);
}

int WorldPartition3D::get_streaming_source_failed_cell_count(const String &p_name) const {
	return _count_source_cells(p_name, 2);
}

real_t WorldPartition3D::get_streaming_source_progress(const String &p_name) const {
	const int total = get_streaming_source_cell_count(p_name);
	if (total == 0) {
		return 0.0;
	}
	return real_t(get_streaming_source_loaded_cell_count(p_name)) / real_t(total);
}

bool WorldPartition3D::is_streaming_source_ready(const String &p_name) const {
	// Merely registering a source is not sufficient. The node must be actively
	// streaming, with a resolved observer and a registered destination.
	if (!streaming_enabled || !is_inside_tree() || observer_path.is_empty() || Object::cast_to<Node3D>(get_node_or_null(observer_path)) == nullptr) {
		return false;
	}
	const int total = get_streaming_source_cell_count(p_name);
	return total > 0 && get_streaming_source_failed_cell_count(p_name) == 0 && get_streaming_source_loaded_cell_count(p_name) == total;
}

int WorldPartition3D::get_streaming_source_activated_cell_count(const String &p_name) const {
	const StreamingSource *source = streaming_sources.getptr(p_name);
	if (source == nullptr) {
		return 0;
	}
	const Vector2i center = local_position_to_cell(to_local(source->global_position));
	if (_get_scene_path(center).is_empty()) {
		return 0;
	}
	int count = 0;
	for (int dz = -source->radius; dz <= source->radius; dz++) {
		for (int dx = -source->radius; dx <= source->radius; dx++) {
			const Vector2i cell = center + Vector2i(dx, dz);
			if (!_get_scene_path(cell).is_empty() && is_cell_activation_ready(cell)) {
				count++;
			}
		}
	}
	return count;
}

real_t WorldPartition3D::get_streaming_source_activation_progress(const String &p_name) const {
	const int total = get_streaming_source_cell_count(p_name);
	return total > 0 ? real_t(get_streaming_source_activated_cell_count(p_name)) / real_t(total) : 0.0;
}

bool WorldPartition3D::is_streaming_source_activation_ready(const String &p_name) const {
	// Scene-root readiness is a prerequisite, but not enough for physics-aware
	// gameplay activation. This API is a bounded physics-tick and script fence,
	// NOT a guarantee of collision, navmesh or GPU residency.
	if (!is_streaming_source_ready(p_name)) {
		return false;
	}
	return get_streaming_source_activated_cell_count(p_name) == get_streaming_source_cell_count(p_name);
}

bool WorldPartition3D::_is_cell_required_by_source(const Vector2i &p_cell, int p_extra_radius) const {
	for (const KeyValue<String, StreamingSource> &E : streaming_sources) {
		const Vector2i center = local_position_to_cell(to_local(E.value.global_position));
		if (_within_radius(p_cell, center, E.value.radius + p_extra_radius)) {
			return true;
		}
	}
	return false;
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

void WorldPartition3D::_request_cell(const Vector2i &p_cell, int &r_new_requests, int &r_instances) {
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

void WorldPartition3D::update_streaming() {
	_poll_requests();
	if (!streaming_enabled || !is_inside_tree()) {
		predicted_cell_valid = false;
		_purge_unused_ready_scenes();
		_refresh_processing();
		return;
	}

	Node3D *observer = observer_path.is_empty() ? nullptr : Object::cast_to<Node3D>(get_node_or_null(observer_path));
	const bool has_claims = !pinned_cells.is_empty() || !cell_leases.is_empty();
	if (observer == nullptr && !has_claims && !unload_after_claim_released && !layer_update_needed) {
		// Preserve cells if the observer disappears temporarily without an
		// explicit pin/lease release (e.g., a brief scene-tree reparenting).
		predicted_cell_valid = false;
		_purge_unused_ready_scenes();
		if (observer_path.is_empty()) {
			_refresh_processing();
		}
		return;
	}

	Vector2i center;
	bool observer_cell_changed = false;
	predicted_cell_valid = false;
	if (observer != nullptr) {
		center = local_position_to_cell(to_local(observer->get_global_position()));
		observer_cell_changed = !observer_cell_valid || observer_cell != center;
		observer_cell = center;
		observer_cell_valid = true;
		// With a valid observer, ordinary distance-based eviction runs normally.
		unload_after_claim_released = false;

		// Predict a single future cell after the observer's normal demand radius.
		// Feed velocity via set_predictive_velocity() in world space. The built-in
		// distance and time bounds avoid unbounded speculative memory growth.
		if (predictive_lookahead_seconds > 0.0 && predictive_max_distance > 0.0 && predictive_velocity.length_squared() > 0.01) {
			Vector3 offset = predictive_velocity * predictive_lookahead_seconds;
			const real_t distance = offset.length();
			if (Math::is_finite(distance) && distance > 0.0) {
				if (distance > predictive_max_distance) {
					offset *= predictive_max_distance / distance;
				}
				const Vector3 predicted_global = observer->get_global_position() + offset;
				if (predicted_global.is_finite()) {
					predicted_cell = local_position_to_cell(to_local(predicted_global));
					predicted_cell_valid = predicted_cell != center;
				}
			}
		}
	}

	// Without an observer, distance eviction only runs while a pin/lease exists
	// or was just released; a layer deactivation always removes its own cells.
	const bool distance_eviction = observer != nullptr || has_claims || unload_after_claim_released;
	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		bool evict = ObjectDB::get_instance(E.value) == nullptr || !_is_cell_layer_enabled(E.key);
		if (!evict && distance_eviction && !_has_residency_claim(E.key) && !_is_cell_required_by_source(E.key, 1)) {
			evict = observer == nullptr || (!(predicted_cell_valid && E.key == predicted_cell) && !_within_radius(E.key, center, unload_radius));
		}
		if (evict) {
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
		bool drop = !_is_cell_layer_enabled(E.key);
		if (!drop && distance_eviction && !_has_residency_claim(E.key) && !_is_cell_required_by_source(E.key, 0)) {
			drop = observer == nullptr || (!(predicted_cell_valid && E.key == predicted_cell) && !_within_radius(E.key, center, load_radius));
		}
		if (drop) {
			cancel.push_back(E.key);
		}
	}
	for (const Vector2i &cell : cancel) {
		pending_cells.erase(cell);
	}

	int new_requests = max_new_requests_per_frame;
	int instances = max_instances_per_frame;
	// Explicit gameplay claims come first: pinned hubs (in pin order), then
	// lease-held cells. They work without an observer and share the global
	// request/instance budgets with everything below.
	for (const Vector2i &cell : pinned_cells) {
		_request_cell(cell, new_requests, instances);
	}
	for (const KeyValue<Vector2i, int> &E : cell_lease_counts) {
		if (!pinned_cells.has(E.key)) {
			_request_cell(E.key, new_requests, instances);
		}
	}
	if (observer != nullptr) {
		// Visit nearer cells first and produce a deterministic order.
		for (int radius = 0; radius <= load_radius; radius++) {
			for (int dz = -radius; dz <= radius; dz++) {
				for (int dx = -radius; dx <= radius; dx++) {
					if (MAX(Math::abs(dx), Math::abs(dz)) != radius) {
						continue;
					}
					const Vector2i cell = center + Vector2i(dx, dz);
					_request_cell(cell, new_requests, instances);
				}
			}
		}
		// Registered source priorities (3 urgent .. 0 background) are evaluated
		// only after observer and claimed cells. The budget is shared across all
		// sources. Stable name ordering within each tier avoids HashMap iteration
		// nondeterminism. Within a tier the nearest ring of EVERY source is
		// visited before any farther ring, so a source with a large radius cannot
		// starve the center cell of another source under a small request budget.
		Vector<String> source_names;
		for (const KeyValue<String, StreamingSource> &E : streaming_sources) {
			source_names.push_back(E.key);
		}
		source_names.sort();
		for (int priority = 3; priority >= 0; priority--) {
			int max_radius = -1;
			for (const String &name : source_names) {
				const StreamingSource *source = streaming_sources.getptr(name);
				if (source != nullptr && source->priority == priority) {
					max_radius = MAX(max_radius, source->radius);
				}
			}
			for (int radius = 0; radius <= max_radius; radius++) {
				for (const String &name : source_names) {
					const StreamingSource *source = streaming_sources.getptr(name);
					if (source == nullptr || source->priority != priority || source->radius < radius) {
						continue;
					}
					const Vector2i source_center = local_position_to_cell(to_local(source->global_position));
					for (int dz = -radius; dz <= radius; dz++) {
						for (int dx = -radius; dx <= radius; dx++) {
							if (MAX(Math::abs(dx), Math::abs(dz)) == radius) {
								_request_cell(source_center + Vector2i(dx, dz), new_requests, instances);
							}
						}
					}
				}
			}
		}
		// Lowest priority: one forecast cell, after visible, claimed and quest cells.
		if (predicted_cell_valid && !_within_radius(predicted_cell, center, load_radius)) {
			_request_cell(predicted_cell, new_requests, instances);
		}
		_refresh_cell_detail(center);
		_refresh_cell_simulation(center);
		_refresh_cell_physics(center);
		_refresh_cell_navigation(center);
		_refresh_dirty_navigation_cells(center);
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
	if (observer == nullptr && !has_claims && active_cells.is_empty() && pending_cells.is_empty()) {
		unload_after_claim_released = false;
	}
	if (observer_cell_changed) {
		emit_signal(SNAME("observer_cell_changed"), observer_cell);
	}
}

void WorldPartition3D::set_min_physics_frames_after_load(int p_frames) {
	ERR_FAIL_COND_MSG(p_frames < 0 || p_frames > 8, "WorldPartition3D min_physics_frames_after_load must be between 0 and 8.");
	min_physics_frames_after_load = p_frames;
}

int WorldPartition3D::get_min_physics_frames_after_load() const {
	return min_physics_frames_after_load;
}

bool WorldPartition3D::is_cell_activation_ready(const Vector2i &p_cell) const {
	Node3D *scene_root = get_cell_instance(p_cell);
	const uint64_t *created_on_frame = cell_creation_physics_frames.getptr(p_cell);
	if (scene_root == nullptr || created_on_frame == nullptr) {
		return false;
	}
	const uint64_t current_frame = Engine::get_singleton()->get_physics_frames();
	if (current_frame < *created_on_frame || current_frame - *created_on_frame < uint64_t(min_physics_frames_after_load)) {
		return false;
	}
	// An opt-in scene can gate readiness on its terrain, collision setup,
	// navmesh availability or gameplay state. Invalid return values fail closed.
	if (scene_root->has_method(SNAME("is_streaming_activation_ready"))) {
		const Variant result = scene_root->call(SNAME("is_streaming_activation_ready"));
		return result.get_type() == Variant::BOOL && bool(result);
	}
	return true;
}

bool WorldPartition3D::is_cell_loaded(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	return id != nullptr && ObjectDB::get_instance(*id) != nullptr;
}

Node3D *WorldPartition3D::get_cell_instance(const Vector2i &p_cell) const {
	const ObjectID *id = active_cells.getptr(p_cell);
	if (id == nullptr) {
		return nullptr;
	}
	// Never expose stale node pointers after an external free or stream unload.
	Node3D *instance = Object::cast_to<Node3D>(ObjectDB::get_instance(*id));
	return instance != nullptr && !instance->is_queued_for_deletion() ? instance : nullptr;
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
	// Explicit retry keeps registrations and already instantiated cells.
	failed_cells.clear();
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
	ClassDB::bind_method(D_METHOD("set_detail_radius", "radius"), &WorldPartition3D::set_detail_radius);
	ClassDB::bind_method(D_METHOD("get_detail_radius"), &WorldPartition3D::get_detail_radius);
	ClassDB::bind_method(D_METHOD("set_detail_hysteresis_cells", "cells"), &WorldPartition3D::set_detail_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("get_detail_hysteresis_cells"), &WorldPartition3D::get_detail_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("set_max_detail_transitions_per_frame", "count"), &WorldPartition3D::set_max_detail_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_detail_transitions_per_frame"), &WorldPartition3D::get_max_detail_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("get_cell_detail_level", "cell"), &WorldPartition3D::get_cell_detail_level);
	ClassDB::bind_method(D_METHOD("get_distant_cell_count"), &WorldPartition3D::get_distant_cell_count);
	ClassDB::bind_method(D_METHOD("set_simulation_radius", "radius"), &WorldPartition3D::set_simulation_radius);
	ClassDB::bind_method(D_METHOD("get_simulation_radius"), &WorldPartition3D::get_simulation_radius);
	ClassDB::bind_method(D_METHOD("set_simulation_hysteresis_cells", "cells"), &WorldPartition3D::set_simulation_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("get_simulation_hysteresis_cells"), &WorldPartition3D::get_simulation_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("set_max_simulation_transitions_per_frame", "count"), &WorldPartition3D::set_max_simulation_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_simulation_transitions_per_frame"), &WorldPartition3D::get_max_simulation_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("is_cell_simulation_active", "cell"), &WorldPartition3D::is_cell_simulation_active);
	ClassDB::bind_method(D_METHOD("get_simulation_active_cell_count"), &WorldPartition3D::get_simulation_active_cell_count);
	ClassDB::bind_method(D_METHOD("set_physics_radius", "radius"), &WorldPartition3D::set_physics_radius);
	ClassDB::bind_method(D_METHOD("get_physics_radius"), &WorldPartition3D::get_physics_radius);
	ClassDB::bind_method(D_METHOD("set_physics_hysteresis_cells", "cells"), &WorldPartition3D::set_physics_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("get_physics_hysteresis_cells"), &WorldPartition3D::get_physics_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("set_max_physics_transitions_per_frame", "count"), &WorldPartition3D::set_max_physics_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_physics_transitions_per_frame"), &WorldPartition3D::get_max_physics_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("is_cell_physics_active", "cell"), &WorldPartition3D::is_cell_physics_active);
	ClassDB::bind_method(D_METHOD("get_physics_active_cell_count"), &WorldPartition3D::get_physics_active_cell_count);
	ClassDB::bind_method(D_METHOD("is_cell_physics_ready", "cell"), &WorldPartition3D::is_cell_physics_ready);
	ClassDB::bind_method(D_METHOD("is_streaming_source_physics_ready", "name"), &WorldPartition3D::is_streaming_source_physics_ready);
	ClassDB::bind_method(D_METHOD("set_navigation_radius", "radius"), &WorldPartition3D::set_navigation_radius);
	ClassDB::bind_method(D_METHOD("get_navigation_radius"), &WorldPartition3D::get_navigation_radius);
	ClassDB::bind_method(D_METHOD("set_navigation_hysteresis_cells", "cells"), &WorldPartition3D::set_navigation_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("get_navigation_hysteresis_cells"), &WorldPartition3D::get_navigation_hysteresis_cells);
	ClassDB::bind_method(D_METHOD("set_max_navigation_transitions_per_frame", "count"), &WorldPartition3D::set_max_navigation_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_navigation_transitions_per_frame"), &WorldPartition3D::get_max_navigation_transitions_per_frame);
	ClassDB::bind_method(D_METHOD("is_cell_navigation_active", "cell"), &WorldPartition3D::is_cell_navigation_active);
	ClassDB::bind_method(D_METHOD("get_navigation_active_cell_count"), &WorldPartition3D::get_navigation_active_cell_count);
	ClassDB::bind_method(D_METHOD("is_cell_navigation_ready", "cell"), &WorldPartition3D::is_cell_navigation_ready);
	ClassDB::bind_method(D_METHOD("is_streaming_source_navigation_ready", "name"), &WorldPartition3D::is_streaming_source_navigation_ready);
	ClassDB::bind_method(D_METHOD("set_max_navigation_rebuilds_per_physics_frame", "count"), &WorldPartition3D::set_max_navigation_rebuilds_per_physics_frame);
	ClassDB::bind_method(D_METHOD("get_max_navigation_rebuilds_per_physics_frame"), &WorldPartition3D::get_max_navigation_rebuilds_per_physics_frame);
	ClassDB::bind_method(D_METHOD("mark_cell_navigation_dirty", "cell"), &WorldPartition3D::mark_cell_navigation_dirty);
	ClassDB::bind_method(D_METHOD("get_navigation_dirty_cell_count"), &WorldPartition3D::get_navigation_dirty_cell_count);
	ClassDB::bind_method(D_METHOD("get_cell_navigation_revision", "cell"), &WorldPartition3D::get_cell_navigation_revision);
	ClassDB::bind_method(D_METHOD("get_navigation_mesh_generation"), &WorldPartition3D::get_navigation_mesh_generation);
	ClassDB::bind_method(D_METHOD("set_max_navigation_updates_per_physics_frame", "count"), &WorldPartition3D::set_max_navigation_updates_per_physics_frame);
	ClassDB::bind_method(D_METHOD("get_max_navigation_updates_per_physics_frame"), &WorldPartition3D::get_max_navigation_updates_per_physics_frame);
	ClassDB::bind_method(D_METHOD("register_navigation_agent", "name", "agent", "priority"), &WorldPartition3D::register_navigation_agent, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("unregister_navigation_agent", "name"), &WorldPartition3D::unregister_navigation_agent);
	ClassDB::bind_method(D_METHOD("unregister_navigation_agent_if_owner", "name", "agent"), &WorldPartition3D::unregister_navigation_agent_if_owner);
	ClassDB::bind_method(D_METHOD("has_navigation_agent", "name"), &WorldPartition3D::has_navigation_agent);
	ClassDB::bind_method(D_METHOD("get_navigation_agent_count"), &WorldPartition3D::get_navigation_agent_count);
	ClassDB::bind_method(D_METHOD("set_navigation_agent_priority", "name", "priority"), &WorldPartition3D::set_navigation_agent_priority);
	ClassDB::bind_method(D_METHOD("get_navigation_agent_priority", "name"), &WorldPartition3D::get_navigation_agent_priority);
	ClassDB::bind_method(D_METHOD("try_acquire_navigation_update", "name"), &WorldPartition3D::try_acquire_navigation_update);
	ClassDB::bind_method(D_METHOD("get_navigation_updates_used_this_frame"), &WorldPartition3D::get_navigation_updates_used_this_frame);
	ClassDB::bind_method(D_METHOD("set_observer_path", "path"), &WorldPartition3D::set_observer_path);
	ClassDB::bind_method(D_METHOD("get_observer_path"), &WorldPartition3D::get_observer_path);
	ClassDB::bind_method(D_METHOD("set_predictive_velocity", "velocity"), &WorldPartition3D::set_predictive_velocity);
	ClassDB::bind_method(D_METHOD("get_predictive_velocity"), &WorldPartition3D::get_predictive_velocity);
	ClassDB::bind_method(D_METHOD("set_predictive_lookahead_seconds", "seconds"), &WorldPartition3D::set_predictive_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("get_predictive_lookahead_seconds"), &WorldPartition3D::get_predictive_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("set_predictive_max_distance", "distance"), &WorldPartition3D::set_predictive_max_distance);
	ClassDB::bind_method(D_METHOD("get_predictive_max_distance"), &WorldPartition3D::get_predictive_max_distance);
	ClassDB::bind_method(D_METHOD("has_predicted_cell"), &WorldPartition3D::has_predicted_cell);
	ClassDB::bind_method(D_METHOD("get_predicted_cell"), &WorldPartition3D::get_predicted_cell);
	ClassDB::bind_method(D_METHOD("has_observer_cell"), &WorldPartition3D::has_observer_cell);
	ClassDB::bind_method(D_METHOD("get_observer_cell"), &WorldPartition3D::get_observer_cell);
	ClassDB::bind_method(D_METHOD("set_cell_scenes", "scenes"), &WorldPartition3D::set_cell_scenes);
	ClassDB::bind_method(D_METHOD("get_cell_scenes"), &WorldPartition3D::get_cell_scenes);
	ClassDB::bind_method(D_METHOD("set_cell_scene", "cell", "scene_path"), &WorldPartition3D::set_cell_scene);
	ClassDB::bind_method(D_METHOD("get_cell_scene", "cell"), &WorldPartition3D::get_cell_scene);
	ClassDB::bind_method(D_METHOD("remove_cell_scene", "cell"), &WorldPartition3D::remove_cell_scene);
	ClassDB::bind_method(D_METHOD("clear_cell_scenes"), &WorldPartition3D::clear_cell_scenes);
	ClassDB::bind_method(D_METHOD("get_configured_cell_count"), &WorldPartition3D::get_configured_cell_count);
	ClassDB::bind_method(D_METHOD("find_cell_path", "from", "to", "loaded_only"), &WorldPartition3D::find_cell_path, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("set_max_cell_path_cache_entries", "count"), &WorldPartition3D::set_max_cell_path_cache_entries);
	ClassDB::bind_method(D_METHOD("get_max_cell_path_cache_entries"), &WorldPartition3D::get_max_cell_path_cache_entries);
	ClassDB::bind_method(D_METHOD("get_cell_path_cache_entry_count"), &WorldPartition3D::get_cell_path_cache_entry_count);
	ClassDB::bind_method(D_METHOD("get_cell_path_cache_hit_count"), &WorldPartition3D::get_cell_path_cache_hit_count);
	ClassDB::bind_method(D_METHOD("get_cell_path_cache_miss_count"), &WorldPartition3D::get_cell_path_cache_miss_count);
	ClassDB::bind_method(D_METHOD("clear_cell_path_cache"), &WorldPartition3D::clear_cell_path_cache);
	ClassDB::bind_method(D_METHOD("build_navigation_tile", "vertices", "resolution", "blockers", "agent_radius", "max_slope_degrees"), &WorldPartition3D::build_navigation_tile, DEFVAL(0.45), DEFVAL(45.0));
	ClassDB::bind_method(D_METHOD("patch_navigation_tile", "previous", "resolution", "previous_blockers", "blockers", "agent_radius", "max_slope_degrees"), &WorldPartition3D::patch_navigation_tile, DEFVAL(0.45), DEFVAL(45.0));
	ClassDB::bind_method(D_METHOD("get_last_navigation_tile_retested_triangle_count"), &WorldPartition3D::get_last_navigation_tile_retested_triangle_count);
	ClassDB::bind_method(D_METHOD("pin_cell", "cell"), &WorldPartition3D::pin_cell);
	ClassDB::bind_method(D_METHOD("unpin_cell", "cell"), &WorldPartition3D::unpin_cell);
	ClassDB::bind_method(D_METHOD("is_cell_pinned", "cell"), &WorldPartition3D::is_cell_pinned);
	ClassDB::bind_method(D_METHOD("get_pinned_cells"), &WorldPartition3D::get_pinned_cells);
	ClassDB::bind_method(D_METHOD("set_pinned_cells", "cells"), &WorldPartition3D::set_pinned_cells);
	ClassDB::bind_method(D_METHOD("clear_pinned_cells"), &WorldPartition3D::clear_pinned_cells);
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
	ClassDB::bind_method(D_METHOD("set_cell_navigation_enabled", "cell", "enabled"), &WorldPartition3D::set_cell_navigation_enabled);
	ClassDB::bind_method(D_METHOD("is_cell_navigation_enabled", "cell"), &WorldPartition3D::is_cell_navigation_enabled);
	ClassDB::bind_method(D_METHOD("set_navigation_cell_states", "states"), &WorldPartition3D::set_navigation_cell_states);
	ClassDB::bind_method(D_METHOD("get_navigation_cell_states"), &WorldPartition3D::get_navigation_cell_states);
	ClassDB::bind_method(D_METHOD("get_disabled_navigation_cell_count"), &WorldPartition3D::get_disabled_navigation_cell_count);
	ClassDB::bind_method(D_METHOD("set_cell_navigation_link_enabled", "cell", "link_path", "enabled"), &WorldPartition3D::set_cell_navigation_link_enabled);
	ClassDB::bind_method(D_METHOD("is_cell_navigation_link_enabled", "cell", "link_path"), &WorldPartition3D::is_cell_navigation_link_enabled);
	ClassDB::bind_method(D_METHOD("set_navigation_link_states", "states"), &WorldPartition3D::set_navigation_link_states);
	ClassDB::bind_method(D_METHOD("get_navigation_link_states"), &WorldPartition3D::get_navigation_link_states);
	ClassDB::bind_method(D_METHOD("get_disabled_navigation_link_count"), &WorldPartition3D::get_disabled_navigation_link_count);
	ClassDB::bind_method(D_METHOD("set_route_connection_link", "from_cell", "to_cell", "link_path"), &WorldPartition3D::set_route_connection_link);
	ClassDB::bind_method(D_METHOD("clear_route_connection_link", "from_cell", "to_cell"), &WorldPartition3D::clear_route_connection_link);
	ClassDB::bind_method(D_METHOD("get_route_connection_link", "from_cell", "to_cell"), &WorldPartition3D::get_route_connection_link);
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
	ClassDB::bind_method(D_METHOD("set_persist_streaming_objects", "enabled"), &WorldPartition3D::set_persist_streaming_objects);
	ClassDB::bind_method(D_METHOD("is_persisting_streaming_objects"), &WorldPartition3D::is_persisting_streaming_objects);
	ClassDB::bind_method(D_METHOD("get_cell_object_states", "cell"), &WorldPartition3D::get_cell_object_states);
	ClassDB::bind_method(D_METHOD("capture_cell_object_states", "cell"), &WorldPartition3D::capture_cell_object_states);
	ClassDB::bind_method(D_METHOD("snapshot_cell_object_states"), &WorldPartition3D::snapshot_cell_object_states);
	ClassDB::bind_method(D_METHOD("load_cell_object_states", "states"), &WorldPartition3D::load_cell_object_states);
	ClassDB::bind_method(D_METHOD("clear_cell_object_states"), &WorldPartition3D::clear_cell_object_states);
	ClassDB::bind_method(D_METHOD("get_cell_object_state_count"), &WorldPartition3D::get_cell_object_state_count);
	ClassDB::bind_method(D_METHOD("get_cell_simulation_stats", "cell"), &WorldPartition3D::get_cell_simulation_stats);
	ClassDB::bind_method(D_METHOD("retry_failed_cells"), &WorldPartition3D::retry_failed_cells);
	ClassDB::bind_method(D_METHOD("get_pinned_cell_count"), &WorldPartition3D::get_pinned_cell_count);
	ClassDB::bind_method(D_METHOD("set_streaming_source", "name", "global_position", "radius", "priority"), &WorldPartition3D::set_streaming_source, DEFVAL(0), DEFVAL(1));
	ClassDB::bind_method(D_METHOD("set_streaming_source_priority", "name", "priority"), &WorldPartition3D::set_streaming_source_priority);
	ClassDB::bind_method(D_METHOD("get_streaming_source_priority", "name"), &WorldPartition3D::get_streaming_source_priority);
	ClassDB::bind_method(D_METHOD("remove_streaming_source", "name"), &WorldPartition3D::remove_streaming_source);
	ClassDB::bind_method(D_METHOD("clear_streaming_sources"), &WorldPartition3D::clear_streaming_sources);
	ClassDB::bind_method(D_METHOD("has_streaming_source", "name"), &WorldPartition3D::has_streaming_source);
	ClassDB::bind_method(D_METHOD("get_streaming_source_count"), &WorldPartition3D::get_streaming_source_count);
	ClassDB::bind_method(D_METHOD("get_streaming_source_cell", "name"), &WorldPartition3D::get_streaming_source_cell);
	ClassDB::bind_method(D_METHOD("get_streaming_source_cell_count", "name"), &WorldPartition3D::get_streaming_source_cell_count);
	ClassDB::bind_method(D_METHOD("get_streaming_source_loaded_cell_count", "name"), &WorldPartition3D::get_streaming_source_loaded_cell_count);
	ClassDB::bind_method(D_METHOD("get_streaming_source_failed_cell_count", "name"), &WorldPartition3D::get_streaming_source_failed_cell_count);
	ClassDB::bind_method(D_METHOD("get_streaming_source_progress", "name"), &WorldPartition3D::get_streaming_source_progress);
	ClassDB::bind_method(D_METHOD("is_streaming_source_ready", "name"), &WorldPartition3D::is_streaming_source_ready);
	ClassDB::bind_method(D_METHOD("get_streaming_source_activated_cell_count", "name"), &WorldPartition3D::get_streaming_source_activated_cell_count);
	ClassDB::bind_method(D_METHOD("get_streaming_source_activation_progress", "name"), &WorldPartition3D::get_streaming_source_activation_progress);
	ClassDB::bind_method(D_METHOD("is_streaming_source_activation_ready", "name"), &WorldPartition3D::is_streaming_source_activation_ready);
	ClassDB::bind_method(D_METHOD("local_position_to_cell", "local_position"), &WorldPartition3D::local_position_to_cell);
	ClassDB::bind_method(D_METHOD("cell_to_local_position", "cell"), &WorldPartition3D::cell_to_local_position);
	ClassDB::bind_method(D_METHOD("get_cells_in_radius", "center", "radius"), &WorldPartition3D::get_cells_in_radius);
	ClassDB::bind_method(D_METHOD("update_streaming"), &WorldPartition3D::update_streaming);
	ClassDB::bind_method(D_METHOD("set_min_physics_frames_after_load", "frames"), &WorldPartition3D::set_min_physics_frames_after_load);
	ClassDB::bind_method(D_METHOD("get_min_physics_frames_after_load"), &WorldPartition3D::get_min_physics_frames_after_load);
	ClassDB::bind_method(D_METHOD("is_cell_activation_ready", "cell"), &WorldPartition3D::is_cell_activation_ready);
	ClassDB::bind_method(D_METHOD("is_cell_loaded", "cell"), &WorldPartition3D::is_cell_loaded);
	ClassDB::bind_method(D_METHOD("get_cell_instance", "cell"), &WorldPartition3D::get_cell_instance);
	ClassDB::bind_method(D_METHOD("get_loaded_cell_count"), &WorldPartition3D::get_loaded_cell_count);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldPartition3D::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("get_pending_cell_count"), &WorldPartition3D::get_pending_cell_count);
	ClassDB::bind_method(D_METHOD("get_inflight_request_count"), &WorldPartition3D::get_inflight_request_count);
	ClassDB::bind_method(D_METHOD("get_failed_cell_count"), &WorldPartition3D::get_failed_cell_count);

	ADD_GROUP("World Grid", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,4096,1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cell_scenes"), "set_cell_scenes", "get_cell_scenes");
	ADD_GROUP("Streaming", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "streaming_enabled"), "set_streaming_enabled", "is_streaming_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "observer_path", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_observer_path", "get_observer_path");
	ADD_GROUP("Predictive Prefetch", "predictive_");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "predictive_velocity"), "set_predictive_velocity", "get_predictive_velocity");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "predictive_lookahead_seconds", PROPERTY_HINT_RANGE, "0,5,0.1,suffix:s"), "set_predictive_lookahead_seconds", "get_predictive_lookahead_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "predictive_max_distance", PROPERTY_HINT_RANGE, "0,128,1,suffix:m"), "set_predictive_max_distance", "get_predictive_max_distance");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "load_radius", PROPERTY_HINT_RANGE, "0,32,1"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "unload_radius", PROPERTY_HINT_RANGE, "0,64,1"), "set_unload_radius", "get_unload_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_new_requests_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_new_requests_per_frame", "get_max_new_requests_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instances_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_instances_per_frame", "get_max_instances_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_unloads_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_unloads_per_frame", "get_max_unloads_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_requests", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_concurrent_requests", "get_max_concurrent_requests");
	ADD_GROUP("Gameplay State", "");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "persist_rigid_bodies"), "set_persist_rigid_bodies", "is_persisting_rigid_bodies");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "persist_streaming_objects"), "set_persist_streaming_objects", "is_persisting_streaming_objects");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "cell_layers"), "set_cell_layers", "get_cell_layers");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "layer_states"), "set_layer_states", "get_layer_states");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "navigation_cell_states"), "set_navigation_cell_states", "get_navigation_cell_states");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "navigation_link_states"), "set_navigation_link_states", "get_navigation_link_states");
	ADD_GROUP("Cell Detail Levels", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "detail_radius", PROPERTY_HINT_RANGE, "-1,32,1"), "set_detail_radius", "get_detail_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "detail_hysteresis_cells", PROPERTY_HINT_RANGE, "0,8,1"), "set_detail_hysteresis_cells", "get_detail_hysteresis_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_detail_transitions_per_frame", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_detail_transitions_per_frame", "get_max_detail_transitions_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "simulation_radius", PROPERTY_HINT_RANGE, "-1,32,1"), "set_simulation_radius", "get_simulation_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "simulation_hysteresis_cells", PROPERTY_HINT_RANGE, "0,8,1"), "set_simulation_hysteresis_cells", "get_simulation_hysteresis_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_simulation_transitions_per_frame", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_simulation_transitions_per_frame", "get_max_simulation_transitions_per_frame");
	ADD_GROUP("Cell Physics", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "physics_radius", PROPERTY_HINT_RANGE, "-1,32,1"), "set_physics_radius", "get_physics_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "physics_hysteresis_cells", PROPERTY_HINT_RANGE, "0,8,1"), "set_physics_hysteresis_cells", "get_physics_hysteresis_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_physics_transitions_per_frame", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_physics_transitions_per_frame", "get_max_physics_transitions_per_frame");
	ADD_GROUP("Cell Route Cache", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cell_path_cache_entries", PROPERTY_HINT_RANGE, "0,128,1"), "set_max_cell_path_cache_entries", "get_max_cell_path_cache_entries");
	ADD_GROUP("Navigation Regions", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "navigation_radius", PROPERTY_HINT_RANGE, "-1,32,1"), "set_navigation_radius", "get_navigation_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "navigation_hysteresis_cells", PROPERTY_HINT_RANGE, "0,8,1"), "set_navigation_hysteresis_cells", "get_navigation_hysteresis_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_navigation_transitions_per_frame", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_navigation_transitions_per_frame", "get_max_navigation_transitions_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_navigation_rebuilds_per_physics_frame", PROPERTY_HINT_RANGE, "1,16,1"), "set_max_navigation_rebuilds_per_physics_frame", "get_max_navigation_rebuilds_per_physics_frame");
	ADD_GROUP("Navigation Scheduling", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_navigation_updates_per_physics_frame", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_navigation_updates_per_physics_frame", "get_max_navigation_updates_per_physics_frame");
	ADD_GROUP("Cell Activation", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "min_physics_frames_after_load", PROPERTY_HINT_RANGE, "0,8,1"), "set_min_physics_frames_after_load", "get_min_physics_frames_after_load");

	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_activated", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_deactivating", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_state_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::DICTIONARY, "state")));
	ADD_SIGNAL(MethodInfo("cell_object_state_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::DICTIONARY, "states")));
	ADD_SIGNAL(MethodInfo("cell_navigation_state_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::BOOL, "enabled")));
	ADD_SIGNAL(MethodInfo("cell_navigation_link_state_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::STRING, "link_path"), PropertyInfo(Variant::BOOL, "enabled")));
	ADD_SIGNAL(MethodInfo("layer_state_changed", PropertyInfo(Variant::STRING, "layer"), PropertyInfo(Variant::BOOL, "enabled")));
	ADD_SIGNAL(MethodInfo("observer_cell_changed", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_detail_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::INT, "detail_level")));
	ADD_SIGNAL(MethodInfo("cell_simulation_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::BOOL, "active")));
	ADD_SIGNAL(MethodInfo("cell_physics_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::BOOL, "active")));
	ADD_SIGNAL(MethodInfo("cell_navigation_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::BOOL, "active")));
	ADD_SIGNAL(MethodInfo("cell_navigation_mesh_rebuilt", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::INT, "revision")));
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
	cell_creation_physics_frames.clear();
	active_detail_levels.clear();
	active_simulation_cells.clear();
	active_physics_cells.clear();
	physics_enabled_frames.clear();
	active_navigation_cells.clear();
	navigation_enabled_frames.clear();
	navigation_dirty_cells.clear();
	navigation_mesh_revisions.clear();
	pending_cells.clear();
	ready_scenes.clear();
	pinned_cells.clear();
	navigation_agents.clear();
	navigation_selected.clear();
	navigation_consumed.clear();
}
