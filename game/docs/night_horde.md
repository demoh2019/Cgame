# Night hordes in dangerous zones

At night a server-owned timed roaming pack can spawn near survivors in **red/black full-loot zones**, using three infected in red or four in black (including brutes/spitters), subject to a global 90-enemy cap. The first attempt is at 480 seconds and later waves have a 780-second global cooldown. If no eligible player or safe terrain exists, the server retries in 60 seconds.

The deterministic terrain search rejects protected hubs, water, steep slopes, walls, existing infected, insufficient separation from actual survivors, and out-of-zone points. Hordes have a **300-second deadline** and no renewable world spawn slots; a single event may be active at once. Fleeing does not unload its members early. If the deadline expires, enemies and the event are cleaned without bonus rewards.

Killing **every original member through confirmed server combat** grants one public PvPvE trophy bag for 240 seconds, with infected cores, tier materials and silver. Missing/despawned IDs do not count as kills. The chest is **not reserved** for the killer: rival parties may fight over it in full-loot territory. Regular infected drops remain unchanged. The event's server-only membership list is never sent to clients; clients receive only proximity-filtered start/clear/expiry messages and ordinary public bag snapshots.

The online HUD announces the horde and its shared trophy, the offline HUD shows remaining enemies and time, and a world label identifies the cache. No engine modifications or new RPC required.

Headless regression: `godot --headless --path game --script res://tests/run_all.gd`.
