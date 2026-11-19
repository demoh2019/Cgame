#!/usr/bin/env python3
"""FBX neutral-bone backport regressions for Godot #125492.

The C++ harness extracts and compiles the REAL vertex skin-weight loop from
fbx_document.cpp against small input structures; source lifecycle checks
verify neutral bone insertion. This is not a full FBX import runtime test.
"""

from __future__ import annotations

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "modules/fbx/fbx_document.cpp"
HEADER = ROOT / "modules/fbx/fbx_document.h"


def body_at(source: str, signature: str) -> str:
    start = source.index(signature)
    first = source.index("{", start)
    depth = 0
    for offset in range(first, len(source)):
        if source[offset] == "{":
            depth += 1
        elif source[offset] == "}":
            depth -= 1
            if depth == 0:
                return source[first:offset + 1]
    raise AssertionError("C++ block has unbalanced braces: " + signature)


class FBXNeutralBoneContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = SOURCE.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.insert = body_at(cls.cpp, "Error FBXDocument::_add_neutral_bones(")
        cls.parse = body_at(cls.cpp, "Error FBXDocument::_parse_fbx_state(")
        cls.meshes = body_at(cls.cpp, "Error FBXDocument::_parse_meshes(")

    def test_declares_neutral_bone_helper(self):
        self.assertIn("Error _add_neutral_bones(Ref<FBXState> p_state);", self.header)

    def test_run_neutral_bone_setup_after_skeleton_detection_before_creation(self):
        stage = self.parse
        self.assertLess(stage.index("SkinTool::_determine_skeletons("), stage.index("_add_neutral_bones(p_state);"))
        self.assertLess(stage.index("_add_neutral_bones(p_state);"), stage.index("SkinTool::_create_skeletons("))

    def test_neutral_bone_setup_propagates_errors(self):
        stage = self.parse
        start = stage.index("_add_neutral_bones(p_state);")
        self.assertIn("ERR_FAIL_COND_V(err != OK, ERR_PARSE_ERROR);", stage[start:start + 145])

    def test_skips_unimported_skins(self):
        self.assertIn("if (skin_i < 0)", self.insert)
        self.assertIn("continue;", self.insert)

    def test_skips_skins_without_unweighted_vertices(self):
        self.assertIn("if (!needs_neutral_bone)", self.insert)
        self.assertIn("continue;", self.insert)

    def test_reuses_neutral_bone_per_skeleton(self):
        self.assertIn("HashMap<GLTFSkeletonIndex, GLTFNodeIndex> neutral_bones;", self.insert)
        self.assertIn("neutral_bones.has(skin->skeleton)", self.insert)
        self.assertIn("neutral_bones.insert(skin->skeleton, neutral_node_i);", self.insert)

    def test_neutral_bone_is_unanimated_and_attached_to_skeleton(self):
        for required in (
            'neutral_node->set_name("NeutralBone");',
            "neutral_node->joint = true;",
            'neutral_node->set_additional_data("GODOT_rest_transform", Transform3D());',
            "skeleton->joints.push_back(neutral_node_i);",
            "skeleton->roots.push_back(neutral_node_i);",
            "skin->joints.push_back(neutral_node_i);",
        ):
            with self.subTest(required=required):
                self.assertIn(required, self.insert)

    def test_computes_bind_transform_in_parent_space(self):
        self.assertIn("while (parent_i >= 0)", self.insert)
        self.assertIn("skeleton_to_world.affine_inverse() * _as_xform(geometry_to_world)", self.insert)
        self.assertIn("skin->inverse_binds.push_back(neutral_bind);", self.insert)

    def test_expands_and_verifies_modified_skin(self):
        self.assertIn("SkinTool::_expand_skin(p_state->nodes, skin)", self.insert)
        self.assertIn("SkinTool::_verify_skin(p_state->nodes, skin)", self.insert)

    def test_no_neutral_bone_for_skins_without_clusters(self):
        # Earlier _parse_skins excludes these deformers from skin_indices.
        prior = body_at(self.cpp, "Error FBXDocument::_parse_skins(")
        self.assertIn("fbx_skin->clusters.count == 0 || fbx_skin->weights.count == 0", prior)
        self.assertIn("p_state->skin_indices.push_back(-1);", prior)

    @unittest.skipUnless(shutil.which(os.environ.get("CXX", "c++")), "C++ compiler unavailable")
    def test_compiled_importer_weight_loop_keeps_unweighted_vertices(self):
        # Compile the actual production loop so a mutation of the importer
        # changes behavior. Include four- and eight-weight skinning scenarios.
        start = self.meshes.index("for (int32_t vertex_i = 0; vertex_i < vertex_num; vertex_i++) {")
        loop = body_at(self.meshes[start:], "for (int32_t vertex_i = 0; vertex_i < vertex_num; vertex_i++)")
        prelude = r"""
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>
#define MIN(a, b) std::min((a), (b))
template <typename T> struct Vector {
    std::vector<T> write;
    void resize(size_t n) { write.resize(n); }
};
struct ufbx_skin_vertex {
    uint32_t num_weights;
    uint32_t weight_begin;
};
struct ufbx_skin_weight {
    uint32_t cluster_index;
    double weight;
};
struct ufbx_skin_deformer {
    std::vector<ufbx_skin_vertex> vertices;
    std::vector<ufbx_skin_weight> weights;
    struct { int count; } clusters;
    int max_weights_per_vertex;
};
struct UfbxMesh {
    std::vector<uint32_t> vertex_indices;
};
int run_case(int max_weights) {
    ufbx_skin_deformer skin {
        {{0,0}, {2,0}, {1,2}, {2,3}, {1,5}},
        {{0,1.0}, {1,3.0}, {2,0.0}, {0,0.0}, {1,0.0}, {2,NAN}},
        {3}, max_weights
    };
    ufbx_skin_deformer *fbx_skin = &skin;
    UfbxMesh mesh {{0,1,2,3,4}};
    UfbxMesh *fbx_mesh = &mesh;
    std::vector<uint32_t> indices {0,1,2,3,4};
    int32_t vertex_num = 5;
    int32_t num_skin_weights = max_weights > 4 ? 8 : 4;
    Vector<int32_t> bones;
    Vector<float> weights;
    bones.resize(vertex_num * num_skin_weights);
    weights.resize(vertex_num * num_skin_weights);
"""
        checks = r"""
    // Four vertices have zero, zero-sum, or non-finite weights.
    for (int v : {0,2,3,4}) {
        const int offset = v * num_skin_weights;
        if (bones.write[offset] != skin.clusters.count ||
            weights.write[offset] != 1.0f) return 1;
        for (int k = 1; k < num_skin_weights; ++k) {
            if (weights.write[offset + k] != 0.0f) return 2;
        }
    }
    // Positive weights remain normalized and keep their bone indices.
    const int offset = num_skin_weights;
    if (bones.write[offset] != 0 || bones.write[offset + 1] != 1) return 3;
    if (std::abs(weights.write[offset] - 0.25f) > 0.00001f ||
        std::abs(weights.write[offset + 1] - 0.75f) > 0.00001f) return 4;
    for (int k = 2; k < num_skin_weights; ++k) {
        if (weights.write[offset + k] != 0.0f) return 5;
    }
    return 0;
}
int main() {
    if (run_case(4) != 0) return 6;
    if (run_case(8) != 0) return 7;
    std::cout << "4/8 skinning cases passed\n";
}
"""
        with tempfile.TemporaryDirectory() as temp:
            cpp = Path(temp) / "fbx_neutral_weight.cpp"
            binary = Path(temp) / "fbx_neutral_weight"
            cpp.write_text(prelude + loop + checks, encoding="utf-8")
            compiled = subprocess.run(
                [os.environ.get("CXX", "c++"), "-std=c++17", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(binary)],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            executed = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
            self.assertEqual(executed.returncode, 0, executed.stderr)
            self.assertIn("4/8 skinning cases passed", executed.stdout)


if __name__ == "__main__":
    unittest.main()
