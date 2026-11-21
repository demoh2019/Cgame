/**************************************************************************/
/*  world_streamer.h                                             */
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

#include "scene/main/node.h"
#include "scene/main/world_streaming_grid.h"

#include "core/templates/hash_map.h"
#include "core/templates/hash_set.h"
#include "core/variant/dictionary.h"

// Streams the parts ("chunks") of a big world in and out around a focus point, so an open world
// only keeps the nearby scenes in memory. The world is split into a grid of square (or cubic)
// cells; the scene for a cell is found with a path template or a callback, loaded on background
// threads, instantiated a few per frame, and freed again once the focus has moved far enough away.
class WorldStreamer : public Node {
	GDCLASS(WorldStreamer, Node);

public:
	enum Axes {
		AXES_XZ,
		AXES_XY,
		AXES_XYZ,
	};

private:
	NodePath focus;
	Vector3 focus_position;
	Axes axes = AXES_XZ;
	real_t cell_size = 64.0;
	real_t load_radius = 128.0;
	real_t unload_radius = 192.0;
	// Opt-in startup World Partition-style loading area ramp. Fractions
	// describe 2D area or 3D volume, NOT radial distance. Existing loaded
	// cells keep the configured unload hysteresis during the ramp.
	real_t loading_range_area_fraction = 1.0;
	real_t loading_ramp_initial_fraction = 1.0;
	real_t loading_ramp_delay = 0.0;
	real_t loading_ramp_duration = 0.0;
	real_t loading_ramp_elapsed = 0.0;
	bool loading_ramp_active = false;
	// Optional hint only affects load order; current focus still controls
	// residency and chunk generation. Disabled unless set by the game.
	Vector3 velocity_hint;
	real_t lookahead_seconds = 0.0;
	// Optional view-source bias: zero preserves motion-only scheduling.
	// These hints reorder eligible work, never grow the resident set.
	Vector3 view_direction;
	real_t view_priority = 0.0;
	// 180 degrees preserves the historical heading-only streaming order.
	real_t view_cone_half_angle_degrees = 180.0;
	// Optional secondary streaming source for cinematic targets or nearby
	// waypoints. Its radius and distance from focus are both bounded, so
	// arbitrarily distant map pins cannot load remote chunks into memory.
	bool auxiliary_source_active = false;
	Vector3 auxiliary_source_position;
	real_t auxiliary_source_radius = 0.0;
	struct AuxiliaryCompletion {
		int total = 0;
		int completed = 0;
		int failed = 0;
	};
	// Query only; does not request resources, instantiate scenes or alter residency.
	AuxiliaryCompletion _get_auxiliary_completion(bool p_require_visual_details) const;
	// Read-only main focus completion, using the same bounded grid as streaming.
	AuxiliaryCompletion _get_focus_completion(bool p_require_visual_details, bool &r_truncated) const;
	// Optional route plan from AStarGrid2D or another game planner.
	// Only reorders already-eligible player-radius chunks: it never adds
	// residency, skips streaming budgets or loads a distant island.
	LocalVector<Vector3i> route_hint_cells;
	// 0 = legacy update cadence. A large camera turn may rebuild the
	// scheduling queue sooner, subject to a 50 ms minimum CPU interval.
	real_t fast_view_refresh_degrees = 0.0;
	Vector3 last_queued_view_direction;
	int max_concurrent_loads = 4;
	int max_instantiations_per_frame = 1;
	// Opt-in bounded per-refresh unloads. Zero preserves historical immediate
	// release of every distant cell; positive counts defer the rest.
	int max_unloads_per_update = 0;
	// Optional soft wall-clock cap for scheduled unloads, measured in
	// microseconds. Zero retains count-only scheduling; legacy unlimited
	// unloads and explicit reset/teardown are never time-sliced.
	int max_unload_work_usec = 0;
	int64_t last_unload_work_usec = 0;
	int last_unload_count = 0;
	int last_deferred_unload_count = 0;
	// Soft main-thread time slice for procedural generation or scene
	// activation (0 = count-only). Each individual chunk is indivisible.
	int max_chunk_work_usec = 0;
	// Opt-in simulation LOD: loaded scenery remains visible while a chunk's
	// cosmetic script updates can be paused through its own callback.
	real_t simulation_radius = -1.0; // Negative preserves legacy full simulation.
	real_t simulation_hysteresis = 16.0;
	int max_simulation_transitions_per_update = 4;
	// Separate Unreal-style cosmetic tick-rate tier, opt-in and independent
	// of simulation pause. Chunks decide how to throttle their own script.
	real_t tick_throttle_radius = -1.0;
	real_t tick_throttle_interval = 0.125;
	real_t tick_throttle_hysteresis = 8.0;
	int max_tick_throttle_transitions_per_update = 4;
	// Opt-in adaptive backpressure. Defaults off to preserve existing games.
	bool adaptive_chunk_budget_enabled = false;
	double streaming_frame_pressure = 0.0;
	int active_chunk_work_budget_usec = 0;
	int active_instantiation_budget = 1;
	int64_t frame_chunk_work_usec = 0;
	int64_t last_frame_chunk_work_usec = 0;
	int frame_chunk_attempt_count = 0;
	int last_frame_chunk_attempt_count = 0;
	// Optional per-stage EMA admission forecast, not a hard CPU cap.
	bool predictive_chunk_work_budget_enabled = false;
	int64_t estimated_generator_work_usec = 0;
	int64_t estimated_finalization_work_usec = 0;
	int frame_predicted_deferred_count = 0;
	int last_predicted_deferred_count = 0;
	double update_interval = 0.1;
	String chunk_path_template;
	Callable chunk_provider;
	// Procedural worlds: called on the main thread with the cell, returns the chunk node (or null).
	Callable chunk_generator;
	// Cells waiting for the generator, nearest first. Generation is paced by max_instantiations_per_frame.
	LocalVector<Vector3i> generate_queue;
	NodePath chunk_parent;
	bool position_chunks = true;
	bool enabled = true;

	HashMap<Vector3i, ObjectID> loaded;
	// Nodes resident before a generator replacement may not enter the new cache.
	HashSet<ObjectID> cache_ineligible_nodes;
	// Explicitly opt-in, bounded procedural scene retention. Detached nodes do
	// not render or process; only roots that allow caching can be preserved.
	struct CachedChunk {
		ObjectID node_id;
		uint64_t age = 0;
		int64_t estimated_bytes = 0;
		double retained_at_seconds = 0.0;
	};
	HashMap<Vector3i, CachedChunk> cached_chunks;
	int max_cached_chunks = 0; // Zero preserves legacy free-on-unload.
	int64_t max_cached_chunk_bytes = 0;
	int64_t cached_chunk_bytes = 0;
	// Zero disables time-based reclamation of detached procedural roots.
	real_t cached_chunk_retention_seconds = 0.0;
	double cached_chunk_elapsed_seconds = 0.0;
	uint64_t cache_clock = 0;
	int cache_hits = 0;
	int cache_evictions = 0;
	int cache_expirations = 0;
	// Opt-in incremental cache expiration, preserving legacy semantics at zero.
	int max_cached_expirations_per_frame = 0;
	int max_cached_expiration_work_usec = 0;
	int last_cached_expiration_count = 0;
	int last_deferred_cached_expiration_count = 0;
	int64_t last_cached_expiration_work_usec = 0;
	HashMap<Vector3i, bool> simulation_active_cells;
	int simulation_inactive_count = 0;
	// Only chunk roots actually implementing the callback are tracked.
	// A zero/absent entry means full tick frequency.
	HashMap<Vector3i, real_t> applied_tick_intervals;
	int tick_throttled_count = 0;
	// Optional cosmetic work is tracked separately from playable chunk residency.
	HashSet<Vector3i> pending_visual_details;
	HashMap<Vector3i, String> loading;
	// Cells without a chunk scene, and cells whose scene failed to load. Not asked again until
	// refresh(true) or a change of the grid or the path template.
	HashSet<Vector3i> missing;
	HashSet<Vector3i> failed;
	// Automatic retries are opt-in; failures are bounded to active world cells.
	struct RetryState {
		int attempts = 0;
		uint64_t next_retry_usec = 0;
	};
	HashMap<Vector3i, RetryState> retry_states;
	int max_auto_retries = 0;
	real_t retry_initial_delay = 1.0;
	real_t retry_max_delay = 16.0;
	double time_since_update = 1e9;
	bool truncated_warned = false;

	WorldStreamingGrid::Axes _grid_axes() const { return WorldStreamingGrid::Axes(axes); }
	bool _get_focus_position(Vector3 &r_position) const;
	real_t _auxiliary_effective_radius() const;
	bool _auxiliary_is_near_focus(const Vector3 &p_focus) const;
	bool _cell_requested(const Vector3 &p_focus, const Vector3i &p_cell) const;
	String _path_for_cell(const Vector3i &p_cell) const;
	Node *_get_parent_for_chunks() const;
	void _forget_dead_chunks();
	void _update_streaming();
	void _update_simulation(const Vector3 &p_focus);
	void _update_tick_intervals(const Vector3 &p_focus);
	void _set_chunk_tick_interval(const Vector3i &p_cell, real_t p_seconds);
	void _set_chunk_simulation_active(const Vector3i &p_cell, bool p_active);
	void _poll_loading(int &r_instantiation_budget, uint64_t p_frame_started_usec);
	bool _finalize_chunk(const Vector3i &p_cell, const String &p_path);
	bool _adopt_chunk(const Vector3i &p_cell, Node *p_chunk);
	void _run_generator_queue(int &r_instantiation_budget, uint64_t p_frame_started_usec);
	void _generate_cell(const Vector3i &p_cell);
	void _record_chunk_work(uint64_t p_started_usec, bool p_generator);
	bool _should_defer_predicted_work(bool p_generator) const;
	void _finish_chunk_work_frame();
	void _unload_cell(const Vector3i &p_cell, bool p_allow_cache = true);
	bool _restore_cached_chunk(const Vector3i &p_cell);
	void _trim_cached_chunks();
	void _expire_cached_chunks(bool p_ignore_budget = false);
	void _discard_cached_chunks();
	void _reset_state();
	void _record_failure(const Vector3i &p_cell, const String &p_reason);
	void _update_retries(const Vector3 &p_focus, real_t p_keep_radius);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_focus(const NodePath &p_focus);
	NodePath get_focus() const { return focus; }
	void set_focus_position(const Vector3 &p_position);
	Vector3 get_focus_position() const { return focus_position; }
	void set_axes(Axes p_axes);
	Axes get_axes() const { return axes; }
	void set_cell_size(real_t p_size);
	real_t get_cell_size() const { return cell_size; }
	void set_load_radius(real_t p_radius);
	real_t get_load_radius() const { return load_radius; }
	void set_unload_radius(real_t p_radius);
	real_t get_unload_radius() const { return unload_radius; }
	// Explicit opt-in, progressive load-queue expansion. Full configured
	// load_radius and unload_radius are unchanged; slow frames cannot make
	// the player's currently loaded cells disappear.
	void begin_loading_range_ramp(real_t p_initial_area_fraction, real_t p_delay_seconds, real_t p_duration_seconds);
	void advance_loading_range_ramp(real_t p_delta_seconds);
	void cancel_loading_range_ramp();
	bool is_loading_range_ramping() const { return loading_ramp_active; }
	real_t get_loading_range_area_percent() const { return loading_range_area_fraction * real_t(100.0); }
	real_t get_effective_load_radius() const;
	void set_velocity_hint(const Vector3 &p_velocity);
	Vector3 get_velocity_hint() const { return velocity_hint; }
	void set_lookahead_seconds(real_t p_seconds);
	real_t get_lookahead_seconds() const { return lookahead_seconds; }
	void set_view_direction(const Vector3 &p_direction);
	Vector3 get_view_direction() const { return view_direction; }
	void set_view_priority(real_t p_weight);
	void set_view_cone_half_angle_degrees(real_t p_degrees);
	real_t get_view_cone_half_angle_degrees() const { return view_cone_half_angle_degrees; }
	void set_fast_view_refresh_degrees(real_t p_degrees);
	real_t get_fast_view_refresh_degrees() const { return fast_view_refresh_degrees; }
	real_t get_view_priority() const { return view_priority; }
	// One bounded extra streaming source, independent of the camera/motion
	// priority hints. Setting a remote target stores it but does not load it
	// until it approaches the main focus. Clear to restore legacy behavior.
	void set_auxiliary_source(const Vector3 &p_position, real_t p_radius);
	void clear_auxiliary_source();
	// Accepts at most 64 edge-adjacent cells in the active streaming plane.
	// Reorders eligible work without changing membership, CPU budgets or
	// the priority of the chunk beneath the player.
	bool set_route_cells(const TypedArray<Vector3i> &p_cells);
	TypedArray<Vector3i> get_route_cells() const;
	void clear_route_cells();
	bool has_auxiliary_source() const { return auxiliary_source_active; }
	Vector3 get_auxiliary_source_position() const { return auxiliary_source_position; }
	real_t get_auxiliary_source_radius() const { return auxiliary_source_active ? _auxiliary_effective_radius() : real_t(0.0); }
	// Optional World Partition-style completion/readiness for the bounded
	// auxiliary source. Missing (empty) cells are settled; failed ones are not.
	real_t get_auxiliary_source_progress(bool p_require_visual_details = false) const;
	bool is_auxiliary_source_ready(bool p_require_visual_details = false) const;
	int get_auxiliary_source_pending_count(bool p_require_visual_details = false) const;
	int get_auxiliary_source_failed_count() const;
	// One snapshot avoids four O(cells) queries from HUD/telemetry clients.
	// No cell generation, resource requests or main-thread scene work.
	Dictionary get_focus_streaming_status(bool p_require_visual_details = false) const;
	void set_max_concurrent_loads(int p_count);
	int get_max_concurrent_loads() const { return max_concurrent_loads; }
	void set_max_instantiations_per_frame(int p_count);
	void set_max_unloads_per_update(int p_count);
	int get_max_unloads_per_update() const { return max_unloads_per_update; }
	void set_max_unload_work_usec(int p_usec);
	int get_max_unload_work_usec() const { return max_unload_work_usec; }
	int64_t get_last_unload_work_usec() const { return last_unload_work_usec; }
	int get_last_unload_count() const { return last_unload_count; }
	int get_last_deferred_unload_count() const { return last_deferred_unload_count; }
	int get_max_instantiations_per_frame() const { return max_instantiations_per_frame; }
	void set_max_chunk_work_usec(int p_usec);
	void set_simulation_radius(real_t p_radius);
	real_t get_simulation_radius() const { return simulation_radius; }
	void set_simulation_hysteresis(real_t p_radius);
	real_t get_simulation_hysteresis() const { return simulation_hysteresis; }
	void set_max_simulation_transitions_per_update(int p_count);
	int get_max_simulation_transitions_per_update() const { return max_simulation_transitions_per_update; }
	bool is_cell_simulation_active(const Vector3i &p_cell) const;
	int get_simulation_active_count() const;
	// For opted-in script roots, set_streaming_tick_interval(seconds) is called
	// at initial adoption and for later bounded near/far transitions.
	// -1 disables; hysteresis only affects far-tier entry, not near recovery.
	void set_tick_throttle_radius(real_t p_radius);
	real_t get_tick_throttle_radius() const { return tick_throttle_radius; }
	void set_tick_throttle_interval(real_t p_seconds);
	real_t get_tick_throttle_interval() const { return tick_throttle_interval; }
	void set_tick_throttle_hysteresis(real_t p_distance);
	real_t get_tick_throttle_hysteresis() const { return tick_throttle_hysteresis; }
	void set_max_tick_throttle_transitions_per_update(int p_count);
	int get_max_tick_throttle_transitions_per_update() const { return max_tick_throttle_transitions_per_update; }
	bool is_cell_tick_throttled(const Vector3i &p_cell) const;
	int get_tick_throttled_count() const { return tick_throttled_count; }
	int get_max_chunk_work_usec() const { return max_chunk_work_usec; }
	void set_adaptive_chunk_budget_enabled(bool p_enabled);
	bool is_adaptive_chunk_budget_enabled() const { return adaptive_chunk_budget_enabled; }
	// Pure, bounded pressure step shared with performance tests. Large delta
	// raises pressure; stable fast frames recover it gradually.
	static double advance_chunk_pressure(double p_pressure, double p_frame_delta);
	static int calculate_adaptive_instantiation_slots(int p_configured, double p_pressure);
	// Zero preserves unlimited cleanup; positive limits adapt to frame pressure.
	static int calculate_adaptive_unload_slots(int p_configured, double p_pressure);
	int get_effective_unloads_per_update() const;
	static int calculate_adaptive_chunk_work_usec(int p_configured, double p_pressure);
	int get_effective_chunk_work_usec() const;
	int get_effective_instantiations_per_frame() const;
	double get_streaming_frame_pressure_percent() const { return streaming_frame_pressure * 100.0; }
	int64_t get_last_frame_chunk_work_usec() const { return last_frame_chunk_work_usec; }
	int get_last_frame_chunk_attempt_count() const { return last_frame_chunk_attempt_count; }
	void set_predictive_chunk_work_budget_enabled(bool p_enabled) { predictive_chunk_work_budget_enabled = p_enabled; }
	bool is_predictive_chunk_work_budget_enabled() const { return predictive_chunk_work_budget_enabled; }
	int64_t get_estimated_generator_work_usec() const { return estimated_generator_work_usec; }
	int64_t get_estimated_finalization_work_usec() const { return estimated_finalization_work_usec; }
	int get_last_predicted_deferred_chunk_count() const { return last_predicted_deferred_count; }
	static int64_t update_chunk_work_estimate(int64_t p_previous, int64_t p_sample_usec);
	static bool should_defer_predicted_chunk_work(int p_budget_usec, int p_previous_attempts,
			int64_t p_work_spent_usec, int64_t p_estimated_next_usec);
	void set_max_auto_retries(int p_count);
	int get_max_auto_retries() const { return max_auto_retries; }
	void set_retry_initial_delay(real_t p_seconds);
	real_t get_retry_initial_delay() const { return retry_initial_delay; }
	void set_retry_max_delay(real_t p_seconds);
	real_t get_retry_max_delay() const { return retry_max_delay; }
	int get_retry_pending_count() const;
	void set_update_interval(double p_seconds);
	double get_update_interval() const { return update_interval; }
	void set_chunk_path_template(const String &p_template);
	String get_chunk_path_template() const { return chunk_path_template; }
	void set_chunk_provider(const Callable &p_provider);
	Callable get_chunk_provider() const { return chunk_provider; }
	// Builds chunks in code instead of loading scene files: `generator.call(cell)` must return a Node
	// (or null for an empty cell). Use it for worlds generated from a seed. Takes precedence over the
	// provider and the path template.
	void set_chunk_generator(const Callable &p_generator);
	// Retain up to 16 detached PROCEDURAL chunk roots by cell coordinate.
	// A root must explicitly implement can_cache_streaming_chunk() -> true.
	// Cached chunks never count as loaded and reinsertion is still frame-budgeted.
	void set_max_cached_chunks(int p_count);
	int get_max_cached_chunks() const { return max_cached_chunks; }
	void set_max_cached_chunk_bytes(int64_t p_bytes);
	int64_t get_max_cached_chunk_bytes() const { return max_cached_chunk_bytes; }
	int64_t get_cached_chunk_bytes() const { return cached_chunk_bytes; }
	void set_cached_chunk_retention_seconds(real_t p_seconds);
	real_t get_cached_chunk_retention_seconds() const { return cached_chunk_retention_seconds; }
	void advance_cached_chunk_retention(real_t p_delta_seconds);
	int get_chunk_cache_expiration_count() const { return cache_expirations; }
	void set_max_cached_expirations_per_frame(int p_count);
	int get_max_cached_expirations_per_frame() const { return max_cached_expirations_per_frame; }
	void set_max_cached_expiration_work_usec(int p_usec);
	int get_max_cached_expiration_work_usec() const { return max_cached_expiration_work_usec; }
	int get_last_cached_expiration_count() const { return last_cached_expiration_count; }
	int get_last_deferred_cached_expiration_count() const { return last_deferred_cached_expiration_count; }
	int64_t get_last_cached_expiration_work_usec() const { return last_cached_expiration_work_usec; }
	int get_cached_chunk_count() const { return int(cached_chunks.size()); }
	int get_chunk_cache_hit_count() const { return cache_hits; }
	int get_chunk_cache_eviction_count() const { return cache_evictions; }
	void clear_cached_chunks();
	Callable get_chunk_generator() const { return chunk_generator; }
	void set_chunk_parent(const NodePath &p_parent);
	NodePath get_chunk_parent() const { return chunk_parent; }
	void set_position_chunks(bool p_enabled) { position_chunks = p_enabled; }
	bool get_position_chunks() const { return position_chunks; }
	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }

	Vector3i world_to_cell(const Vector3 &p_position) const;
	Vector3 cell_to_world(const Vector3i &p_cell) const;
	bool is_cell_loaded(const Vector3i &p_cell) const { return loaded.has(p_cell); }
	Node *get_chunk(const Vector3i &p_cell) const;
	TypedArray<Vector3i> get_loaded_cells() const;
	int get_loaded_count() const { return int(loaded.size()); }
	int get_pending_count() const { return int(loading.size()); }
	// Procedural cells queue separately from threaded scene loads.
	// Expose their backlog for streaming telemetry and adaptive game scheduling.
	int get_queued_generation_count() const { return int(generate_queue.size()); }
	int get_pending_visual_details_count() const { return int(pending_visual_details.size()); }
	// A loaded procedural chunk calls this after staged scenery is complete.
	// The world is already playable; this is visual-progress telemetry only.
	void mark_visual_details_ready(const Vector3i &p_cell);

	// Re-evaluates immediately instead of waiting for the update interval. With `p_retry`, cells
	// that were missing or failed are tried again.
	void refresh(bool p_retry = false);
	// Frees every loaded chunk. Streaming resumes at the next update unless `enabled` is false.
	void unload_all();

	WorldStreamer() {}
	~WorldStreamer();
};

VARIANT_ENUM_CAST(WorldStreamer::Axes);
