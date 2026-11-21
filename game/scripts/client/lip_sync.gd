extends RefCounted
## Automatic lip sync: rule-based grapheme-to-phoneme (English + Cyrillic transliteration),
## phoneme -> 9-shape viseme mapping, coarticulated viseme timeline and audio refinement.
##
## Concepts ported (clean-room GDScript, no code copied) from:
##  - Rhubarb Lip Sync by Daniel Wolf, MIT License, https://github.com/DanielSWolf/rhubarb-lip-sync
##    (mouth shapes A-H + X: A closed P/B/M, B slight open K/S/T/EE, C open EH/AE, D wide AA,
##    E rounded AO/ER, F puckered UW/OW/W, G F/V teeth-on-lip, H L tongue-up, X rest;
##    short mouth shapes are dropped/merged, silence -> X).
##  - Preston Blair phoneme set (public animation convention) and Oculus OVRLipSync viseme
##    groupings (PP FF TH DD kk CH SS nn RR aa E ih oh ou), reduced here to the 9 shapes.
## Pure-GDScript, deterministic, no dictionaries.

const REST := "X"
const OPEN_VISEMES := ["C", "D", "E"]
const SILENCE_LEVEL := 0.1
const TRANSITION := 0.07
const MIN_KEY_GAP := 0.03

# Pattern -> space separated phonemes (ARPAbet-like, lowercase). Longest patterns first.
const EN_RULES := [
	["tion", "sh ah n"], ["sion", "sh ah n"], ["ough", "ah f"], ["igh", "ay"],
	["tch", "ch"], ["dge", "j"],
	["sh", "sh"], ["ch", "ch"], ["th", "th"], ["ph", "f"], ["ck", "k"], ["ng", "n g"],
	["qu", "k w"], ["wh", "w"], ["gh", ""], ["kn", "n"], ["wr", "r"], ["mb", "m"],
	["ee", "iy"], ["ea", "iy"], ["oo", "uw"], ["ou", "aw"], ["ow", "ow"], ["oa", "ow"],
	["ai", "ey"], ["ay", "ey"], ["oi", "oy"], ["oy", "oy"], ["au", "ao"], ["aw", "ao"],
	["ie", "iy"], ["ei", "ey"], ["ew", "uw"], ["ar", "aa r"], ["or", "ao r"], ["er", "er"],
	["ir", "er"], ["ur", "er"],
]
const EN_LETTERS := {
	"a": "ae", "b": "b", "c": "k", "d": "d", "e": "eh", "f": "f", "g": "g", "h": "h",
	"i": "ih", "j": "j", "k": "k", "l": "l", "m": "m", "n": "n", "o": "aa", "p": "p",
	"q": "k", "r": "r", "s": "s", "t": "t", "u": "ah", "v": "v", "w": "w", "x": "k s",
	"y": "iy", "z": "z",
}
const RU_LETTERS := {
	"а": "aa", "б": "b", "в": "v", "г": "g", "д": "d", "е": "eh", "ё": "ow", "ж": "sh",
	"з": "z", "и": "iy", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "ao",
	"п": "p", "р": "r", "с": "s", "т": "t", "у": "uw", "ф": "f", "х": "h", "ц": "t s",
	"ч": "ch", "ш": "sh", "щ": "sh", "ъ": "", "ь": "", "ы": "ih", "э": "eh", "ю": "y uw",
	"я": "y aa",
}
const VOWELS := ["aa", "ae", "ah", "ao", "eh", "er", "ih", "iy", "uh", "uw", "ow", "aw", "ay", "ey", "oy"]
const VISEME_OF := {
	"p": "A", "b": "A", "m": "A",
	"f": "G", "v": "G",
	"l": "H", "th": "H",
	"w": "F", "uw": "F", "ow": "F", "sh": "F", "ch": "F", "j": "F",
	"ao": "E", "er": "E", "oy": "E", "uh": "E",
	"aa": "D", "aw": "D", "ay": "D",
	"eh": "C", "ae": "C", "ah": "C", "ey": "C",
	"ih": "B", "iy": "B", "k": "B", "g": "B", "s": "B", "z": "B", "t": "B", "d": "B",
	"n": "B", "r": "B", "y": "B", "h": "B",
	"sil": "X",
}


static func phonemes_from_text(text: String, language := "en") -> PackedStringArray:
	var out := PackedStringArray()
	var word := ""
	var lower := text.to_lower()
	for i in lower.length():
		var ch := lower[i]
		if _is_letter(ch):
			word += ch
		else:
			if ch == "'" or ch == "’":
				continue
			_flush_word(word, language, out)
			word = ""
			if out.size() > 0 and out[out.size() - 1] != "sil":
				out.append("sil")
	_flush_word(word, language, out)
	while out.size() > 0 and out[out.size() - 1] == "sil":
		out.remove_at(out.size() - 1)
	return out


static func viseme_for(phoneme: String) -> String:
	if VISEME_OF.has(phoneme):
		return str(VISEME_OF[phoneme])
	return REST


static func timeline(text: String, duration_seconds: float, language := "en") -> Array:
	var keys: Array = []
	keys.append({"time": 0.0, "viseme": REST, "weight": 1.0})
	var phones := phonemes_from_text(text, language)
	if duration_seconds <= 0.0 or phones.is_empty():
		if duration_seconds > 0.0:
			keys.append({"time": duration_seconds, "viseme": REST, "weight": 1.0})
		return keys
	var total := 0.0
	var lengths := PackedFloat32Array()
	for p in phones:
		var w := _phoneme_weight(p)
		lengths.append(w)
		total += w
	var cursor := 0.0
	for i in phones.size():
		var seg := duration_seconds * lengths[i] / total
		var viseme := viseme_for(phones[i])
		var mid := cursor + seg * 0.5
		cursor += seg
		var last: Dictionary = keys[keys.size() - 1]
		var last_viseme: String = last["viseme"]
		var last_time: float = last["time"]
		if viseme == last_viseme:
			continue
		# Coarticulation: a very short non-closure shape is swallowed by its neighbours.
		if viseme != "A" and viseme != REST and mid - last_time < MIN_KEY_GAP:
			continue
		if mid <= last_time:
			continue
		keys.append({"time": mid, "viseme": viseme, "weight": 1.0})
	var tail: Dictionary = keys[keys.size() - 1]
	var tail_time: float = tail["time"]
	var tail_viseme: String = tail["viseme"]
	if tail_viseme == REST and tail_time < duration_seconds:
		tail["time"] = duration_seconds
	elif tail_time < duration_seconds:
		keys.append({"time": duration_seconds, "viseme": REST, "weight": 1.0})
	return keys


static func amplitude_track(samples: PackedFloat32Array, sample_rate: int, hop_seconds := 0.02) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	var hop_n := maxi(1, int(float(sample_rate) * hop_seconds))
	var pos := 0
	while pos < samples.size():
		var end := mini(pos + hop_n, samples.size())
		var acc := 0.0
		for i in range(pos, end):
			acc += samples[i] * samples[i]
		env.append(sqrt(acc / float(end - pos)))
		pos = end
	return env


static func refine_with_audio(tl: Array, envelope: PackedFloat32Array, hop: float) -> Array:
	var peak := 0.0
	for v in envelope:
		peak = maxf(peak, v)
	var out: Array = []
	for k in tl:
		var key: Dictionary = k
		var time: float = key["time"]
		var viseme: String = key["viseme"]
		var weight: float = key["weight"]
		var level := 0.0
		if peak > 0.00001 and not envelope.is_empty() and hop > 0.0:
			var idx := clampi(int(time / hop), 0, envelope.size() - 1)
			var m := envelope[idx]
			if idx > 0:
				m = maxf(m, envelope[idx - 1])
			if idx < envelope.size() - 1:
				m = maxf(m, envelope[idx + 1])
			level = clampf(m / peak, 0.0, 1.0)
		if level < SILENCE_LEVEL:
			viseme = REST
			weight = 1.0
		elif OPEN_VISEMES.has(viseme):
			weight *= 0.35 + 0.65 * level
		out.append({"time": time, "viseme": viseme, "weight": weight})
	return out


static func sample(tl: Array, t: float) -> Dictionary:
	var result := {}
	if tl.is_empty():
		result[REST] = 1.0
		return result
	var first: Dictionary = tl[0]
	var last: Dictionary = tl[tl.size() - 1]
	var first_t: float = first["time"]
	var last_t: float = last["time"]
	if t <= first_t:
		result[str(first["viseme"])] = float(first["weight"])
		return result
	if t >= last_t:
		result[str(last["viseme"])] = float(last["weight"])
		return result
	var lo := 0
	var hi := tl.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		var mk: Dictionary = tl[mid]
		var mt: float = mk["time"]
		if mt <= t:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = tl[lo]
	var b: Dictionary = tl[hi]
	var ta: float = a["time"]
	var tb: float = b["time"]
	var va: String = a["viseme"]
	var vb: String = b["viseme"]
	var wa: float = a["weight"]
	var wb: float = b["weight"]
	var trans := minf(tb - ta, TRANSITION)
	var start := tb - trans
	if t < start or trans <= 0.0:
		result[va] = wa
		return result
	var s := smoothstep(0.0, 1.0, (t - start) / trans)
	result[va] = wa * (1.0 - s)
	result[vb] = float(result.get(vb, 0.0)) + wb * s
	return result


static func _phoneme_weight(p: String) -> float:
	if p == "sil":
		return 1.2
	if VOWELS.has(p):
		return 1.6
	if p == "p" or p == "b" or p == "t" or p == "d" or p == "k" or p == "g":
		return 0.8
	return 1.0


static func _is_letter(ch: String) -> bool:
	if ch.is_empty():
		return false
	var c := ch.unicode_at(0)
	return (c >= 97 and c <= 122) or (c >= 0x0430 and c <= 0x045F)


static func _is_cyrillic(word: String) -> bool:
	return word.unicode_at(0) >= 0x0400


static func _flush_word(word: String, language: String, out: PackedStringArray) -> void:
	if word.is_empty():
		return
	var phones: PackedStringArray
	if language == "ru" or _is_cyrillic(word):
		phones = _ru_word(word)
	else:
		phones = _en_word(word)
	out.append_array(phones)


static func _ru_word(word: String) -> PackedStringArray:
	var out := PackedStringArray()
	for i in word.length():
		var ch := word[i]
		if RU_LETTERS.has(ch):
			_append_phones(out, str(RU_LETTERS[ch]))
	return out


static func _en_word(word: String) -> PackedStringArray:
	var out := PackedStringArray()
	var w := word
	# Silent final e after a consonant ("make", "time") when another vowel precedes it.
	if w.length() > 2 and w.ends_with("e") and not "aeiouy".contains(w[w.length() - 2]):
		var stem := w.substr(0, w.length() - 1)
		for v in "aeiouy":
			if stem.contains(v):
				w = stem
				break
	var n := w.length()
	var i := 0
	while i < n:
		var matched := false
		for rule in EN_RULES:
			var pat: String = rule[0]
			if w.substr(i, pat.length()) == pat:
				_append_phones(out, str(rule[1]))
				i += pat.length()
				matched = true
				break
		if matched:
			continue
		var ch := w[i]
		var nxt := w[i + 1] if i + 1 < n else ""
		var phones := ""
		if ch == "c" and (nxt == "e" or nxt == "i" or nxt == "y"):
			phones = "s"
		elif ch == "g" and (nxt == "e" or nxt == "i") and i > 0:
			phones = "j"
		elif ch == "y" and i == 0:
			phones = "y"
		elif ch == "y" and i == n - 1 and n > 2:
			phones = "iy"
		elif ch == "y":
			phones = "ih"
		elif EN_LETTERS.has(ch):
			phones = str(EN_LETTERS[ch])
		_append_phones(out, phones)
		i += 1
	return out


static func _append_phones(out: PackedStringArray, phones: String) -> void:
	if phones.is_empty():
		return
	for p in phones.split(" "):
		out.append(p)
