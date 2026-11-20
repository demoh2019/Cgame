# Bicycle hearing, craftable quiet chain wrap

The fast Salvaged Trail Bike now creates a **27 m noise signature** during real, server-verified movement; stationary vehicles and replayed inputs make no new sound. Existing zombie hearing uses the noise like footsteps and gunfire. Sound fades after 0.9 seconds when riding stops.

Craft a **Quiet Chain Wrap** at a workbench using 2 Cloth T1, 2 Fiber T1 and 2 Scrap. Dismount and use the consumable while owning a Salvaged Trail Bike. One wrap reduces **only mounted rolling noise** to 9 m for **180 seconds**. It does not suppress gunfire, sprint footsteps, scent, visual aggro or active combat pursuit. Another wrap cannot be used until the current one wears off.

The server owns input budgets, movement, sound, carried items and the duration. The remaining duration is saved for returning accounts, bounded and validated before character mutation; old saves load without a wrap. A death/respawn clears the effect. The HUD displays a noise warning or active duration. Existing use-item RPC is reused, so the network protocol requires no additional methods.

Regression suite: `game/tests/test_bike_chain.gd` in `game/tests/run_all.gd`.
