"""Regression contracts for Godot PRs #125579, #125581 and #125549."""
from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def function(code: str, signature: str) -> str:
    pos = code.index(signature)
    start = code.index("{", pos)
    depth = 0
    for index in range(start, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return code[pos:index + 1]
    raise AssertionError("Unbalanced C++ function: " + signature)


class PropertyInfoContracts(unittest.TestCase):
    def test_literal_overload_exists(self):
        self.assertIn("PropertyInfo(Variant::Type p_type, const char *p_name", source("core/object/property_info.h"))

    def test_string_overload_kept(self):
        self.assertIn("PropertyInfo(Variant::Type p_type, const String &p_name", source("core/object/property_info.h"))

    def test_implementations_out_of_line(self):
        self.assertEqual(source("core/object/property_info.cpp").count("PropertyInfo::PropertyInfo("), 2)

    def test_resource_hint_overrides_class_name(self):
        implementation = function(source("core/object/property_info.cpp"),
                                  "PropertyInfo::PropertyInfo(const Variant::Type p_type, const char *p_name")
        self.assertIn("if (hint == PROPERTY_HINT_RESOURCE_TYPE)", implementation)
        self.assertIn("class_name = hint_string;", implementation)
        self.assertIn("} else if (p_class_name)", implementation)

    def test_null_class_name_does_not_intern(self):
        implementation = function(source("core/object/property_info.cpp"),
                                  "PropertyInfo::PropertyInfo(const Variant::Type p_type, const char *p_name")
        self.assertIn("class_name = StringName(p_class_name);", implementation)

    def test_classdb_overloads_present(self):
        header = source("core/object/class_db.h")
        self.assertIn("const char *p_setter, const char *p_getter", header)
        self.assertIn("const StringName &p_setter, const StringName &p_getter", header)

    def test_macros_use_overload_resolution(self):
        header = source("core/object/object.h")
        for key in ("#define ADD_PROPERTY(", "#define ADD_PROPERTYI("):
            line = next(l for l in header.splitlines() if l.startswith(key))
            self.assertNotIn("StringName(m_setter)", line)
            self.assertNotIn("StringName(m_getter)", line)

    def test_classdb_literal_delegates_to_interned(self):
        implementation = function(source("core/object/class_db.cpp"),
                                  "void ClassDB::add_property(const StringName &p_class, const PropertyInfo &p_pinfo, const char *p_setter")
        self.assertIn("StringName(p_setter), StringName(p_getter)", implementation)

    def test_native_regressions_included(self):
        native = source("tests/core/object/test_property_info_overloads.cpp")
        self.assertIn("TEST_FORCE_LINK(test_property_info_overloads)", native)
        self.assertGreaterEqual(native.count("CHECK("), 25)


class AndroidBuildContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.method = function(source("platform/android/display_server_android.cpp"),
                              "bool DisplayServerAndroid::check_vulkan_global_context(")

    def test_fallback_variable_only_under_opengl_guard(self):
        script = self.method
        guard = script.index("#if defined(GLES3_ENABLED)")
        name = script.index("bool fallback_to_opengl3")
        self.assertGreater(name, guard)
        self.assertLess(name, script.index("if (fallback_to_opengl3)"))

    def test_no_unused_fallback_when_gles3_disabled(self):
        cpp = shutil.which("c++")
        if not cpp:
            self.skipTest("C++ compiler unavailable")
        prelude = """
using Error = int;
constexpr Error ERR_CANT_CREATE = 1;
constexpr Error OK = 0;
struct RenderingContextDriverVulkanAndroid { Error initialize() { return ERR_CANT_CREATE; } };
struct OS {
    enum { RENDERING_SOURCE_FALLBACK = 1 };
    static OS *get_singleton() { static OS os; return &os; }
    void set_current_rendering_driver_name(const char *, int) {}
    void set_current_rendering_method(const char *, int) {}
};
#define GLOBAL_GET(x) true
#define memnew(T) new T
#define memdelete(x) delete x
#define WARN_PRINT(x) (void)0
#define ERR_PRINT(x) (void)0
class DisplayServerAndroid {
public:
    bool rendering_context_global_checked = false;
    RenderingContextDriverVulkanAndroid *rendering_context_global = nullptr;
    bool check_vulkan_global_context(bool);
};
"""
        for defines in ([], ["-DGLES3_ENABLED"]):
            with self.subTest(defines=defines):
                result = subprocess.run(
                    [cpp, "-x", "c++", "-std=c++17", "-Wall", "-Wextra",
                     "-Werror", "-fsyntax-only", *defines, "-"],
                    input=prelude + "\n" + self.method + "\n",
                    text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
