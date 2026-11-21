# Priority-aware Gameplay Cue admission (Niagara-inspired)

The native Cgame `GameplayCueQueue` has a bounded 128-event backlog. This
extension preserves important combat feedback when low-priority cosmetic
events have already filled it. Unreal Engine Niagara Effect Types provide
similar significance-oriented scalability and budget culling strategies:
https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-best-practices-for-niagara

## Engine

When `emit_cue(tag, magnitude, priority)` encounters a full queue:

1. If an executed cue with the same tag is already pending, merge into that
   cue as before (max 32 duplicates) without consuming another slot.
2. Otherwise search *only* disposable `executed` cues whose priority is
   strictly below the newcomer. Evict one with the lowest priority,
   resolving ties by oldest insertion.
3. If no eligible transient exists, reject the new cosmetic cue and leave
   the queue unchanged.

Persistent `started`, `updated` and `stopped` cues are NEVER eviction
candidates, so a burst of cosmetic events cannot silently skip a status
start or cleanup. Existing `replace_active` remains transactional and
continues to reject updates if it cannot enqueue all lifecycle events.

`get_evicted_transient_count()` and `get_rejected_transient_count()`
expose saturation diagnostics since the last `reset()`. Both counters
saturate to avoid numeric overflow; invalid input does not contribute.

## Albion After

`game/scripts/client/gameplay_cues.gd` maps replicated zombie periodic
Resolve pulses to priority **6** and Sunder pulses to priority **4**.
When 128 low-priority cosmetic effects are already queued, those pulses
can still reach the highest-priority portion of the 8-event/frame drain.
The same priorities are carried by the stock-Godot fallback event
descriptors, so the visual policy does not depend on engine availability.

The queues and all signals are presentation-only: server damage, status
stacks, animation authority and ability validation remain unchanged.

## Tests

- Native C++: `[GameplayFX] CueQueue ...` cases in
  `modules/gameplay_fx/tests/test_gameplay_fx.h` cover saturation,
  duplicate coalescing, low-priority FIFO eviction, lifecycle safety,
  transactional rollback and diagnostic counters.
- Game: `game/tests/test_gameplay_cues.gd` tests live native admission
  under a fully saturated 128-event backlog and fallback priority parity.
- Existing `.github/workflows/native-gameplay-cues.yml` builds the
  custom engine and runs both test suites.
