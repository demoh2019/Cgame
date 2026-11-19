"""Upstream #125526 source regression contracts for text-script stack growth.

These checks validate source structure and do not substitute for compiler,
AddressSanitizer or real complex-text shaping behavior tests.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "modules/text_server_adv/script_iterator.cpp"


class ScriptIteratorGrowthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SRC.read_text(encoding="utf-8")
        cls.emoji = cls.text[cls.text.index("emoji_size += EMOJI_STACK_DEPTH;"):]
        cls.paren = cls.text[cls.text.index("paren_size += PAREN_STACK_DEPTH;"):]

    def test_emoji_starter_stack_allocated(self):
        self.assertIn("emoji_stack = static_cast<EmojiSubrunEntry *>(memalloc(", self.emoji)

    def test_emoji_stack_copied_on_first_growth(self):
        self.assertIn("memcpy(emoji_stack, &starter_emoji_stack[0], EMOJI_STACK_DEPTH * sizeof(EmojiSubrunEntry));", self.emoji)

    def test_emoji_copy_after_allocation(self):
        self.assertLess(self.emoji.index("memalloc("), self.emoji.index("memcpy(emoji_stack"))

    def test_emoji_copy_before_realloc_branch(self):
        self.assertLess(self.emoji.index("memcpy(emoji_stack"), self.emoji.index("memrealloc(emoji_stack"))

    def test_emoji_first_growth_only(self):
        self.assertRegex(self.emoji, r"if \(emoji_stack == starter_emoji_stack\)\s*\{\s*emoji_stack = static_cast<EmojiSubrunEntry \*>\(memalloc\([^;]+;\s*memcpy\(emoji_stack")

    def test_emoji_realloc_preserved(self):
        self.assertIn("emoji_stack = static_cast<EmojiSubrunEntry *>(memrealloc(emoji_stack, emoji_size * sizeof(EmojiSubrunEntry)));", self.emoji)

    def test_emoji_copy_uses_element_size(self):
        self.assertIn("EMOJI_STACK_DEPTH * sizeof(EmojiSubrunEntry)", self.emoji)

    def test_emoji_stack_growth_budget_preserved(self):
        self.assertIn("emoji_size += EMOJI_STACK_DEPTH;", self.emoji)

    def test_emoji_entries_written_after_growth(self):
        self.assertLess(self.emoji.index("memrealloc(emoji_stack"), self.emoji.index("emoji_stack[emoji_sp].start = script_end;"))

    def test_emoji_dynamic_storage_freed(self):
        self.assertIn("if (emoji_stack != starter_emoji_stack)", self.text)
        self.assertIn("memfree(emoji_stack);", self.text)

    def test_paren_starter_stack_allocated(self):
        self.assertIn("paren_stack = static_cast<ParenStackEntry *>(memalloc(", self.paren)

    def test_paren_stack_copied_on_first_growth(self):
        self.assertIn("memcpy(paren_stack, &starter_paren_stack[0], PAREN_STACK_DEPTH * sizeof(ParenStackEntry));", self.paren)

    def test_paren_copy_after_allocation(self):
        self.assertLess(self.paren.index("memalloc("), self.paren.index("memcpy(paren_stack"))

    def test_paren_copy_before_realloc_branch(self):
        self.assertLess(self.paren.index("memcpy(paren_stack"), self.paren.index("memrealloc(paren_stack"))

    def test_paren_first_growth_only(self):
        self.assertRegex(self.paren, r"if \(paren_stack == starter_paren_stack\)\s*\{\s*paren_stack = static_cast<ParenStackEntry \*>\(memalloc\([^;]+;\s*memcpy\(paren_stack")

    def test_paren_realloc_preserved(self):
        self.assertIn("paren_stack = static_cast<ParenStackEntry *>(memrealloc(paren_stack, paren_size * sizeof(ParenStackEntry)));", self.paren)

    def test_paren_copy_uses_element_size(self):
        self.assertIn("PAREN_STACK_DEPTH * sizeof(ParenStackEntry)", self.paren)

    def test_paren_stack_growth_budget_preserved(self):
        self.assertIn("paren_size += PAREN_STACK_DEPTH;", self.paren)

    def test_paren_entries_written_after_growth(self):
        self.assertLess(self.paren.index("memrealloc(paren_stack"), self.paren.index("paren_stack[paren_sp].pair_index = ch;"))

    def test_paren_dynamic_storage_freed(self):
        self.assertIn("if (paren_stack != starter_paren_stack)", self.text)
        self.assertIn("memfree(paren_stack);", self.text)

    def test_no_duplicate_first_growth_memcpy(self):
        self.assertEqual(self.text.count("memcpy(emoji_stack, &starter_emoji_stack[0]"), 1)
        self.assertEqual(self.text.count("memcpy(paren_stack, &starter_paren_stack[0]"), 1)

    def test_paren_script_metadata_preserved(self):
        self.assertIn("paren_stack[paren_sp].script_code = script_code;", self.text)

    def test_bidi_paired_bracket_search_preserved(self):
        self.assertIn("paren_stack[paren_sp].pair_index != paired_ch", self.text)


if __name__ == "__main__":
    unittest.main()
