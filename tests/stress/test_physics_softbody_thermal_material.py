"""Independent thermal graph diffusion / XPBD material contract tests for Cgame."""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def exact_exchange(a: float, b: float, rate: float, dt: float) -> tuple[float, float]:
    fraction = 0.5 * (1 - math.exp(-2 * rate * dt))
    delta = fraction * (b - a)
    return a + delta, b - delta


def bath(temperature: float, target: float, rate: float, dt: float) -> float:
    return temperature + (target-temperature) * (1-math.exp(-rate * dt))


def thermal_rest_length(base: float, a: float, b: float,
                        ambient: float, expansion: float) -> float:
    scale = max(0.25, min(4.0, 1 + expansion * ((a+b)*0.5-ambient)))
    return base*scale


class ThermoMechanicalTests(unittest.TestCase):
    def test_pair_has_exact_two_particle_heat_equation(self):
        a, b = exact_exchange(0, 100, 1, 1)
        self.assertAlmostEqual(a, 43.23323584, places=6)
        self.assertAlmostEqual(b, 56.76676416, places=6)
        self.assertAlmostEqual(a+b, 100)

    def test_exponential_pair_exchange_stable_with_any_dt(self):
        for rate in [0, .01, 1, 500]:
            for dt in [0, 1/1000, 1, 10, 1000]:
                a, b = exact_exchange(-273, 2000, rate, dt)
                self.assertTrue(math.isfinite(a) and math.isfinite(b))
                self.assertGreaterEqual(a, -273)
                self.assertLessEqual(a, 2000)
                self.assertGreaterEqual(b, -273)
                self.assertLessEqual(b, 2000)
                self.assertAlmostEqual(a+b, 1727, delta=1e-9)

    def test_heat_is_conserved_across_mesh_links(self):
        t = [200., 20., 20., 20., 20.]
        edges = [(0,1), (1,2), (2,3), (3,4), (4,0), (1,3)]
        initial = sum(t)
        for _ in range(200):
            for a, b in edges:
                t[a], t[b] = exact_exchange(t[a], t[b], 10, 1/60)
        self.assertAlmostEqual(sum(t), initial, places=8)
        self.assertLess(max(t)-min(t), .01)

    def test_equal_capacity_even_if_node_is_pinned(self):
        # A pinned vertex retains its heat capacity and can heat its neighbor.
        fixed = 100.
        movable = 20.
        fixed, movable = exact_exchange(fixed, movable, 5, .2)
        self.assertLess(fixed, 100)
        self.assertGreater(movable, 20)
        self.assertAlmostEqual(fixed+movable, 120)

    def test_pair_subdivision_matches_single_step(self):
        a, b = exact_exchange(0, 100, 1, 1)
        x, y = 0., 100.
        for _ in range(10):
            x, y = exact_exchange(x, y, 1, .1)
        self.assertAlmostEqual(a, x, places=12)
        self.assertAlmostEqual(b, y, places=12)

    def test_ambient_and_heater_can_cool_or_heat(self):
        self.assertAlmostEqual(bath(100, 20, math.log(2), 1), 60)
        self.assertLess(bath(20, -100, 10, .1), 20)
        self.assertGreater(bath(20, 100, 10, .1), 20)

    def test_ambient_subdivision_independence(self):
        one = bath(200, 20, 2, 1)
        many = 200
        for _ in range(20):
            many = bath(many, 20, 2, .05)
        self.assertAlmostEqual(one, many, places=12)

    def test_hot_spot_heat_spreads_on_links(self):
        temps = [20., 20., 20.]
        positions = [(0.,0.,0.), (1.,0.,0.), (2.,0.,0.)]
        for _ in range(50):
            for i,p in enumerate(positions):
                if sum(x*x for x in p) <= .5*.5:
                    temps[i] = bath(temps[i], 100, 8, 1/60)
            for a,b in [(0,1),(1,2)]:
                temps[a],temps[b] = exact_exchange(temps[a],temps[b],5,1/60)
        self.assertGreater(temps[0], temps[1])
        self.assertGreater(temps[1], temps[2])
        self.assertGreater(temps[2], 20)

    def test_material_returns_to_original_after_cooling(self):
        base = 2.0
        hot = thermal_rest_length(base, 100, 100, 20, .001)
        cold = thermal_rest_length(base, 20, 20, 20, .001)
        self.assertAlmostEqual(hot, 2.16)
        self.assertAlmostEqual(cold, base)
        self.assertAlmostEqual(thermal_rest_length(base, -100, -100, 20, .001), 1.76)

    def test_material_respects_current_plastic_length(self):
        self.assertAlmostEqual(thermal_rest_length(2.5, 100, 100, 20, .001), 2.7)
        self.assertAlmostEqual(thermal_rest_length(2.5, 20, 20, 20, .001), 2.5)

    def test_safe_expansion_bounds(self):
        self.assertAlmostEqual(thermal_rest_length(2, 2000, 2000, 20, .01), 8)
        self.assertAlmostEqual(thermal_rest_length(2, 2000, 2000, 20, -.01), .5)
        self.assertAlmostEqual(thermal_rest_length(2, 50, 50, 20, 0), 2)

    def test_settings_default_inactive(self):
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        header = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        cpp = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        names = (
            "conduction_rate",
            "ambient_exchange_rate",
            "ambient_temperature",
            "source_rate",
            "source_temperature",
            "source_center",
            "source_radius",
            "expansion_coefficient",
        )
        for name in names:
            token = f"soft_body_thermal_{name}"
            key = f"physics/3d/solver/{token}"
            self.assertIn(f'"{key}"', server)
            self.assertIn(f'GLOBAL_GET("{key}")', cpp)
            self.assertIn(f"get_{token}()", header)
        self.assertIn("soft_body_thermal_conduction_rate = 0.0", header)
        self.assertIn("soft_body_thermal_ambient_exchange_rate = 0.0", header)
        self.assertIn("soft_body_thermal_source_rate = 0.0", header)
        self.assertIn("soft_body_thermal_source_radius = 0.0", header)
        self.assertIn("soft_body_thermal_expansion_coefficient = 0.0", header)

    def test_source_is_world_space_bounded_sphere(self):
        helper = (ROOT/"servers/physics_softbody_thermal_material.h").read_text()
        self.assertIn("const double dx = double(p_position.x) - double(p_source.x)", helper)
        self.assertIn("sq <= radius_sq", helper)
        self.assertIn("!(p_radius > 0.0)", helper)
        self.assertIn("p_position.is_finite()", helper)

    def test_heat_buffers_are_opt_in_persistent_and_cleared(self):
        cpp = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        self.assertIn("LocalVector<real_t> thermal_node_temperatures;", header)
        self.assertIn("LocalVector<real_t> thermal_link_rest_lengths;", header)
        self.assertIn("void advance_thermal_material(real_t p_delta, bool p_xpbd_enabled);", header)
        self.assertIn("thermal_node_temperatures.size() != nodes.size()", cpp)
        self.assertIn("thermal_link_rest_lengths.resize(links.size())", cpp)
        self.assertIn("thermal_node_temperatures.reset();", cpp)
        self.assertIn("thermal_link_rest_lengths.reset();", cpp)
        self.assertIn("const bool use_source = source_rate > 0.0 && source_radius > 0.0;", cpp)
        self.assertIn("if (!use_thermal) {", cpp)
        self.assertIn("advance_thermal_material(p_delta, use_xpbd);", cpp)

    def test_heat_runs_once_before_xpbd_and_other_solvers(self):
        cpp = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertLess(cpp.index("advance_thermal_material(p_delta, use_xpbd);"),
                        cpp.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        self.assertIn("physics_softbody_thermal_exchange_pair(", cpp)
        self.assertIn("physics_softbody_thermal_relax(", cpp)
        self.assertIn("physics_softbody_thermal_expanded_rest_length(", cpp)

    def test_thermal_length_used_by_distance_strain_and_fatigue(self):
        cpp = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("const real_t link_rest = use_thermal_rest ? thermal_link_rest_lengths[link_index] : link.rl;", cpp)
        self.assertIn("link_rest, link_alpha, yield_strain", cpp)
        self.assertIn("link_rest, link_alpha, compression_yield", cpp)
        self.assertIn("link_rest, fatigue_yield", cpp)
        self.assertGreaterEqual(cpp.count("use_thermal_rest ? thermal_link_rest_lengths[link_index] : link.rl"),3)
        self.assertIn("use_thermal_rest = use_xpbd", cpp)

    def test_plastic_rest_lengths_are_never_mutated_by_thermal_code(self):
        cpp = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        thermal_section = cpp.split("void GodotSoftBody3D::advance_thermal_material(")[1].split(
            "void GodotSoftBody3D::solve_constraints(")[0]
        self.assertNotIn("link.rl =", thermal_section)
        self.assertNotIn("link.c1 =", thermal_section)
        self.assertIn("real_t rest = link.rl;", thermal_section)

    def test_native_cases_and_workflow_exist(self):
        native = (ROOT/"tests/servers/test_physics_softbody_thermal_material.cpp").read_text()
        workflow = (ROOT/".github/workflows/physics-softbody-thermal-material.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_thermal_material)", native)
        self.assertGreaterEqual(native.count("TEST_CASE("), 19)
        self.assertIn("Heat-source sphere is symmetric", native)
        self.assertIn("python3 -m unittest discover", workflow)


if __name__ == "__main__":
    unittest.main()
