# Open World Terrain — experimental editor add-on

This is the first, **bounded terrain prototype** for the Godot fork. It adds:
- An editable heightfield mesh and collision shape, saved as height arrays.
- Raise, lower, smooth and four-layer vertex-weight paint brushes in the 3D editor.
- Optional tiled textures per layer, with color fallback.
- Deterministic thermal erosion (conserves total height).
- Seeded GPU-instanced foliage scatter via MultiMesh; instances track edited heights.
- Undo/Redo for brush strokes, erosion and foliage scattering.

## Enable in the editor

1. Copy this directory to \`res://addons/open_world/\` in a Godot project (or work directly from this fork after making a project).
2. Enable **Open World Terrain** in Project > Project Settings > Plugins.
3. Open a 3D scene. In the **Open World** dock click **Create Terrain**, or add the \`OpenWorldTerrain\` custom node.
4. Select the terrain in the Scene dock. Choose **Raise**, **Lower**, **Smooth**, or **Paint** and left-drag over the terrain in the 3D viewport.
5. In the Inspector, set the four optional textures and layer colors. Press **Rebuild mesh / material** to reflect changes.
6. To scatter meshes, assign **Foliage Mesh** (for example a small tree mesh) in the Inspector, choose count and seed, then click **Scatter foliage**.
7. Save the scene. The heightfield, paint data and foliage placement are serialized using \`@export_storage\`; derived meshes and collision are regenerated on load.

## Automated tests

The \`addons/open_world/tests/test_terrain.gd\` runner exercises dimensions, material defaults, mesh and collider, height sampling, brushes, layer paint, undo serialization, deterministic erosion, and MultiMesh foliage.

From the repository root, after building Godot with tests enabled:

\`\`\`sh
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/addons"
cp -R addons/open_world "$tmpdir/addons/open_world"
printf 'config_version=5\n' > "$tmpdir/project.godot"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path "$tmpdir" --script res://addons/open_world/tests/test_terrain.gd
rm -rf "$tmpdir"
\`\`\`

The Linux build workflow runs the same suite in its sanitizer-enabled editor test matrix.

## Known limitations / planned work

- A **single heightfield** (maximum 128×128 cells), not World Partition or infinite terrain.
- The mesh and trimesh collider are rebuilt after every brush update, which is too expensive for production-scale scenes. A chunked dirty-region update system is needed.
- Paint weights are **per vertex**; high-resolution splatmaps and virtual texturing are future work.
- Foliage supports a Mesh through MultiMesh, not arbitrary PackedScene prefabs or collision per instance.
- No PCG graph, HLOD builder, water, weather or erosion via hydraulic simulation yet.
- Editing is best performed with a terrain placed without non-uniform scaling.
- The source can be reviewed without the engine binary, but correctness must be validated by Godot CI and interactive editor testing before merge.

The add-on is intentionally opt-in and makes no changes to the engine renderer or resource serialization formats.
