# Expedition trauma kit

A **tier-2 craftable medical kit** gives mixed-injury expedition and raid
groups a costly but convenient option for emergency care. It is an ordinary
`medical` inventory item; both self-treatment and party aid use the existing
server-authoritative transaction and survival rules.

## Crafting

At any legitimate workbench, with tier-2 crafting mastery:

| Output | Inputs |
| --- | --- |
| 1 Expedition Trauma Kit | 2 bandages, 1 field splint, 1 field antiseptic, 2 cloth T2 |

Missing materials, insufficient crafting mastery, invalid station or a full
backpack prevent crafting. Failed crafts do not consume input items.

## Treatment

One use restores **38 health** (affected by the existing self-heal skill
modifier), cures **15 infection**, immediately stops **bleeding**, and reduces
**fracture severity by 45**. Each effect respects the survival system's
normal maximum/minimum bounds. It cannot revive a dead survivor, and the server
does not charge a kit when the character has no treatable condition.

Both clients support **Shift+3** to use a kit; the regular **3** hotkey
continues using a bandage. The online inventory's **Field** section includes
a clickable self-use action, and inventory cards use the same existing
`use_item` request.

For group medicine, select **Expedition Trauma Kit** in the party **Aid**
selector and choose a nearby team member. The existing membership consent,
3.2-metre range, five-second cooldown and healer threat checks apply. Only
the medic's own carried kit is consumed, exactly once.

Unspent kits are stored by existing player inventory saves (offline solo
and account-backed play); no new RPC, native engine code or save schema
is necessary.

## Test coverage

`res://tests/test_expedition_trauma_kit.gd` covers workbench crafting,
material debit, no-effect and missing-item refusals, simultaneous treatment
of wounds, infection, bleeding and fractures, saving/loading, party
membership, range restrictions and cooldown behavior.

Run with a compiled compatible Godot/Cgame runtime:

```sh
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```
