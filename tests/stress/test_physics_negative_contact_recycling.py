"""Conservative negative narrowphase caching contracts for GodotPhysics.

A broadphase AABB overlap need not be a real shape intersection. Cached
separating SAT/GJK results may be reused only for *exactly unchanged* relative
body transforms and geometry revisions, with CCD disabled.
These source-level checks supplement native and engine runtime regressions.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "servers/physics_contact_recycling.h"
PAIR2 = ROOT / "modules/godot_physics_2d/godot_body_pair_2d.cpp"
PAIR3 = ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp"
NATIVE = ROOT / "tests/servers/test_godot_physics_contact_recycling.cpp"


def can_recycle_separation(cached_revisions, current_revisions,
                           cached_separated, same_relative_offset, ccd):
    return (
        cached_separated
        and same_relative_offset
        and not ccd
        and 0 not in cached_revisions
        and cached_revisions == current_revisions
    )


class NegativeContactRecyclingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = SHARED.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.pairs = {}
        for dim, path, setup_name, pre_name in (
            ("2d", PAIR2, "bool GodotBodyPair2D::setup(", "bool GodotBodyPair2D::pre_solve("),
            ("3d", PAIR3, "bool GodotBodyPair3D::setup(", "bool GodotBodyPair3D::pre_solve("),
        ):
            source = path.read_text(encoding="utf-8")
            cls.pairs[dim] = source[source.index(setup_name):source.index(pre_name)]

    def test_cache_preserves_actual_narrowphase_negative_result(self):
        self.assertIn("bool narrowphase_separated = false;", self.header)
        self.assertIn("narrowphase_separated = !p_narrowphase_collided;", self.header)
        self.assertIn("inline bool can_reuse_separation(", self.header)
        self.assertIn("inline bool matches_geometry(", self.header)
        self.assertIn("return narrowphase_separated && !p_ccd && matches_geometry(", self.header)
        self.assertIn("!narrowphase_separated &&", self.header)

    def test_negative_cache_never_applies_after_changed_relative_translation(self):
        for dim, block in self.pairs.items():
            with self.subTest(dim=dim):
                self.assertIn("const bool relative_translation_unchanged = offset_B == new_offset_B;", block)
                self.assertIn("if (relative_translation_unchanged && contact_recycling.can_reuse_separation(", block)
                self.assertLess(block.index("const bool relative_translation_unchanged"),
                                block.index("can_reuse_separation("))

    def test_geometry_keys_and_ccd_guard_both_dimensions(self):
        for dim, block in self.pairs.items():
            with self.subTest(dim=dim):
                self.assertIn("A->get_collision_geometry_version()", block)
                self.assertIn("B->get_collision_geometry_version()", block)
                self.assertIn("geometry_version_a, geometry_version_b, ccd_enabled)", block)
                self.assertLess(block.index("const uint64_t geometry_version_a"), block.index("can_reuse_separation("))
                self.assertIn("return false;", block[block.index("can_reuse_separation("):
                                                      block.index("can_reuse(", block.index("can_reuse_separation("))])

    def test_result_is_recorded_only_after_the_actual_solver(self):
        for dim, block in self.pairs.items():
            with self.subTest(dim=dim):
                solver = ("GodotCollisionSolver2D::solve("
                          if dim == "2d" else "GodotCollisionSolver3D::solve_static(")
                self.assertIn(solver, block)
                self.assertIn("contact_recycling.remember(geometry_version_a, geometry_version_b, collided);", block)
                self.assertLess(block.index(solver), block.index("contact_recycling.remember("))

    def test_previous_positive_manifold_is_not_treated_as_separated(self):
        self.assertIn("narrowphase_separated = !p_narrowphase_collided;", self.header)
        self.assertIn("p_narrowphase_collided = true", self.header)
        self.assertIn("Recycle exact separated SAT/GJK pairs", self.native)
        self.assertIn("cache.remember(7, 11, false);", self.native)
        self.assertIn("cache.remember(7, 11, true);", self.native)
        self.assertIn("CHECK_FALSE(cache.can_reuse_separation(7, 11, true))", self.native)

    def test_previous_one_way_filter_result_is_not_cached_as_negative(self):
        setup = self.pairs["2d"]
        self.assertLess(setup.index("contact_recycling.remember("), setup.index("if (oneway_disabled) {"))
        self.assertIn("if (relative_translation_unchanged && contact_recycling.can_reuse_separation(", setup)
        # One-way filtering can only reject a positive SAT contact that was
        # already recorded as colliding. The negative flag stays false.
        self.assertIn("collided = false;", setup)

    def test_reference_state_transitions(self):
        revisions = (7, 11)
        cases = [
            (False, revisions, True, False, False),
            (True, revisions, True, False, True),
            (True, revisions, False, False, False),
            (True, revisions, True, True, False),
            (True, (8, 11), True, False, False),
            (True, (7, 12), True, False, False),
            (True, (7, 11), True, False, True),
            (False, (7, 11), True, False, False),
        ]
        for separated, current, same, ccd, expected in cases:
            with self.subTest(separated=separated, current=current, same=same, ccd=ccd):
                self.assertEqual(
                    can_recycle_separation(revisions, current, separated, same, ccd),
                    expected,
                )
        self.assertFalse(can_recycle_separation((0, 11), (0, 11), True, True, False))


if __name__ == "__main__":
    unittest.main()
