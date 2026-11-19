# PCG Graph for Godot — experimental add-on

A first usable slice of a **visual Procedural Content Generation (PCG) Graph**.
It adds a node-based workflow for generating points and placing GPU-instanced meshes
as a foundation for more advanced open-world tooling.

## Installation and use

Open the `misc/pcg_graph` folder as a Godot 4.7+ project to try it.
For other games, copy `misc/pcg_graph/addons/pcg_graph` to
`res://addons/pcg_graph`, then enable **PCG Graph** under
**Project → Project Settings → Plugins**. A **PCG Graph** bottom panel appears.

1. Click **New** to create a GRID → OUTPUT graph.
2. Add processors from the dropdown, edit their parameters in the graph nodes,
   and connect their output/input ports. The editor rejects cycles and
   multiple input connections.
3. Enter a `res://forest_graph.tres` path, then click **Save**.
   Click **Open** to reload a saved graph.
4. Add a Node3D to your scene and attach `pcg_spawner_3d.gd`, or use the
   globally registered `PCGSpawner3D` script class.
5. Assign an **Instance Mesh** in Inspector. With the spawner selected,
   click **Generate on selected PCGSpawner3D** in the graph panel.
6. Alternatively, assign a PCGGraph resource in Inspector, press its
   **Generate PCG** tool button, or enable `generate_on_game_start`.

Successful generation creates/replaces one child MultiMeshInstance3D named
`_PCGGenerated`. Editor generated children are saved with the scene when the
spawner has an owner. Failed evaluation or budget checks preserve the last
successful generation.

## Node kinds

| Node | Inputs | Behavior |
| --- | --- | --- |
| GRID | none | X/Z grid with columns, rows and spacing |
| JITTER | point stream | Reproducible random X/Z position offsets |
| RANDOM_FILTER | point stream | Seeded probability to retain points |
| NOISE_FILTER | point stream | Threshold on seeded FastNoiseLite noise |
| HEIGHT_NOISE | point stream | Add deterministic FastNoiseLite height to Y; frequency and amplitude |
| HEIGHT_FILTER | point stream | Keep points within an inclusive Y interval |
| DISTANCE_FILTER | point stream | Greedy X/Z spacing filter using a spatial hash; no two retained points closer than minimum_distance |
| OFFSET | point stream | Translate points along XYZ |
| OUTPUT | point stream | Final stream delivered to spawner |

For a simple forest placement graph, connect **GRID → JITTER → HEIGHT_NOISE → HEIGHT_FILTER → DISTANCE_FILTER → OUTPUT**.
`HEIGHT_NOISE` produces procedural Y values rather than sampling existing terrain.
`HEIGHT_FILTER` keeps points in a chosen elevation band, and
`DISTANCE_FILTER` removes nearby points in input order using X/Z distance,
regardless of Y (useful for tree spacing). The filter is deterministic,
retains earlier points first, and handles negative and very large grid coordinates.
These steps do not yet project instances onto an external heightmap or collision surface.

The graph is saved as a native Godot Resource. GDScript code can call
`PCGGenerator.evaluate(graph)` and receives a Dictionary containing
`ok`, `error` and `points` keys. Unchanged seed, IDs and parameters
produce deterministic results.

Validation rejects missing or multiple OUTPUT nodes, invalid/missing inputs,
cycles, duplicate node IDs, malformed connections, invalid/nonfinite
parameters, and excessive point counts. Default budget is **10,000 points**
and **256 nodes**, enforced even on manually edited resources.

## Automated tests

Run with Godot 4.7.2 or newer:

```sh
godot --headless --path misc/pcg_graph --editor --import --quit
godot --headless --path misc/pcg_graph --script res://tests/test_pcg_graph.gd
```

The suite includes additional height-noise, altitude-filter, and
minimum-distance scatter test groups alongside the original 15 test groups and 80+ checks covering topology, seeded randomness, processing, error handling,
resource save/load, large grids and MultiMesh generation/replacement.
The GitHub Actions workflow downloads the official Linux editor binary and
runs the same project in headless mode.

## Limitations and integration plans

This is a scoped **PCG Graph MVP**, not full Unreal Engine PCG parity.
It does not yet support typed multi-input pins, procedural subgraphs, custom
GDScript nodes, external terrain/spline/volume sampling, material layers, instanced
scenes, grass LODs, streaming generation, HLOD, graph debugging or scene
UndoRedo for generated instances.

The add-on is deliberately isolated from Godot engine internals. When the
separate native Terrain and WorldPartition prototypes receive review and
land in the fork, point sampling and spawning can be integrated with them.

**Save your scene before regenerating editor-visible instances:** the
current Generate action is not yet undoable. This needs a separate follow-up
implementation and tests.

Authorship: code developed with AI assistance; integration and user-facing
usability should be reviewed in a real editor before merging.
