# Cinematic lighting and scalable sky — Albion After

The lighting pipeline now has a backend-aware quality budget. It follows
the practical design of high-end engines (cascaded outdoor shadows, bounded
volumetric fog and explicit low-end fallbacks), without attempting to copy
Unreal's Lumen/Nanite or Unity HDRP renderers into Godot.

## What changed in the actual game

- **Performance:** no sun shadow-map passes; volumetric fog disabled.
- **Balanced:** two directional shadow cascades; volumetric fog disabled.
- **High:** two shadow cascades with blended transitions; volumetric fog disabled.
- **Ultra:** four shadow cascades with blended transitions, increasing close
  shadow detail; on **Forward+ only**, also uses bounded, illuminated
  volumetric fog (78 m range) for depth around outdoor silhouettes.
- **Mobile / Compatibility:** volumetric fog is *always off*, even on Ultra.
  The existing inexpensive distance fog still works, and other visual
  quality features keep their own existing profile settings.

The existing multiplayer quality selector and **Ctrl+F11** shortcut use
this policy automatically. The **local playable preview** now uses the
same shared `Atmosphere` system instead of a flat solid-colour background:
panorama sky, changing sun and moon, cloud shadows, ACES tonemapping,
day/night fog and storm transitions. It loads the same saved graphics
quality preference, and also supports **Ctrl+F11** to cycle presets while
keeping **F11** for its existing medical shortcut.

Local weather samples are capped at **4 per second** rather than doing a
full biome/weather query each render frame. Sky reflection updates stay
bounded by the existing incremental sky cadence; sunlight and fog continue
to animate every frame. The sky disc now points *toward* the light source
(the reverse of the emitted directional light rays), matching the sun in
the game world.

No gameplay, networking, world generation, character persistence or
server rules were modified.

## Engine references

- Unreal Engine uses high-resolution virtual shadowing and scalability
  around complex worlds: https://dev.epicgames.com/documentation/en-us/unreal-engine/virtual-shadow-maps-in-unreal-engine
- Unity HDRP uses explicit graphics budgets, probe lighting and optimized
  atmospheric effects: https://unity.com/blog/lighting-and-environments-hdrp-updates-unity-6
- Godot documents its 2-/4-split directional shadows:
  https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html
- Godot Forward+ supports volumetric fog; Compatibility and Mobile do not:
  https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html

## Regression tests and performance review

`res://tests/test_graphics_lighting.gd` checks profile bounds, renderer
feature gates, actual Godot shadow/fog property writes, the shared offline
visual pipeline and weather sampling throttling.

```sh
godot --headless --path game --script res://tests/run_all.gd
godot --path game
```

Visual QA to do on a real GPU: capture identical coordinates at noon,
dusk, night and during a storm, in Compatibility Balanced/Ultra and
Forward+ Balanced/Ultra. Compare median and p95 frame times, GPU time,
shadow acne and cascade transitions while roaming around foliage/ruins.
Keep expensive effects disabled on profiles that miss the frame budget.

**Note:** The project defaults to Compatibility renderer for the
widest device support. Four split shadows work there; Forward+ volumetric
lighting requires a supported Forward+ runtime. Neither Lumen, Nanite,
nor Unity APV were added to Godot.
