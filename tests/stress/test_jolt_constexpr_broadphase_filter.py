"""Jolt broadphase object-layer packing and filter matrix contracts.

The 16-bit ObjectLayer layout is 3 broadphase bits + 13 collision-mask index
bits. This test compares all 5x5 directed broadphase combinations and 10000
random packed ObjectLayers against the old decode-based implementation.
Real native Area3D callbacks are checked by the companion GDScript fixture.
"""

from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/spaces/jolt_layers.cpp"
BROADPHASE_H = ROOT / "modules/jolt_physics/spaces/jolt_broad_phase_layer.h"
RUNTIME = ROOT / "tests/stress/physics_jolt_broadphase_filter_regression.gd"

STATIC = 0
STATIC_BIG = 1
DYNAMIC = 2
AREA_DETECTABLE = 3
AREA_UNDETECTABLE = 4
INDEX_BITS = 13
INDEX_MASK = (1 << INDEX_BITS) - 1

# Directed row masks reconstructed from the original JoltBroadPhaseMatrix.
REFERENCE_ROWS = (
    (1 << DYNAMIC) | (1 << AREA_DETECTABLE) | (1 << AREA_UNDETECTABLE),
    (1 << DYNAMIC) | (1 << AREA_DETECTABLE) | (1 << AREA_UNDETECTABLE),
    (1 << STATIC) | (1 << STATIC_BIG) | (1 << DYNAMIC)
    | (1 << AREA_DETECTABLE) | (1 << AREA_UNDETECTABLE),
    (1 << STATIC) | (1 << STATIC_BIG) | (1 << DYNAMIC)
    | (1 << AREA_DETECTABLE) | (1 << AREA_UNDETECTABLE),
    (1 << STATIC) | (1 << STATIC_BIG) | (1 << DYNAMIC) | (1 << AREA_DETECTABLE),
)


def optimized_broadphase_layer(encoded: int) -> int:
    return (encoded >> INDEX_BITS) & 7


def old_broadphase_filter(encoded: int, second_layer: int) -> bool:
    first_layer, _object_index = divmod(encoded, 1 << INDEX_BITS)
    return bool(REFERENCE_ROWS[first_layer] & (1 << second_layer))


def optimized_broadphase_filter(encoded: int, second_layer: int) -> bool:
    return bool(REFERENCE_ROWS[optimized_broadphase_layer(encoded)] & (1 << second_layer))


class JoltConstexprBroadphaseFilterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SOURCE.read_text(encoding="utf-8")
        cls.broadphase_header = BROADPHASE_H.read_text(encoding="utf-8")
        cls.get_layer = cls.code.split(
            "JPH::BroadPhaseLayer JoltLayers::GetBroadPhaseLayer(JPH::ObjectLayer p_layer) const {", 1
        )[1].split("\n}", 1)[0]
        cls.filter = cls.code.split(
            "bool JoltLayers::ShouldCollide(JPH::ObjectLayer p_encoded_layer1, JPH::BroadPhaseLayer p_broad_phase_layer2) const {", 1
        )[1].split("\n}", 1)[0]

    def test_broadphase_matrix_is_fully_constexpr(self):
        self.assertIn("constexpr JoltBroadPhaseMatrix() {", self.code)
        self.assertIn("constexpr void allow_collision(UnderlyingType", self.code)
        self.assertIn("constexpr void allow_collision(LayerType", self.code)
        self.assertIn("constexpr bool should_collide(UnderlyingType", self.code)
        self.assertIn("constexpr bool should_collide(LayerType", self.code)
        self.assertIn("static constexpr JoltBroadPhaseMatrix matrix;", self.filter)
        self.assertNotIn("static const JoltBroadPhaseMatrix matrix;", self.filter)

    def test_direct_unpack_avoids_decoding_unused_index(self):
        self.assertIn("uint32_t(p_layer) >> OBJECT_LAYER_INDEX_BITS", self.get_layer)
        self.assertIn("uint32_t(p_encoded_layer1) >> OBJECT_LAYER_INDEX_BITS", self.filter)
        self.assertNotIn("decode_layers(", self.get_layer)
        self.assertNotIn("decode_layers(", self.filter)
        self.assertIn("matrix.should_collide(broad_phase_layer1, p_broad_phase_layer2)", self.filter)

    def test_layer_id_mapping_remains_unchanged(self):
        self.assertIn("BODY_STATIC(0)", self.broadphase_header)
        self.assertIn("BODY_STATIC_BIG(1)", self.broadphase_header)
        self.assertIn("BODY_DYNAMIC(2)", self.broadphase_header)
        self.assertIn("AREA_DETECTABLE(3)", self.broadphase_header)
        self.assertIn("AREA_UNDETECTABLE(4)", self.broadphase_header)
        self.assertIn("COUNT = 5", self.broadphase_header)
        self.assertIn("OBJECT_LAYER_INDEX_BITS = 13", self.code)

    def test_all_directed_layer_categories(self):
        self.assertEqual(REFERENCE_ROWS, (28, 28, 31, 31, 15))
        for first in range(5):
            for second in range(5):
                for index in (0, 1, 127, 8191):
                    with self.subTest(first=first, second=second, index=index):
                        encoded = (first << INDEX_BITS) | index
                        self.assertEqual(optimized_broadphase_layer(encoded), first)
                        self.assertEqual(
                            optimized_broadphase_filter(encoded, second),
                            old_broadphase_filter(encoded, second),
                        )

    def test_filter_matrix_does_not_accidentally_symmetricize(self):
        self.assertFalse(optimized_broadphase_filter(STATIC << INDEX_BITS, STATIC))
        self.assertTrue(optimized_broadphase_filter(DYNAMIC << INDEX_BITS, STATIC))
        self.assertTrue(optimized_broadphase_filter(AREA_UNDETECTABLE << INDEX_BITS, DYNAMIC))
        self.assertFalse(optimized_broadphase_filter(AREA_UNDETECTABLE << INDEX_BITS, AREA_UNDETECTABLE))
        self.assertTrue(optimized_broadphase_filter(AREA_DETECTABLE << INDEX_BITS, AREA_UNDETECTABLE))

    def test_random_packed_layers_agree_with_old_decoder(self):
        rng = random.Random(20261119)
        for _ in range(10000):
            broadphase = rng.randrange(5)
            index = rng.randrange(INDEX_MASK + 1)
            encoded = (broadphase << INDEX_BITS) | index
            second = rng.randrange(5)
            self.assertEqual(
                optimized_broadphase_filter(encoded, second),
                old_broadphase_filter(encoded, second),
            )

    def test_native_area_categories_are_exercised(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("PhysicsServer3D.area_set_monitorable(area, i == 0)", code)
        self.assertIn("PhysicsServer3D.area_set_monitor_callback", code)
        self.assertIn("PhysicsServer3D.BODY_MODE_RIGID", code)
        self.assertIn("PhysicsServer3D.AREA_BODY_ADDED", code)
        self.assertIn("PhysicsServer3D.AREA_BODY_REMOVED", code)
        self.assertIn("JOLT_BROADPHASE_FILTER_RESULT:", code)
        self.assertIn("Jolt broadphase filter regression passed.", code)


if __name__ == "__main__":
    unittest.main()
