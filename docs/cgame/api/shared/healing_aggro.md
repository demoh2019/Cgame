# healing_aggro.gd

> Classic party-healer threat without client-defined targets or strength.

`res://scripts/shared/healing_aggro.gd`

## Overview

Classic party-healer threat without client-defined targets or strength.
Award threat only for actual server-applied HP, not cured infection, wound
treatment, rejected actions or overheal. Combat threat remains ephemeral.

## Constants

- `const HEAL_TO_THREAT := 0.75`
- `const MAX_PER_ACTION := 75.0`

## Functions

### `threat_for`

```gdscript
static func threat_for(actual_heal: float) -> float
```

Multi-target healing is summed once per infected, then capped.

### `can_credit`

```gdscript
static func can_credit(infected, medic_position: Vector3, patient_position: Vector3, patient_peer: int) -> bool
```

Only an infected already fighting the patient can react to their medic.
Neither silence nor an unrelated nearby enemy creates new aggro.

