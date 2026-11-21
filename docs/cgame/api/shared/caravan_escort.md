# caravan_escort.gd

> (no header comment)

`res://scripts/shared/caravan_escort.gd`

## Constants

- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")` - Party-only preview of a courier destination; no wallet or account details.

## Functions

### `shared_route`

```gdscript
static func shared_route(peer_id: int, players: Dictionary, parties) -> Dictionary
```

### `can_receive_alert`

```gdscript
static func can_receive_alert(event: Dictionary, peer: int, players: Dictionary, parties) -> bool
```

Validate both current group and original alarm group at delivery time.

