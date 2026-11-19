#!/usr/bin/env python3
"""Fast source-invariant guards for selected upstream Godot bugfix backports.

These checks detect accidental regression during merges. They do NOT replace
C++ compilation, native runtime tests or manual editor verification.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


def read_source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class UpstreamBackportGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.filesystem = read_source("editor/docks/filesystem_dock.cpp")
        cls.audio = read_source("scene/3d/audio_stream_player_3d.cpp")
        cls.gdscript = read_source("modules/gdscript/gdscript_editor.cpp")
        cls.render = read_source("servers/rendering/rendering_server_default.h")
        cls.image_tests = read_source("tests/core/io/test_image.cpp")

    def _filesystem_callback(self, name: str) -> str:
        prefix = "void FileSystemDock::" + name
        self.assertEqual(self.filesystem.count(prefix), 1)
        return self.filesystem.split(prefix, 1)[1].split("\nvoid FileSystemDock::", 1)[0]

    def test_file_removal_preserves_trailing_slash(self):
        callback = self._filesystem_callback("_file_removed")
        self.assertIn('if (current_path != "res://")', callback)
        self.assertIn('current_path = current_path + "/";', callback)

    def test_folder_removal_preserves_trailing_slash(self):
        callback = self._filesystem_callback("_folder_removed")
        self.assertIn('if (current_path != "res://")', callback)
        self.assertIn('current_path = current_path + "/";', callback)

    def test_root_not_double_slash_on_file_removal(self):
        callback = self._filesystem_callback("_file_removed")
        self.assertRegex(callback, r'if \(current_path != "res://"\)\s*\{\s*current_path = current_path \+ "/";\s*\}')

    def test_root_not_double_slash_on_folder_removal(self):
        callback = self._filesystem_callback("_folder_removed")
        self.assertRegex(callback, r'if \(current_path != "res://"\)\s*\{\s*current_path = current_path \+ "/";\s*\}')

    def test_audio_panning_updates_at_zero_playback_offset(self):
        self.assertIn("setplay.get() >= 0", self.audio)

    def test_audio_updates_mix_count_after_panning(self):
        self.assertRegex(
            self.audio,
            r"volume_vector = _update_panning\(\);\s*"
            r"last_mix_count = AudioServer::get_singleton\(\)->get_mix_count\(\);",
        )

    def test_gdscript_subscript_type_preserves_script_path(self):
        self.assertRegex(
            self.gdscript,
            r"r_base_type\.script_type = scr;\s*r_base_type\.script_path = scr->get_path\(\);",
        )

    def _texture_update(self) -> str:
        marker = "virtual void texture_2d_update(RID p_texture, const Ref<Image> &p_image, int p_layer) override"
        self.assertEqual(self.render.count(marker), 1)
        return self.render.split(marker, 1)[1].split("FUNC2(texture_3d_update", 1)[0]

    def test_renderer_keeps_snapshot_in_async_queue(self):
        update = self._texture_update()
        self.assertIn("if (ASYNC_COND_PUSH)", update)
        self.assertIn("snapshot = p_image->duplicate();", update)
        self.assertRegex(update, r"command_queue\.push\([^;]*p_texture, snapshot, p_layer\);")

    def test_renderer_accepts_null_image_safely(self):
        update = self._texture_update()
        self.assertRegex(update, r"Ref<Image> snapshot;\s*if \(p_image\.is_valid\(\)\)")

    def test_renderer_nonqueued_path_remains_direct(self):
        update = self._texture_update()
        self.assertRegex(
            update, r"command_queue\.flush_if_pending\(\);\s*"
            r"RSG::texture_storage->texture_2d_update\(p_texture, p_image, p_layer\);",
        )

    def test_native_snapshot_regression_tests_are_registered(self):
        self.assertIn('TEST_CASE("[Image] Queued upload snapshot keeps pixels when caller changes the image")', self.image_tests)
        self.assertIn('TEST_CASE("[Image] Multiple queued upload snapshots keep independent generations")', self.image_tests)


if __name__ == "__main__":
    unittest.main()
