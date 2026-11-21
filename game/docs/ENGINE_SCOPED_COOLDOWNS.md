# Scoped ability cooldown reconciliation (Unreal GAS-inspired)

Albion After already uses native `GameplayCooldownTracker` for server-driven
weapon, ultimate, gear and shared-global cooldown display. Full
`replace_snapshot(...)` reconciliation clears *all* tags, including
independent local timers.

## Native API

`replace_cooldown_branch("Ability", snapshot)` replaces only tags equal to
`Ability` or beginning with `Ability.`. The operation:

- validates all keys, numeric durations and resulting total capacity before
  committing; rejects invalid or nonmatching inputs without partial updates;
- removes stale ability cooldowns and zero-duration tags;
- preserves timers under `Local.*` and unrelated names such as
  `AbilityExtra.*`, including elapsed phase across snapshots;
- retains the explicit-clock `tick(delta)` contract and 256-timer cap;
- does not run abilities, replicate state or grant gameplay authority.

## Albion After

`AbilityCooldowns.reconcile_native()` calls the scoped API on new server
snapshots. On older Cgame builds, it uses the legacy whole snapshot method.
The ability bar records a short `Local.UI.Activation.<slot>` pulse for
cosmetic tap feedback; it never bypasses server-side checks or extends a
server-owned cooldown. Older builds keep their original UI behavior.

The native C++ regression is included in `test_gameplay_fx.h`. Game
fallback/native parity is in `test_native_ability_cooldowns.gd` and the
existing `native-ability-cooldowns.yml` CI workflow.

Reference: Unreal Engine Gameplay Ability System's tag-based cooldowns and
server/prediction split:
https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-the-unreal-engine-gameplay-ability-system
