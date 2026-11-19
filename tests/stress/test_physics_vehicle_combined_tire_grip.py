"""Numerical and source contracts for VehicleWheel3D combined-slip grip."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def project(forward, side, normal, friction, long_grip=1., side_grip=1.):
    args = (forward, side, normal, friction, long_grip, side_grip)
    if not all(math.isfinite(x) for x in args) or normal < 0 or friction < 0 or not 0 <= long_grip <= 4 or not 0 <= side_grip <= 4:
        return 0., 0., 0., False
    base = normal*friction
    max_f = 2*base*long_grip
    max_s = base*side_grip
    if not math.isfinite(max_f) or not math.isfinite(max_s):
        return 0., 0., 0., False
    f = forward if max_f > 0 else 0.
    s = side if max_s > 0 else 0.
    norm = math.hypot(f/max_f if max_f else 0., s/max_s if max_s else 0.)
    if norm > 1:
        f /= norm
        s /= norm
    frac_f = min(1., abs(f/forward)) if forward else 1.
    frac_s = min(1., abs(s/side)) if side else 1.
    return f, s, min(frac_f, frac_s), True


class TestCombinedTireGrip(unittest.TestCase):
    def test_50000_randomized_coupled_grip_ellipses(self):
        rng = random.Random(0xC6A31)
        saturated = 0
        for _ in range(50000):
            n = 10**rng.uniform(-3, 6)
            mu = 10**rng.uniform(-2, 1)
            lg = rng.uniform(.001, 4)
            sg = rng.uniform(.001, 4)
            x = rng.uniform(-6, 6)*n*mu
            y = rng.uniform(-6, 6)*n*mu
            f, s, skid, valid = project(x, y, n, mu, lg, sg)
            self.assertTrue(valid)
            self.assertTrue(all(math.isfinite(z) for z in (f, s, skid)))
            self.assertGreaterEqual(skid, 0.)
            self.assertLessEqual(skid, 1.)
            self.assertLessEqual(math.hypot(f/(2*n*mu*lg), s/(n*mu*sg)), 1+1e-12)
            self.assertLessEqual(abs(f), abs(x)+1e-8)
            self.assertLessEqual(abs(s), abs(y)+1e-8)
            self.assertGreaterEqual(f*x, 0.)
            self.assertGreaterEqual(s*y, 0.)
            if skid < 1:
                saturated += 1
        self.assertGreater(saturated, 30000)

    def test_12000_legacy_grip_ellipse_cases(self):
        rng = random.Random(0xD11)
        for _ in range(12000):
            n = rng.uniform(.01, 2000)
            mu = rng.uniform(.01, 10)
            x = rng.uniform(-100, 100)*n
            y = rng.uniform(-100, 100)*n
            f, s, _, valid = project(x, y, n, mu)
            self.assertTrue(valid)
            old_len = math.hypot(.5*x, y)
            old_factor = min(1., n*mu/old_len) if old_len else 1.
            self.assertAlmostEqual(f, x*old_factor, delta=1e-8)
            self.assertAlmostEqual(s, y*old_factor, delta=1e-8)

    def test_pure_forward_wheelspin_and_independent_grip(self):
        self.assertEqual(project(100, 0, 10, 1), (20., 0., .2, True))
        self.assertEqual(project(100, 6, 10, 1, 0, 1), (0., 6., 0., True))
        self.assertEqual(project(8, 100, 10, 1, 1, 0), (8., 0., 0., True))

    def test_no_contact_and_malformed_data(self):
        self.assertEqual(project(100, 10, 0, 1), (0., 0., 0., True))
        self.assertEqual(project(0, 0, 0, 1), (0., 0., 1., True))
        for args in ((math.nan, 0, 1, 1), (math.inf, 0, 1, 1),
                     (1, 1, -1, 1), (1, 1, 1, -1),
                     (1, 1, 1, 1, 5, 1), (1, 1, 1, 1, 1, math.nan)):
            self.assertEqual(project(*args), (0., 0., 0., False))

    def test_load_scale_invariance(self):
        rng = random.Random(0x45A)
        for _ in range(5000):
            x, y = rng.uniform(-200, 200), rng.uniform(-200, 200)
            n = rng.uniform(.1, 500)
            mu = rng.uniform(.01, 3)
            factor = 10**rng.uniform(-2, 4)
            f, s, skid, _ = project(x, y, n, mu)
            g, h, skid2, _ = project(x*factor, y*factor, n*factor, mu)
            self.assertAlmostEqual(g, f*factor, delta=1e-8)
            self.assertAlmostEqual(h, s*factor, delta=1e-8)
            self.assertAlmostEqual(skid2, skid, delta=1e-12)

    def test_production_wiring_and_inspector_properties(self):
        cpp = (ROOT/"scene/3d/physics/vehicle_body_3d.cpp").read_text()
        header = (ROOT/"scene/3d/physics/vehicle_body_3d.h").read_text()
        helper = (ROOT/"servers/physics_vehicle_combined_tire_grip.h").read_text()
        docs = (ROOT/"doc/classes/VehicleWheel3D.xml").read_text()
        self.assertIn('#include "servers/physics_vehicle_combined_tire_grip.h"', cpp)
        self.assertEqual(cpp.count("physics_vehicle_project_combined_tire_impulses("), 1)
        self.assertIn("double(wheelInfo.m_wheelsSuspensionForce) * double(s->get_step())", cpp)
        self.assertIn("double(wheelInfo.m_longitudinalGrip)", cpp)
        self.assertIn("double(wheelInfo.m_lateralGrip)", cpp)
        self.assertIn("m_forwardImpulse.write[wheel] = real_t(next_forward);", cpp)
        self.assertIn("m_sideImpulse.write[wheel] = real_t(next_side);", cpp)
        self.assertIn("wheelInfo.m_skidInfo = real_t(next_skid);", cpp)
        self.assertNotIn("bool sliding = false;", cpp)
        self.assertNotIn("if (wheels[wheel]->m_skidInfo < real_t(1.))", cpp)
        self.assertIn("real_t m_longitudinalGrip = 1.0;", header)
        self.assertIn("real_t m_lateralGrip = 1.0;", header)
        self.assertIn('ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "wheel_longitudinal_grip"', cpp)
        self.assertIn('ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "wheel_lateral_grip"', cpp)
        self.assertIn('member name="wheel_longitudinal_grip"', docs)
        self.assertIn('member name="wheel_lateral_grip"', docs)
        self.assertIn("std::hypot(normalized_forward, normalized_side)", helper)


if __name__ == "__main__":
    unittest.main()
