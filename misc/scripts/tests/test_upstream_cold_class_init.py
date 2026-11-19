"""Source regression contracts for the Cgame-safe upstream cold init adaptation.

The fork uses SafeFlag for class init; the upstream PR used a plain boolean.
The optimized hot/cold split intentionally keeps SafeFlag and the lock so
multi-threaded class registration is still single-shot.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def src(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ColdClassInitContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.obj = src("core/object/object.h")
        cls.typedef = src("core/typedefs.h")
        cls.main = src("main/main.h")
        cls.block = cls.obj.split("#define GDCLASS(m_class, m_inherits) \\\n", 1)[1].split(
            "virtual void _initialize_classv() override", 1
        )[0]
        cls.hot = cls.block.split("static void initialize_class() {", 1)[1].split(
            "_NO_INLINE_ _COLD_ static void _initialize_class_cold", 1
        )[0]
        cls.cold = cls.block.split("_initialize_class_cold(SafeFlag &initialized) {", 1)[1]

    def test_cold_macro_exists(self):
        self.assertIn("#ifndef _COLD_", self.typedef)

    def test_cold_attribute_on_gcc_and_clang(self):
        self.assertIn("#define _COLD_ __attribute__((cold))", self.typedef)

    def test_cold_attribute_fallback_for_other_compilers(self):
        self.assertRegex(self.typedef, re.compile(
            r"#if defined\(__GNUC__\)\s*"
            r"#define _COLD_ __attribute__\(\(cold\)\)\s*"
            r"#else\s*#define _COLD_\s*#endif", re.S
        ))

    def test_hot_class_entrypoint_exists(self):
        self.assertIn("static void initialize_class()", self.block)

    def test_hot_path_preserves_atomic_safe_flag(self):
        self.assertIn("static SafeFlag initialized;", self.block)

    def test_hot_path_does_not_add_plain_boolean(self):
        self.assertNotIn("static bool initialized", self.block)
        self.assertNotIn("static inline bool _class_initialized", self.block)

    def test_fast_path_checks_already_initialized(self):
        self.assertIn("if (likely(initialized.is_set()))", self.block)

    def test_fast_path_returns_before_slow_call(self):
        self.assertLess(
            self.block.index("if (likely(initialized.is_set()))"),
            self.block.index("_initialize_class_cold(initialized);"),
        )

    def test_slow_path_accepts_shared_flag_by_reference(self):
        self.assertIn("_initialize_class_cold(SafeFlag &initialized)", self.block)

    def test_slow_path_is_cold(self):
        self.assertIn("_COLD_ static void _initialize_class_cold", self.block)

    def test_slow_path_not_inlined(self):
        self.assertIn("_NO_INLINE_ _COLD_", self.block)

    def test_mutex_remains_in_cold_path(self):
        self.assertLess(self.block.index("_initialize_class_cold(SafeFlag &initialized)"),
                        self.block.index("_initialize_class_cold(SafeFlag &initialized)") + self.cold.index("static BinaryMutex __init_mutex;"))

    def test_lock_before_second_check(self):
        self.assertLess(self.cold.index("MutexLock lock(__init_mutex);"),
                        self.cold.index("if (initialized.is_set())"))

    def test_secondary_guard_kept_under_lock(self):
        self.assertRegex(self.cold, re.compile(
            r"MutexLock lock\(__init_mutex\);\s*\\\s*"
            r"if \(initialized\.is_set\(\)\)\s*\{", re.S))

    def test_parent_initialized_before_registering_child(self):
        self.assertLess(self.block.index("m_inherits::initialize_class();"),
                        self.block.index("_add_class_to_classdb("))

    def test_gdtype_registration_is_preserved(self):
        self.assertIn("get_gdtype_static_mutable().initialize();", self.block)

    def test_bind_methods_are_preserved(self):
        self.assertIn("_bind_methods();", self.block)
        self.assertIn("_bind_compatibility_methods();", self.block)

    def test_flag_set_after_bindings(self):
        self.assertLess(self.cold.index("_bind_compatibility_methods();"),
                        self.cold.index("initialized.set();"))

    def test_class_init_still_initializes_virtual_base(self):
        self.assertIn("virtual void _initialize_classv() override", self.obj)

    def test_safe_flag_memory_model_not_bypassed(self):
        self.assertEqual(self.hot.count("static SafeFlag initialized;"), 1)
        self.assertEqual(self.cold.count("initialized.set();"), 1)
        self.assertNotIn("static bool initialized", self.cold)

    def test_main_setup_is_cold(self):
        self.assertIn("_COLD_ static Error setup(", self.main)

    def test_main_setup2_is_cold(self):
        self.assertIn("_COLD_ static Error setup2(", self.main)

    def test_main_start_is_cold(self):
        self.assertIn("_COLD_ static int start();", self.main)

    def test_main_cleanup_is_cold(self):
        self.assertIn("_COLD_ static void cleanup(", self.main)

    def test_main_iteration_not_marked_cold(self):
        self.assertIn("static bool iteration();", self.main)
        self.assertNotIn("_COLD_ static bool iteration();", self.main)


if __name__ == "__main__":
    unittest.main()
