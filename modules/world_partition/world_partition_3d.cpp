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
	cell_creation_physics_frames.erase(p_cell);
	active_detail_levels.erase(p_cell);
	active_simulation_cells.erase(p_cell);
	active_physics_cells.erase(p_cell);
	physics_enabled_frames.erase(p_cell);
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
	add_child(instance);
	active_cells.insert(p_cell, instance->get_instance_id());
	cell_creation_physics_frames.insert(p_cell, Engine::get_singleton()->get_physics_frames());
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
	if (detail_radius < 0 || pinned_cells.has(p_cell) || _is_cell_required_by_important_source(p_cell) || _within_radius(p_cell, p_center, detail_radius)) {
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
	if (simulation_radius < 0 || pinned_cells.has(p_cell) || _within_radius(p_cell, p_center, simulation_radius)) {
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
	if (physics_radius < 0 || pinned_cells.has(p_cell) || _is_cell_required_by_important_source(p_cell) || _within_radius(p_cell, p_center, physics_radius)) {
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

void WorldPartition3D::set_max_navigation_updates_per_physics_frame(int p_count) {
	ERR_FAIL_COND_MSG(p_count < 1 || p_count > 64, "WorldPartition3D navigation update budget must be 1 to 64 per physics frame.");
	max_navigation_updates_per_physics_frame = p_count;
}

int WorldPartition3D::get_max_navigation_updates_per_physics_frame() const {
	return max_navigation_updates_per_physics_frame;
}

bool WorldPartition3D::register_navigation_agent(const String &p_name, Node3D *p_agent, int p_priority) {
	ERR_FAIL_COND_V_MSG(p_name.is_empty() || p_name.length() > 64, false, "Navigation agent name must contain 1 to 64 characters.");
	ERR_FAIL_NULL_V_MSG(p_agent, false, "Navigation agent must be a Node3D.");
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
		if (!node->is_inside_tree() || !node->is_physics_processing()) {
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
	if (node == nullptr || node->is_queued_for_deletion() || !node->is_inside_tree() || !node->is_physics_processing()) {
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
	pinned_cells.erase(p_cell);
	_purge_unused_ready_scenes();
}

void WorldPartition3D::clear_cell_scenes() {
	_clear_active_cells();
	pending_cells.clear();
	failed_cells.clear();
	cell_scenes.clear();
	pinned_cells.clear();
	_purge_unused_ready_scenes();
}

bool WorldPartition3D::pin_cell(const Vector2i &p_cell) {
	ERR_FAIL_COND_V_MSG(_get_scene_path(p_cell).is_empty(), false, "WorldPartition3D cannot pin an unregistered cell.");
	if (pinned_cells.has(p_cell)) {
		return false;
	}
	ERR_FAIL_COND_V_MSG(pinned_cells.size() >= MAX_PINNED_CELLS, false, "WorldPartition3D supports at most 128 pinned cells.");
	pinned_cells.insert(p_cell);
	return true;
}

void WorldPartition3D::unpin_cell(const Vector2i &p_cell) {
	pinned_cells.erase(p_cell);
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

void WorldPartition3D::update_streaming() {
	_poll_requests();
	if (!streaming_enabled || !is_inside_tree() || observer_path.is_empty()) {
		predicted_cell_valid = false;
		_purge_unused_ready_scenes();
		_refresh_processing();
		return;
	}

	Node3D *observer = Object::cast_to<Node3D>(get_node_or_null(observer_path));
	if (observer == nullptr) {
		predicted_cell_valid = false;
		_purge_unused_ready_scenes();
		return;
	}

	const Vector2i center = local_position_to_cell(to_local(observer->get_global_position()));
	const bool observer_cell_changed = !observer_cell_valid || observer_cell != center;
	observer_cell = center;
	observer_cell_valid = true;

	// Predict a single future cell after the observer's normal demand radius.
	// Feed velocity via set_predictive_velocity() in world space. The built-in
	// distance and time bounds avoid unbounded speculative memory growth.
	predicted_cell_valid = false;
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

	Vector<Vector2i> unload;
	for (const KeyValue<Vector2i, ObjectID> &E : active_cells) {
		if ((!pinned_cells.has(E.key) && !_is_cell_required_by_source(E.key, 1) && !(predicted_cell_valid && E.key == predicted_cell) && !_within_radius(E.key, center, unload_radius)) || ObjectDB::get_instance(E.value) == nullptr) {
			unload.push_back(E.key);
		}
	}
	for (const Vector2i &cell : unload) {
		_unload_cell(cell);
	}

	Vector<Vector2i> cancel;
	for (const KeyValue<Vector2i, String> &E : pending_cells) {
		if (!pinned_cells.has(E.key) && !_is_cell_required_by_source(E.key, 0) && !(predicted_cell_valid && E.key == predicted_cell) && !_within_radius(E.key, center, load_radius)) {
			cancel.push_back(E.key);
		}
	}
	for (const Vector2i &cell : cancel) {
		pending_cells.erase(cell);
	}

	int new_requests = max_new_requests_per_frame;
	int instances = max_instances_per_frame;
	// Visit nearer cells first and produce a deterministic order.
	for (int radius = 0; radius <= load_radius; radius++) {
		for (int dz = -radius; dz <= radius; dz++) {
			for (int dx = -radius; dx <= radius; dx++) {
				if (MAX(ABS(dx), ABS(dz)) != radius) {
					continue;
				}
				const Vector2i cell = center + Vector2i(dx, dz);
				_request_cell(cell, new_requests, instances);
			}
		}
	}
	// Explicitly pinned hubs are kept alive outside the observer radius.
	// They share the same per-frame budgets and threaded path cache.
	for (const Vector2i &cell : pinned_cells) {
		if (!_within_radius(cell, center, load_radius)) {
			_request_cell(cell, new_requests, instances);
		}
	}
	// Registered source priorities (3 urgent .. 0 background) are evaluated
	// only after observer and pinned cells. The budget is shared across all
	// sources. Stable name ordering within each tier avoids HashMap iteration
	// nondeterminism, including when multiple sources target the same scene.
	Vector<String> source_names;
	for (const KeyValue<String, StreamingSource> &E : streaming_sources) {
		source_names.push_back(E.key);
	}
	source_names.sort();
	for (int priority = 3; priority >= 0; priority--) {
		for (const String &name : source_names) {
			const StreamingSource *source = streaming_sources.getptr(name);
			if (source == nullptr || source->priority != priority) {
				continue;
			}
			const Vector2i source_center = local_position_to_cell(to_local(source->global_position));
			for (int radius = 0; radius <= source->radius; radius++) {
				for (int dz = -radius; dz <= radius; dz++) {
					for (int dx = -radius; dx <= radius; dx++) {
						if (MAX(ABS(dx), ABS(dz)) == radius) {
							_request_cell(source_center + Vector2i(dx, dz), new_requests, instances);
						}
					}
				}
			}
		}
	}
	// Lowest priority: one forecast cell, after visible, pinned, and quest cells.
	if (predicted_cell_valid && !_within_radius(predicted_cell, center, load_radius)) {
		_request_cell(predicted_cell, new_requests, instances);
	}
	_refresh_cell_detail(center);
	_refresh_cell_simulation(center);
	_refresh_cell_physics(center);
	_purge_unused_ready_scenes();
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
	ClassDB::bind_method(D_METHOD("pin_cell", "cell"), &WorldPartition3D::pin_cell);
	ClassDB::bind_method(D_METHOD("unpin_cell", "cell"), &WorldPartition3D::unpin_cell);
	ClassDB::bind_method(D_METHOD("is_cell_pinned", "cell"), &WorldPartition3D::is_cell_pinned);
	ClassDB::bind_method(D_METHOD("get_pinned_cells"), &WorldPartition3D::get_pinned_cells);
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
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_requests", PROPERTY_HINT_RANGE, "1,128,1"), "set_max_concurrent_requests", "get_max_concurrent_requests");
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
	ADD_GROUP("Navigation Scheduling", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_navigation_updates_per_physics_frame", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_navigation_updates_per_physics_frame", "get_max_navigation_updates_per_physics_frame");
	ADD_GROUP("Cell Activation", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "min_physics_frames_after_load", PROPERTY_HINT_RANGE, "0,8,1"), "set_min_physics_frames_after_load", "get_min_physics_frames_after_load");

	ADD_SIGNAL(MethodInfo("cell_loaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_unloaded", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("observer_cell_changed", PropertyInfo(Variant::VECTOR2I, "cell")));
	ADD_SIGNAL(MethodInfo("cell_detail_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::INT, "detail_level")));
	ADD_SIGNAL(MethodInfo("cell_simulation_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::BOOL, "active")));
	ADD_SIGNAL(MethodInfo("cell_physics_changed", PropertyInfo(Variant::VECTOR2I, "cell"), PropertyInfo(Variant::BOOL, "active")));
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
	pending_cells.clear();
	ready_scenes.clear();
	pinned_cells.clear();
	navigation_agents.clear();
	navigation_selected.clear();
	navigation_consumed.clear();
}
