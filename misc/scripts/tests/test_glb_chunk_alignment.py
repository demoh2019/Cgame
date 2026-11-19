#!/usr/bin/env python3
"""Regression checks for the 64-bit GLB chunk-alignment expressions.

This compiles the actual alignment expressions extracted from gltf_document.cpp
and checks large synthetic lengths, without allocating 4+ GiB of memory.
It does not replace a Godot engine build or an import/export integration test.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "modules/gltf/gltf_document.cpp"

ALIGNMENT_ASSIGNMENT = re.compile(
    r"(?:text_chunk_length|binary_chunk_length)\s*=\s*"
    r"(\(\((?:text_data_length|binary_data_length)\s*\+\s*3\)\s*"
    r"&\s*\(~\(uint64_t\)3\)\))"
)


class TestGLBChunkAlignment(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.expressions = ALIGNMENT_ASSIGNMENT.findall(cls.source)

    def test_all_four_serialization_paths_use_a_64_bit_mask(self) -> None:
        self.assertEqual(
            len(self.expressions),
            4,
            "Expected four GLB chunk-alignment sites with explicit uint64_t masks",
        )
        self.assertEqual(
            sum("text_data_length" in expr for expr in self.expressions), 3
        )
        self.assertEqual(
            sum("binary_data_length" in expr for expr in self.expressions), 1
        )
        self.assertNotRegex(
            self.source,
            r"(?:text_chunk_length|binary_chunk_length)\s*=\s*"
            r"\(\([^\n]*&\s*\(~3\)\)",
        )

    def test_compiled_production_expressions_preserve_high_bits(self) -> None:
        self.assertEqual(len(self.expressions), 4)
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if compiler is None:
            self.skipTest("C++ compiler unavailable")

        checks = "\n".join(
            f"  if (({expression}) != expected) return {index + 1};"
            for index, expression in enumerate(self.expressions)
        )
        program = (
            "#include <cstdint>\n"
            "#include <cstdlib>\n"
            "int main(int argc, char **argv) {\n"
            "  if (argc != 2) return 100;\n"
            "  const uint64_t input = std::strtoull(argv[1], nullptr, 0);\n"
            "  const uint64_t text_data_length = input;\n"
            "  const uint64_t binary_data_length = input;\n"
            "  const uint64_t expected = ((input + 3ULL) / 4ULL) * 4ULL;\n"
            f"{checks}\n"
            "  return 0;\n"
            "}\n"
        )

        with tempfile.TemporaryDirectory(prefix="godot-glb-align-") as temp:
            source = Path(temp) / "test_alignment.cpp"
            binary = Path(temp) / "test_alignment"
            source.write_text(program, encoding="utf-8")
            compiled = subprocess.run(
                [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                 str(source), "-o", str(binary)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)

            cases = (
                0, 1, 2, 3, 4, 7, 4093, 4096, 4097,
                0xFFFFFFFD, 0xFFFFFFFF,
                0x100000000, 0x100000001, 0x100000003,
                0x200000002, 0x1000000000001,
                0x7FFFFFFFFFFFFFFB,
            )
            for length in cases:
                with self.subTest(length=length):
                    result = subprocess.run(
                        [str(binary), str(length)],
                        capture_output=True, text=True,
                    )
                    self.assertEqual(
                        result.returncode, 0,
                        f"GLB alignment failed for {length} bytes; "
                        f"expression {result.returncode}",
                    )


if __name__ == "__main__":
    unittest.main()
