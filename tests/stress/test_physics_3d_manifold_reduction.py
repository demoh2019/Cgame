"""3D contact manifold spread-reduction source contracts and reference model.

The native C++ helper keeps the deepest contact and, for compatible contact
normals, chooses four points with better projected patch coverage. The option
defaults OFF and never allocates. This script checks the integration points
and reproduces deterministic mathematical properties without compiling C++.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PAIR3 = ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp"
PAIR2 = ROOT / "modules/godot_physics_2d/godot_body_pair_2d.cpp"
REDUCER = ROOT / "servers/physics_manifold_reduction_3d.h"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SERVER_CPP = ROOT / "servers/physics_3d/physics_server_3d.cpp"
NATIVE = ROOT / "tests/servers/test_godot_physics_manifold_reduction_3d.cpp"


def area_score(points, omit):
    keep = [p for i, p in enumerate(points) if i != omit]
    total = 0.0
    for i, j, k in ((0, 1, 2), (0, 1, 3), (0, 2, 3), (1, 2, 3)):
        ux, uy = keep[j][0] - keep[i][0], keep[j][1] - keep[i][1]
        vx, vy = keep[k][0] - keep[i][0], keep[k][1] - keep[i][1]
        total += (ux * vy - uy * vx) ** 2
    return total


def choose(points, depths, compatible=True):
    deepest = max(range(5), key=lambda i: depths[i])
    if not compatible:
        replacement, min_depth = -1, depths[4]
        for i in range(4):
            if depths[i] < min_depth:
                replacement, min_depth = i, depths[i]
        return replacement
    best = 0 if deepest == 4 else 4
    best_score = area_score(points, best)
    for i in range(4):
        if i in (best, deepest):
            continue
        score = area_score(points, i)
        if score > best_score * 1.01:
            best, best_score = i, score
    return -1 if best == 4 else best


class ManifoldReduction3DContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source3 = PAIR3.read_text(encoding="utf-8")
        cls.source2 = PAIR2.read_text(encoding="utf-8")
        cls.reducer = REDUCER.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.space_cpp = SPACE_CPP.read_text(encoding="utf-8")
        cls.server_cpp = SERVER_CPP.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_opt_in_default_off_and_cached_once_per_space(self):
        self.assertIn('GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/manifold_spread_reduction"), false);', self.server_cpp)
        self.assertIn('manifold_spread_reduction = GLOBAL_GET("physics/3d/solver/manifold_spread_reduction");', self.space_cpp)
        self.assertIn("bool manifold_spread_reduction = false;", self.space_h)
        self.assertIn("bool is_manifold_spread_reduction_enabled() const", self.space_h)

    def test_only_full_3d_rigid_manifolds_use_the_reducer(self):
        self.assertIn('#include "servers/physics_manifold_reduction_3d.h"', self.source3)
        self.assertIn("if (new_index == MAX_CONTACTS) {", self.source3)
        self.assertIn("if (space->is_manifold_spread_reduction_enabled()) {", self.source3)
        self.assertIn("GodotPhysicsManifoldReduction3D::choose_replacement(", self.source3)
        self.assertIn("contacts[replacement] = contact;", self.source3)
        self.assertIn("// Legacy: remove the contact with the minimum depth.", self.source3)

    def test_selection_is_fixed_size_and_depth_preserving(self):
        self.assertIn("static constexpr int MAX_CONTACTS = 4;", self.reducer)
        self.assertIn("int deepest = 0;", self.reducer)
        self.assertIn("if (p_depths[i] > p_depths[deepest])", self.reducer)
        self.assertIn("omitted == deepest", self.reducer)
        self.assertIn("best_score * real_t(1.01)", self.reducer)
        self.assertIn("p_normals[i].dot(p_normals[deepest]) < real_t(0.98)", self.reducer)
        self.assertNotIn("memnew(", self.reducer)

    def test_matching_filters_wrong_face_before_nearest_candidate(self):
        for src, label in ((self.source2, "2d"), (self.source3, "3d")):
            with self.subTest(dimension=label):
                fn = ("GodotBodyPair2D::_contact_added_callback("
                      if label == "2d" else "GodotBodyPair3D::contact_added_callback(")
                start = src.index("void " + fn)
                stop = src.index("void GodotBodyPair", start + 5)
                section = src[start:stop]
                self.assertIn("normal.dot(contact.normal) < real_t(0.98)", section)
                self.assertLess(section.index("normal.dot(contact.normal) < real_t(0.98)"),
                                section.index("best_match = i;"))

    def test_native_regressions_cover_patch_quality(self):
        for title in ("Keep the broad original contact patch",
                      "Replace an interior point to cover the surface",
                      "Never discard the deepest penetration",
                      "Different face normals retain the legacy depth selection",
                      "Degenerate line contact does not replace a valid point"):
            self.assertIn(title, self.native)

    def test_reference_regression_examples(self):
        square = [(-1, -1), (1, -1), (1, 1), (-1, 1), (0, 0)]
        self.assertEqual(choose(square, [2, 1, 1, 1, 0.5]), -1)
        clustered = [(0, 0), (0, 1), (0, -1), (0, 0.2), (10, 0)]
        self.assertEqual(choose(clustered, [2, 1, 1, 1, 0.5]), 3)
        self.assertIn(choose(square, [1, 1, 1, 1, 3]), range(4))
        self.assertEqual(choose(square, [1, 2, 3, 4, 0.5], False), -1)
        self.assertEqual(choose(square, [1, 2, 3, 4, 5], False), 0)

    def test_random_patches_never_remove_the_deepest_point(self):
        rng = random.Random(914007)
        for _ in range(1000):
            points = [(rng.uniform(-10, 10), rng.uniform(-10, 10)) for _ in range(5)]
            depths = [rng.uniform(-0.5, 2.0) for _ in range(5)]
            deepest = max(range(5), key=lambda i: depths[i])
            replacement = choose(points, depths)
            self.assertTrue(-1 <= replacement < 4)
            self.assertNotEqual(replacement, deepest)
            if replacement >= 0 and deepest != 4:
                self.assertGreater(area_score(points, replacement),
                                   area_score(points, 4))
            self.assertTrue(math.isfinite(area_score(points, replacement if replacement >= 0 else 4)))


if __name__ == "__main__":
    unittest.main()
