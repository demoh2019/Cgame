/**************************************************************************/
/*  compression.cpp                                                       */
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

#include "compression.h"

#include "core/io/zip_io.h"

#include <thirdparty/misc/fastlz.h>

#include <zlib.h>
#include <zstd.h>

#ifdef BROTLI_ENABLED
#include <brotli/decode.h>
#endif

// Validate our forward-declared magic numbers.
static_assert(Z_DEFAULT_COMPRESSION == -1);
#ifdef ZSTD_WINDOWLOG_LIMIT_DEFAULT
static_assert(ZSTD_WINDOWLOG_LIMIT_DEFAULT == 27);
#endif

namespace {
struct ZstdDecompressorContext {
	ZSTD_DCtx *zstd_d_ctx = nullptr;
	bool zstd_long_distance_matching = false;
	int zstd_window_log_size = 0;

	~ZstdDecompressorContext() {
		if (zstd_d_ctx) {
			ZSTD_freeDCtx(zstd_d_ctx);
		}
	}

	void invalidate(bool p_zstd_long_distance_matching, int p_zstd_window_log_size) {
		if (!zstd_d_ctx || zstd_long_distance_matching != p_zstd_long_distance_matching || zstd_window_log_size != p_zstd_window_log_size) {
			if (zstd_d_ctx) {
				ZSTD_freeDCtx(zstd_d_ctx);
			}

			zstd_d_ctx = ZSTD_createDCtx();
			if (p_zstd_long_distance_matching) {
				ZSTD_DCtx_setParameter(zstd_d_ctx, ZSTD_d_windowLogMax, p_zstd_window_log_size);
			}
			zstd_long_distance_matching = p_zstd_long_distance_matching;
			zstd_window_log_size = p_zstd_window_log_size;
		}
	}
};
} //namespace

Compression::ZstdCompressionContext::~ZstdCompressionContext() {
	if (context) {
		ZSTD_freeCCtx(context);
	}
}

int64_t Compression::ZstdCompressionContext::compress(uint8_t *p_dst, const uint8_t *p_src, int64_t p_src_size) {
	ERR_FAIL_COND_V(p_src_size < 0, -1);

	if (!context) {
		context = ZSTD_createCCtx();
		ERR_FAIL_NULL_V(context, -1);
	}

	// Reset parameters only when settings change. ZSTD_compressCCtx() ends
	// each independent frame and reuses the context's existing workspace.
	if (configured_level != Compression::zstd_level ||
			configured_long_distance_matching != Compression::zstd_long_distance_matching ||
			configured_window_log_size != Compression::zstd_window_log_size) {
		size_t result = ZSTD_CCtx_reset(context, ZSTD_reset_parameters);
		ERR_FAIL_COND_V(ZSTD_isError(result), -1);
		result = ZSTD_CCtx_setParameter(context, ZSTD_c_compressionLevel, Compression::zstd_level);
		ERR_FAIL_COND_V(ZSTD_isError(result), -1);
		if (Compression::zstd_long_distance_matching) {
			result = ZSTD_CCtx_setParameter(context, ZSTD_c_enableLongDistanceMatching, 1);
			ERR_FAIL_COND_V(ZSTD_isError(result), -1);
			result = ZSTD_CCtx_setParameter(context, ZSTD_c_windowLog, Compression::zstd_window_log_size);
			ERR_FAIL_COND_V(ZSTD_isError(result), -1);
		}
		configured_level = Compression::zstd_level;
		configured_long_distance_matching = Compression::zstd_long_distance_matching;
		configured_window_log_size = Compression::zstd_window_log_size;
	}

	const int64_t max_dst_size = Compression::get_max_compressed_buffer_size(p_src_size, MODE_ZSTD);
	ERR_FAIL_COND_V(max_dst_size < 0, -1);
	const size_t result = ZSTD_compressCCtx(context, p_dst, max_dst_size, p_src, p_src_size, Compression::zstd_level);
	ERR_FAIL_COND_V(ZSTD_isError(result), -1);
	return int64_t(result);
}

int64_t Compression::compress(uint8_t *p_dst, const uint8_t *p_src, int64_t p_src_size, Mode p_mode) {
	switch (p_mode) {
		case MODE_BROTLI: {
			ERR_FAIL_V_MSG(-1, "Only brotli decompression is supported.");
		} break;
		case MODE_FASTLZ: {
			ERR_FAIL_COND_V_MSG(p_src_size > INT32_MAX, -1, "Cannot compress a FastLZ/LZ77 file 2 GiB or larger. LZ77 supports larger files, but FastLZ's implementation uses C++ `int` so is limited to 2 GiB. Consider using Zstd instead.");
			if (p_src_size < 16) {
				uint8_t src[16];
				memset(&src[p_src_size], 0, 16 - p_src_size);
				memcpy(src, p_src, p_src_size);
				return fastlz_compress(src, 16, p_dst);
			} else {
				return fastlz_compress(p_src, p_src_size, p_dst);
			}

		} break;
		case MODE_DEFLATE:
		case MODE_GZIP: {
			ERR_FAIL_COND_V_MSG(p_src_size > INT32_MAX, -1, "Cannot compress a Deflate or GZip file 2 GiB or larger. Deflate and GZip are both limited to 4 GiB, and ZLib's implementation uses C++ `int` so is limited to 2 GiB. Consider using Zstd instead.");
			int window_bits = p_mode == MODE_DEFLATE ? 15 : 15 + 16;

			z_stream strm;
			strm.zalloc = zipio_alloc;
			strm.zfree = zipio_free;
			strm.opaque = Z_NULL;
			int level = p_mode == MODE_DEFLATE ? zlib_level : gzip_level;
			int err = deflateInit2(&strm, level, Z_DEFLATED, window_bits, 8, Z_DEFAULT_STRATEGY);
			if (err != Z_OK) {
				return -1;
			}

			strm.avail_in = p_src_size;
			int aout = deflateBound(&strm, p_src_size);
			strm.avail_out = aout;
			strm.next_in = (Bytef *)p_src;
			strm.next_out = p_dst;
			deflate(&strm, Z_FINISH);
			aout = aout - strm.avail_out;
			deflateEnd(&strm);
			return aout;

		} break;
		case MODE_ZSTD: {
			ZstdCompressionContext context;
			return context.compress(p_dst, p_src, p_src_size);
		} break;
	}

	ERR_FAIL_V(-1);
}

int64_t Compression::get_max_compressed_buffer_size(int64_t p_src_size, Mode p_mode) {
	switch (p_mode) {
		case MODE_BROTLI: {
			ERR_FAIL_V_MSG(-1, "Only brotli decompression is supported.");
		} break;
		case MODE_FASTLZ: {
			ERR_FAIL_COND_V_MSG(p_src_size > INT32_MAX, -1, "Cannot compress a FastLZ/LZ77 file 2 GiB or larger. LZ77 supports larger files, but FastLZ's implementation uses C++ `int` so is limited to 2 GiB. Consider using Zstd instead.");
			int ss = p_src_size + p_src_size * 6 / 100;
			if (ss < 66) {
				ss = 66;
			}
			return ss;

		} break;
		case MODE_DEFLATE:
		case MODE_GZIP: {
			ERR_FAIL_COND_V_MSG(p_src_size > INT32_MAX, -1, "Cannot compress a Deflate or GZip file 2 GiB or larger. Deflate and GZip are both limited to 4 GiB, and ZLib's implementation uses C++ `int` so is limited to 2 GiB. Consider using Zstd instead.");
			int window_bits = p_mode == MODE_DEFLATE ? 15 : 15 + 16;

			z_stream strm;
			strm.zalloc = zipio_alloc;
			strm.zfree = zipio_free;
			strm.opaque = Z_NULL;
			int err = deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, window_bits, 8, Z_DEFAULT_STRATEGY);
			if (err != Z_OK) {
				return -1;
			}
			int aout = deflateBound(&strm, p_src_size);
			deflateEnd(&strm);
			return aout;
		} break;
		case MODE_ZSTD: {
			return ZSTD_compressBound(p_src_size);
		} break;
	}

	ERR_FAIL_V(-1);
}

int64_t Compression::decompress(uint8_t *p_dst, int64_t p_dst_max_size, const uint8_t *p_src, int64_t p_src_size, Mode p_mode) {
	switch (p_mode) {
		case MODE_BROTLI: {
#ifdef BROTLI_ENABLED
			size_t ret_size = p_dst_max_size;
			BrotliDecoderResult res = BrotliDecoderDecompress(p_src_size, p_src, &ret_size, p_dst);
			ERR_FAIL_COND_V(res != BROTLI_DECODER_RESULT_SUCCESS, -1);
			return ret_size;
#else
			ERR_FAIL_V_MSG(-1, "Godot was compiled without brotli support.");
#endif
		} break;
		case MODE_FASTLZ: {
			ERR_FAIL_COND_V_MSG(p_dst_max_size > INT32_MAX, -1, "Cannot decompress a FastLZ/LZ77 file 2 GiB or larger. LZ77 supports larger files, but FastLZ's implementation uses C++ `int` so is limited to 2 GiB. Consider using Zstd instead.");
			int ret_size = 0;

			if (p_dst_max_size < 16) {
				uint8_t dst[16];
				fastlz_decompress(p_src, p_src_size, dst, 16);
				memcpy(p_dst, dst, p_dst_max_size);
				ret_size = p_dst_max_size;
			} else {
				ret_size = fastlz_decompress(p_src, p_src_size, p_dst, p_dst_max_size);
			}
			return ret_size;
		} break;
		case MODE_DEFLATE:
		case MODE_GZIP: {
			ERR_FAIL_COND_V_MSG(p_dst_max_size > INT32_MAX, -1, "Cannot decompress a Deflate or GZip file 2 GiB or larger. Deflate and GZip are both limited to 4 GiB, and ZLib's implementation uses C++ `int` so is limited to 2 GiB. Consider using Zstd instead.");
			int window_bits = p_mode == MODE_DEFLATE ? 15 : 15 + 16;

			z_stream strm;
			strm.zalloc = zipio_alloc;
			strm.zfree = zipio_free;
			strm.opaque = Z_NULL;
			strm.avail_in = 0;
			strm.next_in = Z_NULL;
			int err = inflateInit2(&strm, window_bits);
			ERR_FAIL_COND_V(err != Z_OK, -1);

			strm.avail_in = p_src_size;
			strm.avail_out = p_dst_max_size;
			strm.next_in = (Bytef *)p_src;
			strm.next_out = p_dst;

			err = inflate(&strm, Z_FINISH);
			int total = strm.total_out;
			inflateEnd(&strm);
			ERR_FAIL_COND_V(err != Z_STREAM_END, -1);
			return total;
		} break;
		case MODE_ZSTD: {
			thread_local ZstdDecompressorContext decompressor_ctx;
			decompressor_ctx.invalidate(zstd_long_distance_matching, zstd_window_log_size);

			size_t ret = ZSTD_decompressDCtx(decompressor_ctx.zstd_d_ctx, p_dst, p_dst_max_size, p_src, p_src_size);
			return (int64_t)ret;
		} break;
	}

	ERR_FAIL_V(-1);
}

/**
	This will handle both Gzip and Deflate streams. It will automatically allocate the output buffer into the provided p_dst_vect Vector.
	This is required for compressed data whose final uncompressed size is unknown, as is the case for HTTP response bodies.
	This is much slower however than using Compression::decompress because it may result in multiple full copies of the output buffer.
*/
int Compression::decompress_dynamic(Vector<uint8_t> *p_dst_vect, int64_t p_max_dst_size, const uint8_t *p_src, int64_t p_src_size, Mode p_mode) {
	ERR_FAIL_NULL_V(p_dst_vect, Z_STREAM_ERROR);
	ERR_FAIL_NULL_V(p_src, Z_DATA_ERROR);
	ERR_FAIL_COND_V(p_src_size <= 0, Z_DATA_ERROR);
	ERR_FAIL_COND_V(gzip_chunk <= 0, Z_BUF_ERROR);

	// The output array has a signed 32-bit element count. Allocate just one
	// byte past a caller-supplied limit so the decoder can distinguish a
	// successful exact-limit stream from one that exceeds the limit.
	int64_t hard_limit = INT32_MAX;
	if (p_max_dst_size >= 0 && p_max_dst_size < INT32_MAX) {
		hard_limit = p_max_dst_size + 1;
	}
	auto grow_output = [&]() -> bool {
		const int64_t allocated = p_dst_vect->size();
		const int64_t wanted = MIN(allocated + int64_t(gzip_chunk), hard_limit);
		return wanted > allocated && p_dst_vect->resize_uninitialized(wanted) == OK;
	};

	if (p_mode == MODE_BROTLI) {
#ifdef BROTLI_ENABLED
		BrotliDecoderState *state = BrotliDecoderCreateInstance(nullptr, nullptr, nullptr);
		ERR_FAIL_NULL_V(state, Z_MEM_ERROR);
		p_dst_vect->clear();

		const uint8_t *next_in = p_src;
		size_t avail_in = size_t(p_src_size);
		size_t total_out = 0;

		while (true) {
			if (total_out == size_t(p_dst_vect->size()) && !grow_output()) {
				BrotliDecoderDestroyInstance(state);
				p_dst_vect->clear();
				return Z_BUF_ERROR;
			}

			// Brotli reports the cumulative number of decompressed bytes.
			// Preserve unused room within the last chunk and never advance
			// the output cursor by the nominal chunk size.
			uint8_t *next_out = p_dst_vect->ptrw() + total_out;
			size_t avail_out = size_t(p_dst_vect->size()) - total_out;
			const BrotliDecoderResult result = BrotliDecoderDecompressStream(state, &avail_in, &next_in, &avail_out, &next_out, &total_out);

			if (p_max_dst_size >= 0 && total_out > uint64_t(p_max_dst_size)) {
				BrotliDecoderDestroyInstance(state);
				p_dst_vect->clear();
				return Z_BUF_ERROR;
			}
			if (result == BROTLI_DECODER_RESULT_SUCCESS) {
				p_dst_vect->resize_uninitialized(total_out);
				BrotliDecoderDestroyInstance(state);
				return Z_OK;
			}
			if (result == BROTLI_DECODER_RESULT_ERROR || (result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT && avail_in == 0)) {
				if (result == BROTLI_DECODER_RESULT_ERROR) {
					WARN_PRINT(BrotliDecoderErrorString(BrotliDecoderGetErrorCode(state)));
				}
				BrotliDecoderDestroyInstance(state);
				p_dst_vect->clear();
				return Z_DATA_ERROR;
			}
		}
#else
		ERR_FAIL_V_MSG(Z_ERRNO, "Godot was compiled without brotli support.");
#endif
	}

	ERR_FAIL_COND_V_MSG(p_mode != MODE_DEFLATE && p_mode != MODE_GZIP, Z_ERRNO, "Dynamic decompression is only supported with gzip, DEFLATE, and Brotli compression methods.");
	ERR_FAIL_COND_V(p_src_size > UINT32_MAX, Z_STREAM_ERROR);

	z_stream strm = {};
	const int window_bits = p_mode == MODE_DEFLATE ? 15 : 15 + 16;
	const int err = inflateInit2(&strm, window_bits);
	ERR_FAIL_COND_V(err != Z_OK, Z_MEM_ERROR);

	strm.next_in = const_cast<Bytef *>(p_src);
	strm.avail_in = uInt(p_src_size);
	p_dst_vect->clear();

	while (true) {
		if (strm.total_out == uLong(p_dst_vect->size()) && !grow_output()) {
			inflateEnd(&strm);
			p_dst_vect->clear();
			return Z_BUF_ERROR;
		}

		uint8_t *const dst = p_dst_vect->ptrw();
		strm.next_out = dst + strm.total_out;
		strm.avail_out = uInt(p_dst_vect->size() - strm.total_out);
		const uLong previous_out = strm.total_out;
		const uInt previous_in = strm.avail_in;
		const int result = inflate(&strm, Z_SYNC_FLUSH);

		if (p_max_dst_size >= 0 && strm.total_out > uint64_t(p_max_dst_size)) {
			inflateEnd(&strm);
			p_dst_vect->clear();
			return Z_BUF_ERROR;
		}
		if (result == Z_STREAM_END) {
			p_dst_vect->resize_uninitialized(strm.total_out);
			inflateEnd(&strm);
			return Z_OK;
		}
		if (result != Z_OK || (strm.avail_in == 0 && strm.avail_out > 0) ||
				(strm.total_out == previous_out && strm.avail_in == previous_in)) {
			if (strm.msg) {
				WARN_PRINT(strm.msg);
			}
			inflateEnd(&strm);
			p_dst_vect->clear();
			return result == Z_OK ? Z_DATA_ERROR : result;
		}
	}
}
