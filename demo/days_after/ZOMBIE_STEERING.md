# Days After: infected local steering

Zombies in the playable survival prototype use lightweight **physics-raycast
steering** to walk around nearby walls. The steering works with the existing
collision geometry and requires no navigation mesh or additional Cgame APIs.

## Behavior

- Acquire a living survivor within 19 metres.
- Probe in the desired movement direction for terrain/structure collision.
- When blocked, select a freer side and maintain it briefly so steering does
  not jitter between left and right.
- Stop and attack only within melee range **and** with clear line of sight,
  preventing hits through solid level geometry.

This is **not** full A* or navigation mesh pathfinding: large dead ends,
multi-room interiors, vertical links and complex crowd movement still need a
dedicated navigation solution. Longer-term, prefer NavigationAgent3D and
baked/streamed navigation meshes for cross-zone pursuit.

## Regression check

```sh
<cgame-editor> --headless --path demo/days_after --script res://smoke_test_zombie_steering.gd
```

The test constructs a collision-enabled wall, spawns a zombie and a test-only
target, checks lateral movement around cover, rejects an attack through the
wall and confirms an unobstructed melee attack still damages the target.
