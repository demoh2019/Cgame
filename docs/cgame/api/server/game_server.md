# game_server.gd

> The authoritative simulation of the world: players, zombies, resources, loot and the rules that connect them.

`res://scripts/server/game_server.gd`

## Overview

The authoritative simulation of the world: players, zombies, resources, loot and the rules that
connect them. It has no networking and no scene: the network layer only feeds it commands and
reads snapshots out of it, so the whole game can be tested by calling it directly.

## Constants

- `const LagCompensation = preload("res://scripts/server/lag_compensation.gd")`
- `const HTNPlanner = preload("res://scripts/shared/htn_planner.gd")`
- `const InfectedRaidDomain = preload("res://scripts/shared/infected_raid_domain.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const Vendor = preload("res://scripts/shared/vendor.gd")`
- `const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")`
- `const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")`
- `const CombatLogout = preload("res://scripts/shared/combat_logout.gd")`
- `const TrainingDuel = preload("res://scripts/shared/training_duel.gd")`
- `const ArenaRating = preload("res://scripts/shared/arena_rating.gd")`
- `const ArenaMatchmaking = preload("res://scripts/shared/arena_matchmaking.gd")`
- `const PvPHonor = preload("res://scripts/shared/pvp_honor.gd")`
- `const OutlawBounty = preload("res://scripts/shared/outlaw_bounty.gd")`
- `const PlayerTrade = preload("res://scripts/shared/player_trade.gd")`
- `const Party = preload("res://scripts/shared/party.gd")`
- `const PartyFocus = preload("res://scripts/shared/party_focus.gd")`
- `const PartyFlank = preload("res://scripts/shared/party_flank.gd")`
- `const RallyStandard = preload("res://scripts/shared/rally_standard.gd")`
- `const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")`
- `const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")`
- `const LootRights = preload("res://scripts/shared/loot_rights.gd")`
- `const LootSweep = preload("res://scripts/shared/loot_sweep.gd")`
- `const DeathRecovery = preload("res://scripts/shared/death_recovery.gd")`
- `const PartyCorpseRescue = preload("res://scripts/shared/party_corpse_rescue.gd")`
- `const PartyAid = preload("res://scripts/shared/party_aid.gd")`
- `const PartyMedicMastery = preload("res://scripts/shared/party_medic_mastery.gd")`
- `const CampProvisions = preload("res://scripts/shared/camp_provisions.gd")`
- `const QuickMedicine = preload("res://scripts/shared/quick_medicine.gd")`
- `const SmartProvisions = preload("res://scripts/shared/smart_provisions.gd")`
- `const PartySupplyRequest = preload("res://scripts/shared/party_supply_request.gd")`
- `const PartyTriage = preload("res://scripts/shared/party_triage.gd")`
- `const RestorationStaff = preload("res://scripts/shared/restoration_staff.gd")`
- `const HealingAggro = preload("res://scripts/shared/healing_aggro.gd")`
- `const MedicCover = preload("res://scripts/shared/medic_cover.gd")`
- `const Threat = preload("res://scripts/shared/threat.gd")`
- `const FinishingStrike = preload("res://scripts/shared/finishing_strike.gd")`
- `const SunderMark = preload("res://scripts/shared/sunder_mark.gd")`
- `const TerritoryControl = preload("res://scripts/shared/territory_control.gd")`
- `const SiegeContracts = preload("res://scripts/shared/siege_contracts.gd")`
- `const OutpostFortification = preload("res://scripts/shared/outpost_fortification.gd")`
- `const OutpostProvisions = preload("res://scripts/shared/outpost_provisions.gd")`
- `const OutpostBreach = preload("res://scripts/shared/outpost_breach.gd")`
- `const MarketBoard = preload("res://scripts/shared/market_board.gd")`
- `const Contracts = preload("res://scripts/shared/contracts.gd")`
- `const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")`
- `const CaravanAmbush = preload("res://scripts/shared/caravan_ambush.gd")`
- `const RuinAmbush = preload("res://scripts/shared/ruin_ambush.gd")`
- `const CaravanEscort = preload("res://scripts/shared/caravan_escort.gd")`
- `const CaravanEscortRewards = preload("res://scripts/shared/caravan_escort_rewards.gd")`
- `const NightCaravan = preload("res://scripts/shared/night_caravan.gd")`
- `const Skills = preload("res://scripts/shared/skills.gd")`
- `const DailyBounties = preload("res://scripts/shared/daily_bounties.gd")`
- `const SaveValidation = preload("res://scripts/shared/save_validation.gd")`
- `const StashBulk = preload("res://scripts/shared/stash_bulk.gd")`
- `const EquipmentPresets = preload("res://scripts/shared/equipment_presets.gd")`
- `const ExpeditionLoadout = preload("res://scripts/shared/expedition_loadout.gd")`
- `const Reputation = preload("res://scripts/shared/reputation.gd")`
- `const Crafting = preload("res://scripts/shared/crafting.gd")`
- `const CraftFromStash = preload("res://scripts/shared/craft_from_stash.gd")`
- `const GearSalvage = preload("res://scripts/shared/gear_salvage.gd")`
- `const FieldWhetstone = preload("res://scripts/shared/field_whetstone.gd")`
- `const FieldSightingKit = preload("res://scripts/shared/field_sighting_kit.gd")`
- `const MiningWedges = preload("res://scripts/shared/mining_wedges.gd")`
- `const FieldArmorPlate = preload("res://scripts/shared/field_armor_plate.gd")`
- `const Survival = preload("res://scripts/shared/survival.gd")`
- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")`
- `const InfectedMeleeCover = preload("res://scripts/shared/infected_melee_cover.gd")`
- `const FlankSlotReservations = preload("res://scripts/shared/flank_slot_reservations.gd")`
- `const BarricadeBallistics = preload("res://scripts/shared/barricade_ballistics.gd")`
- `const SiegeCharge = preload("res://scripts/shared/siege_charge.gd")`
- `const SiegeDefusal = preload("res://scripts/shared/siege_defusal.gd")`
- `const SiegeBlastBrace = preload("res://scripts/shared/siege_blast_brace.gd")`
- `const Mounts = preload("res://scripts/shared/mounts.gd")`
- `const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")`
- `const TrailBackpack = preload("res://scripts/shared/trail_backpack.gd")`
- `const CargoRattle = preload("res://scripts/shared/cargo_rattle.gd")`
- `const RoadTravel = preload("res://scripts/shared/road_travel.gd")`
- `const BikeChain = preload("res://scripts/shared/bike_chain.gd")`
- `const BikeService = preload("res://scripts/shared/bike_service.gd")`
- `const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")`
- `const BikeLantern = preload("res://scripts/shared/bike_lantern.gd")`
- `const BikeGrip = preload("res://scripts/shared/bike_grip.gd")`
- `const Evasion = preload("res://scripts/shared/evasion.gd")`
- `const TreeAmbush = preload("res://scripts/shared/tree_ambush.gd")`
- `const InfectedPounce = preload("res://scripts/shared/infected_pounce.gd")`
- `const DataLayers = preload("res://scripts/shared/data_layers.gd")`
- `const Brawl = preload("res://scripts/shared/brawl.gd")`
- `const MeleeParry = preload("res://scripts/shared/melee_parry.gd")`
- `const ParryRiposte = preload("res://scripts/shared/parry_riposte.gd")`
- `const StaggerFinisher = preload("res://scripts/shared/stagger_finisher.gd")`
- `const ArcaneAbilities = preload("res://scripts/shared/arcane_abilities.gd")`
- `const Swimming = preload("res://scripts/shared/swimming.gd")`
- `const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")`
- `const WorldEncounterDirector = preload("res://scripts/shared/world_encounter_director.gd")`
- `const PlayerPresenceGrid = preload("res://scripts/server/player_presence_grid.gd")`
- `const PackNeighborSelection = preload("res://scripts/shared/pack_neighbor_selection.gd")`
- `const HousePieces = preload("res://scripts/shared/house_pieces.gd")`
- `const AntisepticEdge = preload("res://scripts/shared/antiseptic_edge.gd")`
- `const Combat = preload("res://scripts/shared/combat.gd")`
- `const GearDurability = preload("res://scripts/shared/gear_durability.gd")`
- `const Enchanting = preload("res://scripts/shared/enchanting.gd")`
- `const GearSkills = preload("res://scripts/shared/gear_skills.gd")`
- `const ReturnRate = preload("res://scripts/shared/return_rate.gd")`
- `const MarketBids = preload("res://scripts/shared/market_bids.gd")`
- `const Factions = preload("res://scripts/shared/factions.gd")`
- `const Farming = preload("res://scripts/shared/farming.gd")`
- `const GuildBank = preload("res://scripts/shared/guild_bank.gd")`
- `const GuildAlliances = preload("res://scripts/shared/guild_alliances.gd")`
- `const Scavenging = preload("res://scripts/shared/scavenging.gd")`
- `const HerbalForaging = preload("res://scripts/shared/herbal_foraging.gd")`
- `const WoundSealant = preload("res://scripts/shared/wound_sealant.gd")`
- `const GatheringNoise = preload("res://scripts/shared/gathering_noise.gd")`
- `const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")`
- `const ProspectingChart = preload("res://scripts/shared/prospecting_chart.gd")`
- `const SurveySignal = preload("res://scripts/shared/survey_signal.gd")`
- `const ThreatScan = preload("res://scripts/shared/field_threat_scanner.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const SiegeWaves = preload("res://scripts/shared/siege_waves.gd")`
- `const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")`
- `const RaidTempo = preload("res://scripts/shared/raid_tempo.gd")`
- `const RaidAggroView = preload("res://scripts/shared/raid_aggro_view.gd")`
- `const RaidRecovery = preload("res://scripts/shared/raid_recovery.gd")`
- `const RaidInterrupt = preload("res://scripts/shared/raid_interrupt.gd")`
- `const RaidCone = preload("res://scripts/shared/raid_cone.gd")`
- `const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")`
- `const AcidNeutralizer = preload("res://scripts/shared/acid_neutralizer.gd")`
- `const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")`
- `const GuardianIntercept = preload("res://scripts/shared/guardian_intercept.gd")`
- `const PartyShieldWall = preload("res://scripts/shared/party_shield_wall.gd")`
- `const GuardianRetribution = preload("res://scripts/shared/guardian_retribution.gd")`
- `const WardenAura = preload("res://scripts/shared/warden_aura.gd")`
- `const RaidReinforcements = preload("res://scripts/shared/raid_reinforcements.gd")`
- `const RaidWard = preload("res://scripts/shared/raid_ward.gd")`
- `const RaidLoot = preload("res://scripts/shared/raid_loot.gd")`
- `const RaidRoundRobin = preload("res://scripts/shared/raid_round_robin.gd")`
- `const RaidNeedGreed = preload("res://scripts/shared/raid_need_greed.gd")`
- `const Zombie = preload("res://scripts/shared/zombie.gd")`
- `const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")`
- `const EliteInfected = preload("res://scripts/shared/elite_infected.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")`
- `const NightHorde = preload("res://scripts/shared/night_horde.gd")`
- `const HubRecall = preload("res://scripts/shared/hub_recall.gd")`
- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const StormMud = preload("res://scripts/shared/storm_mud.gd")`
- `const StormLightning = preload("res://scripts/shared/storm_lightning.gd")`
- `const StormInsulator = preload("res://scripts/shared/storm_insulator.gd")`
- `const WetClothing = preload("res://scripts/shared/wet_clothing.gd")`
- `const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")`
- `const WadingTravel = preload("res://scripts/shared/wading_travel.gd")`
- `const WindChill = preload("res://scripts/shared/wind_chill.gd")`
- `const SporeHazard = preload("res://scripts/shared/spore_hazard.gd")`
- `const SporeSampling = preload("res://scripts/shared/spore_sampling.gd")`
- `const BloodScent = preload("res://scripts/shared/blood_scent.gd")`
- `const FieldScentMask = preload("res://scripts/shared/field_scent_mask.gd")`
- `const SoftSoleWraps = preload("res://scripts/shared/soft_sole_wraps.gd")`
- `const Camouflage = preload("res://scripts/shared/camouflage.gd")`
- `const StealthStance = preload("res://scripts/shared/stealth_stance.gd")`
- `const StealthAmbush = preload("res://scripts/shared/stealth_ambush.gd")`
- `const FieldSmoke = preload("res://scripts/shared/field_smoke.gd")`
- `const Progression = preload("res://scripts/shared/progression.gd")`
- `const WorldDiscovery = preload("res://scripts/shared/world_discovery.gd")`
- `const CampRest = preload("res://scripts/shared/camp_rest.gd")`
- `const RestedTraining = preload("res://scripts/shared/rested_training.gd")`
- `const FieldRest = preload("res://scripts/shared/field_rest.gd")`
- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")`
- `const StormproofBriquette = preload("res://scripts/shared/stormproof_briquette.gd")`
- `const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")`
- `const StormTarpAnchors = preload("res://scripts/shared/storm_tarp_anchors.gd")`
- `const CampfireThreat = preload("res://scripts/shared/campfire_threat.gd")`
- `const CampAlarm = preload("res://scripts/shared/camp_alarm.gd")`
- `const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")`
- `const HandFlare = preload("res://scripts/shared/hand_flare.gd")`
- `const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")`
- `const FlashCharge = preload("res://scripts/shared/flash_charge.gd")`
- `const EmberFlask = preload("res://scripts/shared/ember_flask.gd")`
- `const InfectedSnare = preload("res://scripts/shared/infected_snare.gd")`
- `const Fishing = preload("res://scripts/shared/fishing.gd")`
- `const ShoreFishTrap = preload("res://scripts/shared/shore_fish_trap.gd")`
- `const FishingBait = preload("res://scripts/shared/fishing_bait.gd")`
- `const StormFishing = preload("res://scripts/shared/storm_fishing.gd")`
- `const FieldWater = preload("res://scripts/shared/field_water.gd")`
- `const RainHarvest = preload("res://scripts/shared/rain_harvest.gd")`
- `const FieldCanteen = preload("res://scripts/shared/field_canteen.gd")`
- `const FrontierStim = preload("res://scripts/shared/frontier_stim.gd")`
- `const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")`
- `const TrailRation = preload("res://scripts/shared/trail_ration.gd")`
- `const FoodSafety = preload("res://scripts/shared/food_safety.gd")`
- `const CombatStress = preload("res://scripts/shared/combat_stress.gd")`
- `const PartyFeast = preload("res://scripts/shared/party_feast.gd")`
- `const PcgSpawns = preload("res://scripts/server/pcg_spawns.gd")`
- `const WORKBENCH_POSITION := Vector2(9.0, 0.0)`
- `const WORKBENCH_RANGE := 6.0`
- `const TRADE_RANGE := 6.0`
- `const TRADE_TIMEOUT := 45.0`
- `const MARKET_MAX_REQUEST_ID := 2_147_483_647`
- `const FORTIFY_MAX_REQUEST_ID := 2_147_483_647`
- `const PROVISION_MAX_REQUEST_ID := 2_147_483_647`
- `const BREACH_MAX_REQUEST_ID := 2_147_483_647`
- `const SIEGE_DECLARE_MAX_REQUEST_ID := 2_147_483_647`
- `const ZOMBIE_ACTIVE_RADIUS := 130.0 # Zombies farther than this from every player are put to sleep.`
- `const ZOMBIE_PACK_ALERT_RADIUS := 18.0`
- `const ZOMBIE_PACK_BUCKET_SIZE := 18.0`
- `const ZOMBIE_PACK_MAX_ALERTS := 12 # Per-source crowd fanout; nearest eligible targets first.`
- `const BAG_LIFETIME := 300.0`
- `const MAX_NAME_LENGTH := 20`
- `const SNAPSHOT_REPEAT_SECONDS := 2.5`
- `const SKILL_NOURISH_THRESHOLD := 90.0 # Eating or drinking above this teaches nothing.`
- `const SKILL_METERS_PER_ATHLETICS_XP := 6.0`
- `const SKILL_METERS_PER_EXPLORER_XP := 25.0`
- `const STARTER_KIT := {"bandage": 2, "canned_food": 2, "water_bottle": 2}`
- `const AI_STAGGER_MIN_POPULATION := 128`
- `const AI_STAGGER_SLOTS := 4`
- `const AI_BATCH_MAX_SIZE := 4096 # Match the native guard; larger populations use safe scalar calls.`
- `const AI_EQS_REPLAN_MIN_POPULATION := 64`
- `const AI_EQS_REPLAN_QUOTA := 8 # Regular tactical queries per authoritative tick.`
- `const AI_EQS_GLOBAL_QUOTA_US := 600 # Shared ordinary EQS CPU time per tick (soft).`
- `const AI_EQS_GLOBAL_URGENT_US := 240 # Independent bounded slot-recovery pool.`
- `const AI_CROWD_SEPARATION_MIN := 32`
- `const AI_CROWD_SEPARATION_MAX := 1024 # Native source index safety limit.`
- `const AI_CROWD_SEPARATION_TICKS := 5 # 4Hz, not every 20Hz movement tick.`
- `const AI_CROWD_SEPARATION_RADIUS := 2.5`
- `const AI_CROWD_LOOKAHEAD_SECONDS := 0.75 # Mass-style desired-velocity anticipation.`
- `const AI_CUE_NATIVE_MIN_NPCS := 32`
- `const AI_CUE_NATIVE_MIN_SOURCES := 4`
- `const AI_PERCEPTION_INTEREST_MIN_NPCS := 64`
- `const AI_PERCEPTION_INTEREST_MIN_PLAYERS := 8`
- `const AI_SNARE_BROADPHASE_MIN_NPCS := 32`
- `const AI_SNARE_BROADPHASE_MIN_TRAPS := 8`
- `const AI_SNARE_BROADPHASE_MAX_NPCS := 4096`
- `const MAX_PIECES_PER_OWNER := 80` - House pieces snap to the 3 m grid; each slot (cell edge, floor, roof, corner) holds one piece.
- `const MAX_PIECES_GLOBAL := 2500`

## Classes

- `class Player:`

## Documented variables

- `var lag_history := LagCompensation.new()` - PvP lag compensation: recent survivor positions and each peer's measured round trip (seconds).

## Functions

### `new_id`

```gdscript
func new_id() -> int
```

### `set_verified_guild`

```gdscript
func set_verified_guild(peer_id: int, backend_result: Dictionary) -> bool
```

Called only by the authoritative ENet/Nakama gateway, never an RPC.
Membership cannot be restored from client saves or assigned to guests.

### `add_player`

```gdscript
func add_player(peer_id: int, p_name: String, p_user_id: String = "", saved: Dictionary = {}) -> Player
```

### `character_data`

```gdscript
func character_data(player: Player) -> Dictionary
```

The part of a player that survives between sessions.

### `apply_character`

```gdscript
func apply_character(player: Player, data: Dictionary) -> bool
```

Restores a saved character. Returns false (and changes nothing) if the data is not usable.

### `valid_character_data`

```gdscript
func valid_character_data(data: Dictionary) -> bool
```

Check a complete saved character without modifying a live player or the spawn RNG.
The loader refuses corrupt existing accounts instead of minting a new starter kit.

### `prepare_disconnect`

```gdscript
func prepare_disconnect(peer_id: int) -> bool
```

Call before building a logout save. A live player disconnecting while
PvP-tagged in a full-loot zone drops equipment once, then respawns safely.
This applies to voluntary exits and network loss alike. Safes and PvE are
exempt; stash and character progression are never dropped.

### `remove_player`

```gdscript
func remove_player(peer_id: int) -> void
```

### `cmd_survey_ruins`

```gdscript
func cmd_survey_ruins(peer_id: int) -> Dictionary
```

A movement input measured by the client. `dt` is how long the client says it moved. The server
accepts at most as much movement time as real time has passed, so a modified client cannot speed up.
Bike ownership and eligibility are validated exclusively on the server.
Use one real chart to map the nearest unopened dangerous ruin crate.
Clients choose neither the crate nor coordinates; no guaranteed loot.

### `cmd_toggle_mount`

```gdscript
func cmd_toggle_mount(peer_id: int) -> Dictionary
```

### `submit_input`

```gdscript
func submit_input(peer_id: int, seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float, crouch: bool = false) -> void
```

### `cmd_place_fish_trap`

```gdscript
func cmd_place_fish_trap(peer_id: int) -> Dictionary
```

Fishing is a delayed, cancelable server action; no catch count is supplied
by clients. Distinct from lake drinking and free berry scavenging.
An authentic rod and procedural shore determine the maximum output tier;
client sends no location, reward or duration, only intent to place.

### `cmd_collect_fish_trap`

```gdscript
func cmd_collect_fish_trap(peer_id: int, trap_id: int) -> Dictionary
```

Authoritative pickup: no remote looting, expired nets, phantom XP or
partial inventory transfers. Rights survive authenticated reconnection.

### `cmd_fish`

```gdscript
func cmd_fish(peer_id: int, baited: bool = false, storm_cast: bool = false) -> Dictionary
```

### `cmd_dungeon`

```gdscript
func cmd_dungeon(peer_id: int, down: bool) -> Dictionary
```

Down the hatch of a bunker into its dungeon (`down`), or up the stairs of the first room back to the hatch.

### `cmd_gather`

```gdscript
func cmd_gather(peer_id: int, node_id: int) -> Dictionary
```

### `cmd_craft`

```gdscript
func cmd_craft(peer_id: int, recipe_id: String, times: int = 1, from_stash: bool = false, use_focus: bool = false) -> Dictionary
```

### `cmd_salvage_gear`

```gdscript
func cmd_salvage_gear(peer_id: int, item_id: String) -> Dictionary
```

Recycle unused equipment at the settlement workbench.
No client-provided refund amounts: recipe and inventory are server-owned.

### `cmd_arena_queue_join`

```gdscript
func cmd_arena_queue_join(peer_id: int) -> Dictionary
```

Mutual, proximity-checked hub sparring: no loot, crimes or PvP rewards.
Voluntary ranked match search. Queueing means consenting to a rated
match against a valid opponent, with existing nonlethal duel protections.

### `cmd_arena_queue_leave`

```gdscript
func cmd_arena_queue_leave(peer_id: int) -> Dictionary
```

### `cmd_duel_invite`

```gdscript
func cmd_duel_invite(peer_id: int, target_id: int, ranked: bool = false) -> Dictionary
```

### `cmd_duel_accept`

```gdscript
func cmd_duel_accept(peer_id: int) -> Dictionary
```

### `cmd_duel_cancel`

```gdscript
func cmd_duel_cancel(peer_id: int) -> Dictionary
```

### `cmd_party_invite`

```gdscript
func cmd_party_invite(peer_id: int, target_id: int) -> Dictionary
```

### `cmd_party_accept`

```gdscript
func cmd_party_accept(peer_id: int) -> Dictionary
```

### `cmd_party_decline`

```gdscript
func cmd_party_decline(peer_id: int) -> Dictionary
```

### `cmd_party_leave`

```gdscript
func cmd_party_leave(peer_id: int) -> Dictionary
```

### `cmd_party_kick`

```gdscript
func cmd_party_kick(peer_id: int, target_id: int) -> Dictionary
```

### `cmd_party_ready_start`

```gdscript
func cmd_party_ready_start(peer_id: int) -> Dictionary
```

The server determines the caller's identity and current simulation time.

### `cmd_party_ready_answer`

```gdscript
func cmd_party_ready_answer(peer_id: int, ready: bool) -> Dictionary
```

### `cmd_medic_cover`

```gdscript
func cmd_medic_cover(peer_id: int) -> Dictionary
```

Panic button for medics: ask the nearest real, armed guardian to cover them.
No client-controlled enemy IDs, guardian IDs, range, aggro, threat or damage.
Only currently engaged non-boss infected with genuine medic attention qualify.

### `cmd_party_supply_request`

```gdscript
func cmd_party_supply_request(peer_id: int, need: String) -> Dictionary
```

A trusted survival check broadcasts only a genuine low-supply request
to the current party. The client supplies neither coordinates nor level.

### `cmd_party_aid`

```gdscript
func cmd_party_aid(peer_id: int, target_id: int, item_id: String) -> Dictionary
```

Item-powered party medicine and provisions, resolved only on the server.

### `cmd_party_provision`

```gdscript
func cmd_party_provision(peer_id: int, target_id: int, kind: String) -> Dictionary
```

Transfer only known real provisions between living party allies by ONE
actual campfire. This reuses the aid cooldown and inventory save flags.

### `cmd_party_triage`

```gdscript
func cmd_party_triage(peer_id: int) -> Dictionary
```

One authenticated medic spends one crafted pack for up to three injured
current teammates. Target selection is never client-authored.

### `cmd_party_feast`

```gdscript
func cmd_party_feast(peer_id: int, item_id: String) -> Dictionary
```

Expedition support: one real cooked fish per eligible party member.
The client only picks a recipe, not recipient count, fire or bonus strength.

### `cmd_party_standard`

```gdscript
func cmd_party_standard(peer_id: int) -> Dictionary
```

A real item-paid rally standard. Clients never set location, recipients,
recovery strength, or its deadline; all rules use the live server party.

### `cmd_party_ping`

```gdscript
func cmd_party_ping(peer_id: int, x: float, z: float) -> Dictionary
```

Secure, ephemeral tactical marker; movement and rewards are unaffected.

### `cmd_party_corpse_rescue`

```gdscript
func cmd_party_corpse_rescue(peer_id: int) -> Dictionary
```

No position, bag ID or payout is client-selected. Even a dead member
may ask their existing party to help recover lost equipment.

### `cmd_party_rally`

```gdscript
func cmd_party_rally(peer_id: int) -> Dictionary
```

### `cmd_party_focus`

```gdscript
func cmd_party_focus(peer_id: int) -> Dictionary
```

Leader marks the closest currently living infected in real server space.
No client-specified target, range, damage, position or enemy identity.

### `cmd_party_loot_mode`

```gdscript
func cmd_party_loot_mode(peer_id: int, mode: String) -> Dictionary
```

Only the authenticated party leader configures FUTURE raid loot bags.

### `cmd_raid_vote`

```gdscript
func cmd_raid_vote(peer_id: int, bag_id: int, choice: String) -> Dictionary
```

Every ballot is validated against a frozen server entitlement list.
Voters must be nearby living survivors; no client-provided identity,
loot contents, roll value, winner or deadline is accepted.

### `cmd_outpost_provision`

```gdscript
func cmd_outpost_provision(peer_id: int, site_id: int, request_id: int) -> Dictionary
```

Bounded resource convoys. Monotonic request IDs cache the result of every
command, so duplicated network packets cannot spend or extend twice.

### `cmd_outpost_fortify`

```gdscript
func cmd_outpost_fortify(peer_id: int, site_id: int, request_id: int) -> Dictionary
```

### `cmd_outpost_breach`

```gdscript
func cmd_outpost_breach(peer_id: int, site_id: int, request_id: int) -> Dictionary
```

### `cmd_siege_declare`

```gdscript
func cmd_siege_declare(peer_id: int, site_id: int, request_id: int) -> Dictionary
```

### `release_pair_commit`

```gdscript
func release_pair_commit(tx: String) -> void
```

The backend confirmed (or finally gave up on) a settlement: the two players may trade again.

### `cmd_trade_invite`

```gdscript
func cmd_trade_invite(peer_id: int, target_id: int) -> Dictionary
```

### `cmd_trade_offer`

```gdscript
func cmd_trade_offer(peer_id: int, trade_id: int, item_id: String, count: int) -> Dictionary
```

A zero count removes an offer line. Every change clears BOTH confirmations.

### `cmd_trade_accept`

```gdscript
func cmd_trade_accept(peer_id: int, trade_id: int, revision: int) -> Dictionary
```

The revision is the number from the latest trade event. Stale confirmation
packets cannot accept a new or changed proposal.

### `cmd_trade_cancel`

```gdscript
func cmd_trade_cancel(peer_id: int, trade_id: int) -> Dictionary
```

### `cmd_enchant`

```gdscript
func cmd_enchant(peer_id: int, item_id: String) -> Dictionary
```

The hub's workbench or the one of a settlement (village, fort) out in the world. Crafting, the vendor and contracts work at
either; the bank, the market and camp rest stay in the hub's safe zone.
Albion-style enchanting at a workbench: runes / souls / relics plus a silver fee raise one
carried piece of gear to its next enchantment level (.1, .2, .3).

### `cmd_repair_gear`

```gdscript
func cmd_repair_gear(peer_id: int) -> Dictionary
```

Albion-style gear repair: at a workbench, pay silver to restore every damaged
carried item to 100% durability. Costs scale with item value and wear.

### `cmd_market_list`

```gdscript
func cmd_market_list(peer_id: int) -> Dictionary
```

### `cmd_alliance`

```gdscript
func cmd_alliance(peer_id: int, action: String, target_peer: int = -1) -> Dictionary
```

Albion-style alliances (hub, guild leaders): "invite" a leader by peer id, "accept", "leave", "status".

### `cmd_guild_bank`

```gdscript
func cmd_guild_bank(peer_id: int, action: String, item_id: String = "", quantity: int = 0) -> Dictionary
```

Albion-style guild bank at the hub: "list", "deposit" (any member), "withdraw" (officers).

### `cmd_plant`

```gdscript
func cmd_plant(peer_id: int, seed_id: String) -> Dictionary
```

Homestead farming: plant a carried seed 1.5 m in front of you (green zone only).

### `cmd_harvest`

```gdscript
func cmd_harvest(peer_id: int) -> Dictionary
```

Harvest the nearest ripe plot of your own within reach.

### `cmd_faction`

```gdscript
func cmd_faction(peer_id: int, action: String, faction_id: String = "") -> Dictionary
```

Faction warfare commands: "enlist" (hub, with faction id), "flag", "unflag", "redeem".

### `cmd_market_bid`

```gdscript
func cmd_market_bid(peer_id: int, item_id: String, quantity: int, unit_price: int) -> Dictionary
```

Albion-style buy order: escrows quantity * price silver from the buyer (hub only).

### `cmd_market_fill`

```gdscript
func cmd_market_fill(peer_id: int, bid_id: int, quantity: int) -> Dictionary
```

Sell straight into a buy order: the seller is paid now (minus tax); the buyer's goods wait at the hub.

### `cmd_market_cancel_bid`

```gdscript
func cmd_market_cancel_bid(peer_id: int, bid_id: int) -> Dictionary
```

### `cmd_market_create`

```gdscript
func cmd_market_create(peer_id: int, item_id: String, quantity: int, unit_price: int) -> Dictionary
```

### `cmd_market_cancel`

```gdscript
func cmd_market_cancel(peer_id: int, listing_id: int) -> Dictionary
```

### `cmd_market_buy`

```gdscript
func cmd_market_buy(peer_id: int, listing_id: int, quantity: int, request_id: int) -> Dictionary
```

A market purchase must have a monotonically increasing, session-scoped request ID.
A retry returns the original result, never a second transfer, even after a partial fill.
Old IDs are refused rather than evicted and potentially executed a second time.

### `cmd_vendor`

```gdscript
func cmd_vendor(peer_id: int, item_id: String, quantity: int, buy: bool) -> Dictionary
```

The safe-hub vendor uses server position and inventory only.
A rejected trade leaves every item and silver balance unchanged.

### `cmd_outpost_supplies`

```gdscript
func cmd_outpost_supplies(peer_id: int, site_id: int) -> Dictionary
```

Captured frontier outpost supplies: authenticated server-owned ownership,
exact on-site position, live enemy contest, one account claim per capture.
No client may specify the reward, party, token, or cache contents.

### `cmd_rest`

```gdscript
func cmd_rest(peer_id: int) -> Dictionary
```

Camp contracts use the same real hub distance check as the vendor and bank.
The only client input is accept/claim, never rewards, progress or prices.
Camp recovery is an authoritative, resource-paid sanctuary action.
Recent combat and noise lockouts prevent instant healing during danger.

### `cmd_caravan`

```gdscript
func cmd_caravan(peer_id: int, action: String) -> Dictionary
```

Cross-settlement resource couriers: the server selects and validates
both real NPC stations. Goods are gathered by the player, not spawned.

### `cmd_contract`

```gdscript
func cmd_contract(peer_id: int, action: String) -> Dictionary
```

### `cmd_stash`

```gdscript
func cmd_stash(peer_id: int, item_id: String, count: int, deposit: bool) -> Dictionary
```

Authoritative hub bank: move a bounded item stack only when the actual
server position is near the workbench. A failed operation changes nothing.

### `cmd_equipment_preset`

```gdscript
func cmd_equipment_preset(peer_id: int, action: String, slot: int) -> Dictionary
```

Players may record and swap three owned gear sets only at the hub workbench.
Client requests carry no gear IDs: server owns the inventory and saved sets.
Combat, movement actions, mounts and recall cannot become instant gear swaps.

### `cmd_expedition_restock`

```gdscript
func cmd_expedition_restock(peer_id: int, preset_id: String) -> Dictionary
```

One server-authorized action banks raw and refined crafting inputs.
The client selects no item IDs, quantities or receipt; failed operations
do not modify either inventory or the account-bound protected bank.

### `cmd_stash_bulk`

```gdscript
func cmd_stash_bulk(peer_id: int) -> Dictionary
```

### `cmd_place_infected_snare`

```gdscript
func cmd_place_infected_snare(peer_id: int, x: float, z: float) -> Dictionary
```

Validate and build entirely on the authority. Clients only request a location.
Building is intentionally forbidden inside the town sanctuary.
The client requests coordinates, but cannot claim warmth, time or a free
fire. All placement and inventory costs are validated by the server.
The client supplies a direction, not the position, price or affected NPCs.
Cost and flight-path validation happen atomically on this simulation.
Deploy only by spending a real crafted kit at a verified outdoor site.
Account-bound owner caps prevent relogging to bypass the three-trap limit.

### `cmd_throw_flash`

```gdscript
func cmd_throw_flash(peer_id: int, direction_x: float, direction_z: float) -> Dictionary
```

A one-shot, inventory-paid, obstacle-checked PvE interrupt. Never trust
player-supplied impact positions, affected zombie IDs, or target counts.

### `cmd_throw_ember`

```gdscript
func cmd_throw_ember(peer_id: int, direction_x: float, direction_z: float) -> Dictionary
```

Inventory-paid, obstacle-checked PvE fire. Shares the persistent flash
timer to avoid rapid alternating charges or reconnect cooldown bypasses.

### `cmd_throw_decoy`

```gdscript
func cmd_throw_decoy(peer_id: int, direction_x: float, direction_z: float) -> Dictionary
```

### `cmd_pitch_shelter`

```gdscript
func cmd_pitch_shelter(peer_id: int, x: float, z: float) -> Dictionary
```

Shared expedition tarp: weather reduction, not PvP protection.

### `cmd_pack_shelter`

```gdscript
func cmd_pack_shelter(peer_id: int, shelter_id: int) -> Dictionary
```

### `cmd_light_campfire`

```gdscript
func cmd_light_campfire(peer_id: int, x: float, z: float) -> Dictionary
```

### `cmd_extinguish_campfire`

```gdscript
func cmd_extinguish_campfire(peer_id: int, id: int) -> Dictionary
```

Nearby survivors may cooperatively fuel an existing fire. The server
validates its deadline and charges the correct backpack before extending it.
The account/session owner can extinguish an ephemeral campfire early.
Fuel is already burned and never refunded; strangers cannot delete the
group's heating by guessing a network entity ID.

### `cmd_arm_camp_alarm`

```gdscript
func cmd_arm_camp_alarm(peer_id: int, fire_id: int) -> Dictionary
```

Attach a crafted 3-minute infected warning kit to a burning campfire.
Only a real nearby survivor can pay; server chooses who hears the signal.

### `cmd_refuel_campfire`

```gdscript
func cmd_refuel_campfire(peer_id: int, id: int) -> Dictionary
```

### `cmd_build_piece`

```gdscript
func cmd_build_piece(peer_id: int, piece: String, x: float, z: float, facing: float = 0.0) -> Dictionary
```

### `cmd_toggle_door`

```gdscript
func cmd_toggle_door(peer_id: int, id: int) -> Dictionary
```

Open or shut a door. Its owner, their party and their guild may; everyone else has to break it.

### `cmd_build`

```gdscript
func cmd_build(peer_id: int, x: float, z: float, yaw: float = 0.0) -> Dictionary
```

### `cmd_repair`

```gdscript
func cmd_repair(peer_id: int, id: int) -> Dictionary
```

### `cmd_upgrade`

```gdscript
func cmd_upgrade(peer_id: int, id: int) -> Dictionary
```

Upgrade the closest existing wall, not an arbitrary remote structure.
Item costs are server-derived from the target tier, never RPC parameters.

### `cmd_dismantle`

```gdscript
func cmd_dismantle(peer_id: int, id: int) -> Dictionary
```

Owner-only, local, all-or-nothing structure salvage.
Never remove a world collider until the inventory accepts the full refund.

### `damage_barricade`

```gdscript
func damage_barricade(id: int, damage: float) -> bool
```

### `cmd_smart_provision`

```gdscript
func cmd_smart_provision(peer_id: int, intent: String) -> Dictionary
```

Smart field treatment, selected from the player's server-owned wounds and items.
Server verifies food/drink intent and selects one carried, safe ration.

### `cmd_quick_medicine`

```gdscript
func cmd_quick_medicine(peer_id: int) -> Dictionary
```

### `cmd_use`

```gdscript
func cmd_use(peer_id: int, item_id: String) -> Dictionary
```

### `cmd_sample_spores`

```gdscript
func cmd_sample_spores(peer_id: int) -> Dictionary
```

A dangerous-swamp research loop; world, kit, protective suit, filtration,
infection exposure and output are exclusively server-owned.

### `cmd_collect_rain`

```gdscript
func cmd_collect_rain(peer_id: int) -> Dictionary
```

Convert a crafted tarp into clean bottled stormwater. The server decides
climate, terrain, swamp contamination, costs and output, never the client.

### `cmd_refill_canteen`

```gdscript
func cmd_refill_canteen(peer_id: int, boil: bool = false) -> Dictionary
```

Lake water hydrates but can infect: clean bottles remain a risk-free alternative.
Filtration is item-paid, never a free client flag or cure.
Bottle clean water at an actual shore with either a charcoal filter or
two wood beside a LIVE campfire. Shared persisted cooldown prevents
alternating methods and reconnect bypass. The client chooses only method.

### `cmd_drink_water`

```gdscript
func cmd_drink_water(peer_id: int) -> Dictionary
```

### `cmd_attack`

```gdscript
func cmd_attack(peer_id: int, dir_x: float, dir_z: float, charge: float = 0.0) -> Dictionary
```

Attack in the direction the player is facing. Melee hits the closest enemy in range; a pistol
shoots a ray that hits the first enemy along it.

### `cmd_guardian_taunt`

```gdscript
func cmd_guardian_taunt(peer_id: int) -> Dictionary
```

Party frontline role: no client-authored targets, aggro, radius or damage.

### `cmd_party_shield_wall`

```gdscript
func cmd_party_shield_wall(peer_id: int) -> Dictionary
```

Short nonstacking party frontline stance. No client-provided coordinates,
protected targets, damage values, enemy IDs or shared buff durations.

### `cmd_guardian_intercept`

```gdscript
func cmd_guardian_intercept(peer_id: int, target_id: int) -> Dictionary
```

Protect exactly one verified party ally from their next infected MELEE hit.
Client supplies an ally ID, never the enemy, damage amount or hit outcome.

### `cmd_gear_skill`

```gdscript
func cmd_gear_skill(peer_id: int, slot: String) -> Dictionary
```

Resolve active combat on the server; the client supplies only aim direction.
Albion-style armor abilities (R chest / D helmet / F boots), granted by the equipped piece.

### `cmd_skill`

```gdscript
func cmd_skill(peer_id: int, dir_x: float, dir_z: float, ultimate: bool = false) -> Dictionary
```

### `cmd_stagger_finisher`

```gdscript
func cmd_stagger_finisher(peer_id: int) -> Dictionary
```

Classless evasion: no client-supplied distance, speed, stamina or invulnerability.
Reuse swept-in-small-steps world collision and restrict zombie immunity to 0.30 s.
Timed, one-hit melee parry. Facing, ownership and the actual enemy strike
are evaluated on the authoritative server; no client target is accepted.
The caller chooses no enemy: server selects the nearest visible and
genuinely stunned infected. Bosses, players and barriers are excluded.

### `cmd_kick`

```gdscript
func cmd_kick(peer_id: int, dir_x: float, dir_z: float) -> Dictionary
```

Kick: cheap shove that staggers; a staggered target goes down for a ground finisher.

### `cmd_rage`

```gdscript
func cmd_rage(peer_id: int) -> Dictionary
```

Rage: spend a full bar for a short frenzy.

### `cmd_parry`

```gdscript
func cmd_parry(peer_id: int) -> Dictionary
```

### `cmd_arcane_bolt`

```gdscript
func cmd_arcane_bolt(peer_id: int, dir_x: float, dir_z: float) -> Dictionary
```

Arcane Bolt: a classless magic projectile. Same line-of-fire, cover and PvP
protection rules as any shot; no ammo, paid with combat energy.

### `cmd_ultimate`

```gdscript
func cmd_ultimate(peer_id: int) -> Dictionary
```

Cataclysm ultimate: every living infected within the blast takes falloff damage
and is staggered. PvE only; survivors are never damaged by it.

### `cmd_dodge`

```gdscript
func cmd_dodge(peer_id: int, dir_x: float, dir_z: float) -> Dictionary
```

### `cmd_raid_skip_turn`

```gdscript
func cmd_raid_skip_turn(peer_id: int, entity_id: int) -> Dictionary
```

A contributor may voluntarily pass only their OWN active raid turn.
The server owns identities, world distance, timers and the bag contents.

### `cmd_raid_claim_selected`

```gdscript
func cmd_raid_claim_selected(peer_id: int, entity_id: int, item_id: String) -> Dictionary
```

Explicit type selection only applies to live round-robin raid bags;
ordinary scavenging stays unchanged, including the keyboard pickup.

### `cmd_loot_sweep`

```gdscript
func cmd_loot_sweep(peer_id: int) -> Dictionary
```

Authorized, reach-limited pickup from at most five existing PvE bags.
Raid, PvP death, supply and crate loot are always manual.

### `cmd_loot`

```gdscript
func cmd_loot(peer_id: int, entity_id: int, requested_item: String = "") -> Dictionary
```

### `cmd_perk`

```gdscript
func cmd_perk(peer_id: int, perk_id: String) -> Dictionary
```

### `tick`

```gdscript
func tick(delta: float) -> void
```

### `get_ai_schedule_stats`

```gdscript
func get_ai_schedule_stats() -> Dictionary
```

### `get_eqs_replan_stats`

```gdscript
func get_eqs_replan_stats() -> Dictionary
```

### `get_crowd_separation_stats`

```gdscript
func get_crowd_separation_stats() -> Dictionary
```

Server-only diagnostic snapshot: steering is never replicated to clients.

### `get_snare_query_stats`

```gdscript
func get_snare_query_stats() -> Dictionary
```

Server-only profiling; candidate counts are prefilters, never confirmed hits.

### `get_perception_interest_stats`

```gdscript
func get_perception_interest_stats() -> Dictionary
```

An optional broadphase of *potential* nearby players for passive target
selection. Threat, forced targets and active combat always receive the
full authoritative player table. The native query cannot authorize sight,
hearing, blood scent, safe zones, or an attack.

### `get_ai_cue_query_stats`

```gdscript
func get_ai_cue_query_stats() -> Dictionary
```

Shares target awareness inside a bounded 2D neighborhood. Bucket lookup
avoids checking every zombie against every other zombie in crowded ruins.
Reuses one stateless C++ EQS nearest-target query for noise, corpse scent
and night firelight. World cues are already server-filtered (including TTL).
The result selects a candidate only; Zombie.investigate_decoy still owns
state, territory/leash, combat priority and final behavior.

### `get_camp_alarm_query_stats`

```gdscript
func get_camp_alarm_query_stats() -> Dictionary
```

Build one native XZ spatial hash for every camp alarm ready to scan.
This is a purely server-owned optimization; CampAlarm.scan still enforces
fuel, expiration, 2s scan cadence, cooldown and private event limits.

### `drain_events`

```gdscript
func drain_events() -> Array
```

Returns the events since the last call and forgets them.

### `threat_scan_for`

```gdscript
func threat_scan_for(peer_id: int) -> Dictionary
```

Resolves paid scouting intel for the viewer. A party may relay the
original scout's signal only while its exact live roster is unchanged.
The client never supplies a target, source, position, or party membership.

### `prepare_snapshot_interest`

```gdscript
func prepare_snapshot_interest() -> bool
```

Build the Replication Graph-style spatial lists just once for a packet
broadcast. Only transient authoritative server values enter these grids.

### `finish_snapshot_interest`

```gdscript
func finish_snapshot_interest() -> void
```

### `snapshot_for`

```gdscript
func snapshot_for(peer_id: int) -> Dictionary
```

What one player is allowed to know: their own full state and nearby entities.

_117 private function(s) starting with `_` are not listed._
