# Navigation BVH hot-path performance

## What changes

Godot upstream #125543 adds a bounding-volume hierarchy (BVH) for finding
the closest start and end navigation polygons in 2D and 3D, replacing a full
scan of large regions. Regions with eight or fewer polygons still use the
original linear scan and allocate no BVH data.

Cgame also avoids `sqrt()` in BVH bounding-box traversal: it compares
squared distances and squared pruning thresholds. The search retains its
rounding slack, near-first traversal, and tie-breaking rules. Closest-point
distances for actual polygon faces still use their original arithmetic.

## Verification

Build the engine with `tests=yes` and the navigation modules enabled, then
run native cases with the appropriate engine binary:

```sh
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[NavigationBVH2D]*"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[NavigationBVH3D]*"
```

The supplementary `tests/servers/test_nav_polygon_bvh.cpp` suite compares
actual BVH query results with a full polygon scan, including 1,024-polygon
grids, tie-breaking, small-region fallback, rebuild/reset, and preexisting
nearest-polygon results.

Its two benchmark cases time 512 queries on the same 1,024-polygon input
against an exhaustive scan, using `OS::get_ticks_usec()`. Output includes
elapsed microseconds and the persistent BVH node/index memory footprint in
bytes. **No speedup threshold is asserted**; benchmark results require a
native build and matched machine conditions.

Run the fast integration checks separately:

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_navigation_bvh_upstream.py -v
```

## Memory trade-off

BVH node capacity is preallocated to the exact median-split node count, avoiding
reallocations during construction and excess persistent node capacity.

The BVH requires extra per-region memory for nodes and polygon indices; it
also uses transient per-polygon bounding boxes while building. The
`get_size_bytes()` value reports the persistent node/index capacity only.
For small regions (at most eight polygons), the persistent BVH is empty.
Measured speed and RAM effects depend on mesh geometry, region sizes, scene
churn, query patterns, and CPU/allocator behavior.
