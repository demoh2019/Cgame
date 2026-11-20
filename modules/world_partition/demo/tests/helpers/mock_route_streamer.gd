extends Node3D

# Minimal API stand-in so Godot headless can exercise actual NavigationAgent3D
# traversal without a compiled Cgame WorldPartition3D module.
var next_token := 1
var leases: Dictionary = {}
var cells_loaded := true

func acquire_cell_route(from_cell: Vector2i, to_cell: Vector2i) -> Array:
    if not cells_loaded or from_cell != Vector2i(0, 0) or to_cell != Vector2i(1, 0):
        return []
    var tokens: Array = []
    for cell in [from_cell, to_cell]:
        var token: int = next_token
        next_token += 1
        leases[token] = cell
        tokens.append(token)
    return tokens

func release_cell_route(tokens: Array) -> int:
    var released := 0
    for token in tokens:
        if leases.has(token):
            leases.erase(token)
            released += 1
    return released

func is_cell_loaded(cell: Vector2i) -> bool:
    return cells_loaded and (cell == Vector2i(0, 0) or cell == Vector2i(1, 0))

func get_cell_lease_count_total() -> int:
    return leases.size()
