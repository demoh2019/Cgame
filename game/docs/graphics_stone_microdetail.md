# Procedural PBR microdetail on masonry ruins

Inspired by **Unreal Engine Detail Texturing** and **Unity HDRP detail
normal maps**, this system adds thin stone-grain relief to masonry walls,
columns, pillars, stairs and ruined masonry within the optional dungeon
art kit. This is real native Godot Standard/ORM Material3D
`detail_normal`, not painted vertex color or extra shadow map geometry.

The existing ModelCatalog bake already preserves tangents with an
inverse-transpose and orthogonalized tangent frames, so this feature is
applied only to surfaces that have valid tangents. The original albedo,
ORM, metallic and base normal textures are preserved exactly. Authored
materials that already have their own detail maps are left untouched.
Bed, barrel, torch, cloth, foliage and character materials are excluded.

## Cost and quality

- Performance, Balanced, GL Compatibility and Mobile: **no detail normal
  sampler**. The original material pipeline remains.
- Forward+ High: one shared procedural 128x128 high-strength? No:
  mild normal detail texture sampled by the existing native detail stage.
- Forward+ Ultra: one shared 128x128 more pronounced normal detail.
- Two mipmapped, tileable normal textures are generated on the CPU
  lazily, at most once each, and shared by every eligible masonry surface.
- No new mesh, texture download, geometry tessellation, draw call,
  fullscreen pass, terrain chunk rebuild or network changes.
- Quality/Auto settings toggle existing baked materials *in place* using
  WeakRefs. Newly streamed ruins immediately inherit the active tier;
  old world meshes may be freed without the profile controller owning them.

The material detail stage costs one extra texture lookup on High/Ultra
stone surfaces. Check GPU frametimes and close-camera before/after
screenshots on target hardware before raising the strength or tile density.

Tests: `res://tests/test_graphics_stone_microdetail.gd`.
Run: `godot --headless --path game --script res://tests/run_graphics.gd`.

No engine C++ changes: Godot's existing native PBR detail-normal stage
supports these features and is already integrated into the graphics engine.
