#!/usr/bin/env python3
"""Regression tests for upstream Godot PR #125621.

Compile the real uninitialize_gdscript_module() body against small lifecycle
test doubles. Verify that parser cleanup happens at the same initialization
stage as registration, without requiring a full Godot editor build.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "modules/gdscript/register_types.cpp"


def get_function(name):
    source = SOURCE.read_text(encoding="utf-8")
    match = re.search(r"\bvoid\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", source)
    if not match:
        raise AssertionError(f"{name} not found")
    end = source.find("\n}\n", match.start())
    if end == -1:
        raise AssertionError(f"{name} end not found")
    return source[match.start() : end + 2]


HARNESS = r"""
#include <algorithm>
#include <cassert>
#include <string>
#include <vector>

std::vector<std::string> events;
bool happened(const std::string &name) {
    return std::find(events.begin(), events.end(), name) != events.end();
}
int occurrences(const std::string &name) {
    return static_cast<int>(std::count(events.begin(), events.end(), name));
}
int position(const std::string &name) {
    return static_cast<int>(std::find(events.begin(), events.end(), name) - events.begin());
}

enum ModuleInitializationLevel {
    MODULE_INITIALIZATION_LEVEL_CORE,
    MODULE_INITIALIZATION_LEVEL_SERVERS,
    MODULE_INITIALIZATION_LEVEL_EDITOR
};

template <typename T> void memdelete(T *ptr) { delete ptr; }

struct GDScriptCache {
    ~GDScriptCache() { events.push_back("cache-free"); }
};
struct GDScriptLanguage {
    ~GDScriptLanguage() { events.push_back("language-free"); }
};
GDScriptCache *gdscript_cache = new GDScriptCache;
GDScriptLanguage *script_language_gd = new GDScriptLanguage;

struct FakeRef {
    std::string label;
    explicit FakeRef(const std::string &p_label) : label(p_label) {}
    void unref() { events.push_back(label + "-unref"); }
};
FakeRef resource_loader_gd("loader");
FakeRef resource_saver_gd("saver");
FakeRef gdscript_translation_parser_plugin("parser");

struct ScriptServer {
    static void unregister_language(GDScriptLanguage *) {
        events.push_back("language-unregister");
    }
};
struct ResourceLoader {
    static void remove_resource_format_loader(FakeRef &) {
        events.push_back("loader-remove");
    }
};
struct ResourceSaver {
    static void remove_resource_format_saver(FakeRef &) {
        events.push_back("saver-remove");
    }
};
struct GDScriptParser {
    static void cleanup() { events.push_back("parser-cleanup"); }
};
struct GDScriptUtilityFunctions {
    static void unregister_functions() { events.push_back("utility-unregister"); }
};
struct EditorTranslationParser {
    enum { STANDARD };
    static EditorTranslationParser *get_singleton() {
        static EditorTranslationParser singleton;
        return &singleton;
    }
    void remove_parser(FakeRef &, int) {
        events.push_back("translation-parser-remove");
    }
};
struct GDScriptLanguageProtocol {
    static GDScriptLanguageProtocol *get_singleton() {
        static GDScriptLanguageProtocol *singleton = new GDScriptLanguageProtocol;
        return singleton;
    }
    ~GDScriptLanguageProtocol() { events.push_back("lsp-free"); }
};
struct GDScriptEditorLanguage {
    static GDScriptEditorLanguage *get_singleton() {
        static GDScriptEditorLanguage *singleton = new GDScriptEditorLanguage;
        return singleton;
    }
    ~GDScriptEditorLanguage() { events.push_back("editor-language-free"); }
};

__FUNCTION__

int main() {
    uninitialize_gdscript_module(MODULE_INITIALIZATION_LEVEL_CORE);
    assert(events.empty());

    uninitialize_gdscript_module(MODULE_INITIALIZATION_LEVEL_EDITOR);
#ifdef TOOLS_ENABLED
    assert(occurrences("editor-language-free") == 1);
#ifndef GDSCRIPT_NO_LSP
    assert(occurrences("lsp-free") == 1);
#else
    assert(occurrences("lsp-free") == 0);
#endif
#else
    assert(events.empty());
#endif
    assert(occurrences("translation-parser-remove") == 0);
    assert(occurrences("parser-unref") == 0);
    assert(occurrences("language-unregister") == 0);

    events.clear();
    uninitialize_gdscript_module(MODULE_INITIALIZATION_LEVEL_SERVERS);
    assert(occurrences("language-unregister") == 1);
    assert(occurrences("cache-free") == 1);
    assert(occurrences("language-free") == 1);
    assert(occurrences("loader-remove") == 1);
    assert(occurrences("loader-unref") == 1);
    assert(occurrences("saver-remove") == 1);
    assert(occurrences("saver-unref") == 1);
    assert(occurrences("parser-cleanup") == 1);
    assert(occurrences("utility-unregister") == 1);
#ifdef TOOLS_ENABLED
    assert(occurrences("translation-parser-remove") == 1);
    assert(occurrences("parser-unref") == 1);
    assert(position("translation-parser-remove") < position("parser-unref"));
#else
    assert(occurrences("translation-parser-remove") == 0);
    assert(occurrences("parser-unref") == 0);
#endif
    return 0;
}
"""


class GDScriptModuleTeardown(unittest.TestCase):
    def test_parser_registration_and_unregistration_share_servers_stage(self):
        source = get_function("initialize_gdscript_module")
        self.assertIn("EditorTranslationParser::get_singleton()->add_parser", source)
        self.assertRegex(
            source,
            r"if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\) \{"
            r"[\s\S]*?EditorTranslationParser::get_singleton\(\)->add_parser",
        )
        shutdown = get_function("uninitialize_gdscript_module")
        self.assertRegex(
            shutdown,
            r"if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\) \{"
            r"[\s\S]*?EditorTranslationParser::get_singleton\(\)->remove_parser",
        )

    def test_cleanup_isolated_from_editor_lsp_shutdown(self):
        shutdown = get_function("uninitialize_gdscript_module")
        self.assertIn("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", shutdown)
        pos_parser = shutdown.index("EditorTranslationParser::get_singleton()->remove_parser")
        pos_editor = shutdown.index("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {")
        pos_lsp = shutdown.index("memdelete(GDScriptLanguageProtocol::get_singleton())")
        self.assertLess(pos_parser, pos_editor)
        self.assertLess(pos_editor, pos_lsp)

    def test_compiled_lifecycle_matrix(self):
        compiler = os.environ.get("CXX", "c++")
        if not shutil.which(compiler):
            self.skipTest(f"{compiler} not installed")
        code = HARNESS.replace("__FUNCTION__", get_function("uninitialize_gdscript_module"))
        configurations = [
            ("runtime-only", []),
            ("editor-with-lsp", ["-DTOOLS_ENABLED"]),
            ("editor-without-lsp", ["-DTOOLS_ENABLED", "-DGDSCRIPT_NO_LSP"]),
        ]
        with tempfile.TemporaryDirectory(prefix="gdscript-lifecycle-test-") as temp:
            for label, macros in configurations:
                with self.subTest(mode=label):
                    binary = Path(temp) / label
                    compiled = subprocess.run(
                        [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                         *macros, "-x", "c++", "-", "-o", str(binary)],
                        input=code, text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(compiled.returncode, 0, compiled.stderr)
                    executed = subprocess.run(
                        [str(binary)], text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(executed.returncode, 0, executed.stderr)


if __name__ == "__main__":
    unittest.main()
