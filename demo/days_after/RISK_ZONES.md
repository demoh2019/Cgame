# Risk zones — Days After × classless sandbox

The world now has three meaningful regions, based on horizontal distance from
the starter camp centre **(0, 7)**:

| Region | Radius | Gameplay |
|---|---|---|
| Sheltered camp | <= 5 m | No infected aggression and no environmental exposure |
| Wasteland | > 5 m to < 18 m | Existing infected threats and normal harvesting |
| Exclusion | >= 18 m | Environmental damage at 2.5 HP/s and one bonus unit per successful nearby harvest |

Zones are **gameplay rules** from `risk_zone_rules.gd`, not new engine API.
Positions and other parameters are prototype balance settings. The HUD uses
`risk_zone_system.gd` and marks the active region.

`ExclusionFiber` and `ExclusionWood` are new gathering spots located outside
the starter radius. A player must be within 3.5 m of an exclusion deposit
and be in the exclusion zone to receive its bonus. Existing tier/tool/skill
gates are always applied: failing a harvest gives neither materials nor XP.
A survivor outside the exclusion zone cannot obtain extra yield by interacting
with a distant deposit. Resource nodes still exhaust and respawn normally.

The camp shelters the player from infected **aggression** and radiation. This
is not yet PvP territory enforcement, MMO faction logic, server authority or
a radiation-resistance equipment system. The zone rules are deliberately kept
data-only for deterministic testing and eventual server reuse.

## Test

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test_risk_zones.gd
```

This checks the boundaries, rate of environmental damage, finite harvest
bonuses, resource depletion and infected shelter. Run this alongside existing
gameplay and inventory smoke tests on a compiled Cgame engine.
