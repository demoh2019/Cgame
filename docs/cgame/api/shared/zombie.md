# zombie.gd

> One zombie and its brain.

`res://scripts/shared/zombie.gd`

## Overview

One zombie and its brain. The brain is a small state machine: wander, chase the nearest player
it notices, attack when close, and give up when the player gets away.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const Threat = preload("res://scripts/shared/threat.gd")`
- `const EliteInfected = preload("res://scripts/shared/elite_infected.gd")`
- `const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")`
- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const WindHearing = preload("res://scripts/shared/wind_hearing.gd")`
- `const InfectedHearing = preload("res://scripts/shared/infected_hearing.gd")`
- `const SunderMark = preload("res://scripts/shared/sunder_mark.gd")`
- `const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")`
- `const InfectedResolve = preload("res://scripts/shared/infected_resolve.gd")`
- `const InfectedSight = preload("res://scripts/shared/infected_sight.gd")`
- `const InfectedMeleeCover = preload("res://scripts/shared/infected_melee_cover.gd")`
- `const NativeSenses = preload("res://scripts/shared/native_infected_senses.gd")`
- `const EffectRules = preload("res://scripts/shared/effect_application_rules.gd")`
- `const InfectedTargetUtility = preload("res://scripts/shared/infected_target_utility.gd")`
- `enum State { IDLE, WANDER, CHASE, ATTACK, DEAD, INVESTIGATE }`
- `const INVESTIGATE_SECONDS := 4.0`
- `const PACK_HOWL_COOLDOWN_SECONDS := 6.0`
- `const HUNTER_MEMORY_SECONDS := 6.0 # A hunter keeps coming this long after losing sight of you.`
- `const HUNTER_SEARCH_SECONDS := 10.0 # ...then searches where it last saw you.`
- `const TERRITORY_GRACE := 3.0`
- `const FLANK_FROM := 3.5 # Closer than this, an infected goes straight for its target.`
- `const FLANK_RANGE := 14.0`
- `const FLANK_RING := 2.4`
- `const FLANK_REPLAN_SECONDS := 0.30`
- `const FLANK_INCREMENTAL_STEP := 3 # Bootstrap cap for older native engines.`
- `const FLANK_EQS_TIME_BUDGET_US := 120 # Soft per-granted-query CPU time budget.`
- `const FLANK_EQS_MAX_CANDIDATES := 8 # Hard source-item safety cap for each step.`

## Functions

### `become_elite`

```gdscript
func become_elite() -> void
```

One-way transformation on server-created enemies. Never shared mutable stats.

### `enable_ai_profiling`

```gdscript
func enable_ai_profiling(enabled: bool) -> bool
```

Opt-in timing on the authoritative server. Disabled in ordinary gameplay.
Returns false on stock Godot when this fork's profiler is unavailable.

### `get_ai_profile_snapshot`

```gdscript
func get_ai_profile_snapshot() -> Dictionary
```

### `reset_ai_profile`

```gdscript
func reset_ai_profile() -> void
```

### `enable_ai_trace`

```gdscript
func enable_ai_trace(enabled: bool) -> bool
```

Opt-in trace of authoritative target selection. Source positions and target
choices must remain on the server. Unavailable on stock Godot.

### `get_ai_trace_snapshot`

```gdscript
func get_ai_trace_snapshot() -> Dictionary
```

### `reset_ai_trace`

```gdscript
func reset_ai_trace() -> void
```

### `get_ai_trace_history_frames`

```gdscript
func get_ai_trace_history_frames(changes_only: bool = false) -> Array
```

Replay data is private to server operators; never replicate player-related
trace decisions in public multiplayer snapshots.

### `get_ai_slowest_trace_nodes`

```gdscript
func get_ai_slowest_trace_nodes(limit: int = 8) -> Array
```

### `get_ai_state_visual_snapshot`

```gdscript
func get_ai_state_visual_snapshot() -> Dictionary
```

On-demand server-only visualization of the actual GDScript state machine.
Uses the same plain-data node layout as BehaviorTreeRunner.get_tree_snapshot()
without claiming that this state machine is a native BehaviorTree.

### `get_ai_debug_snapshot`

```gdscript
func get_ai_debug_snapshot() -> Dictionary
```

Server-side diagnostic query. Never include this in public game snapshots:
it exposes AI target identity and last perceived target locations.

### `is_alive`

```gdscript
func is_alive() -> bool
```

### `think`

```gdscript
func think(world, players: Dictionary, delta: float, rng: RandomNumberGenerator) -> Dictionary
```

Advances the brain. `players` maps peer id to {position: Vector3, alive: bool,
safe: bool, noise: float, scent: float, firelight: float}. Sound, scent and light are
server-owned sensory channels revealing noisy or wounded survivors.
Returns {"hit": peer_id, "damage": float} when the zombie lands a blow, else {}.

### `consume_howl`

```gdscript
func consume_howl() -> bool
```

True once when a howler has just spotted someone; the server wakes the pack around it.

### `force_taunt`

```gdscript
func force_taunt(peer_id: int, seconds: float) -> bool
```

Only the authoritative server calls this after checking the guardian's party,
weapon, distance, combat energy and cooldown.

### `receive_pack_alert`

```gdscript
func receive_pack_alert(peer_id: int, players: Dictionary) -> bool
```

Nearby infected share an already acquired target. Pack alerts never bypass
server-owned safe-zone, life, or leash checks and cannot overwrite active aggro.

### `investigate_decoy`

```gdscript
func investigate_decoy(site: Vector2) -> bool
```

An unattended infected may investigate a thrown clattering lure.
This never steals aggro from a real chase, raid boss or attacker.

### `set_passive_crowd_separation`

```gdscript
func set_passive_crowd_separation(value: Vector2) -> void
```

The server supplies bounded, already-sampled nearby-agent repulsion.
Malformed native output cannot steer an infected across the world.

### `apply_stagger`

```gdscript
func apply_stagger(seconds: float) -> bool
```

Confirmed crowd control gets weaker on repeated successful applications.
Failed attempts cannot build immunity, refresh timers or cancel acid windups.

### `apply_knockback`

```gdscript
func apply_knockback(world, attacker_position: Vector3, meters: float) -> float
```

Physical impulse from a real server-confirmed melee hit. Elites have
extra mass, bosses are immovable, and trap-rooted infected stay anchored.
This cannot move a player, and collision is resolved by shared movement.

### `apply_sunder`

```gdscript
func apply_sunder(now: float, seconds: float) -> bool
```

Debuff from an actual server-resolved axe hit. Refreshing cannot stack
magnitude or extend beyond a single duration from this point in time.

### `apply_snare`

```gdscript
func apply_snare(seconds: float) -> bool
```

Server-only trap application; cannot target a boss or expired/dead zombie.

### `take_damage`

```gdscript
func take_damage(amount: float, attacker_id: int = -1) -> bool
```

_7 private function(s) starting with `_` are not listed._
