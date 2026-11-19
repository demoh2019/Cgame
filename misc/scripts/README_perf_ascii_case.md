# Performance: ASCII case conversion hot path

This change ports the low-risk fast ASCII idea from Godot PR
[#124138](https://github.com/godotengine/godot/pull/124138) and extends it to
`String::char_uppercase()`, `String::to_lower()`, and `String::to_upper()`.
It **does not** claim the rest of the upstream PR was merged.

Previously every code point — including ASCII letters in resource paths,
project keys and method names — entered the approximately 1,500-entry
binary-searched Unicode case table. Each new scalar wrapper now handles
`0..127` inline and retains the existing Unicode table for everything else.
Whole-string conversion does the same inside its loop without introducing a
function-call overhead for non-ASCII characters.

There are no changes to String allocation behavior or Unicode mapping tables.
Only the choice of lookup algorithm for ASCII input changes.

## Regressions

- Native `[String]` tests cover all 128 ASCII code points, representative
  Latin-1/Greek/Cyrillic/non-BMP code points, and mixed-string output.
- Python structural tests verify the table fallback and the fast-path guards.
- A standalone C++ microbenchmark compiles against **the repository's actual
  `core/string/ucaps.h` tables**. It checks equivalence for ASCII and all table
  mappings before printing ASCII/mixed/Unicode lower/uppercase timings.

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_ascii_case_hotpath.py -v
c++ -std=c++17 -O3 -I. misc/scripts/benchmarks/benchmark_unicode_ascii.cpp -o /tmp/cgame-case-bench
/tmp/cgame-case-bench
```

The microbenchmark isolates *case mapping only*. It does not measure full
Godot editor launch, project import, frame time or RSS. CI prints timings but
does not enforce a noisy throughput threshold; compare multiple runs on the
same machine before making a product-level performance claim.
