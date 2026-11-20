# Panoramic torch light cookies (High/Ultra, Forward+)

Albion After's rooms already have a global camera-nearest torch manager with
hard limits of one shadow caster on High, two on Ultra. This update improves
their directional light patterns without allocating any additional lights.

Inspired by Unreal Engine Light Functions and Unity HDRP light cookies, it
uses Godot's **native OmniLight3D.light_projector**. A single procedural
128x64 lat-long panorama is generated lazily. The mask is almost white, with
subtle periodic cage-shadow ribs and uneven angular detail, allowing stone
walls and dungeon props to receive more sculpted warm firelight.

- Projectors require actual shadow casters in Godot. The existing nearest
  1/2 shadowed torches receive the texture; all shadowless and unsupported
  lights have null projector.
- The texture is reused by all current and streamed torches, rather than
  constructing a new ImageTexture or material for every room.
- High uses dual-paraboloid Omni shadow mapping and limits camera-space
  shadow influence to 27 m. Ultra preserves accurate cubemap shadows with
  a 38 m bound. The existing larger unshadowed torch radii are preserved.
- Performance, Balanced, Mobile and Compatibility use no light cookies,
  no new shadow passes and no extra 3D lighting allocations.
- The lat-long panorama is mathematically periodic at its horizontal seam.
  At polar latitudes the azimuthal modulation is reduced to zero.
- No dynamic projection UV animation: the existing faint torch energy
  flicker is retained, avoiding shimmering projection/shadow atlases.

The effect lives in the client renderer and requires **no C++ patch**;
Light3D already has the projector and shadow mode APIs in this engine fork.
No server or save state is modified.

Tests: res://tests/test_dungeon_torch_cookie.gd, in the full and graphics
suites. Run: godot --headless --path game --script res://tests/run_graphics.gd

The tests prove budget wiring and resource sharing but cannot substitute
for a GPU screenshot comparison and frametime benchmark.
