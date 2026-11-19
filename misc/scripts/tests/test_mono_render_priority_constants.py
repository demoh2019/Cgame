"""Regression contracts for upstream Godot #125477 C# RenderPriority constants."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "modules/mono/editor/bindings_generator.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "modules/mono/editor/bindings_generator.h").read_text(encoding="utf-8")


class MonoMaterialRenderPriorityTests(unittest.TestCase):
    def test_whitelist_only_targets_material_render_priority_limits(self):
        match = re.search(
            r"const Vector<String> constants_with_int32_type\s*=\s*\{([^}]+)\};",
            SOURCE, re.S)
        self.assertIsNotNone(match)
        values = re.findall(r'"([^"]+)"', match.group(1))
        self.assertCountEqual(values,
                              ["Material.RENDER_PRIORITY_MIN", "Material.RENDER_PRIORITY_MAX"])

    def test_per_constant_flag_defaults_to_false(self):
        self.assertIn("bool is_int32 = false;", HEADER)

    def test_bindings_generator_uses_int32_for_whitelisted_constants(self):
        self.assertIn('output.append(iconstant.is_int32 ? "int " : "long ");', SOURCE)

    def test_unlisted_constants_keep_long_type(self):
        self.assertIn("iconstant.is_int32 ? \"int \" : \"long \"", SOURCE)
        self.assertIn("bool is_int32 = false;", HEADER)

    def test_whitelist_lookup_uses_full_constant_name(self):
        self.assertIn('constants_with_int32_type.has(itype.name + "." + constant_name)', SOURCE)

    def test_prevents_overflow_before_narrowing(self):
        self.assertIn("value < INT32_MIN || value > INT32_MAX", SOURCE)
        self.assertIn("ERR_FAIL_COND_V_MSG(", SOURCE)
        self.assertLess(
            SOURCE.index("value < INT32_MIN || value > INT32_MAX"),
            SOURCE.index("iconstant.is_int32 = true;"))

    def test_output_preserves_integer_value(self):
        start = SOURCE.index('output.append(iconstant.is_int32 ? "int " : "long ");')
        self.assertIn("output.append(itos(iconstant.value));", SOURCE[start:start+500])

    def test_int32_names_are_not_exported_as_unconditional_long(self):
        # Another generator path intentionally emits long, so scope this to
        # the object-constant writer, where the new type selection occurs.
        start = SOURCE.index('output.append(iconstant.is_int32 ? "int " : "long ");')
        writer = SOURCE[start - 150:start + 300]
        self.assertNotIn('output.append(MEMBER_BEGIN "public const long ");', writer)


if __name__ == "__main__":
    unittest.main()
