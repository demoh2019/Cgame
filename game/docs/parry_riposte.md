# Server-confirmed melee riposte against infected

Timed melee parry (F8) now rewards a successful defense with a classless PvE counter. The server creates a **2.25 s** opening only when an actual, living, non-boss infected strikes an active, front-facing parry with a physically owned melee weapon.

The first ordinary attack during that opening consumes the opportunity even on a miss. If it lands on **the same infected** with **the same equipped melee weapon**, it deals **+40% damage**. Normal reach, angle, PvP targeting and other combat permission checks remain intact. Ripostes are incompatible with random critical damage stacking and stealth-ambush multiplication.

No riposte occurs from merely pressing F8, being hit from behind, parrying a boss, shooting, switching to another weapon, dodging or attacking a player. Damage and hit confirmation are always resolved by the server. The opportunity is transient and owner-private, never stored in character saves; death, respawn and disconnection remove it. A HUD timer and a success notification reuse existing snapshots and attack-result RPCs.

Regression suite: `game/tests/test_parry_riposte.gd` in `game/tests/run_all.gd`. No Godot core modification was necessary.
