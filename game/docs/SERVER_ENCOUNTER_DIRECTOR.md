# Серверный режиссёр столкновений / Server Encounter Director

This feature is live in the **canonical game** at `game/scripts/server/game_server.gd`,
not just the Visual Quality Lab demo.

## Why this exists

The earlier `WorldIncidents` generator created a random horde, guarded cache,
or screamer escort on a fixed interval and only considered the global 150
infected cap. A badly wounded player could receive another full wave while
20 infected were already clustered around them.

`scripts/shared/world_encounter_director.gd` adds a deterministic, bounded
control layer to the authoritative server:

1. Count **living infected only** within **75 meters** of the selected real
   survivor. Counting stops at 20, avoiding unnecessary work once saturated.
2. Calculate a spawn budget from local pressure, server-wide remaining slots,
   health fraction, and zone difficulty. Quiet zones can spawn 7–10 infected
   (subject to actual roster size); 8 nearby infected reduce new spawns to at
   most 4; 12 or more reduce them to 2; 20 or more cancel the attempt. A
   survivor below 30% HP receives at most 2 new incident enemies.
3. Build the usual seeded incident roster and **crop** it to the approved
   budget. The first special enemy (e.g. howler or cache guard) is preserved.
4. Increase post-incident recovery time by 20–75 seconds under heavy crowd
   pressure or low player health. Never shorten an existing incident cooldown.

Every decision is calculated **inside GameServer** from its actual zombies,
survivor vitals and world-zone data. There are no new client commands, no
client-controlled spawn rates, no additional network events and no changes to
the PvP, night-horde or caravan-ambush encounter systems. The module is a
standalone `RefCounted` pure gameplay/engine service, similar in *principle*
to encounter pacing systems used in more sophisticated engines, without
claiming to copy any engine's proprietary implementation.

## Run tests

The canonical Godot test entrypoint loads
`res://tests/test_world_encounter_director.gd` as part of all tests:

```bash
godot --headless --path game --script res://tests/run_all.gd
```

Test cases cover malformed inputs, zone caps, global cap, crowded areas,
low health, deterministic ordered roster trimming, cooldowns, near/dead
detection, and a real `GameServer._tick_world_incidents()` high-pressure
rejection with no fake broadcast events.

**Validation status:** headless Godot execution is not available from this
authoring environment (Godot is not installed; the authorized Mac is offline).
The source/test files and runner hookup can be statically inspected, but
this is **not** proof of green runtime tests or performance measurements.

Related reading:
- https://docs.godotengine.org/en/4.6/tutorials/best_practices/scenes_versus_scripts.html
- https://dev.epicgames.com/documentation/unreal-engine/gameplay-framework-in-unreal-engine
