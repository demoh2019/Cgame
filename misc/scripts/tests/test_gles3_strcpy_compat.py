#!/usr/bin/env python3
"""GLES3 CRT mapping regression tests; no full Godot build required.

Run: python3 -m unittest discover -s misc/scripts/tests -p test_gles3_strcpy_compat.py -v
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "drivers/gles3/rasterizer_gles3.cpp"
START = "#if defined(GLAD_ENABLED) || defined(EGL_ENABLED) || defined(ANDROID_ENABLED)"
END = "#endif // GLAD_ENABLED || EGL_ENABLED || ANDROID_ENABLED"


def extract_compat_block() -> str:
    source = SOURCE.read_text(encoding="utf-8")
    start = source.index(START)
    end = source.index(END, start) + len(END)
    return source[start:end] + "\n"


class TestGles3StrcpyCompatibility(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.block = extract_compat_block()
        candidate = os.environ.get("CXX", "c++")
        cls.compiler = shutil.which(candidate)

    def test_guard_is_msvc_specific(self) -> None:
        self.assertRegex(self.block, r"(?m)^#ifdef _MSC_VER$")
        self.assertNotRegex(self.block, r"(?m)^#ifdef _WIN32$")
        self.assertEqual(self.block.count("#define strcpy strcpy_s"), 1)

    def test_gl_debug_callback_retained(self) -> None:
        self.assertIn("#define GL_DEBUG_CALLBACK", self.block)
        self.assertTrue(self.block.startswith(START))
        self.assertTrue(self.block.rstrip().endswith(END))

    def _strcpy_macro(self, *definitions: str) -> bool:
        if self.compiler is None:
            self.skipTest("C++ preprocessor not installed")
        cmd = [self.compiler, "-x", "c++", "-E", "-dM", "-"]
        cmd += ["-D" + definition for definition in definitions]
        result = subprocess.run(cmd, input=self.block, text=True, capture_output=True, check=True)
        return re.search(r"(?m)^#define strcpy strcpy_s$", result.stdout) is not None

    def test_msvc_uses_strcpy_s_with_supported_gl_backends(self) -> None:
        for backend in ("GLAD_ENABLED", "EGL_ENABLED", "ANDROID_ENABLED"):
            with self.subTest(backend=backend):
                self.assertTrue(self._strcpy_macro(backend, "_WIN32", "_MSC_VER=1930"))

    def test_mingw_keeps_standard_strcpy(self) -> None:
        for backend in ("GLAD_ENABLED", "EGL_ENABLED", "ANDROID_ENABLED"):
            for mingw in ("__MINGW32__", "__MINGW64__"):
                with self.subTest(backend=backend, mingw=mingw):
                    self.assertFalse(self._strcpy_macro(backend, "_WIN32", mingw))

    def test_non_msvc_targets_keep_standard_strcpy(self) -> None:
        for definitions in (
            ("GLAD_ENABLED",),
            ("EGL_ENABLED", "_WIN32"),
            ("ANDROID_ENABLED", "__ANDROID__"),
            ("GLAD_ENABLED", "_WIN32", "__clang__"),
        ):
            with self.subTest(definitions=definitions):
                self.assertFalse(self._strcpy_macro(*definitions))

    def test_no_gl_backend_never_defines_mapping(self) -> None:
        for definitions in ((), ("_MSC_VER=1930",), ("_WIN32", "_MSC_VER=1930")):
            with self.subTest(definitions=definitions):
                self.assertFalse(self._strcpy_macro(*definitions))


    def _expand_strcpy_call(self, *definitions: str) -> str:
        """Check emitted tokens, not only whether the macro exists in -dM output."""
        if self.compiler is None:
            self.skipTest("C++ preprocessor not installed")
        command = [self.compiler, "-x", "c++", "-E", "-P", "-"]
        command += ["-D" + definition for definition in definitions]
        result = subprocess.run(
            command,
            input=self.block + "strcpy(dst, src)\n",
            text=True,
            capture_output=True,
            check=True,
            timeout=15,
        )
        return result.stdout.strip()

    def test_real_mingw_strcpy_call_stays_unmodified(self) -> None:
        for backend in ("GLAD_ENABLED", "EGL_ENABLED", "ANDROID_ENABLED"):
            for mingw in ("__MINGW32__", "__MINGW64__"):
                with self.subTest(backend=backend, mingw=mingw):
                    self.assertEqual(
                        self._expand_strcpy_call("_WIN32", backend, mingw),
                        "strcpy(dst, src)",
                    )

    def test_real_msvc_strcpy_call_maps_to_secure_variant(self) -> None:
        for backend in ("GLAD_ENABLED", "EGL_ENABLED", "ANDROID_ENABLED"):
            with self.subTest(backend=backend):
                self.assertEqual(
                    self._expand_strcpy_call("_WIN32", "_MSC_VER=1930", backend),
                    "strcpy_s(dst, src)",
                )

    def test_real_other_compilers_keep_standard_strcpy_call(self) -> None:
        for definitions in (
            ("GLAD_ENABLED",),
            ("EGL_ENABLED", "_WIN32", "__clang__"),
            ("ANDROID_ENABLED", "__ANDROID__"),
            ("GLAD_ENABLED", "_MSC_VER=1930"),
        ):
            with self.subTest(definitions=definitions):
                expected = (
                    "strcpy_s(dst, src)"
                    if "_MSC_VER=1930" in definitions
                    else "strcpy(dst, src)"
                )
                self.assertEqual(self._expand_strcpy_call(*definitions), expected)

    def test_real_no_gl_backend_never_rewrites_strcpy(self) -> None:
        for definitions in (
            (),
            ("_WIN32",),
            ("_MSC_VER=1930",),
            ("_WIN32", "_MSC_VER=1930"),
        ):
            with self.subTest(definitions=definitions):
                self.assertEqual(self._expand_strcpy_call(*definitions), "strcpy(dst, src)")



if __name__ == "__main__":
    unittest.main()
