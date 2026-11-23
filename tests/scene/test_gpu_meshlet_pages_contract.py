"""Source/API contract for bounded GPU-resident meshlet pages and Albion integration.

Run with python3 -m unittest tests/scene/test_gpu_meshlet_pages_contract.py -v.
These checks do NOT replace Vulkan mesh shader compilation and a GPU capture.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TestGpuMeshletPageContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = (ROOT / "game/scripts/shared/meshlet_page_streaming.gd").read_text()
        cls.renderer = (ROOT / "game/scripts/client/meshlet_renderer.gd").read_text()
        cls.task = (ROOT / "game/shaders/compute/meshlet.task.glsl").read_text()
        cls.mesh = (ROOT / "game/shaders/compute/meshlet.mesh.glsl").read_text()
        cls.probe = (ROOT / "game/scripts/client/virtual_geometry_probe.gd").read_text()
        cls.client = (ROOT / "game/scripts/client/online_main.gd").read_text()
        cls.test = (ROOT / "game/tests/test_meshlet_page_streaming.gd").read_text()

    def test_storage_page_layout_matches_shader(self):
        for token in (
            "const MESHLETS_PER_PAGE: int = 32",
            "const MAX_MESHLET_VERTICES: int = 64",
            "const MAX_MESHLET_TRIANGLES: int = 124",
            "const POSITIONS_BYTES: int = MESHLETS_PER_PAGE * MAX_MESHLET_VERTICES * 16",
            "const VERTEX_IDS_BYTES: int = MESHLETS_PER_PAGE * MAX_MESHLET_VERTICES * 4",
            "const TRIANGLES_BYTES: int = MESHLETS_PER_PAGE * MAX_MESHLET_TRIANGLES * 4",
            "const DESCRIPTORS_BYTES: int = MESHLETS_PER_PAGE * 48",
        ):
            self.assertIn(token, self.policy)
        self.assertIn("#define TASK_GROUP_SIZE 32u", self.task)
        self.assertIn("layout(triangles, max_vertices = 64, max_primitives = 124) out", self.mesh)
        self.assertIn("const DESCRIPTOR_STRIDE: int = 48", self.renderer)
        self.assertIn("a | (b << 8) | (c << 16)", self.renderer)
        self.assertIn("slot_id * TASK_GROUP_SIZE * MAX_MESHLET_VERTICES", self.renderer)
        self.assertIn("slot_id * TASK_GROUP_SIZE * MAX_MESHLET_TRIANGLES", self.renderer)

    def test_resident_only_gpu_allocations_and_no_readback(self):
        fn = self.renderer.split("func _ensure_gpu(", 1)[1].split("func _create_shader(", 1)[0]
        for marker in (
            "_page_bounds.size(), clampi(max_resident_pages, 1, 256)",
            "slots * PagePolicy.POSITIONS_BYTES",
            "slots * PagePolicy.VERTEX_IDS_BYTES",
            "slots * PagePolicy.TRIANGLES_BYTES",
            "slots * PagePolicy.DESCRIPTORS_BYTES",
            "empty_descriptors.resize(",
        ):
            self.assertIn(marker, fn)
        self.assertNotIn("_packed[\"positions\"]", fn)
        self.assertNotIn("_packed[\"descriptors\"]", fn)
        self.assertNotIn("buffer_get_data", self.renderer)
        self.assertIn("_slot_pages.size() * TASK_GROUP_SIZE", self.renderer)
        self.assertIn("draw_list_draw_mesh_tasks", self.renderer)
        self.assertIn("m.counts.z == 0u || m.counts.w == 0u", self.task)
        self.assertIn("if not _stream_gpu_pages(cam.origin)", self.renderer)
        stream = self.renderer.split("func _stream_gpu_pages(", 1)[1].split("func _storage(", 1)[0]
        self.assertIn("PagePolicy.wanted_pages(", stream)
        self.assertIn("PagePolicy.plan(", stream)
        self.assertIn("max_page_uploads_per_frame", stream)
        self.assertIn("_rd.buffer_update(_buffers[index], slot * stride", stream)
        self.assertNotIn("buffer_get_data", stream)

    def test_safe_canonical_game_opt_in_and_fallback(self):
        for marker in (
            'CGAME_MESHLET_PAGE_PROBE',
            'MeshletRenderer.new()',
            'mesh.get_surface_count() != 1',
            'renderer.setup_from_mesh(vertices, indices)',
            'renderer.call("mesh_shader_supported")',
            'RenderingServer.call_on_render_thread',
        ):
            self.assertIn(marker, self.probe)
        self.assertIn('const VirtualGeometryProbe = preload("res://scripts/client/virtual_geometry_probe.gd")', self.client)
        self.assertIn('VirtualGeometryProbe.attach_for_debug(Meshes.get_mesh("rock"), camera)', self.client)
        self.assertIn('VirtualGeometryProbe.detach_for_debug(_meshlet_page_probe, camera)', self.client)
        self.assertIn('_meshlet_page_probe.call("set_view", camera.global_position, camera.get_frustum())', self.client)
        self.assertIn("func create_fallback_instance()", self.renderer)
        self.assertIn("func choose_path()", self.renderer)
        self.assertNotIn("CGAME_MESHLET_PAGE_PROBE", (ROOT / "game/scripts/server/game_server.gd").read_text())

    def test_tests_and_ci_are_registered(self):
        runner = (ROOT / "game/tests/run_all.gd").read_text()
        for suite in ("test_meshlet_renderer.gd", "test_meshlet_page_streaming.gd"):
            self.assertIn(suite, runner)
        for phrase in (
            "camera movement uploads one replacement",
            "the GPU task shader refuses zeroed pages",
            "the live Albion rock model can produce GPU meshlets",
        ):
            self.assertIn(phrase, self.test)
        workflow = (ROOT / ".github/workflows/gpu-meshlet-residency.yml").read_text()
        self.assertIn("test_gpu_meshlet_pages_contract.py", workflow)
        self.assertIn("test_meshlet_page_streaming", workflow)
        self.assertIn("test_meshlet_renderer", workflow)
        self.assertIn("tests=yes", workflow)
        docs = (ROOT / "game/docs/P1_GPU_MESHLET_RESIDENCY.md").read_text()
        self.assertIn("not", docs.lower())
        self.assertIn("hardware", docs.lower())


if __name__ == "__main__":
    unittest.main()
