"""Reference contracts for objective SoftBody3D StVK membrane velocity damping.

Run: python3 -m unittest discover -s tests/stress -p test_physics_softbody_membrane_damping.py -v

This checks the velocity-projection math and source integration, not the
entire native engine build. Native tests are in tests/servers/.
"""

import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def rest_metric(a, b, c):
    ab = [b[i] - a[i] for i in range(3)]
    ac = [c[i] - a[i] for i in range(3)]
    area_sq = dot(cross(ab, ac), cross(ab, ac))
    ab_sq = dot(ab, ab)
    ac_sq = dot(ac, ac)
    if not (ab_sq > 0 and ac_sq > 0 and area_sq > ab_sq * ac_sq * 1e-16):
        return None
    length = math.sqrt(ab_sq)
    height = math.sqrt(area_sq) / length
    along = dot(ab, ac) / length
    return (1 / length, -along / (length * height),
            1 / height, length * height * 0.5)


def damp(a, b, c, va, vb, vc, inv=(1, 1, 1), fraction=1.0, rest=None):
    if rest is None:
        rest = rest_metric(a, b, c)
    if (rest is None or not (0 < fraction <= 1) or
            not all(math.isfinite(t) for t in
                    (*a, *b, *c, *va, *vb, *vc, *inv, *rest, fraction)) or
            any(t < 0 for t in inv) or sum(inv) <= 0):
        return None
    inv_u, q, inv_h, area = rest
    if not (inv_u > 0 and inv_h > 0 and area > 0):
        return None
    v = [list(va), list(vb), list(vc)]
    ab = [b[k] - a[k] for k in range(3)]
    ac = [c[k] - a[k] for k in range(3)]
    f0 = [inv_u * ab[k] for k in range(3)]
    f1 = [q * ab[k] + inv_h * ac[k] for k in range(3)]
    changed = False
    for mode in range(3):
        df0 = [f0[k] if mode == 0 else (0.5 * f1[k] if mode == 2 else 0)
               for k in range(3)]
        df1 = [f1[k] if mode == 1 else (0.5 * f0[k] if mode == 2 else 0)
               for k in range(3)]
        gb = [inv_u * df0[k] + q * df1[k] for k in range(3)]
        gc = [inv_h * df1[k] for k in range(3)]
        ga = [-gb[k] - gc[k] for k in range(3)]
        grads = (ga, gb, gc)
        rate = sum(dot(g, vel) for g, vel in zip(grads, v))
        denom = sum(m * dot(g, g) for m, g in zip(inv, grads))
        if not all(math.isfinite(t) for t in (rate, denom)):
            return None
        if denom <= 0 or rate == 0:
            continue
        impulse = -fraction * rate / denom
        for j in range(3):
            for k in range(3):
                v[j][k] += inv[j] * impulse * grads[j][k]
        if not all(math.isfinite(t) for item in v for t in item):
            return None
        changed = True
    return v if changed else None


def momentum(v, inverse_masses):
    return [sum(v[i][axis] / inverse_masses[i] for i in range(3))
            for axis in range(3)]


def angular(x, v, inverse_masses):
    return [sum(cross(x[i], [t / inverse_masses[i] for t in v[i]])[axis]
                for i in range(3)) for axis in range(3)]


def kinetic(v, inverse_masses):
    return sum(dot(vel, vel) / (2 * inverse_masses[i])
               for i, vel in enumerate(v))


class MembraneDampingContracts(unittest.TestCase):
    def test_linear_damping_reduces_energy(self):
        x = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        v = ([0, 0, 0], [2, 0, 0], [0, 0, 0])
        out = damp(*x, *v)
        self.assertIsNotNone(out)
        self.assertLess(kinetic(out, (1, 1, 1)), kinetic(v, (1, 1, 1)))
        for expected, actual in zip(momentum(v, (1, 1, 1)),
                                     momentum(out, (1, 1, 1))):
            self.assertAlmostEqual(expected, actual)

    def test_shear_rate_dissipates(self):
        x = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        v = ([0, 0, 0], [0, 0, 0], [1, 0, 0])
        out = damp(*x, *v)
        self.assertLess(kinetic(out, (1, 1, 1)), kinetic(v, (1, 1, 1)))

    def test_rigid_translation_and_rotation_are_undamped(self):
        x = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        v1 = ([3, 2, -4], [3, 2, -4], [3, 2, -4])
        out1 = damp(*x, *v1)
        self.assertTrue(out1 is None or all(
            all(abs(a - b) <= 1e-12 for a, b in zip(u, t))
            for u, t in zip(out1, v1)))
        v2 = ([0, 0, 0], [0, 1, 0], [-1, 0, 0])
        out2 = damp(*x, *v2)
        self.assertTrue(out2 is None or all(
            all(abs(a - b) <= 1e-12 for a, b in zip(u, t))
            for u, t in zip(out2, v2)))

    def test_pins_and_invalid_inputs(self):
        x = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        v = ([0, 0, 0], [0, 0, 0], [2, 0, 0])
        out = damp(*x, *v, inv=(0, 0, 1))
        self.assertIsNotNone(out)
        self.assertEqual(out[0], v[0])
        self.assertEqual(out[1], v[1])
        self.assertIsNone(damp(*x, *v, inv=(0, 0, 0)))
        self.assertIsNone(damp(*x, *v, fraction=0))
        self.assertIsNone(damp(*x, *v, fraction=math.inf))

    def test_fraction_orders_energy(self):
        x = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        v = ([0, 0, 0], [2, 0, 0], [0, 0, 0])
        lo = damp(*x, *v, fraction=0.1)
        hi = damp(*x, *v, fraction=0.9)
        self.assertLess(kinetic(hi, (1, 1, 1)), kinetic(lo, (1, 1, 1)))

    def test_randomized_kinetic_and_momentum_invariants(self):
        rng = random.Random(20261119)
        for _ in range(5000):
            scale = 10 ** rng.uniform(-8, 20)
            x = ([0, 0, 0],
                 [scale * rng.uniform(0.7, 1.3),
                  scale * rng.uniform(-0.15, 0.15), 0],
                 [scale * rng.uniform(-0.15, 0.15),
                  scale * rng.uniform(0.7, 1.3), 0])
            inv = tuple(rng.uniform(0.25, 3) for _ in range(3))
            v = [[rng.uniform(-10, 10) for _ in range(3)]
                 for _ in range(3)]
            before = kinetic(v, inv)
            out = damp(*x, *v, inv=inv, fraction=rng.uniform(0.01, 1.0))
            if out is None:
                continue
            after = kinetic(out, inv)
            self.assertLessEqual(after, before + max(1e-8, abs(before) * 1e-12))
            p0, p1 = momentum(v, inv), momentum(out, inv)
            l0, l1 = angular(x, v, inv), angular(x, out, inv)
            for a, b in zip(p0, p1):
                self.assertAlmostEqual(a, b, delta=1e-8 + abs(a) * 1e-10)
            for a, b in zip(l0, l1):
                self.assertAlmostEqual(a, b,
                                       delta=1e-8 * scale + abs(a) * 1e-10)
            self.assertTrue(all(math.isfinite(t) for vel in out for t in vel))

    def test_source_wiring_opt_in_and_no_extra_per_tick_memory(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        head = (ROOT / "servers/physics_softbody_membrane_damping.h").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        opts = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn("physics_softbody_damp_membrane(", body)
        self.assertIn("get_soft_body_membrane_damping_rate()", body)
        self.assertIn("const double impulse = -p_fraction * strain_rate", head)
        self.assertIn("r_v_a = next_a;", head)
        self.assertIn("if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite())", head)
        self.assertLess(head.index("if (!next_a.is_finite()"),
                        head.index("r_v_a = next_a;"))
        self.assertIn("soft_body_membrane_damping_rate", space)
        self.assertIn('"physics/3d/solver/soft_body_membrane_damping_rate"', opts)
        self.assertIn("get_soft_body_xpbd_membrane_compliance() <= 0.0 &&", body)


if __name__ == "__main__":
    unittest.main()
