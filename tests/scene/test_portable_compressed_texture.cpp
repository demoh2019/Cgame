/**************************************************************************/
/*  test_portable_compressed_texture.cpp                                  */
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

TEST_FORCE_LINK(test_portable_compressed_texture)

#include "core/io/marshalls.h"
#include "scene/resources/portable_compressed_texture.h"

namespace TestPortableCompressedTexture {

static Vector<uint8_t> make_basis_texture_data() {
	Vector<uint8_t> data;
	data.resize(21);
	data.fill(0);
	encode_uint16(PortableCompressedTexture2D::COMPRESSION_MODE_BASIS_UNIVERSAL, data.ptrw());
	encode_uint16(PortableCompressedTexture2D::DATA_FORMAT_BASIS_UNIVERSAL, data.ptrw() + 2);
	encode_uint32(Image::FORMAT_RGBA8, data.ptrw() + 4);
	encode_uint32(1, data.ptrw() + 8);
	encode_uint32(1, data.ptrw() + 12);
	encode_uint32(1, data.ptrw() + 16);
	return data;
}

static Ref<Image> empty_basis_decoder(const uint8_t *, int) {
	return Ref<Image>();
}

TEST_CASE("[PortableCompressedTexture2D] Reject missing Basis Universal decoder") {
	Ref<PortableCompressedTexture2D> texture;
	texture.instantiate();

	const auto previous_decoder = Image::basis_universal_unpacker_ptr;
	Image::basis_universal_unpacker_ptr = nullptr;

	ERR_PRINT_OFF;
	texture->set(SNAME("_data"), make_basis_texture_data());
	ERR_PRINT_ON;

	Image::basis_universal_unpacker_ptr = previous_decoder;

	CHECK(texture->get_image().is_null());
}

TEST_CASE("[PortableCompressedTexture2D] Reject null decoded Basis image") {
	Ref<PortableCompressedTexture2D> texture;
	texture.instantiate();

	const auto previous_decoder = Image::basis_universal_unpacker_ptr;
	Image::basis_universal_unpacker_ptr = empty_basis_decoder;

	ERR_PRINT_OFF;
	texture->set(SNAME("_data"), make_basis_texture_data());
	ERR_PRINT_ON;

	Image::basis_universal_unpacker_ptr = previous_decoder;

	CHECK(texture->get_image().is_null());
}

#ifdef TOOLS_ENABLED
TEST_CASE("[PortableCompressedTexture2D] Reject compression without Basis Universal support") {
	Ref<PortableCompressedTexture2D> texture;
	texture.instantiate();

	Ref<Image> source;
	source.instantiate(4, 4, false, Image::FORMAT_RGBA8);
	source->fill(Color(1, 0, 0));

	const auto previous_decoder = Image::basis_universal_unpacker;
	Image::basis_universal_unpacker = nullptr;

	ERR_PRINT_OFF;
	texture->create_from_image(source, PortableCompressedTexture2D::COMPRESSION_MODE_BASIS_UNIVERSAL);
	ERR_PRINT_ON;

	Image::basis_universal_unpacker = previous_decoder;

	CHECK(texture->get_image().is_null());
}
#endif // TOOLS_ENABLED

} // namespace TestPortableCompressedTexture
