# Night courier premium — verified nighttime caravan travel

Cross-settlement trade routes now reward couriers who physically travel with
their promised cargo during the world night. The bonus is **20% of the base
vendor fare**, capped at 28 silver, and stacks with the existing 15% verified
caravan-ambush defense bonus. Qualified party guards still split **only the
original base fare**; there is no second escort payout.

## Gameplay

1. Accept a real caravan from a village/fort merchant and obtain its full
   quantity of cargo. The normal destination and amount remain unchanged.
2. Travel **at night** in yellow, red or black risk zones, carrying **all**
   required cargo. Green-zone or safe settlement movement does not count.
3. Make net forward progress toward the authenticated NPC destination.
   At least **25% of the route, between 80 and 160 metres**, must be logged at
   night. Distance already travelled cannot be counted again by reversing,
   walking in loops, standing still, or revisiting earlier checkpoints.
4. Deliver the real cargo at the correct merchant. The HUD shows
   `NIGHT distance/required` and the possible or already-earned silver.
   The delivery receipt separates base, defense and night premiums.

A route may be completed during daylight after qualifying during a night.
The quota is earned only once per route, never multiplied per escort.
Players can choose a safer daytime trip without any penalty to the existing
fare.

## Server ownership and anti-exploit guarantees

`scripts/shared/night_caravan.gd` computes route geometry from the existing
canonical caravan offer and stores only bounded `src_id`, `dst_id`,
`forward`, and `night_meters`. The authoritative server measures
`before_move` and `player.position` after `Movement.step` collision.
Night state and zone come from server `WorldCycle` and world geography,
not client RPC fields.

Forward progress is monotonic. The helper credits at most 4 m per movement
packet and never more than the newly reached route projection, preventing
long input packets from minting progress. Even in daylight, the farthest
forward point advances; the same terrain cannot later be retraversed to
claim nighttime credit. A cargo shortage blocks recording entirely.

The bounded route-linked night journal is saved on the character and
validated before loading any character state. Legacy active routes start
at zero night progress. Abandon, successful delivery and death clear all
unclaimed night progress; starting a new job always creates a fresh journal.

`CaravanEscortRewards.settle` stages cargo removal, original payout, the
existing ambush premium, the new night premium, and every escort wallet
before committing any inventory. A full backpack or invalid escort fails
without consuming cargo or paying silver. A successful delivery resets the
route, so replayed claims cannot pay twice.

## Tests

`tests/test_night_caravan.gd` covers day/night and zone restrictions,
missing cargo, reverse/replayed distance, fixed quota and capped rewards,
route and save tampering, courier/escort accounting, successful delivery,
repeat claim, death reset, and legacy character compatibility.
