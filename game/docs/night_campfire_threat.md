# Night campfires: warmth versus stealth

Survivors can warm themselves, cook and rest by a temporary field fire. At night the same burning fire reveals nearby survivors up to 30 m and lures idle infected within 26 m of the flames.

- `O` creates a fire after normal placement/fuel checks, `9` refuels and `-` extinguishes.
- Daylight, expiry and extinguishing stop new light detections and investigations.
- An unattended campfire creates a finite `INVESTIGATE` destination, never a fake player or damage event.
- Existing safe-zone, player-alive, combat threat, guardian taunt, raid boss, and pursuit leash rules all remain authoritative.
- Server-owned fire positions and world time drive the effect. Periodic spatial buckets avoid every-frame checks of all fires.
- No special engine API or save format changes are required.

Tests: `godot --headless --path game --script res://tests/run_all.gd`
