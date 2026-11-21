# infected_hearing.gd

> (no header comment)

`res://scripts/shared/infected_hearing.gd`

## Constants

- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")` - Authoritative acoustic cover. Sound already has a server-issued radius and wind direction; nearby walls attenuate first passive acquisition only. Reuses bullet/vision broadphase, never client physics or replicated targets.
- `const QUIET_REFERENCE := 21.0`
- `const LOUD_REFERENCE := 32.0`
- `const QUIET_TRANSMISSION := 0.62`
- `const LOUD_TRANSMISSION := 0.80`
- `const END_TOLERANCE := 0.08`
- `const ACOUSTIC_MIN_RADIUS := 1.1`

## Functions

### `attenuation_radius`

```gdscript
static func attenuation_radius(source_radius: float, wind_radius: float, blocked: bool) -> float
```

Pure GDScript reference matches the optional native SoundPropagation
engine module. Even gunshots cannot exceed the original wind/leash radius.

### `audible`

```gdscript
static func audible(world, source: Vector3, listener: Vector3, source_radius: float, wind_radius: float) -> bool
```

One broadphase ray only for marginal acoustic acquisition. At close
range cover still permits hearing, farther than unobstructed sound no
ray is necessary. Vision/scent/pack alerts have separate semantics.

