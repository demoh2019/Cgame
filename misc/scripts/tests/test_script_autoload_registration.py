#!/usr/bin/env python3
"""Native regression for Godot upstream #125567 (--script autoload names).

Compiles the actual early-registration block from Main::start() against
small ScriptServer/ProjectSettings test doubles.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "main/main.cpp"
START = "\tif (!script.is_empty()) {\n\t\t// Register autoload names before the script loads"


def extract_block():
    content = SOURCE.read_text(encoding="utf-8")
    start = content.find(START)
    if start == -1:
        raise AssertionError("early autoload registration block not found")
    end = content.find("\n\t}\n#endif", start)
    if end == -1:
        raise AssertionError("registration block end not found")
    return content[start : end + 3]


HARNESS = r"""
#include <algorithm>
#include <cassert>
#include <string>
#include <vector>

using StringName = std::string;
struct Variant {};

template <class K, class V> struct KeyValue {
    K key;
    V value;
};
template <class K, class V>
using HashMap = std::vector<KeyValue<K, V>>;

struct FakeScript {
    bool empty = true;
    bool is_empty() const { return empty; }
};
FakeScript script;

struct ProjectSettings {
    struct AutoloadInfo {
        StringName name;
        bool is_singleton;
    };
    bool loaded = false;
    HashMap<StringName, AutoloadInfo> autoloads;

    static ProjectSettings *get_singleton() {
        static ProjectSettings singleton;
        return &singleton;
    }
    bool is_project_loaded() const { return loaded; }
    const HashMap<StringName, AutoloadInfo> &get_autoload_list() const { return autoloads; }
};

struct FakeLanguage {
    std::vector<StringName> registered;
    void add_global_constant(const StringName &name, Variant) {
        registered.push_back(name);
    }
};

struct ScriptServer {
    static std::vector<FakeLanguage> languages;
    static int get_language_count() {
        return static_cast<int>(languages.size());
    }
    static FakeLanguage *get_language(int index) {
        return &languages[index];
    }
};
std::vector<FakeLanguage> ScriptServer::languages;

void register_script_autoloads() {
__BLOCK__
}

bool contains(const FakeLanguage &language, const StringName &name) {
    return std::find(language.registered.begin(), language.registered.end(), name)
        != language.registered.end();
}

int main() {
    auto *settings = ProjectSettings::get_singleton();
    settings->autoloads = {
        {"SceneOnly", {"SceneOnly", false}},
        {"SaveManager", {"SaveManager", true}},
        {"GameState", {"GameState", true}},
    };

    // No command-line script: do not register anything.
    script.empty = true;
    settings->loaded = true;
    ScriptServer::languages.resize(2);
    register_script_autoloads();
    assert(ScriptServer::languages[0].registered.empty());
    assert(ScriptServer::languages[1].registered.empty());

    // A command-line script without a loaded project is also a no-op.
    script.empty = false;
    settings->loaded = false;
    register_script_autoloads();
    assert(ScriptServer::languages[0].registered.empty());

    // Each singleton is registered once per language, but scene-only
    // autoloads are not exposed as script global constants.
    settings->loaded = true;
    register_script_autoloads();
    for (const FakeLanguage &language : ScriptServer::languages) {
        assert(language.registered.size() == 2);
        assert(contains(language, "SaveManager"));
        assert(contains(language, "GameState"));
        assert(!contains(language, "SceneOnly"));
    }

    // Empty autoload registry and zero languages must be harmless.
    for (auto &language : ScriptServer::languages) {
        language.registered.clear();
    }
    settings->autoloads.clear();
    register_script_autoloads();
    assert(ScriptServer::languages[0].registered.empty());

    settings->autoloads.push_back({"SaveManager", {"SaveManager", true}});
    ScriptServer::languages.clear();
    register_script_autoloads();
}
"""


class ScriptAutoloadRegistrationTests(unittest.TestCase):
    def test_registration_occurs_before_script_resource_load(self):
        source = SOURCE.read_text(encoding="utf-8")
        block = extract_block()
        self.assertLess(source.index(START), source.index("Ref<Script> script_res = ResourceLoader::load(script);"))
        self.assertIn("ProjectSettings::get_singleton()->is_project_loaded()", block)
        self.assertIn("ScriptServer::get_language_count()", block)
        self.assertIn("info.is_singleton", block)
        self.assertIn("add_global_constant(info.name, Variant())", block)

    def test_cpp_block_handles_script_project_singleton_matrix(self):
        compiler = os.environ.get("CXX", "c++")
        if not shutil.which(compiler):
            self.skipTest(f"compiler {compiler} missing")
        source = HARNESS.replace("__BLOCK__", extract_block())
        with tempfile.TemporaryDirectory(prefix="autoload-regression-") as dirname:
            binary = Path(dirname) / "autoloads"
            compiled = subprocess.run(
                [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                 "-x", "c++", "-", "-o", str(binary)],
                input=source, text=True, capture_output=True, check=False,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            ran = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
            self.assertEqual(ran.returncode, 0, ran.stderr)


if __name__ == "__main__":
    unittest.main()
