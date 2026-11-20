# Rain-reactive PBR clothing and gear

The open-world weather already wets terrain and foliage. Animated survivors,
outfits, boots, cloaks and hoods now share that renderer-only rain response.

Using Godot StandardMaterial3D (conceptually similar to Unreal's Clear Coat
shading model), the system derives **four discrete wet material variants** from
existing imported PBR resources. Wet fabric gets darker and its roughness
decreases. On Forward+ High/Ultra, a restrained clearcoat layer simulates a
thin water film above the original texture/normal/ORM maps.

There are no additional scene meshes, draw calls, user shaders, or uploaded
textures per actor. Variants are cached **per source material**, so hundreds
of identical outfits share the same native PBR resources. At the same
weather/quality step, the per-frame cost is a single integer comparison.
Imported base materials are never modified. Skin, hair, transparent cutouts
and unshaded materials are explicitly excluded.

Performance disables visual weathering; Balanced uses only slight albedo/
roughness changes. Compatibility and Mobile are capped at the low-cost tier.
Only Forward+ High/Ultra use the additional clearcoat lighting computation.

OnlineMain passes the already-smoothed server weather and active graphics
profile into both the local avatar and EntityView. Newly streamed actors
inherit the current weather immediately, and newly attached wearable gear
receives the same material treatment without rebuilding the character mesh.

No server state, save schema or networking packets change.

Regression suite: res://tests/test_character_rain_gear.gd
Run: godot --headless --path game --script res://tests/run_all.gd

Static tests verify material and scene wiring; physically-based highlight
quality and FPS must still be measured on the actual target GPUs.
