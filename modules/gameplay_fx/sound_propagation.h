// Native pure hearing-range policy shared by sound and authoritative AI.
#pragma once

#include "core/object/ref_counted.h"

class SoundPropagation : public RefCounted {
	GDCLASS(SoundPropagation, RefCounted);

protected:
	static void _bind_methods();

public:
	// The already wind-adjusted radius is attenuated by physical cover.
	// Loud gunshots penetrate farther than steps, without exceeding the
	// server-provided leash or creating detections from silence.
	float effective_radius(float p_source_radius, float p_wind_radius, bool p_blocked) const;
};
