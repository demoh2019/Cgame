# Improvised Smoke Charge

Craft from 2 cloth T1 and 1 scrap at a workbench. Use from the inventory or
press F9. This creates a 9-second, 4.5-metre-radius cloud at the player's
actual server position, reducing first-time **visual** detection by a factor
of 0.52 for quiet survivors, never lower than the 0.35 visibility floor.

Smoke does not break existing infected target/threat/pack alert, block
hearing, scent or firelight, prevent PvP damage, protect from acid or heal.
Deployment itself makes a brief quiet sound; to hide, let it subside.
Ghillie suits, crouching and temporary field tarps stack within the cap.

Charges are paid for before cloud creation. Server enforces 18-second
cooldown, maximum 48 clouds and one active cloud per owner. Only nearby
players see the anonymous cloud and its expiration; no player/account IDs
or permanent state are saved. Offline and multiplayer use identical rules.

Regression command:
godot --headless --path game --script res://tests/run_all.gd
