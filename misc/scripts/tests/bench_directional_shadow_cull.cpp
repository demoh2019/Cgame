// Copyright (c) 2026 Cgame contributors.
// Standalone synthetic benchmark and equivalence check for upstream Godot #124897.
// No Godot headers or build required; this models the predicates and expensive-call order.
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <random>
#include <vector>

namespace {
constexpr unsigned LIGHTS = 2;
constexpr unsigned CASCADES = 4;
constexpr std::array<uint32_t, LIGHTS> CASTER_MASKS = {1U, 2U};

struct Instance {
    bool visible = true;
    bool geometry = true;
    bool casts_shadows = true;
    bool inactive_particle = false;
    uint32_t layer_mask = 3U;
    std::array<std::array<bool, CASCADES>, LIGHTS> in_frustum = {};
    uint32_t seed = 1;
};

struct Metrics {
    uint64_t expensive_calls = 0;
    uint64_t selected = 0;
    uint64_t checksum = 0;
};

// Repeatable work resembling a non-trivial directional-light culling query.
// It is intentionally *not* a measurement of Godot's real geometry algorithm.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((noinline))
#endif
bool expensive_shadow_test(uint32_t seed, unsigned light, unsigned cascade) {
    uint32_t x = seed ^ (0x9e3779b9U + light * 7U + cascade * 19U);
    for (int i = 0; i < 24; ++i) {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
    }
    return (x & 3U) != 0;
}

uint32_t original_mask(const Instance &obj, unsigned lights, Metrics &m) {
    uint32_t mask = 0;
    for (unsigned j = 0; j < lights; ++j) {
        for (unsigned k = 0; k < CASCADES; ++k) {
            ++m.expensive_calls;
            if (!expensive_shadow_test(obj.seed, j, k)) {
                continue;
            }
            if (obj.in_frustum[j][k] && obj.visible) {
                if (obj.geometry && obj.casts_shadows &&
                    (obj.layer_mask & CASTER_MASKS[j]) && !obj.inactive_particle) {
                    mask |= (1U << (j * CASCADES + k));
                }
            }
        }
    }
    return mask;
}

uint32_t optimized_mask(const Instance &obj, unsigned lights, Metrics &m) {
    uint32_t mask = 0;
    if (lights > 0 && obj.visible && obj.geometry && obj.casts_shadows && !obj.inactive_particle) {
        for (unsigned j = 0; j < lights; ++j) {
            if (!(obj.layer_mask & CASTER_MASKS[j])) {
                continue;
            }
            for (unsigned k = 0; k < CASCADES; ++k) {
                if (!obj.in_frustum[j][k]) {
                    continue;
                }
                ++m.expensive_calls;
                if (!expensive_shadow_test(obj.seed, j, k)) {
                    continue;
                }
                mask |= (1U << (j * CASCADES + k));
            }
        }
    }
    return mask;
}

Instance instance_from_bits(uint32_t bits) {
    Instance obj;
    obj.visible = (bits & 1U) != 0;
    obj.geometry = (bits & 2U) != 0;
    obj.casts_shadows = (bits & 4U) != 0;
    obj.inactive_particle = (bits & 8U) != 0;
    obj.layer_mask = (bits >> 4) & 3U;
    obj.seed = 27U * bits + 11U;
    for (unsigned j = 0; j < LIGHTS; ++j) {
        for (unsigned k = 0; k < CASCADES; ++k) {
            obj.in_frustum[j][k] = (bits & (1U << (6U + j * CASCADES + k))) != 0;
        }
    }
    return obj;
}

bool verify_equivalence() {
    Metrics original;
    Metrics optimized;
    // Exhaustively cover all combinations of 6 object-state and 8 cascade bits.
    // Also test the zero-light path and several different deterministic seeds.
    for (uint32_t bits = 0; bits < (1U << 14U); ++bits) {
        Instance obj = instance_from_bits(bits);
        for (uint32_t seed : {1U, 19U, 0xFFFFFFFFU}) {
            obj.seed = seed;
            for (unsigned lights : {0U, 1U, LIGHTS}) {
                if (original_mask(obj, lights, original) != optimized_mask(obj, lights, optimized)) {
                    std::cerr << "Mismatch: bits=" << bits << " seed=" << seed << " lights=" << lights << '\n';
                    return false;
                }
            }
        }
    }
    std::cout << "PASS: exhaustive synthetic selection equivalence (147456 cases)\n";
    return true;
}

Metrics benchmark_pass(const std::vector<Instance> &objects, bool optimized) {
    Metrics total;
    for (const Instance &obj : objects) {
        const uint32_t mask = optimized ? optimized_mask(obj, LIGHTS, total)
                                        : original_mask(obj, LIGHTS, total);
        total.selected += static_cast<uint64_t>(__builtin_popcount(mask));
        total.checksum = total.checksum * 131U + mask;
    }
    return total;
}
} // namespace

int main() {
    if (!verify_equivalence()) {
        return EXIT_FAILURE;
    }
    std::mt19937 rng(0xC0FFEEU);
    std::vector<Instance> objects;
    objects.reserve(40000);
    for (unsigned i = 0; i < 40000; ++i) {
        Instance obj;
        obj.seed = rng();
        obj.visible = (rng() % 100U) < 85U;
        obj.geometry = (rng() % 100U) < 80U;
        obj.casts_shadows = (rng() % 100U) < 25U;
        obj.inactive_particle = (rng() % 100U) < 5U;
        obj.layer_mask = rng() % 4U;
        for (unsigned j = 0; j < LIGHTS; ++j) {
            for (unsigned k = 0; k < CASCADES; ++k) {
                obj.in_frustum[j][k] = (rng() % 100U) < 35U;
            }
        }
        objects.push_back(obj);
    }
    auto timed = [&](bool opt) {
        const auto t0 = std::chrono::steady_clock::now();
        Metrics result = benchmark_pass(objects, opt);
        const auto dt = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
        std::cout << (opt ? "optimized" : "original") << ": " << dt << " us, "
                  << result.expensive_calls << " expensive predicate calls, "
                  << result.selected << " selected cascades\n";
        return result;
    };
    const Metrics base = timed(false);
    const Metrics fast = timed(true);
    if (base.selected != fast.selected || base.checksum != fast.checksum ||
        fast.expensive_calls >= base.expensive_calls) {
        std::cerr << "FAIL: output mismatch or no reduction in expensive cull calls\n";
        return EXIT_FAILURE;
    }
    std::cout << "PASS: expensive calls saved = " << base.expensive_calls - fast.expensive_calls << '\n';
    return EXIT_SUCCESS;
}
