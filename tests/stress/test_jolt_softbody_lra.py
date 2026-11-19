"""Source contracts and reference mathematics for Jolt soft-body LRA.

Native solver behavior is checked separately in jolt_lra/pinned_cloth_lra_regression.gd.
These checks do not replace an engine build or physical simulation run.
Run: python3 -m unittest tests/stress/test_jolt_softbody_lra.py -v
"""

import heapq
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
SETTINGS_H = ROOT / "modules/jolt_physics/jolt_project_settings.h"
JOLT_API = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"


def shortest_path(vertices, edges, start, goal):
    """Dijkstra on edge lengths, the reference for geodesic cloth distance."""
    neighbor = {i: [] for i in range(len(vertices))}
    for a, b in edges:
        length = math.dist(vertices[a], vertices[b])
        neighbor[a].append((b, length))
        neighbor[b].append((a, length))
    frontier = [(0.0, start)]
    best = {start: 0.0}
    while frontier:
        cost, node = heapq.heappop(frontier)
        if node == goal:
            return cost
        if cost > best[node]:
            continue
        for nxt, length in neighbor[node]:
            alt = cost + length
            if alt < best.get(nxt, math.inf):
                best[nxt] = alt
                heapq.heappush(frontier, (alt, nxt))
    return math.inf


class JoltLRAContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.soft = CPP.read_text(encoding="utf-8")
        cls.settings = SETTINGS_CPP.read_text(encoding="utf-8")
        cls.header = SETTINGS_H.read_text(encoding="utf-8")
        cls.jolt_api = JOLT_API.read_text(encoding="utf-8")
        cls.generator = cls.soft.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("void JoltSoftBody3D::_apply_environmental_forces(", 1)[0]

    def test_opt_in_default_does_not_add_any_lra_constraints(self):
        self.assertIn("inline static int soft_body_lra_mode = 0;", self.header)
        self.assertIn(
            'soft_body_lra_mode", PROPERTY_HINT_ENUM, "Disabled,Euclidean,Geodesic"), 0',
            self.settings,
        )
        self.assertIn("JoltProjectSettings::soft_body_lra_mode != 0", self.generator)
        self.assertIn("vertex_attrib.mLRAType", self.generator)

    def test_valid_pinned_vertex_required_before_generating_lra(self):
        self.assertLess(
            self.generator.index("pin_vertices(*this, pinned_vertices, mesh_to_physics, physics_vertices);"),
            self.generator.index("bool has_kinematic_vertex = false;"),
        )
        self.assertIn("vertex.mInvMass == 0.0f", self.generator)
        self.assertIn("if (has_kinematic_vertex)", self.generator)

    def test_both_jolt_distance_modes_and_multiplier_are_connected(self):
        self.assertIn("using LRAType = JPH::SoftBodySharedSettings::ELRAType;", self.generator)
        self.assertIn("EuclideanDistance", self.jolt_api)
        self.assertIn("GeodesicDistance", self.jolt_api)
        self.assertIn("LRAType::EuclideanDistance", self.generator)
        self.assertIn("LRAType::GeodesicDistance", self.generator)
        self.assertIn("vertex_attrib.mLRAMaxDistanceMultiplier", self.generator)
        self.assertIn("mLRAMaxDistanceMultiplier", self.jolt_api)
        self.assertIn("mLRAType", self.jolt_api)
        self.assertIn("CreateConstraints(&vertex_attrib, 1, bend_type)", self.generator)

    def test_slider_values_are_clamped_and_nonfinite_fall_back(self):
        self.assertIn("CLAMP(lra_multiplier, 1.0f, 10.0f)", self.settings)
        self.assertIn("Math::is_finite(lra_multiplier)", self.settings)
        self.assertIn("CLAMP((int)GLOBAL_GET(\"physics/jolt_physics_3d/simulation/soft_body_lra_mode\"), 0, 2)", self.settings)

    def test_welded_alias_reports_actual_physical_inverse_mass(self):
        query = self.soft.split("bool JoltSoftBody3D::is_vertex_pinned(int p_index) const {", 1)[1]
        self.assertIn("GetVertices()[physics_index].mInvMass == 0.0f", query)
        self.assertNotIn("pinned_vertices.has(physics_index)", query)
        impulse = self.soft.split("void JoltSoftBody3D::apply_vertex_impulse(", 1)[1].split(
            "void JoltSoftBody3D::apply_vertex_force(", 1
        )[0]
        self.assertIn("physics_vertex.mInvMass <= 0.0f", impulse)

    def test_geodesic_follows_folded_mesh_instead_of_shortcut(self):
        # A folded three-vertex line; the endpoints are near each other in 3D,
        # but a particle travelling along the surface has to follow two edges.
        vertices = [(0, 0, 0), (1, 0, 0), (0, 0.1, 0)]
        d_euclidean = math.dist(vertices[0], vertices[2])
        d_geodesic = shortest_path(vertices, [(0, 1), (1, 2)], 0, 2)
        self.assertAlmostEqual(d_euclidean, 0.1)
        self.assertGreater(d_geodesic, 20 * d_euclidean)
        for slack in (1.0, 1.05, 1.5, 10.0):
            self.assertGreaterEqual(slack * d_geodesic, slack * d_euclidean)


if __name__ == "__main__":
    unittest.main()
