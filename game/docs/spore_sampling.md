# Dangerous swamp: sample and antidote loop

Swamps now offer a survival MMO reward instead of only an environmental penalty.

Create a **Sealed Spore Sample Kit** (`spore_sampler`) at a workbench from two Cloth T1, one Metal Bar T1 and one Charcoal Filter. In a yellow, red or black *swamp* on dry land, the inventory's **Sample swamp spores** action consumes the kit and yields **2 hazardous spore cultures**.

Sampling also adds **5 infection** before protection: actually equipped sealed expedition armor and a still-active spore filter reduce the risk. A carried, missing or stale armor ID cannot provide free protection. The server owns the real position, zone, biome, equipment, filter and result; the client cannot supply quantity, coordinates or exposure.

The **150-second** collection cooldown persists through reconnect and is strictly validated before restoring character data. Missing kits, missing slots and wrong biomes never spend inventory. Items are transferred atomically. The returned cultures can be crafted at a workbench into a **Distilled Swamp Antidote** (`spore_antidote`, heals 75 infection) from 2 cultures, 1 bandage and 1 water bottle.

No engine patch is needed; the game reuses Godot item crafting, network RPC, infection, persistence and HUD. Regression tests: `res://tests/test_spore_sampling.gd`, included in `res://tests/run_all.gd`.
