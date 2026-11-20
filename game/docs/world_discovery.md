# Persistent island exploration journal

Entering the actual generated bounds of one of the island's villages, farms, forts, depots, mines, lighthouses, camps or ruined cities now yields a one-time **Explorer XP** and **Renown** reward. Values are bounded by the real danger tier: 20–65 XP and 1–4 reputation per newly visited location. Revisit, death, reconnect or server restart cannot repeat the reward. The server checks actual movement at 1-second intervals; no client discovery request exists.

The private journal tracks one site ID per seeded 256m region. Player character saves carry `discovered_sites: [{rx, rz, id}]`. On reload each bounded integer is verified against the same procedural-world region before any character inventory, reputation or progression is changed. Duplicate regions, unknown IDs, foreign seeds, NaNs and fractional numbers reject the whole restore; older version-one saves with no field are accepted as empty journals.

The online island map shows personal visited locations with gold rings, a running discovery counter, and visited/unexplored hover status. The multiplayer HUD and offline status show the cartography count; only the owner receives discovery event messages or journal IDs. All other map sites remain visible so navigation is not artificially locked.

No new engine API, RPC or migration of save version was needed. Regression: `godot --headless --path game --script res://tests/run_all.gd`, including `test_world_discovery.gd`.
