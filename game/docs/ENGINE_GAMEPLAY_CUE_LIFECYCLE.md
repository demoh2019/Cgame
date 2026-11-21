# Resilient Gameplay Cue lifecycle under cosmetic overload

Cgame supports Unreal GAS-style presentation-only cues without granting
gameplay authority to particles or sound dispatch. A full per-actor queue
of 128 expendable ambient cues previously prevented a newly replicated
status's `started` or `stopped` cue from being scheduled. That could
leave cosmetic status indicators visually stale until a later snapshot.

## Native API

`GameplayCueQueue.replace_active_resilient(snapshot, priority=0)` is an
opt-in variant of the existing strict `replace_active()`. It validates
the complete snapshot and queues **all** necessary lifecycle transitions
as one transaction.

- Reuses pending same-tag/same-event coalescing.
- If 128 slots are occupied, may evict the **oldest transient** with the
  **lowest** priority *strictly below* the incoming lifecycle priority.
- Never evicts `started`, `updated` or `stopped` events, nor transients
  of equal/higher priority.
- If there are not enough eligible victims for **every** lifecycle event,
  the active tags, queued events and evicted/rejected counters are all
  unchanged. A subsequent drain can make room safely.
- Queue and active limits stay at 128, repeat coalescing at 32 and
  priority range at 0–7. All runtime CPU work remains per-actor bounded.
- `get_evicted_transient_count()` includes lower-priority background
  pulses displaced to admit lifecycle transitions.

The existing `replace_active()` and `set_active()` retain their strict
atomic no-eviction contract for games that require it.

## Albion After

`game/scripts/client/gameplay_cues.gd::sync()` derives persistent cues
only from the replicated server-owned actor snapshot. It requests priority
2 for status transitions and uses the resilient method when available.
Older Cgame builds use the strict legacy method; stock Godot continues
using the client-side cosmetic fallback.

Only visual status lifecycle is improved: no client-induced damage,
health, status duration, effect rules, networking or server behavior
changes. Ambient VFX remain lower priority than status cleanup.

## Validation

- Native tests cover saturated ambience, multi-cue start and stop,
  idempotent snapshots, atomic rollback when there is only one eligible
  victim, and prohibition on evicting equally important/high-priority
  transients.
- A real Albion actor test exercises the live `GameplayCues.sync` path,
  ensuring two status starts and later stops survive a full background
  queue and drain at the configured per-frame budget.
- Dedicated source contract runs in GitHub Actions. Existing
  `native-gameplay-cues.yml` independently compiles native Cgame and
  runs the headless gameplay suite. No performance improvement is
  asserted without profiling.

Design reference:
https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-effects-for-the-gameplay-ability-system-in-unreal-engine
