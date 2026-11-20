#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <limits>

// Standalone numerical reference for the shader's finite screen-axis math.
// The actual GLSL source is checked separately by CI; Godot runtime tests
// and live GPU benchmarks still require the custom Cgame engine.
static float safe_axis(float value) {
	return (value < 0.0f ? -1.0f : 1.0f) *
			std::max(std::abs(value), 0.000001f);
}

static bool can_trace(float dx, float dy, float dz) {
	return std::isfinite(dx) && std::isfinite(dy) && std::isfinite(dz) &&
			std::abs(dz) > 0.000001f &&
			(dx * dx + dy * dy) > 0.000000000001f;
}

int main() {
	assert(safe_axis(0.0f) == 0.000001f);
	assert(safe_axis(0.00000001f) == 0.000001f);
	assert(safe_axis(-0.00000001f) == -0.000001f);
	assert(safe_axis(0.2f) == 0.2f);
	assert(safe_axis(-0.2f) == -0.2f);
	const std::array<std::array<float, 2>, 8> rays = {{
		{{0.0f, 1.0f}}, {{0.0f, -1.0f}},
		{{1.0f, 0.0f}}, {{-1.0f, 0.0f}},
		{{0.000001f, 0.01f}}, {{-0.000001f, -0.01f}},
		{{0.45f, 0.35f}}, {{-0.25f, 0.4f}}
	}};
	for (const auto &ray : rays) {
		assert(can_trace(ray[0], ray[1], -1.0f));
		for (float axis : ray) {
			const float t = 0.5f / safe_axis(axis);
			assert(std::isfinite(t));
		}
	}
	assert(!can_trace(0.0f, 0.0f, -1.0f));
	assert(!can_trace(0.5f, 0.5f, 0.0f));
	assert(!can_trace(0.5f, 0.5f, 0.0000001f));
	assert(!can_trace(std::numeric_limits<float>::infinity(), 0.1f, 1.0f));
	assert(!can_trace(std::numeric_limits<float>::quiet_NaN(), 0.1f, 1.0f));
	assert(!can_trace(0.1f, 0.1f, std::numeric_limits<float>::infinity()));
}
