// Standalone microbenchmark for the actual Godot Unicode case tables.
// Build from the repository root:
// c++ -O3 -std=c++17 -I. misc/scripts/benchmarks/benchmark_unicode_ascii.cpp -o /tmp/cgame-case-bench
// /tmp/cgame-case-bench
#include "core/string/ucaps.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

using Clock = std::chrono::steady_clock;

static inline uint32_t original_lower(uint32_t codepoint) {
	return _find_lower(static_cast<int>(codepoint));
}

static inline uint32_t fast_lower(uint32_t codepoint) {
	if (codepoint < 128) {
		return codepoint >= 'A' && codepoint <= 'Z' ? codepoint + ('a' - 'A') : codepoint;
	}
	return _find_lower(static_cast<int>(codepoint));
}

static inline uint32_t original_upper(uint32_t codepoint) {
	return _find_upper(static_cast<int>(codepoint));
}

static inline uint32_t fast_upper(uint32_t codepoint) {
	if (codepoint < 128) {
		return codepoint >= 'a' && codepoint <= 'z' ? codepoint - ('a' - 'A') : codepoint;
	}
	return _find_upper(static_cast<int>(codepoint));
}

static bool check_equivalence() {
	// All ASCII inputs and non-ASCII entries from each actual Godot mapping table.
	for (uint32_t codepoint = 0; codepoint < 128; ++codepoint) {
		if (original_lower(codepoint) != fast_lower(codepoint) || original_upper(codepoint) != fast_upper(codepoint)) {
			return false;
		}
	}
	for (int i = 0; i < UTL_LEN; i++) {
		const uint32_t codepoint = reverse_caps_table[i][0];
		if (original_lower(codepoint) != fast_lower(codepoint)) {
			return false;
		}
	}
	for (int i = 0; i < LTU_LEN; i++) {
		const uint32_t codepoint = caps_table[i][0];
		if (original_upper(codepoint) != fast_upper(codepoint)) {
			return false;
		}
	}
	return true;
}

using CaseTransform = uint32_t (*)(uint32_t);
static uint64_t run_case(const std::vector<uint32_t> &corpus, CaseTransform transform, int iterations, double &r_ns_per_char) {
	volatile uint64_t checksum = 0;
	const auto begin = Clock::now();
	for (int i = 0; i < iterations; ++i) {
		for (const uint32_t ch : corpus) {
			checksum = checksum + transform(ch);
		}
	}
	const auto end = Clock::now();
	const double elapsed_ns = std::chrono::duration<double, std::nano>(end - begin).count();
	r_ns_per_char = elapsed_ns / (static_cast<double>(iterations) * corpus.size());
	return checksum;
}

static void benchmark(const char *label, const std::vector<uint32_t> &corpus, CaseTransform old_transform, CaseTransform new_transform) {
	constexpr int iterations = 8000;
	double before = 0;
	double after = 0;
	const uint64_t old_sum = run_case(corpus, old_transform, iterations, before);
	const uint64_t new_sum = run_case(corpus, new_transform, iterations, after);
	if (old_sum != new_sum) {
		std::fprintf(stderr, "FAIL: %s produced different checksums\n", label);
		std::exit(1);
	}
	std::printf("%-14s baseline %8.3f ns/char; fast %8.3f ns/char; speedup %.2fx\n", label, before, after, after == 0 ? 0.0 : before / after);
}

int main() {
	if (!check_equivalence()) {
		std::fprintf(stderr, "ERROR: Unicode table equivalence failed\n");
		return 1;
	}

	std::vector<uint32_t> ascii;
	std::vector<uint32_t> mixed;
	std::vector<uint32_t> unicode;
	ascii.reserve(1024);
	mixed.reserve(1024);
	unicode.reserve(1024);
	for (int i = 0; i < 1024; ++i) {
		const uint32_t a = static_cast<uint32_t>(32 + (i * 31) % 95);
		const uint32_t u = static_cast<uint32_t>(reverse_caps_table[i % UTL_LEN][0]);
		ascii.push_back(a);
		mixed.push_back(i % 8 == 0 ? u : a);
		unicode.push_back(u);
	}
	benchmark("ASCII lowercase", ascii, original_lower, fast_lower);
	benchmark("Mixed lowercase", mixed, original_lower, fast_lower);
	benchmark("Unicode lower", unicode, original_lower, fast_lower);
	benchmark("ASCII uppercase", ascii, original_upper, fast_upper);
	benchmark("Mixed uppercase", mixed, original_upper, fast_upper);
	benchmark("Unicode upper", unicode, original_upper, fast_upper);
	return 0;
}
