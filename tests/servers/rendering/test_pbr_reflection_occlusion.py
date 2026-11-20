"""Native Forward+ indirect-specular continuity and PBR occlusion regressions.

Run:
    python3 -m unittest tests/servers/rendering/test_pbr_reflection_occlusion.py -v

Source contracts + numerical invariants, not a GPU shader compile or visual
benchmark. Only tests the existing render path; no extra GPU passes are added.
"""

from pathlib import Path
import math
import unittest


ROOT = Path(__file__).resolve().parents[3]
SHADER = (
    ROOT / "servers/rendering/renderer_rd/shaders/forward_clustered/"
    "scene_forward_clustered.glsl"
)


def lagarde_specular_ao(no_v, ao, roughness):
    """Reference to the Lagarde/Frostbite-Filament specular visibility model."""
    no_v = min(max(no_v, 0.0), 1.0)
    ao = min(max(ao, 0.0), 1.0)
    roughness = min(max(roughness, 0.0), 1.0)
    if ao >= 0.999:
        return 1.0
    exponent = 2 ** (-16.0 * roughness - 1.0)
    value = max(no_v + ao, 0.0001) ** exponent - 1.0 + ao
    return min(max(value, 0.0), 1.0)


def blend_reflection(sdfgi_rgb, sky_rgb, blend):
    """Reference for smooth SDFGI -> sky IBL transition on the outer cascade."""
    return tuple(sdfgi * (1.0 - blend) + sky * blend
                 for sdfgi, sky in zip(sdfgi_rgb, sky_rgb))


class NativePBRReflectionsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SHADER.read_text(encoding="utf-8")

    def test_outer_sdfgi_cascade_uses_final_local_specular_before_assignment(self):
        source = self.source
        begin = source.index("if (cascade == sdfgi.max_cascades - 1)")
        end = source.index("} else {", begin)
        branch = source[begin:end]
        self.assertIn("diffuse = mix(diffuse, ambient_light, blend);", branch)
        self.assertIn(
            "specular = mix(specular, indirect_specular_light, blend);", branch
        )
        self.assertNotIn("indirect_specular_light = mix(", branch)
        self.assertIn(
            "indirect_specular_light = specular;",
            source[end:source.index("if (sc_use_forward_gi()", end)]
        )

    def test_outer_reflection_fade_is_bounded_and_continuous_for_hdr_colors(self):
        for gi, sky in (
            ((0.02, 0.03, 0.01), (1.3, 0.7, 0.1)),
            ((7.0, 3.0, 0.5), (0.02, 0.03, 0.05)),
            ((0.3, 0.7, 0.2), (0.3, 0.7, 0.2)),
        ):
            last = None
            for blend in (0.0, 0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99, 1.0):
                pixel = blend_reflection(gi, sky, blend)
                for channel, a, b in zip(pixel, gi, sky):
                    self.assertGreaterEqual(channel + 1e-12, min(a, b))
                    self.assertLessEqual(channel - 1e-12, max(a, b))
                if last is not None:
                    self.assertTrue(all(math.isfinite(c) for c in pixel))
                last = pixel
            self.assertEqual(blend_reflection(gi, sky, 0.0), gi)
            self.assertEqual(blend_reflection(gi, sky, 1.0), sky)

    def test_roughness_aware_specular_occlusion_is_in_existing_shading_pass(self):
        source = self.source
        start = source.index("#else // BENT_NORMAL_MAP_USED", source.index("//finalize ambient light here"))
        end = source.index("#endif // BENT_NORMAL_MAP_USED", start)
        no_bent_normal = source[start:end]
        self.assertIn("if (ao < 0.999)", no_bent_normal)
        self.assertIn("float specular_occlusion = visibility;", no_bent_normal)
        self.assertIn("if (roughness < 0.55)", no_bent_normal)
        self.assertIn("float NoV = clamp(dot(normal, view), 0.0, 1.0);", no_bent_normal)
        self.assertIn("float visibility = clamp(ao, 0.0, 1.0);", no_bent_normal)
        self.assertIn("exp2(-16.0 * clamp(roughness, 0.0, 1.0) - 1.0)", no_bent_normal)
        self.assertIn("indirect_specular_light *= specular_occlusion;", no_bent_normal)
        self.assertNotIn("reflective_f * specular_occlusion * 10.0", no_bent_normal)
        self.assertNotIn("texture(", no_bent_normal)
        self.assertNotIn("direct_specular_light *=", no_bent_normal)
        self.assertIn("#ifdef BENT_NORMAL_MAP_USED", source)

    def test_specular_ao_preserves_unoccluded_and_direct_light(self):
        for n_dot_v in (0.0, 0.02, 0.25, 0.5, 0.9, 1.0):
            for roughness in (0.0, 0.02, 0.1, 0.3, 0.5, 0.9, 1.0):
                self.assertEqual(lagarde_specular_ao(n_dot_v, 1.0, roughness), 1.0)
                self.assertEqual(lagarde_specular_ao(n_dot_v, 0.0, roughness), 0.0)
                for ao in (0.01, 0.05, 0.1, 0.35, 0.6, 0.85, 0.98):
                    out = lagarde_specular_ao(n_dot_v, ao, roughness)
                    self.assertTrue(math.isfinite(out))
                    self.assertGreaterEqual(out, 0.0)
                    self.assertLessEqual(out, 1.0)

    def test_grazing_reflections_occlude_more_than_head_on(self):
        for ao in (0.15, 0.35, 0.7, 0.9):
            for roughness in (0.01, 0.08, 0.25, 0.7):
                grazing = lagarde_specular_ao(0.02, ao, roughness)
                head_on = lagarde_specular_ao(0.95, ao, roughness)
                self.assertLessEqual(grazing, head_on)

    def test_rough_surface_fast_path_matches_lagarde_within_visual_tolerance(self):
        # The exponent is <= 0.00112 for roughness >= .55. This shortcut
        # avoids pow/exp2 on dry terrain and foliage without losing
        # visually meaningful specular reflection visibility.
        max_error = 0.0
        for roughness in (0.55, 0.6, 0.75, 0.9, 1.0):
            for ao_int in range(1000):
                ao = ao_int / 1000.0
                for no_v in (0.0, 0.02, 0.1, 0.4, 0.7, 1.0):
                    exact = lagarde_specular_ao(no_v, ao, roughness)
                    approx = ao if ao < 0.999 else 1.0
                    max_error = max(max_error, abs(exact - approx))
        self.assertLessEqual(max_error, 0.0065)

    def test_native_shader_keeps_specular_ao_after_reflection_probe_blending(self):
        source = self.source
        reflection_blend = source.index("indirect_specular_light = reflection_accum.rgb;")
        ao_calc = source.index("indirect_specular_light *= specular_occlusion;")
        self.assertLess(reflection_blend, ao_calc)


if __name__ == "__main__":
    unittest.main()
