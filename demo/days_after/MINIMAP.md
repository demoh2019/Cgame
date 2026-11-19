# Tactical minimap for Days After × Albion

A north-up tactical minimap is now part of the main survival scene. The map is
centered on the survivor and shows up to **24 metres** of nearby terrain:

- White arrow: player's direction
- Red circles: nearby infected (dynamic)
- Yellow dots: harvestable resource deposits
- Green dots: loot/pickups
- Blue circle: abandoned shelter

Press **M** to show or hide the minimap and its legend. The overlay is built
using Cgame/Godot's built-in CanvasLayer, Control and custom 2D draw APIs.

## Regression

```sh
<cgame-editor> --headless --path demo/days_after --script res://smoke_test_minimap.gd
```

The smoke test validates world-to-map projection, horizontal radius clipping,
scene/player binding and key-toggle behavior.

## Engine boundary

The minimap deliberately reads the **same scene entities** as gameplay and
does not duplicate resource or infected state. It currently scans direct scene
children for resource/pickup script types; scale up with spatial indexing and
world streaming when the project grows beyond this small demo. That is when
a reusable engine-level spatial query API may need profiling and tests.

This is a local single-player navigation aid, not an MMO world map,
fog-of-war, territory system or cross-zone pathfinder.
