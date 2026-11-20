# Regional wind chill

Cold weather in **Albion After** now reacts to actual seeded regional wind. This connects the new smoke-drift wind system with survival gameplay.

- Below 8°C and above 0.35 m/s, gusts add up to 22% base exposure intensity before the wet-clothes amplifier.
- Soaked clothing can raise the added intensity by up to 50%. Armor insulation reduces the effect.
- Indoor/starter-hub shelter and warm weather grant zero wind-chill penalty.
- Real temporary tarps still reduce exposure, and a burning field campfire removes it while in range.
- Thermal wraps still mitigate the final exposure intensity using the existing partial-tick duration rules.
- There is no separate damage channel, network command, inventory item or save-field migration.

The authoritative game server obtains the weather, wind, moisture and equipped armor from its own state. Only a derived, self-only wind speed and mitigated chill estimate is sent to the multiplayer HUD. The local singleplayer preview uses the identical rule.

Regression test: `game/tests/test_wind_chill.gd`, included in `game/tests/run_all.gd`.
