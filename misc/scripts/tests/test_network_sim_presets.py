"""Portable regression cases for named multiplayer network simulation profiles."""

import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from network_sim_presets import FIELDS, PRESETS, resolve_preset


class NetworkPresetTests(unittest.TestCase):
    def test_names_include_sane_default_and_adverse_networks(self):
        self.assertEqual(set(PRESETS), {"clean", "fiber", "wifi", "mobile", "satellite", "severe"})

    def test_each_profile_has_all_four_transport_parameters(self):
        for name, values in PRESETS.items():
            with self.subTest(name=name):
                self.assertEqual(set(values), set(FIELDS))
                self.assertEqual(set(resolve_preset(name)), set(FIELDS))

    def test_clean_preset_has_no_impairments(self):
        self.assertEqual(resolve_preset("clean"), dict(latency_ms=0.0, jitter_ms=0.0, loss_percent=0.0, duplicate_percent=0.0))

    def test_named_profile_not_mutated_by_override(self):
        original = resolve_preset("mobile")
        changed = resolve_preset("mobile", {"latency_ms": 0})
        self.assertEqual(changed["latency_ms"], 0)
        self.assertEqual(resolve_preset("mobile"), original)

    def test_explicit_zero_overrides_preset(self):
        profile = resolve_preset("severe", {"loss_percent": 0.0, "duplicate_percent": 0.0, "jitter_ms": 0.0})
        self.assertEqual(profile["loss_percent"], 0.0)
        self.assertEqual(profile["duplicate_percent"], 0.0)
        self.assertEqual(profile["jitter_ms"], 0.0)
        self.assertEqual(profile["latency_ms"], PRESETS["severe"]["latency_ms"])

    def test_missing_and_none_overrides_keep_preset_values(self):
        self.assertEqual(resolve_preset("wifi", {"jitter_ms": None}), resolve_preset("wifi"))

    def test_separate_policies_are_independent(self):
        a = resolve_preset("wifi")
        b = resolve_preset("wifi")
        a["loss_percent"] = 99
        self.assertEqual(b["loss_percent"], 2)

    def test_unrecognized_profile_fails(self):
        for name in ("", "WIFI", "4g", "secret"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                resolve_preset(name)

    def test_non_string_profile_fails(self):
        for name in (None, [], 0):
            with self.subTest(name=name), self.assertRaises(ValueError):
                resolve_preset(name)

    def test_unrecognized_field_fails(self):
        with self.assertRaisesRegex(ValueError, "Unknown network parameter"):
            resolve_preset("wifi", {"target_host": "127.0.0.1"})

    def test_nan_infinity_and_negative_are_rejected(self):
        for field in FIELDS:
            for value in (float("nan"), float("inf"), -1.0, float("-inf")):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    resolve_preset("wifi", {field: value})

    def test_limits_for_delay_and_percentages(self):
        for field in FIELDS:
            valid_max = 120000 if field.endswith("_ms") else 100
            self.assertEqual(resolve_preset("clean", {field: valid_max})[field], valid_max)
            with self.assertRaises(ValueError):
                resolve_preset("clean", {field: valid_max + 0.01})

    def test_string_boolean_and_none_are_handled(self):
        for value in ("12", True, False, object()):
            with self.subTest(value=value), self.assertRaises(ValueError):
                resolve_preset("wifi", {"loss_percent": value})
        self.assertEqual(resolve_preset("wifi", {"loss_percent": None})["loss_percent"], 2.0)

    def test_integration_values_for_each_profile(self):
        for name in PRESETS:
            data = resolve_preset(name)
            self.assertGreaterEqual(data["latency_ms"], 0)
            self.assertGreaterEqual(data["jitter_ms"], 0)
            self.assertLessEqual(data["loss_percent"], 100)
            self.assertLessEqual(data["duplicate_percent"], 100)


if __name__ == "__main__":
    unittest.main()
