"""InputEvent keycode scan count and explicit Ogg LocalVector include contracts."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class BuildHotpathChecks(unittest.TestCase):
    def test_keycode_count_calculated_once_per_update(self):
        source = (ROOT / "editor/settings/input_event_configuration_dialog.cpp").read_text()
        method = source.split("void InputEventConfigurationDialog::_update_input_list()", 1)[1]
        self.assertIn("const int keycode_count = keycode_get_count();", method)
        self.assertIn("for (int i = 0; i < keycode_count; i++)", method)
        self.assertNotIn("for (int i = 0; i < keycode_get_count(); i++)", method)

    def test_ogg_declares_its_own_local_vector_dependency(self):
        header = (ROOT / "modules/ogg/ogg_packet_sequence.h").read_text()
        self.assertIn('#include "core/templates/local_vector.h"', header)
        self.assertIn("LocalVector<LocalVector<PackedByteArray, int64_t>> page_data;", header)


if __name__ == "__main__":
    unittest.main()
