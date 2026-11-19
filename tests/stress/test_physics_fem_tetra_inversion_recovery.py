"""Reference contracts for opt-in XPBD tetrahedron inversion recovery."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def sub(a, b):
    return tuple(a[i]-b[i] for i in range(3))


def jacobian_and_grad(x, rest_det=1.):
    u, v, w = (sub(x[i], x[0]) for i in (1, 2, 3))
    gb, gc, gd = (tuple(c/rest_det for c in cross(a, b))
                  for a, b in ((v, w), (w, u), (u, v)))
    ga = tuple(-(gb[k]+gc[k]+gd[k]) for k in range(3))
    return dot(u, cross(v, w))/rest_det, (ga, gb, gc, gd)


def recover(points, inv_masses, threshold=.05, rest_det=1.):
    x = [tuple(p) for p in points]
    if not .001 <= threshold <= .5 or not any(w > 0 for w in inv_masses):
        return False, x
    progressed = False
    for _ in range(8):
        j, g = jacobian_and_grad(x, rest_det)
        if j >= threshold:
            break
        k = sum(w*dot(gi, gi) for w, gi in zip(inv_masses, g))
        if not k > 0 or not math.isfinite(k):
            break
        correction = (threshold-j)/k
        accepted = False
        for attempt in range(12):
            step = correction/(2**attempt)
            candidate = [tuple(p[a]+step*w*gi[a] for a in range(3))
                         for p, gi, w in zip(x, g, inv_masses)]
            new_j, _ = jacobian_and_grad(candidate, rest_det)
            if math.isfinite(new_j) and j+1e-12 < new_j <= 1.+1e-9:
                x = candidate
                progressed = accepted = True
                break
        if not accepted:
            break
    return progressed, x


class TestInvertedTetraRecovery(unittest.TestCase):
    def test_randomized_inverted_tetrahedra_and_pins(self):
        rng = random.Random(0xC0FFEE)
        passed = 0
        for _ in range(10000):
            x = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.),
                 (rng.uniform(-2., 2.), rng.uniform(-2., 2.), -rng.uniform(.01, 1.8))]
            w = [0. if rng.random()<.3 else rng.uniform(.1, 3.) for i in range(4)]
            if not any(w):
                continue
            old_j, _ = jacobian_and_grad(x)
            ok, result = recover(x, w)
            new_j, _ = jacobian_and_grad(result)
            self.assertTrue(ok)
            self.assertGreater(new_j, old_j)
            self.assertGreaterEqual(new_j, .05 - 1e-6)
            self.assertLessEqual(new_j, 1+1e-9)
            for i in range(4):
                if w[i] == 0:
                    self.assertEqual(result[i], x[i])
            passed += 1
        self.assertGreater(passed, 9800)

    def test_rest_winding_and_scale(self):
        for scale in (1e-3, 1., 1e3):
            for direction in (-1., 1.):
                x = [(0., 0., 0.), (scale, 0., 0.), (0., scale, 0.),
                     (0., 0., -direction*scale)]
                ok, after = recover(x, (0, 0, 0, 1), rest_det=direction*scale**3)
                j, _ = jacobian_and_grad(after, direction*scale**3)
                self.assertTrue(ok)
                self.assertAlmostEqual(j, .05, delta=1e-6)

    def test_atomic_noop_on_valid_and_pinned(self):
        valid = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.)]
        inverted = valid[:3] + [(0., 0., -1.)]
        self.assertFalse(recover(valid, (1, 1, 1, 1))[0])
        self.assertEqual(recover(valid, (1, 1, 1, 1))[1], valid)
        self.assertFalse(recover(inverted, (0, 0, 0, 0))[0])
        self.assertEqual(recover(inverted, (0, 0, 0, 0))[1], inverted)

    def test_volume_gradient_translation_invariance(self):
        rng = random.Random(0xD0C0)
        for _ in range(2000):
            pts = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.),
                   (rng.uniform(-2, 2), rng.uniform(-2, 2), rng.uniform(-2, 2))]
            j, gradients = jacobian_and_grad(pts)
            self.assertTrue(math.isfinite(j))
            self.assertTrue(all(abs(sum(g[a] for g in gradients)) < 1e-12
                                for a in range(3)))

    def test_cgame_source_integration_and_default_off(self):
        cpp = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        sh = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_inversion_recovery.h").read_text()
        self.assertIn("physics_fem_tetra_recover_orientation(", helper)
        self.assertEqual(cpp.count("physics_fem_tetra_recover_orientation("), 1)
        self.assertIn("if (use_fem_inversion_recovery) {", cpp)
        self.assertIn("const bool use_fem_inversion_recovery = use_fem &&", cpp)
        self.assertIn("is_soft_body_tetra_inversion_recovery_enabled()", cpp)
        self.assertIn("get_soft_body_tetra_inversion_min_j()", cpp)
        self.assertIn("bool soft_body_tetra_inversion_recovery = false;", sh)
        self.assertIn('"physics/3d/solver/soft_body_tetra_inversion_recovery"', server)
        self.assertIn('"physics/3d/solver/soft_body_tetra_inversion_min_j"', server)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_tetra_inversion_recovery")', space)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_tetra_inversion_min_j")', space)
        self.assertLess(cpp.index("physics_fem_tetra_recover_orientation(a.x, b.x, c.x, d.x,"),
                        cpp.index("tetra.rest, fem_poisson, local_alpha, tetra.lambda);"))


if __name__ == "__main__":
    unittest.main()
