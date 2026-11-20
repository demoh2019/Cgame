# Regional NPC trading demand

Settlements on the island now have **deterministic resource demand**, inspired by sandbox MMO trade runs. Every named village/fort with a trader and workbench has one preferred raw commodity: **fish, ore, fiber, wood or stone**. Matching raw resources sell for a premium of **35–75%**, higher on risky travel routes. Settlement prices are stable for the world seed; the island map shows each settlement's demand on hover, and the inventory HUD shows the demand when standing at the trader.

To sell at this premium, physically deliver gathered goods to the settlement's workbench. The server verifies the player's actual position against generated station coordinates, calculates the quote and commits the resource-to-silver transfer atomically through the existing NPC vendor logic. Market selling, refined materials, PvP prices, purchases, outposts without NPC traders, and the starting hub retain their original economics.

No NPC offers regional goods for purchase, so players cannot profit from an NPC buy/sell loop. The maximum unit premium is capped to 75%; the server owns the quote, not an RPC parameter. Invalid prices and full bags cannot duplicate money. Trade remains risky through the existing transport, encumbrance and red/black full-loot PvP systems.

The UI automatically displays named settlement demand and premium on the world map, in the online survivor status and in offline mode. No new network command or save migration is necessary.

Run `godot --headless --path game --script res://tests/run_all.gd`; the new `test_regional_trade.gd` suite covers real settlements, seeded demand, balance settlement, anti-replay and pricing limits.
