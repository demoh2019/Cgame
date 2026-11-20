# How the game looks

* `scripts/client/atmosphere.gd`: procedural sky with a day/night/dusk/storm palette, a warm low sun and a blue moon, ACES tone mapping,
  glow, contrast, aerial fog, and a directional light with soft shadows that follow the camera (trees, houses and walls cast them).
  Compatibility renderer by default (it runs everywhere); SSAO is switched on for Forward+, see below.
* `assets/shaders/water.gdshader`: sea with depth-based colour, a foam line along the shore, scrolling ripples and a Fresnel sheen.
* `scripts/client/chunk_view.gd` ground shader: patches of lush and dry grass, dirt, sand and wet ground at the shore, rock strata on slopes,
  snow on the peaks, all from layered noise.
* `scripts/client/foliage.gd`: trees, bushes, grass and ferns sway in the wind (a vertex shader that keeps the pack's textures).
* `scripts/client/effects.gd`: particles for hits, deaths, muzzle flashes, gathering, loot, level-ups, dust from running, and rain that
  follows the camera during storms (not under the settlement roofs).
* `scripts/client/ui_theme.gd`: one theme for the HUD: outlined text, rounded dark panels with a gold edge, rounded bars and buttons.

Screenshot a time of day: `... online_main.tscn -- --connect ... --demo forest --phase 0.22` (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight), `--storm` for rain.

Forward+ (`--rendering-method forward_plus`) adds SSAO but made the first frames stall for 3-4 s here (shader compilation), long enough for
the server to drop the connection, so it is not the default.
