# Market sale tax

The safe-hub survivor market charges a **3% seller-side commission** on each
successful fill. The tax is rounded **up** to whole silver, but the seller is
guaranteed at least one silver per successful sale. A 1-silver fill has no tax.
The buyer always pays the advertised gross price.

Example: selling four units at 5 silver each costs the buyer 20 silver.
The seller gets 19, and 1 silver is removed from circulation. A later partial
fill is taxed separately based on its own gross total.

This rule applies only to the online hub listing board. Direct player barter,
NPC vendor trades and listing creation remain untaxed. Listings still reserve
no items, and disconnected sellers' orders disappear.

Settlement is server-authoritative: stock, buyer funds, buyer space and
seller space are checked on cloned inventories. The sale, tax and inventory
changes all commit together; if any step fails, neither inventory is altered.
A market-buy request ID is still idempotent within its server session, and
the buyer receipt and bounded server audit record gross, tax and seller net.

Regression coverage: `game/tests/test_market_board.gd`.

Run: `godot --headless --path game --script res://tests/run_all.gd`
