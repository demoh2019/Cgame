# Orthographic terrain LOD pixel calibration: Cgame + Albion After

The native ChunkedTerrain3D error-based mesh LOD system already uses
current camera resolution and render scale (FSR). However, the orthographic
projection branch always divided the *vertical* pixel count by Camera3D.size.
Godot specifies that size is horizontal when Camera3D KEEP_WIDTH is selected,
and vertical for KEEP_HEIGHT. This mismatch causes overly aggressive
simplification in portrait/ultrawide layouts, despite the same visible error.

The engine now selects the correct viewport axis and accounts for 3D
resolution scale. A small pure geometry helper is exercised by C++ tests
across horizontal and vertical modes, portrait/wide views, FSR half scale,
and invalid inputs. Unsupported frustum projections leave geometric error
LOD disabled rather than using a false perspective FOV.

The game caps all incoming terrain pixel error requests to 0..20 and
ignores NaN/Infinity from presets or the adaptive renderer. Existing
graphics quality tiers and real terrain shaders are left intact.

No draw calls, mesh data, textures, physics or gameplay state changes.
The native policy is quality-critical but FPS changes require hardware
measurement.

Engine: tests/scene/test_heightmap_terrain_geometry.cpp.
Game: game/tests/test_terrain_geometric_error_lod.gd.
Command: godot --headless --path game --script res://tests/run_all.gd
