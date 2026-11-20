# GPU-aware automatic resolution and half-resolution indirect light

Inspired by Unreal Engine TSR dynamic screen percentage and Unity URP/HDRP
dynamic resolution: the online Forward+ client now enables per-viewport Godot
GPU timing **only in Auto mode**. The 3D FSR2 render scale reacts to actual
measured GPU milliseconds rather than CPU frame deltas when the GPU reports
valid measurements. Process time remains a safe fallback if measurements are
unavailable (including renderer fallback and headless tests). This prevents
CPU-bound combat/network/streaming frames from needlessly blurring the world.

Automatic FSR2 keeps its current warmup, hysteresis, 0.04 down / 0.03 up
steps, per-tier floors, and its outer geometry/fog/shadow quality fallback.
The system never assumes that better frame-time figures equal GPU throughput.

The High/Ultra Forward+ presets now apply an explicit Godot Environment
contact-lighting budget (SSAO). Ultra also gets short-range SSIL diffuse
bounce with normal rejection to reduce leaks and angular streaks. Screen-
space reflection remains independently budgeted. The actual SSAO, SSIL and
SSR buffers use Godot's built-in **half resolution** project settings; no
new shader post pass, third-party dependency or server change is required.

Performance/Balanced have neither SSAO nor SSIL, and Compatibility/Mobile
never request those unsupported effects. Manual presets disable GPU timer
measurement; Auto re-enables it.

## Test

`godot --headless --path game --script res://tests/run_all.gd`

Tests cover CPU-bound versus GPU-bound decision logic, fallback to legacy
timing, invalid GPU timestamps, runtime lighting tier changes and renderer
compatibility. Actual FPS and GPU timing gains must be benchmarked on the
target hardware, not inferred from the deterministic tests.
