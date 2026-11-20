# Outlaw hunting: verified PvP bounties

A hunter who defeats a **wanted outlaw** in the dangerous red or black PvP
zones receives a small server-funded silver bounty in addition to normal
loot and PvP honor. This turns the existing criminal infamy and legal
retaliation rules into an optional player-driven hunt.

## Reward brackets

| Victim's infamy | Red zone | Black zone |
| --- | ---: | ---: |
| 0–49.99 (not outlaw) | 0 | 0 |
| 50–74.99 | 15 silver | 30 silver |
| 75–99.99 | 25 silver | 40 silver |
| 100 | 35 silver | 50 silver |

- The server computes the score from the **victim's** existing character
  state before death. No client RPC can claim a bounty or choose a payout.
- Both killer and outlaw must be connected through **distinct nonempty
  authenticated account IDs**. Guests retain their normal PvP rules and honor
  but do not earn minted currency.
- A kill must have earned positive PvP honor through the existing unique-victim
  ledger. Killing the same victim/account again within **300 seconds** pays
  nothing; a same-account kill is always ineligible. Ordinary self-defense
  against a non-outlaw remains lawful but has no monetary bounty.
- Payout uses the existing server inventory, weight and stack limits.
  Overflow becomes an existing short-lived party-reserved ground bag at the
  hunter's location rather than bypassing inventory capacity.
- Only the hunter sees the `outlaw_bounty` event. No account ID, outlaw
  infamy numeric score, or private wallet data is broadcast.
- Payouts do not remove the outlaw's ordinary full-loot death bag, affect
  skills, or change criminal reputation.
- This is intentionally a bounded first iteration, not an escrow,
  global bounty board or offline-economy guarantee.

Regression coverage is in `game/tests/test_outlaw_bounty.gd` and registered
in `game/tests/run_all.gd`. Run headlessly with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
