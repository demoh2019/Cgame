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


    def unity_sprite(self, guid="0123456789abcdef0123456789abcdef", extra="", game_id="100", component="401"):
        return (f"--- !u!212 &{component}\nSpriteRenderer:\n"
                f"  m_GameObject: {{fileID: {game_id}}}\n"
                f"  m_Sprite: {{fileID: 21300000, guid: {guid}, type: 3}}\n"
                f"{extra}")

    def unity_meta(self, name="Assets/Art/hero.png", guid="0123456789abcdef0123456789abcdef", extra=""):
        self.write(name + ".meta", f"fileFormatVersion: 2\nguid: {guid}\n{extra}")

    def test_sprite_renderer_ext_resource_generated(self):
        img = "res://imported/unity/Art/hero.png"
        data, nodes, warnings = convert_unity_scene(
            UNITY_SCENE + self.unity_sprite(), {"0123456789abcdef0123456789abcdef": img})
        scene = data.decode()
        self.assertEqual(nodes, 2)
        self.assertIn('[gd_scene load_steps=2 format=3]', scene)
        self.assertIn(f'path="{img}"', scene)
        self.assertIn('[node name="Sprite" type="Sprite3D" parent="Parent"]', scene)
        self.assertIn('texture = ExtResource("1")', scene)
        self.assertNotIn("SpriteRenderer 401", " ".join(warnings))

    def test_unity_sprite_meta_resolves_in_manifest(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"PNG_BYTES")
        self.unity_meta()
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        assets = result["report"]["assets"]
        self.assertEqual([a["source"] for a in assets], ["Art/hero.png", "Scene.tscn"])
        self.assertTrue(all(".meta" not in a["target"] for a in assets))
        count, skipped = apply_plan(result, self.target)
        self.assertEqual((count, skipped), (3, 0))
        scene = (self.target / "imported/unity/Scene.tscn").read_text()
        self.assertIn('path="res://imported/unity/Art/hero.png"', scene)
        self.assertEqual(len(result["report"]["assets"]), 2)

    def test_unity_sprite_missing_guid_warns_and_skips(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("Sprite3D", scene.content.decode())
        self.assertIn("GUID unavailable", " ".join(result["report"]["warnings"]))

    def test_unity_sprite_disabled_renderer(self):
        scene, _, _ = convert_unity_scene(UNITY_SCENE + self.unity_sprite(extra="  m_Enabled: 0\n"),
                       {"0123456789abcdef0123456789abcdef": "res://imported/unity/a.png"})
        self.assertIn('[node name="Sprite" type="Sprite3D" parent="Parent"]\ntexture = ExtResource("1")\nvisible = false', scene.decode())

    def test_unity_sprite_flip(self):
        scene, _, _ = convert_unity_scene(UNITY_SCENE + self.unity_sprite(extra="  m_FlipX: 1\n  m_FlipY: 1\n"),
                       {"0123456789abcdef0123456789abcdef": "res://imported/unity/a.png"})
        self.assertIn("flip_h = true", scene.decode())
        self.assertIn("flip_v = true", scene.decode())

    def test_unity_sprite_color(self):
        scene, _, _ = convert_unity_scene(UNITY_SCENE + self.unity_sprite(extra="  m_Color: {r: 0.25, g: 1, b: 0.75, a: 0.5}\n"),
                       {"0123456789abcdef0123456789abcdef": "res://imported/unity/a.png"})
        self.assertIn("modulate = Color(0.25, 1, 0.75, 0.5)", scene.decode())

    def test_unity_sprite_invalid_color_uses_default(self):
        scene, _, _ = convert_unity_scene(UNITY_SCENE + self.unity_sprite(extra="  m_Color: {r: nan, g: 1, b: 1, a: 1}\n"),
                       {"0123456789abcdef0123456789abcdef": "res://imported/unity/a.png"})
        self.assertNotIn("modulate =", scene.decode())

    def test_unity_sprite_empty_asset_does_not_warn(self):
        contents = (UNITY_SCENE + self.unity_sprite().replace("fileID: 21300000", "fileID: 0"))
        _, _, messages = convert_unity_scene(contents)
        self.assertNotIn("GUID unavailable", " ".join(messages))

    def test_unity_sprite_unknown_texture_not_referenced(self):
        scene, _, messages = convert_unity_scene(UNITY_SCENE + self.unity_sprite())
        self.assertNotIn("ext_resource", scene.decode())
        self.assertIn("GUID unavailable", " ".join(messages))

    def test_unity_sprite_duplicate_references_share_single_ext_resource(self):
        contents = UNITY_SCENE + self.unity_sprite() + self.unity_sprite(game_id="101", component="402")
        scene, _, _ = convert_unity_scene(contents,
                     {"0123456789abcdef0123456789abcdef": "res://imported/unity/hero.png"})
        text = scene.decode()
        self.assertEqual(text.count("[ext_resource"), 1)
        self.assertEqual(text.count('texture = ExtResource("1")'), 2)
        self.assertIn('parent="Parent/Child"', text)

    def test_unity_sprite_renderer_name_collision(self):
        contents = UNITY_SCENE.replace('m_Name: Child', 'm_Name: Sprite') + self.unity_sprite()
        scene, _, _ = convert_unity_scene(contents, {"0123456789abcdef0123456789abcdef": "res://imported/unity/hero.png"})
        txt = scene.decode()
        self.assertEqual(txt.count('parent="Parent"'), 2)
        self.assertIn('name="Sprite_401_1"', txt)

    def test_unity_sprite_renderer_missing_gameobject_warns(self):
        _, _, warnings = convert_unity_scene(UNITY_SCENE + self.unity_sprite(game_id="999"))
        self.assertIn("no converted Transform", " ".join(warnings))

    def test_unity_sprite_draw_mode_warns(self):
        _, _, warnings = convert_unity_scene(UNITY_SCENE + self.unity_sprite(extra="  m_DrawMode: 2\n  m_SortingOrder: 7\n"),
                         {"0123456789abcdef0123456789abcdef": "res://imported/unity/hero.png"})
        self.assertTrue(any("sliced/tiled" in w for w in warnings))
        self.assertTrue(any("sorting order" in w for w in warnings))

    def test_unity_multi_sprite_atlas_is_not_imported_as_whole(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta(extra="  spriteMode: 2\n")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        self.assertIn("atlas", " ".join(result["report"]["warnings"]))
        self.assertIn("GUID unavailable", " ".join(result["report"]["warnings"]))
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("Sprite3D", scene.content.decode())

    def test_unity_duplicate_guids_rejected(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"one")
        self.write("Assets/Art/enemy.png", b"two")
        self.unity_meta("Assets/Art/hero.png")
        self.unity_meta("Assets/Art/enemy.png")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        self.assertIn("duplicate Unity texture GUID", " ".join(result["report"]["warnings"]))
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("Sprite3D", scene.content.decode())

    def test_unity_invalid_guid_is_not_used(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta(guid="not-a-guid")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        self.assertIn("invalid Unity texture GUID", " ".join(result["report"]["warnings"]))
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("Sprite3D", scene.content.decode())

    def test_unity_oversized_meta_is_skipped(self):
        self.unity()
        self.write("Assets/Art/hero.png")
        self.write("Assets/Art/hero.png.meta", "guid: " + "f" * 32 + "\n" + "X" * (256 * 1024))
        result = plan(self.source, self.target)
        self.assertIn("oversized", " ".join(result["report"]["warnings"]))

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_unity_symlinked_meta_is_ignored(self):
        self.unity()
        self.write("Assets/Art/hero.png")
        outside = self.write("secret.txt", "guid: " + "f" * 32)
        try:
            (self.source / "Assets/Art/hero.png.meta").symlink_to(outside)
        except OSError:
            self.skipTest("Symlinks restricted")
        result = plan(self.source, self.target)
        self.assertEqual([a["source"] for a in result["report"]["assets"]], ["Art/hero.png"])

    def test_unity_sprite_extension_not_supported(self):
        self.unity()
        self.write("Assets/Art/hero.exr")
        self.unity_meta("Assets/Art/hero.exr")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("Sprite3D", scene.content.decode())

    def test_unity_camera_perspective(self):
        contents = UNITY_SCENE + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 100}
  orthographic: 0
  field of view: 65
  near clip plane: 0.2
  far clip plane: 500
'''
        scene, count, warnings = convert_unity_scene(contents)
        self.assertEqual(count, 2)
        txt = scene.decode()
        self.assertIn('[node name="Camera" type="Camera3D" parent="Parent"]', txt)
        self.assertIn('fov = 65', txt)
        self.assertIn('near = 0.2', txt)
        self.assertIn('far = 500', txt)
        self.assertIn("render settings", " ".join(warnings))

    def test_unity_camera_orthographic_size_doubled(self):
        contents = UNITY_SCENE + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 101}
  orthographic: 1
  orthographic size: 4
'''
        scene, _, _ = convert_unity_scene(contents)
        txt = scene.decode()
        self.assertIn('parent="Parent/Child"', txt)
        self.assertIn('projection = 1', txt)
        self.assertIn('size = 8', txt)
        self.assertNotIn('fov = ', txt)

    def test_unity_camera_disabled(self):
        contents = UNITY_SCENE + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 101}
  m_Enabled: 0
'''
        scene, _, _ = convert_unity_scene(contents)
        self.assertIn('current = false', scene.decode())

    def test_unity_camera_unknown_gameobject_warns(self):
        contents = UNITY_SCENE + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 999}
'''
        scene, _, warnings = convert_unity_scene(contents)
        self.assertNotIn('Camera3D', scene.decode())
        self.assertIn("no converted Transform", " ".join(warnings))

    def test_unity_camera_inactive_gameobject(self):
        contents = UNITY_SCENE.replace("m_IsActive: 1", "m_IsActive: 0", 1) + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 100}
'''
        scene, _, _ = convert_unity_scene(contents)
        self.assertIn("current = false", scene.decode())

    def test_unity_camera_invalid_clip_is_omitted(self):
        contents = UNITY_SCENE + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 100}
  near clip plane: 10
  far clip plane: 1
'''
        scene, _, _ = convert_unity_scene(contents)
        self.assertNotIn('near = ', scene.decode())
        self.assertNotIn('far = ', scene.decode())

    def test_unity_camera_invalid_fov_not_emitted(self):
        contents = UNITY_SCENE + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 100}
  field of view: nan
'''
        scene, _, _ = convert_unity_scene(contents)
        self.assertIn('fov = 75', scene.decode())

    def test_unity_both_camera_and_sprite_on_same_gameobject(self):
        contents = UNITY_SCENE + self.unity_sprite() + '''--- !u!20 &500
Camera:
  m_GameObject: {fileID: 100}
'''
        scene, _, _ = convert_unity_scene(contents,
                      {"0123456789abcdef0123456789abcdef": "res://imported/unity/hero.png"})
        txt = scene.decode()
        self.assertIn('type="Camera3D"', txt)
        self.assertIn('type="Sprite3D"', txt)
        self.assertEqual(txt.count('parent="Parent"'), 3)

    def test_unity_asset_apply_idempotency_with_sprite_scene(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta()
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        self.assertEqual(apply_plan(result, self.target), (3, 0))
        self.assertEqual(apply_plan(result, self.target), (0, 3))

    def test_unity_asset_changed_does_not_overwrite_sprite_scene(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"first")
        self.unity_meta()
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        first = plan(self.source, self.target)
        apply_plan(first, self.target)
        self.write("Assets/Art/hero.png", b"different")
        with self.assertRaisesRegex(ImportErrorDetail, "overwrite"):
            apply_plan(plan(self.source, self.target), self.target)
        self.assertEqual((self.target / "imported/unity/Art/hero.png").read_bytes(), b"first")


    def test_unity_sprite_custom_pixels_per_unit(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta(extra="TextureImporter:\n  spritePixelsToUnits: 32\n")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertIn("pixel_size = 0.03125", scene.content.decode())

    def test_unity_sprite_default_pixels_per_unit(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta(extra="TextureImporter:\n  spritePixelsToUnits: 100\n")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("pixel_size =", scene.content.decode())

    def test_unity_sprite_invalid_pixels_per_unit_falls_back(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta(extra="TextureImporter:\n  spritePixelsToUnits: 0\n")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        self.assertIn("invalid sprite pixels-per-unit", " ".join(result["report"]["warnings"]))
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn("pixel_size =", scene.content.decode())

    def test_unity_sprite_atlas_order_prevents_duplicate_guid_fallback(self):
        self.unity()
        self.write("Assets/Art/a.png", b"one")
        self.write("Assets/Art/b.png", b"two")
        self.unity_meta("Assets/Art/a.png", extra="spriteMode: 2\n")
        self.unity_meta("Assets/Art/b.png")
        self.write("Assets/Scene.unity", UNITY_SCENE + self.unity_sprite())
        result = plan(self.source, self.target)
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertNotIn('Sprite3D', scene.content.decode())

    def test_unity_sprite_case_insensitive_guid(self):
        self.unity()
        self.write("Assets/Art/hero.png", b"image")
        self.unity_meta(guid="ABCDEF0123456789ABCDEF0123456789")
        self.write("Assets/Scene.unity", UNITY_SCENE +
                   self.unity_sprite(guid="abcdef0123456789abcdef0123456789"))
        result = plan(self.source, self.target)
        scene = next(e for e in result["entries"] if e.destination.endswith(".tscn"))
        self.assertIn("Sprite3D", scene.content.decode())


if __name__ == "__main__":
    unittest.main()