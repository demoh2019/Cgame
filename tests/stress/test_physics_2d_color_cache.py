"""Reference tests for persistent 2D constraint graph-color cache invalidation.

These verify the *invariants* of the C++ cache implementation, not its runtime
thread safety. The Godot GDScript regression checks actual joint rewiring.
"""

from __future__ import annotations

import random
import unittest

# (constraint identity, ordered endpoints with body identity and mode)
Constraint = tuple[int, tuple[tuple[int, int], ...]]
Topology = tuple[Constraint, ...]


def can_reuse(
    previous: Topology,
    current: Topology,
    previous_contact_only: bool,
    current_contact_only: bool,
) -> bool:
    if previous_contact_only != current_contact_only or len(previous) != len(current):
        return False
    for old, new in zip(previous, current):
        if len(old[1]) > 2 or len(new[1]) > 2:
            return False
        if old != new:
            return False
    return True


def greedy_colors(topology: Topology, contact_only: bool) -> list[int]:
    # In Cgame static and kinematic bodies may be shared only if *all*
    # constraints in the island explicitly permit it.
    occupancy: dict[int, int] = {}
    colors: list[int] = []
    for _, bodies in topology:
        participants = [
            body_id for body_id, mode in bodies if not contact_only or mode > 1
        ]
        forbidden = 0
        for body_id in participants:
            forbidden |= occupancy.get(body_id, 0)
        available = next((c for c in range(16) if not forbidden & (1 << c)), 16)
        if not bodies:
            available = 16
        colors.append(available)
        if available != 16:
            for body_id in participants:
                occupancy[body_id] = occupancy.get(body_id, 0) | (1 << available)
    return colors


def check_disjoint(topology: Topology, colors: list[int], contact_only: bool) -> None:
    for color in range(16):
        touched: set[int] = set()
        for (_, bodies), assigned in zip(topology, colors):
            if assigned != color:
                continue
            # A self-constraint can reference the same body twice. What
            # matters is disjointness between different constraints.
            participants = {
                body_id for body_id, mode in bodies
                if not contact_only or mode > 1
            }
            if not touched.isdisjoint(participants):
                raise AssertionError(f"shared body in color {color}")
            touched.update(participants)


class PersistentGraphColoringTests(unittest.TestCase):
    def test_unchanged_topology_reuses_colors(self) -> None:
        graph: Topology = tuple((i, ((i, 2), (i + 1, 2))) for i in range(383))
        colors = greedy_colors(graph, False)
        self.assertTrue(can_reuse(graph, graph, False, False))
        self.assertEqual(set(colors), {0, 1})
        check_disjoint(graph, colors, False)

    def test_endpoint_rebind_must_invalidate_cache(self) -> None:
        original: Topology = tuple((i, ((i, 2), (i + 1, 2))) for i in range(383))
        changed = list(original)
        changed[180] = (180, ((180, 2), (183, 2)))
        rewired = tuple(changed)
        self.assertFalse(can_reuse(original, rewired, False, False))
        check_disjoint(rewired, greedy_colors(rewired, False), False)
        self.assertTrue(can_reuse(original, original, False, False))

    def test_identity_mode_reordering_and_count_changes_invalidate(self) -> None:
        original: Topology = ((10, ((1, 2), (2, 2))), (11, ((2, 2), (3, 2))))
        mutations: list[Topology] = [
            ((10, ((2, 2), (1, 2))), original[1]),  # endpoint order
            ((10, ((1, 2), (4, 2))), original[1]),  # joint rebinding
            ((12, original[0][1]), original[1]),  # constraint replacement
            ((10, ((1, 0), (2, 2))), original[1]),  # static-mode transition
            (original[1], original[0]),  # traversal order
            (original[0],),  # removal
            original + ((12, ((3, 2), (4, 2))),),  # insertion
        ]
        for mutated in mutations:
            self.assertFalse(can_reuse(original, mutated, False, False))
        self.assertFalse(can_reuse(original, original, False, True))
        three_body: Topology = ((1, ((0, 2), (1, 2), (2, 2))),)
        self.assertFalse(can_reuse(three_body, three_body, False, False))

    def test_static_sharing_stays_conflict_free(self) -> None:
        floor = (0, 0)
        graph: Topology = tuple((i, (floor, (i + 1, 2))) for i in range(384))
        colors = greedy_colors(graph, True)
        self.assertEqual(set(colors), {0})
        check_disjoint(graph, colors, True)
        self.assertGreater(len(set(greedy_colors(graph, False))), 1)

    def test_random_topology_churn_never_reuses_invalid_schedule(self) -> None:
        randomizer = random.Random(20261119)
        for _ in range(400):
            size = randomizer.randint(1, 200)
            graph: Topology = tuple(
                (i, ((randomizer.randrange(90), 2), (randomizer.randrange(90), 2)))
                for i in range(size)
            )
            mutated = list(graph)
            index = randomizer.randrange(size)
            identity, bodies = mutated[index]
            mutated[index] = (
                identity,
                ((bodies[0][0] + 91, bodies[0][1]), bodies[1]),
            )
            self.assertFalse(can_reuse(graph, tuple(mutated), False, False))
            check_disjoint(graph, greedy_colors(graph, False), False)
            check_disjoint(tuple(mutated), greedy_colors(tuple(mutated), False), False)


if __name__ == "__main__":
    unittest.main()
