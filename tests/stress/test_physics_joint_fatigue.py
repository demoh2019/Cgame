"""Numerical and source integration contracts for progressive Joint3D fatigue."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def fatigue(force, torque, force_limit, torque_limit, ratio, rate, dt, damage):
    args = (force, torque, force_limit, torque_limit, ratio, rate, dt, damage)
    if not all(math.isfinite(v) for v in args):
        return damage
    if (force < 0 or torque < 0 or force_limit < 0 or torque_limit < 0
            or not 0 <= ratio <= .99 or rate <= 0 or dt <= 0
            or not 0 <= damage < 1 or (force_limit <= 0 and torque_limit <= 0)):
        return damage
    f = force / force_limit if force_limit > 0 else 0
    t = torque / torque_limit if torque_limit > 0 else 0
    usage = math.hypot(f, t)
    if usage <= ratio:
        return damage
    increment = rate * dt * (usage-ratio)**2
    if increment <= 0:
        return damage
    return min(1., damage+increment)


class TestJointFatigue(unittest.TestCase):
    def test_30000_randomized_nonnegative_bounded_damage(self):
        rng = random.Random(0xAFA716)
        positive = 0
        for _ in range(30000):
            old = rng.random()
            force_limit = 10**rng.uniform(-2, 5)
            torque_limit = 10**rng.uniform(-2, 5)
            force = force_limit*rng.uniform(0, .99)
            torque = torque_limit*rng.uniform(0, .99)
            threshold = rng.uniform(0, .99)
            rate = 10**rng.uniform(-2, 2)
            dt = rng.uniform(.0001, .1)
            next_value = fatigue(force, torque, force_limit, torque_limit,
                                 threshold, rate, dt, old)
            self.assertGreaterEqual(next_value, old)
            self.assertLessEqual(next_value, 1.)
            self.assertTrue(math.isfinite(next_value))
            if next_value > old:
                positive += 1
        self.assertGreater(positive, 20000)

    def test_fixed_load_time_subdivision_consistency(self):
        rng = random.Random(0xFE04)
        for _ in range(12000):
            f = rng.uniform(.2, .9)
            torque = rng.uniform(.2, .9)
            y = rng.uniform(0, .3)
            rate = rng.uniform(.01, 4.)
            dt = rng.uniform(.001, .2)
            full = fatigue(f, torque, 1, 1, y, rate, dt, 0)
            split = 0
            for _ in range(4):
                split = fatigue(f, torque, 1, 1, y, rate, dt/4, split)
            self.assertAlmostEqual(full, split, delta=1e-12)

    def test_fatigue_on_sustained_subcritical_reaction(self):
        d = 0
        for i in range(16):
            d = fatigue(75, 0, 100, 0, .5, 10, .1, d)
        self.assertEqual(d, 1.)
        self.assertEqual(fatigue(30, 0, 100, 0, .5, 10, .1, .2), .2)
        self.assertEqual(fatigue(500, 0, 0, 100, .5, 10, .1, .2), .2)

    def test_source_wiring_scene_server_solver_and_stale_stamp(self):
        joint = (ROOT/"modules/godot_physics_3d/godot_joint_3d.h").read_text()
        server = (ROOT/"modules/godot_physics_3d/godot_physics_server_3d.cpp").read_text()
        api = (ROOT/"servers/physics_3d/physics_server_3d.h").read_text()
        api_bind = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        scene = (ROOT/"scene/3d/physics/joints/joint_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_joint_fatigue.h").read_text()
        self.assertIn("inline static bool physics_joint_accumulate_fatigue_damage(", helper)
        self.assertIn("double fatigue_damage = 0.0;", joint)
        self.assertIn("real_t fatigue_rate = 0.0;", joint)
        self.assertIn("uint64_t fatigue_reaction_stamp = UINT64_MAX;", joint)
        self.assertIn("reaction_stamp == fatigue_reaction_stamp", joint)
        self.assertIn("reaction_stamp == UINT64_MAX", joint)
        self.assertIn("fatigue_reaction_stamp = reaction_stamp;", joint)
        self.assertIn("physics_joint_accumulate_fatigue_damage(", joint)
        self.assertIn("bool accumulate_fatigue(real_t p_delta)", joint)
        self.assertIn("joint->accumulate_fatigue(p_step) && joint->is_fatigue_broken()", server)
        self.assertIn("_process_joint_breaks(p_step);", server)
        self.assertIn("void GodotPhysicsServer3D::joint_set_fatigue_rate(", server)
        self.assertIn("void GodotPhysicsServer3D::joint_set_fatigue_yield_ratio(", server)
        self.assertIn("real_t GodotPhysicsServer3D::joint_get_fatigue_damage(", server)
        self.assertIn("virtual void joint_set_fatigue_rate(", api)
        self.assertIn('D_METHOD("joint_get_fatigue_damage", "joint")', api_bind)
        self.assertIn('D_METHOD("get_fatigue_damage")', scene)
        self.assertIn('ADD_GROUP("Fatigue", "fatigue_")', scene)
        self.assertIn('ADD_SIGNAL(MethodInfo("broken"))', scene)
        self.assertIn("broken_joint_queue.push_back(rid);", server)
        # The instantaneous force/torque path is preserved and checked first.
        self.assertLess(server.index("joint->exceeds_break_threshold()"),
                        server.index("joint->accumulate_fatigue(p_step)"))
        # Rebuilding a new joint transfers *settings*, not accumulated damage.
        self.assertIn("fatigue_rate = p_joint->fatigue_rate;", joint)
        self.assertNotIn("fatigue_damage = p_joint->fatigue_damage", joint)


if __name__ == "__main__":
    unittest.main()
