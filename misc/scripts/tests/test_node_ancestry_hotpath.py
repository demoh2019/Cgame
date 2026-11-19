#!/usr/bin/env python3
"""Source and executable checks for fast, allocation-free node ancestry."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def function(name):
    source = (ROOT / "scene/main/node.cpp").read_text()
    pos = source.index(name)
    start = source.index("{", pos)
    depth = 0
    for end in range(start, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                return source[pos:end + 1]
    raise AssertionError("Unbalanced C++ method " + name)


class NodeFastPaths(unittest.TestCase):
    def test_no_temp_hashset_and_preallocated_path(self):
        path = function("NodePath Node::get_path_to(")
        common = function("Node *Node::find_common_parent_with(")
        self.assertNotIn("HashSet", path + common)
        self.assertIn("path.resize(this_branch_depth + other_branch_depth)", path)
        self.assertIn("ERR_FAIL_NULL_V_MSG(common_parent", path)
        self.assertIn("path.reverse()", path)
        self.assertIn("if (!p_node)", common)
        self.assertIn("return const_cast<Node *>(left)", common)

    def test_depth_uses_cache_for_attached_nodes(self):
        depth = function("uint32_t Node::calculate_depth() const")
        self.assertIn("if (is_inside_tree())", depth)
        self.assertIn("return data.depth;", depth)
        self.assertIn("iter = iter->data.parent;", depth)

    def test_actual_ancestry_methods_compile_and_match_reference(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if compiler is None:
            self.skipTest("C++ compiler unavailable")
        header = """
#include <array>
#include <cassert>
#include <cstdint>
class Node {
public:
    struct Data {
        const Node *parent = nullptr;
        uint32_t depth = 0;
        bool inside_tree = false;
    } data;
    bool is_inside_tree() const { return data.inside_tree; }
    uint32_t calculate_depth() const;
    Node *find_common_parent_with(const Node *p_node) const;
};
"""
        main = """
static Node *naive(const Node *a, const Node *b) {
    for (const Node *i = a; i; i = i->data.parent)
        for (const Node *j = b; j; j = j->data.parent)
            if (i == j) return const_cast<Node *>(i);
    return nullptr;
}
int main() {
    std::array<Node, 512> nodes{};
    for (int i = 0; i < 512; ++i) {
        int root = (i < 256) ? 0 : 256;
        nodes[i].data.inside_tree = (root == 0);
        if (i != root) {
            nodes[i].data.parent = &nodes[root + (i - root - 1) / 2];
            nodes[i].data.depth = nodes[i].data.parent->data.depth + 1;
        } else {
            nodes[i].data.depth = 1;
        }
    }
    for (int i = 0; i < 512; ++i) {
        assert(nodes[i].calculate_depth() == nodes[i].data.depth);
        assert(nodes[i].find_common_parent_with(nullptr) == nullptr);
        for (int j = 0; j < 512; ++j)
            assert(nodes[i].find_common_parent_with(&nodes[j]) == naive(&nodes[i], &nodes[j]));
    }
    std::array<Node, 1025> chain{};
    chain[0].data.depth = 1;
    for (int i = 1; i < 1025; ++i)
        chain[i].data.parent = &chain[i - 1];
    assert(chain.back().calculate_depth() == 1025);
    assert(chain.back().find_common_parent_with(&chain.front()) == &chain.front());
}
"""
        program = header + function("uint32_t Node::calculate_depth() const") + "\n" + function("Node *Node::find_common_parent_with(") + "\n" + main
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "node.cpp"
            exe = Path(tmp) / "node"
            src.write_text(program)
            build = subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", str(src), "-o", str(exe)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == "__main__":
    unittest.main()
