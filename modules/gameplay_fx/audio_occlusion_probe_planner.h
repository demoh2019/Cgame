/**************************************************************************/
/* audio_occlusion_probe_planner.h - main-thread, data-only audio planning */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

/**
 * Priority/age-based selection of sound obstruction probes.
 * No audio server, physics, scene nodes, global state or wall-clock access.
 */
class AudioOcclusionProbePlanner : public RefCounted {
	GDCLASS(AudioOcclusionProbePlanner, RefCounted);

protected:
	static void _bind_methods();

public:
	// Returns at most 16 due indices, ordered by overdue age + priority, then
	// audibility and stable ID. Array size is bounded to 128.
	PackedInt32Array select_due(const PackedFloat64Array &p_next_due_seconds,
			const PackedByteArray &p_priorities,
			const PackedFloat64Array &p_audibilities,
			const PackedInt64Array &p_ids,
			double p_now_seconds, int p_budget) const;
};
