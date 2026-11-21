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
