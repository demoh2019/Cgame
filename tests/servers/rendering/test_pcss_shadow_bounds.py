"""Source and numerical regression tests for native PCSS penumbra guards.

Run from the repository root:
    python3 -m unittest discover -s tests/servers/rendering -p test_pcss_shadow_bounds.py

The tests do not replace GPU image validation on Metal/Vulkan.
"""

import math
from pathlib import Path
import unittest


SHADER = (
    Path(__file__).resolve().parents[3]
    / "servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl"
)


def bounded_penumbra(blocker_depth, receiver_depth):
    """Mirror the GPU's finite, bounded PCSS blocker width."""
    delta = blocker_depth - receiver_depth
    value = delta / max(1.0 - blocker_depth, 0.0001)
    return min(max(value, 0.0), 8.0)


class PcssShadowBoundsTests(unittest.TestCase):
    def test_all_four_shadow_light_types_have_guarded_filter_footprints(self):
        source = SHADER.read_text(encoding="utf-8")
        self.assertEqual(source.count("max(1.0 - blocker_average, 0.0001)"), 4)
        self.assertEqual(
            source.count("float penumbra = clamp((blocker_average - "),
            4,
        )
        self.assertNotIn("/ (1.0 - blocker_average);", source)

    def test_far_depth_and_tiny_denominators_remain_finite(self):
        for blocker in (0.1, 0.5, 0.99, 0.999999, 1.0):
            for receiver in (0.0, 0.01, 0.5, 0.95, 0.999999):
                width = bounded_penumbra(blocker, receiver)
                self.assertTrue(math.isfinite(width))
                self.assertGreaterEqual(width, 0.0)
                self.assertLessEqual(width, 8.0)

    def test_contact_hardening_increases_with_caster_distance(self):
        receiver = 0.6
        widths = [
            bounded_penumbra(blocker, receiver)
            for blocker in (0.6001, 0.65, 0.70, 0.8)
        ]
        self.assertEqual(widths, sorted(widths))
        self.assertGreater(widths[-1], widths[0])

    def test_invalid_depth_order_never_inverts_penumbra(self):
        self.assertEqual(bounded_penumbra(0.3, 0.9), 0.0)
        self.assertEqual(bounded_penumbra(1.0, 1.0), 0.0)


if __name__ == "__main__":
    unittest.main()
