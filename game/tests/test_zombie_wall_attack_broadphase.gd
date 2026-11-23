extends RefCounted
## Fast nearby wall attacks and bounded extreme-radius fallback must agree.

const WallGrid = preload("res://scripts/shared/zombie_wall_attack_grid.gd")


func run(t) -> void:
	t.current = "infected hit only the barricades in front and in range"
	var walls: Dictionary = {
		11: {"x": -4.0, "z": 0.0},
		21: {"x": 1.0, "z": 0.0},
		13: {"x": 75.0, "z": 0.0},
		22: {"x": 3.0, "z": 1.0},
	}
	var index: Dictionary = WallGrid.build(walls)
	t.eq(WallGrid.candidates(index, Vector2.ZERO, Vector2.RIGHT, 4.0),
		[21, 22], "nearby spatial cells preserve hit order and facing")
	t.eq(WallGrid.candidates(index, Vector2.ZERO, Vector2.RIGHT, 0.0),
		[], "zero attack reach cannot damage any barricade")
	t.eq(WallGrid.candidates(index, Vector2.ZERO, Vector2.LEFT, 4.0),
		[11], "turning changes which wall the infected can reach")

	t.current = "very wide AI queries scan real walls rather than empty cells"
	var wide: Array[int] = WallGrid.candidates(index, Vector2.ZERO, Vector2.RIGHT, 1000.0)
	t.eq(wide, [21, 13, 22],
		"large-radius fallback still preserves original barricade insertion order")
	t.eq(WallGrid.candidates(index, Vector2.ZERO, Vector2.RIGHT, 100.0),
		wide, "fallback stays deterministic across different wide radii")
	t.eq(WallGrid.candidates(index, Vector2.ZERO, Vector2.RIGHT, INF),
		[], "infinite reach is refused")
	t.eq(WallGrid.candidates(index, Vector2.ZERO, Vector2.RIGHT, -1.0),
		[], "negative reach is refused")
	t.eq(WallGrid.candidates(index, Vector2(NAN, 0.0), Vector2.RIGHT, 100.0),
		[], "invalid AI location cannot damage walls")
