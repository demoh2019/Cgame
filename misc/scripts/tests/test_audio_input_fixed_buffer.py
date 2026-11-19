"""Source safety and performance contracts for upstream #125533 audio capture.

These are not a substitute for TSAN / native device concurrency tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(name):
    return (ROOT / name).read_text(encoding="utf-8")


DRIVER = read("servers/audio/audio_driver.cpp")
HEADER = read("servers/audio/audio_driver.h")
SERVER = read("servers/audio/audio_server.cpp")
MIC = read("scene/resources/audio/audio_stream_microphone.cpp")
WEB = read("platform/web/audio_driver_web.cpp")
PULSE = read("drivers/pulseaudio/audio_driver_pulseaudio.cpp")
WASAPI = read("drivers/wasapi/audio_driver_wasapi.cpp")
COREAUDIO = read("drivers/coreaudio/audio_driver_coreaudio.mm")
NATIVE = read("tests/servers/test_audio_input_cow.cpp")


class FixedAudioCaptureBufferContracts(unittest.TestCase):
    def test_ring_buffer_is_pinned_on_first_init(self):
        self.assertIn("if (input_buffer_data == nullptr)", DRIVER)
        self.assertIn("input_buffer_data = input_buffer.ptrw();", DRIVER)
        self.assertIn("int32_t *input_buffer_data = nullptr;", HEADER)

    def test_atomic_position_size(self):
        for name in ("input_position", "input_size"):
            with self.subTest(name=name):
                self.assertIn("SafeNumeric<unsigned int> " + name, HEADER)
                self.assertIn(name + ".set(0);", DRIVER)
                self.assertIn(name + ".get()", DRIVER)

    def test_capture_directly_writes_into_pinned_samples(self):
        self.assertIn("input_buffer_data[v_input_position++] = sample;", DRIVER)
        self.assertNotIn("input_buffer.write[input_position++]", DRIVER)

    def test_readers_only_see_nonowning_view(self):
        self.assertIn("const int32_t *get_input_buffer_data()", HEADER)
        self.assertNotIn("get_input_buffer()", HEADER)
        self.assertIn("const int32_t *buf = ad->get_input_buffer_data();", SERVER)
        self.assertIn("const int32_t *buf = AudioDriver::get_singleton()->get_input_buffer_data();", MIC)

    def test_server_capture_never_takes_device_output_lock(self):
        begin = SERVER.index("int AudioServer::get_input_frames_available()")
        end = SERVER.index("void AudioServer::set_enable_tagging_used_audio_streams(", begin)
        body = SERVER[begin:end]
        self.assertNotIn("ad->lock();", body)
        self.assertNotIn("ad->unlock();", body)

    def test_microphone_mixing_never_takes_output_lock(self):
        begin = MIC.index("int AudioStreamPlaybackMicrophone::_mix_internal(")
        end = MIC.index("int AudioStreamPlaybackMicrophone::mix(", begin)
        body = MIC[begin:end]
        self.assertNotIn("AudioDriver::get_singleton()->lock();", body)
        self.assertIn("get_input_buffer_size()", body)

    def test_platform_reset_paths_use_atomic_set(self):
        for platform, source in (("coreaudio", COREAUDIO), ("pulseaudio", PULSE), ("wasapi", WASAPI)):
            with self.subTest(platform=platform):
                self.assertIn("input_position.set(0);", source)
                self.assertIn("input_size.set(0);", source)

    def test_web_restarts_keep_buffer_memory_alive(self):
        start = WEB.index("Error AudioDriverWeb::input_stop()")
        end = WEB.index("bool AudioDriverWeb::is_stream_registered", start)
        method = WEB[start:end]
        self.assertNotIn("input_buffer.clear()", method)
        self.assertIn("input_position.set(0);", method)
        self.assertIn("input_size.set(0);", method)

    def test_web_input_start_reuses_init_and_clears_cursors(self):
        self.assertIn("input_buffer_init(buffer_length);", WEB)
        self.assertIn("if (input_buffer_data == nullptr)", DRIVER)

    def test_audio_buffer_native_test_checks_fixed_pointer_type(self):
        self.assertIn("get_input_buffer_data()", NATIVE)
        self.assertIn("const int32_t *view = original;", NATIVE)

    def test_source_wraps_ring_on_buffer_size(self):
        self.assertIn("if ((int)v_input_position >= input_buffer.size())", DRIVER)
        self.assertIn("v_input_position = 0;", DRIVER)


if __name__ == "__main__":
    unittest.main()
