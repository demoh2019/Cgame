# Directional infected hearing

Regional weather is now tactically relevant beyond smoke drift and cold exposure.

- In clear weather or calm wind, the existing noise radius is unchanged.
- Strong gusts carry actual sprint, attack and gathering noise farther **downwind**, while making that same sound harder to hear **upwind**.
- A crosswind has little effect. The maximum hearing change is ±25%, and the infected pursuit leash remains an absolute cap.
- Silent players do not generate sound from wind alone.
- Vision, blood scent, firelight, combat threat and pack alert rules are unchanged. Wind only affects initial passive sound detection; it never cancels an active chase.
- The authoritative server computes regional wind at each survivor's real position, then passes it to infected AI internally. Clients never supply wind, noise multipliers, or enemy target IDs.

Regression coverage: `game/tests/test_wind_hearing.gd`, registered in `game/tests/run_all.gd`. Godot can run the suite with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
