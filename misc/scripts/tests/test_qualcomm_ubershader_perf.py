#!/usr/bin/env python3
"""Regression checks for Qualcomm Adreno 740 Vulkan ubershader workaround.

Runs the actual C++ vendor/device predicate from Godot #125014 against device
IDs. Not a substitute for testing pipelines and GPU memory on physical devices.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "drivers/vulkan/rendering_device_driver_vulkan.cpp"


class AdrenoUbershaderWorkaroundTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = SOURCE.read_text(encoding="utf-8")
        begin = text.index("void RenderingDeviceDriverVulkan::_check_driver_workarounds(")
        cls.body = text[begin:text.index("\n}\n", begin)]
        pattern = (
            r"if \((p_device_properties.vendorID == "
            r"RenderingContextDriver::Vendor::VENDOR_QUALCOMM"
            r" && p_device_properties.deviceID == 0x43050a01)\)"
            r" \{\s*driver_workarounds\.disable_ubershaders = true;\s*\}"
        )
        found = re.search(pattern, cls.body)
        if not found:
            raise AssertionError("Missing exact Qualcomm Adreno 740 workaround")
        cls.predicate = found.group(1)

    def test_workaround_only_targets_qualcomm_adreno_740(self):
        self.assertEqual(self.body.count("deviceID == 0x43050a01"), 1)
        self.assertIn("driver_workarounds.disable_ubershaders = true;", self.body)

    def test_real_device_predicate_compiles_and_preserves_prior_flags(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if not compiler:
            self.skipTest("No C++ compiler found")
        code = r'''
#include <cassert>
#include <cstdint>
struct RenderingContextDriver {
    struct Vendor { enum : uint32_t { VENDOR_QUALCOMM = 0x5143 }; };
};
struct DeviceProperties { uint32_t vendorID; uint32_t deviceID; };
struct Workarounds { bool disable_ubershaders = false; };
int main() {
    for (uint32_t vendor : {uint32_t(0x5143), uint32_t(0x10de), uint32_t(0x1002)}) {
        for (uint32_t device : {uint32_t(0x43050a01), uint32_t(0x6060001),
                                uint32_t(0x43050a00), uint32_t(0x43050a02)}) {
            for (bool prior : {false, true}) {
                DeviceProperties p_device_properties{vendor, device};
                Workarounds driver_workarounds{prior};
                if (''' + self.predicate + r''') {
                    driver_workarounds.disable_ubershaders = true;
                }
                const bool targeted = vendor == 0x5143 && device == 0x43050a01;
                assert(driver_workarounds.disable_ubershaders == (prior || targeted));
            }
        }
    }
}
'''
        code = code.replace("#include <cstdint>", "#include <cstdint>\n#include <initializer_list>")
        with tempfile.TemporaryDirectory() as folder:
            src = Path(folder) / "test.cpp"
            binary = Path(folder) / "test"
            src.write_text(code, encoding="utf-8")
            build = subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                 str(src), "-o", str(binary)],
                capture_output=True, text=True, timeout=30, check=False,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            result = subprocess.run([str(binary)], capture_output=True,
                                    text=True, timeout=10, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
