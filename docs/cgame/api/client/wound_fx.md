# wound_fx.gd

> Location-based gore, built the way shipped games do it (Valve's L4D2 wound cut-outs, the layered anatomy of Dead Island 2's FLESH, weight-based dismemberment...

`res://scripts/client/wound_fx.gd`

## Overview

```text
Location-based gore, built the way shipped games do it (Valve's L4D2 wound cut-outs, the
layered anatomy of Dead Island 2's FLESH, weight-based dismemberment):
 * the bone nearest the strike gets a real opening — a shader cuts the skin along the strike
   and shows a crater of skin, fat and striated muscle, with the actual BONE inside;
 * fresh wounds keep dripping;
 * a severing blow removes the limb from the body BY BONE WEIGHTS (no stretching), leaves a
   layered stump (skin rim, fat, muscle, bone with marrow) and throws a copy of the real limb;
 * blunt power blows snap limbs to sick angles.
Purely cosmetic and client-side; the server only says who hit whom, how hard, and if it killed.
```

## Constants

- `const MAX_WOUNDS_PER_BODY := 10`
- `const MAX_WOUNDS := 160`
- `const MAX_PIECES := 24`
- `const PIECE_LIFETIME := 25.0`
- `const SEVER_DAMAGE := 22.0`
- `const DRIP_SECONDS := 9.0 # A fresh wound keeps dripping this long.`
- `const MAX_DRIPPING := 6`
- `const WOUND_SHADER := preload("res://shaders/wound_flesh.gdshader")`
- `const MAX_OPENINGS := 8 # Shader slots per body; the oldest wound closes when a ninth opens.`

## Classes

- `class Breaker extends SkeletonModifier3D:` - Runs after animation and ragdoll every frame: collapses severed bones and bends broken ones.

## Functions

### `on_hit`

```gdscript
func on_hit(model: Node3D, origin: Vector3, direction: Vector3, damage: float, ranged: bool, fatal: bool, ichor: bool, weapon_id: String = "", charge: float = 0.0) -> bool
```

model: the enemy's character model; origin/direction: the line of the strike in world space.
Returns true when the blow was spectacular (severed or snapped), for a beat of slow motion.

### `finisher`

```gdscript
func finisher(model: Node3D, weapon_id: String, ichor: bool) -> void
```

Ground finisher on a downed body: a blunt weapon caves the skull in, a blade takes the head.

### `wound_shape`

```gdscript
static func wound_shape(weapon_id: String, ranged: bool, damage: float) -> Dictionary
```

Weapon families: stabbing makes a deep round hole, slashing a long gaping cut, blunt a small split.

_26 private function(s) starting with `_` are not listed._
