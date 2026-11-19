# HLOD Builder — experimental Godot 4.7+ addon

Implements the first vertical slice of **#6 HLOD Builder** in
[issue #61](https://github.com/demoh2019/Cgame/issues/61).

Unlike an engine-wide HLOD system, this opt-in editor addon is designed to be
isolated from the core renderer and from experimental terrain formats under
review in other PRs.

## Features

- `HLODCluster3D`: a scriptable Node3D class with a Build/Clear button in
  Inspector and a dedicated HLOD Builder editor dock.
- Discovers eligible visible MeshInstance3D descendants (excluding its own
  proxy and nested HLOD clusters).
- Provides two modes: **Merged Geometry** batches full source triangles by active material; **Bounds Proxy** replaces each source mesh with a coarse 12-triangle bounding box, while preserving one active material per source. The generated mesh is a persistent `__HLOD_PROXY__` child in saved scenes.
- Preserves material grouping, normals, UVs and vertex colors. Transforms
  vertices correctly for nested origins and nonuniform scales; handles
  negative determinant transforms by reversing triangle winding.
- Generates vertex normals for sources that don't provide them.
- Runtime near/far visibility switching based on the active Camera3D,
  with distance-based hysteresis and an adjustable check interval.
- Keeps collision and scripts active while switching only rendered meshes.
- Rejects missing geometry, non-triangle primitives, singular transforms,
  malformed vertex buffers and oversized inputs. Failed rebuilds preserve the
  most recent generated proxy.

## Getting started

1. Open `misc/hlod_builder` in Godot 4.7+ as a project, or copy
   `misc/hlod_builder/addons/hlod_builder` into another project's `addons`.
2. Enable **HLOD Builder** under **Project Settings → Plugins**.
3. Add **HLODCluster3D** to a scene, then put static MeshInstance3D objects
   under the cluster (including nested Node3D transforms).
4. Select the cluster, click **Build HLOD Proxy** in Inspector or
   **Build selected cluster** in the HLOD Builder dock.
5. Choose `proxy_mode` — **Merged Geometry** for shape preservation or **Bounds Proxy** for a much cheaper but visually coarse distant proxy.
6. Set `switch_distance` and `hysteresis` in Inspector. At runtime, objects
   switch to the merged mesh at `switch_distance + hysteresis` and revert
   below `switch_distance - hysteresis`.

Generated proxy meshes are saved with the scene if the cluster is in the
currently edited scene; for script-built clusters you may manually assign
`owner` on the generated proxy when packing a scene.

## Script API

```gdscript
var result := HLODMeshBuilder.build(cluster, 100000, false) # true = bounds proxy
if result["ok"]:
    print(result["source_count"], result["vertex_count"])
cluster.build_proxy()
cluster.update_for_camera_position(Vector3(100, 0, 0))
print(cluster.is_using_proxy())
cluster.clear_proxy()
```

`HLODMeshBuilder.build()` returns a Dictionary containing `ok`, `error`,
`mesh`, `source_count`, `surface_count`, and `vertex_count`.

## Tests

Using an official Godot 4.7.2 editor binary:

```sh
godot --headless --path misc/hlod_builder --editor --import --quit
godot --headless --path misc/hlod_builder --script res://tests/test_hlod_builder.gd
godot --headless --path misc/hlod_builder --script res://tests/benchmark_hlod.gd
```

The headless suite includes 15 integration groups and 95+ assertions on
geometry merging, materials, attributes, transform composition, triangle
winding, normals, budgets, singular transforms, nested clusters,
hysteresis, scene serialization and proxy replacement. GitHub Actions
runs these checks using the pinned official binary and SHA-256 digest. The benchmark reports per-scenario source count, proxy surfaces, vertices, triangles and CPU build duration for 16/64/256/512 box meshes; it does not claim GPU FPS or production memory improvements.

## Limitations — do not call this full HLOD yet

Merged Geometry **does not reduce polygon count**; it reduces draw calls only
when source meshes share active materials. Bounds Proxy does reduce polygons,
but replaces detailed geometry with crude bounding boxes and is not a
production-quality simplification algorithm. Both modes may increase memory
usage because source geometry and proxy geometry coexist. It doesn't build multiple HLOD tiers or spatial clusters
automatically and doesn't yet provide mesh simplification, dithered
cross-fades, occlusion culling, WorldPartition streaming integration or
per-camera multi-viewport policies. Switching only visuals means original
physics stays active at distance.

Editor rebuild is currently not UndoRedo-aware. Save scenes and use version
control before rebuilding. Dynamic, skinned, blended or animated meshes are
**not suitable** for proxy compilation. Subsurface custom attribute streams,
blend shapes, tangents and mesh-specific shader effects are not preserved.
Tests and renderer/OS verification must pass before merging.

Later phases: authored low-poly source meshes, spatial grouping,
multi-tier LOD, mesh reduction, LOD streaming, memory instrumentation and
Terrain/WorldPartition/PCG integration. This PR covers only a **subset** of
the 48-direction issue #61, not the entire roadmap.

Implementation authored with AI assistance; maintainer review required.
