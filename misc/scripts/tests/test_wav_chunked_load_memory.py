"""Ensure WAV disk loading has O(1) temporary sample storage."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class WAVChunkedLoadContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(ROOT/"scene/resources/audio/audio_stream_wav.cpp").read_text(encoding="utf-8")
        cls.header=(ROOT/"scene/resources/audio/audio_stream_wav.h").read_text(encoding="utf-8")
        cls.load=cls.source.split("Ref<AudioStreamWAV> AudioStreamWAV::load_from_file(",1)[1].split(
            "\nvoid AudioStreamWAV::_bind_methods()",1)[0]
        cls.helper=cls.source.split("Ref<AudioStreamWAV> AudioStreamWAV::_load_from_file_access(",1)[1].split(
            "\nRef<AudioStreamWAV> AudioStreamWAV::load_from_buffer(",1)[0]

    def test_disk_load_uses_file_access_instead_of_whole_file_copy(self):
        self.assertNotIn("FileAccess::get_file_as_bytes(",self.load)
        self.assertIn("FileAccess::open(p_path, FileAccess::READ",self.load)
        self.assertIn("return _load_from_file_access(file, p_options);",self.load)

    def test_4096_byte_chunk_is_bounded_and_reused(self):
        self.assertIn("uint8_t sample_buffer[4096];",self.helper)
        self.assertIn("const uint32_t bytes_per_frame",self.helper)
        self.assertIn("file->get_buffer(sample_buffer, block_bytes)",self.helper)
        self.assertIn("sample_file->seek(0);",self.helper)
        self.assertIn("frames_done += block_frames;",self.helper)
        self.assertIn("sample_file->get_double()",self.helper)
        self.assertIn("sample_file->get_16()",self.helper)

    def test_public_buffer_api_still_uses_same_decoder(self):
        self.assertIn("static Ref<AudioStreamWAV> _load_from_file_access",self.header)
        self.assertIn("Ref<AudioStreamWAV> AudioStreamWAV::load_from_buffer(",self.source)
        self.assertEqual(self.source.count("return _load_from_file_access(file, p_options);"),2)

if __name__=="__main__":
    unittest.main()
