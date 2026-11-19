/**************************************************************************/
/*  file_access_packed_byte_array.cpp                                     */
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

#include "file_access_packed_byte_array.h"

Error FileAccessPackedByteArray::open_custom(const PackedByteArray &p_data) {
	data = p_data;
	pos = 0;
	return OK;
}

void FileAccessPackedByteArray::seek(uint64_t p_position) {
	ERR_FAIL_COND(p_position > (uint64_t)data.size());
	pos = p_position;
}

void FileAccessPackedByteArray::seek_end(int64_t p_position) {
	ERR_FAIL_COND((int64_t)data.size() + p_position < 0);
	seek(data.size() + p_position);
}

uint64_t FileAccessPackedByteArray::get_position() const {
	return pos;
}

uint64_t FileAccessPackedByteArray::get_length() const {
	return data.size();
}

bool FileAccessPackedByteArray::eof_reached() const {
	return pos >= (uint64_t)data.size();
}

uint64_t FileAccessPackedByteArray::get_buffer(uint8_t *p_dst, uint64_t p_length) const {
	ERR_FAIL_NULL_V(p_dst, -1);
	if (!p_length) {
		return 0;
	}

	const uint64_t length = uint64_t(data.size());
	// The cursor can temporarily be at EOF after a shrink. Avoid unsigned
	// underflow and do not dereference an empty array (even for a zero copy).
	const uint64_t available = pos < length ? length - pos : 0;
	const uint64_t read = MIN(p_length, available);

	if (read < p_length) {
		WARN_PRINT("Reading less data than requested");
	}

	if (read > 0) {
		memcpy(p_dst, data.ptr() + pos, read);
		pos += read;
	}

	return read;
}

Error FileAccessPackedByteArray::get_error() const {
	return pos >= (uint64_t)data.size() ? ERR_FILE_EOF : OK;
}

Error FileAccessPackedByteArray::resize(int64_t p_length) {
	const Error err = data.resize(p_length);
	if (err == OK && pos > uint64_t(data.size())) {
		pos = uint64_t(data.size());
	}
	return err;
}

bool FileAccessPackedByteArray::store_buffer(const uint8_t *p_src, uint64_t p_length) {
	if (!p_length) {
		return true;
	}

	ERR_FAIL_NULL_V(p_src, false);

	const uint64_t length = uint64_t(data.size());
	const uint64_t available = pos < length ? length - pos : 0;
	const uint64_t write = MIN(p_length, available);

	// Only request writable storage when bytes will actually be changed.
	// An out-of-range write must not detach PackedByteArray's COW storage.
	if (write > 0) {
		memcpy(data.ptrw() + pos, p_src, write);
		pos += write;
	}

	ERR_FAIL_COND_V_MSG(write < p_length, false, "Writing less data than requested.");

	return true;
}
