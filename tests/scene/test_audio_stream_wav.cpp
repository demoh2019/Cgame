/**************************************************************************/
/*  test_audio_stream_wav.cpp                                             */
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

TEST_FORCE_LINK(test_audio_stream_wav)

#include "core/io/file_access.h"
#include "core/io/marshalls.h"
#include "core/math/math_defs.h"
#include "core/math/math_funcs.h"
#include "scene/audio/audio_stream_player.h"
#include "scene/2d/audio_stream_player_2d.h"
#include "scene/3d/audio_stream_player_3d.h"
#include "scene/resources/audio/audio_stream_wav.h"
#include "tests/test_utils.h"

namespace TestAudioStreamWAV {

// Default wav rate for test cases.
constexpr float WAV_RATE = 44100;
/* Default wav count for test cases. 1 second of audio is used so that the file can be listened
to manually if needed. */
constexpr int WAV_COUNT = WAV_RATE;

float gen_wav(float frequency, float wav_rate, int wav_number) {
	// formula for generating a sin wave with given frequency.
	return Math::sin((Math::TAU * frequency / wav_rate) * wav_number);
}

/* Generates a 440Hz sin wave in channel 0 (mono channel or left stereo channel)
 * and a 261.63Hz wave in channel 1 (right stereo channel).
 * These waves correspond to the music notes A4 and C4 respectively.
 */
Vector<uint8_t> gen_pcm8_test(float wav_rate, int wav_count, bool stereo) {
	Vector<uint8_t> buffer;
	buffer.resize(stereo ? wav_count * 2 : wav_count);

	uint8_t *write_ptr = buffer.ptrw();
	for (int i = 0; i < buffer.size(); i++) {
		float wav;
		if (stereo) {
			if (i % 2 == 0) {
				wav = gen_wav(440, wav_rate, i / 2);
			} else {
				wav = gen_wav(261.63, wav_rate, i / 2);
			}
		} else {
			wav = gen_wav(440, wav_rate, i);
		}

		// Map sin wave to full range of 8-bit values.
		uint8_t wav_8bit = Math::fast_ftoi(((wav + 1) / 2) * UINT8_MAX);
		// Unlike the .wav format, AudioStreamWAV expects signed 8-bit wavs.
		int8_t wav_8bit_signed = wav_8bit - (INT8_MAX + 1);
		// Cast to uint8_t to match Vector<uint8_t> type, but this is really a signed value.
		write_ptr[i] = (uint8_t)wav_8bit_signed;
	}

	return buffer;
}

// Same as gen_pcm8_test but with 16-bit wavs.
Vector<uint8_t> gen_pcm16_test(float wav_rate, int wav_count, bool stereo) {
	Vector<uint8_t> buffer;
	buffer.resize(stereo ? wav_count * 4 : wav_count * 2);

	uint8_t *write_ptr = buffer.ptrw();
	for (int i = 0; i < buffer.size() / 2; i++) {
		float wav;
		if (stereo) {
			if (i % 2 == 0) {
				wav = gen_wav(440, wav_rate, i / 2);
			} else {
				wav = gen_wav(261.63, wav_rate, i / 2);
			}
		} else {
			wav = gen_wav(440, wav_rate, i);
		}

		// Map sin wave to full range of 16-bit values.
		uint16_t wav_16bit = Math::fast_ftoi(((wav + 1) / 2) * UINT16_MAX);
		// The .wav format expects wavs larger than 8 bits to be signed.
		int16_t wav_16bit_signed = wav_16bit - (INT16_MAX + 1);
		// Cast to uint16_t to match encode_uint16 type, but this is really a signed value.
		encode_uint16((uint16_t)wav_16bit_signed, write_ptr + (i * 2));
	}

	return buffer;
}

void run_test(String file_name, AudioStreamWAV::Format data_format, bool stereo, float wav_rate, float wav_count) {
	String save_path = TestUtils::get_temp_path(file_name);

	Vector<uint8_t> test_data;
	if (data_format == AudioStreamWAV::FORMAT_8_BITS) {
		test_data = gen_pcm8_test(wav_rate, wav_count, stereo);
	} else {
		test_data = gen_pcm16_test(wav_rate, wav_count, stereo);
	}

	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	stream->set_mix_rate(wav_rate);
	CHECK(stream->get_mix_rate() == wav_rate);

	stream->set_format(data_format);
	CHECK(stream->get_format() == data_format);

	stream->set_stereo(stereo);
	CHECK(stream->is_stereo() == stereo);

	stream->set_data(test_data);
	CHECK(stream->get_data() == test_data);

	SUBCASE("Stream length is computed properly") {
		CHECK(stream->get_length() == doctest::Approx(double(wav_count / wav_rate)));
	}

	SUBCASE("Stream can be saved as .wav") {
		REQUIRE(stream->save_to_wav(save_path) == OK);

		Error error;
		Ref<FileAccess> wav_file = FileAccess::open(save_path, FileAccess::READ, &error);
		REQUIRE(error == OK);

		Dictionary options;
		Ref<AudioStreamWAV> loaded_stream = AudioStreamWAV::load_from_file(save_path, options);

		CHECK(loaded_stream->get_format() == stream->get_format());
		CHECK(loaded_stream->get_loop_mode() == stream->get_loop_mode());
		CHECK(loaded_stream->get_loop_begin() == stream->get_loop_begin());
		CHECK(loaded_stream->get_loop_end() == stream->get_loop_end());
		CHECK(loaded_stream->get_mix_rate() == stream->get_mix_rate());
		CHECK(loaded_stream->is_stereo() == stream->is_stereo());
		CHECK(loaded_stream->get_length() == stream->get_length());
		CHECK(loaded_stream->is_monophonic() == stream->is_monophonic());
		CHECK(loaded_stream->get_data() == stream->get_data());
	}
}

TEST_CASE("[Audio][AudioStreamWAV] Mono PCM8 format") {
	run_test("test_pcm8_mono.wav", AudioStreamWAV::FORMAT_8_BITS, false, WAV_RATE, WAV_COUNT);
}

TEST_CASE("[Audio][AudioStreamWAV] Mono PCM16 format") {
	run_test("test_pcm16_mono.wav", AudioStreamWAV::FORMAT_16_BITS, false, WAV_RATE, WAV_COUNT);
}

TEST_CASE("[Audio][AudioStreamWAV] Stereo PCM8 format") {
	run_test("test_pcm8_stereo.wav", AudioStreamWAV::FORMAT_8_BITS, true, WAV_RATE, WAV_COUNT);
}

TEST_CASE("[Audio][AudioStreamWAV] Stereo PCM16 format") {
	run_test("test_pcm16_stereo.wav", AudioStreamWAV::FORMAT_16_BITS, true, WAV_RATE, WAV_COUNT);
}

TEST_CASE("[Audio][AudioStreamWAV] Alternate mix rate") {
	run_test("test_pcm16_stereo_38000Hz.wav", AudioStreamWAV::FORMAT_16_BITS, true, 38000, 38000);
}

TEST_CASE("[Audio][AudioStreamWAV] save_to_wav() adds '.wav' file extension automatically") {
	String save_path = TestUtils::get_temp_path("test_wav_extension");
	Vector<uint8_t> test_data = gen_pcm8_test(WAV_RATE, WAV_COUNT, false);
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	stream->set_data(test_data);

	REQUIRE(stream->save_to_wav(save_path) == OK);
	Error error;
	Ref<FileAccess> wav_file = FileAccess::open(save_path + ".wav", FileAccess::READ, &error);
	CHECK(error == OK);
}


TEST_CASE("[Audio][AudioStreamWAV] Chunked file and memory decoding are identical") {
	// 8193 frames deliberately cross the 4096-byte sample buffer boundary
	// for both mono/stereo and PCM8/PCM16.
	const int frames = 8193;
	for (int bits = 0; bits < 2; bits++) {
		for (int channels = 0; channels < 2; channels++) {
			const bool stereo = channels != 0;
			Ref<AudioStreamWAV> original;
			original.instantiate();
			original->set_format(bits ? AudioStreamWAV::FORMAT_16_BITS : AudioStreamWAV::FORMAT_8_BITS);
			original->set_stereo(stereo);
			original->set_mix_rate(WAV_RATE);
			original->set_data(bits ? gen_pcm16_test(WAV_RATE, frames, stereo) : gen_pcm8_test(WAV_RATE, frames, stereo));

			const String path = TestUtils::get_temp_path(vformat("chunked_wav_%d_%d.wav", bits, channels));
			REQUIRE(original->save_to_wav(path) == OK);
			Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(path);
			REQUIRE(bytes.size() > 4096);
			Ref<AudioStreamWAV> disk = AudioStreamWAV::load_from_file(path, Dictionary());
			Ref<AudioStreamWAV> memory = AudioStreamWAV::load_from_buffer(bytes, Dictionary());
			REQUIRE(disk.is_valid());
			REQUIRE(memory.is_valid());
			CHECK_EQ(disk->get_data(), memory->get_data());
			CHECK_EQ(disk->get_data(), original->get_data());
			CHECK_EQ(disk->get_mix_rate(), memory->get_mix_rate());
			CHECK_EQ(disk->is_stereo(), memory->is_stereo());
			CHECK_EQ(disk->get_format(), memory->get_format());
		}
	}
}

TEST_CASE("[Audio][AudioStreamWAV] Default values") {
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	CHECK(stream->get_format() == AudioStreamWAV::FORMAT_8_BITS);
	CHECK(stream->get_loop_mode() == AudioStreamWAV::LOOP_DISABLED);
	CHECK(stream->get_loop_begin() == 0);
	CHECK(stream->get_loop_end() == 0);
	CHECK(stream->get_mix_rate() == 44100);
	CHECK(stream->is_stereo() == false);
	CHECK(stream->get_length() == 0);
	CHECK(stream->is_monophonic() == false);
	CHECK(stream->get_data() == Vector<uint8_t>{});
}

TEST_CASE("[Audio][AudioStreamWAV] Save empty file") {
	run_test("test_empty.wav", AudioStreamWAV::FORMAT_8_BITS, false, WAV_RATE, 0);
}

TEST_CASE("[Audio][AudioStreamWAV] Saving IMA ADPCM is not supported") {
	String save_path = TestUtils::get_temp_path("test_adpcm.wav");
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	stream->set_format(AudioStreamWAV::FORMAT_IMA_ADPCM);
	ERR_PRINT_OFF;
	CHECK(stream->save_to_wav(save_path) == ERR_UNAVAILABLE);
	ERR_PRINT_ON;
}

TEST_CASE("[Audio][AudioStreamWAV] WAV loop negative offsets are end-relative") {
	const String path = TestUtils::get_temp_path("upstream_wav_loop_negative.wav");
	Ref<AudioStreamWAV> original;
	original.instantiate();
	original->set_format(AudioStreamWAV::FORMAT_16_BITS);
	original->set_mix_rate(44100);
	original->set_data(gen_pcm16_test(44100, 64, false));
	REQUIRE(original->save_to_wav(path) == OK);

	struct LoopCase {
		int64_t begin;
		int64_t end;
		int64_t expected_begin;
		int64_t expected_end;
	};
	const LoopCase cases[] = {
		{ -1, -1, 64, 64 },
		{ -2, -1, 63, 64 },
		{ -64, -3, 1, 62 },
		{ -65, -66, 0, 0 },
		{ 0, -1, 0, 64 },
		{ 8, 1000, 8, 64 },
	};
	for (const LoopCase &test : cases) {
		INFO("Begin: ", test.begin, ", end: ", test.end);
		Dictionary options;
		options["edit/loop_mode"] = 2; // Loop forward (import enum).
		options["edit/loop_begin"] = test.begin;
		options["edit/loop_end"] = test.end;
		Ref<AudioStreamWAV> imported = AudioStreamWAV::load_from_file(path, options);
		REQUIRE(imported.is_valid());
		CHECK(imported->get_loop_mode() == AudioStreamWAV::LOOP_FORWARD);
		CHECK(imported->get_loop_begin() == test.expected_begin);
		CHECK(imported->get_loop_end() == test.expected_end);
	}
}

TEST_CASE("[Audio][AudioStreamWAV] WAV explicit loop endpoints preserve last-frame boundary") {
	const String path = TestUtils::get_temp_path("upstream_wav_loop_boundary.wav");
	Ref<AudioStreamWAV> original;
	original.instantiate();
	original->set_format(AudioStreamWAV::FORMAT_8_BITS);
	original->set_mix_rate(22050);
	original->set_data(gen_pcm8_test(22050, 32, false));
	REQUIRE(original->save_to_wav(path) == OK);

	for (int loop_mode : { 2, 3, 4 }) {
		INFO("Loop import mode: ", loop_mode);
		Dictionary options;
		options["edit/loop_mode"] = loop_mode;
		options["edit/loop_begin"] = 2;
		options["edit/loop_end"] = -1;
		Ref<AudioStreamWAV> imported = AudioStreamWAV::load_from_file(path, options);
		REQUIRE(imported.is_valid());
		CHECK(imported->get_loop_mode() == AudioStreamWAV::LoopMode(loop_mode - 1));
		CHECK(imported->get_loop_begin() == 2);
		CHECK(imported->get_loop_end() == 32);
		CHECK(imported->get_length() == doctest::Approx(32.0 / 22050.0));
	}
}


TEST_CASE("[Audio][AudioStreamWAV] copy-on-write get_data shares the original large buffer") {
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	Vector<uint8_t> original;
	original.resize(256 * 1024);
	uint8_t *original_write = original.ptrw();
	for (int i = 0; i < original.size(); i++) {
		original_write[i] = uint8_t(i % 251);
	}
	stream->set_data(original);

	// No additional 256 KiB allocation is required to read this buffer.
	const Vector<uint8_t> snapshot = stream->get_data();
	REQUIRE_EQ(snapshot.size(), original.size());
	CHECK(snapshot.ptr() == original.ptr());
	CHECK_EQ(snapshot[0], uint8_t(0));
	CHECK_EQ(snapshot[snapshot.size() - 1], uint8_t((snapshot.size() - 1) % 251));
}

TEST_CASE("[Audio][AudioStreamWAV] mutating a returned buffer detaches without changing stream samples") {
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	Vector<uint8_t> raw;
	raw.resize(64 * 1024);
	uint8_t *raw_write = raw.ptrw();
	for (int i = 0; i < raw.size(); i++) {
		raw_write[i] = uint8_t(i % 239);
	}
	stream->set_data(raw);

	Vector<uint8_t> snapshot = stream->get_data();
	REQUIRE(snapshot.ptr() == raw.ptr());
	snapshot.ptrw()[0] = 253;
	snapshot.ptrw()[1024] = 254;
	CHECK(snapshot.ptr() != raw.ptr());
	CHECK_EQ(raw[0], uint8_t(0));
	CHECK_EQ(raw[1024], uint8_t(1024 % 239));
	const Vector<uint8_t> streamed = stream->get_data();
	CHECK_EQ(streamed[0], uint8_t(0));
	CHECK_EQ(streamed[1024], uint8_t(1024 % 239));
	CHECK_EQ(snapshot[0], uint8_t(253));
	CHECK_EQ(snapshot[1024], uint8_t(254));
}

TEST_CASE("[Audio][AudioStreamWAV] replacing data preserves previous snapshots") {
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	Vector<uint8_t> first = { 12, 34, 56, 78 };
	stream->set_data(first);
	const Vector<uint8_t> old_snapshot = stream->get_data();
	const Vector<uint8_t> next = { 1, 2, 3 };
	stream->set_data(next);
	CHECK_EQ(old_snapshot.size(), 4);
	CHECK_EQ(old_snapshot[0], uint8_t(12));
	CHECK_EQ(old_snapshot[3], uint8_t(78));
	const Vector<uint8_t> current = stream->get_data();
	REQUIRE_EQ(current.size(), 3);
	CHECK_EQ(current[0], uint8_t(1));
	CHECK_EQ(current[2], uint8_t(3));
}

TEST_CASE("[Audio][AudioStreamWAV] empty sample buffers remain valid") {
	Ref<AudioStreamWAV> stream = memnew(AudioStreamWAV);
	const Vector<uint8_t> empty = stream->get_data();
	CHECK(empty.is_empty());
	stream->set_data(Vector<uint8_t>());
	CHECK(stream->get_data().is_empty());
}


TEST_CASE("[AudioSetterFastPath] AudioStreamPlayer avoids redundant volume and pitch updates") {
	AudioStreamPlayer *player = memnew(AudioStreamPlayer);
	CHECK_EQ(player->get_volume_db(), 0.0f);
	player->set_volume_db(-12.5f);
	CHECK_EQ(player->get_volume_db(), -12.5f);
	for (int i = 0; i < 128; i++) {
		player->set_volume_db(-12.5f);
		CHECK_EQ(player->get_volume_db(), -12.5f);
	}
	player->set_pitch_scale(1.75f);
	CHECK_EQ(player->get_pitch_scale(), 1.75f);
	for (int i = 0; i < 128; i++) {
		player->set_pitch_scale(1.75f);
		CHECK_EQ(player->get_pitch_scale(), 1.75f);
	}
	memdelete(player);
}

TEST_CASE("[AudioSetterFastPath] exact small volume changes remain observable") {
	AudioStreamPlayer *player = memnew(AudioStreamPlayer);
	player->set_volume_db(-6.0f);
	player->set_volume_db(-6.0001f);
	CHECK_EQ(player->get_volume_db(), -6.0001f);
	player->set_volume_db(-6.0f);
	CHECK_EQ(player->get_volume_db(), -6.0f);
	memdelete(player);
}

TEST_CASE("[AudioSetterFastPath] pitch changes still apply after repeated identical values") {
	AudioStreamPlayer *player = memnew(AudioStreamPlayer);
	player->set_pitch_scale(1.25f);
	player->set_pitch_scale(1.25f);
	player->set_pitch_scale(0.75f);
	CHECK_EQ(player->get_pitch_scale(), 0.75f);
	ERR_PRINT_OFF;
	player->set_pitch_scale(0.0f);
	ERR_PRINT_ON;
	CHECK_EQ(player->get_pitch_scale(), 0.75f);
	memdelete(player);
}

TEST_CASE("[AudioSetterFastPath] AudioStreamPlayer2D shares the guarded pitch update path") {
	AudioStreamPlayer2D *player = memnew(AudioStreamPlayer2D);
	player->set_pitch_scale(1.5f);
	for (int i = 0; i < 128; i++) {
		player->set_pitch_scale(1.5f);
	}
	CHECK_EQ(player->get_pitch_scale(), 1.5f);
	player->set_pitch_scale(0.5f);
	CHECK_EQ(player->get_pitch_scale(), 0.5f);
	memdelete(player);
}

TEST_CASE("[AudioSetterFastPath] AudioStreamPlayer3D shares the guarded pitch update path") {
	AudioStreamPlayer3D *player = memnew(AudioStreamPlayer3D);
	player->set_pitch_scale(1.5f);
	for (int i = 0; i < 128; i++) {
		player->set_pitch_scale(1.5f);
	}
	CHECK_EQ(player->get_pitch_scale(), 1.5f);
	player->set_pitch_scale(0.5f);
	CHECK_EQ(player->get_pitch_scale(), 0.5f);
	memdelete(player);
}

} // namespace TestAudioStreamWAV
