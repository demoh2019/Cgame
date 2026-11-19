"""Source contracts for String::replace() single-character fast path.

Run after checking out engine root. The C++ tests validate functional equivalence.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class StringSingleCharReplaceFastPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / 'core/string/ustring.cpp').read_text(encoding='utf-8')
        cls.native = (ROOT / 'tests/core/string/test_string.cpp').read_text(encoding='utf-8')

    def section(self, signature):
        start = self.cpp.index(signature)
        end = self.cpp.index('\n}\n', start)
        return self.cpp[start:end]

    def test_string_overload_uses_replace_char(self):
        section = self.section('String String::replace(const String &p_key, const String &p_with) const {')
        self.assertIn('return replace_char(p_key.ptr()[0], p_with.ptr()[0]);', section)

    def test_char_overload_uses_replace_char(self):
        section = self.section('String String::replace(const char *p_key, const char *p_with) const {')
        self.assertIn('return replace_char(p_key[0], p_with[0]);', section)

    def test_unicode_is_supported(self):
        section = self.section('String String::replace(const String &p_key, const String &p_with) const {')
        self.assertIn('p_key.length() == 1 && p_with.length() == 1', section)

    def test_embedded_null_preserves_fallback(self):
        section = self.section('String String::replace(const String &p_key, const String &p_with) const {')
        self.assertIn('p_key.ptr()[0] != 0 && p_with.ptr()[0] != 0', section)

    def test_non_ascii_byte_preserves_fallback(self):
        section = self.section('String String::replace(const char *p_key, const char *p_with) const {')
        self.assertIn('static_cast<unsigned char>(p_key[0]) < 128', section)
        self.assertIn('static_cast<unsigned char>(p_with[0]) < 128', section)

    def test_multiple_characters_preserve_fallback(self):
        for signature in ('String String::replace(const String &p_key, const String &p_with) const {', 'String String::replace(const char *p_key, const char *p_with) const {'):
            self.assertIn('return _replace_common(*this, p_key, p_with, false);', self.section(signature))

    def test_no_positions_buffer_for_repeated_character(self):
        section = self.section('String String::replace_char(char32_t p_key, char32_t p_with) const {')
        self.assertNotIn('LocalVector<int> found;', section)
        self.assertIn('for (++index; index < len; ++index)', section)

    def test_replace_char_noop_returns_shared_buffer(self):
        section = self.section('String String::replace_char(char32_t p_key, char32_t p_with) const {')
        self.assertIn('if (p_key == p_with)', section)
        self.assertIn('return *this;', section)

    def test_single_character_delete_shortcut(self):
        section = self.section('String String::replace(const String &p_key, const String &p_with) const {')
        self.assertIn('return remove_char(p_key.ptr()[0]);', section)
        self.assertIn('p_with.is_empty()', section)

    def test_ascii_delete_shortcut(self):
        section = self.section('String String::replace(const char *p_key, const char *p_with) const {')
        self.assertIn('return remove_char(p_key[0]);', section)
        self.assertIn('p_with[0] == 0', section)

    def test_repeat_empty_returns_without_allocating(self):
        section = self.section('String String::repeat(int p_count) const {')
        self.assertIn('if (len == 0)', section)
        self.assertIn('return *this;', section)

    def test_native_tests_present(self):
        for term in ('[String] Replace character fast path Unicode and ASCII', '[String] Replace char fast path COW and no-op', '[String] Replace preserves multi-character semantics', '[String] Replace deletion fast path and empty repeat'):
            self.assertIn(term, self.native)

if __name__ == '__main__':
    unittest.main()
