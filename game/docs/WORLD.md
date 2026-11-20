# The world

One island, 6.4 km across (`WorldGen.WORLD_RADIUS` = 3200 m), cut from the seed: the server and every client build the same land, the same
places and the same people, so nothing of it travels over the network.

* **Land.** Continent, hills and mountains from noise, raised by `LAND_BIAS` so that about half of the island is dry and 99% of the land can be
  walked to from the hub (checked on seven seeds); the edge sinks into the sea. Terrain is levelled under every site.
* **Places** (`scripts/shared/world_poi.gd`): the island is cut into 256 m regions and almost every one holds a site: **village**, **farm**,
  **camp**, **depot**, **fort** (outpost), **watchtower**, **mine**, **ruined city**, **bunker**, **lighthouse**, **dock**; about 190 in all, with
  generated names (Hollowwatch Village, Ruins of Kingsford, Fort Stormhollow). What appears depends on the zone: villages and farms near the
  hub, forts and cities beyond, bunkers and big ruins in the black zone, docks and lighthouses on the coast, mines in the mountains.
* **Contents.** Houses, palisades, towers, props (barrels, crates, benches, tables), loot crates, ore, zombie packs and **people**: traders,
  guards, villagers, farmers, miners, fishers, survivors by a fire and lookouts, each with a name, a role and an animation. Villages and forts
  have a **workbench and a trader**: crafting, the vendor and contracts work there as at the hub (the bank, the market and camp rest stay in the hub).
* **Names and map.** Walking into a place shows its name; between places the area's name appears (Whispering Pines, Broken Crags ...).
  **J** opens the map of the island with the danger rings, every place (hover for details), the siege outposts and you.
* **Cost.** A chunk takes about 1.5 ms to build; terrain height is one cached lookup per 256 m region, so it is no slower than before.
* Entity ids are built from the chunk coordinates (no hash collisions), props block movement through the same collision list as everything else.

Tests: `tests/test_world_sites.gd` (24 000 checks: island, sites, contents, chunks, stations, determinism).

## Roads and landmarks

* **Roads** (`scripts/shared/world_roads.gd`): every place people built is joined to its two nearest neighbours and the hub to its four, about 345
  winding dirt roads (77 km) on seed 1337, stopping at the shore. Each road has **signposts** near both ends naming the place at the other end and the
  distance. Roads are scenery: the ground shader paints them from a per-chunk mask, the map draws them, movement is unchanged.
* **Landmarks** fill the regions without a settlement: **Stone Circle** (standing stones round an offering chest), **Crystal Grove** (giant crystals and
  crystal ore), **Great Tree** (a 21 m tree with a hermit and a chest), **Old Shrine** (pillars, braziers, an altar chest and a keeper) and **Battlefield**
  (wreckage, supplies and many infected). They count as places for discovery, the map and the banners.
* **Trees by biome**: forests mix broadleaf trees, pines and the painted trees; swamps get dead and twisted trees; mountains pines.
