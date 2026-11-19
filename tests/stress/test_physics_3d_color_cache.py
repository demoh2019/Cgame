"""Reference contracts for topology-safe 3D island graph-color caching.

Reference checks don't replace the Godot runtime regression or sanitizers.
The cache stores exact identities and endpoint modes, not lossy hashes.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
STEP = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
HEADER = ROOT / "modules/godot_physics_3d/godot_step_3d.h"


@dataclass(frozen=True)
class Topology:
    constraint: int
    body_a: int | None
    body_b: int | None
    mode_a: int
    mode_b: int
    body_count: int


def reusable(
    cached: list[Topology],
    current: list[Topology],
    cached_contact_only: bool,
    current_contact_only: bool,
    cache_valid: bool = True,
) -> bool:
    """Mirror the exact comparisons made by _can_reuse_color_cache()."""
    return (
        cache_valid
        and cached_contact_only == current_contact_only
        and len(cached) == len(current)
        and all(
            old.constraint == new.constraint
            and 0 <= new.body_count <= 2
            and old.body_count == new.body_count
            and old.body_a == new.body_a
            and old.body_b == new.body_b
            and old.mode_a == new.mode_a
            and old.mode_b == new.mode_b
            for old, new in zip(cached, current)
        )
    )


class Physics3DColorCacheTests(unittest.TestCase):
    def test_exact_reuse_and_invalidation(self):
        initial = [
            Topology(0x01, 11, 12, 2, 2, 2),
            Topology(0x02, 12, 13, 2, 2, 2),
            Topology(0x03, 13, 14, 2, 0, 2),
        ]
        self.assertTrue(reusable(initial, list(initial), True, True))
        self.assertFalse(reusable(initial, list(initial), True, True, False))
        self.assertFalse(reusable(initial, list(initial), True, False))
        self.assertFalse(reusable(initial, initial[:-1], True, True))
        self.assertFalse(reusable(initial, list(reversed(initial)), True, True))

        mutated = list(initial)
        mutated[1] = Topology(0x02, 12, 99, 2, 2, 2)
        self.assertFalse(reusable(initial, mutated, True, True))
        # The constraint pointer is unchanged but one endpoint's mode changed.
        mutated[1] = Topology(0x02, 12, 13, 2, 1, 2)
        self.assertFalse(reusable(initial, mutated, True, True))
        # Even when both bodies are unchanged, a reallocated constraint is new.
        mutated[1] = Topology(0xAA, 12, 13, 2, 2, 2)
        self.assertFalse(reusable(initial, mutated, True, True))
        # Constraints with > 2 bodies are not cached by this implementation.
        mutated[1] = Topology(0x02, 12, 13, 2, 2, 3)
        self.assertFalse(reusable(initial, mutated, True, True))

    def test_cache_guards_are_before_hash_coloring(self):
        source = STEP.read_text(encoding="utf-8")
        header = HEADER.read_text(encoding="utf-8")
        self.assertIn("struct ColorCacheEntry", header)
        self.assertIn("LocalVector<ColorCacheEntry> cached_color_topology;", header)
        self.assertIn("uint32_t cached_color_sizes[17] = {};", header)
        self.assertIn("uint32_t cached_color_starts[17] = {};", header)
        self.assertIn("bool cached_color_valid = false;", header)
        self.assertIn("bool _can_reuse_color_cache(", header)
        self.assertIn("void _run_colored_batches(", header)
        self.assertIn("bool GodotStep3D::_can_reuse_color_cache(", source)
        self.assertIn("cached_color_contact_only != p_contact_only", source)
        self.assertIn("entry.constraint != constraint", source)
        self.assertIn("entry.body_A != body_A || entry.body_B != body_B", source)
        self.assertIn("entry.mode_A != mode_A || entry.mode_B != mode_B", source)
        self.assertIn("body_count < 0 || body_count > 2", source)
        self.assertIn("_run_colored_batches(cached_color_sizes, cached_color_starts);", source)
        self.assertIn("_run_colored_batches(group_sizes, starts);", source)
        self.assertIn("cached_color_valid = true;", source)
        self.assertIn("cached_color_valid = false;", source)
        self.assertIn("cached_color_topology.reset();", source)
        self.assertIn("cached_color_topology.clear();", source)
        self.assertLess(
            source.index("_can_reuse_color_cache(p_constraint_island, contact_only_island)"),
            source.index("occupied_colors.clear();"),
        )

    def test_cached_topology_has_all_original_endpoints(self):
        source = STEP.read_text(encoding="utf-8")
        self.assertIn("entry.constraint = constraint;", source)
        self.assertIn("entry.body_count = static_cast<uint8_t>(body_count);", source)
        self.assertIn("entry.body_A = body_count > 0 ? bodies[0] : nullptr;", source)
        self.assertIn("entry.body_B = body_count > 1 ? bodies[1] : nullptr;", source)
        self.assertIn("entry.mode_A = entry.body_A ? static_cast<uint8_t>(entry.body_A->get_mode()) : 0;", source)
        self.assertIn("entry.mode_B = entry.body_B ? static_cast<uint8_t>(entry.body_B->get_mode()) : 0;", source)
        self.assertIn("cached_color_sizes[color] = group_sizes[color];", source)
        self.assertIn("cached_color_starts[color] = starts[color];", source)

    def test_cache_buffers_released_when_island_not_used(self):
        source = STEP.read_text(encoding="utf-8")
        body = source[source.index("if (large_island_count != 1"): ]
        self.assertIn("cached_color_topology.reset();", body)
        self.assertIn("cached_color_valid = false;", body)


    def test_live_joint_rebinding_registered_in_stress_runner(self):
        workload = (ROOT / "tests/stress/physics_large_island_3d.gd").read_text(encoding="utf-8")
        runner = (ROOT / "tests/stress/run.py").read_text(encoding="utf-8")
        script = (ROOT / "tests/stress/stress.gd").read_text(encoding="utf-8")
        runtime = (ROOT / "tests/stress/physics_large_island_3d_topology_cache_regression.gd").read_text(encoding="utf-8")
        self.assertIn("topology_churn: bool = false", workload)
        self.assertIn("if frame == 8:", workload)
        self.assertIn("elif frame == 18:", workload)
        self.assertIn("PhysicsServer3D.joint_make_pin(joints[100]", workload)
        self.assertIn("PhysicsServer3D.joint_set_solver_priority(joints[10], 2)", workload)
        self.assertIn("PhysicsServer3D.joint_set_solver_priority(joints[10], 1)", workload)
        for name in ("physics_large_island_3d_topology_serial", "physics_large_island_3d_topology_parallel"):
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', script)
        self.assertIn("for parallel in [false, true]", runtime)
        self.assertIn("self, 1, 52, parallel, false, 0, 16, true", runtime)
        self.assertIn("result.has(\"error\")", runtime)


if __name__ == "__main__":
    unittest.main()
