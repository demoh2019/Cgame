"""Independent hydrostatic reference for arbitrarily tilted cylinders.

The native C++ solver integrates circular segments analytically. This
reference uses composite Simpson quadrature of submerged disk area and its
TWO first moments along the cylinder axis. No external dependencies.
"""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def disk_area(t):
    if t <= -1:
        return 0.0
    if t >= 1:
        return math.pi
    q = math.sqrt(max(0., 1. - t*t))
    return math.acos(-t) + t*q


def disk_moment(t):
    if t <= -1 or t >= 1:
        return 0.0
    return -(2. / 3.) * max(0., 1.-t*t) ** 1.5


def primitives(t):
    t = min(1., max(-1., t))
    q = math.sqrt(max(0., 1. - t*t))
    arcsin = math.asin(t)
    return (
        math.pi*t/2 + t*arcsin + q - q**3/3,
        math.pi*t*t/4 + (4*t*t-1)*arcsin/8 + t*q*(1+2*t*t)/8,
        -(3*arcsin+t*q*(5-2*t*t))/12,
    )


def analytic(half_length, ay, level):
    """Dimensionless submerged V and axial/transverse moments."""
    beta = math.sqrt(max(0., 1.-ay*ay))
    reach = abs(ay)*half_length+beta
    if level <= -reach:
        return (0., 0., 0.)
    if level >= reach:
        return (2*math.pi*half_length, 0., 0.)
    if beta <= 1e-8:
        crossing = level/ay
        start = -half_length if ay>0 else max(-half_length,crossing)
        stop = min(half_length,crossing) if ay>0 else half_length
        return (math.pi*(stop-start), math.pi*(stop-start)*(start+stop)/2, 0.)
    if ay == 0.:
        return (2*half_length*disk_area(level/beta), 0.,
                2*half_length*disk_moment(level/beta))
    if (abs(ay)*half_length <= 1e-6*beta and abs(level/beta) <= .95):
        t = level/beta
        return (2*half_length*disk_area(t),
                -(ay/beta)*(4/3)*half_length**3*math.sqrt(1-t*t),
                2*half_length*disk_moment(t))
    cuts = [-half_length, half_length]
    for t in (-1., 1.):
        axial = (level-beta*t)/ay
        if -half_length < axial < half_length:
            cuts.append(axial)
    cuts.sort()
    v, axial, trans = 0., 0., 0.
    for low, high in zip(cuts, cuts[1:]):
        mid = (low+high)/2
        t = (level-ay*mid)/beta
        if t >= 1.:
            v += math.pi*(high-low)
            axial += math.pi*(high-low)*mid
        elif t > -1.:
            p = primitives((level-ay*low)/beta)
            q = primitives((level-ay*high)/beta)
            delta_area = q[0]-p[0]
            factor = -beta/ay
            v += factor*delta_area
            axial += factor/ay*(level*delta_area-beta*(q[1]-p[1]))
            trans += factor*(q[2]-p[2])
    return v, axial, trans


def reference(half_length, ay, level, intervals=256):
    """Independent area integration, explicitly split at full/dry boundaries."""
    beta = math.sqrt(max(0., 1.-ay*ay))
    cuts = [-half_length, half_length]
    if ay != 0.:
        for t in (-1., 1.):
            a = (level-beta*t)/ay
            if -half_length < a < half_length:
                cuts.append(a)
    cuts.sort()
    total = [0., 0., 0.]
    for low, high in zip(cuts, cuts[1:]):
        step = (high-low)/intervals
        sums = [0., 0., 0.]
        for i in range(intervals+1):
            axial = low+i*step
            u = ((level-ay*axial)/beta if beta else
                 (1. if level >= ay*axial else -1.))
            area = disk_area(u)
            moment = disk_moment(u)
            weight = (1 if i in (0, intervals) else 4 if i%2 else 2)
            for j, value in enumerate((area, axial*area, moment)):
                sums[j] += value*weight
        for j in range(3):
            total[j] += sums[j]*step/3
    return tuple(total)


class CylinderFluidHydrostatics(unittest.TestCase):
    def test_exact_vertical_and_horizontal_caps(self):
        # Radius one, height four -> half_length=2.
        upright = analytic(2., 1., -1.)
        self.assertAlmostEqual(upright[0], math.pi)
        self.assertAlmostEqual(upright[1]/upright[0], -1.5)
        horizontal = analytic(2., 0., 0.)
        self.assertAlmostEqual(horizontal[0], 2*math.pi)
        self.assertAlmostEqual(horizontal[1], 0.)
        self.assertAlmostEqual(horizontal[2]/horizontal[0], -4/(3*math.pi))

    def test_antiderivatives_match_direct_segment_integrals(self):
        rng = random.Random(20261119)
        for _ in range(2000):
            left, right = sorted((rng.uniform(-1.,1.), rng.uniform(-1.,1.)))
            if right == left:
                continue
            n = 128
            dx = (right-left)/n
            sums = [0.,0.,0.]
            for k in range(n+1):
                t=left+dx*k
                w=1 if k in (0,n) else 4 if k%2 else 2
                for j,value in enumerate((disk_area(t),t*disk_area(t),disk_moment(t))):
                    sums[j] += w*value
            integral = tuple(x*dx/3 for x in sums)
            a,b=primitives(left),primitives(right)
            for i in range(3):
                self.assertAlmostEqual(integral[i],b[i]-a[i],delta=2e-6)

    def test_1200_random_orientations_against_independent_axial_quadrature(self):
        rng = random.Random(17019)
        max_relative_error = 0.
        for _ in range(1200):
            half_length = 10 ** rng.uniform(-1.5, 3.5)
            ay = rng.uniform(-.999, .999)
            beta = math.sqrt(1-ay*ay)
            level = (abs(ay)*half_length+beta)*rng.uniform(-.98,.98)
            exact = analytic(half_length,ay,level)
            numerical = reference(half_length,ay,level)
            for a,b in zip(exact,numerical):
                relative = abs(a-b)/(1+abs(b))
                max_relative_error = max(max_relative_error,relative)
                self.assertLess(relative, 2e-6)
        self.assertLess(max_relative_error, 2e-6)

    def test_almost_horizontal_extremely_long_cylinder_keeps_axial_torque(self):
        # A naive 'horizontal' early exit would set this first moment to
        # zero. The tiny tilt times a million-radius axial lever matters.
        length = 1e6
        ay = 1e-12
        integral = analytic(length, ay, .1)
        self.assertGreater(integral[0], 0.)
        centroid_axial = integral[1]/integral[0]
        self.assertLess(centroid_axial, -.25)
        self.assertGreater(centroid_axial, -.50)
        reference_values = reference(length, ay, .1, intervals=512)
        self.assertAlmostEqual(centroid_axial,
                               reference_values[1]/reference_values[0],
                               delta=2e-4)

    def test_symmetry_axis_reversal_and_monotonic_volume(self):
        rng = random.Random(9182)
        for _ in range(800):
            L = 10**rng.uniform(-.5, 2.)
            ay = rng.uniform(-.999,.999)
            reach = abs(ay)*L+math.sqrt(1-ay*ay)
            h = reach*rng.uniform(-.95,.95)
            p=analytic(L,ay,h)
            q=analytic(L,ay,-h)
            reverse=analytic(L,-ay,h)
            self.assertAlmostEqual(p[0]+q[0],2*math.pi*L,delta=1e-7*(1+L))
            self.assertAlmostEqual(p[1]-q[1],0.,delta=1e-7*(1+L*L))
            self.assertAlmostEqual(p[2]-q[2],0.,delta=1e-7*(1+L))
            self.assertAlmostEqual(p[0],reverse[0],delta=1e-7*(1+L))
            self.assertAlmostEqual(p[1],-reverse[1],delta=1e-7*(1+L*L))
            self.assertAlmostEqual(p[2],reverse[2],delta=1e-7*(1+L))

    def test_cpp_integration_preserves_old_fallback_and_no_allocations(self):
        header=(ROOT/"servers/physics_fluid_cylinder_3d.h").read_text()
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn("godot_physics_fluid_cylinder_disk_antiderivatives_3d(",header)
        self.assertIn("godot_physics_fluid_cylinder_sample_3d(",header)
        self.assertIn("last.axial_area - first.axial_area",header)
        self.assertIn("last.transverse_moment - first.transverse_moment",header)
        self.assertIn("double cuts[4]",header)
        self.assertIn("const double max_wet = Math::PI * 2.0 * half_length;",header)
        self.assertIn("const Vector3 center(",header)
        self.assertIn("r_sample.center_of_buoyancy = center;",header)
        self.assertNotIn("memalloc",header)
        self.assertNotIn("new ",header)
        self.assertIn('#include "servers/physics_fluid_cylinder_3d.h"',body)
        self.assertIn("PS3DE::SHAPE_CYLINDER",body)
        self.assertIn("godot_physics_fluid_uniform_scale_3d(shape_world.basis, cylinder_scale)",body)
        self.assertIn("cylinder->get_radius() * cylinder_scale",body)
        self.assertIn("cylinder_total_volume - shape_volume",body)
        self.assertIn("sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);",body)
        self.assertIn("torque += lever.cross(lift + drag);",body)

    def test_native_headless_and_ci_registration(self):
        native=(ROOT/"tests/servers/test_physics_fluid_cylinder_3d.cpp").read_text()
        scene=(ROOT/"tests/stress/physics_cylinder_buoyancy_3d_regression.gd").read_text()
        ci=(ROOT/".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_fluid_cylinder_3d)",native)
        self.assertEqual(native.count('TEST_CASE("[PhysicsCylinderFluid]'),9)
        self.assertIn("PhysicsServer3D.cylinder_shape_create()",scene)
        self.assertIn("cylinder_sinks",scene)
        self.assertIn("tilt_torque",scene)
        self.assertIn("*[PhysicsCylinderFluid]*",ci)
        self.assertIn("physics_cylinder_buoyancy_3d_regression.gd",ci)


if __name__ == "__main__":
    unittest.main()
