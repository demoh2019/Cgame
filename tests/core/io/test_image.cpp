/**************************************************************************/
/*  test_image.cpp                                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_image)

#include "core/io/file_access.h"
#include "core/io/image.h"
#include "tests/test_utils.h"

#include "modules/modules_enabled.gen.h" // For bmp, jpg, svg, webp, tga, exr.

namespace TestImage {

TEST_CASE("[Image] Instantiation") {
	Ref<Image> image = memnew(Image(8, 4, false, Image::FORMAT_RGBA8));
	CHECK_MESSAGE(
			!image->is_empty(),
			"An image created with specified size and format should not be empty at first.");
	CHECK_MESSAGE(
			image->is_invisible(),
			"A newly created image should be invisible.");
	CHECK_MESSAGE(
			!image->is_compressed(),
			"A newly created image should not be compressed.");
	CHECK(!image->has_mipmaps());

	PackedByteArray image_data = image->get_data();
	for (int i = 0; i < image_data.size(); i++) {
		CHECK_MESSAGE(
				image_data[i] == 0,
				"An image created without data specified should have its data zeroed out.");
	}

	Ref<Image> image_copy = memnew(Image());
	CHECK_MESSAGE(
			image_copy->is_empty(),
			"An image created without any specified size and format be empty at first.");
	image_copy->copy_internals_from(image);

	CHECK_MESSAGE(
			image->get_data() == image_copy->get_data(),
			"Duplicated images should have the same data.");

	image_data = image->get_data();
	Ref<Image> image_from_data = memnew(Image(8, 4, false, Image::FORMAT_RGBA8, image_data));
	CHECK_MESSAGE(
			image->get_data() == image_from_data->get_data(),
			"An image created from data of another image should have the same data of the original image.");
}

TEST_CASE("[Image] Saving and loading") {
	Ref<Image> image = memnew(Image(4, 4, false, Image::FORMAT_RGBA8));
	const String save_path_png = TestUtils::get_temp_path("image.png");
#ifdef MODULE_TINYEXR_ENABLED
	const String save_path_exr = TestUtils::get_temp_path("image.exr");
#endif // MODULE_TINYEXR_ENABLED

	// Save PNG
	Error err;
	err = image->save_png(save_path_png);
	CHECK_MESSAGE(
			err == OK,
			"The image should be saved successfully as a .png file.");

	// Only available on editor builds.
#ifdef MODULE_TINYEXR_ENABLED
	// Save EXR
	err = image->save_exr(save_path_exr, false);
	CHECK_MESSAGE(
			err == OK,
			"The image should be saved successfully as an .exr file.");
#endif // MODULE_TINYEXR_ENABLED

	// Load using load()
	Ref<Image> image_load = memnew(Image());
	err = image_load->load(save_path_png);
	CHECK_MESSAGE(
			err == OK,
			"The image should load successfully using load().");
	CHECK_MESSAGE(
			image->get_data() == image_load->get_data(),
			"The loaded image should have the same data as the one that got saved.");

#ifdef MODULE_BMP_ENABLED
	// Load BMP
	Ref<Image> image_bmp = memnew(Image());
	Ref<FileAccess> f_bmp = FileAccess::open(TestUtils::get_data_path("images/icon.bmp"), FileAccess::READ, &err);
	REQUIRE(f_bmp.is_valid());
	PackedByteArray data_bmp;
	data_bmp.resize(f_bmp->get_length() + 1);
	f_bmp->get_buffer(data_bmp.ptrw(), f_bmp->get_length());
	CHECK_MESSAGE(
			image_bmp->load_bmp_from_buffer(data_bmp) == OK,
			"The BMP image should load successfully.");
#endif // MODULE_BMP_ENABLED

#ifdef MODULE_TINYEXR_ENABLED
	// Load EXR
	Ref<Image> image_exr;
	image_exr.instantiate();
	Ref<FileAccess> f_exr = FileAccess::open(TestUtils::get_data_path("images/icon.exr"), FileAccess::READ, &err);
	REQUIRE(f_exr.is_valid());
	PackedByteArray data_exr;
	data_exr.resize(f_exr->get_length() + 1);
	f_exr->get_buffer(data_exr.ptrw(), f_exr->get_length());
	CHECK_MESSAGE(
			image_exr->load_exr_from_buffer(data_exr) == OK,
			"The EXR image should load successfully.");
#endif // MODULE_TINYEXR_ENABLED

#ifdef MODULE_JPG_ENABLED
	// Load JPG
	Ref<Image> image_jpg = memnew(Image());
	Ref<FileAccess> f_jpg = FileAccess::open(TestUtils::get_data_path("images/icon.jpg"), FileAccess::READ, &err);
	REQUIRE(f_jpg.is_valid());
	PackedByteArray data_jpg;
	data_jpg.resize(f_jpg->get_length() + 1);
	f_jpg->get_buffer(data_jpg.ptrw(), f_jpg->get_length());
	CHECK_MESSAGE(
			image_jpg->load_jpg_from_buffer(data_jpg) == OK,
			"The JPG image should load successfully.");

	Ref<Image> image_grayscale_jpg = memnew(Image());
	Ref<FileAccess> f_grayscale_jpg = FileAccess::open(TestUtils::get_data_path("images/grayscale.jpg"), FileAccess::READ, &err);
	REQUIRE(f_grayscale_jpg.is_valid());
	PackedByteArray data_grayscale_jpg;
	data_grayscale_jpg.resize(f_grayscale_jpg->get_length() + 1);
	f_grayscale_jpg->get_buffer(data_grayscale_jpg.ptrw(), f_grayscale_jpg->get_length());
	CHECK_MESSAGE(
			image_jpg->load_jpg_from_buffer(data_grayscale_jpg) == OK,
			"The grayscale JPG image should load successfully.");

	// Save JPG
	const String save_path_jpg = TestUtils::get_temp_path("image.jpg");
	CHECK_MESSAGE(image->save_jpg(save_path_jpg) == OK,
			"The image should be saved successfully as a .jpg file.");

#ifdef MODULE_SVG_ENABLED
	// Load SVG with embedded jpg image
	Ref<Image> image_svg = memnew(Image());
	Ref<FileAccess> f_svg = FileAccess::open(TestUtils::get_data_path("images/embedded_jpg.svg"), FileAccess::READ, &err);
	REQUIRE(f_svg.is_valid());
	PackedByteArray data_svg;
	data_svg.resize(f_svg->get_length() + 1);
	f_svg->get_buffer(data_svg.ptrw(), f_svg->get_length());
	CHECK_MESSAGE(
			image_svg->load_svg_from_buffer(data_svg) == OK,
			"The SVG image should load successfully.");
#endif // MODULE_SVG_ENABLED
#endif // MODULE_JPG_ENABLED

#ifdef MODULE_WEBP_ENABLED
	// Load WebP
	Ref<Image> image_webp = memnew(Image());
	Ref<FileAccess> f_webp = FileAccess::open(TestUtils::get_data_path("images/icon.webp"), FileAccess::READ, &err);
	REQUIRE(f_webp.is_valid());
	PackedByteArray data_webp;
	data_webp.resize(f_webp->get_length() + 1);
	f_webp->get_buffer(data_webp.ptrw(), f_webp->get_length());
	CHECK_MESSAGE(
			image_webp->load_webp_from_buffer(data_webp) == OK,
			"The WebP image should load successfully.");
#endif // MODULE_WEBP_ENABLED

	// Load PNG
	Ref<Image> image_png = memnew(Image());
	Ref<FileAccess> f_png = FileAccess::open(TestUtils::get_data_path("images/icon.png"), FileAccess::READ, &err);
	REQUIRE(f_png.is_valid());
	PackedByteArray data_png;
	data_png.resize(f_png->get_length() + 1);
	f_png->get_buffer(data_png.ptrw(), f_png->get_length());
	CHECK_MESSAGE(
			image_png->load_png_from_buffer(data_png) == OK,
			"The PNG image should load successfully.");

#ifdef MODULE_TGA_ENABLED
	// Load TGA
	Ref<Image> image_tga = memnew(Image());
	Ref<FileAccess> f_tga = FileAccess::open(TestUtils::get_data_path("images/icon.tga"), FileAccess::READ, &err);
	REQUIRE(f_tga.is_valid());
	PackedByteArray data_tga;
	data_tga.resize(f_tga->get_length() + 1);
	f_tga->get_buffer(data_tga.ptrw(), f_tga->get_length());
	CHECK_MESSAGE(
			image_tga->load_tga_from_buffer(data_tga) == OK,
			"The TGA image should load successfully.");
#endif // MODULE_TGA_ENABLED
}

TEST_CASE("[Image] Basic getters") {
	Ref<Image> image = memnew(Image(8, 4, false, Image::FORMAT_LA8));
	CHECK(image->get_width() == 8);
	CHECK(image->get_height() == 4);
	CHECK(image->get_size() == Vector2(8, 4));
	CHECK(image->get_format() == Image::FORMAT_LA8);
	CHECK(image->get_used_rect() == Rect2i(0, 0, 0, 0));
	Ref<Image> image_get_rect = image->get_region(Rect2i(0, 0, 2, 1));
	CHECK(image_get_rect->get_size() == Vector2(2, 1));
}

TEST_CASE("[Image] Resizing") {
	Ref<Image> image = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	// Crop
	image->crop(4, 4);
	CHECK_MESSAGE(
			image->get_size() == Vector2(4, 4),
			"get_size() should return the correct size after cropping.");
	image->set_pixel(0, 0, Color(1, 1, 1, 1));

	// Resize
	for (int i = 0; i < 5; i++) {
		Ref<Image> image_resized = memnew(Image());
		image_resized->copy_internals_from(image);
		Image::Interpolation interpolation = static_cast<Image::Interpolation>(i);
		image_resized->resize(8, 8, interpolation);
		CHECK_MESSAGE(
				image_resized->get_size() == Vector2(8, 8),
				"get_size() should return the correct size after resizing.");
		CHECK_MESSAGE(
				image_resized->get_pixel(1, 1).a > 0,
				"Resizing an image should also affect its content.");
	}

	// shrink_x2()
	image->shrink_x2();
	CHECK_MESSAGE(
			image->get_size() == Vector2(2, 2),
			"get_size() should return the correct size after shrink_x2().");

	// resize_to_po2()
	Ref<Image> image_po_2 = memnew(Image(14, 28, false, Image::FORMAT_RGBA8));
	image_po_2->resize_to_po2();
	CHECK_MESSAGE(
			image_po_2->get_size() == Vector2(16, 32),
			"get_size() should return the correct size after resize_to_po2().");
}

TEST_CASE("[Image] Modifying pixels of an image") {
	Ref<Image> image = memnew(Image(3, 3, false, Image::FORMAT_RGBA8));
	image->set_pixel(0, 0, Color(1, 1, 1, 1));
	CHECK_MESSAGE(
			!image->is_invisible(),
			"Image should not be invisible after drawing on it.");
	CHECK_MESSAGE(
			image->get_pixelv(Vector2(0, 0)).is_equal_approx(Color(1, 1, 1, 1)),
			"Image's get_pixel() should return the same color value as the one being set with set_pixel() in the same position.");
	CHECK_MESSAGE(
			image->get_used_rect() == Rect2i(0, 0, 1, 1),
			"Image's get_used_rect should return the expected value, larger than Rect2i(0, 0, 0, 0) if it's visible.");

	image->set_pixelv(Vector2(0, 0), Color(0.5, 0.5, 0.5, 0.5));
	Ref<Image> image2 = memnew(Image(3, 3, false, Image::FORMAT_RGBA8));

	// Fill image with color
	image2->fill(Color(0.5, 0.5, 0.5, 0.5));
	for (int m = 0; m < image2->get_mipmap_count(); m++) {
		Ref<Image> mip_image = image2->get_image_from_mipmap(m);

		for (int y = 0; y < mip_image->get_height(); y++) {
			for (int x = 0; x < mip_image->get_width(); x++) {
				CHECK_MESSAGE(
						mip_image->get_pixel(x, y).r > 0.49,
						"fill() should colorize all pixels of the image.");
			}
		}
	}

	// Fill rect with color
	{
		const int img_width = 3;
		const int img_height = 3;
		Vector<Rect2i> rects;
		rects.push_back(Rect2i());
		rects.push_back(Rect2i(-5, -5, 3, 3));
		rects.push_back(Rect2i(img_width, 0, 12, 12));
		rects.push_back(Rect2i(0, img_height, 12, 12));
		rects.push_back(Rect2i(img_width + 1, img_height + 2, 12, 12));
		rects.push_back(Rect2i(1, 1, 1, 1));
		rects.push_back(Rect2i(0, 1, 2, 3));
		rects.push_back(Rect2i(-5, 0, img_width + 10, 2));
		rects.push_back(Rect2i(0, -5, 2, img_height + 10));
		rects.push_back(Rect2i(-1, -1, img_width + 1, img_height + 1));

		for (const Rect2i &rect : rects) {
			Ref<Image> img = memnew(Image(img_width, img_height, false, Image::FORMAT_RGBA8));
			img->fill_rect(rect, Color(1, 1, 1, 1));
			for (int y = 0; y < img->get_height(); y++) {
				for (int x = 0; x < img->get_width(); x++) {
					if (rect.abs().has_point(Point2(x, y))) {
						CHECK_MESSAGE(
								img->get_pixel(x, y).is_equal_approx(Color(1, 1, 1, 1)),
								"fill_rect() should colorize all image pixels within rect bounds.");
					} else {
						CHECK_MESSAGE(
								!img->get_pixel(x, y).is_equal_approx(Color(1, 1, 1, 1)),
								"fill_rect() shouldn't colorize any image pixel out of rect bounds.");
					}
				}
			}
		}
	}

	// Blend two images together
	image->blend_rect(image2, Rect2i(Vector2i(0, 0), image2->get_size()), Vector2i(0, 0));
	CHECK_MESSAGE(
			image->get_pixel(0, 0).a > 0.7,
			"blend_rect() should blend the alpha values of the two images.");
	CHECK_MESSAGE(
			image->get_used_rect().size == image->get_size(),
			"get_used_rect() should return the expected value, its Rect size should be the same as get_size() if there are no transparent pixels.");

	Ref<Image> image3 = memnew(Image(2, 2, false, Image::FORMAT_RGBA8));
	image3->set_pixel(0, 0, Color(0, 1, 0, 1));

	//blit_rect() two images together
	image->blit_rect(image3, Rect2i(Vector2i(0, 0), image3->get_size()), Vector2i(0, 0));
	CHECK_MESSAGE(
			image->get_pixel(0, 0).is_equal_approx(Color(0, 1, 0, 1)),
			"blit_rect() should replace old colors and not blend them.");
	CHECK_MESSAGE(
			!image->get_pixel(2, 2).is_equal_approx(Color(0, 1, 0, 1)),
			"blit_rect() should not affect the area of the image that is outside src_rect.");

	// Flip image
	image3->flip_x();
	CHECK(image3->get_pixel(1, 0).is_equal_approx(Color(0, 1, 0, 1)));
	CHECK_MESSAGE(
			image3->get_pixel(0, 0).is_equal_approx(Color(0, 0, 0, 0)),
			"flip_x() should not leave old pixels behind.");
	image3->flip_y();
	CHECK(image3->get_pixel(1, 1).is_equal_approx(Color(0, 1, 0, 1)));
	CHECK_MESSAGE(
			image3->get_pixel(1, 0).is_equal_approx(Color(0, 0, 0, 0)),
			"flip_y() should not leave old pixels behind.");

	// Pre-multiply Alpha then Convert from RGBA to L8, checking alpha
	{
		Ref<Image> gray_image = memnew(Image(3, 3, false, Image::FORMAT_RGBA8));
		gray_image->fill_rect(Rect2i(0, 0, 3, 3), Color(1, 1, 1, 0));
		gray_image->set_pixel(1, 1, Color(1, 1, 1, 1));
		gray_image->set_pixel(1, 2, Color(0.5, 0.5, 0.5, 0.5));
		gray_image->set_pixel(2, 1, Color(0.25, 0.05, 0.5, 1.0));
		gray_image->set_pixel(2, 2, Color(0.5, 0.25, 0.95, 0.75));
		gray_image->premultiply_alpha();
		gray_image->convert(Image::FORMAT_L8);
		CHECK_MESSAGE(gray_image->get_pixel(0, 0).is_equal_approx(Color(0, 0, 0, 1)), "convert() RGBA to L8 should be black.");
		CHECK_MESSAGE(gray_image->get_pixel(0, 1).is_equal_approx(Color(0, 0, 0, 1)), "convert() RGBA to L8 should be black.");
		CHECK_MESSAGE(gray_image->get_pixel(0, 2).is_equal_approx(Color(0, 0, 0, 1)), "convert() RGBA to L8 should be black.");
		CHECK_MESSAGE(gray_image->get_pixel(1, 0).is_equal_approx(Color(0, 0, 0, 1)), "convert() RGBA to L8 should be black.");
		CHECK_MESSAGE(gray_image->get_pixel(1, 1).is_equal_approx(Color(1, 1, 1, 1)), "convert() RGBA to L8 should be white.");
		CHECK_MESSAGE(gray_image->get_pixel(1, 2).is_equal_approx(Color(0.250980407, 0.250980407, 0.250980407, 1)), "convert() RGBA to L8 should be around 0.250980407 (64).");
		CHECK_MESSAGE(gray_image->get_pixel(2, 0).is_equal_approx(Color(0, 0, 0, 1)), "convert() RGBA to L8 should be black.");
		CHECK_MESSAGE(gray_image->get_pixel(2, 1).is_equal_approx(Color(0.125490203, 0.125490203, 0.125490203, 1)), "convert() RGBA to L8 should be around 0.125490203 (32).");
		CHECK_MESSAGE(gray_image->get_pixel(2, 2).is_equal_approx(Color(0.266666681, 0.266666681, 0.266666681, 1)), "convert() RGBA to L8 should be around 0.266666681 (68).");
	}
}

TEST_CASE("[Image] Color rounding") {
	Ref<Image> image = memnew(Image(1, 1, false, Image::FORMAT_R8));
	for (int i = 0; i < 1024; i++) {
		float expected_value = i / 1023.0f;
		image->set_pixel(0, 0, Color(expected_value, 0.0f, 0.0f));

		uint8_t expected_value_int = CLAMP(Math::round(expected_value * 255.0f), 0, 255);
		CHECK_MESSAGE(image->get_data()[0] == expected_value_int, vformat("Pixel's r channel should be around %d", expected_value_int));
	}
}

TEST_CASE("[Image] Custom mipmaps") {
	Ref<Image> image = memnew(Image(100, 100, false, Image::FORMAT_RGBA8));

	REQUIRE(!image->has_mipmaps());
	image->generate_mipmaps();
	REQUIRE(image->has_mipmaps());

	const int mipmaps = image->get_mipmap_count() + 1;
	REQUIRE(mipmaps == 7);

	// Initialize reference mipmap data.
	// Each byte is given value "mipmap_index * 5".

	{
		PackedByteArray data = image->get_data();
		uint8_t *data_ptr = data.ptrw();

		for (int mip = 0; mip < mipmaps; mip++) {
			int64_t mip_offset = 0;
			int64_t mip_size = 0;
			image->get_mipmap_offset_and_size(mip, mip_offset, mip_size);

			for (int i = 0; i < mip_size; i++) {
				data_ptr[mip_offset + i] = mip * 5;
			}
		}
		image->set_data(image->get_width(), image->get_height(), image->has_mipmaps(), image->get_format(), data);
	}

	// Byte format conversion.

	for (int format = Image::FORMAT_L8; format <= Image::FORMAT_RGBA8; format++) {
		Ref<Image> image_bytes = memnew(Image());
		image_bytes->copy_internals_from(image);
		image_bytes->convert((Image::Format)format);
		REQUIRE(image_bytes->has_mipmaps());

		PackedByteArray data = image_bytes->get_data();
		const uint8_t *data_ptr = data.ptr();

		for (int mip = 0; mip < mipmaps; mip++) {
			int64_t mip_offset = 0;
			int64_t mip_size = 0;
			image_bytes->get_mipmap_offset_and_size(mip, mip_offset, mip_size);

			for (int i = 0; i < mip_size; i++) {
				if (data_ptr[mip_offset + i] != mip * 5) {
					REQUIRE_MESSAGE(false, "Byte format conversion error.");
				}
			}
		}
	}

	// Floating point format conversion.

	for (int format = Image::FORMAT_RF; format <= Image::FORMAT_RGBAF; format++) {
		Ref<Image> image_rgbaf = memnew(Image());
		image_rgbaf->copy_internals_from(image);
		image_rgbaf->convert((Image::Format)format);
		REQUIRE(image_rgbaf->has_mipmaps());

		PackedByteArray data = image_rgbaf->get_data();
		const uint8_t *data_ptr = data.ptr();

		for (int mip = 0; mip < mipmaps; mip++) {
			int64_t mip_offset = 0;
			int64_t mip_size = 0;
			image_rgbaf->get_mipmap_offset_and_size(mip, mip_offset, mip_size);

			for (int i = 0; i < mip_size; i += 4) {
				float value = *(float *)(data_ptr + mip_offset + i);
				if (!Math::is_equal_approx(value * 255.0f, mip * 5)) {
					REQUIRE_MESSAGE(false, "Floating point conversion error.");
				}
			}
		}
	}
}

TEST_CASE("[Image] Linear and sRGB conversion of half-float formats") {
	const Color linear = Color(0.5, 0.5, 0.5);
	const Color srgb = linear.linear_to_srgb();

	auto all_pixels_are = [](const Ref<Image> &p_image, const Color &p_color) {
		for (int mip = 0; mip <= p_image->get_mipmap_count(); mip++) {
			Ref<Image> level = p_image->get_image_from_mipmap(mip);
			for (int y = 0; y < level->get_height(); y++) {
				for (int x = 0; x < level->get_width(); x++) {
					const Color pixel = level->get_pixel(x, y);
					if (!Math::is_equal_approx(pixel.r, p_color.r, 0.001f) || !Math::is_equal_approx(pixel.g, p_color.g, 0.001f) || !Math::is_equal_approx(pixel.b, p_color.b, 0.001f)) {
						return false;
					}
				}
			}
		}
		return true;
	};

	for (Image::Format format : { Image::FORMAT_RGBH, Image::FORMAT_RGBAH }) {
		Ref<Image> image = memnew(Image(8, 8, true, format));
		image->fill(linear);

		image->linear_to_srgb();
		CHECK_MESSAGE(all_pixels_are(image, srgb), "linear_to_srgb() should convert every pixel of every mipmap.");

		image->srgb_to_linear();
		CHECK_MESSAGE(all_pixels_are(image, linear), "srgb_to_linear() should convert every pixel of every mipmap.");

		// Holding the data makes the conversion copy it on write.
		Ref<Image> shared = memnew(Image(512, 512, false, format));
		shared->fill(linear);
		const Vector<uint8_t> held_linear = shared->get_data();
		shared->linear_to_srgb();
		CHECK_MESSAGE(all_pixels_are(shared, srgb), "linear_to_srgb() should convert every pixel when the data is shared.");
		CHECK_MESSAGE(all_pixels_are(Image::create_from_data(512, 512, false, format, held_linear), linear), "linear_to_srgb() should not change other copies of the data.");

		const Vector<uint8_t> held_srgb = shared->get_data();
		shared->srgb_to_linear();
		CHECK_MESSAGE(all_pixels_are(shared, linear), "srgb_to_linear() should convert every pixel when the data is shared.");
		CHECK_MESSAGE(all_pixels_are(Image::create_from_data(512, 512, false, format, held_srgb), srgb), "srgb_to_linear() should not change other copies of the data.");
	}
}

TEST_CASE("[Image] Convert image") {
	for (int format = Image::FORMAT_RF; format < Image::FORMAT_RGBE9995; format++) {
		for (int new_format = Image::FORMAT_RF; new_format < Image::FORMAT_RGBE9995; new_format++) {
			Ref<Image> image = memnew(Image(4, 4, false, (Image::Format)format));
			image->convert((Image::Format)new_format);
			String format_string = Image::format_names[(Image::Format)format];
			String new_format_string = Image::format_names[(Image::Format)new_format];
			format_string = "Error converting from " + format_string + " to " + new_format_string + ".";
			CHECK_MESSAGE(image->get_format() == new_format, format_string);
		}
	}

	Ref<Image> image = memnew(Image(4, 4, false, Image::FORMAT_RGBA8));
	PackedByteArray image_data = image->get_data();
	ERR_PRINT_OFF;
	image->convert((Image::Format)-1);
	ERR_PRINT_ON;
	CHECK_MESSAGE(image->get_data() == image_data, "Image conversion to invalid type (-1) should not alter image.");
	Ref<Image> image2 = memnew(Image(4, 4, false, Image::FORMAT_RGBA8));
	image_data = image2->get_data();
	ERR_PRINT_OFF;
	image2->convert((Image::Format)(Image::FORMAT_MAX + 1));
	ERR_PRINT_ON;
	CHECK_MESSAGE(image2->get_data() == image_data, "Image conversion to invalid type (Image::FORMAT_MAX + 1) should not alter image.");
}

TEST_CASE("[Image] Queued upload snapshot keeps pixels when caller changes the image") {
	const Color red(1.0, 0.0, 0.0, 1.0);
	const Color green(0.0, 1.0, 0.0, 1.0);
	const Color blue(0.0, 0.0, 1.0, 1.0);
	for (Image::Format format : { Image::FORMAT_RGB8, Image::FORMAT_RGBA8 }) {
		Ref<Image> original = memnew(Image(3, 2, false, format));
		original->fill(red);
		Ref<Image> snapshot = original->duplicate();
		REQUIRE(snapshot.is_valid());
		CHECK(snapshot.ptr() != original.ptr());
		CHECK(snapshot->get_data() == original->get_data());

		original->fill(green);
		CHECK(snapshot->get_pixel(0, 0) == red);
		CHECK(snapshot->get_pixel(2, 1) == red);
		CHECK(original->get_pixel(0, 0) == green);

		snapshot->set_pixel(2, 1, blue);
		CHECK(snapshot->get_pixel(2, 1) == blue);
		CHECK(original->get_pixel(2, 1) == green);
	}
}

TEST_CASE("[Image] Multiple queued upload snapshots keep independent generations") {
	Ref<Image> original = memnew(Image(2, 2, false, Image::FORMAT_RGBA8));
	const Color red(1.0, 0.0, 0.0, 1.0);
	const Color green(0.0, 1.0, 0.0, 1.0);
	const Color blue(0.0, 0.0, 1.0, 1.0);
	original->fill(red);
	Ref<Image> first = original->duplicate();
	original->fill(green);
	Ref<Image> second = original->duplicate();
	original->fill(blue);
	REQUIRE(first.is_valid());
	REQUIRE(second.is_valid());
	CHECK(first->get_pixel(0, 0) == red);
	CHECK(first->get_pixel(1, 1) == red);
	CHECK(second->get_pixel(0, 0) == green);
	CHECK(second->get_pixel(1, 1) == green);
	CHECK(original->get_pixel(0, 0) == blue);
}


TEST_CASE("[Image][NormalMipmap] RGB8 keeps a flat normal and alpha") {
	Ref<Image> image = memnew(Image(4, 4, false, Image::FORMAT_RGBA8));
	const Color base_normal(0.5, 0.5, 1.0, 0.75);
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			image->set_pixel(x, y, base_normal);
		}
	}
	CHECK(image->generate_mipmaps(true) == OK);
	CHECK(image->get_mipmap_count() == 2);
	const Ref<Image> mip = image->get_image_from_mipmap(1);
	REQUIRE(mip.is_valid());
	for (int y = 0; y < mip->get_height(); y++) {
		for (int x = 0; x < mip->get_width(); x++) {
			const Color normal = mip->get_pixel(x, y);
			CHECK(Math::abs(normal.r - 0.5f) <= 2.0f / 255.0f);
			CHECK(Math::abs(normal.g - 0.5f) <= 2.0f / 255.0f);
			CHECK(Math::abs(normal.b - 1.0f) <= 1.0f / 255.0f);
			CHECK(Math::abs(normal.a - base_normal.a) <= 2.0f / 255.0f);
		}
	}
}

TEST_CASE("[Image][NormalMipmap] RGB16 keeps a flat normal and alpha") {
	Ref<Image> image = memnew(Image(4, 4, false, Image::FORMAT_RGBA16));
	const Color base_normal(0.5, 0.5, 1.0, 0.625);
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			image->set_pixel(x, y, base_normal);
		}
	}
	CHECK(image->generate_mipmaps(true) == OK);
	const Ref<Image> mip = image->get_image_from_mipmap(1);
	REQUIRE(mip.is_valid());
	const Color normal = mip->get_pixel(0, 0);
	CHECK(Math::abs(normal.r - 0.5f) < 3.0f / 65535.0f);
	CHECK(Math::abs(normal.g - 0.5f) < 3.0f / 65535.0f);
	CHECK(Math::abs(normal.b - 1.0f) < 2.0f / 65535.0f);
	CHECK(Math::abs(normal.a - base_normal.a) < 3.0f / 65535.0f);
}

TEST_CASE("[Image][NormalMipmap] Nonaxis normal stays unit length in RGB8 and RGB16") {
	for (Image::Format format : { Image::FORMAT_RGBA8, Image::FORMAT_RGBA16 }) {
		Ref<Image> image = memnew(Image(4, 4, false, format));
		const Color sample(0.7, 0.35, 0.92, 1.0);
		for (int y = 0; y < 4; y++) {
			for (int x = 0; x < 4; x++) {
				image->set_pixel(x, y, sample);
			}
		}
		CHECK(image->generate_mipmaps(true) == OK);
		const Ref<Image> mip = image->get_image_from_mipmap(1);
		REQUIRE(mip.is_valid());
		const Color color = mip->get_pixel(0, 0);
		const Vector3 decoded(color.r * 2.0f - 1.0f, color.g * 2.0f - 1.0f, color.b * 2.0f - 1.0f);
		CHECK(Math::abs(decoded.length() - 1.0f) < (format == Image::FORMAT_RGBA8 ? 0.02f : 0.0002f));
		CHECK(Math::abs(color.a - 1.0f) < 0.001f);
	}
}

TEST_CASE("[Image][NormalMipmap] Mipmap renormalization is deterministic for repeated sources") {
	for (Image::Format format : { Image::FORMAT_RGBA8, Image::FORMAT_RGBA16 }) {
		Ref<Image> first = memnew(Image(4, 4, false, format));
		Ref<Image> second = memnew(Image(4, 4, false, format));
		for (int y = 0; y < 4; y++) {
			for (int x = 0; x < 4; x++) {
				const Color sample(0.4f + 0.1f * (x % 2), 0.3f + 0.1f * (y % 2), 0.9f, 0.8f);
				first->set_pixel(x, y, sample);
				second->set_pixel(x, y, sample);
			}
		}
		CHECK(first->generate_mipmaps(true) == OK);
		CHECK(second->generate_mipmaps(true) == OK);
		CHECK(first->get_data() == second->get_data());
	}
}


TEST_CASE("[Image] optimize_from_channels reduces uncompressed grayscale storage") {
	Ref<Image> image = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	image->fill(Color(0.5, 0.5, 0.5, 1.0));
	CHECK_EQ(image->get_data_size(), 8 * 8 * 4);
	image->optimize_from_channels(Image::USED_CHANNELS_L);
	CHECK_EQ(image->get_format(), Image::FORMAT_L8);
	CHECK_EQ(image->get_data_size(), 8 * 8);
	const Color result = image->get_pixel(0, 0);
	CHECK(Math::abs(result.r - 0.5) < 0.01);
	CHECK(Math::abs(result.g - 0.5) < 0.01);
	CHECK(Math::abs(result.b - 0.5) < 0.01);
}

TEST_CASE("[Image] optimize_from_channels keeps grayscale alpha") {
	Ref<Image> image = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	image->fill(Color(0.5, 0.5, 0.5, 0.25));
	image->optimize_from_channels(Image::USED_CHANNELS_LA);
	CHECK_EQ(image->get_format(), Image::FORMAT_LA8);
	CHECK_EQ(image->get_data_size(), 8 * 8 * 2);
	const Color result = image->get_pixel(0, 0);
	CHECK(Math::abs(result.r - 0.5) < 0.01);
	CHECK(Math::abs(result.a - 0.25) < 0.01);
}

TEST_CASE("[Image] optimize_from_channels removes unused RGB8 and RG8 channels") {
	Ref<Image> image = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	image->fill(Color(0.2, 0.4, 0.6, 1.0));
	image->optimize_from_channels(Image::USED_CHANNELS_RGB);
	CHECK_EQ(image->get_format(), Image::FORMAT_RGB8);
	CHECK_EQ(image->get_data_size(), 8 * 8 * 3);
	CHECK(Math::abs(image->get_pixel(0, 0).r - 0.2) < 0.01);

	Ref<Image> normal = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	normal->fill(Color(0.3, 0.7, 0.0, 1.0));
	normal->optimize_from_channels(Image::USED_CHANNELS_RG);
	CHECK_EQ(normal->get_format(), Image::FORMAT_RG8);
	CHECK_EQ(normal->get_data_size(), 8 * 8 * 2);
	CHECK(Math::abs(normal->get_pixel(0, 0).g - 0.7) < 0.01);
}

TEST_CASE("[Image] optimize_from_channels preserves HDR precision") {
	Ref<Image> hdr = memnew(Image(4, 4, false, Image::FORMAT_RGBAF));
	hdr->fill(Color(2.0, 2.0, 2.0, 1.0));
	hdr->optimize_from_channels(Image::USED_CHANNELS_L);
	CHECK_EQ(hdr->get_format(), Image::FORMAT_RGBF);
	CHECK(Math::abs(hdr->get_pixel(0, 0).r - 2.0) < 0.001);
	CHECK_EQ(hdr->get_data_size(), 4 * 4 * 3 * 4);

	Ref<Image> half = memnew(Image(4, 4, false, Image::FORMAT_RGBAH));
	half->fill(Color(1.5, 1.5, 1.5, 1.0));
	half->optimize_from_channels(Image::USED_CHANNELS_L);
	CHECK_EQ(half->get_format(), Image::FORMAT_RGBH);
	CHECK(Math::abs(half->get_pixel(0, 0).g - 1.5) < 0.01);
}


TEST_CASE("[Image][MaskedBlit] RGBA8 runs match scalar RGBAF reference") {
	const Image::Format formats[] = { Image::FORMAT_RGB8, Image::FORMAT_RGBA8, Image::FORMAT_RGBAF };
	constexpr int SW = 79;
	constexpr int SH = 31;
	for (const Image::Format format : formats) {
		Ref<Image> source = memnew(Image(SW, SH, false, format));
		Ref<Image> mask8 = memnew(Image(SW, SH, false, Image::FORMAT_RGBA8));
		Ref<Image> maskf = memnew(Image(SW, SH, false, Image::FORMAT_RGBAF));
		Ref<Image> optimized = memnew(Image(92, 39, false, format));
		Ref<Image> reference = memnew(Image(92, 39, false, format));
		optimized->fill(Color(0.2f, 0.3f, 0.4f, 0.5f));
		reference->fill(Color(0.2f, 0.3f, 0.4f, 0.5f));

		for (int y = 0; y < SH; y++) {
			for (int x = 0; x < SW; x++) {
				source->set_pixel(x, y, Color(float(x % 37) / 36.0f, float(y % 19) / 18.0f, float((x * 7 + y) % 29) / 28.0f, float(x % 5) / 4.0f));
				const int pattern = (x / 9 + y / 3) % 5;
				const float alpha = pattern == 0 ? 0.0f : pattern == 1 ? (1.0f / 255.0f) : pattern == 2 ? 0.5f : 1.0f;
				mask8->set_pixel(x, y, Color(0, 0, 0, alpha));
				maskf->set_pixel(x, y, Color(0, 0, 0, alpha));
			}
		}
		optimized->blit_rect_mask(source, mask8, Rect2i(3, 2, 71, 27), Point2i(7, 6));
		reference->blit_rect_mask(source, maskf, Rect2i(3, 2, 71, 27), Point2i(7, 6));
		CHECK_MESSAGE(optimized->get_data() == reference->get_data(),
				"RGBA8 opaque runs must match the existing scalar blit byte-for-byte, for every destination pixel format.");
	}
}

TEST_CASE("[Image][MaskedBlit] Cropped spans match scalar clipping") {
	Ref<Image> source = memnew(Image(47, 25, false, Image::FORMAT_RGBA8));
	Ref<Image> mask8 = memnew(Image(47, 25, false, Image::FORMAT_RGBA8));
	Ref<Image> maskf = memnew(Image(47, 25, false, Image::FORMAT_RGBAF));
	for (int y = 0; y < 25; y++) {
		for (int x = 0; x < 47; x++) {
			source->set_pixel(x, y, Color(float(x) / 46, float(y) / 24, 0.75f, 1));
			const float alpha = (x / 4 + y / 2) % 3 == 0 ? 0.0f : 1.0f;
			mask8->set_pixel(x, y, Color(0, 0, 0, alpha));
			maskf->set_pixel(x, y, Color(0, 0, 0, alpha));
		}
	}
	const Rect2i source_rects[] = {
		Rect2i(-6, -4, 40, 25),
		Rect2i(30, 12, 40, 30),
		Rect2i(0, 0, 47, 25),
		Rect2i(8, 3, 30, 16),
	};
	const Point2i dest_positions[] = {
		Point2i(10, 5),
		Point2i(20, 10),
		Point2i(-8, -6),
		Point2i(0, 0),
	};
	for (int i = 0; i < 4; i++) {
		Ref<Image> optimized = memnew(Image(32, 20, false, Image::FORMAT_RGBA8));
		Ref<Image> reference = memnew(Image(32, 20, false, Image::FORMAT_RGBA8));
		optimized->fill(Color(0.9f, 0.5f, 0.2f, 0.8f));
		reference->fill(Color(0.9f, 0.5f, 0.2f, 0.8f));
		optimized->blit_rect_mask(source, mask8, source_rects[i], dest_positions[i]);
		reference->blit_rect_mask(source, maskf, source_rects[i], dest_positions[i]);
		CHECK_MESSAGE(optimized->get_data() == reference->get_data(), "Clipping may not alter RGBA8 mask blit results.");
	}
}

TEST_CASE("[Image][MaskedBlit] Self alias keeps scalar semantics") {
	Ref<Image> actual = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> reference = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> mask = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	for (int y = 0; y < 8; y++) {
		for (int x = 0; x < 8; x++) {
			const Color color(float(x) / 7, float(y) / 7, 0.25f, 1.0f);
			actual->set_pixel(x, y, color);
			reference->set_pixel(x, y, color);
			mask->set_pixel(x, y, Color(0, 0, 0, (x + y) % 3 ? 1.0f : 0.0f));
		}
	}
	for (int y = 0; y < 7; y++) {
		for (int x = 0; x < 7; x++) {
			if (mask->get_pixel(x, y).a != 0) {
				reference->set_pixel(x + 1, y + 1, reference->get_pixel(x, y));
			}
		}
	}
	actual->blit_rect_mask(actual, mask, Rect2i(0, 0, 7, 7), Point2i(1, 1));
	CHECK_MESSAGE(actual->get_data() == reference->get_data(), "Self-blits preserve the existing scalar copy order.");
}

TEST_CASE("[Image][MaskedBlit] Destination mask alias keeps scalar semantics") {
	Ref<Image> source = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> actual = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> reference = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	for (int y = 0; y < 8; y++) {
		for (int x = 0; x < 8; x++) {
			source->set_pixel(x, y, Color(float(x + 1) / 9, float(y + 1) / 9, 0.3f, (x * 2 + y) % 5 ? 1.0f : 0.0f));
			const Color color(0.1f, 0.2f, 0.3f, (x + y) % 4 ? 1.0f : 0.0f);
			actual->set_pixel(x, y, color);
			reference->set_pixel(x, y, color);
		}
	}
	for (int y = 0; y < 7; y++) {
		for (int x = 0; x < 7; x++) {
			if (reference->get_pixel(x, y).a != 0) {
				reference->set_pixel(x + 1, y + 1, source->get_pixel(x, y));
			}
		}
	}
	actual->blit_rect_mask(source, actual, Rect2i(0, 0, 7, 7), Point2i(1, 1));
	CHECK_MESSAGE(actual->get_data() == reference->get_data(), "Destination-mask aliasing must retain scalar semantics.");
}


TEST_CASE("[Image][BlendHotpath] Unmasked blend matches per-pixel reference for several formats") {
	const Image::Format formats[] = { Image::FORMAT_RGBA8, Image::FORMAT_RGB8, Image::FORMAT_LA8, Image::FORMAT_RGBAF };
	for (Image::Format format : formats) {
		Ref<Image> source = memnew(Image(32, 21, false, format));
		Ref<Image> actual = memnew(Image(39, 26, false, format));
		Ref<Image> expected = memnew(Image(39, 26, false, format));
		actual->fill(Color(0.15f, 0.25f, 0.35f, 0.55f));
		expected->fill(Color(0.15f, 0.25f, 0.35f, 0.55f));
		for (int y = 0; y < 21; y++) {
			for (int x = 0; x < 32; x++) {
				source->set_pixel(x, y, Color((x % 13) / 12.0f, (y % 11) / 10.0f, ((x + y) % 17) / 16.0f, (x + y) % 5 == 0 ? 0.0f : (x % 7) / 6.0f));
			}
		}
		// Source [4, 3, 29, 18) maps to destination [6, 5, 31, 20).
		for (int y = 0; y < 15; y++) {
			for (int x = 0; x < 25; x++) {
				const Color sc = source->get_pixel(x + 4, y + 3);
				if (sc.a != 0) {
					expected->set_pixel(x + 6, y + 5, expected->get_pixel(x + 6, y + 5).blend(sc));
				}
			}
		}
		actual->blend_rect(source, Rect2i(4, 3, 25, 15), Point2i(6, 5));
		CHECK_MESSAGE(actual->get_data() == expected->get_data(), "Blend fast path must match the scalar Color.blend reference for every format.");
	}
}

TEST_CASE("[Image][BlendHotpath] RGBA8 mask direct-alpha blend matches scalar reference") {
	const Image::Format formats[] = { Image::FORMAT_RGBA8, Image::FORMAT_RGB8, Image::FORMAT_LA8, Image::FORMAT_RGBAF };
	for (Image::Format format : formats) {
		Ref<Image> source = memnew(Image(34, 23, false, format));
		Ref<Image> mask = memnew(Image(34, 23, false, Image::FORMAT_RGBA8));
		Ref<Image> actual = memnew(Image(37, 26, false, format));
		Ref<Image> expected = memnew(Image(37, 26, false, format));
		actual->fill(Color(0.4f, 0.2f, 0.3f, 0.7f));
		expected->fill(Color(0.4f, 0.2f, 0.3f, 0.7f));
		for (int y = 0; y < 23; y++) {
			for (int x = 0; x < 34; x++) {
				source->set_pixel(x, y, Color((x % 23) / 22.0f, (y % 17) / 16.0f, 0.33f, (x + y) % 5 ? 0.75f : 0.0f));
				const float alpha = (x / 5 + y / 4) % 3 == 0 ? 0.0f : ((x + y) % 7 == 0 ? 0.5f : 1.0f);
				mask->set_pixel(x, y, Color(0.2f, 0.3f, 0.4f, alpha));
			}
		}
		for (int y = 0; y < 19; y++) {
			for (int x = 0; x < 28; x++) {
				if (mask->get_pixel(x + 3, y + 2).a != 0) {
					const Color sc = source->get_pixel(x + 3, y + 2);
					if (sc.a != 0) {
						expected->set_pixel(x + 6, y + 4, expected->get_pixel(x + 6, y + 4).blend(sc));
					}
				}
			}
		}
		actual->blend_rect_mask(source, mask, Rect2i(3, 2, 28, 19), Point2i(6, 4));
		CHECK_MESSAGE(actual->get_data() == expected->get_data(), "RGBA8 masks must match per-pixel composition exactly.");
	}
}

TEST_CASE("[Image][BlendHotpath] Masked blend clipping and no-op regions preserve destination") {
	Ref<Image> source = memnew(Image(17, 15, false, Image::FORMAT_RGBA8));
	Ref<Image> mask = memnew(Image(17, 15, false, Image::FORMAT_RGBA8));
	source->fill(Color(0.1f, 0.9f, 0.2f, 0.5f));
	for (int y = 0; y < 15; y++) {
		for (int x = 0; x < 17; x++) {
			mask->set_pixel(x, y, Color(0, 0, 0, (x + y) % 4 ? 1.0f : 0.0f));
		}
	}
	Ref<Image> actual = memnew(Image(12, 11, false, Image::FORMAT_RGBA8));
	Ref<Image> expected = memnew(Image(12, 11, false, Image::FORMAT_RGBA8));
	actual->fill(Color(0.2f, 0.3f, 0.4f, 1.0f));
	expected->fill(Color(0.2f, 0.3f, 0.4f, 1.0f));
	// Negative source and destination clipping: source (0, 0) -> destination (3, 2).
	for (int y = 0; y < 9; y++) {
		for (int x = 0; x < 9; x++) {
			if (mask->get_pixel(x, y).a != 0) {
				const Color sc = source->get_pixel(x, y);
				expected->set_pixel(x + 3, y + 2, expected->get_pixel(x + 3, y + 2).blend(sc));
			}
		}
	}
	actual->blend_rect_mask(source, mask, Rect2i(-5, -3, 18, 15), Point2i(-2, -1));
	CHECK_MESSAGE(actual->get_data() == expected->get_data(), "Clipped blending must preserve pixel positions and exact output.");
	const PackedByteArray before = actual->get_data();
	actual->blend_rect_mask(source, mask, Rect2i(100, 100, 4, 4), Point2i(0, 0));
	CHECK(actual->get_data() == before);
}

TEST_CASE("[Image][BlendHotpath] Copy-on-write source sharing survives blend") {
	Ref<Image> source = memnew(Image(19, 13, false, Image::FORMAT_RGBA8));
	source->fill(Color(0.9f, 0.5f, 0.4f, 0.75f));
	Ref<Image> actual = memnew(Image(19, 13, false, Image::FORMAT_RGBA8));
	actual->fill(Color(0.1f, 0.2f, 0.3f, 0.5f));
	Ref<Image> expected = memnew(Image(19, 13, false, Image::FORMAT_RGBA8));
	expected->copy_internals_from(actual);
	const PackedByteArray held_source = source->get_data();
	const PackedByteArray held_destination = actual->get_data();
	for (int y = 0; y < 13; y++) {
		for (int x = 0; x < 19; x++) {
			const Color sc = source->get_pixel(x, y);
			expected->set_pixel(x, y, expected->get_pixel(x, y).blend(sc));
		}
	}
	actual->blend_rect(source, Rect2i(0, 0, 19, 13), Point2i(0, 0));
	CHECK(actual->get_data() == expected->get_data());
	CHECK(source->get_data() == held_source);
	CHECK(actual->get_data() != held_destination);
}

TEST_CASE("[Image][BlendHotpath] Self-blend and destination-mask alias use scalar fallback") {
	Ref<Image> source = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> mask = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> actual = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> expected = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	for (int y = 0; y < 8; y++) {
		for (int x = 0; x < 8; x++) {
			const Color color(x / 7.0f, y / 7.0f, 0.4f, (x + y) % 4 ? 0.8f : 0.0f);
			source->set_pixel(x, y, color);
			mask->set_pixel(x, y, Color(0, 0, 0, (x + 2 * y) % 3 ? 1.0f : 0.0f));
			actual->set_pixel(x, y, color);
			expected->set_pixel(x, y, color);
		}
	}
	for (int y = 0; y < 7; y++) {
		for (int x = 0; x < 7; x++) {
			const Color sc = expected->get_pixel(x, y);
			if (sc.a != 0) {
				expected->set_pixel(x + 1, y + 1, expected->get_pixel(x + 1, y + 1).blend(sc));
			}
		}
	}
	actual->blend_rect(actual, Rect2i(0, 0, 7, 7), Point2i(1, 1));
	CHECK_MESSAGE(actual->get_data() == expected->get_data(), "Self-blend must preserve sequential read/write semantics.");

	Ref<Image> masked = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	Ref<Image> reference = memnew(Image(8, 8, false, Image::FORMAT_RGBA8));
	masked->copy_internals_from(mask);
	reference->copy_internals_from(mask);
	for (int y = 0; y < 7; y++) {
		for (int x = 0; x < 7; x++) {
			if (reference->get_pixel(x, y).a != 0) {
				const Color sc = source->get_pixel(x, y);
				if (sc.a != 0) {
					reference->set_pixel(x + 1, y + 1, reference->get_pixel(x + 1, y + 1).blend(sc));
				}
			}
		}
	}
	masked->blend_rect_mask(source, masked, Rect2i(0, 0, 7, 7), Point2i(1, 1));
	CHECK_MESSAGE(masked->get_data() == reference->get_data(), "Destination-mask alias must preserve the original scalar behavior.");
}

} // namespace TestImage
