# Camp recovery at the safe hub

Days After-style survival and the Albion After economy meet at the settlement.
At the workbench, **Z** in the local preview, or the **Rest at camp** button
in the online inventory panel, performs a server-authorized recovery.

It consumes **2 T1 wood, 1 canned food and 1 water bottle**, restoring up to
25 health, 55 stamina, 15 hunger and 15 thirst, capped by the survivor's
natural maxima. Supplies are removed only when all costs can be paid.
The action is denied when dead, remote, in recent combat, already fully
recovered or on the **90-second cooldown**.

The cooldown is attached to the character, saved in the same version-1
Nakama record and validated before applying any loaded state. Legacy records
without the field load with no cooldown. Reconnecting cannot immediately
reset it. An online client cannot choose a healing amount or override costs.

`game/scripts/shared/camp_rest.gd` holds the recovery balance while
`game/scripts/server/game_server.gd` handles authority, timers and
persistence. No Cgame engine feature is missing for this operation.

Headless regression:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

`test_camp_rest.gd` covers distance, complete ingredient checks, benefits,
cooldown, double-spend denial, save validation and older saved characters.
