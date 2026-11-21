# production_readiness.gd

> Test-log parser and Markdown production-readiness (go/no-go) report.

`res://scripts/tools/production_readiness.gd`

## Overview

Test-log parser and Markdown production-readiness (go/no-go) report.
Original code (MIT-compatible).

## Functions

### `parse_test_log`

```gdscript
static func parse_test_log(text: String) -> Dictionary
```

Parses runner output. Returns {suites:{name:{checks,failed,failures,unloadable}},
total_checks, total_failures, has_total, script_errors:[String], orphan_fails:[String]}.

### `report`

```gdscript
static func report(test_results: Dictionary, perf_report: Dictionary, extra_gates: Dictionary) -> String
```

extra_gates: {gate_name: bool | {"pass": bool, "detail": String}}.
perf_report: compare_runs result, optionally with "leak" (memory_leak_trend result).

_1 private function(s) starting with `_` are not listed._
