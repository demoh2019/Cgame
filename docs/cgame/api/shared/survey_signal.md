# survey_signal.gd

> A crafted one-use expedition signal shares only a real, currently marked mineral deposit with authenticated teammates via the existing party ping.

`res://scripts/shared/survey_signal.gd`

## Overview

A crafted one-use expedition signal shares only a real, currently marked
mineral deposit with authenticated teammates via the existing party ping.
No client-supplied coordinates, resource IDs, ore quantities or payouts.

## Constants

- `const Prospecting = preload("res://scripts/shared/prospecting_chart.gd")`
- `const Party = preload("res://scripts/shared/party.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const ITEM_ID := "surveyor_signal"`

## Functions

### `candidate`

```gdscript
static func candidate(player, parties, depleted: Dictionary, now: float) -> Dictionary
```

Pure, nonmutating preflight: invalid scans or party cooldowns cost nothing.

### `broadcast`

```gdscript
static func broadcast(parties, peer_id: int, selection: Dictionary, now: float) -> Dictionary
```

Must be called immediately after preflight and inventory debit on the
authoritative server; mark_ping repeats the party/cooldown validation.

### `clear_depleted`

```gdscript
static func clear_depleted(parties, node_id: int) -> void
```

Any survivor harvesting a signalled node closes the squad waypoint in the
same authoritative tick, even when the surveyor is not the harvester.

