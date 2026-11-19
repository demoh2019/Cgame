"""Source regression guards for CPU-light Curve search and Gradient sampling.

Complement native Godot tests and a deterministic standalone C++ equivalence
benchmark. A source contract by itself does not measure engine FPS.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CurveHotpathContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = read("scene/resources/curve.cpp")
        cls.method = cls.cpp.split("int Curve::get_index(real_t p_offset) const {", 1)[1].split("\n}\n", 1)[0]
        cls.test = read("tests/scene/test_curve.cpp")

    def test_method_still_has_bounded_binary_search(self):
        self.assertIn("while (imax - imin > 1)", self.method)

    def test_search_middle_still_uses_integer_halves(self):
        self.assertIn("int m = (imin + imax) / 2;", self.method)

    def test_midpoint_read_only_once(self):
        self.assertEqual(self.method.count("_points[m].position.x"), 1)

    def test_neighbor_read_occurs_only_in_left_half(self):
        self.assertLess(self.method.index("if (a < p_offset)"),
                        self.method.index("_points[m + 1].position.x"))

    def test_neighbor_is_not_loaded_before_branch(self):
        self.assertNotIn("real_t b = _points[m + 1].position.x;", self.method)

    def test_right_half_still_moves_maximum(self):
        self.assertIn("} else if (a > p_offset) {\n\t\t\timax = m;", self.method)

    def test_equality_still_returns_midpoint(self):
        self.assertIn("} else {\n\t\t\treturn m;", self.method)

    def test_empty_and_single_curve_checks_remain(self):
        sample = self.cpp.split("real_t Curve::sample(real_t p_offset) const {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("if (_points.is_empty())", sample)
        self.assertIn("if (_points.size() == 1)", sample)

    def test_upper_clamp_remains(self):
        self.assertIn("if (p_offset > _points[imax].position.x)", self.method)
        self.assertIn("return imax;", self.method)

    def test_curve_sample_uses_index(self):
        self.assertIn("uint32_t i = get_index(p_offset);", self.cpp)

    def test_native_exact_control_tests_present(self):
        self.assertIn("Hot-path index search preserves exact control values", self.test)
        self.assertIn("for (int i = 0; i <= 64; ++i)", self.test)

    def test_native_empty_single_case_present(self):
        self.assertIn("Hot-path index search keeps single and empty curves safe", self.test)


class GradientHotpathContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = read("scene/resources/gradient.h")
        cls.sample = cls.header.split("_FORCE_INLINE_ Color get_color_at_offset(float p_offset) {", 1)[1].split("\n\t}\n", 1)[0]
        cls.test = read("tests/scene/test_gradient.cpp")

    def test_constant_returns_before_any_division(self):
        self.assertLess(self.sample.index("case GRADIENT_INTERPOLATE_CONSTANT:"),
                        self.sample.index("const float weight ="))
        const_segment = self.sample.split("case GRADIENT_INTERPOLATE_CONSTANT:", 1)[1].split("case GRADIENT_INTERPOLATE_LINEAR:", 1)[0]
        self.assertNotIn("/ (point2.offset", const_segment)

    def test_linear_computes_own_weight(self):
        linear = self.sample.split("case GRADIENT_INTERPOLATE_LINEAR:", 1)[1].split("case GRADIENT_INTERPOLATE_CUBIC:", 1)[0]
        self.assertIn("const float weight = (p_offset - point1.offset) / (point2.offset - point1.offset);", linear)
        self.assertIn("color1.lerp(color2, weight)", linear)

    def test_cubic_computes_own_weight(self):
        cubic = self.sample.split("case GRADIENT_INTERPOLATE_CUBIC:", 1)[1]
        self.assertIn("const float weight = (p_offset - point1.offset) / (point2.offset - point1.offset);", cubic)
        self.assertIn("Math::cubic_interpolate", cubic)

    def test_constant_returns_exact_left_color(self):
        self.assertIn("case GRADIENT_INTERPOLATE_CONSTANT: {\n\t\t\t\treturn point1.color;", self.sample)

    def test_color_space_transform_remains_for_interpolated_modes(self):
        self.assertIn("transform_color_space(point1.color)", self.sample)
        self.assertIn("inv_transform_color_space(interpolated)", self.sample)

    def test_binary_search_still_guards_empty_points(self):
        self.assertIn("if (points.is_empty())", self.sample)
        self.assertIn("while (low <= high)", self.sample)

    def test_native_constant_boundaries_present(self):
        self.assertIn("Constant sampling preserves endpoints and step boundaries", self.test)
        self.assertIn("get_color_at_offset(0.5f)", self.test)

    def test_native_linear_and_cubic_present(self):
        self.assertIn("Linear and cubic sampling retain interpolation weights", self.test)
        self.assertIn("GRADIENT_INTERPOLATE_CUBIC", self.test)


if __name__ == "__main__":
    unittest.main()
