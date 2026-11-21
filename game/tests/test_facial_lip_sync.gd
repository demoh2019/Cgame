extends RefCounted
## Lip sync (G2P, visemes, timeline, audio refinement) and the facial animation graph.

const LipSync = preload("res://scripts/client/lip_sync.gd")
const FacialAnimation = preload("res://scripts/client/facial_animation.gd")


func run(t) -> void:
	t.current = "phonemes"
	var en := LipSync.phonemes_from_text("mama", "en")
	t.check(en.size() > 0, "english phonemes non-empty")
	t.check(en.has("m"), "mama contains bilabial m")
	t.eq(LipSync.viseme_for("m"), "A", "m maps to closed lips")
	t.eq(LipSync.viseme_for("f"), "G", "f maps to teeth-on-lip")
	t.eq(LipSync.viseme_for("uw"), "F", "uw maps to pucker")
	t.eq(LipSync.viseme_for("zzz"), "X", "unknown phoneme rests")
	var ru := LipSync.phonemes_from_text("мама", "ru")
	t.check(ru.size() > 0 and ru.has("m"), "russian mama contains m")
	t.eq(LipSync.viseme_for(ru[0]), "A", "russian мама starts with closed lips")
	var auto := LipSync.phonemes_from_text("привет", "en")
	t.check(auto.has("p") and auto.has("v"), "cyrillic detected regardless of language")
	var sentence := LipSync.phonemes_from_text("Hello, world! Make time.", "en")
	t.check(sentence.has("sil"), "word gaps produce silence")
	t.check(sentence.has("w") and sentence.has("l"), "hello world has w and l")
	t.eq(LipSync.phonemes_from_text("", "en").size(), 0, "empty text has no phonemes")
	var shsh := LipSync.phonemes_from_text("ship", "en")
	t.eq(shsh[0], "sh", "sh digraph")

	t.current = "timeline"
	var tl := LipSync.timeline("mama mama", 2.0, "en")
	t.check(tl.size() >= 3, "timeline has keys")
	var first: Dictionary = tl[0]
	var last: Dictionary = tl[tl.size() - 1]
	t.near(float(first["time"]), 0.0, 0.0001, "timeline starts at 0")
	t.near(float(last["time"]), 2.0, 0.0001, "timeline spans duration")
	var mono := true
	var has_closed := false
	for i in range(1, tl.size()):
		var a: Dictionary = tl[i - 1]
		var b: Dictionary = tl[i]
		if float(b["time"]) <= float(a["time"]):
			mono = false
		if str(b["viseme"]) == "A":
			has_closed = true
	t.check(mono, "times strictly increase")
	t.check(has_closed, "mama timeline has closed-lips viseme")
	var ru_tl := LipSync.timeline("мама", 1.0, "ru")
	var ru_closed := false
	for k in ru_tl:
		var kd: Dictionary = k
		if str(kd["viseme"]) == "A":
			ru_closed = true
	t.check(ru_closed, "russian timeline has closed lips")
	var worst := 0.0
	var tt := 0.0
	while tt <= 2.0:
		var s := LipSync.sample(tl, tt)
		var sum := 0.0
		for key in s:
			sum += float(s[key])
		worst = maxf(worst, absf(sum - 1.0))
		tt += 0.013
	t.check(worst < 0.001, "coarticulated weights sum to 1")
	var mid := LipSync.sample(tl, (float(tl[1]["time"]) + float(tl[2]["time"])) * 0.5)
	t.check(mid.size() >= 1, "sample returns blended visemes")
	t.eq(LipSync.sample([], 0.5).get("X", 0.0), 1.0, "empty timeline rests")
	t.eq(LipSync.timeline("", 1.0).size(), 2, "empty text rests")

	t.current = "audio refinement"
	var sr := 1000
	var samples := PackedFloat32Array()
	for i in 500:
		samples.append(0.8 * sin(float(i) * 0.3))
	for i in 500:
		samples.append(0.0)
	var env := LipSync.amplitude_track(samples, sr, 0.02)
	t.eq(env.size(), 50, "one envelope value per hop")
	t.check(env[5] > 0.4 and env[5] < 0.7, "rms of loud half")
	t.check(env[40] < 0.0001, "silent half is flat")
	var refined := LipSync.refine_with_audio(LipSync.timeline("mama mama mama", 1.0, "en"), env, 0.02)
	var silent_ok := true
	var voiced := false
	for k in refined:
		var kd: Dictionary = k
		if float(kd["time"]) > 0.6 and str(kd["viseme"]) != "X":
			silent_ok = false
		if float(kd["time"]) < 0.4 and str(kd["viseme"]) != "X":
			voiced = true
	t.check(silent_ok, "silence becomes rest")
	t.check(voiced, "voiced part keeps visemes")
	var manual: Array = [
		{"time": 0.0, "viseme": "X", "weight": 1.0},
		{"time": 0.25, "viseme": "D", "weight": 1.0},
		{"time": 0.75, "viseme": "D", "weight": 1.0},
		{"time": 1.0, "viseme": "X", "weight": 1.0},
	]
	var loud_quiet := PackedFloat32Array()
	for i in 50:
		loud_quiet.append(1.0 if i < 25 else 0.4)
	var scaled := LipSync.refine_with_audio(manual, loud_quiet, 0.02)
	t.check(float(scaled[1]["weight"]) > float(scaled[2]["weight"]), "jaw opening scales with loudness")
	t.check(float(scaled[2]["weight"]) > 0.3, "quiet speech still opens")
	var all_silent := LipSync.refine_with_audio(manual, PackedFloat32Array([0.0, 0.0]), 0.5)
	t.eq(str(all_silent[1]["viseme"]), "X", "zero envelope rests")

	t.current = "facial graph"
	var fa := FacialAnimation.new(7)
	var fb := FacialAnimation.new(7)
	var fc := FacialAnimation.new(99)
	var first_blink := -1.0
	var blink_end := -1.0
	var n := 0.0
	var differs := false
	while n <= 6.5:
		var wa := fa.evaluate(n, "neutral", 0.0, {})
		var wb := fb.evaluate(n, "neutral", 0.0, {})
		var wc := fc.evaluate(n, "neutral", 0.0, {})
		if wa != wb:
			t.check(false, "same seed deterministic at %.2f" % n)
		if wa != wc:
			differs = true
		if float(wa.get("eyeBlinkLeft", 0.0)) > 0.05 and (first_blink < 0.0 or n - blink_end < 0.05):
			if first_blink < 0.0:
				first_blink = n
			blink_end = n
		n += 0.01
	t.check(differs, "different seed differs")
	t.check(first_blink > 0.0 and first_blink <= 6.0, "blink within 6 seconds")
	t.check(blink_end - first_blink < 0.4, "blink lasts under 0.4 s")
	t.check(blink_end - first_blink > 0.05, "blink has visible length")
	var peak := 0.0
	var m := first_blink
	while m < blink_end + 0.01:
		peak = maxf(peak, fa.blink_weight(m))
		m += 0.005
	t.check(peak > 0.9, "blink closes fully")
	t.eq(fa.blink_weight(-1.0), 0.0, "no blink before start")
	var gaze := fa.gaze_at(3.0)
	t.check(absf(gaze.x) <= 1.0 and absf(gaze.y) <= 1.0, "gaze in range")

	t.current = "emotion layering"
	var plain := FacialAnimation.new(3)
	plain.blink_enabled = false
	plain.saccades_enabled = false
	var happy := plain.evaluate(0.0, "happy", 1.0, {})
	t.check(float(happy["mouthSmileLeft"]) > 0.5, "happy smiles")
	var half := plain.evaluate(0.0, "happy", 0.5, {})
	t.near(float(half["mouthSmileLeft"]), float(happy["mouthSmileLeft"]) * 0.5, 0.001, "emotion weight scales pose")
	var over := plain.evaluate(0.0, "surprise", 5.0, {"D": 3.0, "F": 2.0})
	var clamped := true
	for key in over:
		if float(over[key]) < 0.0 or float(over[key]) > 1.0:
			clamped = false
	t.check(clamped, "weights clamped 0..1")
	t.eq(float(over["jawOpen"]), 1.0, "jaw saturates")
	t.eq(plain.evaluate(0.0, "nonsense", 1.0, {}).size(), 0, "unknown emotion is neutral")
	var speak := plain.evaluate(0.0, "neutral", 0.0, {"D": 1.0})
	t.near(float(speak["jawOpen"]), 0.85, 0.001, "viseme D opens jaw")
	plain.additive_pain = 1.0
	var pain := plain.evaluate(0.0, "neutral", 0.0, {})
	t.check(float(pain["eyeSquintLeft"]) > 0.5, "pain squints")
	plain.additive_pain = 0.0
	plain.additive_aggression = 1.0
	var aggro := plain.evaluate(0.0, "angry", 1.0, {})
	t.check(float(aggro["browDownLeft"]) == 1.0, "aggression plus anger clamps brows")
	var blinky := FacialAnimation.new(7)
	blinky.saccades_enabled = false
	var closed := blinky.evaluate(first_blink + 0.07, "happy", 1.0, {})
	t.check(float(closed["eyeBlinkLeft"]) > 0.9, "blink layers over emotion")

	t.current = "apply_to"
	var empty_mi := MeshInstance3D.new()
	t.eq(fa.apply_to(empty_mi, {"jawOpen": 0.5}), 0, "no mesh tolerated")
	empty_mi.mesh = BoxMesh.new()
	t.eq(fa.apply_to(empty_mi, {"jawOpen": 0.5, "nope": 1.0}), 0, "mesh without blend shapes tolerated")
	t.eq(fa.apply_to(null, {"jawOpen": 0.5}), 0, "null mesh instance tolerated")
	empty_mi.free()
	var am := ArrayMesh.new()
	am.add_blend_shape("jawOpen")
	var verts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var shape_arrays: Array = []
	var sa: Array = []
	sa.resize(Mesh.ARRAY_MAX)
	sa[Mesh.ARRAY_VERTEX] = verts
	shape_arrays.append(sa)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shape_arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	t.eq(fa.apply_to(mi, {"jawOpen": 2.0, "missing": 0.3}), 1, "present shape applied, missing ignored")
	t.near(mi.get_blend_shape_value(0), 1.0, 0.001, "applied value clamped")
	mi.free()
