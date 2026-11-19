"""Test Cgame's constexpr GDCLASS binding checks against upstream Godot #124495."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ClassBindingPerf(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = (ROOT / "core/object/object.h").read_text(encoding="utf-8")

    def test_compile_time_trait_defined(self):
        self.assertIn("inline constexpr bool _is_same_bind_function = false;", self.h)
        self.assertIn("inline constexpr bool _is_same_bind_function<A, A> = true;", self.h)

    def test_runtime_pointer_checks_removed(self):
        self.assertNotIn("if (m_class::_get_bind_methods() != m_inherits::_get_bind_methods())", self.h)
        self.assertNotIn("if (m_class::_get_bind_compatibility_methods() != m_inherits::_get_bind_compatibility_methods())", self.h)

    def test_dispatch_is_if_constexpr(self):
        self.assertIn("if constexpr (!_is_same_bind_function<m_class::_get_bind_methods(), m_inherits::_get_bind_methods()>)", self.h)
        self.assertIn("if constexpr (!_is_same_bind_function<m_class::_get_bind_compatibility_methods(), m_inherits::_get_bind_compatibility_methods()>)", self.h)

    def test_macro_pointer_accessors_constexpr(self):
        self.assertIn("static constexpr void (*_get_bind_methods())()", self.h)
        self.assertIn("static constexpr void (*_get_bind_compatibility_methods())()", self.h)

    def test_object_base_accessors_constexpr(self):
        self.assertIn("return &Object::_bind_methods;", self.h)
        self.assertIn("return &Object::_bind_compatibility_methods;", self.h)

    def test_safe_flag_thread_safety_kept(self):
        self.assertIn("static SafeFlag initialized;", self.h)
        self.assertIn("MutexLock lock(__init_mutex);", self.h)
        self.assertIn("_initialize_class_cold(initialized);", self.h)

    def test_cold_once_path_kept(self):
        self.assertIn("_NO_INLINE_ _COLD_ static void _initialize_class_cold(SafeFlag &initialized)", self.h)
        self.assertIn("initialized.set();", self.h)

    def test_native_static_asserts_exist(self):
        code = (ROOT / "tests/core/object/test_object.cpp").read_text()
        self.assertIn("static_assert(_is_same_bind_function<", code)
        self.assertIn("static_assert(!_is_same_bind_function<", code)

    @unittest.skipUnless(shutil.which("c++"), "No C++ compiler")
    def test_actual_pointer_trait_with_compile_time_hierarchy(self):
        start = self.h.index("// Compare class method bind functions at compile time.")
        end = self.h.index("/// Provides ", start)
        trait = self.h[start:end]
        example = """
void same() {}
void other() {}
static_assert(_is_same_bind_function<&same, &same>);
static_assert(!_is_same_bind_function<&same, &other>);
struct Base {
    static void _bind_methods() {}
    static constexpr void (*_get_bind_methods())() { return &Base::_bind_methods; }
};
struct DerivedInherited {
    static constexpr void (*_get_bind_methods())() { return Base::_get_bind_methods(); }
};
struct DerivedOverride {
    static void _bind_methods() {}
    static constexpr void (*_get_bind_methods())() { return &DerivedOverride::_bind_methods; }
};
static_assert(_is_same_bind_function<Base::_get_bind_methods(), DerivedInherited::_get_bind_methods()>);
static_assert(!_is_same_bind_function<Base::_get_bind_methods(), DerivedOverride::_get_bind_methods()>);
int main() { return 0; }
"""
        with tempfile.TemporaryDirectory() as tmp:
            exe = str(Path(tmp) / "test")
            build = subprocess.run(
                ["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                 "-x", "c++", "-", "-o", exe],
                input=trait + example, text=True, capture_output=True,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            result = subprocess.run([exe], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
