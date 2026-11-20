extends RefCounted
## After-rain drips timing.
const WetDrips = preload("res://scripts/client/wet_drips.gd")


func run(t) -> void:
	t.current = "drips after the rain stops"
	t.eq(WetDrips.next_soak(0.0, 0.8, false, 0.1), WetDrips.DRY_SECONDS, "rain soaks you")
	t.eq(WetDrips.drip_rate(60.0, 0.8, false), 0.0, "no separate drips while it pours")
	t.check(WetDrips.drip_rate(60.0, 0.0, false) > 0.9, "heavy dripping right after")
	t.check(WetDrips.drip_rate(30.0, 0.0, false) < 0.6, "thinning while drying")
	t.check(WetDrips.drip_rate(60.0, 0.8, true) > 0.9, "under cover the rain stops hitting you, drips start")
	t.near(WetDrips.next_soak(1.0, 0.0, false, 2.0), 0.0, 0.0001, "eventually dry")
