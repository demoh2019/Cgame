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
