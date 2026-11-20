# Fresh corpses and infected scent investigation

Recent kills now create a new tactical risk in this survival MMORPG.
Loot from a **confirmed infected kill** or **full-loot player death**
retains a blood trail for up to **40 seconds**. Idle nearby infected
within **22 metres** investigate the location, even after the killer
has retreated. Corpse loot is still subject to all existing ownership
and party reservation rules.

The server alone marks genuine death bags. Ordinary scavenged crates,
dropped materials, supply loot and empty bags do not generate the cue.
Looting the bag, its normal expiration, or the scent timer removes the
attraction. Safe-zone kills are excluded.

This is a **location investigation**, not a forced aggro command or a
phantom player. Active chases, threat, confirmed survivor perception,
safe zones and raid bosses retain their existing priorities. It never
spawns additional enemies. One nine-cell spatial index is built only
on the normal timed NPC perception pass.

Both offline and multiplayer HUDs warn about a nearby fresh corpse.
Network replication contains a boolean only, never private inventory
contents, player/account identities, or scent expiry internals.

## Tests

Run `godot --headless --path game --script res://tests/run_all.gd`.

`test_corpse_scent.gd` covers world bag validation, deterministic
range search, real NPC investigations, expiry, actual loot removal,
snapshot privacy and full-loot death marking.
