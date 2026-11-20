# Rain-soaked clothing and field drying

Survival now tracks server-authoritative **wetness (0–100%)** separately from weather exposure and illness. Outdoors during a real regional storm, clothing gains up to **0.9 moisture per simulation second**. Worn armor reduces water absorption, but no coat makes a survivor completely rainproof.

A wet survivor gradually builds **additional cold exposure** whenever the local temperature is below 8°C, even if the storm stops. At maximum wetness, the extra pre-shelter cold severity is capped at 0.30; heavier armor reduces it. This works through the existing survival exposure and damage calculation rather than bypassing health or PvP rules.

**Drying:** outdoor clear air dries at 0.16/s; an existing safe hub or deployed field tarp protects from new rain and dries at 0.55/s; a **currently burning field campfire** dries at 2.5/s and temporarily blocks exposure while the fire lasts. Rain, equipment, shelter and campfire state are derived from the actual server world, never from client-supplied flags.

Wetness persists in the normal character save and is strictly validated before any player state changes. Old v1 saves without `wetness` load as dry. Respawn resets it. Offline status and the online HUD show moisture levels; the online client receives a private snapshot field. No new RPC, item, engine extension or save-version bump is necessary.

Tests: `godot --headless --path game --script res://tests/run_all.gd`, including `test_wet_clothing.gd`.
