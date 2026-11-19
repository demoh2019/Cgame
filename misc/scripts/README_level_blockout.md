# Offline 3D level blockout (Godot 4)

A deterministic, standard-library Python CLI for producing editable, collidable 3D greybox scenes from JSON. It is an early ProBuilder-style workflow building block, not a Godot mesh editor or PCG graph.

## Run

```
python3 misc/scripts/level_blockout.py misc/level_blockout/example.json --output /path/to/godot/project/scenes/training.tscn
python3 misc/scripts/level_blockout.py misc/level_blockout/example.json --output /path/to/godot/project/scenes/training.tscn --overwrite
python3 -m unittest discover -s misc/scripts/tests -p test_level_blockout.py -v
```

Each spec uses exactly version (integer 1), name (safe ASCII node name) and blocks (1–128 entries). Each block contains name, position [x,y,z], size [x,y,z], and optional color as #RRGGBB. Names must be unique ignoring case. Position values must be finite within +/-10000, dimensions within 0.05–1024. Each block becomes a StaticBody3D with BoxMesh/BoxShape3D and colored material. A fixed Camera3D and DirectionalLight3D make the scene viewable without extra assets. Output is deterministic and includes no external scripts or resources.

The tool refuses to replace an existing scene unless --overwrite is explicitly set, validates JSON keys, and rejects symlinks. Input files are limited to 512 KiB. Exit status 0 means scene created; 2 means an input or filesystem error. Generated scenes are not a playable game, nor is this a replacement for visual level editing, dynamic imported geometry, navmeshes or runtime profiling. A Godot headless scene-import integration check remains a follow-up.
