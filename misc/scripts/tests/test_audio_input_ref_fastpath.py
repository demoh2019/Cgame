"""Audio input COW reference performance regression tests.

Structural checks do not replace runtime thread-safety stress tests.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]

def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AudioInputReadOnlyViewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.driver = source("servers/audio/audio_driver.h")
        cls.server = source("servers/audio/audio_server.cpp")
        cls.microphone = source("scene/resources/audio/audio_stream_microphone.cpp")

    def test_buffer_getter_returns_a_const_reference(self):
        self.assertIn("const Vector<int32_t> &get_input_buffer() { return input_buffer; }", self.driver)

    def test_no_buffer_value_copy_getter(self):
        self.assertNotIn("Vector<int32_t> get_input_buffer() {", self.driver.replace("const Vector<int32_t> &get_input_buffer()", ""))

    def test_server_uses_readonly_view(self):
        self.assertIn("const Vector<int32_t> &buf = ad->get_input_buffer();", self.server)

    def test_microphone_uses_readonly_view(self):
        self.assertIn("const Vector<int32_t> &buf = AudioDriver::get_singleton()->get_input_buffer();", self.microphone)

    def test_server_no_by_value_alias(self):
        self.assertNotIn("Vector<int32_t> buf = ad->get_input_buffer();", self.server)

    def test_microphone_no_by_value_alias(self):
        self.assertNotIn("Vector<int32_t> buf = AudioDriver::get_singleton()->get_input_buffer();", self.microphone)

    def test_driver_buffer_storage_unchanged(self):
        self.assertIn("Vector<int32_t> input_buffer;", self.driver)

    def test_driver_writer_still_uses_writable_buffer(self):
        self.assertIn("input_buffer.write[input_position++] = sample;", source("servers/audio/audio_driver.cpp"))

    def test_microphone_keeps_lock_during_read(self):
        body = self.microphone.split("int AudioStreamPlaybackMicrophone::_mix_internal(", 1)[1]
        self.assertLess(body.index("->lock();"), body.index("const Vector<int32_t> &buf ="))
        self.assertLess(body.index("const Vector<int32_t> &buf ="), body.index("->unlock();"))

    def test_audio_server_keeps_lock_during_read(self):
        body = self.server.split("PackedVector2Array AudioServer::get_input_frames(", 1)[1]
        self.assertLess(body.index("ad->lock();"), body.index("const Vector<int32_t> &buf ="))
        self.assertLess(body.index("const Vector<int32_t> &buf ="), body.index("ad->unlock();"))

    def test_public_getter_api_preserved(self):
        self.assertEqual(self.driver.count("get_input_buffer() {"), 1)

    def test_native_regressions_available(self):
        test = source("tests/servers/test_audio_input_cow.cpp")
        self.assertIn("TEST_CASE(", test)
        self.assertIn("std::is_same_v<", test)
        self.assertIn("samples.ptr() == original", test)


if __name__ == "__main__":
    unittest.main()
