# Days After — playable survival slice

A standalone 3D prototype running directly on the Cgame engine. Open `demo/days_after/project.godot` in the Cgame editor or launch it with the built Cgame executable.

## First playable loop

- Explore a small abandoned checkpoint in first-person; collide with terrain and walls.
- Look at colored supply crates and press **E** to collect water, food and scrap.
- Watch health, hunger, thirst and inventory in the HUD.
- Press **1** to drink water and **2** to eat; hunger and thirst decrease over time.
- If a survival stat runs out, health starts dropping; health reaching zero ends the run.

Controls: **WASD** move, **Shift** sprint, **Space** jump, **E** interact, **1/2** consume, **Esc** release/capture cursor.

## Running and testing

From the Cgame repository root (replace `godot` with the built Cgame binary path):

```bash
godot --path demo/days_after --editor
godot --headless --path demo/days_after --script res://tests/test_survival_state.gd
godot --headless --path demo/days_after --quit-after 30
```

The pure survival-state regression runs without graphics. The headless scene launch is a separate smoke test, not a claim that rendering or gameplay have been tested.

## Architecture

`survival_state.gd` contains game-specific health/inventory rules and is independent of SceneTree. `player.gd` uses standard CharacterBody3D and RayCast3D. `main.gd` generates the prototype world, pickups and HUD.

**Engine-first rule:** reusable missing functionality should be implemented in Cgame's engine or an engine-generic module, with matching tests; Days After should only contain game-specific rules. This slice currently uses engine APIs already present. No global engine settings or physics core are changed.

## Next steps

Implement save/load (versioned), interactable item resources and inventory slots, crafting, survival zones, enemy AI, gameplay audio, streaming terrain, and performance/CI checks against the custom Cgame binary.
