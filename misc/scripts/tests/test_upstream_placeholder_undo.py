#!/usr/bin/env python3
"""Backport #125575: extract actual scene tree toggle and run a C++ UndoRedo harness."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("GODOT_BACKPORT_ROOT", Path(__file__).resolve().parents[3]))
SOURCE = ROOT / "editor/docks/scene_tree_dock.cpp"


def extract_cpp_function(source: str, signature: str) -> str:
    assert source.count(signature) == 1
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise ValueError("Missing method closing brace")


STUB = r'''
#include <cassert>
#include <iostream>
#include <string>
#include <vector>
#include <functional>
#include <algorithm>

template<class T> using List = std::vector<T>;
struct Node {
    bool placeholder = false;
    void set_scene_instance_load_placeholder(bool value) { placeholder = value; }
};
struct SceneTreeView { int refreshes = 0; void update_tree() { ++refreshes; } };
struct EditorSelection {
    List<Node *> selected;
    List<Node *> get_full_selected_node_list() { return selected; }
};
struct UndoRedo { enum { MERGE_DISABLE = 1 }; };
static const char *TTR(const char *text) { return text; }
struct EditorUndoRedoManager {
    struct Action {
        std::vector<std::function<void()>> do_methods;
        std::vector<std::function<void()>> undo_methods;
    } current;
    std::vector<Action> history;
    int create_calls = 0;
    int commit_calls = 0;
    int explicit_context_calls = 0;
    bool open = false;
    int nesting = 0;
    static EditorUndoRedoManager *get_singleton() { static EditorUndoRedoManager instance; return &instance; }
    void reset() { current = Action(); history.clear(); create_calls = 0; commit_calls = 0; explicit_context_calls = 0; open = false; nesting = 0; }
    void create_action(const char *, int merge = 0, Node *context = nullptr) {
        (void)merge;
        ++create_calls;
        if (context) ++explicit_context_calls;
        if (!open) { current = Action(); open = true; }
        ++nesting;
    }
    void add_do_method(Node *node, const char *, bool value) {
        current.do_methods.emplace_back([node, value] { node->set_scene_instance_load_placeholder(value); });
    }
    void add_undo_method(Node *node, const char *, bool value) {
        current.undo_methods.emplace_back([node, value] { node->set_scene_instance_load_placeholder(value); });
    }
    void add_do_method(SceneTreeView *tree, const char *) {
        current.do_methods.emplace_back([tree] { tree->update_tree(); });
    }
    void add_undo_method(SceneTreeView *tree, const char *) {
        current.undo_methods.emplace_back([tree] { tree->update_tree(); });
    }
    void commit_action() {
        ++commit_calls;
        if (!open) { return; }
        --nesting;
        if (nesting > 0) return;
        for (const auto &call : current.do_methods) call();
        history.push_back(current);
        current = Action();
        open = false;
    }
    void undo_last() {
        assert(!history.empty());
        auto action = history.back();
        history.pop_back();
        for (auto it = action.undo_methods.rbegin(); it != action.undo_methods.rend(); ++it) (*it)();
    }
};
struct SceneTreeDock {
    enum ItemCheckState { STATE_CHECKED, STATE_UNCHECKED, STATE_INDETERMINATE };
    EditorSelection *editor_selection = nullptr;
    SceneTreeView *scene_tree = nullptr;
    Node *edited_scene = nullptr;
    int editable_calls = 0;
    ItemCheckState _is_placeholder(const List<Node *> &selection) {
        bool any = false, all = true;
        for (Node *node : selection) {
            if (node) { any = any || node->placeholder; all = all && node->placeholder; }
        }
        return all ? STATE_CHECKED : (any ? STATE_INDETERMINATE : STATE_UNCHECKED);
    }
    void _toggle_editable_children(List<Node *> &selection, ItemCheckState state) {
        (void)selection; (void)state;
        ++editable_calls;
        // Reflect existing nested undo action in the engine. Real implementation
        // adds editable-child do/undo methods into this shared action context.
        auto *undo = EditorUndoRedoManager::get_singleton();
        undo->create_action("Toggle Editable Children");
        undo->add_do_method(scene_tree, "update_tree");
        undo->add_undo_method(scene_tree, "update_tree");
        undo->commit_action();
    }
    void _toggle_placeholder_from_selection();
};
'''

CHECKS = r'''
static int assertions = 0;
#define CHECK(value) do { if (!(value)) { std::cerr << "failed " #value << " at " << __LINE__ << "\n"; return 1; } ++assertions; } while(0)
int main() {
    Node root, a, b;
    SceneTreeView tree;
    EditorSelection selection;
    selection.selected = {&a, &b};
    SceneTreeDock dock;
    dock.edited_scene = &root;
    dock.editor_selection = &selection;
    dock.scene_tree = &tree;
    auto *undo = EditorUndoRedoManager::get_singleton();
    undo->reset();
    dock._toggle_placeholder_from_selection();
    CHECK(a.placeholder);
    CHECK(b.placeholder);
    CHECK(dock.editable_calls == 1);
    CHECK(undo->create_calls >= 1);
    CHECK(undo->explicit_context_calls == 1);
    CHECK(undo->commit_calls >= 1);
    CHECK(tree.refreshes >= 1);
    undo->undo_last();
    CHECK(!a.placeholder);
    CHECK(!b.placeholder);
    CHECK(tree.refreshes >= 2);

    // Undo of disabling placeholders must restore original flags.
    a.placeholder = true; b.placeholder = true;
    undo->reset();
    dock._toggle_placeholder_from_selection();
    CHECK(!a.placeholder);
    CHECK(!b.placeholder);
    CHECK(dock.editable_calls == 1);
    CHECK(undo->history.size() == 1);
    undo->undo_last();
    CHECK(a.placeholder);
    CHECK(b.placeholder);

    // Null node in an editor selection must not be dereferenced.
    undo->reset();
    selection.selected = {&a, nullptr};
    a.placeholder = true;
    dock._toggle_placeholder_from_selection();
    CHECK(!a.placeholder);
    undo->undo_last();
    CHECK(a.placeholder);
    std::cout << assertions << " placeholder assertions passed\n";
}
'''


def cpp_run(program: str) -> str:
    compiler = shutil.which("g++") or shutil.which("clang++") or shutil.which("c++")
    if not compiler:
        raise unittest.SkipTest("C++ compiler is unavailable")
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "test.cpp"
        executable = Path(temp) / "test"
        source.write_text(program, encoding="utf8")
        compile_result = subprocess.run([compiler, "-std=c++17", "-Werror", "-Wall", "-Wextra", str(source), "-o", str(executable)], capture_output=True, text=True)
        if compile_result.returncode:
            raise AssertionError(compile_result.stderr)
        run_result = subprocess.run([str(executable)], capture_output=True, text=True)
        if run_result.returncode:
            raise AssertionError(run_result.stdout + "\n" + run_result.stderr)
        return run_result.stdout


class PlaceholderUndoRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.full = SOURCE.read_text(encoding="utf8")
        cls.toggle = extract_cpp_function(cls.full, "void SceneTreeDock::_toggle_placeholder_from_selection()")
        cls.editable = extract_cpp_function(cls.full, "void SceneTreeDock::_toggle_editable_children(List<Node *> &p_nodes, ItemCheckState p_current_state)")
        cls.tool = extract_cpp_function(cls.full, "void SceneTreeDock::_tool_selected(")

    def test_toggle_records_explicit_scene_history(self):
        self.assertIn('undo_redo->create_action(TTR("Toggle Load as Placeholder"), UndoRedo::MERGE_DISABLE, edited_scene);', self.toggle)

    def test_toggle_records_state_and_inverse(self):
        self.assertIn('undo_redo->add_do_method(node, "set_scene_instance_load_placeholder", placeholder);', self.toggle)
        self.assertIn('undo_redo->add_undo_method(node, "set_scene_instance_load_placeholder", !placeholder);', self.toggle)

    def test_toggle_commits_one_action(self):
        self.assertEqual(self.toggle.count("undo_redo->commit_action();"), 1)
        self.assertNotIn("node->set_scene_instance_load_placeholder(placeholder);", self.toggle)

    def test_update_tree_on_do_and_undo(self):
        self.assertIn('undo_redo->add_do_method(scene_tree, "update_tree");', self.toggle)
        self.assertIn('undo_redo->add_undo_method(scene_tree, "update_tree");', self.toggle)

    def test_editor_menu_actions_are_undoable(self):
        self.assertIn('undo_redo->create_action(TTR("Toggle Load as Placeholder"));', self.tool)
        self.assertIn('undo_redo->add_do_method(node, "set_scene_instance_load_placeholder", !placeholder);', self.tool)
        self.assertIn('undo_redo->add_undo_method(node, "set_scene_instance_load_placeholder", placeholder);', self.tool)

    def test_editable_children_nested_actions_still_commit(self):
        self.assertIn('undo_redo->create_action(TTR("Toggle Editable Children"));', self.editable)
        self.assertIn("undo_redo->commit_action();", self.editable)

    def test_actual_toggle_cpp_with_undo_redo_mocks(self):
        self.assertIn("placeholder assertions passed", cpp_run(STUB + "\n" + self.toggle + "\n" + CHECKS))


if __name__ == "__main__":
    unittest.main()
