"""Numerical and source regressions for mobile-only clearcoat approximation."""
from pathlib import Path
import math
import re
import unittest

ROOT=Path(__file__).resolve().parents[3]


class ClearCoatFastPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lighting=(ROOT/"servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl").read_text()
        cls.mobile=(ROOT/"servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl").read_text()
        cls.method=cls.lighting.split("hvec3 f0_Clear_Coat_To_Surface(hvec3 f0) {",1)[1].split("\n}",1)[0]

    def test_mobile_branch_keeps_forward_plus_precise_polynomial(self):
        self.assertIn("#ifdef USING_MOBILE_RENDERER", self.method)
        self.assertIn("#else", self.method)
        self.assertIn("#endif", self.method)
        self.assertIn("half(0.526868)", self.method)
        self.assertIn("half(0.529324)", self.method)
        self.assertIn("half(0.0482256)", self.method)
        self.assertIn("half(0.941892)", self.method)
        self.assertIn("half(0.263008)", self.method)
        self.assertIn("half(0.346479)", self.method)

    def test_mobile_polynomial_approximates_reference_over_entire_physical_range(self):
        # Unit tests independently evaluate the two literal shader polynomials;
        # the max difference is ~0.01049 in [0, 1] before half precision rounding.
        for step in range(4097):
            f0=step/4096
            fast=min(1.0,max(0.0,f0*(f0*0.526868+0.529324)-0.0482256))
            ref=min(1.0,max(0.0,f0*(f0*(0.941892-0.263008*f0)+0.346479)-0.0285998))
            self.assertLess(abs(fast-ref),0.011)

    def test_mobile_indirect_clearcoat_still_uses_fresnel(self):
        self.assertIn("indirect_specular_light += cc_specular_light * F;",self.mobile)
        self.assertIn("ambient_light *= cc_attenuation;",self.mobile)


if __name__=="__main__":
    unittest.main()
