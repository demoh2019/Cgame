#!/usr/bin/env python3
"""Godot #125620 (cleanup), #125561 (Basis warning flags), #125606 (docs).

These tests run the actual SCons conditional and compile a C++ harness from
the production error-path branch. They do not replace full engine builds.
"""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[3]


def _display_failure():
    code = (ROOT / "main/main.cpp").read_text(encoding="utf-8")
    marker = 'ERR_PRINT("Unable to create DisplayServer, all display drivers failed.'
    location = code.index(marker)
    opening = "\t\tif (err != OK || display_server == nullptr) {"
    start = code.rfind(opening, 0, location)
    if start == -1:
        raise AssertionError("No display failure branch")
    last_return = code.index("\n\t\t\treturn err;", location)
    end = code.index("\n\t\t}", last_return) + len("\n\t\t}")
    return code[start:end]


class DisplayFailureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.branch = _display_failure()

    def test_uses_full_display_shutdown(self):
        self.assertEqual(self.branch.count("finalize_display();"), 1)
        self.assertNotIn("memdelete(display_server);", self.branch)

    def test_navigation_cleanup_is_before_extensions(self):
        for label in ("2D", "3D"):
            marker = "NavigationServer" + label + "Manager::finalize_server_manager();"
            self.assertEqual(self.branch.count(marker), 1)
            self.assertIn("#ifndef NAVIGATION_" + label + "_DISABLED", self.branch)
            self.assertLess(self.branch.index(marker), self.branch.index("deinitialize_extensions("))

    def test_cleanup_order(self):
        names = ("finalize_display();", "deinitialize_extensions(",
                 "uninitialize_modules(", "unregister_server_types();", "memdelete(input);",
                 "memdelete(tsman);", "return err;")
        for before, after in zip(names, names[1:]):
            self.assertLess(self.branch.index(before), self.branch.index(after))

    def test_physics_cleanup_still_guarded(self):
        for label in ("2D", "3D"):
            self.assertIn("#ifndef PHYSICS_" + label + "_DISABLED", self.branch)
            self.assertIn("PhysicsServer" + label + "Manager::finalize_server_manager();", self.branch)

    def test_success_does_not_take_failure_branch(self):
        self.assertIn("if (err != OK || display_server == nullptr) {", self.branch)

    @unittest.skipUnless(shutil.which("c++"), "C++ compiler unavailable")
    def test_extracted_cpp_branch_executes_cleanup_once(self):
        prefix = r"""
#include <string>
#include <vector>
std::vector<std::string> events;
enum Error { OK, FAIL };
struct DisplayServer {};
DisplayServer *display_server = nullptr;
void *input = nullptr;
void *tsman = nullptr;
void finalize_display() { events.push_back("display"); display_server = nullptr; }
struct NavigationServer2DManager { static void finalize_server_manager() { events.push_back("nav2"); } };
struct NavigationServer3DManager { static void finalize_server_manager() { events.push_back("nav3"); } };
struct PhysicsServer2DManager { static void finalize_server_manager() { events.push_back("phys2"); } };
struct PhysicsServer3DManager { static void finalize_server_manager() { events.push_back("phys3"); } };
struct GDExtension { enum { INITIALIZATION_LEVEL_SERVERS = 1 }; };
struct GDExtensionManager {
    static GDExtensionManager *get_singleton() { static GDExtensionManager x; return &x; }
    void deinitialize_extensions(int) { events.push_back("extensions"); }
};
constexpr int MODULE_INITIALIZATION_LEVEL_SERVERS = 1;
void uninitialize_modules(int) { events.push_back("modules"); }
void unregister_server_types() { events.push_back("types"); }
#define ERR_PRINT(m) events.push_back("error")
#define memdelete(x) events.push_back("delete:" #x)
Error cleanup(Error err) {
"""
        suffix = r"""
    return OK;
}
int main() {
    if (cleanup(FAIL) != FAIL || events != std::vector<std::string>EXPECTED) return 1;
    events.clear();
    display_server = new DisplayServer;
    if (cleanup(OK) != OK || !events.empty()) return 2;
    delete display_server;
    return 0;
}
"""
        base = ["error", "display", "nav2", "nav3", "extensions",
                "modules", "types", "delete:input", "delete:tsman", "phys3", "phys2"]
        cases = (
            (),
            ("NAVIGATION_2D_DISABLED",),
            ("NAVIGATION_3D_DISABLED",),
            ("NAVIGATION_2D_DISABLED", "NAVIGATION_3D_DISABLED",
             "PHYSICS_2D_DISABLED", "PHYSICS_3D_DISABLED"),
        )
        for defines in cases:
            with self.subTest(defines=defines), tempfile.TemporaryDirectory() as folder:
                expected = list(base)
                if "NAVIGATION_2D_DISABLED" in defines:
                    expected.remove("nav2")
                if "NAVIGATION_3D_DISABLED" in defines:
                    expected.remove("nav3")
                if "PHYSICS_2D_DISABLED" in defines:
                    expected.remove("phys2")
                if "PHYSICS_3D_DISABLED" in defines:
                    expected.remove("phys3")
                literal = "{" + ", ".join(json.dumps(x) for x in expected) + "}"
                cpp = prefix + self.branch + suffix.replace("EXPECTED", literal)
                executable = str(Path(folder) / "probe")
                compiler = subprocess.run(
                    ["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                     *("-D" + flag for flag in defines),
                     "-x", "c++", "-", "-o", executable],
                    input=cpp, text=True, capture_output=True, check=False,
                )
                self.assertEqual(compiler.returncode, 0, compiler.stderr)
                execution = subprocess.run([executable], text=True, capture_output=True, check=False)
                self.assertEqual(execution.returncode, 0, execution.stdout + execution.stderr)


class BasisFlagsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "modules/basis_universal/SCsub").read_text(encoding="utf-8")
        anchor = cls.source.index("# Godot source files")
        begin = cls.source.index('if not env.msvc or env.get("use_llvm", False):', anchor)
        end = cls.source.index("module_obj = []", begin)
        cls.rule = cls.source[begin:end]

    def _apply(self, msvc, llvm):
        class Environment:
            def __init__(self):
                self.msvc = msvc
                self.flags = []
            def get(self, key, default):
                return llvm if key == "use_llvm" else default
            def Append(self, CCFLAGS):
                self.flags.extend(CCFLAGS)
        env = Environment()
        exec(self.rule, {"env": env, "env_basisu": env})
        return env.flags

    def test_gcc(self):
        self.assertEqual(self._apply(False, False), ["-Wno-unused-value"])

    def test_clang(self):
        self.assertEqual(self._apply(False, True), ["-Wno-unused-value"])

    def test_msvc(self):
        self.assertEqual(self._apply(True, False), [])

    def test_clang_cl(self):
        self.assertEqual(self._apply(True, True), ["-Wno-unused-value"])

    def test_only_glue_flags_and_no_duplicate(self):
        self.assertEqual(self.source.count('env_basisu.Append(CCFLAGS=["-Wno-unused-value"])'), 1)
        self.assertLess(self.source.index("env.modules_sources += thirdparty_obj"),
                        self.source.index(self.rule.strip()))
        self.assertLess(self.source.index(self.rule.strip()),
                        self.source.index('env_basisu.add_source_files(module_obj, "*.cpp")'))

    def test_thirdparty_warnings_policy_unchanged(self):
        self.assertIn("env_thirdparty.disable_warnings()", self.source)


class StatusIndicatorDocsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.xml = ElementTree.parse(ROOT / "doc/classes/StatusIndicator.xml").getroot()
        cls.description = cls.xml.findtext("description") or ""
        cls.brief = cls.xml.findtext("brief_description") or ""

    def test_class_name(self):
        self.assertEqual(self.xml.get("name"), "StatusIndicator")

    def test_tray_visibility_explained(self):
        self.assertIn("system tray when visible", self.description)

    def test_icon_tooltip_and_menu_explained(self):
        for feature in ("icon", "tooltip", "custom menu"):
            self.assertIn(feature, self.description)

    def test_platform_note_in_detailed_description(self):
        self.assertIn("macOS and Windows", self.description)
        self.assertNotIn("macOS and Windows", self.brief)

    def test_documented_members_exist(self):
        members = {m.get("name") for m in self.xml.findall("./members/member")}
        self.assertTrue({"icon", "tooltip", "menu", "visible"} <= members)


if __name__ == "__main__":
    unittest.main()
