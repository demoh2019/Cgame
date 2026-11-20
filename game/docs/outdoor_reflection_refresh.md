# Weather-aware outdoor reflection captures (native Godot fork)

Albion After's outdoor probes already use box projection, a sky IBL fallback,
one/two nearby cubemaps on High/Ultra and `UPDATE_ONCE`, but their cached
reflections become stale while the player stands in one city through dawn,
dusk or a storm. This is especially visible on wet stone, metal and windows.

This update draws on Unity HDRP **On Demand** probe refresh and Unreal
Engine sky capture recapture / time slicing, while retaining Godot's
economical **UPDATE_ONCE** atlas, unlike `UPDATE_ALWAYS`.

**C++ Godot engine:** `ReflectionProbe.request_update()` sends an
immediate pair of rendering-server instance transforms: a temporary
tiny modified-basis transform followed by the **exact original**.
The RD scene culling backend marks the probe instance dirty on the
first differing transform and restores its actual transform before
the next scheduled capture. No node/world transform is moved, no atlas
resize and no continuous realtime capture mode. The method is a
no-op for detached, hidden and UPDATE_ALWAYS nodes.

**Game:** the existing global outdoor probe manager now receives the
actual shared `Atmosphere` instance created by online_main. It records
the daylight/storm snapshot when each site is first captured. After a
minimum 18-second pool-wide interval, it requests at most one recapture
if daylight changed by >=0.17 or the smoothed storm by >=0.26.
Small weather fluctuations cause no GPU work; an approaching evening
or heavy storm updates the existing local environment reflection.
The existing 1.6s site-switch cooldown remains, as do one/two-capture
High/Ultra and disabled low-tier/Mobile/Compatibility budgets.
No new probes, no new textures, no per-frame cubemap redraws, no server
state or gameplay changes. Stock Godot without the new fork method
keeps existing original one-shot behavior.

**Verification:** `res://tests/test_outdoor_reflection_refresh.gd`
is in both game/graphics suites; run after rebuilding the C++ fork:
`godot --headless --path game --script res://tests/run_graphics.gd`.
The scheduler tests are deterministic, but real rendered cube faces,
sunset transitions, GPU frame times and possible update hitches must be
checked on target hardware.
