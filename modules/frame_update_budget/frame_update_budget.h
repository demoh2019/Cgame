/**************************************************************************/
/*  frame_update_budget.h                                                 */
/*  This file is part of the Godot Engine (MIT License).                   */
/**************************************************************************/

#pragma once

#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"

/**
 * A bounded, main-thread, data-only scheduler for non-critical updates.
 * Does not execute callbacks or touch the scene tree.
 */
class FrameUpdateBudget : public RefCounted {
	GDCLASS(FrameUpdateBudget, RefCounted);

	struct Lane {
		StringName name;
		double elapsed = 0.0;
	};

	Vector<Lane> lanes;
	// Reserved due lanes are selected at frame start before caller order can bias
	// the scarce per-frame slots. The rotating tie breaker prevents starvation.
	Vector<int> reserved_lanes;
	int tie_start = 0;
	double rates[4] = { 12.0, 18.0, 30.0, 60.0 };
	int slots[4] = { 1, 2, 3, 4 };
	double max_step = 0.16;
	int quality = -1;
	bool quality_changed = true;
	bool profile_dirty = false;
	int budget = 1;
	int spent = 0;
	double pressure = 0.0;
	int64_t frame_time_budget_us = 2500; // Soft budget, 0 disables the time limit.
	int64_t frame_cost_us = 0;
	int64_t previous_frame_cost_us = 0;
	int64_t total_updated = 0;
	int64_t total_skipped = 0;
	int last_updated = 0;
	int last_skipped = 0;

	void record_update();

protected:
	static void _bind_methods();

public:
	bool register_lane(const StringName &p_lane);
	bool unregister_lane(const StringName &p_lane);
	int get_lane_count() const { return lanes.size(); }
	bool configure(const PackedFloat64Array &p_rates, const PackedInt32Array &p_slots);
	void begin_frame(double p_delta, int p_quality);
	bool set_frame_time_budget_us(int64_t p_budget_us);
	int64_t get_frame_time_budget_us() const { return frame_time_budget_us; }
	bool record_cost(const StringName &p_lane, int64_t p_elapsed_us);
	int64_t current_frame_cost_us() const { return frame_cost_us; }
	int64_t last_frame_cost_us() const { return previous_frame_cost_us; }
	double consume(const StringName &p_lane, double p_delta, bool p_force = false);
	void reset();
	int64_t updated_total() const { return total_updated; }
	int64_t skipped_total() const { return total_skipped; }
	int current_budget() const { return budget; }
	double pressure_percent() const { return pressure * 100.0; }
	Vector2i last_frame_counts() const { return Vector2i(last_updated, last_skipped); }
};
