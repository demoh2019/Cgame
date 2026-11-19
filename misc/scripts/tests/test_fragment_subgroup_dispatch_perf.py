"""Shader regression: scalar instance indexes for mixed-instance fragment subgroups.

Godot upstream #125023. The Python model checks that the shader's subgroup
partition scheme handles multiple instance IDs without losing fragment lanes.
GPU compilation and performance measurement remain separate requirements.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl"


def subgroup_partitions(instance_indices):
    """Model active-lane first-broadcast dispatch used by the fragment shader."""
    remaining = list(range(len(instance_indices)))
    dispatches = []
    while remaining:
        uniform_index = instance_indices[remaining[0]]
        lanes = [i for i in remaining if instance_indices[i] == uniform_index]
        dispatches.append((uniform_index, lanes))
        remaining = [i for i in remaining if instance_indices[i] != uniform_index]
    return dispatches


class FragmentSubgroupDispatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shader = SOURCE.read_text()

    def test_shader_accepts_uniform_instance_parameter(self):
        self.assertIn("void fragment_shader(in SceneData scene_data, uint instance_index)", self.shader)

    def test_shader_does_not_reload_instance_index_in_fragment_body(self):
        begin = self.shader.index("void fragment_shader(in SceneData scene_data, uint instance_index)")
        end = self.shader.index("\nvoid main()", begin)
        self.assertNotIn("uint instance_index = instance_index_interp;", self.shader[begin:end])

    def test_fragment_dispatch_uses_multimesh_fast_path(self):
        self.assertIn("sc_multimesh() ? draw_call.instance_index : instance_index_interp", self.shader)

    def test_mixed_subgroup_splits_by_uniform_instance(self):
        self.assertIn("uint uniform_instance_index = subgroupBroadcastFirst(instance_index);", self.shader)
        self.assertIn("if (uniform_instance_index == instance_index)", self.shader)

    def test_fragment_invoked_with_uniform_index(self):
        self.assertIn("fragment_shader(scene_data_block.data, uniform_instance_index);", self.shader)

    def test_loop_has_exit_after_dispatch(self):
        start = self.shader.rindex("for (;;) {")
        excerpt = self.shader[start:]
        self.assertIn("break;", excerpt)
        self.assertLess(excerpt.index("fragment_shader(scene_data_block.data, uniform_instance_index);"), excerpt.index("break;"))

    def test_single_instance_group_one_dispatch(self):
        result = subgroup_partitions([8] * 32)
        self.assertEqual(result, [(8, list(range(32)))])

    def test_alternating_instances_dispatch_each_lane_once(self):
        values = [1, 2] * 16
        result = subgroup_partitions(values)
        self.assertEqual([group for group, _ in result], [1, 2])
        self.assertEqual(sorted(i for _, lanes in result for i in lanes), list(range(32)))

    def test_interleaved_instances_have_no_lost_lanes(self):
        values = [4, 7, 4, 11, 7, 4, 9, 7, 9, 11, 4]
        result = subgroup_partitions(values)
        self.assertEqual([group for group, _ in result], [4, 7, 11, 9])
        self.assertEqual(sorted(i for _, lanes in result for i in lanes), list(range(len(values))))
        for group, lanes in result:
            self.assertTrue(all(values[i] == group for i in lanes))

    def test_empty_and_single_lane_subgroups(self):
        self.assertEqual(subgroup_partitions([]), [])
        self.assertEqual(subgroup_partitions([3]), [(3, [0])])

    def test_subgroup_all_unique(self):
        values = list(range(32))
        result = subgroup_partitions(values)
        self.assertEqual(len(result), 32)
        self.assertEqual([lanes for _, lanes in result], [[i] for i in range(32)])

    def test_vertex_instance_dispatch_kept(self):
        self.assertIn("InstanceData instance_data;", self.shader)
        self.assertIn("subgroupBroadcastFirst(instance_index)", self.shader)


if __name__ == "__main__":
    unittest.main()
