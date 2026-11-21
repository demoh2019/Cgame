# party_supply_beacon.gd

> Validate one transient supply location before showing it in the client map, 3D world or HUD.

`res://scripts/client/party_supply_beacon.gd`

## Overview

Validate one transient supply location before showing it in the client map,
3D world or HUD. Server events are trusted for their origin, but every
snapshot must re-check group membership and the event's expiration.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`
- `const PartySupplyRequest = preload("res://scripts/shared/party_supply_request.gd")`

## Functions

### `read`

```gdscript
static func read(signal_state: Dictionary, viewer_id: int, party: Dictionary, now: float) -> Dictionary
```

