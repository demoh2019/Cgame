# Crouch / stealth stance

Hold **Ctrl** to crouch in both offline and online worlds. Crouching lowers
walking speed to **55%**. Holding Sprint at the same time does not override
the slowdown and does not consume sprint stamina. Existing cargo and fracture
speed penalties still apply.

Quiet crouching reduces infected sight range by a factor of **0.60**.
It combines with the genuine worn ghillie cloak but never lowers visual
signature below **0.35**. Sprint/gunfire noise removes all camouflage while
active. Bleeding scent, campfire light, hostile combat threat, pack alerts,
and already-chasing infected are unaffected. No PvP protection is granted.

The server owns the final movement and stealth values. Clients only request
a stance and predict it with the shared movement solver. The stance is
replicated to nearby character models and cleared on respawn; character
saves do not store it.

Regression: res://tests/test_stealth_stance.gd
Run: godot --headless --path game --script res://tests/run_all.gd
