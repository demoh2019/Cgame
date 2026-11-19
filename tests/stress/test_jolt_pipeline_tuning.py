"""Jolt broadphase pair-queue, large-island and manifold tuning regressions.

Source contracts always run; native simulation is opt-in with a Cgame binary.
Run:
  python3 -m unittest discover -s tests/stress -p test_jolt_pipeline_tuning.py -v
  python3 tests/stress/test_jolt_pipeline_tuning.py --godot /path/to/cgame
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
SETTINGS_H = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SPACE_CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
UPSTREAM_SETTINGS = ROOT / "thirdparty/jolt_physics/Jolt/Physics/PhysicsSettings.h"
UPSTREAM_SYSTEM = ROOT / "thirdparty/jolt_physics/Jolt/Physics/PhysicsSystem.cpp"
UPSTREAM_BODYPAIR = ROOT / "thirdparty/jolt_physics/Jolt/Physics/Body/BodyPair.h"
RUNTIME = ROOT / "tests/stress/physics_jolt_pipeline_tuning_regression.gd"
PREFIX = "JOLT_PIPELINE_RESULT:"

PROFILES = [
    (16384, True, True),  # Current default, unchanged.
    (1024, False, True),  # Low temporary memory, no island splitting.
    (32768, True, False),  # More queue capacity, unreduced manifolds.
]


class JoltPipelineSettingsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.settings = SETTINGS_CPP.read_text(encoding="utf-8")
        cls.header = SETTINGS_H.read_text(encoding="utf-8")
        cls.space = SPACE_CPP.read_text(encoding="utf-8")
        cls.upstream = UPSTREAM_SETTINGS.read_text(encoding="utf-8")
        cls.upstream_system = UPSTREAM_SYSTEM.read_text(encoding="utf-8")

    def test_queue_setting_preserves_jolt_default_and_clamps_extremes(self):
        path = "physics/jolt_physics_3d/limits/max_in_flight_body_pairs"
        self.assertIn(f'"{path}"', self.settings)
        self.assertIn('U"1024,262144,1024"), 16384)', self.settings)
        self.assertIn(
            f'CLAMP((int)GLOBAL_GET("{path}"), 1024, 262144)', self.settings
        )
        self.assertIn("inline static int max_in_flight_body_pairs;", self.header)
        self.assertIn(
            "settings.mMaxInFlightBodyPairs = JoltProjectSettings::max_in_flight_body_pairs;",
            self.space,
        )
        self.assertIn("mMaxInFlightBodyPairs = 16384;", self.upstream)

    def test_splitter_and_manifold_defaults_match_upstream(self):
        for name, upstream in (
            ("use_large_island_splitter", "mUseLargeIslandSplitter"),
            ("use_manifold_reduction", "mUseManifoldReduction"),
        ):
            path = f"physics/jolt_physics_3d/simulation/{name}"
            self.assertIn(f'"{path}"), true)', self.settings)
            self.assertIn(f'{name} = GLOBAL_GET("{path}");', self.settings)
            self.assertIn(f"settings.{upstream} = JoltProjectSettings::simulation_{name};", self.space)
            self.assertIn(f"inline static bool simulation_{name};", self.header)
            self.assertIn(f"{upstream} = true;", self.upstream)

    def test_temp_queue_really_allocates_from_jolt_arena_per_step(self):
        # This is a temporary queue, *not* Jolt's cached-contact capacity.
        self.assertIn(
            "sizeof(BodyPair) * mPhysicsSettings.mMaxInFlightBodyPairs",
            self.upstream_system,
        )
        self.assertIn(
            "mMaxBodyPairsPerQueue = mPhysicsSettings.mMaxInFlightBodyPairs / max_concurrency",
            self.upstream_system,
        )
        bodypair = UPSTREAM_BODYPAIR.read_text(encoding="utf-8")
        self.assertIn("static_assert(sizeof(BodyPair) == sizeof(uint64)", bodypair)
        # No Jolt source modifications or dynamic Update() settings lookups.
        self.assertNotIn("GLOBAL_GET(", self.space)

    def test_dense_runtime_fixture_reports_real_bodies_and_contacts(self):
        script = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const BODY_COUNT := 144", script)
        self.assertIn("PhysicsServer3D.INFO_COLLISION_PAIRS", script)
        self.assertIn("PhysicsServer3D.INFO_ACTIVE_OBJECTS", script)
        self.assertIn("JOLT_PIPELINE_RESULT:", script)


def simulate(binary: str, queue_size: int, splitter: bool, reduction: bool) -> dict:
    with tempfile.TemporaryDirectory(prefix="cgame-jolt-pipeline-") as temp:
        folder = Path(temp)
        config = (
            "config_version=5\n\n"
            "[application]\nconfig/name=\"Cgame Jolt Pipeline Test\"\n\n"
            "[physics]\n"
            "3d/physics_engine=\"Jolt Physics\"\n"
            f"jolt_physics_3d/limits/max_in_flight_body_pairs={queue_size}\n"
            "jolt_physics_3d/simulation/use_large_island_splitter="
            f"{str(splitter).lower()}\n"
            "jolt_physics_3d/simulation/use_manifold_reduction="
            f"{str(reduction).lower()}\n"
        )
        (folder / "project.godot").write_text(config, encoding="utf-8")
        shutil.copyfile(RUNTIME, folder / RUNTIME.name)
        process = subprocess.run(
            [binary, "--headless", "--path", str(folder), "--script", f"res://{RUNTIME.name}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=90,
            check=False,
        )
        records = [
            json.loads(line.split(PREFIX, 1)[1])
            for line in process.stdout.splitlines()
            if line.startswith(PREFIX)
        ]
        if process.returncode != 0 or len(records) != 1 or not records[0]["passed"]:
            raise AssertionError(
                f"Jolt queue={queue_size}, splitter={splitter}, reduction={reduction}:"
                f" exit={process.returncode}\n{process.stdout[-6500:]}"
            )
        return records[0]


class JoltPipelineRuntime(unittest.TestCase):
    def test_physics_step_with_each_queue_and_solver_profile(self):
        binary = os.environ.get("CGAME_GODOT_BINARY")
        if not binary:
            self.skipTest("Set CGAME_GODOT_BINARY or pass --godot to run native Jolt")
        binary = os.path.abspath(binary)
        self.assertTrue(Path(binary).is_file(), binary)
        for size, splitter, reduction in PROFILES:
            with self.subTest(size=size, splitter=splitter, reduction=reduction):
                result = simulate(binary, size, splitter, reduction)
                self.assertEqual(result["bodies"], 144)
                self.assertGreater(result["peak_active"], 0)
                self.assertGreater(result["peak_pairs"], 0)
                self.assertEqual(result["max_in_flight_body_pairs"], size)
                self.assertEqual(result["large_island_splitter"], splitter)
                self.assertEqual(result["manifold_reduction"], reduction)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Cgame editor binary built with the Jolt module")
    args = parser.parse_args()
    if args.godot:
        os.environ["CGAME_GODOT_BINARY"] = args.godot
    unittest.main(argv=["test_jolt_pipeline_tuning.py"], verbosity=2)
