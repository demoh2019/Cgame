"""Fast source-contract and pure admission-model checks for Cgame cue lifecycle.

The native C++ and Albion headless workflows are the build/runtime evidence.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/gameplay_fx/gameplay_cue_queue.cpp"
HDR = ROOT / "modules/gameplay_fx/gameplay_cue_queue.h"
GAME = ROOT / "game/scripts/client/gameplay_cues.gd"


def reserve_lifecycle(pending, requested, priority, capacity=128):
    """Return an all-or-nothing rebuilt queue and committed eviction count."""
    next_queue = list(pending)
    removed = 0
    for event in requested:
        if len(next_queue) >= capacity:
            candidates = [(p, index) for index, (kind, p, _) in enumerate(next_queue)
                          if kind == "executed" and p < priority]
            if not candidates:
                return pending, 0, False
            _, victim = min(candidates)
            next_queue.pop(victim)
            removed += 1
        next_queue.append((event, priority, "persistent"))
    return next_queue, removed, True


class LifecycleAdmissionContract(unittest.TestCase):
    def test_native_transaction_and_legacy_path(self):
        hdr = HDR.read_text()
        impl = CPP.read_text()
        self.assertIn("bool replace_active_resilient(", hdr)
        self.assertIn("bool _replace_active_internal(", hdr)
        self.assertIn("Vector<PendingCue> next_pending = pending;", impl)
        self.assertIn("candidate.type == EVENT_EXECUTED && candidate.priority < p_priority", impl)
        self.assertIn("return _replace_active_internal(p_snapshot, p_priority, false);", impl)
        self.assertIn("return _replace_active_internal(p_snapshot, p_priority, true);", impl)
        self.assertIn("active = validated;\n\tpending = next_pending;", impl)
        self.assertIn('D_METHOD("replace_active_resilient", "snapshot", "priority")', impl)
        self.assertIn("MAX_PENDING = 128", hdr)
        self.assertNotIn("SceneTree::", impl)

    def test_runtime_game_uses_new_api_with_fallback(self):
        bridge = GAME.read_text()
        game = (ROOT / "game/scripts/client/engine_features.gd").read_text()
        tests = (ROOT / "game/tests/test_gameplay_cues.gd").read_text()
        self.assertIn('cues.has_method("replace_active_resilient")', bridge)
        self.assertIn('cues.call("replace_active_resilient", next, 2)', bridge)
        self.assertIn('cues.call("replace_active", next, 2)', bridge)
        self.assertIn("GameplayCues.sync(node, kind, snapshot)", game)
        self.assertIn("status start", tests)
        self.assertIn("status stop events reliably clean up", tests)
        doc = ET.parse(ROOT / "modules/gameplay_fx/doc_classes/GameplayCueQueue.xml")
        self.assertTrue(any(x.get("name") == "replace_active_resilient"
                            for x in doc.getroot().findall("methods/method")))

    def test_admission_does_not_lose_lifecycle_or_critical_effects(self):
        full_ambient = [("executed", 0, str(i)) for i in range(128)]
        accepted, drops, ok = reserve_lifecycle(full_ambient, ["started", "stopped"], 2)
        self.assertTrue(ok)
        self.assertEqual(drops, 2)
        self.assertEqual(len(accepted), 128)
        self.assertEqual(accepted[-2:], [("started", 2, "persistent"),
                                         ("stopped", 2, "persistent")])
        self.assertEqual(len([e for e in accepted if e[0] == "executed"]), 126)
        critical = [("executed", 7, str(i)) for i in range(127)] + [("executed", 0, "small")]
        retained, drops, ok = reserve_lifecycle(critical, ["started", "stopped"], 2)
        self.assertFalse(ok)
        self.assertEqual(drops, 0)
        self.assertEqual(retained, critical)
        retained, drops, ok = reserve_lifecycle(
            [("started", 2, "status")] + [("executed", 7, str(i)) for i in range(127)],
            ["stopped"], 2)
        self.assertFalse(ok)
        self.assertEqual(drops, 0)


if __name__ == "__main__":
    unittest.main()
