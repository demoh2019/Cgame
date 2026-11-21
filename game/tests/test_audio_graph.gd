extends RefCounted
## Procedural audio graph: oscillators, envelopes, filters, delay, validation, presets, WAV, cache.

const AudioGraph = preload("res://scripts/client/audio_graph.gd")
const ProceduralSounds = preload("res://scripts/client/procedural_sounds.gd")

const SR := 22050


func _single(def: Dictionary) -> Dictionary:
	return {"nodes": {"o": def}, "connections": [], "output": "o"}


func _energy(s: PackedFloat32Array, from: int = 0, to: int = -1) -> float:
	var end := s.size() if to < 0 else mini(to, s.size())
	var e := 0.0
	for i in range(from, end):
		e += s[i] * s[i]
	return e


func run(t) -> void:
	t.current = "oscillators"
	var sine := AudioGraph.render(_single({"type": "sine", "freq": 440.0}), 0.5, SR, 0)
	var crossings := 0
	for i in range(1, sine.size()):
		if sine[i - 1] < 0.0 and sine[i] >= 0.0:
			crossings += 1
	t.check(absi(crossings - 220) <= 2, "sine 440 Hz crosses zero upward ~220 times in 0.5 s (got %d)" % crossings)
	t.eq(sine.size(), SR / 2, "render length is seconds * rate")
	for type in ["saw", "square", "triangle"]:
		var s := AudioGraph.render(_single({"type": type, "freq": 220.0}), 0.1, SR, 0)
		t.check(_energy(s) > 1.0, "%s oscillator produces signal" % type)

	t.current = "envelopes"
	var adsr_graph := _single({"type": "adsr", "attack": 0.1, "decay": 0.1, "sustain": 0.5, "gate": 0.5, "release": 0.2})
	var env := AudioGraph.render(adsr_graph, 1.0, SR, 0)
	t.near(env[int(0.05 * SR)], 0.5, 0.03, "attack ramps linearly")
	t.near(env[int(0.1 * SR) + 20], 1.0, 0.03, "attack peaks at 1")
	t.near(env[int(0.35 * SR)], 0.5, 0.01, "sustain holds")
	t.check(env[int(0.6 * SR)] < 0.3 and env[int(0.6 * SR)] > 0.0, "release is falling")
	t.eq(env[int(0.9 * SR)], 0.0, "envelope ends at zero")
	var ar := AudioGraph.render(_single({"type": "ar", "attack": 0.05, "release": 0.1}), 0.3, SR, 0)
	t.near(ar[int(0.05 * SR) + 20], 1.0, 0.05, "AR peaks after attack")
	t.eq(ar[ar.size() - 1], 0.0, "AR decays to zero")

	t.current = "filters"
	var noise_only := {"nodes": {"n": {"type": "noise_white"}}, "connections": [], "output": "n"}
	var raw := AudioGraph.render(noise_only, 0.3, SR, 5)
	var lp_graph := {
		"nodes": {"n": {"type": "noise_white"}, "f": {"type": "lowpass", "cutoff": 400.0}},
		"connections": [["n", "f", "in"]], "output": "f",
	}
	var lp := AudioGraph.render(lp_graph, 0.3, SR, 5)
	t.check(_energy(lp) < 0.1 * _energy(raw), "lowpass removes most white-noise energy")
	var hp_graph := {
		"nodes": {"n": {"type": "noise_white"}, "f": {"type": "highpass", "cutoff": 8000.0}},
		"connections": [["n", "f", "in"]], "output": "f",
	}
	t.check(_energy(AudioGraph.render(hp_graph, 0.3, SR, 5)) < 0.4 * _energy(raw), "highpass attenuates noise")
	var low_sine := {
		"nodes": {"s": {"type": "sine", "freq": 200.0}, "f": {"type": "lowpass", "cutoff": 3000.0}},
		"connections": [["s", "f", "in"]], "output": "f",
	}
	var through := AudioGraph.render(low_sine, 0.2, SR, 0)
	t.check(_energy(through, 2000) > 0.4 * _energy(AudioGraph.render(_single({"type": "sine", "freq": 200.0}), 0.2, SR, 0), 2000),
		"lowpass passes a low sine")

	t.current = "modulation"
	var mod_graph := {
		"nodes": {
			"n": {"type": "noise_white"}, "e": {"type": "ar", "attack": 0.01, "release": 0.05},
			"k": {"type": "gain", "gain": 4000.0}, "f": {"type": "lowpass", "cutoff": 200.0},
		},
		"connections": [["n", "f", "in"], ["e", "k", "in"], ["k", "f", "cutoff_mod"]], "output": "f",
	}
	var swept := AudioGraph.render(mod_graph, 0.4, SR, 3)
	t.check(_energy(swept, 100, 2000) > 3.0 * _energy(swept, 6000, 7900), "envelope opens the filter cutoff")
	var am := {
		"nodes": {"a": {"type": "sine", "freq": 300.0}, "b": {"type": "const", "value": 0.0}, "m": {"type": "multiply"}},
		"connections": [["a", "m", "a"], ["b", "m", "b"]], "output": "m",
	}
	t.eq(_energy(AudioGraph.render(am, 0.05, SR, 0)), 0.0, "multiply by zero silences")

	t.current = "delay"
	var echo_graph := {
		"nodes": {"e": {"type": "ar", "attack": 0.001, "release": 0.003}, "d": {"type": "delay", "time": 0.1, "feedback": 0.0}},
		"connections": [["e", "d", "in"]], "output": "d",
	}
	var echo := AudioGraph.render(echo_graph, 0.3, SR, 0)
	var peak_at := 0
	var peak := 0.0
	for i in echo.size():
		if absf(echo[i]) > peak:
			peak = absf(echo[i])
			peak_at = i
	t.check(peak > 0.9, "echo repeats the blip at full level")
	t.check(absf(float(peak_at) / SR - 0.101) < 0.006, "echo lands one delay time later (at %.4f s)" % [float(peak_at) / SR])
	t.eq(_energy(echo, 0, int(0.09 * SR)), 0.0, "nothing before the first echo")
	var loop_graph := {
		"nodes": {
			"e": {"type": "ar", "attack": 0.001, "release": 0.003}, "mix": {"type": "mixer"},
			"d": {"type": "delay", "time": 0.05, "feedback": 0.0}, "g": {"type": "gain", "gain": 0.6},
		},
		"connections": [["e", "mix", "in"], ["mix", "d", "in"], ["d", "g", "in"], ["g", "mix", "in"]], "output": "mix",
	}
	t.eq(AudioGraph.validate(loop_graph).size(), 0, "a cycle through a delay is allowed")
	var loop := AudioGraph.render(loop_graph, 0.3, SR, 0)
	t.check(absf(loop[int(0.05 * SR) + 22]) > 0.1 and absf(loop[int(0.1 * SR) + 44]) > 0.05, "feedback loop produces repeating echoes")

	t.current = "validation"
	var cyc := {
		"nodes": {"a": {"type": "gain"}, "b": {"type": "gain"}},
		"connections": [["a", "b", "in"], ["b", "a", "in"]], "output": "a",
	}
	var errs := AudioGraph.validate(cyc)
	t.check(errs.size() > 0 and "cycle" in errs[0], "cycle without delay is rejected")
	t.eq(AudioGraph.render(cyc, 0.1, SR, 0).size(), 0, "rejected graph renders nothing")
	t.check(AudioGraph.last_errors.size() > 0, "errors are kept for the debugger")
	t.check(AudioGraph.validate({"nodes": {"a": {"type": "bogus"}}, "connections": [], "output": "a"}).size() > 0, "unknown type reported")
	t.check(AudioGraph.validate({"nodes": {"a": {"type": "sine"}}, "connections": [["a", "zz", "in"]], "output": "a"}).size() > 0, "dangling connection reported")
	t.check(AudioGraph.validate({"nodes": {"a": {"type": "sine"}}, "connections": [], "output": "nope"}).size() > 0, "missing output reported")

	t.current = "determinism and range"
	var a := AudioGraph.render(noise_only, 0.1, SR, 42)
	var b := AudioGraph.render(noise_only, 0.1, SR, 42)
	var c := AudioGraph.render(noise_only, 0.1, SR, 43)
	t.check(a == b, "same seed renders identical samples")
	t.check(a != c, "different seed changes noise")
	var loud := {
		"nodes": {"n": {"type": "noise_white"}, "g": {"type": "gain", "gain": 50.0}, "d": {"type": "clip", "drive": 30.0}},
		"connections": [["n", "g", "in"], ["g", "d", "in"]], "output": "g",
	}
	var ok := true
	for v in AudioGraph.render(loud, 0.1, SR, 1):
		if not is_finite(v) or v < -1.0 or v > 1.0:
			ok = false
	t.check(ok, "output is clamped into [-1, 1]")

	t.current = "wav"
	var wav := AudioGraph.to_wav(sine, SR)
	t.eq(wav.format, AudioStreamWAV.FORMAT_16_BITS, "16-bit format")
	t.eq(wav.mix_rate, SR, "mix rate kept")
	t.eq(wav.stereo, false, "mono")
	t.eq(wav.data.size(), sine.size() * 2, "two bytes per sample")
	t.near(wav.get_length(), 0.5, 0.01, "stream length in seconds")

	t.current = "profile"
	AudioGraph.render(lp_graph, 0.1, SR, 0)
	t.eq(AudioGraph.last_profile.size(), 2, "one profile entry per evaluated node")
	var entry: Dictionary = AudioGraph.last_profile["f"] as Dictionary
	t.check(int(entry["calls"]) > 0 and int(entry["usec"]) >= 0 and str(entry["type"]) == "lowpass", "entry carries calls, usec and type")
	var report := AudioGraph.profile_report()
	t.eq(report.size(), 2, "profile report lists nodes")
	t.check(int(report[0]["usec"]) >= int(report[1]["usec"]), "profile report sorted by cost")
	t.check(AudioGraph.last_total_usec > 0, "total render time recorded")

	t.current = "presets"
	ProceduralSounds.clear_cache()
	var cases: Array = [
		["footstep", ["gravel"]], ["footstep", ["grass"]], ["footstep", ["wood"]], ["footstep", ["metal"]],
		["zombie_groan", []], ["wind", [0.8]], ["fire_crackle", []],
		["gunshot", ["9mm"]], ["gunshot", ["12ga"]], ["ui_click", []],
	]
	for case in cases:
		var label := "%s %s" % [case[0], str(case[1])]
		var graph := ProceduralSounds.graph_for(str(case[0]), case[1] as Array, 7)
		t.eq(AudioGraph.validate(graph).size(), 0, "%s graph is valid" % label)
		var s := AudioGraph.render(graph, float(graph["duration"]), SR, 7)
		var finite := true
		var peak_abs := 0.0
		for v in s:
			if not is_finite(v) or absf(v) > 1.0:
				finite = false
			peak_abs = maxf(peak_abs, absf(v))
		t.check(finite and s.size() > 0, "%s renders finite audio" % label)
		t.check(peak_abs > 0.05 and _energy(s) / maxf(float(s.size()), 1.0) > 1e-5, "%s is not silent (peak %.3f)" % [label, peak_abs])

	t.current = "preset cache"
	ProceduralSounds.clear_cache()
	var first := ProceduralSounds.bake("footstep", ["wood"], 1)
	var second := ProceduralSounds.bake("footstep", ["wood"], 1)
	t.check(first != null and first == second, "second bake returns the cached stream")
	t.eq(ProceduralSounds.cache_hits, 1, "one cache hit")
	t.eq(ProceduralSounds.cache_misses, 1, "one cache miss")
	t.check(ProceduralSounds.bake("footstep", ["wood"], 2) != first, "different seed is a different entry")
	t.eq(ProceduralSounds.bake("nope", [], 0), null, "unknown sound yields null")
	for i in ProceduralSounds.CACHE_LIMIT + 4:
		ProceduralSounds.bake("ui_click", [], 100 + i)
	t.check(ProceduralSounds.cache_size() <= ProceduralSounds.CACHE_LIMIT, "cache is bounded")
	ProceduralSounds.clear_cache()
