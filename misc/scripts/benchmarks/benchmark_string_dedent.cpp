// Standalone differential benchmark for String::dedent. Not an engine FPS benchmark.
#include <cassert>
#include <chrono>
#include <cstring>
#include <iostream>
#include <random>
#include <string>
using Text = std::u32string;

static Text legacy_dedent(const Text &s) {
    Text output, indent;
    bool has_indent = false, has_text = false;
    int line_start = 0, indent_stop = -1;
    for (int i = 0; i < static_cast<int>(s.size()); ++i) {
        const char32_t c = s[i];
        if (c == U'\n') {
            if (has_text) output = output + s.substr(indent_stop, i - indent_stop);
            output = output + U"\n";
            has_text = false; line_start = i + 1; indent_stop = -1;
        } else if (!has_text) {
            if (c > 32) {
                has_text = true;
                if (!has_indent) {
                    has_indent = true;
                    indent = s.substr(line_start, i - line_start);
                    indent_stop = i;
                }
            }
            if (has_indent && indent_stop < 0) {
                const int j = i - line_start;
                if (j >= static_cast<int>(indent.size()) || c != indent[j]) indent_stop = i;
            }
        }
    }
    if (has_text) output = output + s.substr(indent_stop);
    return output;
}

static Text fast_dedent(const Text &s) {
    const int length = static_cast<int>(s.size());
    if (!length) return s;
    int indent_begin = 0, indent_length = 0, line_begin = 0;
    for (int i = 0; i < length; ++i) {
        if (s[i] == U'\n') line_begin = i + 1;
        else if (s[i] > 32) { indent_begin = line_begin; indent_length = i - line_begin; break; }
    }
    const auto get_copy_begin = [&](int begin, int end) {
        int first_text = begin;
        while (first_text < end && s[first_text] <= 32) ++first_text;
        if (first_text == end) return end;
        int copy_begin = begin;
        while (copy_begin < first_text && copy_begin - begin < indent_length &&
                s[copy_begin] == s[indent_begin + copy_begin - begin]) ++copy_begin;
        return copy_begin;
    };
    int result_size = 0;
    bool changed = false;
    line_begin = 0;
    for (int end = 0; end <= length; ++end) {
        if (end < length && s[end] != U'\n') continue;
        const int copy_begin = get_copy_begin(line_begin, end);
        result_size += end - copy_begin + (end < length ? 1 : 0);
        changed |= copy_begin != line_begin;
        line_begin = end + 1;
    }
    if (!changed) return s;
    Text out;
    out.resize(result_size);
    int written = 0;
    line_begin = 0;
    for (int end = 0; end <= length; ++end) {
        if (end < length && s[end] != U'\n') continue;
        const int copy_begin = get_copy_begin(line_begin, end);
        const int count = end - copy_begin;
        if (count) {
            std::memcpy(out.data() + written, s.data() + copy_begin, count * sizeof(char32_t));
            written += count;
        }
        if (end < length) out[written++] = U'\n';
        line_begin = end + 1;
    }
    assert(written == result_size);
    return out;
}

int main() {
    std::mt19937 rng(0x4ce6d9);
    const Text alphabet = { U' ', U'\t', U'\r', U'\n', U'\v', U'\0', U'α', U'β', U'Я', U'я', U'😀', U'a', U'b' };
    for (int test = 0; test < 18000; ++test) {
        Text input;
        const int count = static_cast<int>(rng() % 140);
        for (int i = 0; i < count; ++i) input += alphabet[rng() % alphabet.size()];
        if (legacy_dedent(input) != fast_dedent(input)) {
            std::cerr << "Dedent mismatch at test " << test << "\n";
            return 1;
        }
    }
    assert(fast_dedent(U"    a\n  b\n") == U"a\nb\n");
    assert(fast_dedent(U" \tfirst\n  second") == U"first\n second");
    assert(fast_dedent(U"   \n \n") == U"\n\n");
    Text large;
    for (int i = 0; i < 2500; ++i) {
        large += (i % 4 == 0 ? U"    \n" : i % 4 == 1 ? U"    αβ and text\n" : i % 4 == 2 ? U"  β\n" : U"     more text\n");
    }
    volatile std::size_t sink = 0;
    auto run = [&](auto fn) {
        const auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < 14; ++i) sink = sink ^ fn(large).size();
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    };
    const double before = run(legacy_dedent);
    const double after = run(fast_dedent);
    std::cout << "Differential cases: 18000; legacy_ms=" << before << "; fast_ms=" << after
              << "; speedup=" << before / after << "x; sink=" << sink << "\n";
}
