"""Jolt material-combine source contracts and optional real-physics regression.

The real simulation is opt-in because tests/stress/project.godot intentionally
selects GodotPhysics3D. We use per-run temporary projects selecting Jolt
Physics, with all combine modes configured before JoltSpace3D is constructed.

Run:
    python3 -m unittest tests.stress.test_jolt_material_mix -v
    python3 tests/stress/test_jolt_material_mix.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64
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
JOLT_SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
JOLT_SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
JOLT_SETTINGS_H = ROOT / "modules/jolt_physics/jolt_project_settings.h"
F2D = ROOT / "modules/godot_physics_2d/godot_space_2d.h"
F3D = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SCRIPT = ROOT / "tests/stress/physics_jolt_material_mix_regression.gd"
PREFIX = "JOLT_MATERIAL_MIX_RESULT:"


class MaterialCombineSourceContracts(unittest.TestCase):
    def test_new_jolt_modes_are_opt_in_and_clamped(self):
        cpp = JOLT_SETTINGS_CPP.read_text(encoding="utf-8")
        header = JOLT_SETTINGS_H.read_text(encoding="utf-8")
        for name, max_mode in (("friction_combine_mode", 3), ("restitution_combine_mode", 5)):
            key = f"physics/jolt_physics_3d/collisions/{name}"
            self.assertIn(f'"{key}"', cpp)
            self.assertIn(f'GLOBAL_GET("{key}"), 0, {max_mode})', cpp)
            self.assertIn(f"inline static int {name} = 0;", header)

    def test_callbacks_are_per_space_and_have_no_contact_time_setting_lookup(self):
        cpp = JOLT_SPACE.read_text(encoding="utf-8")
        self.assertIn("switch (JoltProjectSettings::friction_combine_mode)", cpp)
        self.assertIn("switch (JoltProjectSettings::restitution_combine_mode)", cpp)
        for mode in range(4):
            self.assertIn(f"SetCombineFriction(&combine_jolt_friction<{mode}>)", cpp)
        for mode in range(6):
            self.assertIn(f"SetCombineRestitution(&combine_jolt_restitution<{mode}>)", cpp)
        self.assertNotIn("GLOBAL_GET(", cpp)
        self.assertIn("godot_physics_combine_friction(", cpp)
        self.assertIn("godot_physics_combine_restitution(", cpp)

    def test_two_builtin_backends_use_same_shared_friction_formulas(self):
        for path in (F2D, F3D):
            contents = path.read_text(encoding="utf-8")
            self.assertIn('#include "servers/physics_friction_combine.h"', contents)
            self.assertIn("godot_physics_combine_friction(p_a, p_b, friction_combine_mode)", contents)


def simulate(godot: str, scenario: str, mode: int) -> float:
    with tempfile.TemporaryDirectory(prefix="cgame-jolt-material-") as temp_dir:
        temp_path = Path(temp_dir)
        config = (
            "config_version=5\n\n"
            "[application]\nconfig/name=\"Jolt material combine test\"\n\n"
            "[physics]\n3d/physics_engine=\"Jolt Physics\"\n"
            f"jolt_physics_3d/collisions/{'friction' if scenario == 'friction' else 'restitution'}_combine_mode={mode}\n\n"
            "[cgame_test]\n"
            f'scenario="{scenario}"\n'
        )
        (temp_path / "project.godot").write_text(config, encoding="utf-8")
        shutil.copyfile(SCRIPT, temp_path / SCRIPT.name)
        result = subprocess.run(
            [godot, "--headless", "--path", str(temp_path), "--script", f"res://{SCRIPT.name}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=75,
            check=False,
        )
        readings = [
            json.loads(line.split(PREFIX, 1)[1])
            for line in result.stdout.splitlines() if line.startswith(PREFIX)
        ]
        if result.returncode or len(readings) != 1 or not readings[0].get("passed"):
            raise AssertionError(
                f"Jolt scenario={scenario}, mode={mode}, status={result.returncode}:\n{result.stdout[-6000:]}"
            )
        return float(readings[0]["reading"])


class JoltMaterialRuntime(unittest.TestCase):
    def test_all_material_modes_with_isolated_real_jolt_spaces(self):
        binary = os.environ.get("CGAME_GODOT_BINARY")
        if not binary:
            self.skipTest("Requires CGAME_GODOT_BINARY or --godot")
        godot = os.path.abspath(binary)
        self.assertTrue(Path(godot).is_file(), godot)
        friction = [simulate(godot, "friction", mode) for mode in range(4)]
        bounce = [simulate(godot, "bounce", mode) for mode in range(6)]
        for value in friction + bounce:
            self.assertGreaterEqual(value, 0.0)
        # The legacy minimum of (1, 0.25) produces less resistance than
        # Box2D's sqrt(1 * 0.25) = 0.5. Other combinations are also checked.
        self.assertGreater(friction[0], friction[1] + 0.25, friction)
        self.assertGreaterEqual(friction[1] + 0.25, friction[2], friction)
        self.assertGreaterEqual(friction[2] + 0.25, friction[3], friction)

        # Bounce coefficients floor=0.1, sphere=0.3:
        # clamped sum 0.4 > max 0.3 > multiply 0.03.
        self.assertGreater(bounce[0], bounce[1] + 0.3, bounce)
        self.assertGreater(bounce[1], bounce[4] + 0.4, bounce)
        self.assertGreater(bounce[2], bounce[3], bounce)
        self.assertGreater(bounce[5], bounce[3], bounce)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Cgame editor executable with Jolt enabled")
    args = parser.parse_args()
    if args.godot:
        os.environ["CGAME_GODOT_BINARY"] = args.godot
    unittest.main(argv=["test_jolt_material_mix.py"], verbosity=2)
