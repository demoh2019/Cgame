/**************************************************************************/
/*  world_streamer.cpp                                             */
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

#include "world_streamer.h"

#include "core/config/engine.h"
#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "scene/2d/node_2d.h"
#include "scene/3d/node_3d.h"
#include "scene/resources/packed_scene.h"


void WorldStreamer::_record_failure(const Vector3i &p_cell, const String &p_reason) {
	failed.insert(p_cell);
	if (max_auto_retries > 0) {
		RetryState &state = retry_states[p_cell];
		if (state.attempts < max_auto_retries) {
			// Bounded exponential backoff; exactly max_auto_retries more requests.
			const real_t multiplier = real_t(1 << state.attempts);
			const real_t seconds = MIN(retry_max_delay, retry_initial_delay * multiplier);
			state.next_retry_usec = OS::get_singleton()->get_ticks_usec() + uint64_t(seconds * 1000000.0);
			state.attempts++;
		} else {
			state.next_retry_usec = 0; // Exhausted until refresh(true) or leaving the area.
		}
	}
	emit_signal(SNAME("chunk_load_failed"), p_cell, p_reason);
}

void WorldStreamer::_update_retries(const Vector3 &p_focus, real_t p_keep_radius) {
	if (retry_states.is_empty()) {
		return;
	}
	const uint64_t now = OS::get_singleton()->get_ticks_usec();
	LocalVector<Vector3i> forget;
	LocalVector<Vector3i> ready;
	for (const KeyValue<Vector3i, RetryState> &entry : retry_states) {
		const bool beyond_focus = WorldStreamingGrid::distance_to_cell(p_focus, entry.key, cell_size, _grid_axes()) > p_keep_radius;
		const bool auxiliary_keeps = _auxiliary_is_near_focus(p_focus) &&
				WorldStreamingGrid::distance_to_cell(auxiliary_source_position, entry.key, cell_size, _grid_axes()) <= _auxiliary_effective_radius();
		if (beyond_focus && !auxiliary_keeps) {
			forget.push_back(entry.key);
		} else if (entry.value.next_retry_usec != 0 && now >= entry.value.next_retry_usec) {
			ready.push_back(entry.key);
		}
	}
	for (const Vector3i &cell : forget) {
		retry_states.erase(cell);
		failed.erase(cell);
	}
	for (const Vector3i &cell : ready) {
		// The attempt is picked up by the usual bounded generation/load queue.
		failed.erase(cell);
		retry_states[cell].next_retry_usec = 0;
	}
}

int WorldStreamer::get_retry_pending_count() const {
	int count = 0;
	for (const KeyValue<Vector3i, RetryState> &entry : retry_states) {
		if (entry.value.next_retry_usec != 0) {
			count++;
		}
	}
	return count;
}

void WorldStreamer::set_max_auto_retries(int p_count) {
	max_auto_retries = CLAMP(p_count, 0, 8);
	if (max_auto_retries == 0) {
		retry_states.clear();
	}
}

void WorldStreamer::set_retry_initial_delay(real_t p_seconds) {
	ERR_FAIL_COND(!Math::is_finite(p_seconds));
	retry_initial_delay = CLAMP(p_seconds, real_t(0.01), real_t(60.0));
}

void WorldStreamer::set_retry_max_delay(real_t p_seconds) {
	ERR_FAIL_COND(!Math::is_finite(p_seconds));
	retry_max_delay = CLAMP(p_seconds, real_t(0.01), real_t(60.0));
}

real_t WorldStreamer::_auxiliary_effective_radius() const {
	// Limit the added residency to a tiny region (maximum two cell widths)
	// no matter which game or editor script sets the auxiliary source.
	return MIN(auxiliary_source_radius, cell_size * real_t(2.0));
}

bool WorldStreamer::_auxiliary_is_near_focus(const Vector3 &p_focus) const {
	if (!auxiliary_source_active || !auxiliary_source_position.is_finite() || !p_focus.is_finite()) {
		return false;
	}
	Vector3 offset = auxiliary_source_position - p_focus;
	if (axes == AXES_XZ) {
		offset.y = 0.0;
	} else if (axes == AXES_XY) {
		offset.z = 0.0;
	}
	// A quest marker on the far side of the map must never become a
	// second independent island of fully instantiated world chunks.
	return offset.length() <= load_radius + cell_size;
}

bool WorldStreamer::_cell_requested(const Vector3 &p_focus, const Vector3i &p_cell) const {
	if (WorldStreamingGrid::distance_to_cell(p_focus, p_cell, cell_size, _grid_axes()) <= load_radius) {
		return true;
	}
	return _auxiliary_is_near_focus(p_focus) &&
			WorldStreamingGrid::distance_to_cell(auxiliary_source_position, p_cell, cell_size, _grid_axes()) <= _auxiliary_effective_radius();
}

bool WorldStreamer::_get_focus_position(Vector3 &r_position) const {
	if (is_inside_tree() && !focus.is_empty()) {
		Node *node = get_node_or_null(focus);
		Node *parent = _get_parent_for_chunks();
		if (Node3D *node_3d = Object::cast_to<Node3D>(node)) {
			if (node_3d->is_inside_tree()) {
				r_position = node_3d->get_global_position();
				// Measure in the frame of the chunk parent. If that parent is moved by something like
				// FloatingOrigin3D, the chunk grid then stays in absolute world coordinates.
				Node3D *parent_3d = Object::cast_to<Node3D>(parent);
				if (parent_3d && parent_3d->is_inside_tree()) {
					r_position = parent_3d->to_local(r_position);
				}
				return r_position.is_finite();
			}
		} else if (Node2D *node_2d = Object::cast_to<Node2D>(node)) {
			if (node_2d->is_inside_tree()) {
				Vector2 position = node_2d->get_global_position();
				Node2D *parent_2d = Object::cast_to<Node2D>(parent);
				if (parent_2d && parent_2d->is_inside_tree()) {
					position = parent_2d->to_local(position);
				}
				r_position = Vector3(position.x, position.y, 0.0);
				return r_position.is_finite();
			}
		}
	}
	r_position = focus_position;
	return r_position.is_finite();
}

String WorldStreamer::_path_for_cell(const Vector3i &p_cell) const {
	if (chunk_provider.is_valid()) {
		Variant cell = p_cell;
		const Variant *args[1] = { &cell };
		Variant result;
		Callable::CallError error;
		chunk_provider.callp(args, 1, result, error);
		if (error.error != Callable::CallError::CALL_OK) {
			return String();
		}
		return result.get_type() == Variant::STRING || result.get_type() == Variant::STRING_NAME ? String(result) : String();
	}
	if (chunk_path_template.is_empty()) {
		return String();
	}
	String path = chunk_path_template;
	path = path.replace("{x}", itos(p_cell.x));
	path = path.replace("{y}", itos(p_cell.y));
	path = path.replace("{z}", itos(p_cell.z));
	return path;
}

Node *WorldStreamer::_get_parent_for_chunks() const {
	if (!chunk_parent.is_empty() && is_inside_tree()) {
		Node *node = get_node_or_null(chunk_parent);
		if (node) {
			return node;
		}
	}
	return const_cast<WorldStreamer *>(this);
}

void WorldStreamer::_forget_dead_chunks() {
	// A chunk may be freed by game code; stop tracking it so the cell can load again.
	LocalVector<Vector3i> dead;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		if (!ObjectDB::get_instance(entry.value)) {
			dead.push_back(entry.key);
		}
	}
	for (const Vector3i &cell : dead) {
		loaded.erase(cell);
		pending_visual_details.erase(cell);
		emit_signal(SNAME("chunk_unloaded"), cell);
	}
}

void WorldStreamer::_unload_cell(const Vector3i &p_cell) {
	HashMap<Vector3i, ObjectID>::Iterator it = loaded.find(p_cell);
	if (!it) {
		return;
	}
	Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(it->value));
	loaded.remove(it);
	pending_visual_details.erase(p_cell);
	if (chunk) {
		if (chunk->get_parent()) {
			chunk->get_parent()->remove_child(chunk);
		}
		chunk->queue_free();
	}
	emit_signal(SNAME("chunk_unloaded"), p_cell);
}

bool WorldStreamer::_adopt_chunk(const Vector3i &p_cell, Node *p_chunk) {
	if (!p_chunk) {
		return false;
	}
	p_chunk->set_name(vformat("Chunk_%d_%d_%d", p_cell.x, p_cell.y, p_cell.z));
	if (position_chunks) {
		const Vector3 origin = WorldStreamingGrid::cell_origin(p_cell, cell_size);
		if (Node3D *chunk_3d = Object::cast_to<Node3D>(p_chunk)) {
			chunk_3d->set_position(origin);
		} else if (Node2D *chunk_2d = Object::cast_to<Node2D>(p_chunk)) {
			chunk_2d->set_position(Vector2(origin.x, origin.y));
		}
	}
	Node *parent = _get_parent_for_chunks();
	parent->add_child(p_chunk);
	loaded[p_cell] = p_chunk->get_instance_id();
	retry_states.erase(p_cell);
	failed.erase(p_cell);
	// Track optional visual continuation without delaying authoritative world
	// ownership or adding extra load requests. Ordinary chunks remain ready.
	if (p_chunk->has_method(SNAME("has_pending_visual_detail")) &&
			bool(p_chunk->call(SNAME("has_pending_visual_detail")))) {
		pending_visual_details.insert(p_cell);
	}
	emit_signal(SNAME("chunk_loaded"), p_cell, p_chunk);
	return true;
}

bool WorldStreamer::_finalize_chunk(const Vector3i &p_cell, const String &p_path) {
	Error error = OK;
	Ref<PackedScene> scene = ResourceLoader::load_threaded_get(p_path, &error);
	if (scene.is_null()) {
		return false;
	}
	Node *chunk = scene->instantiate();
	if (!chunk) {
		return false;
	}
	return _adopt_chunk(p_cell, chunk);
}

// Main-thread chunk creation remains indivisible. Generation and adoption
// time includes Node::_ready() callbacks, even for missing/failed cells.
void WorldStreamer::_generate_cell(const Vector3i &cell) {
	Variant cell_variant = cell;
	const Variant *args[1] = { &cell_variant };
	Variant result;
	Callable::CallError error;
	chunk_generator.callp(args, 1, result, error);
	if (error.error != Callable::CallError::CALL_OK) {
		_record_failure(cell, String("generator call failed"));
		return;
	}
	if (result.get_type() == Variant::NIL) {
		missing.insert(cell); // Null is an intentionally empty cell, not a retryable error.
		return;
	}
	if (result.get_type() != Variant::OBJECT) {
		_record_failure(cell, String("generator returned a non-Node value"));
		return;
	}
	Node *chunk = Object::cast_to<Node>(result.get_validated_object());
	if (!chunk) {
		_record_failure(cell, String("generator returned an unusable object"));
		return;
	}
	if (!_adopt_chunk(cell, chunk)) {
		memdelete(chunk);
		_record_failure(cell, String("generator returned an unusable node"));
	}
}

void WorldStreamer::_record_chunk_work(uint64_t p_started_usec) {
	const uint64_t now = OS::get_singleton()->get_ticks_usec();
	const uint64_t elapsed = now >= p_started_usec ? now - p_started_usec : 0;
	frame_chunk_work_usec = MIN(int64_t(1000000000),
			frame_chunk_work_usec + int64_t(MIN(elapsed, uint64_t(1000000000))));
	frame_chunk_attempt_count++;
}

void WorldStreamer::_finish_chunk_work_frame() {
	last_frame_chunk_work_usec = frame_chunk_work_usec;
	last_frame_chunk_attempt_count = frame_chunk_attempt_count;
	frame_chunk_work_usec = 0;
	frame_chunk_attempt_count = 0;
}

void WorldStreamer::set_adaptive_chunk_budget_enabled(bool p_enabled) {
	adaptive_chunk_budget_enabled = p_enabled;
	if (!p_enabled) {
		streaming_frame_pressure = 0.0;
	}
}

double WorldStreamer::advance_chunk_pressure(double p_pressure, double p_frame_delta) {
	if (!Math::is_finite(p_pressure)) {
		p_pressure = 0.0;
	}
	const double previous = CLAMP(p_pressure, 0.0, 1.0);
	if (!Math::is_finite(p_frame_delta) || p_frame_delta <= 0.0) {
		return previous;
	}
	if (p_frame_delta > 0.030) {
		return MIN(1.0, previous + 0.16);
	}
	if (p_frame_delta < 0.020) {
		return MAX(0.0, previous - 0.05);
	}
	return previous;
}

int WorldStreamer::calculate_adaptive_instantiation_slots(int p_configured, double p_pressure) {
	const int configured = MAX(p_configured, 1);
	const double pressure = Math::is_finite(p_pressure) ? CLAMP(p_pressure, 0.0, 1.0) : 0.0;
	const int reduction = pressure >= 0.8 ? 2 : (pressure >= 0.4 ? 1 : 0);
	return MAX(1, configured - reduction);
}

int WorldStreamer::calculate_adaptive_chunk_work_usec(int p_configured, double p_pressure) {
	const int configured = CLAMP(p_configured, 0, 1000000);
	if (configured == 0) {
		return 0;
	}
	const double pressure = Math::is_finite(p_pressure) ? CLAMP(p_pressure, 0.0, 1.0) : 0.0;
	if (pressure >= 0.8) {
		return MIN(configured, MAX(250, configured / 2));
	}
	if (pressure >= 0.4) {
		return MIN(configured, MAX(250, (configured * 3) / 4));
	}
	return configured;
}

int WorldStreamer::get_effective_instantiations_per_frame() const {
	return adaptive_chunk_budget_enabled ?
			calculate_adaptive_instantiation_slots(max_instantiations_per_frame, streaming_frame_pressure) :
			MAX(max_instantiations_per_frame, 1);
}

int WorldStreamer::get_effective_chunk_work_usec() const {
	return adaptive_chunk_budget_enabled ?
			calculate_adaptive_chunk_work_usec(max_chunk_work_usec, streaming_frame_pressure) :
			max_chunk_work_usec;
}

// Generates queued cells on the main thread, a bounded number per call.
void WorldStreamer::_run_generator_queue(int &r_instantiation_budget, uint64_t p_frame_started_usec) {
	if (!enabled || r_instantiation_budget <= 0 || generate_queue.is_empty() || !chunk_generator.is_valid()) {
		return;
	}
	Vector3 position;
	const bool have_focus = _get_focus_position(position);
	// Queued work must still be within the *load* radius. The larger unload
	// radius is only for keeping existing cells alive after moving away.
	uint32_t consumed = 0;
	while (consumed < generate_queue.size() && r_instantiation_budget > 0) {
		// A single generator call cannot be interrupted. After at least one
		// chunk, stop before the next one if this frame's CPU budget ran out.
		if (active_chunk_work_budget_usec > 0 && r_instantiation_budget < active_instantiation_budget &&
				OS::get_singleton()->get_ticks_usec() - p_frame_started_usec >= uint64_t(active_chunk_work_budget_usec)) {
			break;
		}
		const Vector3i cell = generate_queue[consumed++];
		if (loaded.has(cell)) {
			continue;
		}
		// The focus may have moved on while the cell waited in the queue.
		if (!have_focus || !_cell_requested(position, cell)) {
			continue;
		}
		// Generator calls can be expensive even when a chunk is missing or fails.
		r_instantiation_budget--;
		const uint64_t generation_started_usec = OS::get_singleton()->get_ticks_usec();
		_generate_cell(cell);
		_record_chunk_work(generation_started_usec);
	}
	if (consumed > 0) {
		LocalVector<Vector3i> rest;
		for (uint32_t i = consumed; i < generate_queue.size(); i++) {
			rest.push_back(generate_queue[i]);
		}
		generate_queue = rest;
	}
}

void WorldStreamer::_poll_loading(int &r_instantiation_budget, uint64_t p_frame_started_usec) {
	if (!enabled || loading.is_empty()) {
		return;
	}
	Vector3 position;
	const bool have_focus = _get_focus_position(position);

	struct Ready {
		Vector3i cell;
		real_t distance;
	};
	LocalVector<Ready> ready;
	LocalVector<Vector3i> finished_failed;
	for (const KeyValue<Vector3i, String> &entry : loading) {
		const ResourceLoader::ThreadLoadStatus status = ResourceLoader::load_threaded_get_status(entry.value);
		if (status == ResourceLoader::THREAD_LOAD_LOADED) {
			ready.push_back({ entry.key, have_focus ? WorldStreamingGrid::distance_to_cell(position, entry.key, cell_size, _grid_axes()) : real_t(0.0) });
		} else if (status != ResourceLoader::THREAD_LOAD_IN_PROGRESS) {
			finished_failed.push_back(entry.key);
		}
	}

	for (const Vector3i &cell : finished_failed) {
		const String path = loading[cell];
		loading.erase(cell);
		_record_failure(cell, path);
	}

	// Finished threaded scenes must use the same forward-biased priority as
	// pending procedural cells. Otherwise a fast-moving player waits for
	// already-ready *behind-camera* scenes before nearby forward scenes.
	// First keep nearest-first ordering for stationary/invalid motion hints.
	for (uint32_t i = 1; i < ready.size(); i++) { // Insertion sort: max_concurrent_loads is small.
		Ready item = ready[i];
		int32_t j = int32_t(i) - 1;
		while (j >= 0 && ready[j].distance > item.distance) {
			ready[j + 1] = ready[j];
			j--;
		}
		ready[j + 1] = item;
	}
	LocalVector<Vector3i> ready_cells;
	ready_cells.reserve(ready.size());
	for (const Ready &item : ready) {
		ready_cells.push_back(item.cell);
	}
	if (have_focus) {
		WorldStreamingGrid::prioritize_cells_for_motion_and_view(ready_cells, position,
				velocity_hint, lookahead_seconds, MIN(load_radius * real_t(0.4), cell_size),
				view_direction, view_priority, cell_size, _grid_axes());
	}
	for (const Vector3i &cell : ready_cells) {
		const String path = loading[cell];
		const bool still_wanted = have_focus && _cell_requested(position, cell) && !loaded.has(cell);
		if (!still_wanted) {
			// The focus moved on while loading: release the result and drop it.
			loading.erase(cell);
			ResourceLoader::load_threaded_get(path);
			continue;
		}
		if (r_instantiation_budget <= 0 || (active_chunk_work_budget_usec > 0 && r_instantiation_budget < active_instantiation_budget &&
				OS::get_singleton()->get_ticks_usec() - p_frame_started_usec >= uint64_t(active_chunk_work_budget_usec))) {
			continue; // Keep loaded resources ready for the next frame.
		}
		r_instantiation_budget--;
		loading.erase(cell);
		const uint64_t finalization_started_usec = OS::get_singleton()->get_ticks_usec();
		const bool finalized = _finalize_chunk(cell, path);
		_record_chunk_work(finalization_started_usec);
		if (!finalized) {
			_record_failure(cell, path);
		}
	}
}

void WorldStreamer::_update_streaming() {
	_forget_dead_chunks();

	Vector3 position;
	if (!enabled || !_get_focus_position(position)) {
		return;
	}
	const real_t keep_radius = MAX(unload_radius, load_radius);
	_update_retries(position, keep_radius);

	LocalVector<Vector3i> to_unload;
	HashSet<Vector3i> loaded_cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		loaded_cells.insert(entry.key);
	}
	WorldStreamingGrid::cells_to_unload(position, keep_radius, cell_size, _grid_axes(), loaded_cells, to_unload);
	for (const Vector3i &cell : to_unload) {
		// Keep explicitly prefetched cells while their source stays nearby,
		// even when they are just beyond the ordinary player unload radius.
		if (_auxiliary_is_near_focus(position) &&
				WorldStreamingGrid::distance_to_cell(auxiliary_source_position, cell, cell_size, _grid_axes()) <= _auxiliary_effective_radius()) {
			continue;
		}
		_unload_cell(cell);
	}

	LocalVector<Vector3i> wanted;
	bool truncated = false;
	WorldStreamingGrid::cells_in_radius(position, load_radius, cell_size, _grid_axes(), wanted, WorldStreamingGrid::MAX_CELLS, &truncated);
	// Camera/motion hints reprioritize only the main focus cells; the
	// optional explicit auxiliary source may add a separately bounded set.
	// Predicted velocity never enlarges resident world memory.

	WorldStreamingGrid::prioritize_cells_for_motion_and_view(wanted, position,
			velocity_hint, lookahead_seconds, MIN(load_radius * real_t(0.4), cell_size),
			view_direction, view_priority, cell_size, _grid_axes());
	// Route hints only REORDER cells already selected for player residency.
	// Route pathfinding is performed by gameplay (AStarGrid2D), not by
	// this per-frame engine scheduler. The player's own cell stays first.
	if (route_hint_cells.size() > 1 && route_hint_cells[0] == world_to_cell(position)) {
		HashSet<Vector3i> candidates;
		for (const Vector3i &cell : wanted) {
			candidates.insert(cell);
		}
		HashSet<Vector3i> selected;
		LocalVector<Vector3i> route;
		for (const Vector3i &cell : route_hint_cells) {
			if (cell != route_hint_cells[0] && candidates.has(cell) && !selected.has(cell)) {
				selected.insert(cell);
				route.push_back(cell);
			}
		}
		if (!route.is_empty() && candidates.has(route_hint_cells[0])) {
			LocalVector<Vector3i> normal;
			for (const Vector3i &cell : wanted) {
				if (cell != route_hint_cells[0] && !selected.has(cell)) {
					normal.push_back(cell);
				}
			}
			LocalVector<Vector3i> reordered;
			reordered.reserve(wanted.size());
			reordered.push_back(route_hint_cells[0]);
			uint32_t route_index = 0;
			uint32_t normal_index = 0;
			while (route_index < route.size() || normal_index < normal.size()) {
				if (route_index < route.size()) {
					reordered.push_back(route[route_index++]);
				}
				// Never starve non-route chunks: at least two regular cells
				// can run between successive route promotions.
				for (int n = 0; n < 2 && normal_index < normal.size(); n++) {
					reordered.push_back(normal[normal_index++]);
				}
			}
			if (reordered.size() == wanted.size()) {
				wanted = reordered;
			}
		}
	}
	// A nearby cinematic/waypoint target may contribute a handful of extra
	// cells outside the player sphere. Never sacrifice the bounded player
	// set; interleave at most one auxiliary cell per three primary cells,
	// and always load the player's own cell first.
	if (_auxiliary_is_near_focus(position) && wanted.size() < WorldStreamingGrid::MAX_CELLS) {
		LocalVector<Vector3i> near_source;
		WorldStreamingGrid::cells_in_radius(auxiliary_source_position, _auxiliary_effective_radius(),
				cell_size, _grid_axes(), near_source, 64);
		HashSet<Vector3i> seen;
		for (const Vector3i &cell : wanted) {
			seen.insert(cell);
		}
		LocalVector<Vector3i> extra;
		for (const Vector3i &cell : near_source) {
			if (!seen.has(cell) && wanted.size() + extra.size() < WorldStreamingGrid::MAX_CELLS) {
				seen.insert(cell);
				extra.push_back(cell);
			}
		}
		if (!extra.is_empty()) {
			LocalVector<Vector3i> interleaved;
			interleaved.reserve(wanted.size() + extra.size());
			uint32_t main_index = 0;
			uint32_t extra_index = 0;
			if (!wanted.is_empty()) {
				interleaved.push_back(wanted[main_index++]);
			}
			while (main_index < wanted.size() || extra_index < extra.size()) {
				for (int i = 0; i < 3 && main_index < wanted.size(); i++) {
					interleaved.push_back(wanted[main_index++]);
				}
				if (extra_index < extra.size()) {
					interleaved.push_back(extra[extra_index++]);
				}
			}
			wanted = interleaved;
		}
	}
	// Compare future camera turns against the last actually published queue,
	// not the previous render frame. Ordinary motion still uses the old rate.
	last_queued_view_direction = view_direction;
	if (truncated && !truncated_warned) {
		truncated_warned = true;
		WARN_PRINT(vformat("WorldStreamer: load_radius %s with cell_size %s covers more than %d cells; only the nearest are streamed. Increase cell_size or reduce load_radius.", rtos(load_radius), rtos(cell_size), WorldStreamingGrid::MAX_CELLS));
	}

	if (chunk_generator.is_valid()) {
		// Reconcile the pending queue against the *current* load radius,
		// rather than retaining cells from previous player positions.
		// The wanted cells are unique, already sorted by movement priority,
		// and bounded by MAX_CELLS. Rebuilding also prevents old work from
		// delaying new terrain after teleports or fast camera turns.
		generate_queue.clear();
		for (const Vector3i &cell : wanted) {
			if (!loaded.has(cell) && !missing.has(cell) && !failed.has(cell)) {
				generate_queue.push_back(cell);
			}
		}
		return;
	}

	for (const Vector3i &cell : wanted) {
		if (int(loading.size()) >= MAX(max_concurrent_loads, 1)) {
			break;
		}
		if (loaded.has(cell) || loading.has(cell) || missing.has(cell) || failed.has(cell)) {
			continue;
		}
		const String path = _path_for_cell(cell);
		if (path.is_empty() || !ResourceLoader::exists(path)) {
			missing.insert(cell);
			continue;
		}
		if (ResourceLoader::load_threaded_request(path, "PackedScene", true) != OK) {
			_record_failure(cell, path);
			continue;
		}
		loading[cell] = path;
	}
}

void WorldStreamer::_reset_state() {
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	for (const Vector3i &cell : cells) {
		_unload_cell(cell);
	}
	// In-flight requests finish on their own; their results are released when polled.
	missing.clear();
	failed.clear();
	retry_states.clear();
	generate_queue.clear();
	pending_visual_details.clear();
	last_queued_view_direction = Vector3();
	truncated_warned = false;
	streaming_frame_pressure = 0.0;
	frame_chunk_work_usec = 0;
	last_frame_chunk_work_usec = 0;
	frame_chunk_attempt_count = 0;
	last_frame_chunk_attempt_count = 0;
	time_since_update = 1e9;
}

void WorldStreamer::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY:
		case NOTIFICATION_ENTER_TREE: {
			if (!Engine::get_singleton()->is_editor_hint()) {
				set_process_internal(true);
			}
		} break;

		case NOTIFICATION_EXIT_TREE: {
			set_process_internal(false);
			if (chunk_parent.is_empty()) {
				// Chunks are our children and go away with us; just forget them.
				loaded.clear();
				pending_visual_details.clear();
			} else {
				_reset_state();
			}
			// A finished background load keeps its resource alive until somebody collects it. Collecting
			// here may wait briefly for loads still running, only while the streamer is being torn down.
			for (const KeyValue<Vector3i, String> &entry : loading) {
				ResourceLoader::load_threaded_get(entry.value);
			}
			loading.clear();
		} break;

		case NOTIFICATION_INTERNAL_PROCESS: {
			if (Engine::get_singleton()->is_editor_hint()) {
				return;
			}
			// One budget and wall-clock deadline are shared by threaded
			// scene finalization and procedural world generation this frame.
			if (adaptive_chunk_budget_enabled) {
				streaming_frame_pressure = advance_chunk_pressure(streaming_frame_pressure, get_process_delta_time());
			}
			active_instantiation_budget = get_effective_instantiations_per_frame();
			active_chunk_work_budget_usec = get_effective_chunk_work_usec();
			int frame_budget = active_instantiation_budget;
			const uint64_t frame_started_usec = OS::get_singleton()->get_ticks_usec();
			_poll_loading(frame_budget, frame_started_usec);
			time_since_update += get_process_delta_time();
			// Camera cuts and rapid 180-degree turns should reprioritize
			// the PROCEDURAL queue before the normal 150 ms refresh. The
			// 50 ms minimum protects CPU budgets against per-frame resorting.
			const bool turned = enabled && view_priority > real_t(0.0) &&
					WorldStreamingGrid::should_refresh_for_view_turn(
							last_queued_view_direction, view_direction, fast_view_refresh_degrees);
			const bool early = turned && time_since_update >= 0.05;
			if (time_since_update >= update_interval || early) {
				time_since_update = 0.0;
				_update_streaming();
			}
			// Exactly one queue drain per frame. Previously _poll_loading() and
			// this path both ran procedural generation on update frames, doubling
			// max_instantiations_per_frame and causing occasional frame spikes.
			_run_generator_queue(frame_budget, frame_started_usec);
			_finish_chunk_work_frame();
		} break;
	}
}

void WorldStreamer::set_auxiliary_source(const Vector3 &p_position, real_t p_radius) {
	ERR_FAIL_COND_MSG(!p_position.is_finite() || !Math::is_finite(p_radius) || p_radius <= 0.0,
			"WorldStreamer auxiliary source requires a finite position and positive finite radius.");
	const real_t bounded_radius = MIN(p_radius, cell_size * real_t(2.0));
	if (auxiliary_source_active && auxiliary_source_position == p_position && auxiliary_source_radius == bounded_radius) {
		return;
	}
	auxiliary_source_position = p_position;
	auxiliary_source_radius = bounded_radius;
	auxiliary_source_active = true;
	// Rescan the queue on the next internal frame; do not instantiate extra
	// scene nodes inside the map's input callback.
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::clear_auxiliary_source() {
	if (!auxiliary_source_active) {
		return;
	}
	auxiliary_source_active = false;
	auxiliary_source_radius = 0.0;
	time_since_update = MAX(time_since_update, update_interval);
}

bool WorldStreamer::set_route_cells(const TypedArray<Vector3i> &p_cells) {
	ERR_FAIL_COND_V_MSG(p_cells.size() > 64, false, "WorldStreamer accepts at most 64 route cells.");
	LocalVector<Vector3i> checked;
	checked.reserve(p_cells.size());
	for (int i = 0; i < p_cells.size(); i++) {
		const Vector3i cell = p_cells[i];
		if ((axes == AXES_XZ && cell.y != 0) || (axes == AXES_XY && cell.z != 0)) {
			return false;
		}
		if (!checked.is_empty()) {
			const Vector3i prev = checked[checked.size() - 1];
			const int64_t dx = int64_t(cell.x) - prev.x;
			const int64_t dy = int64_t(cell.y) - prev.y;
			const int64_t dz = int64_t(cell.z) - prev.z;
			const int64_t step = (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy) + (dz < 0 ? -dz : dz);
			if (step != 1) {
				return false; // Reject diagonals, duplicates and teleport shortcuts.
			}
		}
		checked.push_back(cell);
	}
	if (checked.size() == route_hint_cells.size()) {
		bool unchanged = true;
		for (uint32_t i = 0; i < checked.size(); i++) {
			if (checked[i] != route_hint_cells[i]) {
				unchanged = false;
				break;
			}
		}
		if (unchanged) {
			return true; // No needless queue rebuild every client frame.
		}
	}
	route_hint_cells = checked;
	time_since_update = MAX(time_since_update, update_interval);
	return true;
}

TypedArray<Vector3i> WorldStreamer::get_route_cells() const {
	TypedArray<Vector3i> cells;
	for (const Vector3i &cell : route_hint_cells) {
		cells.push_back(cell);
	}
	return cells;
}

void WorldStreamer::clear_route_cells() {
	if (route_hint_cells.is_empty()) {
		return;
	}
	route_hint_cells.clear();
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::mark_visual_details_ready(const Vector3i &p_cell) {
	if (!pending_visual_details.has(p_cell)) {
		return;
	}
	pending_visual_details.erase(p_cell);
	emit_signal(SNAME("chunk_visual_details_ready"), p_cell);
}

void WorldStreamer::set_focus(const NodePath &p_focus) {
	focus = p_focus;
}

void WorldStreamer::set_focus_position(const Vector3 &p_position) {
	focus_position = p_position;
}

void WorldStreamer::set_axes(Axes p_axes) {
	if (axes == p_axes) {
		return;
	}
	axes = p_axes;
	clear_route_cells();
	_reset_state();
}

void WorldStreamer::set_cell_size(real_t p_size) {
	ERR_FAIL_COND_MSG(!(p_size > 0.0) || !Math::is_finite(p_size), "WorldStreamer cell_size must be a positive finite number.");
	if (cell_size == p_size) {
		return;
	}
	cell_size = p_size;
	clear_route_cells();
	_reset_state();
}

void WorldStreamer::set_load_radius(real_t p_radius) {
	load_radius = MAX(p_radius, real_t(0.0));
}

void WorldStreamer::set_unload_radius(real_t p_radius) {
	unload_radius = MAX(p_radius, real_t(0.0));
}

void WorldStreamer::set_velocity_hint(const Vector3 &p_velocity) {
	// Never let a corrupt network position poison cell priorities.
	if (!p_velocity.is_finite()) {
		return;
	}
	velocity_hint = p_velocity;
}

void WorldStreamer::set_lookahead_seconds(real_t p_seconds) {
	if (!Math::is_finite(p_seconds)) {
		return;
	}
	lookahead_seconds = CLAMP(p_seconds, real_t(0.0), real_t(4.0));
}

void WorldStreamer::set_view_direction(const Vector3 &p_direction) {
	if (!p_direction.is_finite()) {
		return; // Invalid camera/network data cannot corrupt streaming priority.
	}
	const Vector3 unit = p_direction.normalized();
	if (view_direction.is_equal_approx(unit)) {
		return;
	}
	view_direction = unit;
}

void WorldStreamer::set_view_priority(real_t p_weight) {
	if (!Math::is_finite(p_weight)) {
		return;
	}
	const real_t safe = CLAMP(p_weight, real_t(0.0), real_t(1.0));
	if (Math::is_equal_approx(view_priority, safe)) {
		return;
	}
	view_priority = safe;
}

void WorldStreamer::set_fast_view_refresh_degrees(real_t p_degrees) {
	if (!Math::is_finite(p_degrees)) {
		return;
	}
	fast_view_refresh_degrees = CLAMP(p_degrees, real_t(0.0), real_t(180.0));
}

void WorldStreamer::set_max_concurrent_loads(int p_count) {
	max_concurrent_loads = MAX(p_count, 1);
}

void WorldStreamer::set_max_instantiations_per_frame(int p_count) {
	max_instantiations_per_frame = MAX(p_count, 1);
}

void WorldStreamer::set_max_chunk_work_usec(int p_usec) {
	// 0 disables the wall-clock cap; the per-frame count still applies.
	max_chunk_work_usec = CLAMP(p_usec, 0, 1000000);
}

void WorldStreamer::set_update_interval(double p_seconds) {
	update_interval = MAX(p_seconds, 0.0);
}

void WorldStreamer::set_chunk_path_template(const String &p_template) {
	if (chunk_path_template == p_template) {
		return;
	}
	chunk_path_template = p_template;
	missing.clear();
	failed.clear();
	retry_states.clear();
}

void WorldStreamer::set_chunk_provider(const Callable &p_provider) {
	chunk_provider = p_provider;
	missing.clear();
	failed.clear();
	retry_states.clear();
}

void WorldStreamer::set_chunk_generator(const Callable &p_generator) {
	chunk_generator = p_generator;
	generate_queue.clear();
	missing.clear();
	failed.clear();
	retry_states.clear();
}

void WorldStreamer::set_chunk_parent(const NodePath &p_parent) {
	chunk_parent = p_parent;
}

void WorldStreamer::set_enabled(bool p_enabled) {
	enabled = p_enabled;
}

Vector3i WorldStreamer::world_to_cell(const Vector3 &p_position) const {
	return WorldStreamingGrid::world_to_cell(p_position, cell_size, _grid_axes());
}

Vector3 WorldStreamer::cell_to_world(const Vector3i &p_cell) const {
	return WorldStreamingGrid::cell_origin(p_cell, cell_size);
}

Node *WorldStreamer::get_chunk(const Vector3i &p_cell) const {
	HashMap<Vector3i, ObjectID>::ConstIterator it = loaded.find(p_cell);
	return it ? Object::cast_to<Node>(ObjectDB::get_instance(it->value)) : nullptr;
}

TypedArray<Vector3i> WorldStreamer::get_loaded_cells() const {
	TypedArray<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	return cells;
}

void WorldStreamer::refresh(bool p_retry) {
	// Explicit refresh also shares its budget across both kinds of chunks.
	active_instantiation_budget = get_effective_instantiations_per_frame();
	active_chunk_work_budget_usec = get_effective_chunk_work_usec();
	int refresh_budget = active_instantiation_budget;
	const uint64_t started_usec = OS::get_singleton()->get_ticks_usec();
	if (p_retry) {
		missing.clear();
		failed.clear();
		retry_states.clear();
		truncated_warned = false;
	}
	_poll_loading(refresh_budget, started_usec);
	_update_streaming();
	_run_generator_queue(refresh_budget, started_usec);
	_finish_chunk_work_frame();
	time_since_update = 0.0;
}

void WorldStreamer::unload_all() {
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	for (const Vector3i &cell : cells) {
		_unload_cell(cell);
	}
}

void WorldStreamer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_focus", "focus"), &WorldStreamer::set_focus);
	ClassDB::bind_method(D_METHOD("get_focus"), &WorldStreamer::get_focus);
	ClassDB::bind_method(D_METHOD("set_focus_position", "position"), &WorldStreamer::set_focus_position);
	ClassDB::bind_method(D_METHOD("get_focus_position"), &WorldStreamer::get_focus_position);
	ClassDB::bind_method(D_METHOD("set_axes", "axes"), &WorldStreamer::set_axes);
	ClassDB::bind_method(D_METHOD("get_axes"), &WorldStreamer::get_axes);
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &WorldStreamer::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &WorldStreamer::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_load_radius", "radius"), &WorldStreamer::set_load_radius);
	ClassDB::bind_method(D_METHOD("get_load_radius"), &WorldStreamer::get_load_radius);
	ClassDB::bind_method(D_METHOD("set_unload_radius", "radius"), &WorldStreamer::set_unload_radius);
	ClassDB::bind_method(D_METHOD("get_unload_radius"), &WorldStreamer::get_unload_radius);
	ClassDB::bind_method(D_METHOD("set_velocity_hint", "velocity"), &WorldStreamer::set_velocity_hint);
	ClassDB::bind_method(D_METHOD("get_velocity_hint"), &WorldStreamer::get_velocity_hint);
	ClassDB::bind_method(D_METHOD("set_lookahead_seconds", "seconds"), &WorldStreamer::set_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("get_lookahead_seconds"), &WorldStreamer::get_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("set_view_direction", "direction"), &WorldStreamer::set_view_direction);
	ClassDB::bind_method(D_METHOD("get_view_direction"), &WorldStreamer::get_view_direction);
	ClassDB::bind_method(D_METHOD("set_view_priority", "weight"), &WorldStreamer::set_view_priority);
	ClassDB::bind_method(D_METHOD("get_view_priority"), &WorldStreamer::get_view_priority);
	ClassDB::bind_method(D_METHOD("set_auxiliary_source", "position", "radius"), &WorldStreamer::set_auxiliary_source);
	ClassDB::bind_method(D_METHOD("clear_auxiliary_source"), &WorldStreamer::clear_auxiliary_source);
	ClassDB::bind_method(D_METHOD("has_auxiliary_source"), &WorldStreamer::has_auxiliary_source);
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_position"), &WorldStreamer::get_auxiliary_source_position);
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_radius"), &WorldStreamer::get_auxiliary_source_radius);
	ClassDB::bind_method(D_METHOD("set_route_cells", "cells"), &WorldStreamer::set_route_cells);
	ClassDB::bind_method(D_METHOD("get_route_cells"), &WorldStreamer::get_route_cells);
	ClassDB::bind_method(D_METHOD("clear_route_cells"), &WorldStreamer::clear_route_cells);
	ClassDB::bind_method(D_METHOD("set_fast_view_refresh_degrees", "degrees"), &WorldStreamer::set_fast_view_refresh_degrees);
	ClassDB::bind_method(D_METHOD("get_fast_view_refresh_degrees"), &WorldStreamer::get_fast_view_refresh_degrees);
	ClassDB::bind_method(D_METHOD("set_max_concurrent_loads", "count"), &WorldStreamer::set_max_concurrent_loads);
	ClassDB::bind_method(D_METHOD("get_max_concurrent_loads"), &WorldStreamer::get_max_concurrent_loads);
	ClassDB::bind_method(D_METHOD("set_max_instantiations_per_frame", "count"), &WorldStreamer::set_max_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_instantiations_per_frame"), &WorldStreamer::get_max_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_chunk_work_usec", "microseconds"), &WorldStreamer::set_max_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("get_max_chunk_work_usec"), &WorldStreamer::get_max_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("set_adaptive_chunk_budget_enabled", "enabled"), &WorldStreamer::set_adaptive_chunk_budget_enabled);
	ClassDB::bind_method(D_METHOD("is_adaptive_chunk_budget_enabled"), &WorldStreamer::is_adaptive_chunk_budget_enabled);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("advance_chunk_pressure", "pressure", "frame_delta"), &WorldStreamer::advance_chunk_pressure);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("calculate_adaptive_instantiation_slots", "configured", "pressure"), &WorldStreamer::calculate_adaptive_instantiation_slots);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("calculate_adaptive_chunk_work_usec", "configured", "pressure"), &WorldStreamer::calculate_adaptive_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("get_effective_chunk_work_usec"), &WorldStreamer::get_effective_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("get_effective_instantiations_per_frame"), &WorldStreamer::get_effective_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("get_streaming_frame_pressure_percent"), &WorldStreamer::get_streaming_frame_pressure_percent);
	ClassDB::bind_method(D_METHOD("get_last_frame_chunk_work_usec"), &WorldStreamer::get_last_frame_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("get_last_frame_chunk_attempt_count"), &WorldStreamer::get_last_frame_chunk_attempt_count);
	ClassDB::bind_method(D_METHOD("set_max_auto_retries", "count"), &WorldStreamer::set_max_auto_retries);
	ClassDB::bind_method(D_METHOD("get_max_auto_retries"), &WorldStreamer::get_max_auto_retries);
	ClassDB::bind_method(D_METHOD("set_retry_initial_delay", "seconds"), &WorldStreamer::set_retry_initial_delay);
	ClassDB::bind_method(D_METHOD("get_retry_initial_delay"), &WorldStreamer::get_retry_initial_delay);
	ClassDB::bind_method(D_METHOD("set_retry_max_delay", "seconds"), &WorldStreamer::set_retry_max_delay);
	ClassDB::bind_method(D_METHOD("get_retry_max_delay"), &WorldStreamer::get_retry_max_delay);
	ClassDB::bind_method(D_METHOD("get_retry_pending_count"), &WorldStreamer::get_retry_pending_count);
	ClassDB::bind_method(D_METHOD("set_update_interval", "seconds"), &WorldStreamer::set_update_interval);
	ClassDB::bind_method(D_METHOD("get_update_interval"), &WorldStreamer::get_update_interval);
	ClassDB::bind_method(D_METHOD("set_chunk_path_template", "template"), &WorldStreamer::set_chunk_path_template);
	ClassDB::bind_method(D_METHOD("get_chunk_path_template"), &WorldStreamer::get_chunk_path_template);
	ClassDB::bind_method(D_METHOD("set_chunk_generator", "generator"), &WorldStreamer::set_chunk_generator);
	ClassDB::bind_method(D_METHOD("get_chunk_generator"), &WorldStreamer::get_chunk_generator);
	ClassDB::bind_method(D_METHOD("set_chunk_provider", "provider"), &WorldStreamer::set_chunk_provider);
	ClassDB::bind_method(D_METHOD("get_chunk_provider"), &WorldStreamer::get_chunk_provider);
	ClassDB::bind_method(D_METHOD("set_chunk_parent", "parent"), &WorldStreamer::set_chunk_parent);
	ClassDB::bind_method(D_METHOD("get_chunk_parent"), &WorldStreamer::get_chunk_parent);
	ClassDB::bind_method(D_METHOD("set_position_chunks", "enabled"), &WorldStreamer::set_position_chunks);
	ClassDB::bind_method(D_METHOD("get_position_chunks"), &WorldStreamer::get_position_chunks);
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &WorldStreamer::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &WorldStreamer::is_enabled);

	ClassDB::bind_method(D_METHOD("world_to_cell", "position"), &WorldStreamer::world_to_cell);
	ClassDB::bind_method(D_METHOD("cell_to_world", "cell"), &WorldStreamer::cell_to_world);
	ClassDB::bind_method(D_METHOD("is_cell_loaded", "cell"), &WorldStreamer::is_cell_loaded);
	ClassDB::bind_method(D_METHOD("get_chunk", "cell"), &WorldStreamer::get_chunk);
	ClassDB::bind_method(D_METHOD("get_loaded_cells"), &WorldStreamer::get_loaded_cells);
	ClassDB::bind_method(D_METHOD("get_loaded_count"), &WorldStreamer::get_loaded_count);
	ClassDB::bind_method(D_METHOD("get_pending_count"), &WorldStreamer::get_pending_count);
	ClassDB::bind_method(D_METHOD("get_queued_generation_count"), &WorldStreamer::get_queued_generation_count);
	ClassDB::bind_method(D_METHOD("get_pending_visual_details_count"), &WorldStreamer::get_pending_visual_details_count);
	ClassDB::bind_method(D_METHOD("mark_visual_details_ready", "cell"), &WorldStreamer::mark_visual_details_ready);
	ClassDB::bind_method(D_METHOD("refresh", "retry"), &WorldStreamer::refresh, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("unload_all"), &WorldStreamer::unload_all);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "focus", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node2D,Node3D"), "set_focus", "get_focus");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "focus_position", PROPERTY_HINT_NONE, "suffix:m"), "set_focus_position", "get_focus_position");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "axes", PROPERTY_HINT_ENUM, "XZ (3D ground),XY (2D),XYZ (volume)"), "set_axes", "get_axes");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "1,100000,0.1,or_greater,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "load_radius", PROPERTY_HINT_RANGE, "0,100000,0.1,or_greater,suffix:m"), "set_load_radius", "get_load_radius");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "adaptive_chunk_budget_enabled"), "set_adaptive_chunk_budget_enabled", "is_adaptive_chunk_budget_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "unload_radius", PROPERTY_HINT_RANGE, "0,100000,0.1,or_greater,suffix:m"), "set_unload_radius", "get_unload_radius");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "velocity_hint", PROPERTY_HINT_NONE, "suffix:m/s"), "set_velocity_hint", "get_velocity_hint");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lookahead_seconds", PROPERTY_HINT_RANGE, "0,4,0.1,suffix:s"), "set_lookahead_seconds", "get_lookahead_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "view_direction", PROPERTY_HINT_NONE), "set_view_direction", "get_view_direction");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "view_priority", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_view_priority", "get_view_priority");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fast_view_refresh_degrees", PROPERTY_HINT_RANGE, "0,180,1,suffix:°"), "set_fast_view_refresh_degrees", "get_fast_view_refresh_degrees");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "chunk_path_template", PROPERTY_HINT_NONE, ""), "set_chunk_path_template", "get_chunk_path_template");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "chunk_parent", PROPERTY_HINT_NONE, ""), "set_chunk_parent", "get_chunk_parent");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "position_chunks"), "set_position_chunks", "get_position_chunks");
	ADD_GROUP("Budget", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_loads", PROPERTY_HINT_RANGE, "1,64,1,or_greater"), "set_max_concurrent_loads", "get_max_concurrent_loads");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instantiations_per_frame", PROPERTY_HINT_RANGE, "1,16,1,or_greater"), "set_max_instantiations_per_frame", "get_max_instantiations_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_chunk_work_usec", PROPERTY_HINT_RANGE, "0,1000000,100,suffix:us"), "set_max_chunk_work_usec", "get_max_chunk_work_usec");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "update_interval", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:s"), "set_update_interval", "get_update_interval");
	ADD_GROUP("Recovery", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_auto_retries", PROPERTY_HINT_RANGE, "0,8,1"), "set_max_auto_retries", "get_max_auto_retries");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "retry_initial_delay", PROPERTY_HINT_RANGE, "0.01,60,0.01,suffix:s"), "set_retry_initial_delay", "get_retry_initial_delay");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "retry_max_delay", PROPERTY_HINT_RANGE, "0.01,60,0.01,suffix:s"), "set_retry_max_delay", "get_retry_max_delay");

	ADD_SIGNAL(MethodInfo("chunk_loaded", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::OBJECT, "chunk", PROPERTY_HINT_RESOURCE_TYPE, "Node")));
	ADD_SIGNAL(MethodInfo("chunk_visual_details_ready", PropertyInfo(Variant::VECTOR3I, "cell")));
	ADD_SIGNAL(MethodInfo("chunk_unloaded", PropertyInfo(Variant::VECTOR3I, "cell")));
	ADD_SIGNAL(MethodInfo("chunk_load_failed", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::STRING, "path")));

	BIND_ENUM_CONSTANT(AXES_XZ);
	BIND_ENUM_CONSTANT(AXES_XY);
	BIND_ENUM_CONSTANT(AXES_XYZ);
}
