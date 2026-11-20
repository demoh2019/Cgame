# Ruin cache ambushes

Opening a genuine **red (T3) or black (T4) ruin crate** can awaken an infected
pack. Opening its sealed compartment with a real consumed lockpick **always**
provokes a pack if safe spawn sites and capacity exist. Otherwise each
crate has a stable **35% red / 60% black** awakening chance from its
generated ID and world seed; clients never choose the result.

The server spawns up to **two infected in red zones** or **three in black**,
on collision-checked dry terrain at least **12 metres from living players**.
Enemies use ordinary targeting, combat and loot, while the opener receives
an immediate warning (online party members also get an alert). Defeating
**every original summoned infected** before expiry sends a one-time
\`Ruin secured\` confirmation to the opener and party; despawns and missing
entities never count as victory. **Q** loots
nearby caches in the solo preview and **E** interacts in the online client.

A repeated request to an already-open cache cannot create another wave.
A 90-second global cooldown, three-active-wave cap and 88-infected population
cap bound the encounter. Active raid bosses and night hordes suppress new
ruin waves. After **150 seconds** the temporary enemies expire rather than
occupying renewable world spawn slots. If there is no safe spawn site, loot
still succeeds without a new wave.

This behavior runs entirely within the existing authoritative game loop.
It creates no extra guaranteed treasure, modifies no character save schemas
or RPCs, and needs no engine modification.

Run regression checks:

```sh
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

The new `res://tests/test_ruin_ambush.gd` suite covers risk rolls, forged
crate requests, actual lockpick and loot consumption, spawn geometry,
bounded events and population, replay/cooldown resistance and expiry.
