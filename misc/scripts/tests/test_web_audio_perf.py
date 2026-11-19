"""WebAudio hot path contracts accompanying executable JS mixer regression."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class WebAudioPerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = (ROOT / "platform/web/js/libs/library_godot_audio.js").read_text()

    def test_per_channel_gain_cache(self):
        self.assertIn("new Array(NUMBER_OF_WEB_CHANNELS).fill(NaN)", self.code)

    def test_value_change_guard(self):
        self.assertIn("cachedGain[channel] !== gain", self.code)

    def test_all_six_channels_guarded(self):
        for channel in ("L", "R", "SL", "SR", "C", "LFE"):
            self.assertIn("updateChannelGain(WebChannel.CHANNEL_" + channel, self.code)

    def test_volume_slice_is_zero_copy(self):
        self.assertIn("volumes.subarray(idx * size, (idx * size) + size)", self.code)
        self.assertNotIn("volumes.slice(idx * size, (idx * size) + size)", self.code)

    def test_invalid_volume_length_is_still_checked(self):
        self.assertIn("if (volume.length !== MAX_VOLUME_CHANNELS)", self.code)

    def test_runtime_regression_present(self):
        script = (ROOT / "misc/scripts/tests/test_web_audio_volume.cjs").read_text()
        self.assertIn("vm.runInNewContext", script)
        self.assertIn("repeated frames perform no AudioParam writes", script)


if __name__ == "__main__":
    unittest.main()
