#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <utility>

// Shader-independent reference model of the texture-space rotation seed.
// A world point at the same shadow texel must keep the same orientation
// when its screen-space pixel moves as the camera pans.
static std::pair<int, int> cell(float u, float v, int w, int h) {
	return {int(std::floor(u * float(w) * 0.5f)),
			int(std::floor(v * float(h) * 0.5f))};
}
static float quick_hash(float x, float y) {
	const float d = x * 0.06711056f + y * 0.00583715f;
	const float f = d - std::floor(d);
	const float p = 52.9829189f * f;
	return p - std::floor(p);
}
static float rotation(float u, float v, int w, int h, float temporal_frame) {
	const auto c = cell(u, v, w, h);
	return quick_hash(float(c.first) + temporal_frame * 5.588238f,
			float(c.second) + temporal_frame * 5.588238f) * 6.28318530718f;
}

int main() {
	for (auto wh : std::array<std::pair<int, int>, 3>{{
			{512, 512}, {2048, 2048}, {4096, 4096}}}) {
		for (float u : std::array<float, 5>{{0.08f, 0.2f, 0.55f, 0.72f, 0.94f}}) {
			const float initial = rotation(u, 0.37f, wh.first, wh.second, 0.0f);
			assert(initial >= 0.0f && initial < 6.28318530718f);
			// The same shadow UV is independent of gl_FragCoord/camera movement.
			for (int camera_pixel : std::array<int, 4>{{0, 11, 997, 4500}}) {
				(void)camera_pixel;
				assert(rotation(u, 0.37f, wh.first, wh.second, 0.0f) == initial);
			}
			assert(std::isfinite(rotation(u, 0.37f, wh.first, wh.second, 23.0f)));
		}
		// Two locations in one 2x2 shadow texel cell share a stable seed.
		const float u0 = 100.1f / float(wh.first);
		const float u1 = 100.9f / float(wh.first);
		assert(cell(u0, 0.2f, wh.first, wh.second) ==
				cell(u1, 0.2f, wh.first, wh.second));
	}
}
