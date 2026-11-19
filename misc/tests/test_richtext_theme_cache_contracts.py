"""Regression contracts for the RichTextLabel theme font-cache fast path."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = (ROOT / "scene/gui/rich_text_label.h").read_text(encoding="utf-8")
SOURCE = (ROOT / "scene/gui/rich_text_label.cpp").read_text(encoding="utf-8")
THEME = HEADER.split("struct ThemeCache {", 1)[1].split("bool operator==(", 1)[0]
COMPARISON = HEADER.split("bool operator==(", 1)[1].split("bool operator!=(", 1)[0]
NOTIFICATION = SOURCE.split("case NOTIFICATION_THEME_CHANGED: {", 1)[1].split("} break;", 1)[0]


class RichTextThemeCacheContracts(unittest.TestCase):
    def test_comparator_covers_every_theme_cache_field(self):
        fields = set(re.findall(
            r"^\s*(?:Ref<[^>]+>|int|Color|float)\s+(\w+)(?:\s*=\s*[^;]+)?;",
            THEME, re.MULTILINE))
        compared = set(re.findall(r"\b(\w+)\s*==\s*p_other\.(\w+)", COMPARISON))
        self.assertTrue(fields)
        self.assertEqual(fields, {left for left, right in compared if left == right})
        self.assertEqual(len(fields), len(compared))

    def test_style_only_changes_skip_font_cache_invalidation(self):
        self.assertIn("theme_cache_old.normal_style = theme_cache.normal_style;", NOTIFICATION)
        self.assertIn("theme_cache_old.focus_style = theme_cache.focus_style;", NOTIFICATION)
        self.assertLess(NOTIFICATION.index("theme_cache_old.focus_style"), NOTIFICATION.index("if (theme_cache != theme_cache_old)"))

    def test_font_cache_invalidation_is_conditional(self):
        self.assertRegex(NOTIFICATION, r"if \(theme_cache != theme_cache_old\) \{\s*main->first_invalid_font_line\.store\(0\);\s*\}")

    def test_cache_is_updated_and_layout_refresh_preserved(self):
        self.assertLess(NOTIFICATION.index("if (theme_cache != theme_cache_old)"), NOTIFICATION.index("theme_cache_old = theme_cache;"))
        self.assertIn("main->first_resized_line.store(0);", NOTIFICATION)


if __name__ == "__main__":
    unittest.main()
