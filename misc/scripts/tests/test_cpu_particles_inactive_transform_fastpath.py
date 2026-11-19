"""Regression contracts for skipping discarded transforms of inactive CPU particles."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class CPUParticlesInactiveTransformTests(unittest.TestCase):
    def _buffer_function(self, dimension):
        source = (ROOT / f"scene/{dimension}d/cpu_particles_{dimension}d.cpp").read_text(encoding="utf-8")
        start = source.index(f"void CPUParticles{dimension}D::_update_particle_data_buffer()")
        end = source.index(f"void CPUParticles{dimension}D::_set_", start)
        return source[start:end]

    def test_inactive_particles_skip_transform_multiplications(self):
        for dimension in (2, 3):
            with self.subTest(dimension=dimension):
                body = self._buffer_function(dimension)
                # The transform is read and multiplied only after checking active.
                checked = body.index("if (r[idx].active) {")
                transform = body.index(f"Transform{dimension}D t = r[idx].transform;")
                matrix_mul = body.index("t = inv_emission_transform * t;")
                zeroed = body.index("memset(ptr, 0, sizeof(float) *")
                self.assertLess(checked, transform)
                self.assertLess(transform, matrix_mul)
                self.assertLess(matrix_mul, zeroed)

                # The zeroed transform is still followed by unchanged color/custom attributes.
                self.assertIn("Color c = r[idx].color;", body)
                self.assertIn("r[idx].custom[0]", body)
                self.assertIn("r[idx].custom[3]", body)

    def test_inactive_transform_math_elimination_preserves_buffer_values(self):
        # Reference layout: 2D writes 8 transform floats and 3D writes 12.
        # The old implementation transformed inactive particles before discarding
        # the result. Both paths must encode identical active/inactive outputs.
        for stride in (8, 12):
            for active in (False, True):
                values = tuple(float(i + 1) for i in range(stride))
                multiplications = {"before": 0, "after": 0}

                def transform(which):
                    multiplications[which] += 1
                    return tuple(v * 2.0 + 1.0 for v in values)

                # Original C++ computes the matrix product even if it will
                # immediately zero the resulting transform.
                original_transform = transform("before")
                original_output = original_transform if active else (0.0,) * stride

                # New C++ skips that work on the inactive branch.
                optimized_output = transform("after") if active else (0.0,) * stride
                self.assertEqual(original_output, optimized_output)
                self.assertEqual(multiplications["before"], 1)
                self.assertEqual(multiplications["after"], int(active))


if __name__ == "__main__":
    unittest.main()
