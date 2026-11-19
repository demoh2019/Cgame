"""C# Mathf intrinsic fast-path contracts (Godot #123877).

Numeric edge behavior may differ slightly from the old expression; compile and
run .NET 10 tests for both float and double before treating this as validated.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "modules/mono/glue/GodotSharp/GodotSharp/Core/Mathf.cs").read_text(encoding="utf-8")
CSPROJ = (ROOT / "modules/mono/glue/GodotSharp/GodotSharp/GodotSharp.csproj").read_text(encoding="utf-8")

MAP = {
    "DegToRad(float deg)": "float.DegreesToRadians(deg)",
    "DegToRad(double deg)": "double.DegreesToRadians(deg)",
    "RadToDeg(float rad)": "float.RadiansToDegrees(rad)",
    "RadToDeg(double rad)": "double.RadiansToDegrees(rad)",
    "Lerp(float from, float to, float weight)": "float.Lerp(from, to, weight)",
    "Lerp(double from, double to, double weight)": "double.Lerp(from, to, weight)",
}


def method_body(signature):
    pattern = r"public static " + (r"float" if "(float " in signature else r"double")
    i = SOURCE.index("public static ", SOURCE.index(signature) - 28)
    end = SOURCE.index("\n        }", i)
    return SOURCE[i:end + 10]


class MathfIntrinsicsPerformance(unittest.TestCase):
    def test_has_all_six_float_and_double_intrinsics(self):
        for signature, implementation in MAP.items():
            with self.subTest(signature=signature):
                self.assertIn("public static " + ("float " if "(float " in signature else "double ") + signature, SOURCE)
                self.assertIn(implementation, SOURCE)

    def test_no_legacy_angle_constants_in_mathf(self):
        for name in ("DegToRadConstF", "DegToRadConstD",
                     "RadToDegConstF", "RadToDegConstD"):
            with self.subTest(name=name):
                self.assertNotIn(name, SOURCE)

    def test_mathf_target_is_dotnet10(self):
        self.assertIn("<TargetFramework>net10.0</TargetFramework>", CSPROJ)

    def test_lerp_methods_use_bcl_exactly(self):
        for type_name in ("float", "double"):
            signature = f"Lerp({type_name} from, {type_name} to, {type_name} weight)"
            body = method_body(signature)
            with self.subTest(type_name=type_name):
                self.assertIn(f"return {type_name}.Lerp(from, to, weight);", body)

    def test_degree_radian_methods_use_bcl_exactly(self):
        for type_name in ("float", "double"):
            for method, bcl in (("DegToRad", "DegreesToRadians"),
                                ("RadToDeg", "RadiansToDegrees")):
                signature = f"{method}({type_name} " + ("deg" if method == "DegToRad" else "rad") + ")"
                with self.subTest(type_name=type_name, method=method):
                    self.assertIn(f"return {type_name}.{bcl}(", method_body(signature))

    def test_public_api_signatures_unchanged(self):
        for name, arg in (("DegToRad", "deg"), ("RadToDeg", "rad")):
            for t in ("float", "double"):
                with self.subTest(method=name, type=t):
                    self.assertEqual(SOURCE.count(f"public static {t} {name}({t} {arg})"), 1)

    def test_lerp_signatures_unchanged(self):
        for t in ("float", "double"):
            with self.subTest(type=t):
                self.assertEqual(
                    SOURCE.count(f"public static {t} Lerp({t} from, {t} to, {t} weight)"), 1)

    def test_no_narrowing_in_double_overloads(self):
        for name, args in (("DegToRad", "double deg"), ("RadToDeg", "double rad"),
                           ("Lerp", "double from, double to, double weight")):
            with self.subTest(method=name):
                snippet = method_body(name + "(" + args + ")")
                self.assertNotIn("(float)", snippet)
                self.assertIn("double.", snippet)


if __name__ == "__main__":
    unittest.main()
