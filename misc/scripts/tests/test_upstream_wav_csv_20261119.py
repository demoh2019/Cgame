#!/usr/bin/env python3
"""Source regression guards for upstream Godot #123401 and #123812.

These prevent partial patch regressions. Native [AudioStreamWAV] tests and an
actual editor project save/import smoke test are required independently.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class TranslationCsvGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.editor = source("editor/script/script_editor_plugin.cpp")
        cls.header = source("editor/script/script_editor_plugin.h")
        cls.source_block = cls.editor.split("void DocumentEditorContainer::_saved_reimport(", 1)[1].split(
            "\nbool DocumentEditorContainer::edit", 1)[0]

    def test_saved_reimport_has_header_declaration(self):
        self.assertIn("void _saved_reimport(const String &p_path);", self.header)

    def test_editor_includes_importer_api(self):
        self.assertIn('#include "core/io/resource_importer.h"', self.editor)

    def test_reimport_only_after_file_saved(self):
        block = self.editor.split("Error DocumentEditorContainer::_save_text_file(", 1)[1].split(
            "\nvoid DocumentEditorContainer::_saved_reimport", 1)[0]
        self.assertLess(block.index("file->store_string(source);"), block.index("_saved_reimport(p_path);"))
        self.assertLess(block.index("EditorFileSystem::get_singleton()->update_file(p_path);"), block.index("_saved_reimport(p_path);"))

    def test_reimport_keeps_resource_save_callback(self):
        block = self.editor.split("Error DocumentEditorContainer::_save_text_file(", 1)[1].split(
            "\nvoid DocumentEditorContainer::_saved_reimport", 1)[0]
        self.assertLess(block.index("_saved_reimport(p_path);"), block.index("_res_saved_callback(sqscr);"))

    def test_importer_is_detected_not_guessed_from_extension(self):
        self.assertIn("get_import_order_threads_and_importer(p_path, order, can_threads, importer)", self.source_block)

    def test_unknown_importer_is_not_reimported(self):
        self.assertRegex(self.source_block, r"if \(err != OK\) \{\s*return;\s*\}")

    def test_only_translation_csv_is_reimported(self):
        self.assertIn('if (importer == "csv_translation")', self.source_block)
        self.assertIn("EditorFileSystem::get_singleton()->reimport_files({ p_path });", self.source_block)

    def test_non_csv_importers_not_explicitly_handled(self):
        self.assertNotIn('if (importer == "gdscript")', self.source_block)
        self.assertNotIn('if (importer == "text")', self.source_block)


class WaveLoopGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.wav = source("scene/resources/audio/audio_stream_wav.cpp")
        cls.tests = source("tests/scene/test_audio_stream_wav.cpp")

    def test_disabled_loop_uses_last_valid_sample(self):
        self.assertIn(
            "int64_t end_limit = ((base->loop_mode != AudioStreamWAV::LOOP_DISABLED) ? loop_end : len) - 1;",
            self.wav)

    def test_pingpong_does_not_play_terminal_sample_twice(self):
        self.assertIn("offset = loop_end - (offset - loop_end) - 2;", self.wav)

    def test_qoa_allocation_excludes_extra_frame(self):
        self.assertIn("MIN(sample->qoa.desc.samples, (uint32_t)QOA_FRAME_LEN)", self.wav)
        self.assertNotIn("MIN(sample->qoa.desc.samples + 1", self.wav)

    def test_negative_loop_begin_wraps_from_end_exclusive(self):
        self.assertIn("loop_begin = CLAMP(loop_begin + frames + 1, 0, frames);", self.wav)

    def test_negative_loop_end_wraps_from_end_exclusive(self):
        self.assertIn("loop_end = CLAMP(loop_end + frames + 1, 0, frames);", self.wav)

    def test_loop_begin_and_end_do_not_overflow_frame_count(self):
        self.assertIn("loop_begin = MIN(loop_begin, frames);", self.wav)
        self.assertIn("loop_end = MIN(loop_end, frames);", self.wav)

    def test_loop_options_only_apply_to_forced_loop_modes(self):
        block = self.wav.split("if (import_loop_mode >= 2)", 1)[1].split("int compression =", 1)[0]
        self.assertIn('p_options.get("edit/loop_begin", 0)', block)
        self.assertIn('p_options.get("edit/loop_end", 0)', block)

    def test_native_test_checks_negative_one_as_end_exclusive(self):
        self.assertIn("WAV loop negative offsets are end-relative", self.tests)
        self.assertIn("{ -1, -1, 64, 64 }", self.tests)

    def test_native_test_checks_clamping(self):
        self.assertIn("{ 8, 1000, 8, 64 }", self.tests)
        self.assertIn("{ -65, -66, 0, 0 }", self.tests)

    def test_native_test_covers_forward_pingpong_backward(self):
        self.assertIn("WAV explicit loop endpoints preserve last-frame boundary", self.tests)
        self.assertIn("for (int loop_mode : { 2, 3, 4 })", self.tests)


if __name__ == "__main__":
    unittest.main()
