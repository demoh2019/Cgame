"""Analytical and source regression tests for SoftBody3D orthotropic hinge bending."""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def normalize(v):
    norm = math.sqrt(dot(v, v))
    return tuple(x/norm for x in v)


def bend_factor(a, b, c, d, warp, weft_ratio):
    """Pure Python reference based on two triangle normal frames."""
    edge, ac, ad = sub(b, a), sub(c, a), sub(d, a)
    n0 = normalize(cross(edge, ac))
    n1 = normalize(cross(ad, edge))
    ns = tuple(x+y for x, y in zip(n0, n1))
    if dot(ns, ns) < 1e-12:
        ns = n0
    else:
        ns = normalize(ns)
    projection = tuple(w-dot(warp, ns)*n for w, n in zip(warp, ns))
    cos2 = dot(edge, projection)**2/(dot(edge, edge)*dot(projection, projection))
    cos2 = max(0., min(1., cos2))
    return cos2 + (1.0-cos2)*weft_ratio


FLAT = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, -1, 0))


class OrthotropicBendingTests(unittest.TestCase):
    def test_warp_weft_and_isotropic(self):
        a, b, c, d = FLAT
        self.assertAlmostEqual(bend_factor(a, b, c, d, (1, 0, 0), 10), 1)
        self.assertAlmostEqual(bend_factor(a, b, c, d, (0, 1, 0), 10), 10)
        self.assertAlmostEqual(bend_factor(a, b, c, d, (1, 1, 0), 10), 5.5)
        self.assertAlmostEqual(bend_factor(a, b, c, d, (0, 1, 0), .25), .25)
        for theta in [0, math.pi/9, math.pi/3, math.pi/2]:
            self.assertAlmostEqual(
                bend_factor(a, b, c, d, (math.cos(theta), math.sin(theta), 0), 1), 1)

    def test_nonplanar_and_fiber_projection(self):
        a, b, c, d = FLAT
        base = bend_factor(a, b, c, d, (1, 2, 0), 7)
        self.assertAlmostEqual(base, bend_factor(a, b, c, d, (1, 2, 10), 7))
        tilted = ((0, 0, 0), (1, 0, 0), (0, 0, 1), (0, 0, -1))
        self.assertAlmostEqual(base, bend_factor(*tilted, (1, 0, 2), 7))

    def test_deformed_curved_rest_hinge(self):
        a, b, c, d = FLAT
        curved = (a, b, c, (0, -1, .5))
        factor = bend_factor(*curved, (1, 1, .4), 12)
        self.assertTrue(math.isfinite(factor))
        self.assertGreaterEqual(factor, 1)
        self.assertLessEqual(factor, 12)

    def test_symmetry_under_winding_axis_reversal_and_offset(self):
        a, b, c, d = FLAT
        v = bend_factor(a, b, c, d, (2, 1, 0), 9)
        self.assertAlmostEqual(v, bend_factor(b, a, d, c, (2, 1, 0), 9))
        self.assertAlmostEqual(v, bend_factor(a, b, c, d, (-2, -1, 0), 9))
        offset = (100, -20, 30)
        shifted = tuple(tuple(q+o for q, o in zip(p, offset)) for p in FLAT)
        self.assertAlmostEqual(v, bend_factor(*shifted, (2, 1, 0), 9))

    def test_uniform_scale_and_rotation(self):
        a, b, c, d = FLAT
        v = bend_factor(a, b, c, d, (2, 1, 0), 9)
        scaled = tuple(tuple(t*1e-5 for t in p) for p in FLAT)
        self.assertAlmostEqual(v, bend_factor(*scaled, (2, 1, 0), 9))
        # Rotate +90 deg about Z: edge X becomes Y, warp (2,1)->(-1,2).
        rotated = tuple((-p[1], p[0], p[2]) for p in FLAT)
        self.assertAlmostEqual(v, bend_factor(*rotated, (-1, 2, 0), 9))

    def test_bounded_ratio(self):
        a, b, c, d = FLAT
        for angle in [math.pi*i/128 for i in range(256)]:
            warp = (math.cos(angle), math.sin(angle), 0)
            for ratio in [0.01, 0.25, 1, 3, 100]:
                result = bend_factor(a, b, c, d, warp, ratio)
                self.assertTrue(math.isfinite(result))
                self.assertGreaterEqual(result, min(1, ratio)-1e-12)
                self.assertLessEqual(result, max(1, ratio)+1e-12)

    def test_project_settings_and_cached_getters(self):
        defs = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        sh = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        sc = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        self.assertIn('physics/3d/solver/soft_body_xpbd_bend_weft_ratio', defs)
        self.assertIn('physics/3d/solver/soft_body_xpbd_bend_warp_axis', defs)
        self.assertIn('soft_body_xpbd_bend_weft_ratio = 1.0;', sh)
        self.assertIn('Vector3 soft_body_xpbd_bend_warp_axis = Vector3(1, 0, 0)', sh)
        self.assertIn('get_soft_body_xpbd_bend_weft_ratio()', sh)
        self.assertIn('get_soft_body_xpbd_bend_warp_axis()', sh)
        self.assertIn('Math::is_finite(configured_bend_weft_ratio)', sc)
        self.assertIn('configured_bend_warp_axis.is_finite()', sc)

    def test_rest_mesh_cache_and_no_default_extra_work(self):
        soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        self.assertIn('LocalVector<real_t> xpbd_dihedral_anisotropy;', h)
        self.assertIn('xpbd_dihedral_anisotropy.reset();', soft)
        self.assertIn('if (weft_ratio != real_t(1.0) && !xpbd_dihedral_hinges.is_empty())', soft)
        self.assertIn('physics_softbody_orthotropic_bending_ratio(nodes[h.a].s, nodes[h.b].s,', soft)
        self.assertIn('xpbd_dihedral_anisotropy[i] = bend_factor;', soft)
        self.assertIn('use_orthotropic_bending = use_dihedral_xpbd &&', soft)
        self.assertIn('hinge_alpha, xpbd_dihedral_lambdas[hinge_index]', soft)
        self.assertLess(soft.index('physics_softbody_orthotropic_bending_ratio(nodes[h.a].s'),
                        soft.index('for (int isolve = 0; isolve < iteration_count; ++isolve)'))

    def test_helper_numerical_guards_and_no_allocations(self):
        helper = (ROOT / "servers/physics_softbody_orthotropic_bending.h").read_text()
        self.assertIn('Math::is_finite(p_weft_ratio)', helper)
        self.assertIn('p_warp_axis.is_finite()', helper)
        self.assertIn('normal_sq > 1e-12', helper)
        self.assertIn('projected_sq > warp_sq * 1e-12', helper)
        self.assertIn('const double ratio = cos_sq + (1.0 - cos_sq) * double(p_weft_ratio);', helper)
        self.assertNotIn('memnew(', helper)
        self.assertNotIn('malloc(', helper)

    def test_native_test_registration(self):
        native = (ROOT / "tests/servers/test_physics_softbody_orthotropic_bending.cpp").read_text()
        self.assertIn('TEST_FORCE_LINK(test_physics_softbody_orthotropic_bending)', native)
        self.assertGreaterEqual(native.count('TEST_CASE('), 14)


if __name__ == "__main__":
    unittest.main()
