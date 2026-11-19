// Reference-model differential tests and synthetic benchmark for Cgame canvas Z bins.
// Standalone; does not claim to benchmark actual engine FPS or GPU time.
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <random>
#include <vector>

static constexpr int kMinZ = -4096;
static constexpr int kMaxZ = 4096;
static constexpr int kZCount = kMaxZ - kMinZ + 1;

struct FullScan {
    std::vector<int> head = std::vector<int>(kZCount, -1);
    std::vector<int> tail = std::vector<int>(kZCount, -1);
    std::vector<int> next;
    uint64_t examined = 0;
    uint64_t cleared = 0;

    void begin(int size) {
        std::fill(head.begin(), head.end(), -1);
        std::fill(tail.begin(), tail.end(), -1);
        cleared += 2 * kZCount;
        next.assign(size, -1);
    }
    void add(int id, int z) {
        const int slot = z - kMinZ;
        if (tail[slot] != -1) {
            next[tail[slot]] = id;
        } else {
            head[slot] = id;
        }
        tail[slot] = id;
    }
    std::vector<int> output() {
        std::vector<int> values;
        for (int slot = 0; slot < kZCount; ++slot) {
            ++examined;
            for (int id = head[slot]; id != -1; id = next[id]) {
                values.push_back(id);
            }
        }
        return values;
    }
};

struct UsedSpan {
    std::vector<int> head = std::vector<int>(kZCount, -1);
    std::vector<int> tail = std::vector<int>(kZCount, -1);
    std::vector<int> next;
    int min_used = kZCount;
    int max_used = -1;
    uint64_t examined = 0;
    uint64_t cleared = 0;

    void begin(int size) {
        if (min_used <= max_used) {
            for (int i = min_used; i <= max_used; ++i) {
                head[i] = tail[i] = -1;
                cleared += 2;
            }
        }
        min_used = kZCount;
        max_used = -1;
        next.assign(size, -1);
    }
    void add(int id, int z) {
        const int slot = z - kMinZ;
        if (tail[slot] != -1) {
            next[tail[slot]] = id;
        } else {
            head[slot] = id;
            min_used = std::min(min_used, slot);
            max_used = std::max(max_used, slot);
        }
        tail[slot] = id;
    }
    std::vector<int> output() {
        std::vector<int> values;
        for (int slot = min_used; slot <= max_used; ++slot) {
            ++examined;
            for (int id = head[slot]; id != -1; id = next[id]) {
                values.push_back(id);
            }
        }
        return values;
    }
};

static std::vector<int> make_frame(std::mt19937 &rng, int frame) {
    if (frame % 17 == 0) return {}; // Empty frame must clear all previously occupied bins.
    const int count = 1 + (rng() % 150);
    std::vector<int> z;
    z.reserve(count);
    for (int i = 0; i < count; ++i) {
        int value;
        if (frame % 41 == 0) {
            value = i % 2 ? kMinZ : kMaxZ;
        } else if (frame % 29 == 0) {
            value = int(rng() % kZCount) + kMinZ;
        } else if (frame % 7 == 0) {
            value = kMinZ;
        } else if (frame % 11 == 0) {
            value = kMaxZ;
        } else {
            value = int(rng() % 9) - 4;
        }
        z.push_back(value);
    }
    return z;
}

int main() {
    const auto start = std::chrono::steady_clock::now();
    FullScan baseline;
    UsedSpan optimized;
    std::mt19937 rng(0x5eed1234U);
    constexpr int kFrames = 12000;
    uint64_t total_items = 0;
    uint64_t checksum = 0;
    for (int frame = 0; frame < kFrames; ++frame) {
        const std::vector<int> z = make_frame(rng, frame);
        baseline.begin((int)z.size());
        optimized.begin((int)z.size());
        for (int i = 0; i < (int)z.size(); ++i) {
            baseline.add(i, z[i]);
            optimized.add(i, z[i]);
        }
        const std::vector<int> old_items = baseline.output();
        const std::vector<int> new_items = optimized.output();
        assert(old_items == new_items);
        assert(old_items.size() == z.size());
        total_items += z.size();
        for (const int id : new_items) checksum = checksum * 1315423911u + uint64_t(id + 1);
    }
    // A completely empty frame followed by a different Z must not leak stale buckets.
    baseline.begin(1); optimized.begin(1);
    baseline.add(0, kMinZ); optimized.add(0, kMinZ);
    assert(baseline.output() == optimized.output());
    baseline.begin(0); optimized.begin(0);
    assert(baseline.output() == optimized.output());
    baseline.begin(1); optimized.begin(1);
    baseline.add(0, kMaxZ); optimized.add(0, kMaxZ);
    assert(baseline.output() == optimized.output());

    const auto elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    assert(optimized.examined < baseline.examined);
    assert(optimized.cleared < baseline.cleared);
    std::printf("PASS frames=%d items=%llu checksum=%llu\n", kFrames, (unsigned long long)total_items, (unsigned long long)checksum);
    std::printf("full_scan_bins=%llu used_span_scan_bins=%llu full_clear_slots=%llu used_span_clear_slots=%llu elapsed_ms=%.3f\n",
            (unsigned long long)baseline.examined, (unsigned long long)optimized.examined,
            (unsigned long long)baseline.cleared, (unsigned long long)optimized.cleared, elapsed);
}
