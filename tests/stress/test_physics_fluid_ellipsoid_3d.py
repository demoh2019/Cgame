"""Independent analytic-vs-quadrature contracts for ellipsoid fluid immersion.

A sphere under an arbitrary nonsingular affine transform is an ellipsoid.
We integrate unit-ball cross sections with Simpson's rule, independently of
the transformed spherical-cap formula used by the C++ implementation.
"""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_fluid_ellipsoid_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_fluid_ellipsoid_3d.cpp"
ENGINE = ROOT / "tests/stress/physics_ellipsoid_buoyancy_3d_regression.gd"


def mat_vec(B, u):
    return tuple(sum(B[i][k] * u[k] for k in range(3)) for i in range(3))


def determinant(B):
    a,b,c = B
    return (a[0]*(b[1]*c[2]-b[2]*c[1])
            - a[1]*(b[0]*c[2]-b[2]*c[0])
            + a[2]*(b[0]*c[1]-b[1]*c[0]))


def analytic(B, radius, center, waterline):
    # B is row-major: x_world=center+B*x_local
    g = B[1]
    g2 = sum(x*x for x in g)
    H = radius * math.sqrt(g2)
    full = (4*math.pi/3) * radius**3 * abs(determinant(B))
    t = max(0.0, min(2.0, 1+(waterline-center[1])/H))
    f = t*t*(3-t)/4
    if not f:
        return full, 0., None
    dy = -.75*H*(2-t)**2/(3-t)
    offset = mat_vec(B, tuple(v/g2*dy for v in g))
    return full, f, tuple(a+b for a,b in zip(center,offset))


def independent_quadrature(B, radius, center, waterline, intervals=512):
    """Direct integration of unit-ball cross-section area and axial moment."""
    g = B[1]
    g_len = math.sqrt(sum(z*z for z in g))
    upper = max(-1.0, min(1.0, (waterline-center[1])/(radius*g_len)))
    step = (upper+1.0)/intervals
    if not step:
        return 0.0, None
    integral0 = 0.0
    integral1 = 0.0
    for i in range(intervals+1):
        z = -1+i*step
        weight = 1 if i in (0, intervals) else 4 if i%2 else 2
        area = (1-z*z)
        integral0 += weight*area
        integral1 += weight*z*area
    integral0 *= step/3
    integral1 *= step/3
    fraction = integral0/(4/3)
    if not fraction:
        return 0., None
    centroid_u = tuple((q/g_len)*(integral1/integral0) for q in g)
    displacement = mat_vec(B, centroid_u)
    return fraction, tuple(x+radius*d for x,d in zip(center,displacement))


class ExactEllipsoidBuoyancyTests(unittest.TestCase):
    def test_nonuniform_ellipsoid_has_same_fraction_as_unit_sphere(self):
        B = ((2.,0.,0.),(0.,1.,0.),(0.,0.,.5))
        total, frac, center = analytic(B, 1., (2.,0.,-3.), -.5)
        self.assertAlmostEqual(total, 4*math.pi/3)
        self.assertAlmostEqual(frac, .15625)
        self.assertAlmostEqual(center[1], -.675)
        self.assertAlmostEqual(center[0], 2.)

    def test_rotated_and_sheared_lateral_hydrostatic_torque(self):
        B = ((1., .8, 0.),(0.,1.,0.),(0.,0.,1.))
        _, frac, center = analytic(B, 1., (0.,0.,0.), 0.)
        self.assertAlmostEqual(frac, 0.5)
        self.assertAlmostEqual(center[0], -.3)
        self.assertAlmostEqual(center[1], -.375)
        # A vertical upward force acting left of the center creates -Z torque.
        self.assertLess(center[0], 0.)

    def test_randomized_affine_caps_against_independent_quadrature(self):
        rng = random.Random(20261119)
        for _ in range(1000):
            theta = rng.uniform(-3, 3)
            co, si = math.cos(theta), math.sin(theta)
            sx, sy, sz = (rng.uniform(.2, 4) for _ in range(3))
            shear = rng.uniform(-.9, .9)
            B = (
                (sx*co, -sy*si + shear*co, 0.),
                (sx*si, sy*co + shear*si, 0.),
                (0., 0., sz)
            )
            radius = rng.uniform(.1, 3.)
            center = (rng.uniform(-10, 10),rng.uniform(-10, 10),rng.uniform(-10, 10))
            H = radius*math.sqrt(sum(z*z for z in B[1]))
            water = center[1]+rng.uniform(-.9, .9)*H
            full, f, analytical_center = analytic(B,radius,center,water)
            reference_f, reference_center = independent_quadrature(
                B,radius,center,water,intervals=512)
            self.assertGreater(full, 0)
            self.assertAlmostEqual(f, reference_f, delta=2e-6)
            for x,y in zip(analytical_center,reference_center):
                self.assertAlmostEqual(x,y,delta=3e-5*max(1.,radius))

    def test_signed_reflection_complementary_waterline_and_translation(self):
        rng = random.Random(912)
        for _ in range(250):
            sx = -rng.uniform(.5,3.)
            sy = rng.uniform(.5,3.)
            B=((sx,.3,0.),(0.,sy,0.),(0.,0.,1.))
            radius = rng.uniform(.2,2.)
            center = (rng.uniform(-5,5),rng.uniform(-5,5),rng.uniform(-5,5))
            water_delta = rng.uniform(-.75,.75)*sy*radius
            tot_plus,fp,cp=analytic(B,radius,center,center[1]+water_delta)
            tot_minus,fm,cm=analytic(B,radius,center,center[1]-water_delta)
            self.assertGreater(tot_plus,0.)
            self.assertAlmostEqual(tot_plus,tot_minus)
            self.assertAlmostEqual(fp+fm,1.,delta=1e-12)
            for i in range(3):
                self.assertAlmostEqual(
                    fp*(cp[i]-center[i])-fm*(cm[i]-center[i]),0.,delta=1e-12)

    def test_source_uses_wide_affine_cap_and_exact_volume_integration(self):
        h=HEADER.read_text()
        src=BODY.read_text()
        self.assertIn('#include "core/math/transform_3d.h"',h)
        self.assertIn("godot_physics_fluid_affine_ellipsoid_sample_3d(",h)
        self.assertIn("double(p_local_radius)",h)
        self.assertIn("const double vertical_squared",h)
        self.assertIn("const double determinant",h)
        self.assertIn("radius * radius * radius * Math::abs(determinant)",h)
        self.assertIn("const double fraction = t * t * (3.0 - t) * 0.25;",h)
        self.assertIn("const double delta_y",h)
        self.assertIn("const double response_x",h)
        self.assertIn("if (!Math::is_finite(submerged_volume)",h)
        self.assertIn('#include "servers/physics_fluid_ellipsoid_3d.h"',src)
        self.assertIn("} else if (shape_type == PS3DE::SHAPE_SPHERE) {",src)
        self.assertIn("ellipsoid_total_volume - shape_volume",src)
        self.assertIn("sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);",src)
        self.assertIn("torque += lever.cross(lift + drag)",src)
        self.assertNotIn("memalloc",h)

    def test_native_and_runtime_covered_by_ci(self):
        n=NATIVE.read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_fluid_ellipsoid_3d)",n)
        self.assertEqual(n.count('TEST_CASE("[PhysicsEllipsoid]'),8)
        sc=ENGINE.read_text()
        self.assertIn("body_add_shape",sc)
        self.assertIn("ellipsoid_sinks",sc)
        wf=(ROOT/".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("*[PhysicsEllipsoid]*",wf)
        self.assertIn("physics_ellipsoid_buoyancy_3d_regression.gd",wf)
        stress = (ROOT / "tests/stress/physics_ellipsoid_fluid_stress.gd").read_text()
        cases = (ROOT / "tests/stress/run.py").read_text()
        runner = (ROOT / "tests/stress/stress.gd").read_text()
        self.assertIn("PhysicsServer3D.body_add_shape(body, sphere,", stress)
        self.assertIn("Performance.TIME_PHYSICS_PROCESS", stress)
        self.assertIn("frame_p95_ms", stress)
        self.assertIn('"physics_ellipsoid_fluid_3d_disabled"', cases)
        self.assertIn('"physics_ellipsoid_fluid_3d_enabled"', cases)
        self.assertIn("const EllipsoidFluidStress := preload(", runner)
        self.assertIn("EllipsoidFluidStress.new().run(self, scale, frames, true)", runner)


if __name__ == "__main__":
    unittest.main()
