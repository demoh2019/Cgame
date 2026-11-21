# Cgame platform module

Native C++ ports of the runtime and tooling libraries that used to live in GDScript. The semantics follow the
GDScript versions; the classes are available to scripts through `ClassDB` like any other engine class.

| Class | Replaces | Purpose |
| --- | --- | --- |
| `CgamePlatformServices` | `scripts/shared/platform_services.gd` | Engine singleton: integrity-checked saves with backup recovery, achievements, presence, entitlements, controller pairing, suspend/resume, parental restrictions, text input. |
| `CgamePlatformBackend`, `CgameDesktopPlatformBackend`, `CgameMockPlatformBackend` | `Backend`, `DesktopBackend`, `MockConsoleBackend` | Backend contract, filesystem backend (atomic writes, hash envelope, backup, quota) and an in-memory console-style mock for tests. |
| `CgameSceneCRDT` | `scripts/tools/scene_crdt.gd` | Op-based scene CRDT: LWW registers, add-wins set, RGA child order, state vectors, presence. |
| `CgameAssetConflicts` | `scripts/tools/asset_conflicts.gd` | SHA-256 scans, three-way property merge, binary conflicts, exclusive locks with expiry, override conflicts. |
| `CgameGPUSettingsDB` | `scripts/client/gpu_settings_db.gd` | Regex adapter matching, learned JSON recommendations. |
| `CgameThermalGovernor` | `scripts/client/thermal_governor.gd` | FPS cap and quality step with hysteresis, battery drain estimate. |
| `CgameLatencyProbe` | statistics of `scripts/client/input_latency_probe.gd` | Input-to-photon samples, percentile report, photodiode pairing. No rendering or input capture. |
| `CgameGPUMatrixDB` | `scripts/tools/gpu_matrix_db.gd` | Report ingest, dHash, regressions, driver clustering, Markdown/CSV export, learned data. |
| `CgamePerfStats` | `PerfStats` of `scripts/client/perf_overlay.gd` | Ring buffers and percentiles. The overlay UI stays in GDScript. |
| `CgameSafeArea` | `scripts/client/ui_safe_area.gd` | Insets from the display safe area. |

## Platform services

`CgamePlatformServices` is registered as the engine singleton of the same name
(`Engine.get_singleton("CgamePlatformServices")`). It creates a `CgameDesktopPlatformBackend` below
`user://platform` on first use and attaches a helper node to the scene tree so
`NOTIFICATION_APPLICATION_PAUSED` / `NOTIFICATION_APPLICATION_RESUMED` suspend and resume the backend. Instances
created with `CgamePlatformServices.new()` stay independent; forward notifications to
`handle_notification()` yourself.

A save is written as `CGS1:<hash>:<json>`. The desktop backend writes `slot.tmp`, checks its size, moves the
previous `slot.sav` to `slot.bak` and renames the temporary file to `slot.sav`, so an interrupted write never
destroys the last good save. `load_game()` falls back to the backup when the main file is missing or fails the
hash check and reports the source. The hash is the engine's 32-bit `String.hash()`, the same as the GDScript
version, so existing saves remain readable; it detects accidental damage, not tampering.

New platforms add a C++ subclass of `CgamePlatformBackend`; the module contains no vendor SDK code.

## Facades

`game_facade/` (repository root) holds GDScript facades that use these classes when `ClassDB.class_exists()`
reports them and otherwise fall back to the original GDScript files. They contain no `class_name` and use
`preload`. Copy the folder to `res://game_facade/` of the game project.

## Tests

`tests/*.h` are doctest cases included by the engine test runner (`--test`, `TESTS_ENABLED`). They mirror the
GDScript tests: save atomicity and backup recovery, quota, sign-out, controller loss, suspend, CRDT convergence in
three delivery orders, three-way merge conflicts, locks, adapter matching, governor hysteresis, dHash distance,
driver clustering, percentiles and safe-area insets. Tests that need a `SceneTree` are tagged `[SceneTree]`.

## Known limits

- `CgameThermalGovernor.read_system_battery()` always reports unavailable: the engine has no battery API, feed
  readings to `record_battery()`.
- Backends cannot be subclassed from GDScript; port-specific backends are C++ classes.
- `CgameLatencyProbe` does not draw the flash rectangle or listen for input; the host calls `mark_input()` /
  `mark_draw()` and shows the rectangle while `is_flash_on()` is true.
