# Noisy harvesting and quiet foraging

Crafting and gathering now involve a stealth tradeoff. Completed resource
harvesting creates an authentic short-lived sound event tied to the actual
survivor and heard by nearby infected. The **server**, not a client, decides
whether work was completed and how far the sound carries.

| Resource node | Hearing radius |
| --- | ---: |
| Trees / chopping | 25 metres |
| Rock / stone breaking | 24 metres |
| Ore / metal mining | 28 metres |
| Fiber bushes | 8 metres |
| Berry bushes | 6 metres |

Crouching decreases **only soft foraging noise** by 45%. Axes and pickaxes
remain loud regardless of posture, equipment or weather. The sound remains
audible for 1.1 seconds after a completed harvest and uses the existing
infected hearing channel. Actual enemy acquisition still respects NPC chase
range, safe settlement boundaries, alive state, sound vs. visual camouflage,
and existing combat target priority.

Only the **primary items successfully added to inventory** can trigger the
sound; empty, invalid and repeated/depleted nodes cannot create a new event.
The same work also retains existing gathering XP, medicine herb drops,
outpost yield bonuses, and item carrying rules.

A prior key collision is also resolved: **F9 = smoke charge**, **F10 =
signal flare**, and **F11 = herbal poultice** in both offline and online
controls. The remedy is still usable by clicking it in the inventory.

## Tests

`godot --headless --path game --script res://tests/run_all.gd`

`game/tests/test_gathering_noise.gd` verifies the exact radii, survivor
posture, a genuine server harvest, real infected target acquisition,
depletion replay rejection, idle sound expiry, and no post-expiry reacquisition.
