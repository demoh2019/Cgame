# Native Smart Object Slot Reservations

The native `SmartObjectSlotReservations` RefCounted model is inspired by Unreal Engine's [Smart Objects subsystem](https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview).

Unreal has registered Smart Objects with interaction slots and claim handles. This Cgame module provides a **smaller reusable core: slot-ID exclusivity, bounded reservation lifetimes and deterministic selection**; it does not claim to reproduce the whole Unreal Smart Objects editor, tags or interaction system.

API:
- `try_claim_first(slot_ids, actor_id, lease_seconds)`: accepts up to 16 ordered positive candidate IDs; returns the claimed ID or 0. Prefers an already owned candidate to avoid oscillation; otherwise claims the first free candidate, relinquishing any old actor reservation atomically.
- `advance_time(delta)`: simulation-owned lease expiry, no wall-clock or asynchronous timers.
- `release_actor(actor_id)`, `release_slot(slot_id, actor_id)`, `clear()`, `get_owner(slot_id)`, `get_claim_count()`.

Limits: 2048 live claims, max 5 seconds per lease, one claim per actor, positive IDs, atomic validation and fail-closed invalid requests. An unclaimed slot has no stored representation; the caller owns the ID-to-position mapping. This is a data-only manager and performs no physics or navigation; caller remains authoritative for AI movement and attacks.

Albion After's server-owned infected pack flanking can assign the same deterministic ring positions to different AI members without contention. A per-GameServer native manager is ticked once per simulation frame, and GDScript fallback retains semantics on stock Godot. No network request can directly claim a slot.
