# Cgame Server (native MMO server infrastructure)

This optional built-in module ports the GDScript MMO server infrastructure of the game (`game/scripts/server/*.gd`) to native C++ with the same APIs, semantics and determinism. It is meant for dedicated servers that run these components on hot paths and from several threads.

All classes are `RefCounted`. Data is kept in `Dictionary`/`Array` values exactly as in the scripts, so records can be inspected from GDScript and survive a JSON round trip.

| Class | Purpose |
| --- | --- |
| `CgameTransactionCoordinator` | Two-phase commit with presumed abort, durable decision log (temp file + atomic rename), `recover()`, participants as `Callable`s, persistent price-time order book. Mutex-guarded. |
| `CgameItemLedger` | Per-server item ledger acting as a 2PC participant; unique ids, exactly-once moves, duplicate detection / quarantine / resolution. |
| `CgameWorldSharding` | Region-to-server assignment (greedy LPT), hysteresis rebalancing, border ghosts, idempotent four-step player handoff. |
| `CgameGuildSync` | Replicated guild documents: Lamport-timestamped op log, order-independent conflict policy, anti-entropy with version vectors. |
| `CgamePartyMigration` | Party directory whose authority follows the leader; epoch fencing against stale homes. |
| `CgameOwnershipLeases`, `CgameFencedStore` | Expiring leases with monotonic fencing tokens and the protected store that rejects stale writers. |
| `CgameClusterSimulator` | Seeded in-process cluster with latency, reordering, server and coordinator crashes, and invariant checks. Draws from `RandomNumberGenerator` in the same order as the script, so runs are reproducible. |
| `CgameTradeJournal` | Redo log for two-account deals (after-images fsynced before the backend commit), supersede / replay planning. Mutex-guarded. |
| `CgameLagCompensation` | Position history and capped rewind for PvP hit detection. |
| `CgameReplayRecorder` | Record, save, load and replay sessions with per-tick FNV-1a state hashes; only `cmd_*` and `submit_input` are recorded or called (via `Object::callv`). |
| `CgameSaveMigrations` | Versioned single-step save migrations with gap/downgrade refusal and round-trip verification. |

## Differences from the scripts

- Constructors take no arguments: set `server_id`, `seed_value` etc. after `new()`. The `game_facade/*.gd` scripts provide `create(...)` helpers that prefer the native class (`ClassDB.class_exists`) and fall back to `res://scripts/server/*.gd`.
- Nested classes become top-level: `OwnershipLeases.FencedStore` is `CgameFencedStore`.
- Float constants are exposed as static getters (`CgameLagCompensation.get_max_rewind()`); `ReplayRecorder.load` is bound as `load` and implemented as `load_replay`.
- `CgameReplayRecorder.play()` takes an optional `hash_fn` because the game-specific state projection lives in the game: `hash_fn(server)` returns an `int` (used as-is) or any value (hashed with `hash_variant`). Without it the server's `capture_state()` is hashed.
- `CgameClusterSimulator` exposes its collaborators (`coordinator`, `sharding`, `leases`, `fenced`, `rng`) as read-only properties.

## Tests

`tests/test_cgame_server_distribution.h` (2PC commit/abort/recover exactly once, order book, sharding, ledger, guild convergence, party fencing, leases, balancing, seeded fault runs with item conservation) and `tests/test_cgame_server_netcode.h` (trade journal supersede/replay, rewind interpolation, replay determinism and whitelist, migrations chain) mirror `tests/test_server_distribution.gd`, `test_cross_server.gd`, `test_netcode_reliability.gd` and `test_replay_migrations.gd`. They are picked up by Godot's generated module-test list:

```sh
./bin/godot.macos.editor.arm64 --test --test-case="*Cgame*"
```
