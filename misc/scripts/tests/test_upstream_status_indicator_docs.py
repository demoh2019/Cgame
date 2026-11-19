"""Regression contracts for upstream Godot PR #125606 StatusIndicator documentation."""

from __future__ import annotations

import os
from pathlib import Path
import unittest
from xml.etree import ElementTree

ROOT = Path(os.environ.get("GODOT_BACKPORT_ROOT", Path(__file__).resolve().parents[3]))
DOC = ROOT / "doc/classes/StatusIndicator.xml"


class StatusIndicatorDocumentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ElementTree.parse(DOC).getroot()

    def test_class_identity_preserved(self):
        self.assertEqual(self.root.attrib["name"], "StatusIndicator")
        self.assertEqual(self.root.attrib["inherits"], "Node")

    def test_brief_description_is_short_and_still_describes_notification_area(self):
        text = "".join(self.root.find("brief_description").itertext())
        self.assertIn("notification area icon", text)
        self.assertNotIn("[b]Note:[/b]", text)

    def test_long_description_explains_core_functionality(self):
        text = "".join(self.root.find("description").itertext())
        for fragment in ("system tray", "icon", "tooltip", "custom menu"):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, text)

    def test_platform_support_note_is_retained_in_description(self):
        text = "".join(self.root.find("description").itertext())
        self.assertIn("implemented on macOS and Windows", text)

    def test_runtime_reference_methods_remain_documented(self):
        methods = self.root.find("methods")
        self.assertIsNotNone(methods)
        self.assertIn("get_rect", [m.attrib["name"] for m in methods.findall("method")])


if __name__ == "__main__":
    unittest.main()
