# `String::indent`: linear time and a single allocation

The old `String::indent()` concatenated a newly allocated substring for every
nonempty line. On thousands of lines that repeatedly copied already formatted
text, creating quadratic time and temporary heap pressure.

The optimized method makes two linear passes: first count nonempty lines to
compute exact output length, then write each prefix and original character into
a **single output allocation**. Empty input, empty prefix and all-empty lines
return the original copy-on-write string. The original treatment of consecutive
newlines, trailing newlines, Unicode, CRLF and prefix text is retained. A
64-bit length calculation guards against overflowing Godot's 32-bit string
length before allocation.

## Tests and benchmarks

- Native Godot tests in `tests/core/string/test_string.cpp`: edge cases,
  Unicode, COW fast-path, and a 4096-line result.
- `python3 -m unittest discover -s misc/scripts/tests -p test_string_indent_linear.py -v`
- `c++ -O2 -std=c++17 misc/scripts/benchmarks/benchmark_string_indent.cpp -o /tmp/indent_bench && /tmp/indent_bench`

The standalone differential benchmark compares the legacy algorithm with an
independent C++ model of the optimized algorithm over 16,000 randomized cases.
Its timing reflects **only the standalone algorithm** on the runner, not the
Godot engine or a promised game FPS improvement. Validate with native tests,
project-specific editor workloads, allocation instrumentation and benchmarks
before release.
