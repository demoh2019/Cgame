"""Headless, dependency-free diagnostic parsing regressions for AI repair reports."""

import io
from pathlib import Path
import unittest

import ai_diagnostics as parse


class DiagnosticParserTests(unittest.TestCase):
    def setUp(self):
        self.stage = Path("/tmp/staged-game")

    def scan(self, text):
        return parse.scan_text(text, self.stage)

    def test_no_false_errors_from_clean_log(self):
        result = self.scan("Godot v4\nLoaded resources\n")
        self.assertEqual(result["error_count"], 0)
        self.assertEqual(result["diagnostics"], [])

    def test_error_and_warning_prefixes(self):
        result = self.scan("SCRIPT ERROR: broken\nERROR: missing\nParse Error: token\nWARNING: slowdown\n")
        self.assertEqual(result["error_count"], 3)
        self.assertEqual(result["warning_count"], 1)
        self.assertEqual([d["severity"] for d in result["diagnostics"]], ["error"] * 3 + ["warning"])

    def test_parse_inline_scene_path(self):
        result = self.scan("ERROR: res://ai_generated/scenes/main.tscn:17 - Broken resource")
        self.assertEqual(result["diagnostics"][0]["resource"], "res://ai_generated/scenes/main.tscn")
        self.assertEqual(result["diagnostics"][0]["line"], 17)

    def test_parse_inline_column(self):
        record = self.scan("SCRIPT ERROR: res://scripts/player.gd:12:7 Invalid call")["diagnostics"][0]
        self.assertEqual((record["line"], record["column"]), (12, 7))

    def test_parse_following_at_line(self):
        output = "SCRIPT ERROR: Parse Error: Unknown class\n  at: GDScript::reload (res://ai_generated/scripts/player.gd:42)\n"
        record = self.scan(output)["diagnostics"][0]
        self.assertEqual(record["resource"], "res://ai_generated/scripts/player.gd")
        self.assertEqual(record["line"], 42)

    def test_parse_unicode_resource_path(self):
        rec = self.scan("ERROR: res://сцены/雪.tscn:8 parse failed")["diagnostics"][0]
        self.assertEqual(rec["resource"], "res://сцены/雪.tscn")

    def test_reject_traversal_source_hint(self):
        rec = self.scan("ERROR: res://../outside.gd:4 error")["diagnostics"][0]
        self.assertNotIn("resource", rec)

    def test_reject_windows_separator_source_hint(self):
        rec = self.scan("ERROR: res://folder\\evil.gd:4 error")["diagnostics"][0]
        self.assertNotIn("resource", rec)

    def test_ignore_source_line_zero(self):
        rec = self.scan("ERROR: res://a.gd:0 invalid")["diagnostics"][0]
        self.assertNotIn("line", rec)

    def test_stage_absolute_path_redacted(self):
        result = self.scan("ERROR: /tmp/staged-game/secret.gd cannot load\n")
        self.assertIn("<STAGED_PROJECT>/secret.gd", result["errors"][0])
        self.assertNotIn("/tmp/staged-game", str(result))

    def test_ansi_color_codes_do_not_hide_errors(self):
        rec = self.scan("\x1b[31mSCRIPT ERROR: failure\x1b[0m")["diagnostics"][0]
        self.assertEqual(rec["severity"], "error")
        self.assertNotIn("\x1b", rec["message"])

    def test_limits_messages_but_tracks_total(self):
        result = self.scan("ERROR: failed\n" * 200 + "WARNING: suspect\n" * 100)
        self.assertEqual(result["error_count"], 200)
        self.assertEqual(result["warning_count"], 100)
        self.assertEqual(len(result["errors"]), parse.MAX_DIAGNOSTICS)
        self.assertEqual(len(result["warnings"]), parse.MAX_DIAGNOSTICS)
        self.assertEqual(len(result["diagnostics"]), 2 * parse.MAX_DIAGNOSTICS)

    def test_middle_error_not_lost_from_large_output(self):
        text = "ordinary line\n" * 10000 + "ERROR: res://scenes/fault.tscn:19 broken\n" + "ordinary line\n" * 10000
        result = self.scan(text)
        self.assertEqual(result["error_count"], 1)
        self.assertEqual(result["diagnostics"][0]["line"], 19)

    def test_oversized_line_has_bounded_message(self):
        result = self.scan("ERROR: " + "a" * 500_000 + "\nERROR: after a long line\n")
        self.assertEqual(result["error_count"], 2)
        self.assertLessEqual(max(map(len, result["errors"])), parse.MAX_MESSAGE_CHARS)
        self.assertEqual(result["errors"][1], "ERROR: after a long line")

    def test_no_code_evaluation_or_filesystem_read(self):
        result = self.scan("ERROR: res://x.gd:2 ${dangerous} /../../../secrets")
        self.assertEqual(result["diagnostics"][0]["line"], 2)

    def test_following_location_not_applied_across_another_message(self):
        record = self.scan("ERROR: first\nSome normal output\n at: GDScript (res://wrong.gd:4)")["diagnostics"][0]
        self.assertNotIn("resource", record)

    def test_warning_attaches_location(self):
        r = self.scan("WARNING: uncommon\n at: res://visuals/effect.gdshader:6")["diagnostics"][0]
        self.assertEqual((r["severity"], r["resource"], r["line"]), ("warning", "res://visuals/effect.gdshader", 6))

    def test_streaming_log_scan_reads_entire_binary_file(self):
        text = b"START\n" + (b"x" * 10_000_000) + b"\nERROR: middle issue\n" + b"END\n"
        with io.BytesIO(text) as stream:
            result = parse.scan_log(stream, self.stage)
        self.assertEqual(result["error_count"], 1)


if __name__ == "__main__":
    unittest.main()
