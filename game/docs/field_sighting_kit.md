# Salvaged Sighting Kit — PvE ranged preparation

Craft one **Salvaged Sighting Kit** at a workbench using 1 Metal Bar T1,
2 Fiber T1 and 2 Scrap. Equip an owned ranged weapon (bow, crossbow or gun)
and press **Delete** while out of combat.

The server consumes exactly one kit and binds four charges to the exact
equipped weapon. Each confirmed ordinary ranged attack that strikes a
living infected deals **12% additional damage** and consumes one charge.
It does not apply to PvP, misses, cover, ranged skills or non-ranged gear.
Ammo is still required and paid by the ordinary weapon rules; a shot with
no ammunition cannot spend charges.

Switching or losing the sighted weapon, death and respawn discard remaining
charges. The server validates the equipment ID and integer charge count
before reading/writing character saves. Legacy version-one saves default
to no sighted preparation. Only the owner receives remaining charges in
their private snapshot. Both local and online HUDs show the count.

Regression: `game/tests/test_field_sighting_kit.gd`.
The feature uses existing Cgame/Godot APIs; no engine extension is needed.
