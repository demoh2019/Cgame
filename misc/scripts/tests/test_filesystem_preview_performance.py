#!/usr/bin/env python3
"""Regression tests for filesystem dock thumbnail performance (Godot #124138).

Checks that collapsed folders defer preview generation, duplicate requests
are suppressed, and thumbnails are batched for one UI update. Compiles the
actual TreeItem visibility helper from Cgame against a minimal C++ mock.
A real editor GUI stress test is still required to measure frame-time savings.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CPP = ROOT / "editor/docks/filesystem_dock.cpp"
HEADER = ROOT / "editor/docks/filesystem_dock.h"


def method(text: str, signature: str) -> str:
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    raise AssertionError("Unbalanced function " + signature)


class FileSystemPreviewPerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")

    def test_collapsed_directories_do_not_request_file_previews(self):
        source = self.cpp
        flag = "const bool files_shown = _is_tree_item_expanded(subdirectory_item);"
        request = "if (files_shown) {\n\t\t\t\t_queue_tree_item_preview(file_item, file_metadata);\n\t\t\t}"
        self.assertIn(flag, source)
        self.assertIn(request, source)
        self.assertLess(source.index(flag), source.index(request))
        self.assertIn("!favorites_item->is_collapsed()", source)

    def test_deduplicates_queued_preview_requests(self):
        body = method(self.cpp, "void FileSystemDock::_queue_tree_item_preview(")
        self.assertIn("tree_preview_requested.has(id)", body)
        self.assertIn("tree_preview_requested.insert(id);", body)
        self.assertEqual(body.count("queue_resource_preview("), 1)
        self.assertLess(body.index("tree_preview_requested.has(id)"),
                        body.index("tree_preview_requested.insert(id);"))
        self.assertLess(body.index("tree_preview_requested.insert(id);"),
                        body.index("queue_resource_preview("))

    def test_batches_thumbnail_updates_into_internal_process(self):
        callback = method(self.cpp, "void FileSystemDock::_tree_thumbnail_done(")
        update = method(self.cpp, "void FileSystemDock::_apply_pending_tree_thumbnails()")
        self.assertIn("tree_update_id != p_update_id", callback)
        self.assertIn("p_small_preview.is_null()", callback)
        self.assertIn("pending_tree_thumbnails.push_back(", callback)
        self.assertIn("set_process_internal(true);", callback)
        self.assertNotIn("set_icon(", callback)
        self.assertIn("item->set_icon(", update)
        self.assertIn("pending_tree_thumbnails.clear();", update)
        self.assertIn("set_process_internal(false);", update)
        self.assertIn("case NOTIFICATION_INTERNAL_PROCESS:", self.cpp)
        self.assertIn("_apply_pending_tree_thumbnails();", self.cpp)

    def test_tree_rebuild_resets_request_and_pending_queues(self):
        rebuilt = method(self.cpp, "void FileSystemDock::_update_tree(")
        self.assertIn("tree_preview_requested.clear();", rebuilt)
        self.assertIn("pending_tree_thumbnails.clear();", rebuilt)
        self.assertIn("LocalVector<PendingTreeThumbnail> pending_tree_thumbnails;", self.header)
        self.assertIn("HashSet<ObjectID> tree_preview_requested;", self.header)

    def test_expanding_tree_schedules_only_visible_descendants(self):
        children = method(self.cpp, "void FileSystemDock::_queue_tree_children_previews(")
        changed = method(self.cpp, "void FileSystemDock::_tree_item_collapsed(")
        self.assertIn('!path.ends_with("/")', children)
        self.assertIn("!child->is_collapsed()", children)
        self.assertIn("_queue_tree_item_preview(child, path);", children)
        self.assertIn("_queue_tree_children_previews(child);", children)
        self.assertIn("if (!_is_tree_item_expanded(p_item))", changed)
        self.assertIn("_queue_tree_children_previews(p_item);", changed)
        self.assertIn('tree->connect("item_collapsed"', self.cpp)

    def test_compile_actual_visibility_helper_with_collapsed_ancestors(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if not compiler:
            self.skipTest("No C++ compiler installed")
        helper = method(self.cpp, "bool FileSystemDock::_is_tree_item_expanded(")
        test = r'''
#include <cassert>
struct TreeItem {
    bool collapsed = false;
    TreeItem *parent = nullptr;
    TreeItem *get_parent() { return parent; }
    bool is_collapsed() const { return collapsed; }
};
class FileSystemDock {
public:
    static bool _is_tree_item_expanded(TreeItem *p_item);
};
''' + helper + r'''
int main() {
    TreeItem root, folder, nested, file;
    folder.parent = &root;
    nested.parent = &folder;
    file.parent = &nested;
    assert(FileSystemDock::_is_tree_item_expanded(&file));
    nested.collapsed = true;
    assert(!FileSystemDock::_is_tree_item_expanded(&file));
    assert(FileSystemDock::_is_tree_item_expanded(&folder));
    nested.collapsed = false;
    folder.collapsed = true;
    assert(!FileSystemDock::_is_tree_item_expanded(&file));
    folder.collapsed = false;
    root.collapsed = true;
    assert(!FileSystemDock::_is_tree_item_expanded(&file));
    root.collapsed = false;
    assert(FileSystemDock::_is_tree_item_expanded(&file));
    assert(FileSystemDock::_is_tree_item_expanded(nullptr));
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "case.cpp"
            binary = Path(tmp) / "case"
            src.write_text(test, encoding="utf-8")
            build = subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                 str(src), "-o", str(binary)],
                capture_output=True, text=True, timeout=35, check=False,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary)], capture_output=True,
                                 text=True, timeout=10, check=False)
            self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == "__main__":
    unittest.main()
