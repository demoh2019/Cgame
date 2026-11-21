# Native Cgame AI threat / aggro arbitration

This PR adds `AIThreatTable2D`, a native `RefCounted` engine utility that
encapsulates the existing bounded MMORPG-style threat table arithmetic
for repeated use in AI-controlled guards, infected, raid minions and bosses.

Design references: Unreal Engine's Gameplay Targeting System and Ability
System decouple target arbitration and game-authoritative gameplay effects:
- https://dev.epicgames.com/documentation/unreal-engine/gameplay-targeting-system-in-unreal-engine
- https://dev.epicgames.com/documentation/unreal-engine/gameplay-ability-system-for-unreal-engine

It is **not** a replacement for GAS, combat damage validation, perception,
physics queries, networking, or a behavior tree. It does not automatically
accept any client-provided target or threat value.

## Engine API

```gdscript
var tracker := AIThreatTable2D.new()
var hate: Dictionary = {} # belongs to the AI agent, not the tracker
tracker.record(hate, attacker_peer_id, confirmed_server_damage)
tracker.decay(hate, delta)
var aggro := tracker.pick(hate, server_players, enemy_xz, pursuit_leash, current_peer_id)
```

- Up to five tracked peer IDs in normal operation, max 10000 points per
  player, decay 0.75 points/second, and a 1.25 hysteresis ratio for
  target switches.
- Eviction requires strictly greater threat than the weakest entry.
  Score ties resolve to the lowest peer ID for stable server replay
  regardless of insertion order. The current target is retained when
  another player has the same or insufficiently higher score.
- `pick()` erases dead players, safe-zone entrants, disconnected IDs,
  invalid positions and actors outside the pursuit leash. Invalid
  selector origin/leash returns no target without mutating the table.
- `Dictionary` entries remain owned by the game NPC. This class
  contains no shared mutable per-agent state and does not serialize hate.

## Canonical Albion After integration

`game/scripts/shared/threat.gd` now negotiates `AIThreatTable2D` once.
Its existing `Threat.record/decay/pick` interface, call sites and
`MAX_TARGETS`, `MAX_VALUE`, `DECAY_PER_SECOND`, `SWITCH_MARGIN`
constants are unchanged. The fallback GDScript logic still runs on stock
Godot and uses the same deterministic tie rules.

`Zombie.take_damage()` and server-authorized healing aggro are the only
producers of recorded combat threat. The game remains responsible for
verification that an actual hit/heal occurred, so **never** expose
`AIThreatTable2D.record` directly through client commands or RPCs.
No authoritative values are trusted from regular multiplayer clients.
The debug snapshot reports only native capability and stays server-only.

## Tests / operational validation

Native `tests/test_ai_threat_table_2d.h` covers bounded tables,
score cap, expiry, stable target ties, switch hysteresis, safe-zone
filtering, invalid positions and rollback on invalid query input.
Game `tests/test_threat_aggro.gd` retains all existing authoritative
combat and healer rules plus native/fallback parity and deterministic
tie regressions; `run_all.gd` already registers it.

The accompanying CI compiles the native engine, runs focused C++ tests
and the canonical game's headless regression suite. The merge itself
cannot substitute for a successful native build/test run.
