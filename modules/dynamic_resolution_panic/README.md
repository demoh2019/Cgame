# Dynamic Resolution GPU Panic

Unreal Engine's Dynamic Resolution heuristic has an over-budget panic
response after consecutive expensive GPU frames, with an explicit
minimum change interval to avoid thrashing render targets. Albion After
previously took 2.2 seconds to lower render resolution; a sustained
expensive effect or a GPU-heavy camera cut could remain stuttery.

The new reusable C++ DynamicResolutionPanicPolicy API calculates a
bounded scale using current scale, floor, GPU frame time, target time,
consecutive overbudget count, and required consecutive count.

- No side effects: no RenderingServer, GPU API, stateful clock or scene calls.
- Three actual expensive GPU samples are needed (38 ms or 1.75x target).
- Max linear-scale drop 0.12 per panic; a 550 ms game-side cooldown
  prevents rapid repeated render-target resizing.
- Never crosses a device floor such as MetalFX minimum.
- Invalid values fail closed (return -1), zero/unavailable GPU samples
  do nothing. CPU frame deltas never satisfy the emergency condition.
- The scale model assumes rendered pixel area grows quadratically with
  linear resolution, but never promises a proportional GPU speedup.
- GDScript equivalent is always available for stock Godot / old binaries.
- Preset changes reset streaks and cooldown; original slow hysteresis
  and outer graphics quality-tier controller remain active.
- Albion After already obtains native viewport GPU measurements and
  applies viewport scaling via GraphicsQuality.apply_resolution.

Validation: C++ native doctests, script/native parity, short spikes,
high GPU loads, CPU-bound scenes, cooldown, preset reset and device floors.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/dynamic-resolution-in-unreal-engine
