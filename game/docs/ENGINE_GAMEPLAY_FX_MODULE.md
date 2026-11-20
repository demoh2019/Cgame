# Engine module: gameplay_fx

Status: **written, NOT YET COMPILED.** The module was authored statically (no scons run). Expect a possible compile-fix round on the next engine rebuild. The game scripts guard every use with `ClassDB.class_exists`, so the current stale editor binary runs unchanged.

Location: `modules/gameplay_fx/` (auto-picked up by the build; unit tests in `tests/test_gameplay_fx.h` are collected by `modules/SCsub` into `modules_tests.gen.h`, run with `--test --test-case="*GameplayFX*"`).

## Classes and engine equivalents

| Class | Base | Unreal | Unity |
|---|---|---|---|
| `SoundConcurrency` | Resource | Sound Concurrency asset (max count, resolution rule, volume scale, retrigger time) | none built in (usually hand-rolled AudioSource pools) |
| `SoundConcurrencyManager` | Node | Concurrency runtime in the audio engine | AudioMixer voice limit / custom pool |
| `RadialForceField3D` | Node3D | Chaos Radial Force / Field System Radial Falloff | `Rigidbody.AddExplosionForce` |

## SoundConcurrency

Properties: `max_count` (0 = unlimited, default 4), `resolution_rule` (STOP_OLDEST, STOP_FARTHEST, STOP_QUIETEST, PREVENT_NEW), `volume_scale` (gain multiplier per already-playing voice), `retrigger_interval` (seconds).

Static, node-free helpers (unit tested):
- `SoundConcurrency.pick_victim(start_msec, distances, volumes, rule, new_distance, new_volume) -> int` returns the voice index to stop, or `-1` meaning "reject the new sound" (PREVENT_NEW, or the new sound is itself the farthest/quietest).
- `SoundConcurrency.volume_scale_for(active_count, scale_per_voice) -> float` = `scale^active_count`.

## SoundConcurrencyManager

- `request_play(group: StringName, player: Node, position: Vector3, listener: Vector3) -> bool`: call before `play()`. Works with AudioStreamPlayer, 2D and 3D. On success victims were stopped, the player's `volume_db` is scaled (restored on release) and the slot auto-releases on `finished`. It does not call `play()` itself.
- `set_group_config / get_group_config / has_group_config / remove_group_config / clear_group_configs`, `default_concurrency` (8 voices, stop oldest).
- `release_player`, `get_active_count`, `stop_group`, `stop_all`.
- Signal `voice_stopped(player)`: emitted for players the manager stopped (these never emit `finished`), so the owner can free them.

## RadialForceField3D

Properties: `radius`, `strength` (impulse at center, negative pulls), `falloff` (NONE/LINEAR/QUADRATIC), `upward_bias`, `collision_mask`, `continuous` (strength = impulse per second, applied each physics frame), `affect_rigid_bodies`, `affect_physical_bones`, `free_after_fire`, `max_bodies`.

- `fire() -> int`: sphere `intersect_shape`, then `apply_central_impulse` on every RigidBody3D / PhysicalBone3D. The physics space is only queried in the physics frame: outside it, `fire()` defers to the next physics frame and returns 0. Signal `fired(affected_count)`.
- Static: `falloff_scale(distance, radius, mode)` (0..1), `impulse_direction(center, body_pos, upward_bias)`.

## How the game uses it

- `game/scripts/client/engine_features.gd`: `has(cls)`, `make(cls, props)`, `radial_push(parent, at, radius, strength, upward, mask)`. All engine-class access is via `ClassDB.instantiate` + `set`/`call`.
- `game/scripts/client/audio.gd` `play_at`: world one-shots call `request_play(sound_name, ...)` when `SoundConcurrencyManager` exists (groups: enemy_hurt 4, coin 3, blaster 4, blaster_repeater 4, break 3; stop farthest, 0.85 volume per extra voice). Victims are freed via `voice_stopped`. Without the class the existing `AudioVoices` limiter is the only gate.
- `game/scripts/client/online_main.gd`: `flash_thrown` and `barricade_broken` events spawn a `RadialForceField3D` on the ragdoll layer (`1 << 19`, see `ragdoll.gd`) that shoves ragdoll bones.

## Least-certain compile points

See the report accompanying the commit; main items: `callable_mp(...).bind(uint64_t)` usage, `LocalVector<PS3DT::ShapeResult>` (struct with a deprecated member), `Ref<SphereShape3D>` member in a header, `emit_signal` with a `Node *` argument, header include paths in this fork (`core/object/callable_mp.h`, `scene/resources/3d/world_3d.h`).
