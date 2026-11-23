extends RefCounted
## Virtual voices keep time while silent and resume at the right offset.

const AudioVirtualVoices = preload("res://scripts/client/audio_virtual_voices.gd")


func run(t) -> void:
	t.current = "audio virtualization"
	var bank := AudioVirtualVoices.new()
	t.check(not bank.add("shot", Vector3.ZERO, 0.0, 0.0, 0.4), "short one-shots are not virtualized")
	t.check(bank.add("siren", Vector3(40, 0, 0), -3.0, 10.0, 6.0), "long sound goes virtual")
	t.check(bank.add("horde", Vector3(5, 0, 0), -6.0, 11.0, 8.0), "second long sound goes virtual")
	var first: Dictionary = bank.promote(12.0, Vector3.ZERO)
	t.eq(first.get("name"), "horde", "the loudest for the listener is promoted first")
	t.near(float(first["offset"]), 1.0, 0.0001, "resumes where it would be now")
	t.eq(bank.promote(20.0, Vector3.ZERO), {}, "finished virtual voices expire")
	for i in AudioVirtualVoices.MAX_VIRTUAL + 5:
		bank.add("loop%d" % i, Vector3.ZERO, 0.0, 0.0, 30.0)
	t.eq(bank.voices.size(), AudioVirtualVoices.MAX_VIRTUAL, "the virtual bank is bounded")

	t.current = "virtual voices validate times and retain longest-running sounds"
	var protected := AudioVirtualVoices.new()
	t.check(not protected.add("", Vector3.ZERO, 0.0, 1.0, 4.0),
		"unnamed sound is rejected")
	t.check(not protected.add("badtime", Vector3.ZERO, 0.0, NAN, 4.0),
		"invalid time cannot enter the virtual queue")
	t.check(not protected.add("badvolume", Vector3.ZERO, INF, 1.0, 4.0),
		"invalid gain cannot poison voice priority")
	t.check(not protected.add("badpos", Vector3.INF, 0.0, 1.0, 4.0),
		"invalid source position cannot enter audio scene")
	t.check(protected.add("future", Vector3.ZERO, 0.0, 15.0, 6.0),
		"future-starting voice may be scheduled")
	t.eq(protected.promote(14.0, Vector3.ZERO), {},
		"scheduled voice is not played before its start")
	t.eq(protected.promote(NAN, Vector3.ZERO), {},
		"invalid playback time never consumes queued audio")
	t.eq(protected.promote(16.0, Vector3.INF), {},
		"invalid listener cannot consume queued audio")
	t.near(float(protected.promote(16.0, Vector3.ZERO)["offset"]), 1.0, 0.0001,
		"scheduled sound resumes at a valid position after its start")
	protected.add("ambience", Vector3.ZERO, -12.0, 0.0, 120.0)
	for i in AudioVirtualVoices.MAX_VIRTUAL - 1:
		protected.add("brief%d" % i, Vector3.ZERO, 0.0, 20.0, 2.0)
	protected.add("replacement", Vector3.ZERO, 0.0, 20.0, 3.0)
	var still_has_ambience := false
	var brief_count: int = 0
	for voice in protected.voices:
		if voice["name"] == "ambience":
			still_has_ambience = true
		if str(voice["name"]).begins_with("brief"):
			brief_count += 1
	t.check(still_has_ambience, "capacity pressure preserves long-lived ambience")
	t.eq(brief_count, AudioVirtualVoices.MAX_VIRTUAL - 2,
		"expired-soon virtual voice is evicted before long ambience")
