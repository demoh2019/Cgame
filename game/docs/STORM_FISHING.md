# Storm fishing

**New optional cast:** Only near a shoreline in full-loot red/black zones
during a real server-calculated storm. Casting takes **8 seconds**, versus
normal fishing's 5. On successful completion it awards **2 extra fish** on top
of a regular 1–2 catch, provided all fish fit in the backpack. The existing
zone, rod and profession limits still determine the catch's tier.

Moving away, losing the rod, or the storm ending cancels the cast before any
loot is created. Baited and storm modes are mutually exclusive. The server
sets weather, zone, cast timer, random rewards and gathering XP.

Online: inventory -> **Storm cast (red/black coast)**.
Offline: **Alt + fishing key**; Shift + fishing key remains baited casting.

Run: godot --headless --path game --script res://tests/run_all.gd
