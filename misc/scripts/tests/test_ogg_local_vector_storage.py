"""Ogg packet storage allocation and round-trip invariants."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]

class OggLocalStorage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code=(ROOT/"modules/ogg/ogg_packet_sequence.cpp").read_text()
        cls.header=(ROOT/"modules/ogg/ogg_packet_sequence.h").read_text()
        cls.stream=(ROOT/"modules/vorbis/audio_stream_ogg_vorbis.cpp").read_text()

    def test_storage_uses_locally_owned_arrays(self):
        self.assertIn("LocalVector<LocalVector<PackedByteArray, int64_t>> page_data;",self.header)
        self.assertIn("LocalVector<uint64_t, int64_t> page_granule_positions;",self.header)
        self.assertIn("LocalVector<PackedByteArray, int64_t> &p_data",self.header)

    def test_round_trip_preallocates_exact_output(self):
        self.assertIn("page_data.resize(p_data.size());",self.code)
        self.assertIn("page_data[page_idx].resize(this_page_data.size());",self.code)
        self.assertIn("ret.resize(page_data.size())",self.code)
        self.assertIn("page_variant.resize(page.size())",self.code)
        self.assertIn("ret.resize(page_granule_positions.size())",self.code)
        self.assertIn("data_version++;",self.code)

    def test_vorbis_importer_uses_tight_buffers(self):
        self.assertIn("RBMap<uint64_t, LocalVector<PackedByteArray, int64_t>> sorted_packets;",self.stream)
        self.assertIn("packet_data.reserve(packet_data.size() + pair.value.size());",self.stream)
        self.assertNotIn("RBMap<uint64_t, Vector<Vector<uint8_t>>> sorted_packets;",self.stream)

if __name__=="__main__":
    unittest.main()
