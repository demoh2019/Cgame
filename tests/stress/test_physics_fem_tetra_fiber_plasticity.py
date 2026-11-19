"""Independent numerical reference for tetra FEM fiber tensile plasticity.

An undeformed material direction a0 is convected by the deformation
gradient F. When |F*a0| exceeds the irreversible fiber rest stretch times
(1+yield), the rest stretch creeps towards the corresponding new
zero-tension reference. Pure rigid rotation/translation never causes
plasticity. This reference does not replace native C++ scene testing.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def measure_stretch(f, axis):
    length = math.sqrt(sum(a*a for a in axis))
    if length <= 0:
        return None
    u = [a/length for a in axis]
    transformed = [sum(f[row][col]*u[col] for col in range(3))
                   for row in range(3)]
    return math.sqrt(sum(v*v for v in transformed))


def plastic_step(current, old, yield_ratio, creep_rate, dt, cap):
    if (not math.isfinite(current) or not math.isfinite(old) or
            current <= old*(1+yield_ratio) or creep_rate <= 0 or
            dt <= 0 or not 1 <= old <= cap <= 16):
        return old
    target = min(cap, current/(1+yield_ratio))
    return min(cap, old + (target-old)*(1-math.exp(-creep_rate*dt)))


def rotate_world_z(f, angle):
    c, s = math.cos(angle), math.sin(angle)
    rotation = ((c, -s, 0), (s, c, 0), (0, 0, 1))
    return [[sum(rotation[i][k]*f[k][j] for k in range(3))
             for j in range(3)] for i in range(3)]


def xpbd_fiber_length_after_projection(length, inv_mass_a, inv_mass_b,
                                       rest_stretch, alpha):
    # Unit-reference tetra and +X fiber: gradient ±sqrt(V) and
    # C=sqrt(V)*(plastic_rest-stretch). A single XPBD projection.
    v = 1./6.
    w = math.sqrt(v)
    mass = (inv_mass_a + inv_mass_b)*v
    impulse = max(0., (length-rest_stretch)*w/(mass+alpha))
    return length-(inv_mass_a+inv_mass_b)*w*impulse


class FEMTetraFiberPlasticityReference(unittest.TestCase):
    def test_6000_objective_material_stretch_and_yield(self):
        rng = random.Random(0xF1B3A5)
        for _ in range(6000):
            sx, sy, sz = [rng.uniform(.6, 2.2) for _ in range(3)]
            shear = rng.uniform(-.7, .7)
            f = ((sx, shear, 0), (0, sy, 0), (0, 0, sz))
            theta = rng.uniform(-math.pi, math.pi)
            material_axis = (rng.uniform(-2, 2),
                             rng.uniform(-2, 2),
                             rng.uniform(-2, 2))
            s = measure_stretch(f, material_axis)
            rotated_s = measure_stretch(rotate_world_z(f, theta),
                                        material_axis)
            self.assertAlmostEqual(s, rotated_s, delta=1e-12)
            rest = rng.uniform(1, 1.5)
            yield_ratio = rng.uniform(0, .3)
            creep = rng.uniform(.1, 25)
            dt = rng.uniform(.001, .1)
            cap = rng.uniform(1.5, 4)
            next_rest = plastic_step(s, rest, yield_ratio, creep, dt, cap)
            self.assertGreaterEqual(next_rest, rest-1e-12)
            self.assertLessEqual(next_rest, cap+1e-12)
            if s <= rest*(1+yield_ratio):
                self.assertEqual(next_rest, rest)

    def test_3000_plastic_history_timestep_invariance(self):
        rng = random.Random(0xA5E09)
        for _ in range(3000):
            current = rng.uniform(1.2, 5)
            yield_ratio = rng.uniform(0, .1)
            rate = rng.uniform(.1, 20)
            dt = rng.uniform(.01, 1)
            cap = rng.uniform(2, 8)
            one_step = plastic_step(current, 1., yield_ratio, rate, dt, cap)
            subdivided = 1.
            for _ in range(20):
                subdivided = plastic_step(current, subdivided, yield_ratio,
                                          rate, dt/20, cap)
            self.assertAlmostEqual(one_step, subdivided, delta=1e-12)

    def test_3000_stable_xpbd_plastic_projection_and_momentum(self):
        rng = random.Random(0xFEED24)
        for _ in range(3000):
            length = rng.uniform(1.01, 2.4)
            rest = rng.uniform(1, min(length, 2))
            im_a, im_b = rng.uniform(.1, 5), rng.uniform(.1, 5)
            alpha = rng.uniform(1e-8, .1)
            elastic = xpbd_fiber_length_after_projection(
                length, im_a, im_b, 1., alpha)
            plastic = xpbd_fiber_length_after_projection(
                length, im_a, im_b, rest, alpha)
            self.assertGreaterEqual(plastic+1e-12, elastic)
            self.assertLessEqual(plastic, length+1e-12)
            self.assertGreaterEqual(plastic+1e-12, rest)
            grad = math.sqrt(1./6.)
            lam = max(0., (length-rest)*grad/
                      ((im_a+im_b)/6.+alpha))
            da, db = im_a*grad*lam, -im_b*grad*lam
            self.assertAlmostEqual(da/im_a + db/im_b, 0., delta=1e-12)

    def test_compression_shear_and_consecutive_tensile_yield(self):
        self.assertEqual(plastic_step(.8, 1., .15, 5., .02, 3.), 1.)
        self.assertEqual(plastic_step(1.12, 1., .15, 5., .02, 3.), 1.)
        first = plastic_step(1.8, 1., .1, 8., .05, 2.5)
        self.assertGreater(first, 1.)
        self.assertEqual(plastic_step(first*1.05, first, .1, 8., .05, 2.5), first)
        self.assertGreater(plastic_step(2., first, .1, 8., .05, 2.5), first)
        transversely_stretched = ((1, 0, 0), (0, 1.7, 0), (0, 0, 1))
        self.assertAlmostEqual(measure_stretch(transversely_stretched, (1, 0, 0)), 1.)

    def test_config_lifecycle_and_original_solver_compatibility(self):
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_fiber_plasticity.h").read_text()
        fiber = (ROOT/"servers/physics_fem_tetra_fiber.h").read_text()
        self.assertIn('soft_body_tetra_fiber_plastic_creep_rate", PROPERTY_HINT_RANGE', server)
        self.assertIn('soft_body_tetra_fiber_plastic_creep_rate = 0.0;', space_h)
        self.assertIn('soft_body_tetra_fiber_plastic_creep_rate = Math::is_finite(', space_cpp)
        self.assertIn('LocalVector<real_t> xpbd_fem_fiber_plastic_rest_stretches;', body_h)
        self.assertIn('xpbd_fem_fiber_plastic_rest_stretches.resize(', body)
        self.assertIn('xpbd_fem_fiber_plastic_rest_stretches.reset();', body)
        self.assertIn('physics_fem_tetra_fiber_measure_stretch(', body)
        self.assertIn('physics_fem_tetra_fiber_creep_rest_stretch(', body)
        self.assertIn('double(plastic_rest_stretch));', body)
        self.assertIn('p_plastic_rest_stretch = 1.0)', fiber)
        self.assertIn('p_plastic_rest_stretch - stretch', fiber)
        self.assertIn('const double fraction = 1.0 - Math::exp(-p_creep_rate * p_delta)', helper)
        self.assertLess(body.index('physics_fem_tetra_fiber_creep_rest_stretch('),
                        body.index('for (int isolve = 0; isolve < iteration_count; ++isolve)'))


if __name__ == "__main__":
    unittest.main()
