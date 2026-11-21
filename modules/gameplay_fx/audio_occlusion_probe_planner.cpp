/**************************************************************************/
/* audio_occlusion_probe_planner.cpp                                       */
/**************************************************************************/
#include "audio_occlusion_probe_planner.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_set.h"
#include "core/templates/vector.h"

namespace {
constexpr int MAX_VOICES = 128;
constexpr int MAX_PROBES = 16;
constexpr double MAX_CLOCK_SECONDS = 1000000000.0;
constexpr double PRIORITY_SECONDS = 0.15; // Maximum 450 ms age advantage.

struct Probe {
	int index;
	double urgency;
	double audibility;
	int64_t id;
};

static bool better(const Probe &p_a, const Probe &p_b) {
	if (p_a.urgency != p_b.urgency) {
		return p_a.urgency > p_b.urgency;
	}
	if (p_a.audibility != p_b.audibility) {
		return p_a.audibility > p_b.audibility;
	}
	if (p_a.id != p_b.id) {
		return p_a.id < p_b.id;
	}
	return p_a.index < p_b.index;
}
} // namespace

void AudioOcclusionProbePlanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("select_due", "next_due_seconds", "priorities", "audibilities", "ids", "now_seconds", "budget"),
			&AudioOcclusionProbePlanner::select_due);
}

PackedInt32Array AudioOcclusionProbePlanner::select_due(const PackedFloat64Array &p_next_due_seconds,
		const PackedByteArray &p_priorities, const PackedFloat64Array &p_audibilities,
		const PackedInt64Array &p_ids, double p_now_seconds, int p_budget) const {
	PackedInt32Array empty;
	const int count = p_next_due_seconds.size();
	ERR_FAIL_COND_V_MSG(count > MAX_VOICES || count != p_priorities.size() ||
					count != p_audibilities.size() || count != p_ids.size() ||
					p_budget < 0 || p_budget > MAX_PROBES ||
					!Math::is_finite(p_now_seconds) || p_now_seconds < 0.0 ||
					p_now_seconds > MAX_CLOCK_SECONDS,
			empty, "Invalid audio probe budget, clock or array lengths.");
	HashSet<int64_t> ids;
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_next_due_seconds[i]) ||
						p_next_due_seconds[i] < 0.0 || p_next_due_seconds[i] > MAX_CLOCK_SECONDS ||
						!Math::is_finite(p_audibilities[i]) || p_priorities[i] > 3 ||
						p_ids[i] <= 0 || ids.has(p_ids[i]),
				empty, "Invalid audio probe due time, audibility, priority or source ID.");
		ids.insert(p_ids[i]);
	}
	if (p_budget == 0) {
		return empty;
	}
	Vector<Probe> best;
	for (int i = 0; i < count; ++i) {
		if (p_next_due_seconds[i] > p_now_seconds) {
			continue; // Never probe a source before its configured recheck time.
		}
		Probe candidate = {
			i,
			p_now_seconds - p_next_due_seconds[i] + double(p_priorities[i]) * PRIORITY_SECONDS,
			p_audibilities[i],
			p_ids[i]
		};
		if (best.size() == p_budget && !better(candidate, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !better(candidate, best[at])) {
			++at;
		}
		best.insert(at, candidate);
		if (best.size() > p_budget) {
			best.resize(p_budget);
		}
	}
	PackedInt32Array result;
	for (const Probe &probe : best) {
		result.push_back(probe.index);
	}
	return result;
}
