# XPBD SoftBody3D: scale-invariant edge/edge contact narrowphase

Cgame's GodotPhysics3D has optional BVH edge/edge self-collision for folded
cloth and an independent edge/edge Coulomb-like friction PR. Both use
`physics_xpbd_closest_edges()` to compute the interior closest-point pair
on nonadjacent structural mesh edges.

## Problem corrected

The old helper cast the *result* of `Vector3::dot()` to double, rather than
casting the coordinates before multiplying. Finite single-precision edges
could therefore produce an infinite `dot(ab,ab)` near side length 1e20,
while short edges were rejected by a world-unit CMP_EPSILON threshold.

A second failure mode was cancellation in the nearly parallel Gram
determinant `aa*cc-bb²`, which can lose most of its significant digits.
Closest-point separation was also squared in `real_t`, despite both edge
endpoints being valid finite coordinates.

## Implementation

- Subtract all world coordinates into `double`, then compute dot products
  and the edge cross product with double intermediates.
- Use `|ab×cd|²` as the Gram determinant instead of subtracting nearly
  equal values. Reject near-parallel edges with the original angular
  threshold `|ab×cd|² > CMP_EPSILON * |ab|² * |cd|²`.
- Reject *zero-length* edges, but no longer reject geometrically valid
  tiny edges because of a fixed unit-scale epsilon.
- Form closest points and squared separation in double. Only fall back to
  the edge cross normal near an actual crossing using a *scale-relative*
  threshold `distance² <= max(|ab|²,|cd|²)*1e-24`.
- Publish `s`, `t`, unit normal and distance **together** once all values
  are finite and the closest points lie strictly in the interior. Invalid
  faces leave the outputs untouched.
- Retain the existing maximum per-edge candidate budgets, BVH structure,
  collision filters and XPBD solver. No new allocations or settings.

A separate PR on edge/edge friction uses the same common narrowphase, so
it inherits this numerical improvement without adding another query pass.

## Regression

```bash
python3 -m unittest discover -s tests/stress -p test_physics_xpbd_edge_scale.py -v
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="[PhysicsEdgeScale]"
```

Seven C++ cases cover ordinary, 1e20-scale, and 1e-8-scale edges, true
intersection normal, exact pins and contact projection, parallel/endpoint
no-contact, atomic failure and translation invariance. Six Python
source and numerical cases include 10,000 seeded interior pairs with edge
sizes from 1e-19 to 1e23.

### Limitations

These changes improve validity for finite float32 inputs but **cannot**
recover precision lost when distinct world-space positions round to the
same float32 value. Deeply intersecting edge pairs and swept edge/edge CCD
remain outside the existing discrete narrowphase. Added double arithmetic
can increase per-candidate CPU cost: do not claim any FPS or RSS
improvement without native benchmarks.
