"""Independent numerical reference for closed-surface XPBD total-volume projection.

Run: python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_volume_numeric.py' -v
This does not replace compiling or running the GodotPhysics native C++ tests.
"""
import math
import unittest

FACES = ((0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3))


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def signed_volume_gradients(vertices):
    origin = vertices[0]
    grad = [[0.0, 0.0, 0.0] for _ in vertices]
    volume = 0.0
    for i, j, k in FACES:
        a = sub(vertices[i], origin)
        b = sub(vertices[j], origin)
        c = sub(vertices[k], origin)
        volume += dot(a, cross(b, c)) / 6.0
        ga, gb, gc = cross(b, c), cross(c, a), cross(a, b)
        for index, term in ((i, ga), (j, gb), (k, gc)):
            for n in range(3):
                grad[index][n] += term[n] / 6.0
    return volume, grad


def edge_manifold(faces):
    uses = {}
    for face in faces:
        for i in range(3):
            a, b = face[i], face[(i + 1) % 3]
            if a == b:
                return False
            key = (min(a, b), max(a, b))
            uses.setdefault(key, []).append(1 if a < b else -1)
    return bool(uses) and all(len(winding) == 2 and sum(winding) == 0 for winding in uses.values())


def solve_volume(vertices, inverse_masses, target, compliance, lam):
    volume, gradients = signed_volume_gradients(vertices)
    weight = sum(
        w * dot(g, g) for w, g in zip(inverse_masses, gradients)
    )
    if weight <= 0:
        return vertices, lam, False
    dl = -(volume - target + compliance * lam) / (weight + compliance)
    next_positions = [
        tuple(v[n] + w * dl * g[n] for n in range(3))
        for v, w, g in zip(vertices, inverse_masses, gradients)
    ]
    return next_positions, lam + dl, True


class XPBDClosedVolumeNumerics(unittest.TestCase):
    def setUp(self):
        self.tetra = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.)]

    def test_closed_tetra_has_oriented_manifold_and_open_or_flipped_do_not(self):
        self.assertTrue(edge_manifold(FACES))
        self.assertFalse(edge_manifold(FACES[:-1]))
        flipped = list(FACES)
        flipped[2] = flipped[2][::-1]
        self.assertFalse(edge_manifold(flipped))

    def test_rest_volume_and_analytic_gradient_translation_invariant(self):
        volume, gradient = signed_volume_gradients(self.tetra)
        self.assertAlmostEqual(volume, 1. / 6., places=13)
        for j in range(3):
            self.assertAlmostEqual(sum(g[j] for g in gradient), 0.0, places=12)
        shifted = [tuple(v[j] + (1000., -2000., 3000.)[j] for j in range(3))
                   for v in self.tetra]
        self.assertAlmostEqual(signed_volume_gradients(shifted)[0], volume, places=12)

    def test_gradient_matches_finite_difference(self):
        base, gradient = signed_volume_gradients(self.tetra)
        delta = 1e-5
        for i in range(4):
            for j in range(3):
                displaced = list(self.tetra)
                displaced[i] = tuple(self.tetra[i][k] + (delta if k == j else 0)
                                     for k in range(3))
                observed = (signed_volume_gradients(displaced)[0] - base) / delta
                self.assertAlmostEqual(observed, gradient[i][j], delta=1e-9)

    def test_pinned_tetra_recovers_volume_with_accumulated_multiplier(self):
        deformed = self.tetra[:3] + [(0., 0., 0.5)]
        volume0 = 1. / 6.
        pinned = deformed[0]
        lam = 0.
        for _ in range(8):
            deformed, lam, ok = solve_volume(deformed, [0., 1., 1., 1.], volume0, 0., lam)
            self.assertTrue(ok)
        self.assertEqual(deformed[0], pinned)
        self.assertAlmostEqual(signed_volume_gradients(deformed)[0], volume0, places=8)
        self.assertTrue(all(math.isfinite(c) for v in deformed for c in v))

    def test_compliant_projection_is_softer_than_rigid(self):
        deformed = self.tetra[:3] + [(0., 0., 0.5)]
        stiff, _, _ = solve_volume(deformed, [1.] * 4, 1. / 6., 0., 0.)
        soft, _, _ = solve_volume(deformed, [1.] * 4, 1. / 6., 5., 0.)
        stiff_err = abs(signed_volume_gradients(stiff)[0] - 1. / 6.)
        soft_err = abs(signed_volume_gradients(soft)[0] - 1. / 6.)
        self.assertLess(stiff_err, soft_err)

    def test_tiny_but_closed_rest_volume_must_not_use_absolute_epsilon(self):
        scale = 1e-3
        tiny = [tuple(c * scale for c in vertex) for vertex in self.tetra]
        volume, _ = signed_volume_gradients(tiny)
        self.assertLess(volume, 1e-5)
        self.assertAlmostEqual(volume / scale ** 3, 1. / 6., places=12)
        self.assertGreater(volume, scale ** 3 * 1e-10)


if __name__ == "__main__":
    unittest.main()
