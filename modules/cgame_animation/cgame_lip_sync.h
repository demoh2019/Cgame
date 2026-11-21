/**************************************************************************/
/*  cgame_lip_sync.h                                                      */
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

#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

// Text-driven lip sync: rule-based English and Russian grapheme-to-phoneme, phoneme-to-viseme
// mapping (Preston Blair style A..H plus X for rest), viseme timelines and optional refinement from
// an audio amplitude envelope. Mirrors scripts/client/lip_sync.gd.
class CgameLipSync : public RefCounted {
	GDCLASS(CgameLipSync, RefCounted);

	static bool _is_letter(char32_t p_ch);
	static float _phoneme_weight(const String &p_phoneme);
	static void _append_phones(PackedStringArray &r_out, const String &p_phones);
	static PackedStringArray _en_word(const String &p_word);
	static PackedStringArray _ru_word(const String &p_word);

protected:
	static void _bind_methods();

public:
	static constexpr float SILENCE_LEVEL = 0.1f;
	static constexpr float TRANSITION = 0.07f;
	static constexpr float MIN_KEY_GAP = 0.03f;

	static PackedStringArray phonemes_from_text(const String &p_text, const String &p_language = "en");
	static String viseme_for(const String &p_phoneme);
	static Array timeline(const String &p_text, float p_duration_seconds, const String &p_language = "en");
	static PackedFloat32Array amplitude_track(const PackedFloat32Array &p_samples, int p_sample_rate, float p_hop_seconds = 0.02f);
	static Array refine_with_audio(const Array &p_timeline, const PackedFloat32Array &p_envelope, float p_hop);
	static Dictionary sample(const Array &p_timeline, float p_time);
};
