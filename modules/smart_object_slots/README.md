# Native Smart Object Slot Reservations

The native `SmartObjectSlotReservations` RefCounted model is inspired by Unreal Engine's [Smart Objects subsystem](https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview).

Unreal has registered Smart Objects with interaction slots and claim handles. This Cgame module provides a **smaller reusable core: slot-ID exclusivity, bounded reservation lifetimes and deterministic selection**; it does not claim to reproduce the whole Unreal Smart Objects editor, tags or interaction system.

API:
- `try_claim_first(slot_ids, actor_id, lease_seconds)`: accepts up to 16 ordered positive candidate IDs; returns the claimed ID or 0. Prefers an already owned candidate to avoid oscillation; otherwise claims the first free candidate, relinquishing any old actor reservation atomically.
- `advance_time(delta)`: simulation-owned lease expiry, no wall-clock or asynchronous timers.
- `release_actor(actor_id)`, `release_slot(slot_id, actor_id)`, `clear()`, `get_owner(slot_id)`, `get_claim_count()`.

Limits: 2048 live claims, max 5 seconds per lease, one claim per actor, positive IDs, atomic validation and fail-closed invalid requests. An unclaimed slot has no stored representation; the caller owns the ID-to-position mapping. This is a data-only manager and performs no physics or navigation; caller remains authoritative for AI movement and attacks.

Albion After's server-owned infected pack flanking can assign the same deterministic ring positions to different AI members without contention. A per-GameServer native manager is ticked once per simulation frame, and GDScript fallback retains semantics on stock Godot. No network request can directly claim a slot.

## Indexed claims and safe cached-goal invalidation

The original native allocator scanned up to 2048 active leases to locate
each actor or slot. A large infected pack could repeat these scans for every
candidate of every EQS flank replan. The native engine now keeps two hashed
ID-to-index maps, and releases claims with an index-preserving swap-remove:
- Expected O(1) lookup for slot ownership and actor's active claim, versus O(N).
- Expected O(1) release for one actor or slot, versus O(N).
- A claim request checks at most 16 candidate IDs (and validates duplicates);
  expiring all leases still performs the unavoidable O(active claims) scan.
- Memory remains bounded by 2048 vector entries and two indices; no new timers,
  RNG draws, worker threads, client authority or callback ordering.
- `get_actor_slot(actor_id)` returns its claimed slot ID (or zero if absent).
  This is a read-only status lookup, **not** a new permission to claim.

The stock-Godot fallback already indexed IDs using dictionaries and now
exposes the same query. Albion After's server-side `Zombie._flank_goal`
checks the cached slot's ownership before reusing a flank position; losing
a 1.5-second lease immediately invalidates that 0.3-second AI position cache.
Older custom Cgame binaries without the new query keep the previous fallback
behavior through `has_method` compatibility detection.

This is a data-structure optimization, not measured FPS or TPS acceleration.
Measure under a loaded server before claiming a throughput gain.
Reference: Unreal Engine Smart Objects slot claims and invalidation —
https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview

## Unreal-style priority claims and active occupancy

`try_claim_first_priority(slot_ids, actor_id, lease_seconds, priority)`
extends the original first-free lease allocator with strict priorities 0..3.
Free slots are always preferred; only when all candidates are reserved may
a higher-priority actor preempt a strictly lower-priority claim that has **not
yet been marked occupied**. An agent actively using its slot cannot be
preempted, including by priority 3. The preempted actor loses ownership and
must replan before assuming its old position is available.

`set_slot_occupied(slot_id, actor_id, occupied)` is owner-checked.
`is_slot_occupied(slot_id)` is read-only. Moving an actor to a different
slot resets occupancy; clearing or expiring the lease removes it. The
original `try_claim_first` retains priority-zero behavior without
unexpected preemption. Failed requests and invalid priorities do not
relinquish existing claims.

Albion After integrates this into server-owned infected flanking: elite
infected may displace ordinary unoccupied ring reservations, while infected
already within 1m of their claimed flank positions remain protected. The
same rules run in the portable GDScript fallback when the updated native
engine is unavailable; existing combat, targeting and network authority
are unchanged.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview

## Cached Smart Object claim heartbeat and occupancy (new)

`refresh_claim(slot_id, actor_id, lease_seconds, occupied)` combines lease
renewal, strict owner validation and live Claimed/Occupied state in **one
O(1) indexed native operation**. Both actor and slot indices must agree with
the requested IDs; stale, expired and preempted handles return `false` with
no state change. The caller supplies a finite lease duration in (0, 5] seconds.
A valid heartbeat preserves slot identity, claim count, priority and position.

This closes a practical gap between planning and using a Smart Object:
Albion After's infected AI caches an EQS flank goal for 300ms. While it
reuses the cached goal, it now renews its 1.5s lease and updates occupied
state according to **its actual distance to the flank spot** (within 1m).
That means an elite cannot preempt a spot another zombie has reached
between tactical replans. Once that zombie walks away, the reservation
becomes safely preemptible. If a zombie's claim expired or was stolen,
the heartbeat fails and its cached goal is invalidated; throttled AI
can continue directly toward the target instead of visiting a stolen
position. No additional EQS query or physics ray is issued.

The new API is implemented identically in the portable
`game/scripts/shared/flank_slot_reservations.gd` fallback, and older native
binaries still use the previous `get_actor_slot` guard. A forgotten
lease **still expires**, even while marked occupied: this is not an
indefinite lock, and server cleanup on death/despawn remains the owner.
All mutation stays inside the server-owned manager, never client RPCs.

C++ and game tests cover owner mismatch, invalid TTL, expiry, priority
preemption, occupancy transitions, and the real infected cached-EQS
path. This is a reduction in repeated lease work and an AI correctness
improvement; no FPS/TPS speedup is claimed without benchmarking.

Inspired by Unreal's Smart Objects lifecycle (Claimed → Occupied → Released),
rather than directly porting its implementation:
https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview
