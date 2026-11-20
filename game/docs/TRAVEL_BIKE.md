# Salvaged Trail Bike — authoritative travel

This original post-apocalyptic travel feature combines wilderness exploration
and the crafted equipment economy of an MMORPG.

**Crafting:** Build one Salvaged Trail Bike (`salvage_bike`) at the T2
workbench using 4 metal bars T2, 3 planks T2, 5 scrap metal and 4 fiber T2.
It weighs 12 kg, occupies a real inventory slot, and can drop as loot.

**Controls:** F4 toggles riding in both the offline preview and network
client. Riding moves at 1.9× walk speed (7.98 m/s without bonuses), without
sprint stamina use. The server applies regular water, collision, encumbrance
and fracture limits. Crouching cancels riding. Gathering, looting, crafting,
consumables, melee/ranged attacks, weapon skills and dodge require dismounting.

**Terrain handling:** The same shared bicycle physics runs on the dedicated
server and on predicting clients. Firm plains and the hub are fastest; trees
and roots slow riding to 90%, loose mountain stones to 78%, beach sand to 72%,
and muddy swamps to 56% before gradient penalties. Uphill slopes reduce
forward speed to a safe minimum, while descents offer at most an 8% boost.
These values come exclusively from the deterministic world seed and travel
direction, never a claimed client biome. On foot, a genuine dirt road boosts normal/sprint travel by 8%; crouched stealth stays unchanged.
The road surface also improves bike grip in mud, forests and sand, without bypassing slope or collision caps.
Only the world-seeded segment graph determines road coverage, and the shared movement logic keeps network prediction aligned.
Invalid/nonfinite movement values cannot grant free speed.

**Sound risk:** Rolling bikes produce a 27 m audible rattle, compared with
21 m for sprinting. The noise fades 0.9 seconds after stopping. It is heard
by the normal infected AI, while safe zones and NPC chase distances remain
unchanged. Blocking obstacles, stationary riders, walking pedestrians and
forged movement packets create no bike rattle.

**Combat rules:** The server rejects mounting during combat, when over-encumbered,
exhausted, injured or busy gathering. Real damage forces dismount and a 12s
remount cooldown; voluntary dismount starts a 2s cooldown. Trading or dropping
the bike immediately invalidates riding on the next server tick. Only the item
persists across sessions; riding state and cooldown do not.

**Networking:** Mount activation uses a reliable authenticated RPC.
Clients receive mount state via snapshots and use the same movement
prediction. Network movement packets never supply mount speed authority.

## Expedition cargo panniers

A T2 workbench can craft one tradeable Expedition Bike Panniers item from
4 cloth T2, 2 planks T2, 3 scrap and 3 fiber T2. The 3 kg item must remain
in the survivor's inventory along with the bicycle. While riding, its
28 kg support is subtracted from the *effective* weight used for movement
penalties. On foot, the character immediately feels the entire real load;
item counts and slots never change. The server validates ownership and
weight before mounting and every tick. A missing or lost pannier forces
dismount if the player would exceed the supported load. Full-loot death,
stash, market, trading and saved character inventory still use actual items
and actual weight. The client runs the exact same cargo calculation for
movement prediction. A mounted HUD indication shows effective support.

## Drive wear and paid servicing

One Bicycle Drive Service Kit is crafted at a workbench from 1 T1 metal bar,
2 scrap and 1 T1 cloth. Use the kit **off the bike** to service a physically
owned Salvaged Trail Bike. A paid service lasts for 800 m of actual server-
confirmed cycling on firm terrain, less in woods, mountain rocks, sand or
swamp mud. No wear occurs while idle, blocked, walking or dismounted. A
serviced drive reduces ordinary moving-bike noise from 27 m to 17 m; the
existing Quiet Chain Wrap remains the stronger temporary 9 m protection.
Once service wears out, the bicycle remains usable but becomes noisy again.
Using a second kit before service expires is refused without spending it.

Service distance is saved with the survivor, not represented as per-item
durability. Losing the bike clears the owner's remaining service distance;
trading or storing the bike does not transfer the paid service credit. Legacy
characters have zero service distance. Network packets cannot request wear
or noise radii; the authoritative server consumes only observed travel.

## Frame integrity and field repairs

The bike has a persistent, server-owned 100-point frame integrity value
separate from chain service, tire grips and cargo bags. Actual riding
distance causes gradual frame wear (more in mud, sand and mountains), while
being hit and forcibly dismounted removes 20 points. At less than 60 points
the riding pace is 86% of normal; below 25 it is 72%. A completely broken
frame cannot be ridden, but the bike remains in inventory and can be fixed.

A T2 workbench crafts a tradeable Salvaged Bike Frame Patch using 2 T2
bars, 4 scrap and 2 T2 cloth. Each patch used while dismounted restores up
to 45 integrity, capped at 100. Using a patch on an intact bike is
rejected without spending materials. On the local and online client, use
Page Down, or use the repair button in the online inventory. Server
snapshots carry only the server's current integrity; movement prediction
uses it, but client movement packets cannot author condition, hit damage
or repair output. The repair is a normal authenticated inventory command.

On login, a previously damaged bike keeps its condition. Legacy save files
without an integrity field default to 100. Discarding the bike resets its
owner-specific condition on the next server tick; a different acquired
bike therefore starts intact. Losing the bike does not keep a phantom
rideable item, and integrity never affects on-foot speed.

## Dynamo lantern — light versus stealth

Craft the tradeable Trail Bike Dynamo Lantern at a T2 workbench from one
T2 bar, three scrap and one T2 cloth. Carry it with your Salvaged Trail Bike
to illuminate a 13 m forward cone during night travel while mounted.
It switches off automatically at dawn, on dismount, on death or when lost.
No new hotkeys or engine modules are required: the same 3D model displays
the headlight and emissive lens for the rider and nearby players.

Illumination has a cost: idle infected can notice the lit survivor at up to
23 m, independently of crouch/armor camouflage but still within the normal
infected pursuit leash. Safe hubs and dead characters are protected by
existing zombie-target rules. Server inventory ownership, mount state,
survival and the shared world clock decide both AI light-reveal range and
public/private light replication; clients never send a light claim.
Night/day and inventory changes are reflected immediately in next snapshots.
Owning the lamp does not increase speed or modify normal walking physics.

## Presentation

The bicycle has a procedural low-poly 3D model: orange metal frame,
two rotating tires with hubs, saddle and handlebars. Rendered wheel rotation
uses measured motion, not untrusted network data. Local preview, online
player and remotely replicated riders use the same
`scripts/client/trail_bike_visual.gd`. Dismounting or dying hides the
bike; riding suppresses walking sounds and footstep dust. F2 help lists F4.

## Tests


`godot --headless --path game --script res://tests/run_all.gd`

`game/tests/test_bike_terrain.gd` checks slope limits, terrain grip, walking
regression, malformed movement inputs and authoritative server consistency.

`game/tests/test_mounts.gd` checks crafting data, speed bounds, server
ownership, combat restrictions, hit dismount, cooldown, acoustic aggro,
idling, malformed movement and save/load.
