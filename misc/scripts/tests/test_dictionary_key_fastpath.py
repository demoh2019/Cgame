"""Guard no-conversion Dictionary hot paths without a native engine build.

Tests are source contracts, not a substitute for the native Dictionary tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'core/variant/dictionary.cpp'
TESTS = ROOT / 'tests/core/variant/test_dictionary.cpp'


def method_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index('{', start)
    level = 1
    for i in range(opening + 1, len(source)):
        if source[i] == '{':
            level += 1
        elif source[i] == '}':
            level -= 1
            if level == 0:
                return source[opening + 1:i]
    raise ValueError(f'unterminated: {signature}')


class DictionaryKeyFastPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding='utf-8')
        cls.tests = TESTS.read_text(encoding='utf-8')

    def method(self, sig):
        return method_body(self.source, sig)

    def test_const_bracket_shortcut(self):
        fn = self.method('const Variant &Dictionary::operator[](const Variant &p_key) const')
        self.assertIn('_p->typed_key.variant_type == Variant::NIL', fn)
        self.assertIn('_p->variant_map.getptr(p_key)', fn)
        self.assertLess(fn.index('_p->variant_map.getptr(p_key)'), fn.index('_p->typed_key.validate('))

    def test_const_bracket_missing_key_does_not_insert(self):
        fn = self.method('const Variant &Dictionary::operator[](const Variant &p_key) const')
        self.assertIn('ERR_FAIL_NULL_V_MSG', fn)
        self.assertNotIn('_p->variant_map[p_key]', fn)

    def test_mutable_pointer_shortcut(self):
        fn = self.method('Variant *Dictionary::getptr(const Variant &p_key)')
        self.assertIn('_p->typed_key.variant_type == Variant::NIL', fn)
        self.assertIn('_p->variant_map.getptr(p_key)', fn)
        self.assertLess(fn.index('_p->variant_map.getptr(p_key)'), fn.index('_p->typed_key.validate('))

    def test_mutable_pointer_preserves_read_only(self):
        fn = self.method('Variant *Dictionary::getptr(const Variant &p_key)')
        self.assertIn('_p->read_only', fn)
        self.assertIn('return _p->read_only', fn)

    def test_set_fast_key(self):
        fn = self.method('bool Dictionary::set(const Variant &p_key, const Variant &p_value)')
        self.assertIn('_p->typed_key.variant_type == Variant::NIL', fn)
        self.assertIn('_p->variant_map[p_key]', fn)
        self.assertLess(fn.index('_p->variant_map[p_key]'), fn.index('_p->typed_key.validate('))

    def test_set_preserves_typed_value_validator(self):
        fn = self.method('bool Dictionary::set(const Variant &p_key, const Variant &p_value)')
        self.assertIn('_p->typed_value.validate(p_value', fn)
        self.assertIn('ERR_FAIL_NULL_V(value, false)', fn)

    def test_set_preserves_readonly_guard(self):
        fn = self.method('bool Dictionary::set(const Variant &p_key, const Variant &p_value)')
        self.assertIn('ERR_FAIL_COND_V_MSG(_p->read_only, false,', fn)

    def test_erase_fast_key(self):
        fn = self.method('bool Dictionary::erase(const Variant &p_key)')
        self.assertIn('_p->typed_key.variant_type == Variant::NIL', fn)
        self.assertIn('_p->variant_map.erase(p_key)', fn)
        self.assertLess(fn.index('_p->variant_map.erase(p_key)'), fn.index('_p->typed_key.validate('))

    def test_erase_preserves_readonly_guard(self):
        fn = self.method('bool Dictionary::erase(const Variant &p_key)')
        self.assertIn('ERR_FAIL_COND_V_MSG(_p->read_only, false,', fn)

    def test_get_or_add_shortcut(self):
        fn = self.method('Variant Dictionary::get_or_add(const Variant &p_key, const Variant &p_default)')
        self.assertIn('_p->typed_key.variant_type == Variant::NIL', fn)
        self.assertIn('_p->variant_map.getptr(p_key)', fn)
        self.assertLess(fn.index('_p->variant_map.getptr(p_key)'), fn.index('_p->typed_key.validate('))

    def test_get_or_add_preserves_typed_value_validator(self):
        fn = self.method('Variant Dictionary::get_or_add(const Variant &p_key, const Variant &p_default)')
        self.assertIn('_p->typed_value.validate(p_default', fn)
        self.assertIn('ERR_FAIL_NULL_V(value, p_default)', fn)

    def test_untouched_existing_has_fastpath(self):
        fn = self.method('bool Dictionary::has(const Variant &p_key) const')
        self.assertIn('_p->variant_map.has(p_key)', fn)

    def test_typed_validation_still_exists_in_every_method(self):
        for sig in (
            'const Variant &Dictionary::operator[](const Variant &p_key) const',
            'Variant *Dictionary::getptr(const Variant &p_key)',
            'Variant Dictionary::get_or_add(const Variant &p_key, const Variant &p_default)',
            'bool Dictionary::set(const Variant &p_key, const Variant &p_value)',
            'bool Dictionary::erase(const Variant &p_key)',
        ):
            with self.subTest(sig=sig):
                self.assertIn('_p->typed_key.validate(', self.method(sig))

    def test_native_regression_cases(self):
        for name in (
            'untyped lookup and mutable pointer',
            'untyped set, erase and get_or_add',
            'typed dictionary retains key coercion',
            'read-only dictionary keeps writable view isolated',
        ):
            self.assertIn(name, self.tests)

    def test_tests_in_godot_test_file(self):
        self.assertGreaterEqual(self.tests.count('TEST_CASE("[DictionaryFastPath]'), 10)


if __name__ == '__main__':
    unittest.main()
