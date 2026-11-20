# Ultra stone Parallax Occlusion Mapping (native Godot + engine fix)

Inspired by Unreal Engine Parallax Occlusion Mapping and Unity HDRP's
Parallax Occlusion Mapping node, this integrates **angle-aware depth illusion**
into existing imported stone surfaces in the Albion After ruin/dungeon kit.

Godot's existing BaseMaterial3D provides heightmap_enabled,
heightmap_deep_parallax, scale and angle-variable sample counts. We reuse
the same tileable 128x128 height field that drives the micro-normal relief;
the RGB heightmap has proper mipmaps and is lazily generated once for all
masonry chunks. Original artists' PBR albedo, ORM, normals and roughness
are preserved.

Performance, Balanced and High, as well as Mobile/Compatibility, never
enable POM and allocate no height texture. High keeps its existing cheaper
detail normals. Ultra Forward+ uses a shallow heightmap_scale of 0.85
(Godot material converts that to a 0.0085 UV scaling factor) with 4 to 8
sample layers depending on view angle. Heightmap material features already
authored by an artist are never overwritten. Triplanar surfaces, alpha
cutouts and surfaces without valid imported tangents are excluded.

The custom Godot C++ fork now:
- avoids redundant shader variant rebuild requests when the deep-parallax
  setter is called with an unchanged value;
- clamps the interpolation layer budget inside the generated native shader
  to 1..64 even with invalid caller-provided numeric settings;
- guards the POM raymarch at unit height, preventing overrun on unexpected
  height texture values without affecting correctly normalized textures.

Auto quality changes update already instanced material objects in place,
via weak references, and newly streamed models inherit current settings.

Tests: res://tests/test_graphics_stone_parallax.gd
Run: godot --headless --path game --script res://tests/run_graphics.gd

The Godot fork requires recompilation to use the C++ changes; tests also
need a full Godot runtime. GPU screenshots, frame-time measurements, and
angle/focal-distance quality checks remain necessary before tuning further.
