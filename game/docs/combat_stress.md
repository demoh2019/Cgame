# PvE combat stress and squad composure

Infected actively chasing **you** within **22 m** raise short-lived
combat stress; idle or investigating infected, other survivors' enemies,
player PvP and distant threats do not. Elite infected and raid bosses
generate more pressure. The meter is a **private server-owned value**
from 0 to 100; it is not included in nearby player state or saved to
permanent character data.

- Solo chase: +5 stress per second per ordinary targeted pursuer;
  capped at 2.5 pressure units regardless of horde size.
- A living **party ally within 12 m** reduces incoming stress by 40%.
  Merely being near an unrelated survivor does not count.
- When the chase ends, stress decays at 2/s in open ground, 5/s in
  valid shared campfire/shelter coverage, and 10/s in a safe hub.
- Stress affects only natural stamina recovery (up to -40% at the cap).
  It does **not** reduce damage, sprint directly, combat energy,
  medical supplies, prepared meal buffs, party standards or skill XP.
- The existing full HUD indicates stress and its current recovery
  penalty when the meter exceeds 10. No new client RPC or trusted
  client-submitted combat data is required.
- The server samples actual hostile targeting every 0.5 seconds, and
  wipes stress on death/respawn; session-only stress does not outlive
  disconnect. The system cannot duplicate loot or permanent progress.

Only Godot game-layer scripts are needed; the forked engine is unchanged.

Regression: `game/tests/test_combat_stress.gd` is registered in
`game/tests/run_all.gd`. Run:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
