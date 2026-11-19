"""Regression contracts for early GodotPhysics body exception pair filtering.

These tests inspect the source and scenario registration. Runtime correctness
and performance require running the paired engine workloads separately.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "modules"
STRESS = ROOT / "tests/stress"


class PhysicsEarlyPairFilterContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = {}
        for d in ("2d", "3d"):
            folder = MODULES / f"godot_physics_{d}"
            for kind in ("godot_broad_phase", "godot_collision_object", "godot_physics_server"):
                suffix = f"_{d}_bvh.h" if kind == "godot_broad_phase" else f"_{d}.cpp"
                cls.files[d, kind] = (folder / f"{kind}{suffix}").read_text(encoding="utf-8")
            cls.files[d, "object_header"] = (folder / f"godot_collision_object_{d}.h").read_text(encoding="utf-8")
            cls.files[d, "stress"] = (STRESS / f"physics_exception_pairs_{d}.gd").read_text(encoding="utf-8")

    def test_masks_and_body_exceptions_are_rejected_early(self):
        for d in ("2d", "3d"):
            with self.subTest(dimension=d):
                cpp = self.files[d, "godot_broad_phase"]
                self.assertIn(f'#include "godot_body_{d}.h"', cpp)
                self.assertIn("if (!p_a->interacts_with(p_b))", cpp)
                self.assertIn(f"GodotCollisionObject{d.upper()}::TYPE_BODY", cpp)
                self.assertIn("!body_a->has_exception(body_b->get_self())", cpp)
                self.assertIn("!body_b->has_exception(body_a->get_self())", cpp)
                self.assertIn("return true;", cpp)

    def test_exception_updates_rebuild_pairs_without_mass_recalculation(self):
        for d in ("2d", "3d"):
            with self.subTest(dimension=d):
                body_cpp = self.files[d, "godot_collision_object"]
                body_h = self.files[d, "object_header"]
                server = self.files[d, "godot_physics_server"]
                classname = f"GodotCollisionObject{d.upper()}"
                self.assertIn("void refresh_collision_pairs();", body_h)
                start = body_cpp.split(f"void {classname}::refresh_collision_pairs() {{", 1)[1]
                method = start.split("\n}\n", 1)[0]
                self.assertIn("broadphase->force_collision_check(shape.bpid);", method)
                self.assertNotIn("_shapes_changed()", method)
                self.assertNotIn("++collision_geometry_version", method)
                filter_body = body_cpp.split(f"void {classname}::_collision_filter_changed() {{", 1)[1].split("\n}\n", 1)[0]
                self.assertIn("++collision_geometry_version;", filter_body)
                self.assertIn("refresh_collision_pairs();", filter_body)
                self.assertIn("_shapes_changed();", filter_body)
                self.assertEqual(server.count("\tbody->refresh_collision_pairs();"), 2)
                self.assertIn("body->add_exception(p_body_b);", server)
                self.assertIn("body->remove_exception(p_body_b);", server)

    def test_3d_rigid_soft_exception_pairs_are_filtered_early(self):
        broadphase = self.files["3d", "godot_broad_phase"]
        server = self.files["3d", "godot_physics_server"]
        self.assertIn('#include "godot_soft_body_3d.h"', broadphase)
        self.assertIn("GodotCollisionObject3D::TYPE_SOFT_BODY", broadphase)
        self.assertIn("!body->has_exception(soft_body->get_self())", broadphase)
        self.assertIn("!soft_body->has_exception(body->get_self())", broadphase)
        self.assertEqual(server.count("soft_body->refresh_collision_pairs();"), 2)
        self.assertIn("soft_body->add_exception(p_body_b);", server)
        self.assertIn("soft_body->remove_exception(p_body_b);", server)

    def test_stress_cases_check_both_directions_without_motion(self):
        runner = (STRESS / "run.py").read_text(encoding="utf-8")
        dispatcher = (STRESS / "stress.gd").read_text(encoding="utf-8")
        config = (STRESS / "project.godot").read_text(encoding="utf-8")
        for d in ("2d", "3d"):
            with self.subTest(dimension=d):
                name = f"physics_exception_pairs_{d}"
                self.assertIn(f'"{name}"', runner)
                self.assertIn(f'"{name}":', dispatcher)
                script = self.files[d, "stress"]
                self.assertIn("INFO_COLLISION_PAIRS", script)
                self.assertIn("body_add_collision_exception(mover, obstacle)", script)
                self.assertIn("body_remove_collision_exception(mover, obstacle)", script)
                self.assertIn("body_add_collision_exception(obstacle, mover)", script)
                self.assertIn("body_remove_collision_exception(obstacle, mover)", script)
                self.assertIn("stationary_exception_filter_verified", script)
                self.assertIn(f'{d}/physics_engine="GodotPhysics{d.upper()}"', config)


if __name__ == "__main__":
    unittest.main()
