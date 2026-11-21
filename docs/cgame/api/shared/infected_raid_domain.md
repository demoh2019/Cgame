# infected_raid_domain.gd

> Example data for the AI planners.

`res://scripts/shared/infected_raid_domain.gd`

## Overview

```text
Example data for the AI planners. Data only, no behaviour.
 - htn_domain(): raid boss decision tree for HTNPlanner (Horizon-style):
   enrage when low health, summon adds when surrounded, else charge/slam.
 - goap_actions(): scavenger infected for GOAPPlanner (F.E.A.R.-style):
   find food, eat, or flee when threatened.
```

## Functions

### `htn_domain`

```gdscript
static func htn_domain() -> Dictionary
```

### `goap_actions`

```gdscript
static func goap_actions() -> Array
```

