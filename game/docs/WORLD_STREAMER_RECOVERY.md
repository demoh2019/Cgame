# Native WorldStreamer: bounded recovery (Albion After)

The custom **Cgame C++ engine** now supports bounded automatic retry for
transient WorldStreamer chunk failures. The canonical Albion After client
in `game/scripts/client/online_main.gd` opts in; default Godot behavior is unchanged.

## Why this exists

A temporarily failed threaded scene request, a failed generator call, or a
generator that returns the wrong type no longer leaves a hole in the world
forever. A `null` generator result still means **intentionally empty cell**
and is never retried. An absent scene path is likewise not retried.

## Native API

- `max_auto_retries`: 0 (default, disabled) through 8 *extra* attempts.
- `retry_initial_delay`: first delay in seconds; at least 0.01 s.
- `retry_max_delay`: cap on delay; at most 60 s.
- `get_retry_pending_count()`: number of cells waiting for retry.

The delay sequence is `min(retry_max_delay, retry_initial_delay * 2^n)`.
Retries reenter **the existing** generation or threaded request queue and use
the same `max_instantiations_per_frame`, `max_chunk_work_usec`, and
`max_concurrent_loads` budgets; no second unbounded processing loop exists.

After exhausting the attempt budget, the cell remains failed until
`refresh(true)` or until it leaves the streaming unload radius. The
recovery history is also cleared when the streamer is reset or changes
chunk provider/generator/path, and is cleared on successful activation.

Albion After enables two automatic retries at 0.5 s and 1.0 s (capped at
3.0 s), with a visible pending counter in the diagnostics HUD. It does not
alter authoritative game rules, player saves, or multiplayer messages.

## Verification

Rebuild Cgame first. Then run:

```sh
python3 -m unittest tests/scene/test_world_streamer_retry_contract.py -v
godot --headless --path game --script res://tests/run_all.gd
```

The GDScript test simulates transient invalid generator values, exhausted
retry budgets, and intentionally empty chunks. The Python source checks alone
**do not** prove engine compilation or runtime correctness.

This feature follows the engine's existing bounded streaming model and
the general fault-tolerant streaming practices used in large-world engines.
