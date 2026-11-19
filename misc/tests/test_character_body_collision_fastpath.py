"""Contracts for a single writable cached collision result in 2D/3D."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    "2D": (ROOT / "scene/2d/physics/character_body_2d.cpp").read_text(encoding="utf-8"),
    "3D": (ROOT / "scene/3d/physics/character_body_3d.cpp").read_text(encoding="utf-8"),
}
BODIES = {
    dim: code.split(f"Ref<KinematicCollision{dim}> CharacterBody{dim}::_get_slide_collision(int p_bounce) {{", 1)[1].split(
        f"Ref<KinematicCollision{dim}> CharacterBody{dim}::_get_last_slide_collision()", 1)[0]
    for dim, code in SOURCES.items()
}

class CharacterBodyCollisionFastPathContracts(unittest.TestCase):
    def test_each_axis_gets_one_writable_slot(self):
        for dim, code in BODIES.items():
            with self.subTest(dim=dim):
                self.assertIn(
                    f"Ref<KinematicCollision{dim}> &collision = slide_colliders.ptrw()[p_bounce];", code)
                self.assertEqual(code.count("slide_colliders.ptrw()"), 1)
                self.assertNotIn("slide_colliders.write[p_bounce]", code)

    def test_cached_instance_is_reused_unless_referenced_by_script(self):
        for dim, code in BODIES.items():
            with self.subTest(dim=dim):
                self.assertIn("if (collision.is_null() || collision->get_reference_count() > 1)", code)
                self.assertIn("collision.instantiate();", code)
                self.assertIn("collision->owner_id = get_instance_id();", code)

    def test_collision_data_and_return_reference_preserved(self):
        for dim, code in BODIES.items():
            with self.subTest(dim=dim):
                self.assertIn("collision->result = motion_results[p_bounce];", code)
                self.assertIn("return collision;", code)
                self.assertIn("ERR_FAIL_INDEX_V(p_bounce, motion_results.size()", code)

    def test_out_of_range_vector_slots_are_still_resized(self):
        for dim, code in BODIES.items():
            with self.subTest(dim=dim):
                self.assertIn("if (p_bounce >= slide_colliders.size())", code)
                self.assertIn("slide_colliders.resize(p_bounce + 1);", code)
                self.assertLess(code.index("slide_colliders.resize(p_bounce + 1);"),
                                code.index("slide_colliders.ptrw()[p_bounce]"))


if __name__ == "__main__":
    unittest.main()
