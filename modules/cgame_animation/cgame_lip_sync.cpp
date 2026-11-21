/**************************************************************************/
/*  cgame_lip_sync.cpp                                                    */
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

#include "cgame_lip_sync.h"

#include "core/object/class_db.h"
#include "core/templates/hash_map.h"

namespace {

struct GraphemeRule {
	const char32_t *pattern;
	const char *phones;
};

const GraphemeRule EN_RULES[] = {
	{ U"tion", "sh ah n" }, { U"sion", "sh ah n" }, { U"ough", "ah f" }, { U"igh", "ay" },
	{ U"tch", "ch" }, { U"dge", "j" },
	{ U"sh", "sh" }, { U"ch", "ch" }, { U"th", "th" }, { U"ph", "f" }, { U"ck", "k" }, { U"ng", "n g" },
	{ U"qu", "k w" }, { U"wh", "w" }, { U"gh", "" }, { U"kn", "n" }, { U"wr", "r" }, { U"mb", "m" },
	{ U"ee", "iy" }, { U"ea", "iy" }, { U"oo", "uw" }, { U"ou", "aw" }, { U"ow", "ow" }, { U"oa", "ow" },
	{ U"ai", "ey" }, { U"ay", "ey" }, { U"oi", "oy" }, { U"oy", "oy" }, { U"au", "ao" }, { U"aw", "ao" },
	{ U"ie", "iy" }, { U"ei", "ey" }, { U"ew", "uw" }, { U"ar", "aa r" }, { U"or", "ao r" }, { U"er", "er" },
	{ U"ir", "er" }, { U"ur", "er" },
};

const char *en_letter(char32_t p_c) {
	switch (p_c) {
		case 'a': return "ae";
		case 'b': return "b";
		case 'c': return "k";
		case 'd': return "d";
		case 'e': return "eh";
		case 'f': return "f";
		case 'g': return "g";
		case 'h': return "h";
		case 'i': return "ih";
		case 'j': return "j";
		case 'k': return "k";
		case 'l': return "l";
		case 'm': return "m";
		case 'n': return "n";
		case 'o': return "aa";
		case 'p': return "p";
		case 'q': return "k";
		case 'r': return "r";
		case 's': return "s";
		case 't': return "t";
		case 'u': return "ah";
		case 'v': return "v";
		case 'w': return "w";
		case 'x': return "k s";
		case 'y': return "iy";
		case 'z': return "z";
		default: return nullptr;
	}
}

const char *ru_letter(char32_t p_c) {
	switch (p_c) {
		case U'а': return "aa";
		case U'б': return "b";
		case U'в': return "v";
		case U'г': return "g";
		case U'д': return "d";
		case U'е': return "eh";
		case U'ё': return "ow";
		case U'ж': return "sh";
		case U'з': return "z";
		case U'и': return "iy";
		case U'й': return "y";
		case U'к': return "k";
		case U'л': return "l";
		case U'м': return "m";
		case U'н': return "n";
		case U'о': return "ao";
		case U'п': return "p";
		case U'р': return "r";
		case U'с': return "s";
		case U'т': return "t";
		case U'у': return "uw";
		case U'ф': return "f";
		case U'х': return "h";
		case U'ц': return "t s";
		case U'ч': return "ch";
		case U'ш': return "sh";
		case U'щ': return "sh";
		case U'ъ': return "";
		case U'ь': return "";
		case U'ы': return "ih";
		case U'э': return "eh";
		case U'ю': return "y uw";
		case U'я': return "y aa";
		default: return nullptr;
	}
}

struct VisemeEntry {
	const char *phoneme;
	const char *viseme;
};

const VisemeEntry VISEME_OF[] = {
	{ "p", "A" }, { "b", "A" }, { "m", "A" },
	{ "f", "G" }, { "v", "G" },
	{ "l", "H" }, { "th", "H" },
	{ "w", "F" }, { "uw", "F" }, { "ow", "F" }, { "sh", "F" }, { "ch", "F" }, { "j", "F" },
	{ "ao", "E" }, { "er", "E" }, { "oy", "E" }, { "uh", "E" },
	{ "aa", "D" }, { "aw", "D" }, { "ay", "D" },
	{ "eh", "C" }, { "ae", "C" }, { "ah", "C" }, { "ey", "C" },
	{ "ih", "B" }, { "iy", "B" }, { "k", "B" }, { "g", "B" }, { "s", "B" }, { "z", "B" }, { "t", "B" }, { "d", "B" },
	{ "n", "B" }, { "r", "B" }, { "y", "B" }, { "h", "B" },
	{ "sil", "X" },
};

const char *VOWELS[] = { "aa", "ae", "ah", "ao", "eh", "er", "ih", "iy", "uh", "uw", "ow", "aw", "ay", "ey", "oy" };

bool is_open_viseme(const String &p_viseme) {
	return p_viseme == "C" || p_viseme == "D" || p_viseme == "E";
}

} // namespace

bool CgameLipSync::_is_letter(char32_t p_ch) {
	return (p_ch >= 97 && p_ch <= 122) || (p_ch >= 0x0430 && p_ch <= 0x045F);
}

float CgameLipSync::_phoneme_weight(const String &p_phoneme) {
	if (p_phoneme == "sil") {
		return 1.2f;
	}
	for (const char *v : VOWELS) {
		if (p_phoneme == v) {
			return 1.6f;
		}
	}
	if (p_phoneme == "p" || p_phoneme == "b" || p_phoneme == "t" || p_phoneme == "d" || p_phoneme == "k" || p_phoneme == "g") {
		return 0.8f;
	}
	return 1.0f;
}

void CgameLipSync::_append_phones(PackedStringArray &r_out, const String &p_phones) {
	if (p_phones.is_empty()) {
		return;
	}
	const PackedStringArray parts = p_phones.split(" ");
	for (const String &p : parts) {
		r_out.push_back(p);
	}
}

PackedStringArray CgameLipSync::_ru_word(const String &p_word) {
	PackedStringArray out;
	for (int i = 0; i < p_word.length(); i++) {
		const char *ph = ru_letter(p_word[i]);
		if (ph) {
			_append_phones(out, ph);
		}
	}
	return out;
}

PackedStringArray CgameLipSync::_en_word(const String &p_word) {
	PackedStringArray out;
	String w = p_word;
	// Silent trailing "e" after a consonant, as long as a vowel remains in the stem.
	if (w.length() > 2 && w[w.length() - 1] == 'e' && String("aeiouy").find_char(w[w.length() - 2]) < 0) {
		const String stem = w.substr(0, w.length() - 1);
		for (int k = 0; k < stem.length(); k++) {
			if (String("aeiouy").find_char(stem[k]) >= 0) {
				w = stem;
				break;
			}
		}
	}
	const int n = w.length();
	int i = 0;
	while (i < n) {
		bool matched = false;
		for (const GraphemeRule &rule : EN_RULES) {
			const String pat = rule.pattern;
			if (w.substr(i, pat.length()) == pat) {
				_append_phones(out, rule.phones);
				i += pat.length();
				matched = true;
				break;
			}
		}
		if (matched) {
			continue;
		}
		const char32_t ch = w[i];
		const char32_t nxt = i + 1 < n ? w[i + 1] : 0;
		String phones;
		if (ch == 'c' && (nxt == 'e' || nxt == 'i' || nxt == 'y')) {
			phones = "s";
		} else if (ch == 'g' && (nxt == 'e' || nxt == 'i') && i > 0) {
			phones = "j";
		} else if (ch == 'y' && i == 0) {
			phones = "y";
		} else if (ch == 'y' && i == n - 1 && n > 2) {
			phones = "iy";
		} else if (ch == 'y') {
			phones = "ih";
		} else if (const char *l = en_letter(ch)) {
			phones = l;
		}
		_append_phones(out, phones);
		i++;
	}
	return out;
}

PackedStringArray CgameLipSync::phonemes_from_text(const String &p_text, const String &p_language) {
	PackedStringArray out;
	String word;
	const String lower = p_text.to_lower();
	const auto flush_word = [&]() {
		if (word.is_empty()) {
			return;
		}
		const bool ru = p_language == "ru" || word[0] >= 0x0400;
		const PackedStringArray phones = ru ? _ru_word(word) : _en_word(word);
		out.append_array(phones);
	};
	for (int i = 0; i < lower.length(); i++) {
		const char32_t ch = lower[i];
		if (_is_letter(ch)) {
			word += ch;
		} else {
			if (ch == '\'' || ch == 0x2019) {
				continue;
			}
			flush_word();
			word = "";
			if (out.size() > 0 && out[out.size() - 1] != "sil") {
				out.push_back("sil");
			}
		}
	}
	flush_word();
	while (out.size() > 0 && out[out.size() - 1] == "sil") {
		out.remove_at(out.size() - 1);
	}
	return out;
}

String CgameLipSync::viseme_for(const String &p_phoneme) {
	for (const VisemeEntry &e : VISEME_OF) {
		if (p_phoneme == e.phoneme) {
			return e.viseme;
		}
	}
	return "X";
}

static Dictionary _key(float p_time, const String &p_viseme, float p_weight) {
	Dictionary k;
	k["time"] = p_time;
	k["viseme"] = p_viseme;
	k["weight"] = p_weight;
	return k;
}

Array CgameLipSync::timeline(const String &p_text, float p_duration_seconds, const String &p_language) {
	Array keys;
	keys.push_back(_key(0.0f, "X", 1.0f));
	const PackedStringArray phones = phonemes_from_text(p_text, p_language);
	if (p_duration_seconds <= 0.0f || phones.is_empty()) {
		if (p_duration_seconds > 0.0f) {
			keys.push_back(_key(p_duration_seconds, "X", 1.0f));
		}
		return keys;
	}
	float total = 0.0f;
	Vector<float> lengths;
	for (const String &p : phones) {
		const float w = _phoneme_weight(p);
		lengths.push_back(w);
		total += w;
	}
	float cursor = 0.0f;
	for (int i = 0; i < phones.size(); i++) {
		const float seg = p_duration_seconds * lengths[i] / total;
		const String viseme = viseme_for(phones[i]);
		const float mid = cursor + seg * 0.5f;
		cursor += seg;
		const Dictionary last = keys[keys.size() - 1];
		const String last_viseme = last["viseme"];
		const float last_time = last["time"];
		if (viseme == last_viseme) {
			continue;
		}
		if (viseme != "A" && viseme != "X" && mid - last_time < MIN_KEY_GAP) {
			continue;
		}
		if (mid <= last_time) {
			continue;
		}
		keys.push_back(_key(mid, viseme, 1.0f));
	}
	Dictionary tail = keys[keys.size() - 1];
	const float tail_time = tail["time"];
	const String tail_viseme = tail["viseme"];
	if (tail_viseme == "X" && tail_time < p_duration_seconds) {
		tail["time"] = p_duration_seconds;
	} else if (tail_time < p_duration_seconds) {
		keys.push_back(_key(p_duration_seconds, "X", 1.0f));
	}
	return keys;
}

PackedFloat32Array CgameLipSync::amplitude_track(const PackedFloat32Array &p_samples, int p_sample_rate, float p_hop_seconds) {
	PackedFloat32Array env;
	const int hop_n = MAX(1, int(float(p_sample_rate) * p_hop_seconds));
	int pos = 0;
	while (pos < p_samples.size()) {
		const int end = MIN(pos + hop_n, p_samples.size());
		double acc = 0.0;
		for (int i = pos; i < end; i++) {
			acc += double(p_samples[i]) * double(p_samples[i]);
		}
		env.push_back(Math::sqrt(acc / double(end - pos)));
		pos = end;
	}
	return env;
}

Array CgameLipSync::refine_with_audio(const Array &p_timeline, const PackedFloat32Array &p_envelope, float p_hop) {
	float peak = 0.0f;
	for (int i = 0; i < p_envelope.size(); i++) {
		peak = MAX(peak, p_envelope[i]);
	}
	Array out;
	for (int i = 0; i < p_timeline.size(); i++) {
		const Dictionary key = p_timeline[i];
		const float time = key["time"];
		String viseme = key["viseme"];
		float weight = key["weight"];
		float level = 0.0f;
		if (peak > 0.00001f && !p_envelope.is_empty() && p_hop > 0.0f) {
			const int idx = CLAMP(int(time / p_hop), 0, p_envelope.size() - 1);
			float m = p_envelope[idx];
			if (idx > 0) {
				m = MAX(m, p_envelope[idx - 1]);
			}
			if (idx < p_envelope.size() - 1) {
				m = MAX(m, p_envelope[idx + 1]);
			}
			level = CLAMP(m / peak, 0.0f, 1.0f);
		}
		if (level < SILENCE_LEVEL) {
			viseme = "X";
			weight = 1.0f;
		} else if (is_open_viseme(viseme)) {
			weight *= 0.35f + 0.65f * level;
		}
		out.push_back(_key(time, viseme, weight));
	}
	return out;
}

Dictionary CgameLipSync::sample(const Array &p_timeline, float p_time) {
	Dictionary result;
	if (p_timeline.is_empty()) {
		result["X"] = 1.0f;
		return result;
	}
	const Dictionary first = p_timeline[0];
	const Dictionary last = p_timeline[p_timeline.size() - 1];
	if (p_time <= (float)first["time"]) {
		result[String(first["viseme"])] = (float)first["weight"];
		return result;
	}
	if (p_time >= (float)last["time"]) {
		result[String(last["viseme"])] = (float)last["weight"];
		return result;
	}
	int lo = 0;
	int hi = p_timeline.size() - 1;
	while (hi - lo > 1) {
		const int mid = (lo + hi) >> 1;
		const Dictionary mk = p_timeline[mid];
		if ((float)mk["time"] <= p_time) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	const Dictionary a = p_timeline[lo];
	const Dictionary b = p_timeline[hi];
	const float ta = a["time"];
	const float tb = b["time"];
	const String va = a["viseme"];
	const String vb = b["viseme"];
	const float wa = a["weight"];
	const float wb = b["weight"];
	const float trans = MIN(tb - ta, TRANSITION);
	const float start = tb - trans;
	if (p_time < start || trans <= 0.0f) {
		result[va] = wa;
		return result;
	}
	const float s = Math::smoothstep(0.0f, 1.0f, (p_time - start) / trans);
	result[va] = wa * (1.0f - s);
	result[vb] = float(result.get(vb, 0.0f)) + wb * s;
	return result;
}

void CgameLipSync::_bind_methods() {
	const StringName c = "CgameLipSync";
	ClassDB::bind_static_method(c, D_METHOD("phonemes_from_text", "text", "language"), &CgameLipSync::phonemes_from_text, DEFVAL("en"));
	ClassDB::bind_static_method(c, D_METHOD("viseme_for", "phoneme"), &CgameLipSync::viseme_for);
	ClassDB::bind_static_method(c, D_METHOD("timeline", "text", "duration_seconds", "language"), &CgameLipSync::timeline, DEFVAL("en"));
	ClassDB::bind_static_method(c, D_METHOD("amplitude_track", "samples", "sample_rate", "hop_seconds"), &CgameLipSync::amplitude_track, DEFVAL(0.02f));
	ClassDB::bind_static_method(c, D_METHOD("refine_with_audio", "timeline", "envelope", "hop"), &CgameLipSync::refine_with_audio);
	ClassDB::bind_static_method(c, D_METHOD("sample", "timeline", "time"), &CgameLipSync::sample);

}
