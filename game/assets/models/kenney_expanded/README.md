# Integrated environment models

26 self-contained Kenney CC0 glTF binaries, added directly to the game (no network required at runtime).

- `nature/` — 6 trees plus flowers, mushrooms, bushes, stumps, stacked logs and a campfire.
- `graveyard/` — broken headstones, grave border, coffin, damaged fence/bench, fallen pine.
- `castle/` — 2 demolished siege machines.

The game maps the new tree variants into the world renderer through
`scripts/client/model_catalog.gd` and `scripts/client/chunk_view.gd`.
Additional small objects are rendered as batched MultiMeshes, positioned
around vegetation, meadows and actual ruin structures. No gameplay collision
or network entities are created for purely visual objects.

Licensing details: [LICENSE.txt](LICENSE.txt).
