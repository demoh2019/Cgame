# Deterministic client prediction and server reconciliation (experimental)

Part of [roadmap issue #61](https://github.com/demoh2019/Cgame/issues/61):
- **#39 Client Prediction** — basic deterministic input-buffering and local prediction.
- **#40 Rollback/Reconciliation** — replacing an incorrect prediction with an authoritative server snapshot, then replaying later inputs.
- **#42 Multiplayer Debugger (foundation)** — reproducible simulated delay, packet loss, jitter and reordering for test packets (not integrated into the engine network debugger).

This is a reusable **GDScript reference component**, not yet native engine integration or a drop-in multiplayer framework. No transport or authority is bundled. It is intended to be copied into projects or used as a testable reference when implementing engine-level netcode. It does not modify existing Godot RPC or MultiplayerSynchronizer APIs.

## API

`prediction_buffer.gd` extends `RefCounted` and exposes:

- `initialize(initial_tick, initial_state, simulator, comparator=Callable())`
- `predict(next_tick, command)` returns `{ok, status, tick, replayed_steps}`
- `reconcile(authoritative_tick, authoritative_state)` returns `{ok, status, tick, replayed_steps}`
- `get_current_state()`, `get_state_at(tick)`, `get_buffered_command(tick)`
- `configure_history(limit)`, `get_history_limit()`, `get_current_tick()`, `get_earliest_tick()`, `reset()`

Status values include `predicted`, `matched`, `replayed`, `uninitialized`, `out_of_order`, `future_tick`, `stale_tick`, `invalid_command`, `invalid_authoritative_state`, `invalid_simulation_result`, `invalid_comparator_result`, and `missing_command`. A stale snapshot is **not silently accepted**: a caller must request full re-synchronization if it needs to correct a state outside history.

The simulation callable must be **pure/deterministic** from `(previous_state: Dictionary, input: Dictionary, tick: int) -> Dictionary`. It must not depend on wall-clock time, non-seeded randomness, non-deterministic physics, network state, or external mutable world state. The comparator, if supplied, must return a Boolean given two state dictionaries.

State and input dictionaries support nested value types, including numbers, strings, booleans, vectors, colors, arrays and dictionaries. Object, Callable, Signal and RID references are rejected; non-finite numeric values are rejected. Max nesting depth: 8, max elements per array/dictionary: 4096. Snapshot copies isolate state from caller mutation.

## Example client integration

```gdscript
const PredictionBuffer = preload("res://addons/network_prediction/prediction_buffer.gd")
var predictor = PredictionBuffer.new()

func simulate(previous: Dictionary, input: Dictionary, tick: int) -> Dictionary:
    var next := previous.duplicate(true)
    next["position"] += input["move"] * 0.016666667
    return next

func initialize() -> void:
    predictor.initialize(0, {"position": Vector2.ZERO}, Callable(self, "simulate"))

func local_fixed_tick(tick: int, move: Vector2) -> void:
    var command := {"move": move}
    var predicted := predictor.predict(tick, command)
    if not predicted["ok"]:
        return
    # Local client predicts immediately; the server independently validates inputs.
    submit_input_to_server.rpc_id(1, tick, command)
    # Apply predictor.get_current_state() to the local visual entity.

@rpc("any_peer", "call_remote", "reliable")
func submit_input_to_server(tick: int, command: Dictionary) -> void:
    # SERVER ONLY: check sender ID, ownership, tick bounds, input rate and values.
    # Simulate the server's authoritative state, then send a snapshot to that client.
    pass

@rpc("authority", "call_remote", "reliable")
func receive_authoritative(tick: int, state: Dictionary) -> void:
    var result := predictor.reconcile(tick, state)
    if result["status"] == "stale_tick":
        # Request a fresh full state snapshot from the trusted server.
        pass
```

Copy the source file from `misc/netcode/prediction_buffer.gd` to the same path as the example preload or adapt the preload path. The example contains stubs for authorization and server-side simulation: those methods are **not production-safe implementations**.

**Security:** RPC annotations are not a substitute for validating the sender's identity and ownership server-side. Reject forged positions and unreasonable command values; enforce maximum input rates and tick windows. Never trust the client's claimed simulation state.

**Physics caution:** the reference simulation avoids `move_and_slide()`, rigid-body physics, raycasts and real-time delta. If the gameplay simulation is non-deterministic or includes collisions, replay must use a deterministic simulation layer or an explicit reconciliation strategy. This code does not promise physics rewind or a rollback fighting-game engine.

## Deterministic network impairment queue

The independent `impairment_queue.gd` reference helper emulates the arrival timing of queued test packets without requiring real sockets.

```gdscript
const ImpairmentQueue = preload("res://impairment_queue.gd")
var net_test_queue = ImpairmentQueue.new()

func setup() -> void:
    net_test_queue.configure(120, 50, 0.1, 1234) # latency ms, jitter ms, loss rate, seed

func inject_outgoing_packet(packet: Dictionary, clock_ms: int) -> void:
    net_test_queue.schedule(packet, clock_ms)

func process_due_packets(clock_ms: int) -> void:
    for envelope in net_test_queue.poll_due(clock_ms):
        deliver_to_game(envelope["payload"])
```

This helper uses a caller-supplied millisecond clock, deterministic seed and stable ordering for equal deadlines. It exposes dropped/delivered/pending counts and rejects objects, nonfinite payload values and unreasonable configuration. It deliberately does **not** intercept the actual Godot MultiplayerPeer: the caller must decide how to apply simulated deliveries.

## Test

From a Godot 4.x executable:

```sh
godot --headless --path misc/netcode --script res://tests/run_tests.gd
```

This runs 43 regression cases (28 prediction/reconciliation and 15 impairment simulation) (including snapshots, rollback replay, mismatches, expiry, invalid data and atomic failure) and returns a nonzero exit code on failure. CI should invoke the same script. The suite is standalone and does not require a built Godot editor.

### Limitations and next increments

- No RPC transport, reliable/unreliable ordering layer or peer authorization. The impairment queue is a local test utility, not a real network packet interceptor.
- No tick clock synchronization, interpolation/extrapolation renderer, snapshot compression or bandwidth budget.
- Does not persist the buffer; all state is process-local.
- No replay of side effects (audio, particles, animation events); only state dictionaries.
- Bounded O(history) replay; max history is 2048 ticks to limit unbounded memory/time.
- Production network testing should exercise two or more real peers under delay, jitter, packet loss and reordering.
