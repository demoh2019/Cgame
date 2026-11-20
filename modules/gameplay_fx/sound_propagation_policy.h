// Lightweight, deterministic occluded-hearing range for AI/audio events.
// Higher-energy sources retain more low-frequency reach through a single
// obstacle; the world owns geometry and performs at most one bounded query.
// This header has no Godot dependency and is suitable for portable C++ tests.
#pragma once

#include <algorithm>
#include <cmath>

namespace SoundPropagationPolicy {
constexpr float QUIET_REFERENCE = 21.0f;
constexpr float LOUD_REFERENCE = 32.0f;
constexpr float QUIET_TRANSMISSION = 0.62f;
constexpr float LOUD_TRANSMISSION = 0.80f;

inline float transmission(float p_source_radius) {
	if (!std::isfinite(p_source_radius) || p_source_radius <= 0.0f) {
		return 0.0f;
	}
	const float t = std::clamp((p_source_radius - QUIET_REFERENCE) /
			(LOUD_REFERENCE - QUIET_REFERENCE), 0.0f, 1.0f);
	return QUIET_TRANSMISSION + t * (LOUD_TRANSMISSION - QUIET_TRANSMISSION);
}

// p_wind_radius is already clipped to an infected's pursuit leash.
// Never create noise from silence or increase the previously heard range.
inline float hearing_radius(float p_source_radius, float p_wind_radius, bool p_blocked) {
	if (!std::isfinite(p_source_radius) || p_source_radius <= 0.0f ||
			!std::isfinite(p_wind_radius) || p_wind_radius <= 0.0f) {
		return 0.0f;
	}
	const float radius = std::max(p_wind_radius, 0.0f);
	return p_blocked ? radius * transmission(p_source_radius) : radius;
}
// Lightweight speed-of-sound propagation delay for lightning/thunder.
// 331.3 + 0.606*T [m/s] approximates dry air over a bounded temperature
// range. The listener sees the flash at once, but hears the impact later.
// -1 is a sentinel for invalid/out-of-range events, never "play now".
constexpr float THUNDER_MAX_DISTANCE_M = 2400.0f;
constexpr float THUNDER_MIN_TEMPERATURE_C = -40.0f;
constexpr float THUNDER_MAX_TEMPERATURE_C = 60.0f;

inline float sound_delay_seconds(float p_distance_m, float p_temperature_c = 20.0f) {
	if (!std::isfinite(p_distance_m) || !std::isfinite(p_temperature_c) ||
			p_distance_m < 0.0f || p_distance_m > THUNDER_MAX_DISTANCE_M ||
			p_temperature_c < THUNDER_MIN_TEMPERATURE_C ||
			p_temperature_c > THUNDER_MAX_TEMPERATURE_C) {
		return -1.0f;
	}
	const float meters_per_second = 331.3f + 0.606f * p_temperature_c;
	return p_distance_m / meters_per_second;
}
} // namespace SoundPropagationPolicy
