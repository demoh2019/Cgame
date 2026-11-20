# Light3D distance-fade and projector setter fast paths (Godot fork)

Albion After's streamed dungeon renderer updates its camera-nearest
torches about every 130 ms, but most light parameters are unchanged.
The Godot fork previously forwarded identical property writes to
RenderingServer and, for distance_fade_enabled, also refreshed the
property list even when nothing changed.

This optimization adds exact equality guards to C++ Light3D setters
for distance_fade_enabled, distance_fade_begin, distance_fade_shadow,
distance_fade_length, and light_projector. The renderer's default
values exactly match the corresponding Light3D defaults; the C++
constructor does **not** call these distance-fade or projector setters,
so initialization is preserved.

Do not use approximate float comparisons here: subtle but real artistic
parameter changes must still propagate. NaN assignments retain the old
behavior (NaN != NaN), rather than silently suppressing writes.
Existing Light3D::set_shadow(false) initialization is deliberately
left unchanged to avoid altering renderer creation behavior.

As an additional script-level saving, DungeonLightBudget checks values
before submitting the fixed fade properties to Godot, so GDScript
dispatch is also avoided for unchanged settings. This is global engine
code and benefits other OmniLight3D and SpotLight3D consumers, not just
our game. No public API or rendering appearance is changed.

API regression: res://tests/test_engine_light_fade_idempotence.gd
Run: godot --headless --path game --script res://tests/run_graphics.gd

The engine should be rebuilt and run on real hardware to confirm the
reduced setter overhead, visual continuity, and zero shadow regressions.
