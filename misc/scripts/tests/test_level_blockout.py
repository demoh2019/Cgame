"""Offline tests for JSON to Godot 3D blockout generation."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import level_blockout as lb


class BlockoutTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.infile = self.root / "level.json"
        self.outfile = self.root / "level.tscn"
        self.doc = {"version": 1, "name": "Arena", "blocks": [
            {"name": "Floor", "position": [0, -0.5, 0], "size": [20, 1, 20]},
            {"name": "Step", "position": [3, 1, 0], "size": [2, 1, 2], "color": "#22CC88"},
        ]}

    def scene(self, replacement=None):
        return lb.make_scene(self.doc if replacement is None else replacement)

    def bad(self, replacement):
        with self.assertRaises(lb.LevelError):
            self.scene(replacement)

    def test_scene_header(self):
        self.assertIn("[gd_scene load_steps=7 format=3]", self.scene())

    def test_scene_root(self):
        self.assertIn('[node name="Arena" type="Node3D"]', self.scene())

    def test_static_physics(self):
        self.assertEqual(self.scene().count('type="StaticBody3D"'), 2)

    def test_colliders(self):
        self.assertEqual(self.scene().count('type="CollisionShape3D"'), 2)

    def test_meshes(self):
        self.assertEqual(self.scene().count('type="BoxMesh"'), 2)

    def test_color_materials(self):
        self.assertEqual(self.scene().count('type="StandardMaterial3D"'), 2)

    def test_camera(self):
        self.assertIn('type="Camera3D"', self.scene())

    def test_light(self):
        self.assertIn('type="DirectionalLight3D"', self.scene())

    def test_mesh_shape_dimensions_match(self):
        self.assertEqual(self.scene().count("Vector3(20.0, 1.0, 20.0)"), 2)

    def test_deterministic_scene(self):
        self.assertEqual(self.scene(), self.scene())

    def test_doc_unchanged(self):
        before = json.dumps(self.doc, sort_keys=True)
        self.scene()
        self.assertEqual(before, json.dumps(self.doc, sort_keys=True))

    def test_reject_version(self):
        self.bad({**self.doc, "version": 3})

    def test_reject_bool_version(self):
        self.bad({**self.doc, "version": True})

    def test_reject_root_unknown_key(self):
        self.bad({**self.doc, "extra": "ignored?"})

    def test_reject_bad_scene_name(self):
        self.bad({**self.doc, "name": 'Bad"Scene'})

    def test_reject_empty_scene(self):
        self.bad({**self.doc, "blocks": []})

    def test_reject_many_blocks(self):
        blocks = [{"name": "B{}".format(i), "position": [0, 0, 0], "size": [1, 1, 1]}
                  for i in range(lb.MAX_BLOCKS + 1)]
        self.bad({**self.doc, "blocks": blocks})

    def test_reject_duplicate_case_insensitive(self):
        self.bad({**self.doc, "blocks": self.doc["blocks"] + [
            {"name": "floor", "position": [0, 0, 0], "size": [1, 1, 1]}]})

    def test_reject_reserved_camera(self):
        self.bad({**self.doc, "blocks": [
            {"name": "Camera", "position": [0, 0, 0], "size": [1, 1, 1]}]})

    def test_reject_custom_script(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [0, 0, 0], "size": [1, 1, 1], "script": "hacker.gd"}]})

    def test_reject_bad_color(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [0, 0, 0], "size": [1, 1, 1], "color": "orange"}]})

    def test_reject_zero_dimension(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [0, 0, 0], "size": [1, 0, 1]}]})

    def test_reject_huge_dimension(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [0, 0, 0], "size": [1, 2000, 1]}]})

    def test_reject_nan(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [float("nan"), 0, 0], "size": [1, 1, 1]}]})

    def test_reject_boolean_position(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [True, 0, 0], "size": [1, 1, 1]}]})

    def test_reject_position_outside_range(self):
        self.bad({**self.doc, "blocks": [
            {"name": "A", "position": [10001, 0, 0], "size": [1, 1, 1]}]})

    def test_duplicate_json_keys_rejected(self):
        self.infile.write_text('{"version":1,"version":2,"name":"Arena","blocks":[]}')
        with self.assertRaises(lb.LevelError):
            lb.read_spec(self.infile)

    def test_missing_source_rejected(self):
        with self.assertRaises(lb.LevelError):
            lb.read_spec(self.infile)

    def test_output_extension_validation(self):
        with self.assertRaises(lb.LevelError):
            lb.write_scene(self.root / "bad.txt", self.scene())

    def test_output_parent_validation(self):
        with self.assertRaises(lb.LevelError):
            lb.write_scene(self.root / "absent" / "level.tscn", self.scene())

    def test_no_overwrite(self):
        self.outfile.write_text("old")
        with self.assertRaises((lb.LevelError, OSError)):
            lb.write_scene(self.outfile, self.scene())
        self.assertEqual(self.outfile.read_text(), "old")

    def test_explicit_overwrite(self):
        self.outfile.write_text("old")
        lb.write_scene(self.outfile, self.scene(), overwrite=True)
        self.assertIn("[gd_scene", self.outfile.read_text())

    def test_cli_success(self):
        self.infile.write_text(json.dumps(self.doc))
        result = subprocess.run([sys.executable, lb.__file__, str(self.infile),
                                 "-o", str(self.outfile)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["blocks"], 2)

    def test_invalid_spec_preserves_existing_output(self):
        self.outfile.write_text("old")
        self.infile.write_text('{"version":2}')
        result = subprocess.run([sys.executable, lb.__file__, str(self.infile),
                                 "-o", str(self.outfile), "--overwrite"], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.outfile.read_text(), "old")

    def test_symlinked_input_rejected(self):
        self.infile.write_text(json.dumps(self.doc))
        link = self.root / "linked.json"
        try:
            link.symlink_to(self.infile)
        except (NotImplementedError, OSError):
            self.skipTest("No symlink support")
        with self.assertRaises(lb.LevelError):
            lb.read_spec(link)

    def test_symlinked_output_rejected(self):
        target = self.root / "real.tscn"
        target.write_text("original")
        try:
            self.outfile.symlink_to(target)
        except (NotImplementedError, OSError):
            self.skipTest("No symlink support")
        with self.assertRaises(lb.LevelError):
            lb.write_scene(self.outfile, self.scene(), overwrite=True)
        self.assertEqual(target.read_text(), "original")

    def test_portable_vector_values(self):
        self.assertIn("Vector3(0.0, -0.5, 0.0)", self.scene())


if __name__ == "__main__":
    unittest.main()
