# Gameplay Ability Arena

Tiny playable **Godot project** wired to the Cgame native `GameplayAbilitySystem`. Open `project.godot` in a Cgame editor built from this branch, then run the main scene.

- Arrows or WASD: move the blue player.
- Q: shoot a projectile towards the moving training golem (energy cost + cooldown).
- E: dash (energy cost + cooldown + brief invulnerability).
- R: heal (energy cost + cooldown).
- T: toggle a stunned tag to block all three abilities.
- F5 / F9: save / restore player and ability runtime state in `user://`.

The demo exercises the engine API in gameplay; it does **not** replace an existing external game project or include a network-authoritative ability system. It uses no third-party art.
