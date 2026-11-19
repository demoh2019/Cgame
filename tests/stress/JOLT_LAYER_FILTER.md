# Jolt collision-layer pair filtering optimization

Cgame stores Godot's directional 32-bit collision layer and mask as a packed
64-bit value for each of the at most 8192 unique collision configurations in a
Jolt physics space. Each Jolt ObjectLayer encodes the configuration index in
its lower 13 bits and a broadphase class in its upper 3 bits.

Previously the hot **ObjectLayerPairFilter::ShouldCollide()** callback decoded
both complete object layer values through `from_object_layer()`, including two
unused broadphase classes and four output parameters. It now extracts the two
13-bit indices and checks the 64-bit packed layer/mask values directly, without
changing Godot's directional collision semantics:

```
collides = (mask1 & layer2) != 0 || (mask2 & layer1) != 0
```

The layer/mask-to-index registry uses an open-addressed `AHashMap` instead of
the node-based `HashMap` so newly assigned collision configurations can be
looked up more compactly. The vector of packed collision combinations is
unchanged; the 8192-configuration hard bound remains.

## Correctness

```sh
python3 -m unittest tests/stress/test_jolt_layer_pair_filter.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_layer_filter_regression.gd
```

The Python contracts check the two-way OR rule against the old implementation
for 10,000 seeded randomized 32-bit masks and several asymmetric high-bit
cases. The runtime test launches separated static floors and moving spheres:
bidirectional, unilateral ball-to-floor, excluded and upper-32-bit layer cases.
Matching pairs must stop while excluded pairs must pass through.

In CI the test selects the **Jolt Physics** backend explicitly and stores a
log. Python contracts alone do not prove native C++ compilation or runtime
correctness.

## Performance measurement

Benchmark identical large collision candidate workloads with the same machine,
compiler flags and 3D physics backend before/after the change. The relevant
metric is **time spent filtering object-layer pairs** and resulting physics tick
time, not the number of collisions accepted (which should be identical). No
numerical speedup is claimed until a native run confirms it.

This optimization does not increase the number of bodies supported by Jolt;
its `max_bodies`, body pairs and contact buffers require separate sizing for
very large worlds.
