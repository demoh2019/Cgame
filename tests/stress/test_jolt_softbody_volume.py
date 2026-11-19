"""Reference tetrahedral fan geometry + source-contract checks.

Python checks validate mesh eligibility and arithmetic. Native Jolt physics
must also be built and tested; this is not a substitute for solver tests.

Run: python3 -m unittest tests/stress/test_jolt_softbody_volume.py -v
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
JOLT_HEADER = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"


def subtract(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def convex_fan(points, faces):
    """Independent reference validator for closed, convex, oriented triangles.

    Return the positive tetra volumes produced by a centroid fan; empty
    list denotes rejection, mirroring Jolt's optional fallback.
    """
    if len(points) < 4 or len(points) > 2048 or len(faces) < 4 or len(faces) > 4096:
        return []
    if not all(math.isfinite(c) for point in points for c in point):
        return []

    center = tuple(sum(p[k] for p in points) / len(points) for k in range(3))
    radius_sq = max(dot(subtract(p, center), subtract(p, center)) for p in points)
    if not radius_sq or not math.isfinite(radius_sq):
        return []

    edges = {}
    volumes = []
    for face in faces:
        a, b, c = face
        if len({a, b, c}) != 3 or min(face) < 0 or max(face) >= len(points):
            return []
        p0, p1, p2 = [points[i] for i in face]
        normal = cross(subtract(p1, p0), subtract(p2, p0))
        nsq = dot(normal, normal)
        if nsq <= radius_sq * radius_sq * 1.0e-12:
            return []
        tolerance = math.sqrt(nsq * radius_sq) * 1.0e-5
        center_side = dot(normal, subtract(center, p0))
        if abs(center_side) <= tolerance:
            return []
        side = 1 if center_side > 0 else -1
        if any(side * dot(normal, subtract(p, p0)) < -tolerance for p in points):
            return []
        volumes.append(abs(center_side) / 6.0)
        for i in range(3):
            u, v = face[i], face[(i + 1) % 3]
            key = (min(u, v), max(u, v))
            direction = 1 if u < v else -1
            if key not in edges:
                edges[key] = direction
            elif edges[key] == -direction:
                edges[key] = 0
            else:
                return []
    return volumes if all(value == 0 for value in edges.values()) else []


TETRA = [
    (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)
]
TETRA_FACES = [
    (0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)
]
CUBE = [
    (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
    (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)
]
CUBE_FACES = [
    (0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7),
    (0, 1, 5), (0, 5, 4), (3, 7, 6), (3, 6, 2),
    (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5)
]


class SoftBodyVolumeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SOURCE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.jolt = JOLT_HEADER.read_text(encoding="utf-8")
        cls.builder = cls.code.split("static bool try_build_convex_volume_fan(", 1)[1].split(
            "template <typename TJoltVertex>", 1)[0]

    def test_tetra_partition_preserves_rest_volume(self):
        volumes = convex_fan(TETRA, TETRA_FACES)
        self.assertEqual(len(volumes), 4)
        self.assertAlmostEqual(sum(volumes), 1.0 / 6.0)

    def test_inverted_global_winding_is_still_consistent(self):
        volumes = convex_fan(TETRA, [(a, c, b) for a, b, c in TETRA_FACES])
        self.assertEqual(len(volumes), 4)
        self.assertAlmostEqual(sum(volumes), 1.0 / 6.0)

    def test_cube_partition_and_reject_concavity(self):
        self.assertAlmostEqual(sum(convex_fan(CUBE, CUBE_FACES)), 1.0)
        dented = list(CUBE)
        dented[6] = (0.25, 0.25, 0.25)
        self.assertEqual(convex_fan(dented, CUBE_FACES), [])

    def test_reject_open_non_manifold_and_bad_coordinates(self):
        self.assertEqual(convex_fan(TETRA, TETRA_FACES[:3]), [])
        self.assertEqual(convex_fan(TETRA, TETRA_FACES + [TETRA_FACES[0]]), [])
        bad = list(TETRA)
        bad[0] = (math.nan, 0, 0)
        self.assertEqual(convex_fan(bad, TETRA_FACES), [])
        self.assertEqual(convex_fan([(0, 0, 0)] * 4, TETRA_FACES), [])

    def test_opt_in_disabled_by_default(self):
        self.assertIn("inline static bool soft_body_volume_preservation = false;", self.header)
        self.assertIn('simulation/soft_body_volume_preservation"), false', self.settings)
        self.assertIn("if (JoltProjectSettings::soft_body_volume_preservation)", self.code)

    def test_complete_particle_list_precedes_lra_construction(self):
        self.assertIn("mVolumeConstraints.emplace_back(", self.builder)
        self.assertIn("CalculateVolumeConstraintVolumes()", self.builder)
        self.assertIn("CalculateVolumeConstraintVolumes", self.jolt)
        self.assertLess(
            self.code.index("try_build_convex_volume_fan(*settings"),
            self.code.index("settings->CreateConstraints(&vertex_attrib, 1, bend_type)"),
        )
        self.assertLess(
            self.code.index("settings->CreateConstraints(&vertex_attrib, 1, bend_type)"),
            self.code.index("settings->Optimize()"),
        )

    def test_validation_precedes_mutation(self):
        self.assertLess(self.builder.index("for (const JPH::SoftBodySharedSettings::Face &face : faces) {"),
                        self.builder.index("vertices.emplace_back("))
        self.assertIn("state == nullptr || *state != 0", self.builder)
        self.assertIn("MAX_VERTICES = 2048", self.builder)
        self.assertIn("MAX_FACES = 4096", self.builder)
        self.assertIn("side * normal.Dot(", self.builder)

    def test_positive_signed_tetrahedra_for_jolt_volume_gradients(self):
        self.assertIn("const float signed_six_volume =", self.builder)
        self.assertIn("if (signed_six_volume > 0.0f)", self.builder)
        self.assertIn("face.mVertex[0], face.mVertex[2], face.mVertex[1]", self.builder)
        # Jolt computes abs(signed volume) but applies signed gradients.
        vendor = (ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodyMotionProperties.cpp").read_text(encoding="utf-8")
        self.assertIn("float c = abs(x1x2.Cross(x1x3).Dot(x1x4)) - v->mSixRestVolume;", vendor)
        center = (0.25, 0.25, 0.25)
        for a, b, c in TETRA_FACES:
            signed = dot(cross(subtract(TETRA[b], TETRA[a]), subtract(TETRA[c], TETRA[a])),
                         subtract(center, TETRA[a]))
            self.assertNotEqual(signed, 0.0)
            if signed < 0.0:
                b, c = c, b
            corrected = dot(cross(subtract(TETRA[b], TETRA[a]), subtract(TETRA[c], TETRA[a])),
                            subtract(center, TETRA[a]))
            self.assertGreater(corrected, 0.0)

    def test_volume_particle_precedes_mass_compliance_conversion(self):
        self.assertLess(self.code.index("try_build_convex_volume_fan(*settings"),
                        self.code.index("const double w1_plus_w2 ="))

    def test_compliance_parameter_is_finite(self):
        self.assertIn("Math::is_finite(volume_compliance)", self.settings)
        self.assertIn("MAX(volume_compliance, 0.0f)", self.settings)
        self.assertIn("p_compliance", self.builder)


if __name__ == "__main__":
    unittest.main()
