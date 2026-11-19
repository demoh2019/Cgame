#!/usr/bin/env python3
"""Offline regression tests: no dependency on Unity/Unreal/Godot executables."""
from __future__ import annotations

from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from engine_project_import import (  # noqa: E402
    ImportErrorDetail, apply_plan, convert_unity_scene, detect_engine,
    gltf_dependencies, main, plan,
)


UNITY_SCENE = '''%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!1 &100
GameObject:
  m_Name: Parent
  m_IsActive: 1
--- !u!4 &200
Transform:
  m_GameObject: {fileID: 100}
  m_Father: {fileID: 0}
  m_LocalPosition: {x: 1, y: 2, z: 3}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 2, z: 3}
--- !u!1 &101
GameObject:
  m_Name: Child
  m_IsActive: 0
--- !u!4 &201
Transform:
  m_GameObject: {fileID: 101}
  m_Father: {fileID: 200}
  m_LocalPosition: {x: 2, y: 3, z: -4}
  m_LocalRotation: {x: 0.5, y: 0, z: 0, w: 0.8660254}
  m_LocalScale: {x: 1, y: 1, z: 1}
--- !u!114 &300
MonoBehaviour:
  m_Script: {fileID: 0}
'''


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.target = self.root / "target"
        self.target.mkdir()
        (self.target / "project.godot").write_text('config_version=5\n', encoding="utf8")

    def write(self, filename, contents=b"test"):
        path = self.source / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, str):
            contents = contents.encode("utf8")
        path.write_bytes(contents)
        return path

    def unity(self):
        (self.source / "Assets").mkdir(exist_ok=True)
        (self.source / "ProjectSettings").mkdir(exist_ok=True)

    def unreal(self):
        self.write("Adventure.uproject", "{}")
        (self.source / "Content").mkdir(exist_ok=True)

    def cli(self, *args):
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            status = main([str(self.source), str(self.target), *args])
        return status, out.getvalue(), err.getvalue()

    def test_unity_detected(self):
        self.unity()
        self.assertEqual(detect_engine(self.source), "unity")

    def test_unreal_detected(self):
        self.unreal()
        self.assertEqual(detect_engine(self.source), "unreal")

    def test_gamemaker_detected(self):
        self.write("game.yyp", "{}")
        self.assertEqual(detect_engine(self.source), "gamemaker")

    def test_defold_detected(self):
        self.write("game.project", "[project]")
        self.assertEqual(detect_engine(self.source), "defold")

    def test_unknown_engine_errors(self):
        with self.assertRaisesRegex(ImportErrorDetail, "detect"):
            plan(self.source, self.target)

    def test_generic_override(self):
        self.write("hero.png", b"picture")
        self.assertEqual(len(plan(self.source, self.target, "generic")["report"]["assets"]), 1)

    def test_invalid_engine_errors(self):
        with self.assertRaisesRegex(ImportErrorDetail, "Unknown engine"):
            plan(self.source, self.target, "other")

    def test_unreal_needs_content(self):
        self.write("some.uproject")
        with self.assertRaisesRegex(ImportErrorDetail, "missing"):
            plan(self.source, self.target)

    def test_target_must_be_godot_project(self):
        (self.target / "project.godot").unlink()
        with self.assertRaisesRegex(ImportErrorDetail, "project.godot"):
            plan(self.source, self.target, "generic")

    def test_nonexistent_source(self):
        with self.assertRaises(ImportErrorDetail):
            plan(self.root / "none", self.target, "generic")

    def test_nested_dest_rejected(self):
        self.write("project.godot")
        with self.assertRaisesRegex(ImportErrorDetail, "separate"):
            plan(self.source, self.source, "generic")

    def test_nested_source_rejected(self):
        source = self.target / "child"
        source.mkdir()
        with self.assertRaisesRegex(ImportErrorDetail, "separate"):
            plan(source, self.target, "generic")

    def test_safely_lists_portable_assets(self):
        self.unity()
        self.write("Assets/Audio/music.ogg", b"data")
        self.write("Assets/Art/sprite.png", b"pixels")
        self.write("Assets/Scripts/Enemy.cs", "// script")
        self.write("Assets/Art/sprite.png.meta", "guid: abc")
        got = plan(self.source, self.target)
        self.assertEqual([a["source"] for a in got["report"]["assets"]],
                         ["Art/sprite.png", "Audio/music.ogg"])
        self.assertEqual(got["report"]["unsupported_extensions"], {".cs": 1, ".meta": 1})

    def test_unreal_portable_assets(self):
        self.unreal()
        self.write("Content/a.glb")
        self.write("Content/a.uasset")
        self.assertEqual(plan(self.source, self.target)["report"]["unsupported_extensions"], {".uasset": 1})

    def test_ignores_build_caches_and_dotpaths(self):
        self.write(".git/secret.png")
        self.write("Library/x.png")
        self.write("Assets/valid.png")
        self.write("Assets/.hidden.png")
        self.assertEqual([a["source"] for a in plan(self.source, self.target, "generic")["report"]["assets"]],
                         ["Assets/valid.png"])

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_skips_symlinks(self):
        asset = self.write("real.png")
        try:
            (self.source / "fake.png").symlink_to(asset)
        except OSError:
            self.skipTest("Symlinks restricted")
        self.assertEqual(len(plan(self.source, self.target, "generic")["report"]["assets"]), 1)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_skips_symlinked_directories(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "secret.png").write_bytes(b"private")
        try:
            (self.source / "linked").symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks restricted")
        self.assertEqual(plan(self.source, self.target, "generic")["report"]["assets"], [])

    def test_dry_run_does_not_write(self):
        self.write("a.png", b"abc")
        code, stdout, stderr = self.cli("--engine", "generic")
        self.assertEqual(code, 0, stderr)
        self.assertTrue(json.loads(stdout)["dry_run"])
        self.assertFalse((self.target / "imported").exists())

    def test_apply_copies_bytes_and_manifest(self):
        self.write("asset.glb", b"\x00\xfe\xff")
        code, stdout, stderr = self.cli("--engine", "generic", "--apply")
        self.assertEqual(code, 0, stderr)
        self.assertEqual(json.loads(stdout)["written"], 2)
        self.assertEqual((self.target / "imported/generic/asset.glb").read_bytes(), b"\x00\xfe\xff")
        manifest = json.loads((self.target / "imported/generic/import_manifest.json").read_text())
        self.assertEqual(manifest["assets"][0]["bytes"], 3)
        self.assertEqual(len(manifest["assets"][0]["sha256"]), 64)

    def test_second_run_is_idempotent(self):
        self.write("a.png", b"abc")
        self.assertEqual(self.cli("--engine", "generic", "--apply")[0], 0)
        code, output, _ = self.cli("--engine", "generic", "--apply")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output)["written"], 0)
        self.assertEqual(json.loads(output)["unchanged"], 2)

    def test_refuses_conflict_before_writing(self):
        self.write("a.png", b"new")
        target = self.target / "imported/generic/a.png"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"existing")
        self.write("b.png", b"other")
        code, _, err = self.cli("--engine", "generic", "--apply")
        self.assertEqual(code, 2)
        self.assertIn("overwrite", err)
        self.assertEqual(target.read_bytes(), b"existing")
        self.assertFalse((target.parent / "b.png").exists())

    def test_manifest_conflict_after_source_change(self):
        self.write("a.png", b"1")
        self.assertEqual(self.cli("--engine", "generic", "--apply")[0], 0)
        self.write("a.png", b"2")
        self.assertEqual(self.cli("--engine", "generic", "--apply")[0], 2)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_target_symlink_refused(self):
        self.write("a.png")
        outside = self.root / "outside"
        outside.mkdir()
        (self.target / "imported").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ImportErrorDetail):
            apply_plan(plan(self.source, self.target, "generic"), self.target)
        self.assertFalse(list(outside.iterdir()))

    def test_gltf_sidecar_binary_and_texture(self):
        self.write("models/scene.gltf", json.dumps({"buffers": [{"uri": "mesh.bin"}],
            "images": [{"uri": "textures/hero.png"}]}))
        self.write("models/mesh.bin", b"geometry")
        self.write("models/textures/hero.png", b"image")
        assets = plan(self.source, self.target, "generic")["report"]["assets"]
        self.assertEqual([x["source"] for x in assets], ["models/mesh.bin", "models/scene.gltf", "models/textures/hero.png"])

    def test_gltf_embedded_data(self):
        self.write("a.gltf", json.dumps({"buffers": [{"uri": "data:application/octet-stream;base64,AA=="}]}))
        self.assertEqual(len(plan(self.source, self.target, "generic")["report"]["assets"]), 1)

    def test_gltf_missing_reference_warns(self):
        self.write("a.gltf", json.dumps({"buffers": [{"uri": "missing.bin"}]}))
        self.assertIn("missing", " ".join(plan(self.source, self.target, "generic")["report"]["warnings"]))

    def test_gltf_traversal_disallowed(self):
        self.write("a.gltf", json.dumps({"buffers": [{"uri": "../secret.bin"}]}))
        (self.root / "secret.bin").write_bytes(b"do not copy")
        assets = plan(self.source, self.target, "generic")["report"]["assets"]
        self.assertEqual(len(assets), 1)

    def test_gltf_external_uri_disallowed(self):
        self.write("a.gltf", json.dumps({"buffers": [{"uri": "https://host/mesh.bin"}]}))
        self.assertIn("external", " ".join(plan(self.source, self.target, "generic")["report"]["warnings"]))

    def test_invalid_gltf_does_not_crash(self):
        self.write("a.gltf", "not json")
        self.assertIn("invalid glTF", " ".join(plan(self.source, self.target, "generic")["report"]["warnings"]))

    def test_unity_converts_hierarchy_and_transforms(self):
        data, count, warnings = convert_unity_scene(UNITY_SCENE)
        txt = data.decode()
        self.assertEqual(count, 2)
        self.assertIn('parent="Parent"', txt)
        self.assertIn("position = Vector3(1, 2, -3)", txt)
        self.assertIn("position = Vector3(2, 3, 4)", txt)
        self.assertIn("scale = Vector3(1, 2, 3)", txt)
        self.assertIn("quaternion = Quaternion(-0.5, -0, 0, 0.8660254)", txt)
        self.assertIn("visible = false", txt)
        self.assertIn("class 114", str(warnings))

    def test_unity_generates_scene_into_project(self):
        self.unity()
        self.write("Assets/World/Level.unity", UNITY_SCENE)
        r = plan(self.source, self.target)
        self.assertEqual([a["source"] for a in r["report"]["assets"]], ["World/Level.tscn"])
        self.assertEqual(apply_plan(r, self.target)[0], 2)
        self.assertIn("ImportedUnityScene", (self.target / "imported/unity/World/Level.tscn").read_text())

    def test_unity_prefab_conversion(self):
        self.unity()
        self.write("Assets/Tree.prefab", UNITY_SCENE)
        self.assertEqual(plan(self.source, self.target)["report"]["assets"][0]["source"], "Tree.tscn")

    def test_unity_binary_scene_warns_and_skips(self):
        self.unity()
        self.write("Assets/Level.unity", b"\xff\x00")
        r = plan(self.source, self.target)
        self.assertEqual(r["report"]["assets"], [])
        self.assertIn("skipped scene", " ".join(r["report"]["warnings"]))

    def test_unity_rejects_empty_scene(self):
        with self.assertRaises(ImportErrorDetail):
            convert_unity_scene("%YAML 1.1\n--- !u!114 &1\nMonoBehaviour:\n")

    def test_unity_rejects_cycles(self):
        contents = UNITY_SCENE.replace("m_Father: {fileID: 0}", "m_Father: {fileID: 201}")
        with self.assertRaisesRegex(ImportErrorDetail, "Cyclic"):
            convert_unity_scene(contents)

    def test_unity_duplicate_names_renamed(self):
        content = UNITY_SCENE.replace("m_Name: Child", "m_Name: Parent").replace("m_Father: {fileID: 200}", "m_Father: {fileID: 0}")
        data, _, _ = convert_unity_scene(content)
        self.assertIn('name="Parent_101"', data.decode())

    def test_unity_sanitizes_path_names(self):
        content = UNITY_SCENE.replace("m_Name: Child", "m_Name: Unsafe/Path:Name")
        data, _, _ = convert_unity_scene(content)
        self.assertIn('name="Unsafe_Path_Name"', data.decode())

    def test_unity_omits_without_transform(self):
        content = UNITY_SCENE + "--- !u!1 &999\nGameObject:\n  m_Name: Lost\n"
        data, count, warnings = convert_unity_scene(content)
        self.assertEqual(count, 2)
        self.assertIn("without 3D Transform", str(warnings))

    def test_unity_root_order_includes_children(self):
        content = UNITY_SCENE.replace("--- !u!1 &100", "--- !u!1 &100", 1)
        data, _, _ = convert_unity_scene(content)
        self.assertLess(data.index(b'name="Parent"'), data.index(b'name="Child"'))

    def test_destination_collision_same_scene_stem(self):
        self.unity()
        self.write("Assets/A.unity", UNITY_SCENE)
        self.write("Assets/A.prefab", UNITY_SCENE)
        with self.assertRaisesRegex(ImportErrorDetail, "same destination"):
            plan(self.source, self.target)

    def test_cli_failure_code_and_stderr(self):
        code, output, err = self.cli()
        self.assertEqual(code, 2)
        self.assertEqual(output, "")
        self.assertIn("detect", err)


if __name__ == "__main__":
    unittest.main()