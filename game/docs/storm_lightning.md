# Server-authored thunderstorms and lightning strikes

At exposed locations outside the safe hub, a natural storm can generate a **telegraphed lightning strike**. The authoritative world seed, weather and player positions select the ground point. Survivors get **2.8 seconds** to leave its **4m** radius or use their existing dodge immunity; a direct hit inflicts **16 environmental damage** and may dismount the rider. A death uses the usual PvP-zone death/loot rules, but lightning cannot attribute a kill to a PvP attacker.

A server-wide cooldown caps the event rate at one warning every 55 seconds when thunderstorm conditions and eligible exposed survivors exist. The simulation retries in 10 seconds if nobody is outdoors in active storm weather. The struck point is locked at the moment of warning and checked against the real weather again at impact. Distant players never receive storm coordinates.

In offline play and network sessions the danger zone appears as a violet ground disk and on the tactical radar. The HUD shows whether the player is inside the blast circle, along with the remaining wind-up. Nearby players receive lightning warning and strike log events. No client can request a bolt, choose its target, send impact coordinates or forge damage.

No new engine primitives are necessary: this uses built-in Godot 3D meshes, existing gameplay dodge, weather, hit/death rules and the current snapshot system. The warning is ephemeral (not saved); lightning damage/health is persisted by existing character saving. Tests: `godot --headless --path game --script res://tests/run_all.gd` including `test_storm_lightning.gd`.
