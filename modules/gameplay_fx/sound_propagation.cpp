#include "sound_propagation.h"

#include "sound_propagation_policy.h"

#include "core/object/class_db.h"

void SoundPropagation::_bind_methods() {
	ClassDB::bind_method(D_METHOD("effective_radius", "source_radius", "wind_radius", "blocked"),
			&SoundPropagation::effective_radius);
}

float SoundPropagation::effective_radius(float p_source_radius, float p_wind_radius, bool p_blocked) const {
	return SoundPropagationPolicy::hearing_radius(p_source_radius, p_wind_radius, p_blocked);
}
