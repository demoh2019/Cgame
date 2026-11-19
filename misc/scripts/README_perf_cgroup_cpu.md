# Linux cgroup CPU quota-aware default worker pool sizing

**Purpose:** Reduce thread oversubscription and transient memory usage in Linux
containers and constrained hosts that expose more *affinity-allowed CPUs* than
the CPU quota available to the process. Cgame's existing Linux default thread
count already honors `sched_getaffinity()`. The engine now also reads the
cgroup v2 `cpu.max` file when available and takes the smaller positive value.
This affects only the **default** pool size; explicit user thread limits and
non-Linux platforms retain their original behavior.

A quota of `250000 100000` allows 2.5 cores of processing time, and is rounded
up to 3 workers to preserve the opportunity for parallel bursts. A value of
`max 100000`, unreadable file, invalid numeric data, or quota 0 preserves the
affinity-based thread count. Parsing is integer-only with overflow checks.

Example: a Linux process has an affinity mask allowing 16 logical CPUs, but
`/sys/fs/cgroup/cpu.max` reads `200000 100000`. Its **default** worker pool
size becomes 2 instead of 16. Avoid claiming this always improves FPS: on
short, CPU-bursting workloads, it may reduce throughput; measure for your
workload. On startup this can save worker stack reservations and contention.

## Testing

Run cross-platform parser tests with GCC or Clang:

```sh
c++ -std=c++17 -O2 -Wall -Wextra -Werror -I. \
  misc/scripts/benchmarks/test_cgroup_cpu_quota.cpp -o /tmp/cgroup_test
/tmp/cgroup_test
```

Run the native Godot `[OS]` tests with a Linux editor/test build; they check
that the pool never exceeds affinity or a valid cgroup quota and that parsing
and rounding preserve intended semantics.

**Limitations:** This first implementation checks the conventional cgroup-v2
mount point `/sys/fs/cgroup/cpu.max`. Systems with another mount location,
cgroup-v1 CPU bandwidth control, or quotas set only by ancestor cgroups not
visible at that path keep the old affinity-only fallback. This is not a
full cgroup mount discovery utility; it never imposes a quota on unsupported
systems. Worker counts are evaluated when the pool is initialized, not
continuously adjusted at runtime. A benchmark under a real quota is required
to quantify per-machine speed and memory improvements.
