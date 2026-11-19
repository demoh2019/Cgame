// Standalone differential test for Image::blit_rect_mask's RGBA8 run-copy fast path.
// No Godot headers required: compare byte-exact against the existing scalar loops.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <random>
#include <vector>

struct Blit {
    int sw, dw, sx, sy, dx, dy, rw, rh, pixel_bytes;
};

#if defined(__GNUC__) || defined(__clang__)
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif

NOINLINE void legacy(const std::vector<uint8_t> &src, const std::vector<uint8_t> &mask,
                     std::vector<uint8_t> &dst, const Blit &b) {
    for (int y = 0; y < b.rh; y++) {
        for (int x = 0; x < b.rw; x++) {
            const size_t p = size_t(b.sy + y) * b.sw + b.sx + x;
            if (mask[p * 4 + 3] != 0) {
                const size_t d = size_t(b.dy + y) * b.dw + b.dx + x;
                for (int i = 0; i < b.pixel_bytes; i++) {
                    dst[d * b.pixel_bytes + i] = src[p * b.pixel_bytes + i];
                }
            }
        }
    }
}

NOINLINE void batched(const std::vector<uint8_t> &src, const std::vector<uint8_t> &mask,
                      std::vector<uint8_t> &dst, const Blit &b) {
    for (int y = 0; y < b.rh; y++) {
        const size_t source_pixel = size_t(b.sy + y) * b.sw + b.sx;
        const size_t dest_pixel = size_t(b.dy + y) * b.dw + b.dx;
        const uint8_t *mask_alpha = mask.data() + source_pixel * 4 + 3;
        int x = 0;
        while (x < b.rw) {
            while (x < b.rw && mask_alpha[size_t(x) * 4] == 0) { x++; }
            const int run_start = x;
            while (x < b.rw && mask_alpha[size_t(x) * 4] != 0) { x++; }
            if (run_start != x) {
                std::memcpy(dst.data() + (dest_pixel + run_start) * b.pixel_bytes,
                            src.data() + (source_pixel + run_start) * b.pixel_bytes,
                            size_t(x - run_start) * b.pixel_bytes);
            }
        }
    }
}

int main() {
    std::mt19937 rng(0x5a71c31u);
    constexpr int SW = 103, SH = 59, DW = 127, DH = 71;
    int cases = 0;
    for (int bytes : {1, 2, 3, 4, 8, 16}) {
        std::vector<uint8_t> source(size_t(SW) * SH * bytes);
        std::vector<uint8_t> mask(size_t(SW) * SH * 4);
        std::vector<uint8_t> original(size_t(DW) * DH * bytes);
        for (uint8_t &v : source) { v = uint8_t(rng()); }
        for (uint8_t &v : original) { v = uint8_t(rng()); }
        for (int mode = 0; mode < 5; mode++) {
            for (int y = 0; y < SH; y++) {
                for (int x = 0; x < SW; x++) {
                    int a = mode == 0 ? 0 : mode == 1 ? 255 : mode == 2 ? ((x + y) & 1 ? 0 : 1)
                            : mode == 3 ? (x / 9 % 4 ? 255 : 0) : int(rng() & 255);
                    mask[(size_t(y) * SW + x) * 4 + 3] = uint8_t(a);
                }
            }
            for (int trial = 0; trial < 500; trial++) {
                const int sx = int(rng() % SW), sy = int(rng() % SH);
                const int dx = int(rng() % DW), dy = int(rng() % DH);
                const int wmax = std::min(SW - sx, DW - dx);
                const int hmax = std::min(SH - sy, DH - dy);
                const Blit b = {SW, DW, sx, sy, dx, dy, 1 + int(rng() % wmax), 1 + int(rng() % hmax), bytes};
                auto expected = original;
                auto actual = original;
                legacy(source, mask, expected, b);
                batched(source, mask, actual, b);
                if (expected != actual) {
                    std::cerr << "Mismatch: bytes=" << bytes << " mask_mode=" << mode << " trial=" << trial << '\n';
                    return 1;
                }
                cases++;
            }
        }
    }
    std::cout << "Byte-exact differential cases: " << cases << "\n";

    // Compare identical 1920 x 1080 pixel buffers and contiguous 64-pixel alpha runs.
    constexpr int W = 1920, H = 1080, REPEATS = 35;
    Blit b = {W, W, 0, 0, 0, 0, W, H, 4};
    std::vector<uint8_t> source(size_t(W) * H * 4), mask(source.size()), dst(source.size());
    for (uint8_t &v : source) { v = uint8_t(rng()); }
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            mask[(size_t(y) * W + x) * 4 + 3] = ((x / 64 + y / 64) % 5 == 0) ? 0 : 255;
        }
    }
    auto run = [&](bool use_batched) {
        const auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < REPEATS; i++) {
            if (use_batched) { batched(source, mask, dst, b); }
            else { legacy(source, mask, dst, b); }
        }
        const auto end = std::chrono::steady_clock::now();
        uint64_t checksum = 0;
        for (size_t i = 0; i < dst.size(); i += 4093) { checksum += dst[i]; }
        return std::pair<double, uint64_t>(std::chrono::duration<double, std::milli>(end - start).count(), checksum);
    };
    auto old = run(false), optimized = run(true);
    if (old.second != optimized.second) { std::cerr << "Checksum mismatch\n"; return 2; }
    std::cout << "Synthetic 1920x1080 RGBA8, 35 iterations: scalar=" << old.first
              << " ms, batched=" << optimized.first << " ms; checksum=" << optimized.second << '\n';
    return 0;
}
