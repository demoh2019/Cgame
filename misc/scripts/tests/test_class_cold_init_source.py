"""Structural checks for size/cold-path GDCLASS initialization backport.

Native C++ tests exercise actual class registration and inherited method binds.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ColdClassInitializationContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.object = (ROOT / "core/object/object.h").read_text(encoding="utf-8")
        cls.types = (ROOT / "core/typedefs.h").read_text(encoding="utf-8")
        cls.main = (ROOT / "main/main.h").read_text(encoding="utf-8")
        cls.native = (ROOT / "tests/core/object/test_object.cpp").read_text(encoding="utf-8")
        cls.macro = cls.object.split("#define GDCLASS(m_class, m_inherits)", 1)[1].split("#define OBJ_SAVE_TYPE", 1)[0]

    def test_cold_marker_gcc(self):
        self.assertIn("#define _COLD_ __attribute__((cold))", self.types)

    def test_cold_marker_fallback(self):
        self.assertIn("#define _COLD_", self.types)

    def test_cold_helper_is_separate(self):
        self.assertIn("_COLD_ static void _initialize_class_cold()", self.macro)

    def test_fast_path_checks_atomic_flag(self):
        self.assertIn("if (likely(_class_initialized.is_set()))", self.macro)

    def test_flag_is_still_atomic(self):
        self.assertIn("static inline SafeFlag _class_initialized", self.macro)
        self.assertNotIn("static inline bool _class_initialized", self.macro)

    def test_flag_published_on_slow_path(self):
        self.assertIn("_class_initialized.set();", self.macro)

    def test_slow_path_double_check(self):
        self.assertIn("if (_class_initialized.is_set())", self.macro)

    def test_slow_path_uses_mutex(self):
        self.assertIn("MutexLock lock(__init_mutex);", self.macro)

    def test_slow_path_first_registers_base(self):
        self.assertLess(self.macro.index("m_inherits::initialize_class();"), self.macro.index("get_gdtype_static_mutable().initialize();"))

    def test_method_binding_is_compile_time(self):
        self.assertIn("if constexpr (!_is_same_function<", self.macro)
        self.assertEqual(self.macro.count("if constexpr (!_is_same_function<"), 2)

    def test_method_pointer_constexpr(self):
        self.assertIn("static constexpr void (*_get_bind_methods())()", self.macro)
        self.assertIn("static constexpr void (*_get_bind_compatibility_methods())()", self.macro)

    def test_object_base_pointer_constexpr(self):
        self.assertIn("static constexpr void (*_get_bind_methods())()", self.object)

    def test_cold_helper_called_only_from_slow_path(self):
        self.assertIn("_initialize_class_cold();", self.macro)

    def test_setup_marked_cold(self):
        self.assertIn("_COLD_ static Error setup(", self.main)
        self.assertIn("_COLD_ static Error setup2(", self.main)

    def test_start_and_cleanup_cold(self):
        self.assertIn("_COLD_ static int start();", self.main)
        self.assertIn("_COLD_ static void cleanup(", self.main)

    def test_frame_loop_remains_hot(self):
        self.assertIn("static bool iteration();", self.main)
        self.assertNotIn("_COLD_ static bool iteration();", self.main)

    def test_native_idempotence(self):
        self.assertIn('TEST_CASE("[Object] GDCLASS cold initializer binds exactly once")', self.native)

    def test_native_inheritance(self):
        self.assertIn('TEST_CASE("[Object] GDCLASS cold initializer inherits bindings")', self.native)


if __name__ == "__main__":
    unittest.main()
