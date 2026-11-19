"""Numerical and source contracts for selective Godot #125255 vertex optimizations.

The test checks matrix algebra and shader source wiring, but does not measure
GPU speed or validate shaders on a hardware driver.
"""
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[3]
CLUSTER = (ROOT / "servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl").read_text(encoding="utf-8")
MOBILE = (ROOT / "servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl").read_text(encoding="utf-8")


def multiply_mat4_vec4(columns, vec):
    return [sum(columns[j][i] * vec[j] for j in range(4)) for i in range(4)]


def fma_style_mat4_vec4(columns, vec):
    return [columns[0][i] * vec[0] + (
        columns[1][i] * vec[1] + (
            columns[2][i] * vec[2] + columns[3][i] * vec[3]))
        for i in range(4)]


def multiply_mat4(a, b):
    return [multiply_mat4_vec4(a, b_col) for b_col in b]


def affine_matrix(rng):
    cols = [[rng.uniform(-5.0, 5.0) for _ in range(3)] + [0.0] for _ in range(3)]
    return cols + [[rng.uniform(-10.0, 10.0) for _ in range(3)] + [1.0]]


def fma_style_affine_position(columns, p):
    return [columns[0][i] * p[0] + (
        columns[1][i] * p[1] + (
            columns[2][i] * p[2] + columns[3][i]))
        for i in range(3)]


def fma_style_affine_multiply(a, b):
    cols = [
        [sum(a[j][i] * b[k][j] for j in range(3)) for i in range(3)] + [0.0]
        for k in range(3)
    ]
    return cols + [fma_style_affine_position(a, b[3][:3]) + [1.0]]


class ClusteredShaderFMAContracts(unittest.TestCase):
    def test_macros_declared_after_globals(self):
        self.assertLess(CLUSTER.index("#GLOBALS"), CLUSTER.index("#define MAT3_MUL_VEC3("))

    def test_mat3_macro_uses_three_column_terms(self):
        self.assertIn("#define MAT3_MUL_VEC3(m_mat, m_vec)", CLUSTER)
        self.assertIn("fma((m_mat)[0].xyz", CLUSTER)
        self.assertIn("fma((m_mat)[1].xyz", CLUSTER)

    def test_affine_position_macro_handles_translation(self):
        self.assertIn("#define AFFINE_MUL_POSITION(m_mat, m_position)", CLUSTER)
        self.assertIn("(m_mat)[3].xyz", CLUSTER)

    def test_mat4_vector_macro_declared(self):
        self.assertIn("#define MAT4_MUL_VEC4(m_mat, m_vec)", CLUSTER)

    def test_mat4_matrix_macro_uses_vector_macro(self):
        self.assertIn("#define MAT4_MUL(m_a, m_b)", CLUSTER)
        self.assertIn("MAT4_MUL_VEC4(m_a, (m_b)[0])", CLUSTER)

    def test_affine_matrix_macro_declared(self):
        self.assertIn("#define AFFINE_MAT_MUL(m_a, m_b)", CLUSTER)

    def test_projection_uses_explicit_fma_matrix_math(self):
        self.assertIn("gl_Position = MAT4_MUL_VEC4(projection_matrix, vec4(vertex_interp, 1.0));", CLUSTER)

    def test_world_position_uses_affine_fma(self):
        self.assertIn("vertex = AFFINE_MUL_POSITION(model_matrix, vertex);", CLUSTER)

    def test_camera_view_position_uses_affine_fma(self):
        self.assertIn("vertex = AFFINE_MUL_POSITION(read_view_matrix, vertex);", CLUSTER)

    def test_view_matrix_uses_affine_multiply(self):
        self.assertIn("mat4 modelview = AFFINE_MAT_MUL(read_view_matrix, model_matrix);", CLUSTER)

    def test_multimesh_transform_uses_matrix_macro(self):
        self.assertIn("read_model_matrix = MAT4_MUL(model_matrix, matrix);", CLUSTER)

    def test_double_precision_path_uses_explicit_multiply(self):
        self.assertIn("modelview[3].xyz = MAT3_MUL_VEC3(read_view_matrix, modelview[3].xyz);", CLUSTER)

    def test_forward_plus_retains_position_invariance(self):
        self.assertIn("invariant gl_Position;", CLUSTER)

    def test_instance_index_api_unchanged(self):
        self.assertIn("in uint instance_index, in uint multimesh_offset", CLUSTER)


class MobileShaderContracts(unittest.TestCase):
    def test_mobile_removes_unneeded_invariant_qualifier(self):
        self.assertNotIn("invariant gl_Position;", MOBILE)

    def test_mobile_keeps_vertex_stage_declaration(self):
        self.assertIn("#[vertex]", MOBILE)

    def test_mobile_keeps_output_position(self):
        self.assertIn("gl_Position =", MOBILE)

    def test_mobile_keeps_multiview_declaration(self):
        self.assertIn("USE_MULTIVIEW", MOBILE)


class FMANumericalContracts(unittest.TestCase):
    def test_mat4_vector_multiply_equivalent_for_512_vectors(self):
        rng = random.Random(4096)
        for _ in range(512):
            m = [[rng.uniform(-100, 100) for _ in range(4)] for _ in range(4)]
            v = [rng.uniform(-100, 100) for _ in range(4)]
            normal = multiply_mat4_vec4(m, v)
            optimized = fma_style_mat4_vec4(m, v)
            for a, b in zip(normal, optimized):
                self.assertAlmostEqual(a, b, delta=1e-8 * max(1, abs(a), abs(b)))

    def test_mat4_matrix_multiply_reproduces_standard_product(self):
        rng = random.Random(91)
        for _ in range(150):
            a = [[rng.uniform(-10, 10) for _ in range(4)] for _ in range(4)]
            b = [[rng.uniform(-10, 10) for _ in range(4)] for _ in range(4)]
            normal = multiply_mat4(a, b)
            optimized = [fma_style_mat4_vec4(a, col) for col in b]
            for lhs, rhs in zip(normal, optimized):
                for x, y in zip(lhs, rhs):
                    self.assertAlmostEqual(x, y, delta=1e-8 * max(1, abs(x), abs(y)))

    def test_affine_position_matches_reference_multiplication(self):
        rng = random.Random(720)
        for _ in range(150):
            a = affine_matrix(rng)
            p = [rng.uniform(-10, 10) for _ in range(3)]
            expected = multiply_mat4_vec4(a, p + [1.0])[:3]
            actual = fma_style_affine_position(a, p)
            for x, y in zip(expected, actual):
                self.assertAlmostEqual(x, y, delta=1e-8 * max(1, abs(x), abs(y)))

    def test_affine_matrix_multiply_matches_full_multiply(self):
        rng = random.Random(240)
        for _ in range(150):
            a = affine_matrix(rng)
            b = affine_matrix(rng)
            expected = multiply_mat4(a, b)
            actual = fma_style_affine_multiply(a, b)
            for lhs, rhs in zip(expected, actual):
                for x, y in zip(lhs, rhs):
                    self.assertAlmostEqual(x, y, delta=1e-8 * max(1, abs(x), abs(y)))


if __name__ == "__main__":
    unittest.main()
