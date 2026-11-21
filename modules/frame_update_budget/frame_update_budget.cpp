/**************************************************************************/
/*  frame_update_budget.cpp                                               */
/*  This file is part of the Godot Engine (MIT License).                   */
/**************************************************************************/

#include "frame_update_budget.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void FrameUpdateBudget::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_lane", "lane"), &FrameUpdateBudget::register_lane);
	ClassDB::bind_method(D_METHOD("unregister_lane", "lane"), &FrameUpdateBudget::unregister_lane);
	ClassDB::bind_method(D_METHOD("get_lane_count"), &FrameUpdateBudget::get_lane_count);
	ClassDB::bind_method(D_METHOD("set_lane_enabled", "lane", "enabled"), &FrameUpdateBudget::set_lane_enabled);
	ClassDB::bind_method(D_METHOD("is_lane_enabled", "lane"), &FrameUpdateBudget::is_lane_enabled);
	ClassDB::bind_method(D_METHOD("get_enabled_lane_count"), &FrameUpdateBudget::get_enabled_lane_count);
	ClassDB::bind_method(D_METHOD("configure", "quality_rates", "quality_slots"), &FrameUpdateBudget::configure);
	ClassDB::bind_method(D_METHOD("begin_frame", "delta", "quality"), &FrameUpdateBudget::begin_frame);
	ClassDB::bind_method(D_METHOD("set_frame_time_budget_us", "budget_us"), &FrameUpdateBudget::set_frame_time_budget_us);
	ClassDB::bind_method(D_METHOD("get_frame_time_budget_us"), &FrameUpdateBudget::get_frame_time_budget_us);
	ClassDB::bind_method(D_METHOD("record_cost", "lane", "elapsed_us"), &FrameUpdateBudget::record_cost);
	ClassDB::bind_method(D_METHOD("set_lane_importance", "lane", "importance"), &FrameUpdateBudget::set_lane_importance);
	ClassDB::bind_method(D_METHOD("set_lane_rate_scale", "lane", "scale"), &FrameUpdateBudget::set_lane_rate_scale);
	ClassDB::bind_method(D_METHOD("get_lane_rate_scale", "lane"), &FrameUpdateBudget::get_lane_rate_scale);
	ClassDB::bind_method(D_METHOD("set_lane_max_deferred_frames", "lane", "frames"), &FrameUpdateBudget::set_lane_max_deferred_frames);
	ClassDB::bind_method(D_METHOD("get_lane_max_deferred_frames", "lane"), &FrameUpdateBudget::get_lane_max_deferred_frames);
	ClassDB::bind_method(D_METHOD("get_deadline_overdue_lane_count"), &FrameUpdateBudget::get_deadline_overdue_lane_count);
	ClassDB::bind_method(D_METHOD("get_lane_importance", "lane"), &FrameUpdateBudget::get_lane_importance);
	ClassDB::bind_method(D_METHOD("get_lane_estimated_cost_us", "lane"), &FrameUpdateBudget::get_lane_estimated_cost_us);
	ClassDB::bind_method(D_METHOD("get_lane_last_frame_cost_us", "lane"), &FrameUpdateBudget::get_lane_last_frame_cost_us);
	ClassDB::bind_method(D_METHOD("get_reserved_estimated_cost_us"), &FrameUpdateBudget::get_reserved_estimated_cost_us);
	ClassDB::bind_method(D_METHOD("current_frame_cost_us"), &FrameUpdateBudget::current_frame_cost_us);
	ClassDB::bind_method(D_METHOD("last_frame_cost_us"), &FrameUpdateBudget::last_frame_cost_us);
	ClassDB::bind_method(D_METHOD("consume", "lane", "delta", "force"), &FrameUpdateBudget::consume, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("reset"), &FrameUpdateBudget::reset);
	ClassDB::bind_method(D_METHOD("updated_total"), &FrameUpdateBudget::updated_total);
	ClassDB::bind_method(D_METHOD("skipped_total"), &FrameUpdateBudget::skipped_total);
	ClassDB::bind_method(D_METHOD("current_budget"), &FrameUpdateBudget::current_budget);
	ClassDB::bind_method(D_METHOD("pressure_percent"), &FrameUpdateBudget::pressure_percent);
	ClassDB::bind_method(D_METHOD("last_frame_counts"), &FrameUpdateBudget::last_frame_counts);
}

bool FrameUpdateBudget::register_lane(const StringName &p_lane) {
	if (p_lane == StringName() || lanes.size() >= 64) {
		return false;
	}
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return false;
		}
	}
	Lane lane;
	lane.name = p_lane;
	lanes.push_back(lane);
	return true;
}

bool FrameUpdateBudget::unregister_lane(const StringName &p_lane) {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			lanes.remove_at(i);
			reserved_lanes.clear(); // Indices shifted; never reuse a stale reservation.
			return true;
		}
	}
	return false;
}

bool FrameUpdateBudget::set_lane_enabled(const StringName &p_lane, bool p_enabled) {
	for (int i = 0; i < lanes.size(); i++) {
		Lane &lane = lanes.write[i];
		if (lane.name != p_lane) {
			continue;
		}
		if (lane.enabled == p_enabled) {
			return true;
		}
		lane.enabled = p_enabled;
		lane.elapsed = 0.0;
		lane.overdue_frames = 0;
		lane.refresh_pending = p_enabled;
		// Lane indices remain valid, but previous reservations were planned
		// for a different active set and cannot be consumed safely.
		reserved_lanes.clear();
		reserved_estimated_cost_us = 0;
		return true;
	}
	return false;
}

bool FrameUpdateBudget::is_lane_enabled(const StringName &p_lane) const {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return lanes[i].enabled;
		}
	}
	return false;
}

int FrameUpdateBudget::get_enabled_lane_count() const {
	int count = 0;
	for (int i = 0; i < lanes.size(); i++) {
		count += lanes[i].enabled ? 1 : 0;
	}
	return count;
}

bool FrameUpdateBudget::configure(const PackedFloat64Array &p_rates, const PackedInt32Array &p_slots) {
	if (p_rates.size() != 4 || p_slots.size() != 4) {
		return false;
	}
	// Validate the complete profile before mutating it.
	for (int i = 0; i < 4; i++) {
		if (!Math::is_finite(p_rates[i]) || p_rates[i] <= 0.0 || p_rates[i] > 240.0 ||
				p_slots[i] < 1 || p_slots[i] > 64) {
			return false;
		}
	}
	for (int i = 0; i < 4; i++) {
		rates[i] = p_rates[i];
		slots[i] = p_slots[i];
	}
	profile_dirty = true;
	return true;
}

bool FrameUpdateBudget::set_frame_time_budget_us(int64_t p_budget_us) {
	if (p_budget_us < 0 || p_budget_us > 1000000) {
		return false;
	}
	frame_time_budget_us = p_budget_us;
	return true;
}

bool FrameUpdateBudget::record_cost(const StringName &p_lane, int64_t p_elapsed_us) {
	if (p_elapsed_us < 0 || p_elapsed_us > 10000000) {
		return false;
	}
	for (int i = 0; i < lanes.size(); i++) {
		Lane &lane = lanes.write[i];
		if (lane.name != p_lane) {
			continue;
		}
		// A bounded 1/4 exponential moving average predicts future cost.
		// Updating telemetry never mutates scene nodes or alters this frame's
		// already-reserved slots.
		if (p_elapsed_us > 0) {
			lane.estimated_cost_us = lane.estimated_cost_us == 0 ? p_elapsed_us :
					(3 * lane.estimated_cost_us + p_elapsed_us + 2) / 4;
		}
		frame_cost_us = MIN(int64_t(1000000000), frame_cost_us + p_elapsed_us);
		lane.frame_cost_us = MIN(int64_t(1000000000), lane.frame_cost_us + p_elapsed_us);
		return true;
	}
	return false;
}

bool FrameUpdateBudget::set_lane_importance(const StringName &p_lane, double p_importance) {
	if (!Math::is_finite(p_importance) || p_importance < 0.25 || p_importance > 4.0) {
		return false;
	}
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			lanes.write[i].importance = p_importance;
			return true;
		}
	}
	return false;
}

bool FrameUpdateBudget::set_lane_rate_scale(const StringName &p_lane, double p_scale) {
	if (!Math::is_finite(p_scale) || p_scale < 0.75 || p_scale > 2.0) {
		return false;
	}
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			lanes.write[i].rate_scale = p_scale;
			return true;
		}
	}
	return false;
}

bool FrameUpdateBudget::set_lane_max_deferred_frames(const StringName &p_lane, int p_frames) {
	if (p_frames < 0 || p_frames > 120) {
		return false;
	}
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			lanes.write[i].max_deferred_frames = p_frames;
			return true;
		}
	}
	return false;
}

int FrameUpdateBudget::get_lane_max_deferred_frames(const StringName &p_lane) const {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return lanes[i].max_deferred_frames;
		}
	}
	return -1;
}

int FrameUpdateBudget::get_deadline_overdue_lane_count() const {
	int overdue = 0;
	for (int i = 0; i < lanes.size(); i++) {
		const Lane &lane = lanes[i];
		if (lane.max_deferred_frames > 0 && lane.overdue_frames >= lane.max_deferred_frames) {
			overdue++;
		}
	}
	return overdue;
}

double FrameUpdateBudget::get_lane_rate_scale(const StringName &p_lane) const {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return lanes[i].rate_scale;
		}
	}
	return -1.0;
}

double FrameUpdateBudget::get_lane_importance(const StringName &p_lane) const {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return lanes[i].importance;
		}
	}
	return -1.0;
}

int64_t FrameUpdateBudget::get_lane_estimated_cost_us(const StringName &p_lane) const {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return lanes[i].estimated_cost_us;
		}
	}
	return -1;
}

int64_t FrameUpdateBudget::get_lane_last_frame_cost_us(const StringName &p_lane) const {
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			return lanes[i].previous_frame_cost_us;
		}
	}
	return -1;
}

void FrameUpdateBudget::begin_frame(double p_delta, int p_quality) {
	const int next_quality = CLAMP(p_quality, 0, 3);
	quality_changed = profile_dirty || next_quality != quality;
	profile_dirty = false;
	quality = next_quality;
	spent = 0;
	previous_frame_cost_us = frame_cost_us;
	frame_cost_us = 0;
	// Rotate the at-most-64 completed CPU samples without heap allocations.
	for (int i = 0; i < lanes.size(); i++) {
		Lane &lane = lanes.write[i];
		lane.previous_frame_cost_us = lane.frame_cost_us;
		lane.frame_cost_us = 0;
	}
	last_updated = 0;
	last_skipped = 0;
	reserved_estimated_cost_us = 0;
	if (Math::is_finite(p_delta) && p_delta > 0.0) {
		if (p_delta > 0.030) {
			pressure = MIN(1.0, pressure + 0.16);
		} else if (p_delta < 0.020) {
			pressure = MAX(0.0, pressure - 0.05);
		}
	}
	const int reduction = pressure >= 0.8 ? 2 : (pressure >= 0.4 ? 1 : 0);
	const int enabled_lanes = get_enabled_lane_count();
	budget = enabled_lanes == 0 ? 0 : CLAMP(slots[quality] - reduction, 1, enabled_lanes);

	// Score eligible lanes before consume() so fixed game-loop call order
	// cannot permanently favor the first cosmetic effect. This is a
	// data-only greedy selection; no callbacks and at most 64 lanes/slots.
	reserved_lanes.clear();
	if (lanes.is_empty() || quality_changed) {
		tie_start = 0;
		return; // A tier/profile change already forces all lanes to refresh.
	}
	tie_start = (tie_start + 1) % lanes.size();
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return;
	}
	for (int slot = 0; slot < budget; slot++) {
		int best = -1;
		double best_priority = -1.0;
		// First prefer due lanes whose learned cost fits the remaining
		// microsecond budget. If absolutely none fit, still reserve one:
		// a soft budget must not permanently halt expensive effects.
		for (int pass = 0; pass < 2 && best < 0; pass++) {
			if (pass == 1 && !reserved_lanes.is_empty()) {
				break;
			}
			for (int offset = 0; offset < lanes.size(); offset++) {
				const int index = (tie_start + offset) % lanes.size();
				if (reserved_lanes.has(index)) {
					continue;
				}
				const Lane &lane = lanes[index];
				if (!lane.enabled || lane.refresh_pending) {
					continue;
				}
				const double interval = 1.0 / (rates[quality] * lane.rate_scale);
				const double elapsed = MIN(lane.elapsed + p_delta, max_step);
				if (elapsed + 0.000001 < interval) {
					continue;
				}
				const bool forecast_exceeds_budget = frame_time_budget_us > 0 &&
						lane.estimated_cost_us > 0 &&
						reserved_estimated_cost_us + lane.estimated_cost_us > frame_time_budget_us;
				// Overdue lanes get an occasional opportunity regardless of
				// their predicted cost; runtime measured cost still gates
				// subsequent ordinary updates for the current frame.
				const bool deadline_due = lane.max_deferred_frames > 0 &&
						lane.overdue_frames >= lane.max_deferred_frames;
				if (pass == 0 && forecast_exceeds_budget && lane.overdue_frames < 48 && !deadline_due) {
					continue;
				}
				// An explicit soft deadline gives a due lane first chance
				// at a scarce slot even if its learned CPU cost is high.
				// The global slot/CPU budgets still gate normal execution.
				const double priority = (deadline_due ?
								1000.0 + double(lane.overdue_frames - lane.max_deferred_frames) * 0.1 : 0.0) +
						elapsed * lane.importance +
						double(MIN(lane.overdue_frames, 120)) * 0.012;
				if (priority > best_priority + 0.000000000001) {
					best = index;
					best_priority = priority;
				}
			}
		}
		if (best < 0) {
			break;
		}
		reserved_lanes.push_back(best);
		reserved_estimated_cost_us = MIN(int64_t(1000000000),
				reserved_estimated_cost_us + lanes[best].estimated_cost_us);
	}
	for (int i = 0; i < lanes.size(); i++) {
		if (!lanes[i].enabled || lanes[i].refresh_pending) {
			continue;
		}
		const double interval = 1.0 / (rates[quality] * lanes[i].rate_scale);
		const double elapsed = MIN(lanes[i].elapsed + p_delta, max_step);
		if (elapsed + 0.000001 >= interval && !reserved_lanes.has(i)) {
			lanes.write[i].overdue_frames = MIN(120, lanes[i].overdue_frames + 1);
		}
	}
}

double FrameUpdateBudget::consume(const StringName &p_lane, double p_delta, bool p_force) {
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return 0.0;
	}
	int index = -1;
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			index = i;
			break;
		}
	}
	if (index == -1) {
		return 0.0;
	}
	Lane &lane = lanes.write[index];
	// Suppressed work does not accrue stale time or starve active lanes.
	// A single forced update can still hide existing scene effects.
	if (!lane.enabled && !p_force) {
		return 0.0;
	}
	const double elapsed = MIN(lane.elapsed + p_delta, max_step);
	// Critical world visibility and profile transitions bypass the budget.
	if (p_force || quality_changed || lane.refresh_pending) {
		lane.refresh_pending = false;
		const int reserved_index = reserved_lanes.find(index);
		if (reserved_index >= 0) {
			reserved_lanes.remove_at(reserved_index);
		}
		lane.elapsed = 0.0;
		lane.overdue_frames = 0;
		record_update();
		return elapsed;
	}
	lane.elapsed = elapsed;
	const double interval = 1.0 / (rates[MAX(quality, 0)] * lane.rate_scale);
	if (elapsed + 0.000001 < interval || spent >= budget || !reserved_lanes.has(index) ||
			(frame_time_budget_us > 0 && frame_cost_us >= frame_time_budget_us)) {
		last_skipped++;
		total_skipped++;
		return 0.0;
	}
	spent++;
	// Never grant the same reservation twice within a frame.
	reserved_lanes.remove_at(reserved_lanes.find(index));
	lane.elapsed = 0.0;
	lane.overdue_frames = 0;
	record_update();
	return elapsed;
}

void FrameUpdateBudget::record_update() {
	last_updated++;
	total_updated++;
}

void FrameUpdateBudget::reset() {
	for (int i = 0; i < lanes.size(); i++) {
		lanes.write[i].elapsed = 0.0;
		lanes.write[i].overdue_frames = 0;
		lanes.write[i].refresh_pending = false;
		lanes.write[i].frame_cost_us = 0;
		lanes.write[i].previous_frame_cost_us = 0;
	}
	quality = -1;
	quality_changed = true;
	pressure = 0.0;
	frame_cost_us = 0;
	previous_frame_cost_us = 0;
	reserved_estimated_cost_us = 0;
	budget = 1;
	spent = 0;
	last_updated = 0;
	last_skipped = 0;
	reserved_lanes.clear();
	tie_start = 0;
}
