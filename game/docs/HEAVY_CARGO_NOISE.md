# Overloaded backpack noise

A survival/MORPG risk–reward extension for heavy gathering runs.

* Normal-load walking remains quiet; the existing 35 kg effective comfort limit and skill capacity bonuses remain authoritative.
* When a player is above the comfort threshold, **actual on-foot displacement** produces a short noise signal. Heavier loads rise from 10m to 24m detection radius, always quieter than gunfire.
* Crouching avoids load rattles at the cost of the existing reduced stealth movement speed. Bikes use their existing separate, equipment-dependent noise system.
* The server calculates weight from real inventory, measures actual collision-resolved movement, and adds the sound using the current max-radius noise channel. Stationary input, blocked movement or fake sprint commands do not create this new noise.
* The pre-existing directional regional wind affects the new footstep sound, and the infected AI's normal sight, scent, threat, pursuit leash and safe-zone rules are unchanged.
* HUD warns overloaded survivors about noisy footsteps. No network command, inventory schema, saved buff, item or engine patch is needed.

Regression suite: `game/tests/test_cargo_rattle.gd`, registered in `game/tests/run_all.gd`.
