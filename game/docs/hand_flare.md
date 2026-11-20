# Handheld night signal flare

Craft one Signal Flare from **2 T1 wood, 1 T1 cloth and 1 scrap**. At night outside the safe settlement, using the flare consumes exactly one and gives your survivor a moving warm 3D OmniLight and glowing ember for **120 seconds**. Offline: **F2**. Online: inventory's **Light signal flare**. Nearby players can also see the burning light on the replicated character model.

Light has an important survival downside: at night it makes the carrier visible to idle infected from **28 metres**, independently of ordinary camouflage. Noise, blood scent, PvP, damage and campfire effects retain their own rules. A flare is not permitted in daylight, the hub, while riding, or while another is active. Rejected attempts spend nothing, and the server alone decides when a flare can ignite.

The authoritative server owns inventory consumption, light duration, AI sight cue, and remote visual state. Fuel time is saved and validated (finite, 0–120s) for character reconnects, so relog cannot regenerate burning time. Death clears the light. Existing version-one saves without this field remain valid. No extra RPCs or engine source changes are necessary: Godot's built-in OmniLight3D powers the illumination.

Regression: `godot --headless --path game --script res://tests/run_all.gd` including `test_hand_flare.gd`.
