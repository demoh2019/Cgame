# Storm cover: hide from eyesight, not from hearing

Real storms reduce infected's first **visual** detection range by 30% for exposed survivors. The existing night vigilance still applies, but hearing, blood scent, campfire glow, provoked threat, taunts and active pursuit remain fully functional. When the storm ends, normal eyesight returns automatically.

The server calculates this effect from its own world seed, weather cell and simulation clock. It reports a read-only `weather_sight` factor for the online HUD. The local offline HUD uses the same deterministic weather helper. Sensor input is bounded and malformed values cannot create full invisibility. Safe-hub shelter does not add a weather stealth bonus.

No save migration, networking command or native engine API is required. Execute `godot --headless --path game --script res://tests/run_all.gd` and see `test_storm_stealth.gd` for sight/sound/scent/firelight, chase continuity and server integration tests.
