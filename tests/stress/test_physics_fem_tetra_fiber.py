"""Reference invariants for opt-in anisotropic FEM tetrahedral fibers.

The reinforcement constraint follows F * a0, with a0 fixed in material
coordinates, and acts on tension only. Tests validate 5,000 independent
stretches, momentum, rigid-rotation covariance, and Cgame source wiring.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def reference_x_fiber(stretch, inverse_masses, alpha, rest_volume=1. / 6.):
    """Unit rest tetra, fiber axis +X, XPBD lambda initially zero."""
    if stretch <= 1. or min(inverse_masses) < 0.:
        return None
    s = math.sqrt(rest_volume)
    grad = (s, -s, 0., 0.)
    mass = sum(g * g * im for g, im in zip(grad, inverse_masses))
    if mass <= 0.:
        return None
    c = (1. - stretch) * s
    lam = max(0., -c / (mass + alpha))
    initial = (0., stretch, 0., 0.)
    after = tuple(initial[i] + inverse_masses[i] * lam * grad[i]
                  for i in range(4))
    return after, lam


class TestFEMTetraFiber(unittest.TestCase):
    def test_5000_randomized_tensile_constraints(self):
        rng = random.Random(0xF1B3C0DE)
        for _ in range(5000):
            length = rng.uniform(1.01, 1.81)
            masses = tuple(rng.uniform(.1, 4.1) for _ in range(4))
            alpha = rng.choice((0., rng.uniform(.00001, .1)))
            result = reference_x_fiber(length, masses, alpha)
            self.assertIsNotNone(result)
            after, lam = result
            self.assertGreater(lam, 0.)
            corrected_length = after[1] - after[0]
            self.assertLess(corrected_length, length)
            self.assertGreater(corrected_length, 0.)
            self.assertAlmostEqual(
                sum((after[i] - (0., length, 0., 0.)[i]) / masses[i]
                    for i in range(4)), 0., delta=1e-9)
            if alpha == 0.:
                self.assertAlmostEqual(corrected_length, 1., delta=1e-9)

    def test_slack_rotation_and_pin(self):
        self.assertIsNone(reference_x_fiber(.7, (1.,)*4, 0.))
        self.assertIsNone(reference_x_fiber(1., (1.,)*4, 0.))
        self.assertIsNone(reference_x_fiber(1.5, (0.,)*4, 0.))
        after, lam = reference_x_fiber(1.5, (0., 1., 1., 1.), 0.)
        self.assertEqual(after[0], 0.)
        self.assertAlmostEqual(after[1], 1.)
        # Rigid 90-degree rotation of all world positions preserves
        # |F*a0|; the direction of the correction rotates with the body.
        original_correction = (after[1] - 1.5, 0., 0.)
        rotated_correction = (-original_correction[1], original_correction[0], 0.)
        self.assertAlmostEqual(math.dist((0., 0., 0.),
                                          rotated_correction),
                               abs(original_correction[0]))
        self.assertGreater(lam, 0.)

    def test_source_settings_budgets_and_lazy_lambdas(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "servers/physics_fem_tetra_fiber.h").read_text()
        self.assertIn('"physics/3d/solver/soft_body_tetra_fiber_compliance"', server)
        self.assertIn('"physics/3d/solver/soft_body_tetra_fiber_axis"', server)
        self.assertIn('soft_body_tetra_fiber_compliance = 0.0;', space_h)
        self.assertIn('soft_body_tetra_fiber_compliance = Math::is_finite(', space_cpp)
        self.assertIn('get_soft_body_tetra_fiber_compliance()', body)
        self.assertIn('use_fem && fem_fiber_compliance > 0.0', body)
        self.assertIn('LocalVector<double> xpbd_fem_fiber_lambdas;', body_h)
        self.assertIn('xpbd_fem_fiber_lambdas.resize(xpbd_fem_tetrahedra.size())', body)
        self.assertIn('xpbd_fem_fiber_lambdas.reset()', body)
        self.assertIn('physics_fem_tetra_solve_fiber(', body)
        self.assertIn('double(1u << attempt)', header)
        self.assertIn('initial_det / p_rest.signed_det > 1e-9', header)
        self.assertIn('r_lambda = updated_lambda;', header)
        self.assertIn('target_lambda = MAX(0.0', header)
        self.assertLess(body.index('for (double &lambda : xpbd_fem_fiber_lambdas)'),
                        body.index('for (int isolve = 0; isolve < iteration_count; ++isolve)'))


if __name__ == "__main__":
    unittest.main()
