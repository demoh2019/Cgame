#!/usr/bin/env python3
"""Exercise glTF spotlight conversion Expression strings from the engine source.

Validates actual Godot Expression bodies under a small restricted arithmetic
evaluator against independently hand-derived glTF angle cases. A native Godot
doctest separately exercises GLTFLight::from_node() and to_node().
"""

from __future__ import annotations

import ast
import math
import operator
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[3] / "modules/gltf/extensions/gltf_light.cpp"
OPERATORS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
}
FUNCTIONS = {
    "deg_to_rad": math.radians,
    "maxf": max,
    "minf": min,
}


def expression_from_cpp(name: str) -> str:
    source = SOURCE.read_text(encoding="utf-8")
    match = re.search(r"\b" + re.escape(name) + r'->parse\("([^"]+)"', source)
    if not match:
        raise AssertionError("Expression assignment not found: " + name)
    return match.group(1)


def evaluate(expression: str, **variables: float) -> float:
    """Interpret only arithmetic / allowed calls; never eval arbitrary source."""
    def visit(node: ast.AST) -> float:
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) in (float, int):
            return float(node.value)
        if isinstance(node, ast.Name) and node.id in variables:
            return float(variables[node.id])
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return -visit(node.operand)
        if isinstance(node, ast.BinOp) and type(node.op) in OPERATORS:
            return OPERATORS[type(node.op)](visit(node.left), visit(node.right))
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in FUNCTIONS:
            return float(FUNCTIONS[node.func.id](*(visit(arg) for arg in node.args)))
        raise ValueError("Unsupported expression node: " + type(node).__name__)

    return visit(ast.parse(expression, mode="eval"))


class GltfSpotlightExpressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.to_godot = expression_from_cpp("gltf_to_godot_expr")
        cls.to_gltf = expression_from_cpp("godot_to_gltf_expr")

    def test_half_angle_inner_cone_maps_to_attenuation_three_and_one_third(self):
        result = evaluate(self.to_godot, inner_cone_angle=math.pi / 6, spot_angle=60.0)
        self.assertAlmostEqual(result, 10.0 / 3.0, places=5)

    def test_quarter_angle_maps_to_expected_attenuation(self):
        result = evaluate(self.to_godot, inner_cone_angle=math.pi / 12, spot_angle=60.0)
        self.assertAlmostEqual(result, 1.0 / (0.2 / 0.75 - 0.1), places=5)

    def test_inner_zero_maps_to_ten(self):
        result = evaluate(self.to_godot, inner_cone_angle=0.0, spot_angle=45.0)
        self.assertAlmostEqual(result, 10.0, places=5)

    def test_att_three_and_one_third_exports_half_angle_in_radians(self):
        result = evaluate(self.to_gltf, godot_spot_angle_att=10.0 / 3.0, spot_angle=60.0)
        self.assertAlmostEqual(result, math.pi / 6, places=5)

    def test_tiny_attenuation_exports_valid_cone_in_radians(self):
        outer = math.radians(90)
        result = evaluate(self.to_gltf, godot_spot_angle_att=0.000001, spot_angle=90.0)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, outer)
        self.assertAlmostEqual(result / outer, 0.999999, places=6)

    def test_bidirectional_angle_conversion_for_diverse_cases(self):
        for spot_angle, inner_ratio in ((60.0, 0.25), (60.0, 0.75), (30.0, 0.5), (90.0, 0.9)):
            with self.subTest(spot_angle=spot_angle, inner_ratio=inner_ratio):
                angle = math.radians(spot_angle) * inner_ratio
                att = evaluate(self.to_godot, inner_cone_angle=angle, spot_angle=spot_angle)
                exported = evaluate(self.to_gltf, godot_spot_angle_att=att, spot_angle=spot_angle)
                self.assertAlmostEqual(exported, angle, places=5)


if __name__ == "__main__":
    unittest.main()
