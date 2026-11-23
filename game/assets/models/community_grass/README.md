# User-supplied Wild Grass for Albion After

`GroundPlants` can replace the old flat grass texture cards with the actual
Wild Grass meshes supplied by the game owner. The asset files are **not**
distributed through this public repository.

Run from the Cgame repository root:

```sh
python3 game/tools/install_user_wild_grass.py /path/to/wild_grass_vlkhcbxia_ue_low.zip
```

Then open `game/project.godot` in Cgame / Godot and allow imported glTF
resources to finish importing. Launch Albion After normally.

When installed, near-field `lush_grass` is rendered using the archived Wild
Grass LOD1 variants A–H through MultiMesh, with their imported alpha-masked
PBR textures and original scale/orientation. The old giant flat scanned
`grass_medium_01` / `grass_medium_02` variants are removed from the draw list.
Outside ~28 m, the old lightweight card carpet remains to keep wide-field
rendering affordable; **no opaque duplicate blades are layered on top**.
If this optional pack isn't present or fails to load, the original grass
remains unchanged.

Cgame quality presets still control grass density and culling. The LOD1
selection is deliberately conservative until measured GPU benchmarks confirm
whether ultra-dense LOD0 is affordable.

**Licensing:** Install only from an archive you have the right to use.
The original Wild Grass/Megascans assets are subject to their original
Fab licence. Do not commit, redistribute, or publish extracted files as
standalone source assets. The `wild_grass/` directory is ignored by Git.

The other uploaded `grass-clump` and `meadow-grass-patch` CC0 GLBs
currently require conversion because they declare
`EXT_meshopt_compression` and KTX2 texture extensions. They are not silently
substituted into this particular import path.
