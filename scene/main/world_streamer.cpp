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
#include "core/math/math_funcs.h"
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

WorldStreamer::AuxiliaryCompletion WorldStreamer::_get_auxiliary_completion(bool p_require_visual_details) const {
	AuxiliaryCompletion result;
	Vector3 focus_position_local;
	// An inactive or remote source must never report false-positive readiness.
	if (!enabled || !_get_focus_position(focus_position_local) ||
			!_auxiliary_is_near_focus(focus_position_local)) {
		return result;
	}
	// Use exactly the same 64-cell cap and radius as auxiliary queue building.
	// The query is a snapshot: no scene work, resource requests or mutations.
	LocalVector<Vector3i> cells;
	WorldStreamingGrid::cells_in_radius(auxiliary_source_position,
			_auxiliary_effective_radius(), cell_size, _grid_axes(), cells, 64);
	for (const Vector3i &cell : cells) {
		++result.total;
		if (failed.has(cell)) {
			++result.failed;
			continue;
		}
		const ObjectID *id = loaded.getptr(cell);
		if (id != nullptr && ObjectDB::get_instance(*id) != nullptr) {
			if (!p_require_visual_details || !pending_visual_details.has(cell)) {
				++result.completed;
			}
		} else if (missing.has(cell)) {
			// Null from a procedural generator or absent scene is an intentional
			// empty cell, not something the game should wait for forever.
			++result.completed;
		}
	}
	return result;
}

real_t WorldStreamer::get_auxiliary_source_progress(bool p_require_visual_details) const {
	const AuxiliaryCompletion status = _get_auxiliary_completion(p_require_visual_details);
	return status.total > 0 ? real_t(status.completed) / real_t(status.total) : real_t(0.0);
}

bool WorldStreamer::is_auxiliary_source_ready(bool p_require_visual_details) const {
	const AuxiliaryCompletion status = _get_auxiliary_completion(p_require_visual_details);
	return status.total > 0 && status.failed == 0 && status.completed == status.total;
}

int WorldStreamer::get_auxiliary_source_pending_count(bool p_require_visual_details) const {
	const AuxiliaryCompletion status = _get_auxiliary_completion(p_require_visual_details);
	return status.total - status.completed - status.failed;
}

int WorldStreamer::get_auxiliary_source_failed_count() const {
	return _get_auxiliary_completion(false).failed;
}


WorldStreamer::AuxiliaryCompletion WorldStreamer::_get_focus_completion(
		bool p_require_visual_details, bool &r_truncated) const {
	AuxiliaryCompletion result;
	r_truncated = false;
	Vector3 position;
	if (!enabled || !_get_focus_position(position) ||
			!Math::is_finite(load_radius) || load_radius < 0.0 ||
			!Math::is_finite(cell_size) || cell_size <= 0.0) {
		return result;
	}

	// Use the *same* player-centered eligibility set and hard cap as the
	// actual streaming scheduler, but do not inspect the optional waypoint
	// source (whose progress is available from the auxiliary source API).
	LocalVector<Vector3i> wanted;
	WorldStreamingGrid::cells_in_radius(position, get_effective_load_radius(), cell_size,
			_grid_axes(), wanted, WorldStreamingGrid::MAX_CELLS, &r_truncated);
	for (const Vector3i &cell : wanted) {
		++result.total;
		if (failed.has(cell)) {
			++result.failed;
			continue;
		}
		const ObjectID *id = loaded.getptr(cell);
		if (id != nullptr && ObjectDB::get_instance(*id) != nullptr) {
			if (!p_require_visual_details || !pending_visual_details.has(cell)) {
				++result.completed;
			}
		} else if (missing.has(cell)) {
			// A procedural generator's intentional empty result is complete.
			++result.completed;
		}
	}
	return result;
}

Dictionary WorldStreamer::get_focus_streaming_status(bool p_require_visual_details) const {
	bool truncated = false;
	const AuxiliaryCompletion status = _get_focus_completion(p_require_visual_details, truncated);
	const int pending = status.total - status.completed - status.failed;
	const bool ready = status.total > 0 && !truncated && status.failed == 0 && pending == 0;
	Dictionary result;
	result["total"] = status.total;
	result["completed"] = status.completed;
	result["pending"] = pending;
	result["failed"] = status.failed;
	result["truncated"] = truncated;
	result["ready"] = ready;
	// Fail closed rather than claiming 100% completion for a truncated grid.
	result["progress"] = status.total > 0 && !truncated ?
			real_t(status.completed) / real_t(status.total) : real_t(0.0);
	return result;
}

bool WorldStreamer::_cell_requested(const Vector3 &p_focus, const Vector3i &p_cell) const {
	if (WorldStreamingGrid::distance_to_cell(p_focus, p_cell, cell_size, _grid_axes()) <= get_effective_load_radius()) {
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
		const ObjectID *old_id = loaded.getptr(cell);
		if (old_id != nullptr) {
			cache_ineligible_nodes.erase(*old_id);
		}
		loaded.erase(cell);
		const bool *active = simulation_active_cells.getptr(cell);
		if (active != nullptr && !*active) {
			--simulation_inactive_count;
		}
		simulation_active_cells.erase(cell);
		if (applied_tick_intervals.has(cell)) {
			applied_tick_intervals.erase(cell);
			--tick_throttled_count;
		}
		pending_visual_details.erase(cell);
		emit_signal(SNAME("chunk_unloaded"), cell);
	}
}

// Cached nodes are detached from the scene tree (no render/physics/process
// cost), but still own their resources. Keep the cap strict and evict the
// oldest entry deterministically whenever the cache grows or shrinks.
void WorldStreamer::_trim_cached_chunks() {
	while (int(cached_chunks.size()) > max_cached_chunks ||
			(max_cached_chunk_bytes > 0 && cached_chunk_bytes > max_cached_chunk_bytes)) {
		// Protect cells the current focus/nearby source is requesting. Without
		// this, unloading the current chunk first would evict the previous
		// destination immediately even on a one-slot cache backtrack.
		Vector3 focus_position_local;
		const bool have_focus = _get_focus_position(focus_position_local);
		bool found = false;
		bool oldest_requested = true;
		Vector3i oldest_cell;
		uint64_t oldest_age = 0;
		for (const KeyValue<Vector3i, CachedChunk> &entry : cached_chunks) {
			const Vector3i &cell = entry.key;
			const bool requested = have_focus && _cell_requested(focus_position_local, cell);
			const bool tie_before = cell.x < oldest_cell.x ||
					(cell.x == oldest_cell.x && (cell.y < oldest_cell.y ||
							(cell.y == oldest_cell.y && cell.z < oldest_cell.z)));
			const bool older = entry.value.age < oldest_age ||
					(entry.value.age == oldest_age && tie_before);
			if (!found || (oldest_requested && !requested) ||
					(requested == oldest_requested && older)) {
				oldest_cell = cell;
				oldest_age = entry.value.age;
				oldest_requested = requested;
				found = true;
			}
		}
		if (!found) {
			break;
		}
		const CachedChunk entry = cached_chunks[oldest_cell];
		cached_chunk_bytes -= entry.estimated_bytes;
		cached_chunks.erase(oldest_cell);
		Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(entry.node_id));
		if (chunk && !chunk->is_queued_for_deletion()) {
			chunk->queue_free();
		}
		if (cache_evictions < INT32_MAX) {
			++cache_evictions;
		}
	}
}

void WorldStreamer::_expire_cached_chunks(bool p_ignore_budget) {
	last_cached_expiration_count = 0;
	last_deferred_cached_expiration_count = 0;
	last_cached_expiration_work_usec = 0;
	if (cached_chunk_retention_seconds <= real_t(0.0) || cached_chunks.is_empty()) {
		return;
	}
	// No more than 16 entries. Collect cells before changing the hash map.
	const uint64_t started_usec = OS::get_singleton()->get_ticks_usec();
	LocalVector<Vector3i> expired;
	for (const KeyValue<Vector3i, CachedChunk> &entry : cached_chunks) {
		if (cached_chunk_elapsed_seconds - entry.value.retained_at_seconds >= double(cached_chunk_retention_seconds)) {
			expired.push_back(entry.key);
		}
	}
	while (!expired.is_empty()) {
		// Destroy at least one expired root. Destructors are indivisible,
		// so the microsecond budget is deliberately a soft deadline.
		if (!p_ignore_budget && last_cached_expiration_count > 0 &&
				((max_cached_expirations_per_frame > 0 && last_cached_expiration_count >= max_cached_expirations_per_frame) ||
						(max_cached_expiration_work_usec > 0 &&
								OS::get_singleton()->get_ticks_usec() - started_usec >= uint64_t(max_cached_expiration_work_usec)))) {
			break;
		}
		// Always release the oldest expired root first, with stable cell
		// coordinates as a tie-break instead of hash iteration order.
		uint32_t oldest_index = 0;
		for (uint32_t i = 1; i < expired.size(); i++) {
			const CachedChunk *candidate = cached_chunks.getptr(expired[i]);
			const CachedChunk *oldest = cached_chunks.getptr(expired[oldest_index]);
			if (candidate == nullptr || oldest == nullptr) {
				continue;
			}
			const Vector3i &a = expired[i];
			const Vector3i &b = expired[oldest_index];
			if (candidate->retained_at_seconds < oldest->retained_at_seconds ||
					(candidate->retained_at_seconds == oldest->retained_at_seconds &&
							(a.x < b.x || (a.x == b.x && (a.y < b.y || (a.y == b.y && a.z < b.z)))))) {
				oldest_index = i;
			}
		}
		const Vector3i cell = expired[oldest_index];
		expired.remove_at(oldest_index);
		const CachedChunk *entry = cached_chunks.getptr(cell);
		if (entry == nullptr) {
			continue;
		}
		const ObjectID id = entry->node_id;
		cached_chunk_bytes -= entry->estimated_bytes;
		cached_chunks.erase(cell);
		Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(id));
		if (chunk && !chunk->is_queued_for_deletion()) {
			if (chunk->get_parent() == nullptr) {
				memdelete(chunk); // Detached scene: release even outside SceneTree.
			} else {
				chunk->queue_free();
			}
		}
		if (cache_expirations < INT32_MAX) {
			++cache_expirations;
		}
		++last_cached_expiration_count;
	}
	last_deferred_cached_expiration_count = int(expired.size());
	last_cached_expiration_work_usec = int64_t(OS::get_singleton()->get_ticks_usec() - started_usec);
}

void WorldStreamer::_discard_cached_chunks() {
	for (const KeyValue<Vector3i, CachedChunk> &entry : cached_chunks) {
		Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(entry.value.node_id));
		if (chunk && chunk->get_parent() == nullptr && !chunk->is_queued_for_deletion()) {
			// Detached nodes cannot rely on their former parent for cleanup.
			memdelete(chunk);
		}
	}
	cached_chunks.clear();
	cached_chunk_bytes = 0;
}

void WorldStreamer::clear_cached_chunks() {
	_discard_cached_chunks();
	cache_clock = 0;
	cached_chunk_elapsed_seconds = 0.0;
	cache_hits = 0;
	cache_evictions = 0;
	cache_expirations = 0;
	last_cached_expiration_count = 0;
	last_deferred_cached_expiration_count = 0;
	last_cached_expiration_work_usec = 0;
}

void WorldStreamer::set_max_cached_chunks(int p_count) {
	const int bounded = CLAMP(p_count, 0, 16);
	if (max_cached_chunks == bounded) {
		return;
	}
	max_cached_chunks = bounded;
	_trim_cached_chunks();
}

void WorldStreamer::set_max_cached_expirations_per_frame(int p_count) {
	max_cached_expirations_per_frame = CLAMP(p_count, 0, 16);
}

void WorldStreamer::set_max_cached_expiration_work_usec(int p_usec) {
	max_cached_expiration_work_usec = CLAMP(p_usec, 0, 1000000);
}

void WorldStreamer::set_cached_chunk_retention_seconds(real_t p_seconds) {
	if (!Math::is_finite(p_seconds)) {
		return;
	}
	const real_t bounded = CLAMP(p_seconds, real_t(0.0), real_t(120.0));
	if (Math::is_equal_approx(cached_chunk_retention_seconds, bounded)) {
		return;
	}
	cached_chunk_retention_seconds = bounded;
	_expire_cached_chunks(true); // Preserve immediate cleanup on explicit TTL changes.
}

void WorldStreamer::advance_cached_chunk_retention(real_t p_delta_seconds) {
	if (cached_chunk_retention_seconds <= real_t(0.0) || cached_chunks.is_empty() ||
			!Math::is_finite(p_delta_seconds) || p_delta_seconds <= real_t(0.0)) {
		last_cached_expiration_count = 0;
		last_deferred_cached_expiration_count = 0;
		last_cached_expiration_work_usec = 0;
		return;
	}
	// Huge/corrupt frame deltas cannot poison the floating point clock.
	cached_chunk_elapsed_seconds += MIN(double(p_delta_seconds), 120.0);
	_expire_cached_chunks();
}

void WorldStreamer::set_max_cached_chunk_bytes(int64_t p_bytes) {
	const int64_t bounded = CLAMP(p_bytes, int64_t(0), int64_t(268435456));
	if (max_cached_chunk_bytes == bounded) {
		return;
	}
	// Entries admitted while size tracking was disabled carry no estimate.
	// Discard them before enforcing a newly enabled memory budget.
	if (max_cached_chunk_bytes == 0 && bounded > 0) {
		_discard_cached_chunks();
	}
	max_cached_chunk_bytes = bounded;
	_trim_cached_chunks();
}

WorldStreamer::~WorldStreamer() {
	_discard_cached_chunks();
}

bool WorldStreamer::_restore_cached_chunk(const Vector3i &p_cell) {
	const CachedChunk *entry = cached_chunks.getptr(p_cell);
	if (entry == nullptr) {
		return false;
	}
	const ObjectID id = entry->node_id;
	cached_chunk_bytes -= entry->estimated_bytes;
	cached_chunks.erase(p_cell);
	Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(id));
	if (chunk == nullptr || chunk->is_queued_for_deletion() || chunk->get_parent() != nullptr) {
		return false;
	}
	// Re-enter through the normal adoption path: initial simulation tier,
	// optional staged-detail tracking and chunk_loaded always apply.
	if (!_adopt_chunk(p_cell, chunk)) {
		memdelete(chunk);
		return false;
	}
	if (chunk->has_method(SNAME("on_streaming_cache_restored"))) {
		chunk->call(SNAME("on_streaming_cache_restored"));
	}
	if (cache_hits < INT32_MAX) {
		++cache_hits;
	}
	return true;
}

void WorldStreamer::_unload_cell(const Vector3i &p_cell, bool p_allow_cache) {
	HashMap<Vector3i, ObjectID>::Iterator it = loaded.find(p_cell);
	if (!it) {
		return;
	}
	const bool generator_compatible = !cache_ineligible_nodes.has(it->value);
	cache_ineligible_nodes.erase(it->value);
	Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(it->value));
	loaded.remove(it);
	const bool *active = simulation_active_cells.getptr(p_cell);
	if (active != nullptr && !*active) {
		--simulation_inactive_count;
	}
	simulation_active_cells.erase(p_cell);
	if (applied_tick_intervals.has(p_cell)) {
		applied_tick_intervals.erase(p_cell);
		--tick_throttled_count;
	}
	pending_visual_details.erase(p_cell);
	if (chunk) {
		// Only generator-owned roots that opt in may remain cached. Packed
		// scenes and mutable/authoritative chunks keep legacy free-on-unload.
		bool may_cache = p_allow_cache && generator_compatible && max_cached_chunks > 0 && chunk_generator.is_valid() &&
				chunk->get_parent() == _get_parent_for_chunks() && !chunk->is_queued_for_deletion() &&
				chunk->has_method(SNAME("can_cache_streaming_chunk")) &&
				bool(chunk->call(SNAME("can_cache_streaming_chunk")));
		int64_t estimated_bytes = 0;
		if (may_cache && max_cached_chunk_bytes > 0) {
			// An active cost budget must never assume unpriced scenes are free.
			if (!chunk->has_method(SNAME("get_streaming_cache_cost_bytes"))) {
				may_cache = false;
			} else {
				const Variant cost = chunk->call(SNAME("get_streaming_cache_cost_bytes"));
				if (cost.get_type() != Variant::INT) {
					may_cache = false;
				} else {
					estimated_bytes = int64_t(cost);
					may_cache = estimated_bytes > 0 && estimated_bytes <= max_cached_chunk_bytes;
				}
			}
		}
		if (chunk->get_parent()) {
			chunk->get_parent()->remove_child(chunk);
		}
		if (may_cache && !chunk->is_queued_for_deletion()) {
			CachedChunk entry;
			entry.node_id = chunk->get_instance_id();
			entry.age = ++cache_clock;
			entry.estimated_bytes = estimated_bytes;
			entry.retained_at_seconds = cached_chunk_elapsed_seconds;
			cached_chunks[p_cell] = entry;
			cached_chunk_bytes += estimated_bytes;
			_trim_cached_chunks();
		} else {
			chunk->queue_free();
		}
	}
	emit_signal(SNAME("chunk_unloaded"), p_cell);
}

void WorldStreamer::_set_chunk_simulation_active(const Vector3i &p_cell, bool p_active) {
	Node *chunk = get_chunk(p_cell);
	if (chunk == nullptr) {
		return;
	}
	const bool *previous = simulation_active_cells.getptr(p_cell);
	if (previous != nullptr && *previous == p_active) {
		return;
	}
	simulation_active_cells[p_cell] = p_active;
	simulation_inactive_count += p_active ? -1 : 1;
	// The scene explicitly owns what "simulation" means; do not toggle
	// process modes or physics on arbitrary descendants from the engine.
	if (chunk->has_method(SNAME("set_streaming_simulation_active"))) {
		chunk->call(SNAME("set_streaming_simulation_active"), p_active);
	}
	emit_signal(SNAME("chunk_simulation_changed"), p_cell, p_active);
}

void WorldStreamer::_update_simulation(const Vector3 &p_focus) {
	if (simulation_radius < real_t(0.0) && simulation_inactive_count == 0) {
		return; // No per-cell scan or callbacks for legacy worlds.
	}
	int remaining = max_simulation_transitions_per_update;
	// Activate nearest chunks first so a player entering a region does not
	// compete with distant cosmetic shutdowns. Deterministic tie breaking
	// keeps the outcome stable even if the hash map iteration order changes.
	for (int pass = 0; pass < 2 && remaining > 0; ++pass) {
		const bool activating = pass == 0;
		while (remaining > 0) {
			bool found = false;
			Vector3i best;
			real_t best_distance = 0.0;
			for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
				const bool *active_ptr = simulation_active_cells.getptr(entry.key);
				const bool active = active_ptr == nullptr || *active_ptr;
				const real_t distance = WorldStreamingGrid::distance_to_cell(p_focus, entry.key, cell_size, _grid_axes());
				const bool desired = simulation_radius < real_t(0.0) ||
						distance <= simulation_radius + (active ? simulation_hysteresis : real_t(0.0));
				if (active == desired || desired != activating) {
					continue;
				}
				const Vector3i &cell = entry.key;
				if (!found || (activating ? distance < best_distance : distance > best_distance) ||
						(distance == best_distance && (cell.x < best.x ||
								(cell.x == best.x && (cell.y < best.y || (cell.y == best.y && cell.z < best.z)))))) {
					best = cell;
					best_distance = distance;
					found = true;
				}
			}
			if (!found) {
				break;
			}
			_set_chunk_simulation_active(best, activating);
			--remaining;
		}
	}
}

void WorldStreamer::_set_chunk_tick_interval(const Vector3i &p_cell, real_t p_seconds) {
	Node *chunk = get_chunk(p_cell);
	if (chunk == nullptr || !chunk->has_method(SNAME("set_streaming_tick_interval"))) {
		return;
	}
	const real_t *old_ptr = applied_tick_intervals.getptr(p_cell);
	const real_t old_value = old_ptr ? *old_ptr : real_t(0.0);
	if (old_value == p_seconds) {
		return;
	}
	chunk->call(SNAME("set_streaming_tick_interval"), p_seconds);
	if (old_value > real_t(0.0)) {
		--tick_throttled_count;
	}
	if (p_seconds > real_t(0.0)) {
		applied_tick_intervals[p_cell] = p_seconds;
		++tick_throttled_count;
	} else {
		applied_tick_intervals.erase(p_cell);
	}
	emit_signal(SNAME("chunk_tick_interval_changed"), p_cell, p_seconds);
}

void WorldStreamer::_update_tick_intervals(const Vector3 &p_focus) {
	if (tick_throttle_radius < real_t(0.0) && tick_throttled_count == 0) {
		return; // Legacy worlds never scan chunks for rate throttling.
	}
	int remaining = max_tick_throttle_transitions_per_update;
	// Restore near-cell responsiveness first; throttle distant cosmetic
	// work second. Each transition consumes exactly one scheduler slot.
	for (int pass = 0; pass < 2 && remaining > 0; ++pass) {
		const bool restore_near = pass == 0;
		while (remaining > 0) {
			bool found = false;
			Vector3i best;
			real_t best_distance = 0.0;
			real_t best_interval = 0.0;
			for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
				Node *chunk = Object::cast_to<Node>(ObjectDB::get_instance(entry.value));
				if (chunk == nullptr || !chunk->has_method(SNAME("set_streaming_tick_interval"))) {
					continue;
				}
				const real_t *current_ptr = applied_tick_intervals.getptr(entry.key);
				const real_t current = current_ptr ? *current_ptr : real_t(0.0);
				const real_t distance = WorldStreamingGrid::distance_to_cell(p_focus, entry.key, cell_size, _grid_axes());
				const bool far = tick_throttle_radius >= real_t(0.0) && tick_throttle_interval > real_t(0.0) &&
						distance > tick_throttle_radius + (current > real_t(0.0) ? real_t(0.0) : tick_throttle_hysteresis);
				const real_t desired = far ? tick_throttle_interval : real_t(0.0);
				if (current == desired || (desired == real_t(0.0)) != restore_near) {
					continue;
				}
				const Vector3i &cell = entry.key;
				const bool tie_before = cell.x < best.x ||
						(cell.x == best.x && (cell.y < best.y || (cell.y == best.y && cell.z < best.z)));
				if (!found || (restore_near ? distance < best_distance : distance > best_distance) ||
						(distance == best_distance && tie_before)) {
					best = cell;
					best_distance = distance;
					best_interval = desired;
					found = true;
				}
			}
			if (!found) {
				break;
			}
			_set_chunk_tick_interval(best, best_interval);
			--remaining;
		}
	}
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
	// Set the initial tier before _ready() without consuming a transition:
	// the chunk instantiation itself is already covered by the work budget.
	Vector3 simulation_focus;
	const bool simulation_active = simulation_radius < real_t(0.0) ||
			!_get_focus_position(simulation_focus) ||
			WorldStreamingGrid::distance_to_cell(simulation_focus, p_cell, cell_size, _grid_axes()) <= simulation_radius;
	if (simulation_radius >= real_t(0.0) && p_chunk->has_method(SNAME("set_streaming_simulation_active"))) {
		p_chunk->call(SNAME("set_streaming_simulation_active"), simulation_active);
	}
	// Initial cosmetic rate is selected before entering the scene tree.
	// A new chunk is already charged to the normal generation work budget.
	real_t initial_tick_interval = 0.0;
	if (tick_throttle_radius >= real_t(0.0) && tick_throttle_interval > real_t(0.0) &&
			p_chunk->has_method(SNAME("set_streaming_tick_interval"))) {
		Vector3 tick_focus;
		if (_get_focus_position(tick_focus) &&
				WorldStreamingGrid::distance_to_cell(tick_focus, p_cell, cell_size, _grid_axes()) >
					tick_throttle_radius + tick_throttle_hysteresis) {
			initial_tick_interval = tick_throttle_interval;
		}
		p_chunk->call(SNAME("set_streaming_tick_interval"), initial_tick_interval);
	}
	Node *parent = _get_parent_for_chunks();
	parent->add_child(p_chunk);
	loaded[p_cell] = p_chunk->get_instance_id();
	if (initial_tick_interval > real_t(0.0)) {
		applied_tick_intervals[p_cell] = initial_tick_interval;
		++tick_throttled_count;
	}
	if (simulation_radius >= real_t(0.0)) {
		simulation_active_cells[p_cell] = simulation_active;
		if (!simulation_active) {
			++simulation_inactive_count;
		}
	}
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
	// A cache hit still consumes the same integration slot and CPU time slice
	// as a new scene: reattaching a subtree may be expensive.
	if (_restore_cached_chunk(cell)) {
		return;
	}
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

int64_t WorldStreamer::update_chunk_work_estimate(int64_t p_previous, int64_t p_sample_usec) {
	// Bounded 1/4 EMA: no allocations, callbacks, or cross-stage bias.
	const int64_t sample = CLAMP(p_sample_usec, int64_t(0), int64_t(1000000));
	const int64_t previous = CLAMP(p_previous, int64_t(0), int64_t(1000000));
	if (sample == 0) {
		return previous; // A sub-microsecond call is not a reliable cost sample.
	}
	return previous == 0 ? sample : (3 * previous + sample + 2) / 4;
}

bool WorldStreamer::should_defer_predicted_chunk_work(int p_budget_usec, int p_previous_attempts,
		int64_t p_work_spent_usec, int64_t p_estimated_next_usec) {
	// Always allow the first necessary task, even when it is indivisible
	// and more expensive than the configured soft frame budget.
	if (p_budget_usec <= 0 || p_previous_attempts <= 0 || p_estimated_next_usec <= 0) {
		return false;
	}
	const int64_t remaining = int64_t(p_budget_usec) - MAX(p_work_spent_usec, int64_t(0));
	return remaining < p_estimated_next_usec;
}

bool WorldStreamer::_should_defer_predicted_work(bool p_generator) const {
	if (!predictive_chunk_work_budget_enabled) {
		return false;
	}
	return should_defer_predicted_chunk_work(active_chunk_work_budget_usec, frame_chunk_attempt_count,
			frame_chunk_work_usec, p_generator ? estimated_generator_work_usec : estimated_finalization_work_usec);
}

void WorldStreamer::_record_chunk_work(uint64_t p_started_usec, bool p_generator) {
	const uint64_t now = OS::get_singleton()->get_ticks_usec();
	const int64_t elapsed = int64_t(MIN(now >= p_started_usec ? now - p_started_usec : 0, uint64_t(1000000000)));
	frame_chunk_work_usec = MIN(int64_t(1000000000), frame_chunk_work_usec + elapsed);
	int64_t &estimate = p_generator ? estimated_generator_work_usec : estimated_finalization_work_usec;
	estimate = update_chunk_work_estimate(estimate, elapsed);
	frame_chunk_attempt_count++;
}

void WorldStreamer::_finish_chunk_work_frame() {
	last_frame_chunk_work_usec = frame_chunk_work_usec;
	last_frame_chunk_attempt_count = frame_chunk_attempt_count;
	last_predicted_deferred_count = frame_predicted_deferred_count;
	frame_chunk_work_usec = 0;
	frame_chunk_attempt_count = 0;
	frame_predicted_deferred_count = 0;
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

int WorldStreamer::calculate_adaptive_unload_slots(int p_configured, double p_pressure) {
	const int configured = CLAMP(p_configured, 0, 64);
	if (configured == 0) {
		return 0; // Unlimited legacy cleanup, even under pressure.
	}
	const double pressure = Math::is_finite(p_pressure) ? CLAMP(p_pressure, 0.0, 1.0) : 0.0;
	if (pressure >= 0.8) {
		return MAX(1, (configured + 1) / 2);
	}
	if (pressure >= 0.4) {
		return MAX(1, (configured * 3 + 3) / 4);
	}
	return configured;
}

int WorldStreamer::get_effective_unloads_per_update() const {
	return adaptive_chunk_budget_enabled ?
			calculate_adaptive_unload_slots(max_unloads_per_update, streaming_frame_pressure) :
			max_unloads_per_update;
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
		const Vector3i cell = generate_queue[consumed];
		if (loaded.has(cell) || !have_focus || !_cell_requested(position, cell)) {
			consumed++; // Irrelevant cells are discarded without spending CPU slots.
			continue;
		}
		// Forecast a second or later procedural call before starting it.
		// Both the generator and threaded finalization share the same
		// measured work and instantiation counters for this frame.
		if (_should_defer_predicted_work(true)) {
			frame_predicted_deferred_count++;
			break; // Keep the next still-wanted cell queued for a later frame.
		}
		consumed++;
		// Generator calls can be expensive even when a chunk is missing or fails.
		r_instantiation_budget--;
		const uint64_t generation_started_usec = OS::get_singleton()->get_ticks_usec();
		_generate_cell(cell);
		_record_chunk_work(generation_started_usec, true);
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
				velocity_hint, lookahead_seconds, MIN(get_effective_load_radius() * real_t(0.4), cell_size),
				view_direction, view_priority, cell_size, _grid_axes(), view_cone_half_angle_degrees);
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
		if (_should_defer_predicted_work(false)) {
			// The finished resource stays in the bounded ready queue until
			// the next frame; no synchronous scene activation this frame.
			frame_predicted_deferred_count++;
			continue;
		}
		r_instantiation_budget--;
		loading.erase(cell);
		const uint64_t finalization_started_usec = OS::get_singleton()->get_ticks_usec();
		const bool finalized = _finalize_chunk(cell, path);
		_record_chunk_work(finalization_started_usec, false);
		if (!finalized) {
			_record_failure(cell, path);
		}
	}
}

void WorldStreamer::_update_streaming() {
	last_unload_work_usec = 0;
	last_unload_count = 0;
	last_deferred_unload_count = 0;
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
	const bool auxiliary_near = _auxiliary_is_near_focus(position);
	if (max_unloads_per_update == 0) {
		// Preserve the legacy O(N) release path without building another
		// candidate vector or allocating selection metadata.
		for (const Vector3i &cell : to_unload) {
			if (auxiliary_near &&
					WorldStreamingGrid::distance_to_cell(auxiliary_source_position, cell, cell_size, _grid_axes()) <= _auxiliary_effective_radius()) {
				continue;
			}
			_unload_cell(cell);
			++last_unload_count;
		}
	} else {
		LocalVector<Vector3i> expired;
		for (const Vector3i &cell : to_unload) {
			// A nearby secondary source still protects the same cells.
			if (auxiliary_near &&
					WorldStreamingGrid::distance_to_cell(auxiliary_source_position, cell, cell_size, _grid_axes()) <= _auxiliary_effective_radius()) {
				continue;
			}
			expired.push_back(cell);
		}
		const int count = int(expired.size());
		const int grant = MIN(count, get_effective_unloads_per_update());
		const uint64_t unload_started_usec = count > 0 ? OS::get_singleton()->get_ticks_usec() : 0;
		if (grant == count && max_unload_work_usec == 0) {
			// Preserve the fast path when no time-slicing is requested.
			for (const Vector3i &cell : expired) {
				_unload_cell(cell);
			}
			last_unload_count = count;
		} else {
			// With a budget, unload farthest first. Avoid sorting the entire
			// resident grid after teleports: select at most 64 distant cells,
			// in O(expired * grant) comparisons and O(grant) metadata.
			// Stable coordinate ties make tests/replays deterministic.
			HashSet<Vector3i> selected;
			for (int i = 0; i < grant; ++i) {
				// Check after the first complete removal. A chunk's scene-tree
				// detach and signals are indivisible and may exceed the soft cap.
				if (i > 0 && max_unload_work_usec > 0 &&
						OS::get_singleton()->get_ticks_usec() - unload_started_usec >= uint64_t(max_unload_work_usec)) {
					break;
				}
				bool found = false;
				Vector3i best;
				real_t best_distance = 0.0;
				for (const Vector3i &cell : expired) {
					if (selected.has(cell)) {
						continue;
					}
					const real_t distance = WorldStreamingGrid::distance_to_cell(position, cell, cell_size, _grid_axes());
					const bool tie_before = cell.x < best.x ||
							(cell.x == best.x && (cell.y < best.y || (cell.y == best.y && cell.z < best.z)));
					if (!found || distance > best_distance || (distance == best_distance && tie_before)) {
						best = cell;
						best_distance = distance;
						found = true;
					}
				}
				if (!found) {
					break;
				}
				selected.insert(best);
				_unload_cell(best);
				++last_unload_count;
			}
		}
		last_deferred_unload_count = count - last_unload_count;
		if (count > 0) {
			last_unload_work_usec = OS::get_singleton()->get_ticks_usec() - unload_started_usec;
		}
	}

	_update_simulation(position);
	_update_tick_intervals(position);

	LocalVector<Vector3i> wanted;
	bool truncated = false;
	WorldStreamingGrid::cells_in_radius(position, get_effective_load_radius(), cell_size, _grid_axes(), wanted, WorldStreamingGrid::MAX_CELLS, &truncated);
	// Camera/motion hints reprioritize only the main focus cells; the
	// optional explicit auxiliary source may add a separately bounded set.
	// Predicted velocity never enlarges resident world memory.

	WorldStreamingGrid::prioritize_cells_for_motion_and_view(wanted, position,
			velocity_hint, lookahead_seconds, MIN(get_effective_load_radius() * real_t(0.4), cell_size),
			view_direction, view_priority, cell_size, _grid_axes(), view_cone_half_angle_degrees);
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
	// A grid/axis reset must never reuse stale cell geometry.
	clear_cached_chunks();
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	for (const Vector3i &cell : cells) {
		_unload_cell(cell, false);
	}
	// In-flight requests finish on their own; their results are released when polled.
	missing.clear();
	failed.clear();
	retry_states.clear();
	generate_queue.clear();
	pending_visual_details.clear();
	simulation_active_cells.clear();
	applied_tick_intervals.clear();
	tick_throttled_count = 0;
	cache_ineligible_nodes.clear();
	last_unload_count = 0;
	last_deferred_unload_count = 0;
	last_unload_work_usec = 0;
	simulation_inactive_count = 0;
	last_queued_view_direction = Vector3();
	truncated_warned = false;
	streaming_frame_pressure = 0.0;
	frame_chunk_work_usec = 0;
	last_frame_chunk_work_usec = 0;
	frame_chunk_attempt_count = 0;
	last_frame_chunk_attempt_count = 0;
	estimated_generator_work_usec = 0;
	estimated_finalization_work_usec = 0;
	frame_predicted_deferred_count = 0;
	last_predicted_deferred_count = 0;
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
			// Detached opt-in roots are not scene children and require explicit cleanup.
			clear_cached_chunks();
			if (chunk_parent.is_empty()) {
				// Chunks are our children and go away with us; just forget them.
				loaded.clear();
				last_unload_count = 0;
				last_deferred_unload_count = 0;
				cache_ineligible_nodes.clear();
				simulation_active_cells.clear();
				applied_tick_intervals.clear();
				tick_throttled_count = 0;
				simulation_inactive_count = 0;
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
			// Grow the requested area before reconciling the current queue.
			// The ordinary streamer cadence still caps scheduling work.
			advance_loading_range_ramp(get_process_delta_time());
			// Expire stale detached scenes even while the focus is stationary
			// and the ordinary streaming refresh has no pending work.
			advance_cached_chunk_retention(get_process_delta_time());
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

real_t WorldStreamer::get_effective_load_radius() const {
	if (loading_range_area_fraction >= real_t(1.0) || load_radius <= real_t(0.0)) {
		return load_radius;
	}
	// On the XZ/XY planes, reducing area to 25% halves the distance.
	// A 3D cubic grid instead scales by the cube root of volume.
	const real_t exponent = axes == AXES_XYZ ? real_t(1.0 / 3.0) : real_t(0.5);
	return load_radius * Math::pow(loading_range_area_fraction, exponent);
}

void WorldStreamer::begin_loading_range_ramp(real_t p_initial_area_fraction, real_t p_delay_seconds, real_t p_duration_seconds) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_initial_area_fraction) ||
					!Math::is_finite(p_delay_seconds) || !Math::is_finite(p_duration_seconds),
			"WorldStreamer loading range ramp parameters must be finite.");
	// Never exclude the player's own terrain for an initial zero-area plan.
	loading_ramp_initial_fraction = CLAMP(p_initial_area_fraction, real_t(0.05), real_t(1.0));
	loading_ramp_delay = CLAMP(p_delay_seconds, real_t(0.0), real_t(60.0));
	loading_ramp_duration = CLAMP(p_duration_seconds, real_t(0.0), real_t(120.0));
	loading_ramp_elapsed = 0.0;
	loading_ramp_active = loading_ramp_initial_fraction < real_t(1.0) &&
			(loading_ramp_delay > real_t(0.0) || loading_ramp_duration > real_t(0.0));
	loading_range_area_fraction = loading_ramp_active ? loading_ramp_initial_fraction : real_t(1.0);
	// Rebuild eligible work on the next scheduler tick; no scene creation here.
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::advance_loading_range_ramp(real_t p_delta_seconds) {
	if (!loading_ramp_active || !Math::is_finite(p_delta_seconds) || p_delta_seconds <= real_t(0.0)) {
		return;
	}
	loading_ramp_elapsed = MIN(loading_ramp_elapsed + p_delta_seconds, loading_ramp_delay + loading_ramp_duration);
	if (loading_ramp_elapsed < loading_ramp_delay) {
		return;
	}
	const real_t progress = loading_ramp_duration > real_t(0.0) ?
			CLAMP((loading_ramp_elapsed - loading_ramp_delay) / loading_ramp_duration, real_t(0.0), real_t(1.0)) : real_t(1.0);
	loading_range_area_fraction = Math::lerp(loading_ramp_initial_fraction, real_t(1.0), progress);
	if (progress >= real_t(1.0)) {
		loading_range_area_fraction = real_t(1.0);
		loading_ramp_active = false;
	}
}

void WorldStreamer::cancel_loading_range_ramp() {
	if (!loading_ramp_active && loading_range_area_fraction >= real_t(1.0)) {
		return;
	}
	loading_ramp_active = false;
	loading_range_area_fraction = real_t(1.0);
	loading_ramp_elapsed = loading_ramp_delay + loading_ramp_duration;
	time_since_update = MAX(time_since_update, update_interval);
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

void WorldStreamer::set_view_cone_half_angle_degrees(real_t p_degrees) {
	if (!Math::is_finite(p_degrees)) {
		return;
	}
	view_cone_half_angle_degrees = CLAMP(p_degrees, real_t(1.0), real_t(180.0));
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

void WorldStreamer::set_max_unloads_per_update(int p_count) {
	const int bounded = CLAMP(p_count, 0, 64);
	if (max_unloads_per_update == bounded) {
		return; // Graphics quality reapplication must not force new grid scans.
	}
	max_unloads_per_update = bounded;
	// Removing a restrictive budget should flush obsolete cells at the next
	// scheduler pass without requiring an explicit refresh from gameplay.
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::set_max_unload_work_usec(int p_usec) {
	max_unload_work_usec = CLAMP(p_usec, 0, 1000000);
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
	clear_cached_chunks();
	chunk_path_template = p_template;
	estimated_finalization_work_usec = 0;
	missing.clear();
	failed.clear();
	retry_states.clear();
}

void WorldStreamer::set_chunk_provider(const Callable &p_provider) {
	clear_cached_chunks();
	chunk_provider = p_provider;
	estimated_finalization_work_usec = 0;
	missing.clear();
	failed.clear();
	retry_states.clear();
}

void WorldStreamer::set_chunk_generator(const Callable &p_generator) {
	clear_cached_chunks(); // Old nodes cannot be reattached under a different generator.
	// Existing live chunks remain resident under legacy semantics. Mark them
	// noncacheable so unloading later cannot resurrect geometry from the
	// old generator under the newly configured callback.
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cache_ineligible_nodes.insert(entry.value);
	}
	chunk_generator = p_generator;
	estimated_generator_work_usec = 0;
	generate_queue.clear();
	missing.clear();
	failed.clear();
	retry_states.clear();
}

void WorldStreamer::set_chunk_parent(const NodePath &p_parent) {
	if (chunk_parent == p_parent) {
		return;
	}
	clear_cached_chunks(); // Detached nodes from the old world parent are invalid here.
	chunk_parent = p_parent;
}

void WorldStreamer::set_simulation_radius(real_t p_radius) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius), "Simulation radius must be finite.");
	simulation_radius = p_radius < real_t(0.0) ? real_t(-1.0) : MIN(p_radius, real_t(100000.0));
	time_since_update = 1e9;
}

void WorldStreamer::set_simulation_hysteresis(real_t p_radius) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius), "Simulation hysteresis must be finite.");
	simulation_hysteresis = CLAMP(p_radius, real_t(0.0), real_t(1000.0));
	time_since_update = 1e9;
}

void WorldStreamer::set_max_simulation_transitions_per_update(int p_count) {
	max_simulation_transitions_per_update = CLAMP(p_count, 1, 64);
}

bool WorldStreamer::is_cell_simulation_active(const Vector3i &p_cell) const {
	if (!loaded.has(p_cell)) {
		return false;
	}
	const bool *active = simulation_active_cells.getptr(p_cell);
	return active == nullptr || *active;
}

int WorldStreamer::get_simulation_active_count() const {
	return int(loaded.size()) - simulation_inactive_count;
}

void WorldStreamer::set_tick_throttle_radius(real_t p_radius) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius), "Tick throttle radius must be finite.");
	const real_t value = p_radius < real_t(0.0) ? real_t(-1.0) : MIN(p_radius, real_t(100000.0));
	if (tick_throttle_radius == value) {
		return;
	}
	tick_throttle_radius = value;
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::set_tick_throttle_interval(real_t p_seconds) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_seconds), "Tick throttle interval must be finite.");
	const real_t value = CLAMP(p_seconds, real_t(0.0), real_t(1.0));
	if (tick_throttle_interval == value) {
		return;
	}
	tick_throttle_interval = value;
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::set_tick_throttle_hysteresis(real_t p_distance) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_distance), "Tick throttle hysteresis must be finite.");
	const real_t value = CLAMP(p_distance, real_t(0.0), real_t(1000.0));
	if (tick_throttle_hysteresis == value) {
		return;
	}
	tick_throttle_hysteresis = value;
	time_since_update = MAX(time_since_update, update_interval);
}

void WorldStreamer::set_max_tick_throttle_transitions_per_update(int p_count) {
	max_tick_throttle_transitions_per_update = CLAMP(p_count, 1, 64);
}

bool WorldStreamer::is_cell_tick_throttled(const Vector3i &p_cell) const {
	return loaded.has(p_cell) && applied_tick_intervals.has(p_cell);
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
	last_unload_count = 0;
	last_deferred_unload_count = 0;
	last_unload_work_usec = 0;
	clear_cached_chunks(); // Manual reset always releases memory, not just scene residency.
	LocalVector<Vector3i> cells;
	for (const KeyValue<Vector3i, ObjectID> &entry : loaded) {
		cells.push_back(entry.key);
	}
	for (const Vector3i &cell : cells) {
		_unload_cell(cell, false);
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
	ClassDB::bind_method(D_METHOD("begin_loading_range_ramp", "initial_area_fraction", "delay_seconds", "duration_seconds"), &WorldStreamer::begin_loading_range_ramp);
	ClassDB::bind_method(D_METHOD("advance_loading_range_ramp", "delta_seconds"), &WorldStreamer::advance_loading_range_ramp);
	ClassDB::bind_method(D_METHOD("cancel_loading_range_ramp"), &WorldStreamer::cancel_loading_range_ramp);
	ClassDB::bind_method(D_METHOD("is_loading_range_ramping"), &WorldStreamer::is_loading_range_ramping);
	ClassDB::bind_method(D_METHOD("get_loading_range_area_percent"), &WorldStreamer::get_loading_range_area_percent);
	ClassDB::bind_method(D_METHOD("get_effective_load_radius"), &WorldStreamer::get_effective_load_radius);
	ClassDB::bind_method(D_METHOD("set_velocity_hint", "velocity"), &WorldStreamer::set_velocity_hint);
	ClassDB::bind_method(D_METHOD("get_velocity_hint"), &WorldStreamer::get_velocity_hint);
	ClassDB::bind_method(D_METHOD("set_lookahead_seconds", "seconds"), &WorldStreamer::set_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("get_lookahead_seconds"), &WorldStreamer::get_lookahead_seconds);
	ClassDB::bind_method(D_METHOD("set_view_direction", "direction"), &WorldStreamer::set_view_direction);
	ClassDB::bind_method(D_METHOD("get_view_direction"), &WorldStreamer::get_view_direction);
	ClassDB::bind_method(D_METHOD("set_view_priority", "weight"), &WorldStreamer::set_view_priority);
	ClassDB::bind_method(D_METHOD("get_view_priority"), &WorldStreamer::get_view_priority);
	ClassDB::bind_method(D_METHOD("set_view_cone_half_angle_degrees", "degrees"), &WorldStreamer::set_view_cone_half_angle_degrees);
	ClassDB::bind_method(D_METHOD("get_view_cone_half_angle_degrees"), &WorldStreamer::get_view_cone_half_angle_degrees);
	ClassDB::bind_method(D_METHOD("set_auxiliary_source", "position", "radius"), &WorldStreamer::set_auxiliary_source);
	ClassDB::bind_method(D_METHOD("clear_auxiliary_source"), &WorldStreamer::clear_auxiliary_source);
	ClassDB::bind_method(D_METHOD("has_auxiliary_source"), &WorldStreamer::has_auxiliary_source);
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_position"), &WorldStreamer::get_auxiliary_source_position);
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_radius"), &WorldStreamer::get_auxiliary_source_radius);
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_progress", "require_visual_details"), &WorldStreamer::get_auxiliary_source_progress, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("is_auxiliary_source_ready", "require_visual_details"), &WorldStreamer::is_auxiliary_source_ready, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_pending_count", "require_visual_details"), &WorldStreamer::get_auxiliary_source_pending_count, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_auxiliary_source_failed_count"), &WorldStreamer::get_auxiliary_source_failed_count);
	ClassDB::bind_method(D_METHOD("get_focus_streaming_status", "require_visual_details"), &WorldStreamer::get_focus_streaming_status, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("set_route_cells", "cells"), &WorldStreamer::set_route_cells);
	ClassDB::bind_method(D_METHOD("get_route_cells"), &WorldStreamer::get_route_cells);
	ClassDB::bind_method(D_METHOD("clear_route_cells"), &WorldStreamer::clear_route_cells);
	ClassDB::bind_method(D_METHOD("set_fast_view_refresh_degrees", "degrees"), &WorldStreamer::set_fast_view_refresh_degrees);
	ClassDB::bind_method(D_METHOD("get_fast_view_refresh_degrees"), &WorldStreamer::get_fast_view_refresh_degrees);
	ClassDB::bind_method(D_METHOD("set_max_concurrent_loads", "count"), &WorldStreamer::set_max_concurrent_loads);
	ClassDB::bind_method(D_METHOD("get_max_concurrent_loads"), &WorldStreamer::get_max_concurrent_loads);
	ClassDB::bind_method(D_METHOD("set_max_instantiations_per_frame", "count"), &WorldStreamer::set_max_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_instantiations_per_frame"), &WorldStreamer::get_max_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_unloads_per_update", "count"), &WorldStreamer::set_max_unloads_per_update);
	ClassDB::bind_method(D_METHOD("get_max_unloads_per_update"), &WorldStreamer::get_max_unloads_per_update);
	ClassDB::bind_method(D_METHOD("set_max_unload_work_usec", "microseconds"), &WorldStreamer::set_max_unload_work_usec);
	ClassDB::bind_method(D_METHOD("get_max_unload_work_usec"), &WorldStreamer::get_max_unload_work_usec);
	ClassDB::bind_method(D_METHOD("get_last_unload_work_usec"), &WorldStreamer::get_last_unload_work_usec);
	ClassDB::bind_method(D_METHOD("get_last_unload_count"), &WorldStreamer::get_last_unload_count);
	ClassDB::bind_method(D_METHOD("get_last_deferred_unload_count"), &WorldStreamer::get_last_deferred_unload_count);
	ClassDB::bind_method(D_METHOD("set_max_chunk_work_usec", "microseconds"), &WorldStreamer::set_max_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("set_simulation_radius", "radius"), &WorldStreamer::set_simulation_radius);
	ClassDB::bind_method(D_METHOD("get_simulation_radius"), &WorldStreamer::get_simulation_radius);
	ClassDB::bind_method(D_METHOD("set_simulation_hysteresis", "radius"), &WorldStreamer::set_simulation_hysteresis);
	ClassDB::bind_method(D_METHOD("get_simulation_hysteresis"), &WorldStreamer::get_simulation_hysteresis);
	ClassDB::bind_method(D_METHOD("set_max_simulation_transitions_per_update", "count"), &WorldStreamer::set_max_simulation_transitions_per_update);
	ClassDB::bind_method(D_METHOD("get_max_simulation_transitions_per_update"), &WorldStreamer::get_max_simulation_transitions_per_update);
	ClassDB::bind_method(D_METHOD("is_cell_simulation_active", "cell"), &WorldStreamer::is_cell_simulation_active);
	ClassDB::bind_method(D_METHOD("get_simulation_active_count"), &WorldStreamer::get_simulation_active_count);
	ClassDB::bind_method(D_METHOD("set_tick_throttle_radius", "radius"), &WorldStreamer::set_tick_throttle_radius);
	ClassDB::bind_method(D_METHOD("get_tick_throttle_radius"), &WorldStreamer::get_tick_throttle_radius);
	ClassDB::bind_method(D_METHOD("set_tick_throttle_interval", "seconds"), &WorldStreamer::set_tick_throttle_interval);
	ClassDB::bind_method(D_METHOD("get_tick_throttle_interval"), &WorldStreamer::get_tick_throttle_interval);
	ClassDB::bind_method(D_METHOD("set_tick_throttle_hysteresis", "distance"), &WorldStreamer::set_tick_throttle_hysteresis);
	ClassDB::bind_method(D_METHOD("get_tick_throttle_hysteresis"), &WorldStreamer::get_tick_throttle_hysteresis);
	ClassDB::bind_method(D_METHOD("set_max_tick_throttle_transitions_per_update", "count"), &WorldStreamer::set_max_tick_throttle_transitions_per_update);
	ClassDB::bind_method(D_METHOD("get_max_tick_throttle_transitions_per_update"), &WorldStreamer::get_max_tick_throttle_transitions_per_update);
	ClassDB::bind_method(D_METHOD("is_cell_tick_throttled", "cell"), &WorldStreamer::is_cell_tick_throttled);
	ClassDB::bind_method(D_METHOD("get_tick_throttled_count"), &WorldStreamer::get_tick_throttled_count);
	ClassDB::bind_method(D_METHOD("get_max_chunk_work_usec"), &WorldStreamer::get_max_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("set_adaptive_chunk_budget_enabled", "enabled"), &WorldStreamer::set_adaptive_chunk_budget_enabled);
	ClassDB::bind_method(D_METHOD("is_adaptive_chunk_budget_enabled"), &WorldStreamer::is_adaptive_chunk_budget_enabled);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("advance_chunk_pressure", "pressure", "frame_delta"), &WorldStreamer::advance_chunk_pressure);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("calculate_adaptive_instantiation_slots", "configured", "pressure"), &WorldStreamer::calculate_adaptive_instantiation_slots);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("calculate_adaptive_chunk_work_usec", "configured", "pressure"), &WorldStreamer::calculate_adaptive_chunk_work_usec);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("calculate_adaptive_unload_slots", "configured", "pressure"), &WorldStreamer::calculate_adaptive_unload_slots);
	ClassDB::bind_method(D_METHOD("get_effective_unloads_per_update"), &WorldStreamer::get_effective_unloads_per_update);
	ClassDB::bind_method(D_METHOD("get_effective_chunk_work_usec"), &WorldStreamer::get_effective_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("get_effective_instantiations_per_frame"), &WorldStreamer::get_effective_instantiations_per_frame);
	ClassDB::bind_method(D_METHOD("get_streaming_frame_pressure_percent"), &WorldStreamer::get_streaming_frame_pressure_percent);
	ClassDB::bind_method(D_METHOD("get_last_frame_chunk_work_usec"), &WorldStreamer::get_last_frame_chunk_work_usec);
	ClassDB::bind_method(D_METHOD("get_last_frame_chunk_attempt_count"), &WorldStreamer::get_last_frame_chunk_attempt_count);
	ClassDB::bind_method(D_METHOD("set_predictive_chunk_work_budget_enabled", "enabled"), &WorldStreamer::set_predictive_chunk_work_budget_enabled);
	ClassDB::bind_method(D_METHOD("is_predictive_chunk_work_budget_enabled"), &WorldStreamer::is_predictive_chunk_work_budget_enabled);
	ClassDB::bind_method(D_METHOD("get_estimated_generator_work_usec"), &WorldStreamer::get_estimated_generator_work_usec);
	ClassDB::bind_method(D_METHOD("get_estimated_finalization_work_usec"), &WorldStreamer::get_estimated_finalization_work_usec);
	ClassDB::bind_method(D_METHOD("get_last_predicted_deferred_chunk_count"), &WorldStreamer::get_last_predicted_deferred_chunk_count);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("update_chunk_work_estimate", "previous_usec", "sample_usec"), &WorldStreamer::update_chunk_work_estimate);
	ClassDB::bind_static_method("WorldStreamer", D_METHOD("should_defer_predicted_chunk_work", "budget_usec", "previous_attempts", "spent_usec", "predicted_next_usec"), &WorldStreamer::should_defer_predicted_chunk_work);
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
	ClassDB::bind_method(D_METHOD("set_max_cached_chunks", "count"), &WorldStreamer::set_max_cached_chunks);
	ClassDB::bind_method(D_METHOD("get_max_cached_chunks"), &WorldStreamer::get_max_cached_chunks);
	ClassDB::bind_method(D_METHOD("set_max_cached_chunk_bytes", "bytes"), &WorldStreamer::set_max_cached_chunk_bytes);
	ClassDB::bind_method(D_METHOD("get_max_cached_chunk_bytes"), &WorldStreamer::get_max_cached_chunk_bytes);
	ClassDB::bind_method(D_METHOD("get_cached_chunk_bytes"), &WorldStreamer::get_cached_chunk_bytes);
	ClassDB::bind_method(D_METHOD("set_cached_chunk_retention_seconds", "seconds"), &WorldStreamer::set_cached_chunk_retention_seconds);
	ClassDB::bind_method(D_METHOD("get_cached_chunk_retention_seconds"), &WorldStreamer::get_cached_chunk_retention_seconds);
	ClassDB::bind_method(D_METHOD("advance_cached_chunk_retention", "delta_seconds"), &WorldStreamer::advance_cached_chunk_retention);
	ClassDB::bind_method(D_METHOD("get_chunk_cache_expiration_count"), &WorldStreamer::get_chunk_cache_expiration_count);
	ClassDB::bind_method(D_METHOD("set_max_cached_expirations_per_frame", "count"), &WorldStreamer::set_max_cached_expirations_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_cached_expirations_per_frame"), &WorldStreamer::get_max_cached_expirations_per_frame);
	ClassDB::bind_method(D_METHOD("set_max_cached_expiration_work_usec", "usec"), &WorldStreamer::set_max_cached_expiration_work_usec);
	ClassDB::bind_method(D_METHOD("get_max_cached_expiration_work_usec"), &WorldStreamer::get_max_cached_expiration_work_usec);
	ClassDB::bind_method(D_METHOD("get_last_cached_expiration_count"), &WorldStreamer::get_last_cached_expiration_count);
	ClassDB::bind_method(D_METHOD("get_last_deferred_cached_expiration_count"), &WorldStreamer::get_last_deferred_cached_expiration_count);
	ClassDB::bind_method(D_METHOD("get_last_cached_expiration_work_usec"), &WorldStreamer::get_last_cached_expiration_work_usec);
	ClassDB::bind_method(D_METHOD("get_cached_chunk_count"), &WorldStreamer::get_cached_chunk_count);
	ClassDB::bind_method(D_METHOD("get_chunk_cache_hit_count"), &WorldStreamer::get_chunk_cache_hit_count);
	ClassDB::bind_method(D_METHOD("get_chunk_cache_eviction_count"), &WorldStreamer::get_chunk_cache_eviction_count);
	ClassDB::bind_method(D_METHOD("clear_cached_chunks"), &WorldStreamer::clear_cached_chunks);
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
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "view_cone_half_angle_degrees", PROPERTY_HINT_RANGE, "1,180,1,suffix:°"), "set_view_cone_half_angle_degrees", "get_view_cone_half_angle_degrees");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fast_view_refresh_degrees", PROPERTY_HINT_RANGE, "0,180,1,suffix:°"), "set_fast_view_refresh_degrees", "get_fast_view_refresh_degrees");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "chunk_path_template", PROPERTY_HINT_NONE, ""), "set_chunk_path_template", "get_chunk_path_template");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "chunk_parent", PROPERTY_HINT_NONE, ""), "set_chunk_parent", "get_chunk_parent");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "position_chunks"), "set_position_chunks", "get_position_chunks");
	ADD_GROUP("Simulation", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "simulation_radius", PROPERTY_HINT_RANGE, "-1,100000,0.1,suffix:m"), "set_simulation_radius", "get_simulation_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "simulation_hysteresis", PROPERTY_HINT_RANGE, "0,1000,0.1,suffix:m"), "set_simulation_hysteresis", "get_simulation_hysteresis");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_simulation_transitions_per_update", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_simulation_transitions_per_update", "get_max_simulation_transitions_per_update");
	ADD_GROUP("Cosmetic Tick LOD", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tick_throttle_radius", PROPERTY_HINT_RANGE, "-1,100000,0.1,suffix:m"), "set_tick_throttle_radius", "get_tick_throttle_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tick_throttle_interval", PROPERTY_HINT_RANGE, "0,1,0.005,suffix:s"), "set_tick_throttle_interval", "get_tick_throttle_interval");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tick_throttle_hysteresis", PROPERTY_HINT_RANGE, "0,1000,0.1,suffix:m"), "set_tick_throttle_hysteresis", "get_tick_throttle_hysteresis");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_tick_throttle_transitions_per_update", PROPERTY_HINT_RANGE, "1,64,1"), "set_max_tick_throttle_transitions_per_update", "get_max_tick_throttle_transitions_per_update");
	ADD_GROUP("Budget", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_concurrent_loads", PROPERTY_HINT_RANGE, "1,64,1,or_greater"), "set_max_concurrent_loads", "get_max_concurrent_loads");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cached_chunks", PROPERTY_HINT_RANGE, "0,16,1"), "set_max_cached_chunks", "get_max_cached_chunks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cached_chunk_bytes", PROPERTY_HINT_RANGE, "0,268435456,1048576,suffix:B"), "set_max_cached_chunk_bytes", "get_max_cached_chunk_bytes");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cached_chunk_retention_seconds", PROPERTY_HINT_RANGE, "0,120,0.1,suffix:s"), "set_cached_chunk_retention_seconds", "get_cached_chunk_retention_seconds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cached_expirations_per_frame", PROPERTY_HINT_RANGE, "0,16,1"), "set_max_cached_expirations_per_frame", "get_max_cached_expirations_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cached_expiration_work_usec", PROPERTY_HINT_RANGE, "0,1000000,100,suffix:us"), "set_max_cached_expiration_work_usec", "get_max_cached_expiration_work_usec");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_instantiations_per_frame", PROPERTY_HINT_RANGE, "1,16,1,or_greater"), "set_max_instantiations_per_frame", "get_max_instantiations_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_unloads_per_update", PROPERTY_HINT_RANGE, "0,64,1"), "set_max_unloads_per_update", "get_max_unloads_per_update");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_unload_work_usec", PROPERTY_HINT_RANGE, "0,1000000,100,suffix:us"), "set_max_unload_work_usec", "get_max_unload_work_usec");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_chunk_work_usec", PROPERTY_HINT_RANGE, "0,1000000,100,suffix:us"), "set_max_chunk_work_usec", "get_max_chunk_work_usec");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "predictive_chunk_work_budget_enabled"), "set_predictive_chunk_work_budget_enabled", "is_predictive_chunk_work_budget_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "update_interval", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:s"), "set_update_interval", "get_update_interval");
	ADD_GROUP("Recovery", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_auto_retries", PROPERTY_HINT_RANGE, "0,8,1"), "set_max_auto_retries", "get_max_auto_retries");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "retry_initial_delay", PROPERTY_HINT_RANGE, "0.01,60,0.01,suffix:s"), "set_retry_initial_delay", "get_retry_initial_delay");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "retry_max_delay", PROPERTY_HINT_RANGE, "0.01,60,0.01,suffix:s"), "set_retry_max_delay", "get_retry_max_delay");

	ADD_SIGNAL(MethodInfo("chunk_loaded", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::OBJECT, "chunk", PROPERTY_HINT_RESOURCE_TYPE, "Node")));
	ADD_SIGNAL(MethodInfo("chunk_visual_details_ready", PropertyInfo(Variant::VECTOR3I, "cell")));
	ADD_SIGNAL(MethodInfo("chunk_unloaded", PropertyInfo(Variant::VECTOR3I, "cell")));
	ADD_SIGNAL(MethodInfo("chunk_simulation_changed", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::BOOL, "active")));
	ADD_SIGNAL(MethodInfo("chunk_tick_interval_changed", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::FLOAT, "seconds")));
	ADD_SIGNAL(MethodInfo("chunk_load_failed", PropertyInfo(Variant::VECTOR3I, "cell"), PropertyInfo(Variant::STRING, "path")));

	BIND_ENUM_CONSTANT(AXES_XZ);
	BIND_ENUM_CONSTANT(AXES_XY);
	BIND_ENUM_CONSTANT(AXES_XYZ);
}
