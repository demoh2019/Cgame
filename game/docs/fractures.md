# Heavy wounds and field splints

This Days After-inspired injury system builds on the existing bleeding and infection mechanics.

A **real damaging, nonlethal brute zombie hit** adds 35 fracture severity (capped at 100). Dodged strikes, dead victims and ordinary infected do not receive or inflict fractures. While severity exceeds zero, a survivor walks at **65% speed** (before carry/skill multipliers) and **cannot sprint**. Severity heals by 0.04 per second of server simulation; respawn clears it.

**Field Splint** uses 1 T1 plank + 2 T1 fiber + 1 T1 cloth. It can be crafted in the field and one splint repairs up to 100 fracture. Using it on a healthy survivor is denied without consuming the item. Party medics may apply a carried splint only to a nearby consenting party member, respecting the usual aid cooldown.

All injury generation, supplies and movement checks are authoritative. The server sends fractures in character snapshots and events; the client predicts movement with the matching injury factor and displays fracture in the HUD. Version-1 saved characters without a fracture field remain valid; invalid/NaN persisted severity is rejected atomically.

Run `godot --headless --path game --script res://tests/run_all.gd` to run the regression suite including `test_fractures.gd`.
