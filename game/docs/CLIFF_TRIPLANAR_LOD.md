# Distance-bounded triplanar cliff material

Godot's own StandardMaterial3D documentation warns that **triplanar
mapping needs significantly more texture reads per pixel** than ordinary
UV mapping. Our 13-layer biome terrain already has High/Ultra triplanar
rock normal mapping, but *every* cliff pixel also paid for three rock
albedo projections, even when far beyond the texture detail radius.

The new path leaves the full near-camera cliff projection intact and
keeps the existing multi-material PBR layer blend, wetness, roughness,
cliff normals, snow, moss and weather. The existing
`aa_terrain_detail_radius` quality global also controls rock albedo LOD:

- **Near:** same three explicit-gradient triplanar color projections
  and High/Ultra rock normal maps as before.
- **Transition:** gradually mix the triplanar sample toward the
  precomputed, color-corrected average for the same rock layer.
- **Far:** no cliff albedo or cliff normal map samples: the macro
  material blend keeps rock color and biome boundaries intact.
- The transition is continuous; low graphics presets cut the expensive
  samples sooner, Ultra preserves detail farther away.

**GPU sample budget:** a distant pixel selecting cliff rock goes from
3 cliff albedo texture reads to 0. Shader branching, execution granularity,
memory cache and actual screen coverage affect real speedups. This is
not a measured FPS improvement.

The optimization is specific to distant subpixel roughness, following
the geometry/material LOD principles found in Unreal Engine, Unity HDRP
and Godot. It does **not** import their proprietary renderer features.

Tests are appended to `test_terrain_shader_lod.gd`, which is already
registered in `run_all.gd`. Run:
`godot --headless --path game --script res://tests/run_all.gd`.
Screenshot-compare cliff edges and wet/dry material transitions on
desktop and Compatibility/Mobile before release.
