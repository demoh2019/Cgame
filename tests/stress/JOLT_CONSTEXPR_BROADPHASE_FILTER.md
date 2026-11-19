# Jolt: compile-time broadphase filter and direct packed-layer decoding

Jolt calls two independent filters while finding potential contacts. Its
broadphase filter decides which collision trees can be visited; the later
object-layer pair filter checks Godot collision layers/masks. A cheap
broadphase test matters because it is evaluated during broadphase
candidate gathering, before narrowphase collision tests.

Cgame packs each Jolt 16-bit `ObjectLayer` as:

- **high 3 bits**: one of five Jolt broadphase categories
- **low 13 bits**: index into a table of 64-bit Godot layer/mask pairs

Previously the broadphase filter constructed a `static const`
`JoltBroadPhaseMatrix` on first use, requiring a runtime initialization
guard on toolchains that do not optimize it away. It also ran the
`decode_layers` helper which computes both the broadphase category and
an unused object-layer index.

The new implementation marks the matrix constructor and its helper
functions `constexpr`, instantiates a `static constexpr` matrix, and
extracts the broadphase category directly with
`uint32_t(encoded) >> 13`. The `GetBroadPhaseLayer` callback uses the
same direct shift. Compile-time `static_assert` checks guard several
important directed collision rules.

## Directed 5x5 broadphase rules

The rows and columns are ordered STATIC, STATIC_BIG, DYNAMIC,
AREA_DETECTABLE, AREA_UNDETECTABLE.

| Initiating tree | STATIC | STATIC_BIG | DYNAMIC | AREA_DETECTABLE | AREA_UNDETECTABLE |
|---|---|---|---|---|---|
| STATIC | no | no | yes | yes | yes |
| STATIC_BIG | no | no | yes | yes | yes |
| DYNAMIC | yes | yes | yes | yes | yes |
| AREA_DETECTABLE | yes | yes | yes | yes | yes |
| AREA_UNDETECTABLE | yes | yes | yes | yes | no |

The matrix is *directed* and remains byte-for-byte equivalent to the
existing `allow_collision` entries. Do **not** attempt to turn this
matrix into a broadphase collision layer mask or apply Jolt's AND-style
ObjectLayerPairFilterMask: Godot's object collision masks use a
directional **OR** rule, tested separately after broadphase filtering.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_constexpr_broadphase_filter.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_broadphase_filter_regression.gd
```

The Python source contracts cover every directed broadphase matrix pair,
object-layer indices 0 through 8191, plus 10,000 seeded random packed
layers. The native Jolt fixture creates dynamic bodies inside detectable
and undetectable Area3D sensors; both must receive one enter and one exit
when bodies move away. It complements
`physics_jolt_layer_filter_regression.gd`, which covers object
layer/mask interactions including asymmetry and high bits.

The native CI job explicitly **replaces** the existing
`3d/physics_engine="GodotPhysics3D"` setting in `project.godot` with
Jolt, instead of appending a duplicate `[physics]` section. CI compiles
the constexpr assertions, checks the GDScript, runs the native case, and
archives the output log.

This reduces per-callback decoding and removes first-call dynamic matrix
initialization where applicable. **No measured CPU/FPS gain is claimed**
without native before/after profiling of many candidate broadphase pairs.

## References

- Jolt Architecture: https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md
- Jolt ObjectVsBroadPhaseLayerFilter: https://jrouwe.github.io/JoltPhysics/class_object_vs_broad_phase_layer_filter.html
