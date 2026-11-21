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
	ClassDB::bind_method(D_METHOD("configure", "quality_rates", "quality_slots"), &FrameUpdateBudget::configure);
	ClassDB::bind_method(D_METHOD("begin_frame", "delta", "quality"), &FrameUpdateBudget::begin_frame);
	ClassDB::bind_method(D_METHOD("set_frame_time_budget_us", "budget_us"), &FrameUpdateBudget::set_frame_time_budget_us);
	ClassDB::bind_method(D_METHOD("get_frame_time_budget_us"), &FrameUpdateBudget::get_frame_time_budget_us);
	ClassDB::bind_method(D_METHOD("record_cost", "lane", "elapsed_us"), &FrameUpdateBudget::record_cost);
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
	bool registered = false;
	for (int i = 0; i < lanes.size(); i++) {
		if (lanes[i].name == p_lane) {
			registered = true;
			break;
		}
	}
	if (!registered) {
		return false;
	}
	frame_cost_us = MIN(int64_t(1000000000), frame_cost_us + p_elapsed_us);
	return true;
}

void FrameUpdateBudget::begin_frame(double p_delta, int p_quality) {
	const int next_quality = CLAMP(p_quality, 0, 3);
	quality_changed = profile_dirty || next_quality != quality;
	profile_dirty = false;
	quality = next_quality;
	spent = 0;
	previous_frame_cost_us = frame_cost_us;
	frame_cost_us = 0;
	last_updated = 0;
	last_skipped = 0;
	if (Math::is_finite(p_delta) && p_delta > 0.0) {
		if (p_delta > 0.030) {
			pressure = MIN(1.0, pressure + 0.16);
		} else if (p_delta < 0.020) {
			pressure = MAX(0.0, pressure - 0.05);
		}
	}
	const int reduction = pressure >= 0.8 ? 2 : (pressure >= 0.4 ? 1 : 0);
	budget = CLAMP(slots[quality] - reduction, 1, MAX(1, lanes.size()));

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
	const double interval = 1.0 / rates[quality];
	for (int slot = 0; slot < budget; slot++) {
		int best = -1;
		double best_elapsed = -1.0;
		for (int offset = 0; offset < lanes.size(); offset++) {
			const int index = (tie_start + offset) % lanes.size();
			if (reserved_lanes.has(index)) {
				continue;
			}
			const double elapsed = MIN(lanes[index].elapsed + p_delta, max_step);
			if (elapsed + 0.000001 >= interval && elapsed > best_elapsed + 0.000000000001) {
				best = index;
				best_elapsed = elapsed;
			}
		}
		if (best < 0) {
			break;
		}
		reserved_lanes.push_back(best);
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
	const double elapsed = MIN(lane.elapsed + p_delta, max_step);
	// Critical world visibility and profile transitions bypass the budget.
	if (p_force || quality_changed) {
		lane.elapsed = 0.0;
		record_update();
		return elapsed;
	}
	lane.elapsed = elapsed;
	const double interval = 1.0 / rates[MAX(quality, 0)];
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
	}
	quality = -1;
	quality_changed = true;
	pressure = 0.0;
	frame_cost_us = 0;
	previous_frame_cost_us = 0;
	budget = 1;
	spent = 0;
	last_updated = 0;
	last_skipped = 0;
	reserved_lanes.clear();
	tie_start = 0;
}
