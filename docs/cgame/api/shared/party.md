# party.gd

> Session-only survivor parties, inspired by classic cooperative MMORPGs.

`res://scripts/shared/party.gd`

## Overview

Session-only survivor parties, inspired by classic cooperative MMORPGs.
Every mutation is invoked by the authoritative GameServer; clients may
request a target peer but cannot choose a leader, member list, or rewards.

## Constants

- `const MAX_MEMBERS := 5`
- `const INVITE_SECONDS := 30.0`
- `const INVITE_RANGE := 16.0`
- `const ASSIST_RANGE := 28.0`
- `const ASSIST_WINDOW := 20.0`
- `const ASSIST_XP_RATE := 0.5`
- `const RallyStandard = preload("res://scripts/shared/rally_standard.gd")`
- `const PartyFocus = preload("res://scripts/shared/party_focus.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const RALLY_SECONDS := 45.0`
- `const RALLY_COOLDOWN := 12.0`
- `const PING_SECONDS := 30.0`
- `const PING_COOLDOWN := 6.0 # One group-wide rate limit, regardless of party size.`
- `const READY_SECONDS := 30.0`
- `const READY_RESULT_SECONDS := 10.0`
- `const READY_COOLDOWN := 8.0`

## Functions

### `assist_xp`

```gdscript
static func assist_xp(base_xp: int) -> int
```

Only the server invokes this after a confirmed infected kill.

### `in_assist_range`

```gdscript
static func in_assist_range(first: Vector3, second: Vector3) -> bool
```

### `mark_rally`

```gdscript
func mark_rally(peer_id: int, position: Vector3, now: float) -> Dictionary
```

The leader marks their own authoritative location. Party members see
exactly one active marker; ungrouped and unrelated clients never receive it.

### `mark_ping`

```gdscript
func mark_ping(peer_id: int, point: Vector2, now: float) -> Dictionary
```

A member's temporary map mark is kept only in authenticated party state.
No world discovery or rewards; a single shared ping expires after 30s.

### `clear_ping_by`

```gdscript
func clear_ping_by(peer_id: int) -> void
```

Leaving, death or disband should not leave a stale squad instruction.

### `standard_reason`

```gdscript
func standard_reason(peer_id: int, position: Vector3, now: float) -> String
```

Validate a free-standing tactical marker before taking a real crafted item.

### `raise_standard`

```gdscript
func raise_standard(peer_id: int, position: Vector3, now: float) -> Dictionary
```

### `standard_at`

```gdscript
func standard_at(peer_id: int, position: Vector3, now: float, delta: float = 0.0) -> Dictionary
```

A party member can only benefit from its own current group marker.

### `clear_standard_by`

```gdscript
func clear_standard_by(peer_id: int) -> void
```

Remove a temporary standard if the owner dies or leaves the party.

### `start_ready_check`

```gdscript
func start_ready_check(peer_id: int, now: float) -> Dictionary
```

Party-only, short-lived consent check before an expedition or raid.
A leader starts it; nobody can vote for another member or pass a deadline.

### `answer_ready_check`

```gdscript
func answer_ready_check(peer_id: int, is_ready: bool, now: float) -> Dictionary
```

### `cancel_ready_check_for`

```gdscript
func cancel_ready_check_for(peer_id: int) -> void
```

Death immediately revokes raid readiness for the entire current group.

### `focus_reason`

```gdscript
func focus_reason(peer_id: int, now: float) -> String
```

Only a leader may set a group-wide infected focus. The target ID has
already been chosen and validated against live zombies by GameServer.

### `start_focus`

```gdscript
func start_focus(peer_id: int, infected_id: int, now: float) -> Dictionary
```

### `has_focus`

```gdscript
func has_focus(peer_id: int, infected_id: int, now: float) -> bool
```

Called exclusively during authoritative infected damage resolution.

### `clear_focus_target`

```gdscript
func clear_focus_target(infected_id: int) -> void
```

### `cancel_focus_by`

```gdscript
func cancel_focus_by(peer_id: int) -> void
```

A fallen leader cannot keep issuing live tactical coordination.

### `set_loot_mode`

```gdscript
func set_loot_mode(peer_id: int, mode: String) -> Dictionary
```

The current leader chooses how FUTURE raid boss bags are distributed.
Existing bags freeze their own mode and recipients at the confirmed kill.

### `loot_mode_for`

```gdscript
func loot_mode_for(peer_id: int) -> String
```

### `members_of`

```gdscript
func members_of(peer_id: int) -> Array
```

### `group_of`

```gdscript
func group_of(peer_id: int) -> int
```

### `invite`

```gdscript
func invite(from_id: int, to_id: int, now: float) -> Dictionary
```

### `accept`

```gdscript
func accept(target_id: int, now: float) -> Dictionary
```

### `decline`

```gdscript
func decline(target_id: int) -> Dictionary
```

### `leave`

```gdscript
func leave(peer_id: int) -> Dictionary
```

### `kick`

```gdscript
func kick(leader_id: int, target_id: int) -> Dictionary
```

### `disconnect_peer`

```gdscript
func disconnect_peer(peer_id: int) -> void
```

### `expire`

```gdscript
func expire(now: float) -> void
```

### `state_for`

```gdscript
func state_for(peer_id: int, now: float = 0.0) -> Dictionary
```

