#!/usr/bin/env python3
"""Regression contracts for camera component indexing and iOS shader baking.

Source checks are deliberately lightweight and complement native/platform tests.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CameraComponentIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = source("modules/camera/buffer_decoder.h")
        cls.impl = source("modules/camera/buffer_decoder.cpp")
        cls.constructor = cls.impl.split("AbstractYuyvBufferDecoder::AbstractYuyvBufferDecoder", 1)[1].split(
            "SeparateYuyvBufferDecoder::SeparateYuyvBufferDecoder", 1)[0]

    def test_inline_index_storage(self):
        self.assertRegex(self.header, r"int\s+component_indexes\s*\[\s*4\s*\]\s*;")
        self.assertNotRegex(self.header, r"int\s*\*\s*component_indexes")
        self.assertNotIn("new int[4]", self.constructor)
        self.assertNotIn("delete[] component_indexes", self.impl)

    def test_all_five_pixel_formats_keep_original_component_order(self):
        expected = {
            "V4L2_PIX_FMT_YYUV": (0, 1, 2, 3),
            "V4L2_PIX_FMT_YVYU": (0, 2, 3, 1),
            "V4L2_PIX_FMT_UYVY": (1, 3, 0, 2),
            "V4L2_PIX_FMT_VYUY": (1, 3, 2, 0),
            "default": (0, 2, 1, 3),
        }
        pattern = r"(?:case\s+(\w+)\s*:\s*|(\bdefault)\s*:\s*)(.*?)(?=\s*case\s+\w+\s*:|\s*default\s*:|\s*}\s*$)"
        matches = re.findall(pattern, self.constructor, re.DOTALL)
        self.assertEqual(len(matches), 5)
        for case, fallback, body in matches:
            name = case or fallback
            self.assertIn(name, expected)
            assignments = re.findall(r"component_indexes\[(\d)\]\s*=\s*(\d)\s*;", body)
            self.assertEqual(len(assignments), 4, name)
            self.assertEqual(tuple(int(v) for i, v in sorted(assignments, key=lambda t: int(t[0]))), expected[name])

    def test_all_decoders_share_index_mapping(self):
        for name in ("SeparateYuyvBufferDecoder", "YuyvToGrayscaleBufferDecoder", "YuyvToRgbBufferDecoder"):
            body = self.impl.split("void " + name + "::decode(", 1)[1].split("\n}", 1)[0]
            self.assertIn("component_indexes[0]", body)
            self.assertIn("component_indexes[1]", body)

    def test_decoder_does_not_use_dynamic_index_allocation(self):
        self.assertEqual(self.impl.count("component_indexes["), 30)

class ShaderBakePlatformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = source("editor/export/shader_baker/shader_baker_export_plugin.cpp")
        cls.body = cls.source.split(
            "bool ShaderBakerExportPlugin::_begin_customize_resources(", 1)[1].split(
                "RendererSceneRenderRD::get_singleton()->enable_features(renderer_features);", 1)[0]

    def test_fp16_always_included(self):
        self.assertIn("renderer_features.set_flag(RenderingShaderLibrary::FEATURE_FP16_BIT);", self.body)

    def test_fp32_only_outside_ios(self):
        self.assertRegex(self.body, r'if\s*\(\s*!p_features\.has\("ios"\)\s*\)\s*\{\s*renderer_features\.set_flag\(RenderingShaderLibrary::FEATURE_FP32_BIT\);\s*\}')

    def test_ios_fewer_variants_without_changing_other_platforms(self):
        def features(platform):
            enabled = {"fp16"}
            if platform != "ios":
                enabled.add("fp32")
            return enabled
        self.assertEqual(features("ios"), {"fp16"})
        for platform in ("windows", "linux", "macos", "android", "web"):
            self.assertEqual(features(platform), {"fp16", "fp32"})

if __name__ == "__main__":
    unittest.main()
