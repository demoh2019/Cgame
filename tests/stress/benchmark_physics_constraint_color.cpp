// Standalone microbenchmark for GodotPhysics2D/3D's greedy color selection.
// This is not an engine physics-step benchmark.
//
// Build with any C++17 compiler:
//   c++ -O3 -std=c++17 -I. tests/stress/benchmark_physics_constraint_color.cpp -o /tmp/cgame-color-bench
//   /tmp/cgame-color-bench
//
// Include the exact helper linked by both actual physics solvers.
#include "servers/physics_constraint_color.h"

#include <chrono>
#include <cstdint>
#include <iostream>
#include <vector>

static uint32_t legacy_first_available_color(uint32_t p_used_colors) {
	uint32_t color = 16;
	for (uint32_t candidate = 0; candidate < 16; ++candidate) {
		if ((p_used_colors & (uint32_t(1) << candidate)) == 0) {
			color = candidate;
			break;
		}
	}
	return color;
}

template <typename F>
static double benchmark_ns_per_selection(const std::vector<uint32_t> &p_masks, F p_selector) {
	volatile uint64_t sink = 0;
	const auto start = std::chrono::steady_clock::now();
	for (uint32_t repeat = 0; repeat < 80; ++repeat) {
		for (uint32_t mask : p_masks) {
			sink += p_selector(mask);
		}
	}
	const auto end = std::chrono::steady_clock::now();
	if (sink == UINT64_MAX) {
		std::cerr << "Impossible benchmark sink value.\n";
	}
	return std::chrono::duration<double, std::nano>(end - start).count() / (p_masks.size() * 80.0);
}

int main() {
	for (uint32_t mask = 0; mask <= 0xFFFFu; ++mask) {
		const uint32_t expected = legacy_first_available_color(mask);
		if (godot_physics_first_available_constraint_color<16>(mask) != expected ||
				godot_physics_first_available_constraint_color<16>(mask | 0xFFFF0000u) != expected) {
			std::cerr << "Color mismatch for mask " << mask << "\n";
			return 1;
		}
	}
	std::cout << "Verified 65536 color masks plus high-bit variants.\n";

	constexpr uint32_t SAMPLE_COUNT = 100000;
	uint32_t rng = 0xA1382561u;
	for (uint32_t scenario = 0; scenario < 3; ++scenario) {
		std::vector<uint32_t> masks;
		masks.reserve(SAMPLE_COUNT);
		for (uint32_t i = 0; i < SAMPLE_COUNT; ++i) {
			// xorshift32: deterministic inputs; same workload for both selectors.
			rng ^= rng << 13;
			rng ^= rng >> 17;
			rng ^= rng << 5;
			uint32_t mask = 0;
			if (scenario == 0) {
				mask = rng & 3u; // Predominantly color 0/1.
			} else if (scenario == 1) {
				mask = rng & 0xFFFFu; // Arbitrary 16-bit masks.
			} else {
				mask = 0xFFFFu ^ (uint32_t(1) << (rng % 16)); // Saturated graph hub.
			}
			masks.push_back(mask);
		}

		const double legacy_ns = benchmark_ns_per_selection(masks, legacy_first_available_color);
		const double bit_scan_ns = benchmark_ns_per_selection(masks, [](uint32_t mask) {
			return godot_physics_first_available_constraint_color<16>(mask);
		});
		std::cout << (scenario == 0 ? "few_conflicts" : scenario == 1 ? "random_masks" : "saturated_colors")
				  << ": legacy=" << legacy_ns << " ns; bit_scan=" << bit_scan_ns
				  << " ns; ratio=" << (legacy_ns / bit_scan_ns) << "x\n";
	}

	return 0;
}
