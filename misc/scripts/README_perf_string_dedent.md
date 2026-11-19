# Linear-time `String::dedent()` for large script blocks

The previous implementation appended a substring (and a newline) for each line,
repeatedly copying the growing output. This created quadratic copying and
avoidable temporary allocations when working with large GDScript or text files.

The new implementation uses the same indentation semantics while doing three
linear passes: locate the first non-whitespace line's indentation, count the
exact output length, and copy retained text into one preallocated buffer.
Whitespace-only lines lose their whitespace but preserve newlines. The first
nonblank line defines the prefix removed from subsequent lines, stopping at
the first mismatching whitespace character. ASCII control chars, CRLF, Unicode,
blank trailing lines and no-op inputs preserve the original output. Unchanged
strings reuse their copy-on-write storage.

Tests:

- Godot native `tests/core/string/test_string.cpp` exercises whitespace,
  Unicode, mismatched indentation and a 2048-line input.
- `python3 -m unittest discover -s misc/scripts/tests -p test_string_dedent_linear.py -v`
- Compile and run `misc/scripts/benchmarks/benchmark_string_dedent.cpp` with
  GCC or Clang (`-std=c++17 -O2`). It compares 18,000 randomized cases with
  a standalone recreation of the legacy algorithm, then prints timing.

**Timing caveat:** Standalone benchmark gains do not measure engine FPS or
real-world allocation counts. Confirm with native tests, ASan and representative
project formatting workloads before shipping.
