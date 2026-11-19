extends RefCounted
## Stateless party-frame formatting regression, used by live network HUD.

const PartyFrames = preload("res://scripts/client/party_frames.gd")


func run(t) -> void:
	t.current = "party health display from authoritative roster"
	t.eq(PartyFrames.describe({}, 10), "", "solo player sees no distracting party overlay")
	t.eq(PartyFrames.describe({"id": 0, "roster": []}, 10), "",
			"empty party is hidden")
	t.eq(PartyFrames.describe({"id": 3, "roster": []}, 10), "",
			"unpopulated roster is hidden")
	var squad: Dictionary = {"id": 17, "leader": 10, "roster": [
		{"id": 10, "name": "Captain", "alive": true, "health": 76.9},
		{"id": 11, "name": "Medic", "alive": true, "health": 32.0},
		{"id": 12, "name": "Scout", "alive": false, "health": 0.0},
	]}
	var text_value: String = PartyFrames.describe(squad, 10)
	t.check(text_value.contains("PARTY  3/5"), "shows party size and cap")
	t.check(text_value.contains("Captain (you)"), "recognizes the local player")
	t.check(text_value.contains("★ Captain"), "highlights the server-selected leader")
	t.check(text_value.contains("76 HP"), "displays clamped authoritative health")
	t.check(text_value.contains("Medic  32 HP"), "live ally health appears while playing")
	t.check(text_value.contains("Scout  DOWN"), "dead allies are explicitly marked")
	t.eq(PartyFrames.describe(squad, 11).contains("Medic (you)"), true,
			"local identity changes without changing membership")

	t.current = "bounded and sanitized player-facing roster"
	var corrupt: Dictionary = {"id": 6, "leader": 99, "roster": []}
	for id in range(10):
		corrupt["roster"].append({"id": id, "name": "Name\n" + "x".repeat(100),
			"alive": true, "health": 150.0})
	var display: String = PartyFrames.describe(corrupt, 99)
	t.check(display.contains("PARTY  5/5"), "never renders more than five members")
	t.check(not display.contains("150 HP"), "health is capped at the visible maximum")
	t.check(display.contains("100 HP"), "oversized health gets clamped")
	t.check(not display.contains("\nxxxxxxxx"), "embedded user-name newlines are removed")
	t.check(not display.contains("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), "long names are truncated")
	var invalid: Dictionary = {"id": 5, "leader": 1, "roster": [
		{"id": 1, "name": "Survivor", "alive": true, "health": NAN}
	]}
	t.check(PartyFrames.describe(invalid, 1).contains("0 HP"),
			"nonfinite health cannot corrupt formatted UI")
	t.eq(PartyFrames.describe({"id": 7, "roster": "not a list"}, 1), "",
			"non-array roster is ignored")
