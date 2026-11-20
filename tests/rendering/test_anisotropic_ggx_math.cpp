#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>

// Portable numerical reference for the engine's Forward+ anisotropic GGX
// shader (the GPU compiler and Godot runtime are checked separately).
float distribution(float alpha_x, float alpha_y, float cth, float cph, float sph) {
	const float ax = std::max(alpha_x, 0.004f);
	const float ay = std::max(alpha_y, 0.004f);
	const float alpha2 = ax * ay;
	const float vx = ay * cph, vy = ax * sph, vz = alpha2 * cth;
	const float v2 = std::max(vx * vx + vy * vy + vz * vz, 1e-10f);
	const float w2 = alpha2 / v2;
	return std::min(alpha2 * w2 * w2 * (1.0f / 3.14159265358979323846f), 65504.0f);
}

float visibility(float ax_input, float ay_input, float tdv, float tdl,
		float bdv, float bdl, float ndv, float ndl) {
	const float ax = std::max(ax_input, 0.004f);
	const float ay = std::max(ay_input, 0.004f);
	const float lambda_v = ndl * std::sqrt(ax * ax * tdv * tdv + ay * ay * bdv * bdv + ndv * ndv);
	const float lambda_l = ndv * std::sqrt(ax * ax * tdl * tdl + ay * ay * bdl * bdl + ndl * ndl);
	return std::min(0.5f / std::max(lambda_v + lambda_l, 1e-4f), 65504.0f);
}

int main() {
	for (float rough : std::array<float, 7>{0.0f, 0.00001f, 0.004f, 0.01f, 0.1f, 0.5f, 1.0f}) {
		for (float angle : std::array<float, 6>{0.0f, 0.000001f, 0.005f, 0.1f, 0.5f, 1.0f}) {
			const float d = distribution(rough, rough * 0.05f, angle, angle, 1.0f - angle);
			const float v = visibility(rough, rough * 0.1f, angle, 1.0f - angle,
					angle, 1.0f - angle, angle, 1.0f - angle);
			assert(std::isfinite(d) && d >= 0.0f && d <= 65504.0f);
			assert(std::isfinite(v) && v >= 0.0f && v <= 65504.0f);
		}
	}
	assert(distribution(0.0f, 0.0f, 0.0f, 0.0f, 0.0f) >= 0.0f);
	assert(visibility(0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f) > 0.0f);
}
