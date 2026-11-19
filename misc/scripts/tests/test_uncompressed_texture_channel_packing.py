"""VRAM-uncompressed channel packing contracts and HDR preservation."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]

class TextureChannelPacking(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image=(ROOT/"core/io/image.cpp").read_text()
        cls.importer=(ROOT/"editor/import/resource_importer_texture.cpp").read_text()
        cls.method=cls.image.split("void Image::optimize_from_channels(UsedChannels p_channels) {",1)[1].split("\nvoid Image::optimize_channels()",1)[0]

    def test_alpha_and_grayscale_channel_packing(self):
        self.assertIn("case USED_CHANNELS_L:",self.method)
        self.assertIn("convert(FORMAT_L8);",self.method)
        self.assertIn("case USED_CHANNELS_LA:",self.method)
        self.assertIn("convert(FORMAT_LA8);",self.method)
        self.assertIn("convert(FORMAT_RG8);",self.method)
        self.assertIn("convert(FORMAT_RGB8);",self.method)

    def test_hdr_sources_do_not_downgrade_to_8bit(self):
        self.assertIn("convert(FORMAT_RGBF);",self.method)
        self.assertIn("convert(FORMAT_RGBH);",self.method)
        self.assertIn("convert(FORMAT_RGF);",self.method)
        self.assertIn("convert(FORMAT_RGH);",self.method)

    def test_uncompressed_import_converts_only_duplicated_image(self):
        block=self.importer.split("case COMPRESS_VRAM_UNCOMPRESSED: {",1)[1].split("case COMPRESS_BASIS_UNIVERSAL:",1)[0]
        self.assertIn("Ref<Image> image = p_image->duplicate();",block)
        self.assertIn("image->optimize_from_channels(p_channels);",block)
        self.assertIn("image->get_data()",block)
        self.assertNotIn("p_image->get_data()",block)

    def test_channel_detection_is_enabled_for_uncompressed_vram(self):
        self.assertIn("p_compress_mode == COMPRESS_VRAM_UNCOMPRESSED",self.importer)

if __name__=="__main__":
    unittest.main()
