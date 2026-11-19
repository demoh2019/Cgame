"""Independent numerical contracts for submerged SoftBody3D current drag.

Run:
    python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_hydrodynamic_drag.py' -v

These reference calculations verify model invariants, not native C++
compilation. Native doctests exercise the actual Cgame implementation.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def clip_triangle(points, surface):
    source = [(tuple(float(x) for x in points[i]),
               tuple(float(i == j) for j in range(3))) for i in range(3)]
    polygon = []
    for i in range(3):
        a, wa = source[i]
        b, wb = source[(i + 1) % 3]
        da = surface - a[1]
        db = surface - b[1]
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            intersection = tuple(a[k] + (b[k] - a[k]) * t for k in range(3))
            weights = tuple(wa[k] + (wb[k] - wa[k]) * t for k in range(3))
            polygon.append((intersection, weights))
        if db >= 0:
            polygon.append((b, wb))
    return polygon


def submerged_drag(points, velocities, inverse_mass, flow,
                   surface=0, density=10, cd=1, tangent_ratio=0.25, dt=1/60):
    if density <= 0 or cd <= 0 or dt <= 0 or not any(inverse_mass):
        return ((0.0, 0.0, 0.0),) * 3
    polygon = clip_triangle(points, surface)
    impulse = [[0.0, 0.0, 0.0] for _ in range(3)]
    for tri_idx in range(1, len(polygon) - 1):
        tri = [polygon[0], polygon[tri_idx], polygon[tri_idx+1]]
        a, b, c = [entry[0] for entry in tri]
        u = [b[k] - a[k] for k in range(3)]
        v = [c[k] - a[k] for k in range(3)]
        cross = (u[1]*v[2]-u[2]*v[1],
                 u[2]*v[0]-u[0]*v[2],
                 u[0]*v[1]-u[1]*v[0])
        length = math.sqrt(sum(x*x for x in cross))
        if not length:
            continue
        normal = [x/length for x in cross]
        area = length / 2
        bary = [sum(vertex[1][j] for vertex in tri)/3 for j in range(3)]
        rel = [sum(bary[j]*velocities[j][k] for j in range(3)) - flow[k]
               for k in range(3)]
        vn = sum(rel[k]*normal[k] for k in range(3))
        tangent = [rel[k] - vn*normal[k] for k in range(3)]
        speed = math.sqrt(sum(t*t for t in tangent))
        strength = 0.5*density*cd*area*dt
        for k in range(3):
            net = -strength * (vn*abs(vn)*normal[k] + tangent_ratio*speed*tangent[k])
            for j in range(3):
                impulse[j][k] += bary[j]*net

    power = sum(impulse[j][k]*(velocities[j][k]-flow[k])
                for j in range(3) if inverse_mass[j] > 0 for k in range(3))
    quadratic = sum(inverse_mass[j]*impulse[j][k]**2
                    for j in range(3) for k in range(3))
    if power >= 0 or quadratic <= 0:
        return ((0.0, 0.0, 0.0),)*3
    scale = min(1.0, -power/quadratic)
    return tuple(tuple(inverse_mass[j]*scale*impulse[j][k] for k in range(3))
                 for j in range(3))


def kinetic_energy(velocity, inv_mass, flow):
    return sum(sum((velocity[j][k]-flow[k])**2 for k in range(3)) /
               (2*inv_mass[j]) for j in range(3) if inv_mass[j] > 0)


class TestHydrodynamicSoftbody(unittest.TestCase):
    def test_clipping_area_and_barycentric_partition(self):
        points = ((0, -1, 0), (2, 1, 0), (0, 1, 2))
        clipped = clip_triangle(points, 0)
        self.assertEqual(len(clipped), 3)
        self.assertEqual(len(clip_triangle(points, 2)), 3)
        self.assertEqual(len(clip_triangle(points, -2)), 0)
        for _, bary in clipped:
            self.assertAlmostEqual(sum(bary), 1)
            self.assertTrue(all(0 <= x <= 1 for x in bary))

    def test_partially_submerged_drag_tracks_immersed_area(self):
        points = ((0, -1, 0), (2, 1, 0), (0, 1, 2))
        velocity = ((1, -1, 1),)*3
        inv = (1,)*3
        a = submerged_drag(points, velocity, inv, (0, 0, 0), surface=0, dt=0.001, tangent_ratio=0)
        b = submerged_drag(points, velocity, inv, (0, 0, 0), surface=3, dt=0.001, tangent_ratio=0)
        force_ratio = math.sqrt(sum(sum(v[j] for v in a)**2 for j in range(3))) / math.sqrt(
            sum(sum(v[j] for v in b)**2 for j in range(3)))
        self.assertAlmostEqual(force_ratio, 0.25, delta=0.001)

    def test_stationary_water_dissipates_normal_and_shear_motion(self):
        points = ((0, -1, 0), (1, -1, 0), (0, -1, 1))
        inv = (1,)*3
        for v, ratio in (((0, 8, 0), 0), ((5, 0, 0), 0.4)):
            before = (v,)*3
            delta = submerged_drag(points, before, inv, (0, 0, 0),
                                   density=10, tangent_ratio=ratio, dt=0.05)
            after = tuple(tuple(before[j][k]+delta[j][k] for k in range(3))
                          for j in range(3))
            self.assertLess(kinetic_energy(after, inv, (0, 0, 0)),
                            kinetic_energy(before, inv, (0, 0, 0)))

    def test_without_tangential_drag_flow_along_surface_is_unaffected(self):
        p = ((0, -1, 0), (1, -1, 0), (0, -1, 1))
        v = ((2, 0, 0),)*3
        self.assertEqual(submerged_drag(p, v, (1,)*3, (0, 0, 0), tangent_ratio=0),
                         ((0, 0, 0),)*3)

    def test_fixed_vertices_and_huge_density_are_bounded(self):
        p = ((0, -1, 0), (1, -1, 0), (0, -1, 1))
        v = ((0, 10, 0),)*3
        inv = (0, 1, 1)
        dv = submerged_drag(p, v, inv, (0, 0, 0), density=1e12,
                            cd=1e9, dt=1e6)
        self.assertEqual(dv[0], (0, 0, 0))
        nxt = tuple(tuple(v[j][k]+dv[j][k] for k in range(3)) for j in range(3))
        self.assertLessEqual(kinetic_energy(nxt, inv, (0, 0, 0)),
                             kinetic_energy(v, inv, (0, 0, 0)) + 1e-12)

    def test_randomized_current_relative_energy_decreases(self):
        rng = random.Random(0xCA7E)
        for _ in range(5000):
            p = ((0, -1, 0), (1, rng.uniform(-2, 2), 0),
                 (0, rng.uniform(-2, 2), 1))
            v = tuple(tuple(rng.uniform(-10, 10) for _ in range(3)) for _ in range(3))
            inv = tuple(rng.uniform(0.01, 3) if rng.randrange(5) else 0 for _ in range(3))
            flow = tuple(rng.uniform(-3, 3) for _ in range(3))
            coeff = rng.uniform(0, 200)
            ratio = rng.uniform(0, 4)
            dt = rng.uniform(0.0001, 0.5)
            dv = submerged_drag(p, v, inv, flow, 0, coeff, 2, ratio, dt)
            after = tuple(tuple(v[j][k]+dv[j][k] for k in range(3)) for j in range(3))
            before = kinetic_energy(v, inv, flow)
            energy = kinetic_energy(after, inv, flow)
            self.assertLessEqual(energy, before + 1e-10*(1+before))
            for j in range(3):
                if inv[j] == 0:
                    self.assertEqual(dv[j], (0, 0, 0))

    def test_pinned_reaction_does_not_add_energy_to_free_vertices(self):
        p = ((0, -1, 0), (1, -1, 0), (0, -1, 1))
        v = ((0, 100, 0), (0, 0, 0), (0, 0, 0))
        inv = (0, 1, 1)
        dv = submerged_drag(p, v, inv, (0, 0, 0),
                            density=1000, cd=5, tangent_ratio=1, dt=0.1)
        self.assertEqual(dv, ((0.0, 0.0, 0.0),)*3)
        self.assertEqual(kinetic_energy(v, inv, (0, 0, 0)), 0.0)

    def test_sequential_shared_face_drag_stays_dissipative(self):
        p = ((0, -1, 0), (1, -1, 0), (0, -1, 1))
        v = ((-6, 8, 1), (4, 5, -4), (2, 11, 3))
        inv = (1, 1.5, 0.5)
        flow = (3, 0, 1)
        last = kinetic_energy(v, inv, flow)
        for _ in range(100):
            dv = submerged_drag(p, v, inv, flow, density=1000, cd=5, dt=0.5)
            v = tuple(tuple(v[j][k]+dv[j][k] for k in range(3)) for j in range(3))
            energy = kinetic_energy(v, inv, flow)
            self.assertLessEqual(energy, last+1e-10)
            last = energy

    def test_runtime_wiring_default_off_and_hydrostatic_shared_clip(self):
        core = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        spaceh = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        spacec = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        hydro = (ROOT / "servers/physics_softbody_hydrostatic.h").read_text()
        clipping = (ROOT / "servers/physics_softbody_fluid_clipping.h").read_text()
        drag = (ROOT / "servers/physics_softbody_hydrodynamic_drag.h").read_text()
        self.assertIn("soft_body_hydrodynamic_drag = false;", spaceh)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_hydrodynamic_drag")', spacec)
        self.assertIn('"physics/3d/solver/soft_body_hydrodynamic_drag"', server)
        self.assertIn("apply_hydrodynamic_drag(real_t p_delta);", header)
        self.assertIn("physics_softbody_hydrodynamic_drag_face(", core)
        self.assertIn("is_fluid_plane_enabled()", core)
        self.assertIn("get_fluid_plane_flow_velocity()", core)
        self.assertIn("physics_softbody_clip_fluid_triangle(", hydro)
        self.assertIn("physics_softbody_clip_fluid_triangle(", drag)
        self.assertIn("PhysicsSoftBodyFluidVertex clipped[4]", clipping)
        position = core.index("void GodotSoftBody3D::predict_motion(")
        stage = core.index("apply_hydrodynamic_drag(p_delta)", position)
        integrate = core.index("node.v += delta_v", position)
        self.assertLess(stage, integrate)


if __name__ == "__main__":
    unittest.main()
