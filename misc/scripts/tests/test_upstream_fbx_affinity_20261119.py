#!/usr/bin/env python3
"""Source contracts for upstream #125230 and #125492.

Guards catch accidental partial backports during merges. Native OS/FBX tests
and an actual Godot build are still required for runtime validation.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class AffinityBackportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.linux_cpp = source("platform/linuxbsd/os_linuxbsd.cpp")
        cls.linux_h = source("platform/linuxbsd/os_linuxbsd.h")
        cls.nav2 = source("modules/navigation_2d/nav_map_2d.cpp")
        cls.nav3 = source("modules/navigation_3d/nav_map_3d.cpp")
        cls.basis = source("modules/basis_universal/image_compress_basisu.cpp")
        cls.raycast = source("modules/raycast/raycast_occlusion_cull.cpp")
        cls.render = source("servers/rendering/rendering_device.cpp")
        cls.docs = source("doc/classes/ProjectSettings.xml")
        cls.native = source("tests/core/os/test_os.cpp")

    def test_linux_affinity_api_includes_sched_header(self):
        self.assertIn("#include <sched.h>", self.linux_cpp)

    def test_linux_implementation_is_linux_only(self):
        self.assertRegex(self.linux_cpp, r"#ifdef __linux__\s+int OS_LinuxBSD::get_default_thread_pool_size\(\) const")

    def test_linux_header_declares_override(self):
        self.assertRegex(self.linux_h, r"#ifdef __linux__\s+virtual int get_default_thread_pool_size\(\) const override;")

    def test_linux_uses_process_affinity_mask(self):
        self.assertIn("sched_getaffinity(0, sizeof(cpu_set_t), &set)", self.linux_cpp)

    def test_linux_does_not_return_empty_affinity(self):
        self.assertRegex(self.linux_cpp, r"int count = CPU_COUNT\(&set\);\s+if \(count > 0\) \{\s+return count;")

    def test_linux_falls_back_to_os_processor_count(self):
        self.assertRegex(self.linux_cpp, r"int OS_LinuxBSD::get_default_thread_pool_size\(\) const \{[\s\S]*?return get_processor_count\(\);")

    def test_navigation_2d_limits_workers(self):
        self.assertIn("int thread_count = OS::get_singleton()->get_default_thread_pool_size();", self.nav2)
        self.assertIn("path_query_slots_max = thread_count;", self.nav2)
        self.assertIn("if (path_query_slots_max < 1)", self.nav2)

    def test_navigation_3d_limits_workers(self):
        self.assertIn("int thread_count = OS::get_singleton()->get_default_thread_pool_size();", self.nav3)
        self.assertIn("path_query_slots_max = thread_count;", self.nav3)
        self.assertIn("if (path_query_slots_max < 1)", self.nav3)

    def test_basisu_uses_default_threads(self):
        self.assertIn("basisu::job_pool job_pool(OS::get_singleton()->get_default_thread_pool_size());", self.basis)

    def test_raycast_reserves_two_worker_slots(self):
        self.assertIn("MAX(1, OS::get_singleton()->get_default_thread_pool_size() - 2)", self.raycast)

    def test_render_device_limits_transfer_workers(self):
        self.assertIn("transfer_worker_pool_max_size = OS::get_singleton()->get_default_thread_pool_size();", self.render)

    def test_docs_mention_allowed_processors(self):
        self.assertIn("maximum available or allowed OS processor count", self.docs)
        self.assertIn("CPU cores available (see [method OS.get_processor_count]) or allowed", self.docs)

    def test_native_affinity_test_is_present(self):
        self.assertIn('[OS] Thread pool respects Linux affinity mask', self.native)
        self.assertIn("CHECK(OS::get_singleton()->get_default_thread_pool_size() == allowed_count);", self.native)

    def test_native_default_thread_count_is_positive(self):
        self.assertIn('[OS] Default worker pool thread count is positive', self.native)
        self.assertIn("get_default_thread_pool_size() >= 1", self.native)


class FbxBackportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = source("modules/fbx/fbx_document.cpp")
        cls.header = source("modules/fbx/fbx_document.h")

    def test_neutral_bone_method_declared(self):
        self.assertIn("Error _add_neutral_bones(Ref<FBXState> p_state);", self.header)
        self.assertIn("Error FBXDocument::_add_neutral_bones(Ref<FBXState> p_state)", self.cpp)

    def test_unweighted_vertex_uses_neutral_bone(self):
        self.assertRegex(self.cpp, r"if \(!\(total_weight > 0\.0f\)\) \{\s+bones\.write\[vertex_i \* num_skin_weights\] = int\(fbx_skin->clusters\.count\);\s+weights\.write\[vertex_i \* num_skin_weights\] = 1\.0f;")

    def test_neutral_bones_are_created_before_skeletons(self):
        start = self.cpp.index("/* ADD NEUTRAL BONES */")
        add = self.cpp.index("_add_neutral_bones(p_state);", start)
        skeletons = self.cpp.index("SkinTool::_create_skeletons(", start)
        self.assertLess(start, add)
        self.assertLess(add, skeletons)

    def test_only_skins_with_zero_weight_vertices_need_bones(self):
        body = self.cpp.split("Error FBXDocument::_add_neutral_bones", 1)[1].split("Error FBXDocument::_parse_skins", 1)[0]
        self.assertIn("if (!(total_weight > 0.0f))", body)
        self.assertIn("if (!needs_neutral_bone)", body)

    def test_neutral_bones_are_reused_per_skeleton(self):
        body = self.cpp.split("Error FBXDocument::_add_neutral_bones", 1)[1].split("Error FBXDocument::_parse_skins", 1)[0]
        self.assertIn("HashMap<GLTFSkeletonIndex, GLTFNodeIndex> neutral_bones;", body)
        self.assertIn("neutral_bones.has(skin->skeleton)", body)
        self.assertIn("neutral_bones.insert(skin->skeleton, neutral_node_i);", body)

    def test_neutral_node_is_joint_with_identity_rest(self):
        self.assertIn('neutral_node->set_name("NeutralBone");', self.cpp)
        self.assertIn("neutral_node->joint = true;", self.cpp)
        self.assertIn('neutral_node->set_additional_data("GODOT_rest_transform", Transform3D());', self.cpp)

    def test_neutral_inverse_bind_is_attached(self):
        self.assertIn("skin->inverse_binds.push_back(neutral_bind);", self.cpp)
        self.assertIn("skin->joints_original.push_back(neutral_node_i);", self.cpp)

    def test_neutral_skin_is_expanded_and_verified(self):
        self.assertIn("SkinTool::_expand_skin(p_state->nodes, skin)", self.cpp)
        self.assertIn("SkinTool::_verify_skin(p_state->nodes, skin)", self.cpp)


if __name__ == "__main__":
    unittest.main()
