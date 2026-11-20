# Region-specific atmosphere on the existing Godot fog pass

The renderer already supports Godot built-in height fog everywhere and a
small Forward+ froxel volume on High/Ultra. This change makes the same
resources react to the local biome without any extra textures, draw calls,
volumes, shaders or material variants:

* Swamps are more humid and carry a gentle desaturated green haze.
* Forests are slightly mistier and cooler.
* Mountains have notably cleaner, thinner air.
* Beaches have lighter bluish sea haze.
* Plains, unknown areas and other biomes preserve neutral settings.

The online and offline clients sample `world.biome_at` with the existing
4 Hz weather cadence; the shared Atmosphere eases colors and densities
across regional boundaries. Night fog keeps the original sky color. The
input is visual-only, never affects server weather, line of sight,
collision or PvP.

Preset multipliers are bounded, and every renderer reuses Godot's
existing Environment fog state. High and Ultra preserve the same
volumetric rendering budget; Compatibility/Mobile create no additional
GPU effect.

Godot test command:
`godot --headless --path game --script res://tests/run_all.gd`
The new `test_biome_atmosphere.gd` checks renderer behavior, limits,
boundary smoothing, biome variation and both client wiring.
Measured GPU frame times and screenshots are still necessary.
