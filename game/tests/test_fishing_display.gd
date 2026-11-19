extends RefCounted
## Fishing HUD uses the exact same server state on both playable clients.

const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
	t.current = "server-owned fishing progress"
	t.eq(FishingDisplay.progress({}), "", "no fishing action means no casting label")
	t.eq(FishingDisplay.progress({"node": 5, "remaining": 1.0}), "",
		"gathering does not display fishing progress")
	for tier in range(1, Defs.MAX_TIER + 1):
		var item_id: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
		var action := {"fish": true, "catch_id": item_id, "total": 5.0, "remaining": 2.3}
		var label: String = FishingDisplay.progress(action)
		t.check(str(Defs.item(item_id)["name"]) in label,
			"the actual T%d fish name is displayed" % tier)
		t.check("2.3s remaining" in label, "remaining server time shown")
		t.check("moving cancels" in label, "player learns the cast is interruptible")
		t.eq(float(action["remaining"]), 2.3, "UI never modifies authoritative timer")
	t.current = "bad presentation input is bounded"
	t.check("0.0s remaining" in FishingDisplay.progress({
		"fish": true, "catch_id": "raw_fish", "total": 5.0, "remaining": -10.0
	}), "negative time is clamped")
	t.check("5.0s remaining" in FishingDisplay.progress({
		"fish": true, "catch_id": "raw_fish", "total": 5.0, "remaining": 10000.0
	}), "remaining time is limited by cast duration")
	t.check("0.0s remaining" in FishingDisplay.progress({
		"fish": true, "catch_id": "raw_fish", "total": 5.0, "remaining": NAN
	}), "nonfinite status cannot leak to the HUD")
