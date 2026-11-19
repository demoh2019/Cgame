// Standalone differential test and microbenchmark of Godot String::indent algorithms.
// Build: c++ -std=c++17 -O2 -Wall -Wextra benchmark_string_indent.cpp -o indent_bench
#include <cassert>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <string>

using Text = std::u32string;

// Mirror the old Godot implementation: repeated String += prefix + substr.
static Text legacy_indent(const Text &input, const Text &prefix) {
    Text result;
    std::size_t start = 0;
    for (std::size_t i = 0; i < input.size(); ++i) {
        if (input[i] == U'\n') {
            if (i == start) {
                result += U'\n';
            } else {
                result = result + prefix + input.substr(start, i - start + 1);
            }
            start = i + 1;
        }
    }
    if (start != input.size()) {
        result = result + prefix + input.substr(start);
    }
    return result;
}

// Same two passes and one result allocation as the Godot optimized implementation.
static Text fast_indent(const Text &input, const Text &prefix) {
    if (input.empty() || prefix.empty()) return input;
    std::size_t nonempty_lines = 0;
    bool line_start = true;
    for (char32_t ch : input) {
        if (line_start && ch != U'\n') ++nonempty_lines;
        line_start = ch == U'\n';
    }
    if (nonempty_lines == 0) return input;
    const std::size_t size = input.size() + nonempty_lines * prefix.size();
    Text result;
    result.resize(size);
    std::size_t offset = 0;
    line_start = true;
    for (char32_t ch : input) {
        if (line_start && ch != U'\n') {
            for (char32_t pc : prefix) result[offset++] = pc;
        }
        result[offset++] = ch;
        line_start = ch == U'\n';
    }
    assert(offset == size);
    return result;
}

int main() {
    std::mt19937 rng(0x6cafe88u);
    const Text alphabet = { U' ', U'\t', U'\n', U'α', U'β', U'Я', U'я', U'😀', U'a', U'b', U'\0', U'x' };
    for (int test = 0; test < 16000; ++test) {
        Text value;
        Text prefix;
        const int input_size = static_cast<int>(rng() % 100);
        const int prefix_size = static_cast<int>(rng() % 12);
        for (int i = 0; i < input_size; ++i) value += alphabet[rng() % alphabet.size()];
        for (int i = 0; i < prefix_size; ++i) prefix += alphabet[rng() % alphabet.size()];
        if (legacy_indent(value, prefix) != fast_indent(value, prefix)) {
            std::cerr << "Differential failure at " << test << "\n";
            return 1;
        }
    }
    assert(fast_indent(U"x\n\ny\n", U"\t") == U"\tx\n\n\ty\n");
    assert(fast_indent(U"\n\n", U"*") == U"\n\n");
    assert(fast_indent(U"", U"*") == U"");
    assert(fast_indent(U"α\nβ", U"🠖") == U"🠖α\n🠖β");

    Text large;
    for (int i = 0; i < 3200; ++i) {
        large += (i % 3 == 0 ? U"\n" : U"line with unicode αβ and lots of characters\n");
    }
    volatile std::size_t sink = 0;
    auto run = [&](auto fn, int repetitions) {
        auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < repetitions; ++i) sink = sink ^ fn(large, U"    ").size();
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    };
    const double old_ms = run(legacy_indent, 12);
    const double new_ms = run(fast_indent, 12);
    std::cout << "Differential cases: 16000; legacy_ms=" << old_ms << "; fast_ms=" << new_ms
              << "; speedup=" << old_ms / new_ms << "x; sink=" << sink << "\n";
    return 0;
}
