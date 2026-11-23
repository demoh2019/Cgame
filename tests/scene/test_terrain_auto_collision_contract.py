"""Guard native HeightmapTerrain3D collision and Albion authoring integration.

Source contracts do not substitute for compiling Godot or physics tests.
"""
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def src(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class TerrainCollisionContract(unittest.TestCase):
    def test_native_collision_is_opt_in_and_safely_coalesced(self):
        cpp = src("modules/heightmap_terrain/heightmap_terrain_3d.cpp")
        hdr = src("modules/heightmap_terrain/heightmap_terrain_3d.h")
        for needle in (
            "bool automatic_collision = false;",
            "collision_rebuild_pending = false",
            "last_collision_heights",
            "collision_step = 1",
        ):
            self.assertIn(needle, hdr)
        for needle in (
            'call_deferred(SNAME("_update_auto_collision"))',
            "MAX_COLLISION_TRIANGLES = 8192",
            "heights == last_collision_heights",
            "auto_collision_enabled",
            "auto_collision_step",
            "Ref<ConcavePolygonShape3D> shape",
            "Node::INTERNAL_MODE_BACK",
            "collision_shape->set_disabled(true)",
            "last_collision_heights = heights",
            "write[cursor++] = a",
            "write[cursor++] = e",
        ):
            self.assertIn(needle, cpp)
        self.assertIn("set_mesh(build_mesh())", cpp)
        self.assertIn("#ifndef PHYSICS_3D_DISABLED", cpp)
        self.assertIn("#ifndef PHYSICS_3D_DISABLED", hdr)

    def test_game_can_author_from_real_world_with_stock_godot_fallback(self):
        game = src("game/scripts/client/terrain_collision_authoring.gd")
        tool = src("game/tools/terrain_collision_probe.gd")
        tests = src("game/tests/test_terrain_auto_collision.gd")
        for needle in (
            'EngineFeatures.has("HeightmapTerrain3D")',
            'EngineFeatures.make("HeightmapTerrain3D")',
            'world.height_at(',
            'set_auto_collision_enabled',
            'set_auto_collision_step',
            'heights[z * samples + x] = y',
            "not is_finite(y)",
        ):
            self.assertIn(needle, game)
        self.assertIn("TerrainAuthoring.build_patch(", tool)
        self.assertIn("get_auto_collision_triangle_count", tests)
        self.assertIn("terrain color paint does not trigger", tests)
        self.assertIn("test_terrain_auto_collision.gd", src("game/tests/run_all.gd"))
        self.assertIn("get_auto_collision_triangle_count", src("modules/heightmap_terrain/doc_classes/HeightmapTerrain3D.xml"))

    def test_native_regression_covers_actual_collision_shape(self):
        tests = src("modules/heightmap_terrain/tests/test_heightmap_terrain.h")
        for needle in (
            "[Terrain] Opt-in collision follows sculpt",
            "[Terrain] Large editor heightfields auto-cap",
            "terrain->get_auto_collision_shape()",
            "concave->get_faces()",
            "8192 * 3",
            "terrain->set_auto_collision_step(16)",
            "terrain->set_auto_collision_enabled(false)",
        ):
            self.assertIn(needle, tests)


if __name__ == "__main__":
    unittest.main()
