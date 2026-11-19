"""Jolt ObjectLayer packing/filtering regression contracts.

The Jolt engine stores 32-bit Godot collision layers/masks in a packed uint64_t
and combines them with a 3-bit broadphase class inside a 16-bit ObjectLayer.
Test numerical equivalence to the previous Godot-style OR filter as well as
source wiring; native collision tests are executed separately.
"""

from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
LAYERS_CPP = ROOT / "modules/jolt_physics/spaces/jolt_layers.cpp"
LAYERS_H = ROOT / "modules/jolt_physics/spaces/jolt_layers.h"
RUNTIME = ROOT / "tests/stress/physics_jolt_layer_filter_regression.gd"


def pack(layer: int, mask: int) -> int:
    return ((layer & 0xFFFFFFFF) << 32) | (mask & 0xFFFFFFFF)


def should_collide_packed(packed1: int, packed2: int) -> bool:
    layer1, mask1 = packed1 >> 32, packed1 & 0xFFFFFFFF
    layer2, mask2 = packed2 >> 32, packed2 & 0xFFFFFFFF
    return bool((mask1 & layer2) or (mask2 & layer1))


class JoltLayerPairFilterContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = LAYERS_CPP.read_text(encoding="utf-8")
        cls.header = LAYERS_H.read_text(encoding="utf-8")
        cls.filter = cls.cpp.split(
            "bool JoltLayers::ShouldCollide(JPH::ObjectLayer p_encoded_layer1, JPH::ObjectLayer p_encoded_layer2) const {",
            1,
        )[1].split("bool JoltLayers::ShouldCollide(JPH::ObjectLayer p_encoded_layer1, JPH::BroadPhaseLayer", 1)[0]

    def test_compact_unique_layer_index(self):
        self.assertIn('#include "core/templates/a_hash_map.h"', self.header)
        self.assertIn("AHashMap<uint64_t, JPH::ObjectLayer> layers_by_collision;", self.header)
        self.assertIn("layers_by_collision.getptr(collision)", self.cpp)
        self.assertIn("object_layer = *existing_layer;", self.cpp)
        self.assertIn("layers_by_collision[p_collision] = new_object_layer;", self.cpp)

    def test_body_pair_hot_path_uses_packed_collision_values(self):
        self.assertIn("OBJECT_LAYER_INDEX_BITS = 13", self.cpp)
        self.assertIn("OBJECT_LAYER_INDEX_MASK = (1U << OBJECT_LAYER_INDEX_BITS) - 1U", self.cpp)
        self.assertIn("collisions_by_layer[uint32_t(p_encoded_layer1) & OBJECT_LAYER_INDEX_MASK]", self.filter)
        self.assertIn("collisions_by_layer[uint32_t(p_encoded_layer2) & OBJECT_LAYER_INDEX_MASK]", self.filter)
        self.assertIn("uint32_t(collision1 >> 32U)", self.filter)
        self.assertIn("uint32_t(collision2)", self.filter)
        self.assertNotIn("from_object_layer(", self.filter)
        self.assertIn(
            "(collision_mask1 & collision_layer2) != 0 || (collision_mask2 & collision_layer1) != 0",
            self.filter,
        )

    def test_asymmetric_and_high_bit_masks_keep_old_semantics(self):
        examples = [
            (0x01, 0x02, 0x02, 0, True),
            (0x01, 0, 0x02, 0x01, True),
            (0x01, 0, 0x02, 0, False),
            (0x80000000, 0, 0x01, 0x80000000, True),
            (0x80000000, 0, 0x01, 0x40000000, False),
            (0, 0, 0, 0, False),
        ]
        for layer1, mask1, layer2, mask2, expected in examples:
            with self.subTest(mask=(layer1, mask1, layer2, mask2)):
                self.assertEqual(should_collide_packed(pack(layer1, mask1), pack(layer2, mask2)), expected)

        rng = random.Random(7331)
        for _ in range(10000):
            values = [rng.getrandbits(32) for _ in range(4)]
            layer1, mask1, layer2, mask2 = values
            old = bool((mask1 & layer2) or (mask2 & layer1))
            self.assertEqual(should_collide_packed(pack(layer1, mask1), pack(layer2, mask2)), old)

    def test_broadphase_bits_do_not_change_collision_lookup(self):
        for index in (0, 1, 127, 8191):
            for bp in range(8):
                encoded = (bp << 13) | index
                self.assertEqual(encoded & ((1 << 13) - 1), index)
        self.assertIn("object_layer_count = 1U << OBJECT_LAYER_INDEX_BITS", self.cpp)
        self.assertIn("p_encoded_layers & OBJECT_LAYER_INDEX_MASK", self.cpp)

    def test_runtime_regression_covers_collide_and_noncollide(self):
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("body_set_collision_layer", source)
        self.assertIn("body_set_collision_mask", source)
        self.assertIn("BODY_STATE_LINEAR_VELOCITY", source)
        self.assertIn("1 << 20", source)
        self.assertIn("JOLT_LAYER_FILTER_RESULT:", source)
        self.assertIn("failed_cases", source)


if __name__ == "__main__":
    unittest.main()
