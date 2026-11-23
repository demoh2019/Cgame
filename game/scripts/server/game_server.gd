extends RefCounted
## The authoritative simulation of the world: players, zombies, resources, loot and the rules that
## connect them. It has no networking and no scene: the network layer only feeds it commands and
## reads snapshots out of it, so the whole game can be tested by calling it directly.

const LagCompensation = preload("res://scripts/native/lag_compensation.gd") # Native CgameLagCompensation when built in.
const HTNPlanner = preload("res://scripts/native/htn_planner.gd") # Native CgameHTNPlanner when built in.
const InfectedRaidDomain = preload("res://scripts/shared/infected_raid_domain.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const CombatLogout = preload("res://scripts/shared/combat_logout.gd")
const TrainingDuel = preload("res://scripts/shared/training_duel.gd")
const ArenaRating = preload("res://scripts/shared/arena_rating.gd")
const ArenaMatchmaking = preload("res://scripts/shared/arena_matchmaking.gd")
const PvPHonor = preload("res://scripts/shared/pvp_honor.gd")
const OutlawBounty = preload("res://scripts/shared/outlaw_bounty.gd")
const PlayerTrade = preload("res://scripts/shared/player_trade.gd")
const Party = preload("res://scripts/shared/party.gd")
const PartyFocus = preload("res://scripts/shared/party_focus.gd")
const PartyFlank = preload("res://scripts/shared/party_flank.gd")
const RallyStandard = preload("res://scripts/shared/rally_standard.gd")
const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")
const LootRights = preload("res://scripts/shared/loot_rights.gd")
const LootSweep = preload("res://scripts/shared/loot_sweep.gd")
const DeathRecovery = preload("res://scripts/shared/death_recovery.gd")
const PartyCorpseRescue = preload("res://scripts/shared/party_corpse_rescue.gd")
const PartyAid = preload("res://scripts/shared/party_aid.gd")
const PartyMedicMastery = preload("res://scripts/shared/party_medic_mastery.gd")
const CampProvisions = preload("res://scripts/shared/camp_provisions.gd")
const QuickMedicine = preload("res://scripts/shared/quick_medicine.gd")
const SmartProvisions = preload("res://scripts/shared/smart_provisions.gd")
const PartySupplyRequest = preload("res://scripts/shared/party_supply_request.gd")
const PartyTriage = preload("res://scripts/shared/party_triage.gd")
const RestorationStaff = preload("res://scripts/shared/restoration_staff.gd")
const HealingAggro = preload("res://scripts/shared/healing_aggro.gd")
const MedicCover = preload("res://scripts/shared/medic_cover.gd")
const Threat = preload("res://scripts/shared/threat.gd")
const FinishingStrike = preload("res://scripts/shared/finishing_strike.gd")
const SunderMark = preload("res://scripts/shared/sunder_mark.gd")
const TerritoryControl = preload("res://scripts/shared/territory_control.gd")
const SiegeContracts = preload("res://scripts/shared/siege_contracts.gd")
const OutpostFortification = preload("res://scripts/shared/outpost_fortification.gd")
const OutpostProvisions = preload("res://scripts/shared/outpost_provisions.gd")
const OutpostBreach = preload("res://scripts/shared/outpost_breach.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Contracts = preload("res://scripts/shared/contracts.gd")
const StoryCampaign = preload("res://scripts/shared/story_campaign.gd")
const StoryChapterTwo = preload("res://scripts/shared/story_chapter_two.gd")
const StoryChapterThree = preload("res://scripts/shared/story_chapter_three.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const CaravanAmbush = preload("res://scripts/shared/caravan_ambush.gd")
const RuinAmbush = preload("res://scripts/shared/ruin_ambush.gd")
const CaravanEscort = preload("res://scripts/shared/caravan_escort.gd")
const CaravanEscortRewards = preload("res://scripts/shared/caravan_escort_rewards.gd")
const NightCaravan = preload("res://scripts/shared/night_caravan.gd")
const Skills = preload("res://scripts/shared/skills.gd")
const DailyBounties = preload("res://scripts/shared/daily_bounties.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")
const StashBulk = preload("res://scripts/shared/stash_bulk.gd")
const EquipmentPresets = preload("res://scripts/shared/equipment_presets.gd")
const ExpeditionLoadout = preload("res://scripts/shared/expedition_loadout.gd")
const Reputation = preload("res://scripts/shared/reputation.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const CraftFromStash = preload("res://scripts/shared/craft_from_stash.gd")
const GearSalvage = preload("res://scripts/shared/gear_salvage.gd")
const FieldWhetstone = preload("res://scripts/shared/field_whetstone.gd")
const FieldSightingKit = preload("res://scripts/shared/field_sighting_kit.gd")
const MiningWedges = preload("res://scripts/shared/mining_wedges.gd")
const FieldArmorPlate = preload("res://scripts/shared/field_armor_plate.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const RangedCover = preload("res://scripts/shared/ranged_cover.gd")
const InfectedMeleeCover = preload("res://scripts/shared/infected_melee_cover.gd")
const FlankSlotReservations = preload("res://scripts/shared/flank_slot_reservations.gd")
const BarricadeBallistics = preload("res://scripts/shared/barricade_ballistics.gd")
const SiegeCharge = preload("res://scripts/shared/siege_charge.gd")
const SiegeDefusal = preload("res://scripts/shared/siege_defusal.gd")
const SiegeBlastBrace = preload("res://scripts/shared/siege_blast_brace.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")
const TrailBackpack = preload("res://scripts/shared/trail_backpack.gd")
const CargoRattle = preload("res://scripts/shared/cargo_rattle.gd")
const RoadTravel = preload("res://scripts/shared/road_travel.gd")
const BikeChain = preload("res://scripts/shared/bike_chain.gd")
const BikeService = preload("res://scripts/shared/bike_service.gd")
const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")
const BikeLantern = preload("res://scripts/shared/bike_lantern.gd")
const BikeGrip = preload("res://scripts/shared/bike_grip.gd")
const Evasion = preload("res://scripts/shared/evasion.gd")
const TreeAmbush = preload("res://scripts/shared/tree_ambush.gd")
const InfectedPounce = preload("res://scripts/shared/infected_pounce.gd")
const DataLayers = preload("res://scripts/shared/data_layers.gd")
const Brawl = preload("res://scripts/shared/brawl.gd")
const MeleeParry = preload("res://scripts/shared/melee_parry.gd")
const ParryRiposte = preload("res://scripts/shared/parry_riposte.gd")
const StaggerFinisher = preload("res://scripts/shared/stagger_finisher.gd")
const ArcaneAbilities = preload("res://scripts/shared/arcane_abilities.gd")
const Swimming = preload("res://scripts/shared/swimming.gd")
const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")
const WorldEncounterDirector = preload("res://scripts/shared/world_encounter_director.gd")
const PlayerPresenceGrid = preload("res://scripts/server/player_presence_grid.gd")
const PackNeighborSelection = preload("res://scripts/shared/pack_neighbor_selection.gd")
const HousePieces = preload("res://scripts/shared/house_pieces.gd")
const ZombieWallAttackGrid = preload("res://scripts/shared/zombie_wall_attack_grid.gd")
const AntisepticEdge = preload("res://scripts/shared/antiseptic_edge.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const GearDurability = preload("res://scripts/shared/gear_durability.gd")
const Enchanting = preload("res://scripts/shared/enchanting.gd")
const GearSkills = preload("res://scripts/shared/gear_skills.gd")
const ReturnRate = preload("res://scripts/shared/return_rate.gd")
const MarketBids = preload("res://scripts/shared/market_bids.gd")
const Factions = preload("res://scripts/shared/factions.gd")
const Farming = preload("res://scripts/shared/farming.gd")
const GuildBank = preload("res://scripts/shared/guild_bank.gd")
const GuildAlliances = preload("res://scripts/shared/guild_alliances.gd")
const Scavenging = preload("res://scripts/shared/scavenging.gd")
const HerbalForaging = preload("res://scripts/shared/herbal_foraging.gd")
const WoundSealant = preload("res://scripts/shared/wound_sealant.gd")
const GatheringNoise = preload("res://scripts/shared/gathering_noise.gd")
const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")
const ProspectingChart = preload("res://scripts/shared/prospecting_chart.gd")
const SurveySignal = preload("res://scripts/shared/survey_signal.gd")
const ThreatScan = preload("res://scripts/shared/field_threat_scanner.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const WallUpkeepIndex = preload("res://scripts/shared/wall_upkeep_index.gd")
const BarricadeSnapshotIndex = preload("res://scripts/shared/barricade_snapshot_index.gd")
const SiegeWaves = preload("res://scripts/shared/siege_waves.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const RaidTempo = preload("res://scripts/shared/raid_tempo.gd")
const RaidAggroView = preload("res://scripts/shared/raid_aggro_view.gd")
const RaidRecovery = preload("res://scripts/shared/raid_recovery.gd")
const RaidInterrupt = preload("res://scripts/shared/raid_interrupt.gd")
const RaidCone = preload("res://scripts/shared/raid_cone.gd")
const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")
const AcidNeutralizer = preload("res://scripts/shared/acid_neutralizer.gd")
const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")
const GuardianIntercept = preload("res://scripts/shared/guardian_intercept.gd")
const PartyShieldWall = preload("res://scripts/shared/party_shield_wall.gd")
const GuardianRetribution = preload("res://scripts/shared/guardian_retribution.gd")
const WardenAura = preload("res://scripts/shared/warden_aura.gd")
const RaidReinforcements = preload("res://scripts/shared/raid_reinforcements.gd")
const RaidWard = preload("res://scripts/shared/raid_ward.gd")
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const RaidRoundRobin = preload("res://scripts/shared/raid_round_robin.gd")
const RaidNeedGreed = preload("res://scripts/shared/raid_need_greed.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")
const EliteInfected = preload("res://scripts/shared/elite_infected.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const NightHorde = preload("res://scripts/shared/night_horde.gd")
const HubRecall = preload("res://scripts/shared/hub_recall.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const StormMud = preload("res://scripts/shared/storm_mud.gd")
const StormLightning = preload("res://scripts/shared/storm_lightning.gd")
const StormInsulator = preload("res://scripts/shared/storm_insulator.gd")
const WetClothing = preload("res://scripts/shared/wet_clothing.gd")
const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")
const WadingTravel = preload("res://scripts/shared/wading_travel.gd")
const WindChill = preload("res://scripts/shared/wind_chill.gd")
const SporeHazard = preload("res://scripts/shared/spore_hazard.gd")
const SporeSampling = preload("res://scripts/shared/spore_sampling.gd")
const BloodScent = preload("res://scripts/shared/blood_scent.gd")
const FieldScentMask = preload("res://scripts/shared/field_scent_mask.gd")
const SoftSoleWraps = preload("res://scripts/shared/soft_sole_wraps.gd")
const Camouflage = preload("res://scripts/shared/camouflage.gd")
const StealthStance = preload("res://scripts/shared/stealth_stance.gd")
const StealthAmbush = preload("res://scripts/shared/stealth_ambush.gd")
const FieldSmoke = preload("res://scripts/shared/field_smoke.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const WorldDiscovery = preload("res://scripts/shared/world_discovery.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")
const RestedTraining = preload("res://scripts/shared/rested_training.gd")
const CrossTraining = preload("res://scripts/shared/cross_training.gd")
const DeepPractice = preload("res://scripts/shared/deep_practice.gd")
const FieldRest = preload("res://scripts/shared/field_rest.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const StormproofBriquette = preload("res://scripts/shared/stormproof_briquette.gd")
const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")
const StormTarpAnchors = preload("res://scripts/shared/storm_tarp_anchors.gd")
const CampfireThreat = preload("res://scripts/shared/campfire_threat.gd")
const CampAlarm = preload("res://scripts/shared/camp_alarm.gd")
const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")
const HandFlare = preload("res://scripts/shared/hand_flare.gd")
const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const FlashCharge = preload("res://scripts/shared/flash_charge.gd")
const EmberFlask = preload("res://scripts/shared/ember_flask.gd")
const InfectedSnare = preload("res://scripts/shared/infected_snare.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const ShoreFishTrap = preload("res://scripts/shared/shore_fish_trap.gd")
const FishingBait = preload("res://scripts/shared/fishing_bait.gd")
const StormFishing = preload("res://scripts/shared/storm_fishing.gd")
const FieldWater = preload("res://scripts/shared/field_water.gd")
const RainHarvest = preload("res://scripts/shared/rain_harvest.gd")
const FieldCanteen = preload("res://scripts/shared/field_canteen.gd")
const FrontierStim = preload("res://scripts/shared/frontier_stim.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const TrailRation = preload("res://scripts/shared/trail_ration.gd")
const FoodSafety = preload("res://scripts/shared/food_safety.gd")
const CombatStress = preload("res://scripts/shared/combat_stress.gd")
const PartyFeast = preload("res://scripts/shared/party_feast.gd")
const PcgSpawns = preload("res://scripts/server/pcg_spawns.gd")

const WORKBENCH_POSITION := Vector2(9.0, 0.0)
const WORKBENCH_RANGE := 6.0
const TRADE_RANGE := 6.0
const TRADE_TIMEOUT := 45.0
const MARKET_MAX_REQUEST_ID := 2_147_483_647
const FORTIFY_MAX_REQUEST_ID := 2_147_483_647
const PROVISION_MAX_REQUEST_ID := 2_147_483_647
const BREACH_MAX_REQUEST_ID := 2_147_483_647
const SIEGE_DECLARE_MAX_REQUEST_ID := 2_147_483_647
const ZOMBIE_ACTIVE_RADIUS := 130.0 # Zombies farther than this from every player are put to sleep.
const ZOMBIE_PACK_ALERT_RADIUS := 18.0
const ZOMBIE_PACK_BUCKET_SIZE := 18.0
const ZOMBIE_PACK_MAX_ALERTS := 12 # Per-source crowd fanout; nearest eligible targets first.
const BAG_LIFETIME := 300.0
const MAX_NAME_LENGTH := 20
const SNAPSHOT_REPEAT_SECONDS := 2.5
const SKILL_NOURISH_THRESHOLD := 90.0 # Eating or drinking above this teaches nothing.
const SKILL_METERS_PER_ATHLETICS_XP := 6.0
const SKILL_METERS_PER_EXPLORER_XP := 25.0
const STARTER_KIT := {"bandage": 2, "canned_food": 2, "water_bottle": 2}

var world
var rng := RandomNumberGenerator.new()
var time: float = 0.0
## PvP lag compensation: recent survivor positions and each peer's measured round trip (seconds).
var lag_history = LagCompensation.create()
var peer_round_trip: Dictionary = {}
var tick_count: int = 0

class Player:
	var id: int
	var name: String = ""
	var position: Vector3
	var yaw: float = 0.0
	var inventory
	var stash # Account-bound safe storage; isolated from full-loot death drops.
	var survival
	var progression # Permanent skills; gear is lost on death, not experience.
	var skills # The skill tree: XP in every kind of action, perks, bonuses.
	var pending_xp: Dictionary = {} # skill -> XP gained since the last report to the player
	var pending_levels: Array = [] # [{"skill", "level"}] reached since the last report
	var xp_report_timer: float = 0.0
	var run_meters: float = 0.0 # Sprinted distance not yet turned into XP.
	var travel_meters: float = 0.0
	var dirty_skills: bool = true
	var skills_sent_at: float = -100.0
	var inventory_sent_at: float = -100.0
	var stash_sent_at: float = -100.0
	var equipment_presets: Array = [] # Persistent owned weapon/armor shortcuts.
	var contract_state: Dictionary = {} # Server-owned persistent camp contract journal.
	var story_state: Dictionary = {} # Character-bound narrative chapter checkpoint.
	var story2_state: Dictionary = {} # Independent, persistent Chapter II and ending choice.
	var story3_state: Dictionary = {} # Chapter III checkpoint and inherited branch.
	var caravan_state: Dictionary = {} # Saved canonical source/destination IDs only.
	var caravan_view: Dictionary = {} # Verified route details for this private client.
	var caravan_ambushed: bool = false # One PvE ambush per active route, persisted.
	var caravan_defended: bool = false # All summoned attackers killed before deadline.
	var caravan_night: Dictionary = {} # Saved server-verified night delivery progress.
	var daily_bounty: Dictionary = {} # Account-persisted UTC daily bounty, never set by clients.
	var renown: int = 0 # Permanent survivor reputation, validated on Nakama loads.
	var discovered_sites: Dictionary = {} # Personal authenticated landmark journal.
	var threat_scan: Dictionary = {} # Paid, session-only tracking; optional roster-bound party intel.
	var prospect_mark: Dictionary = {} # One paid, session-only resource waypoint.
	var rest_cooldown: float = 0.0 # Per-survivor seconds until next camp recovery.
	var rested_xp_credit: int = 0 # Paid rest creates a capped, persistent training XP reserve.
	var practice_state: Dictionary = {} # Recent verified skill branches, session-only.
	var deep_practice_state: Dictionary = {} # Distinct skills practised in each discipline, session-only.
	var party_aid_timer: float = 0.0 # Shared medical/provisions support cooldown.
	var medic_cover_cooldown: float = 0.0 # Server-only healer aggro rescue cooldown.
	var supply_request_last_at: float = -INF # Session-only anti-spam for supply distress signals.
	var feast_timer: float = 0.0 # Session-only prepared group meal cooldown.
	var combat_stress: float = 0.0 # Session-only PvE pressure; not a permanent condition.
	var stress_pressure: float = 0.0 # Last trusted nearby infected threat sample.
	var stress_scan_seconds: float = 0.0 # Bound scanning to twice per second.
	var guardian_timer: float = 0.0 # Session-only PvE frontline cooldown.
	var guardian_brace: float = 0.0 # Short PvE-only defensive brace after a valid taunt.
	var guard_link_target: int = -1 # Server-only chosen ally for one zombie melee hit.
	var guard_link_seconds: float = 0.0 # Valid for at most 9 seconds.
	var guard_link_cooldown: float = 0.0 # Session-only cast cooldown.
	var shield_wall_seconds: float = 0.0 # Classless guardian's active PvE group defense.
	var shield_wall_cooldown: float = 0.0 # Session-only rate limit, no persistent stat.
	var guard_counter_target: int = -1 # Exact infected whose melee was intercepted.
	var guard_counter_seconds: float = 0.0 # 4s to answer with normal melee.
	var guard_counter_weapon: String = "" # Original real melee gear.
	var guard_counter_party: int = 0 # Group valid at time of interception.
	var lake_drink_cooldown: float = 0.0 # Prevents lake hydration spam and relog bypass.
	var rain_cooldown: float = 0.0 # Persisted storm water collection cooldown.
	var stim_cooldown: float = 0.0 # Persistent server-authorized injection cooldown.
	var spore_filter_seconds: float = 0.0 # Paid temporary swamp respirator, persisted.
	var wound_seal_seconds: float = 0.0 # Paid bite-wound prevention, persisted.
	var soft_sole_seconds: float = 0.0 # Paid, persisted reduced sprint footstep hearing.
	var storm_insulator_seconds: float = 0.0 # Persisted paid shock resistance.
	var spore_sample_cooldown: float = 0.0 # Persistent harvest cooldown.
	var meal_seconds: float = 0.0 # Remaining server-ticked cooked-fish recovery buff.
	var meal_tier: int = 0 # Zero when no meal buff is active; never client-authored.
	var ration_seconds: float = 0.0 # Item-paid, persisted reduced hunger drain.
	var ration_tier: int = 0 # T1-T4 smoked fish; no stacked durations.
	var input_budget: float = 0.0
	var last_input_seq: int = 0
	var attack_timer: float = 0.0
	var skill_timer: float = 0.0
	var ultimate_timer: float = 0.0 # Weapon E (charged skill), separate from Q.
	var faction: String = "" # Factions.FACTIONS id, or "" when not enlisted.
	var faction_flagged: bool = false
	var faction_unflag_at: float = -1.0 # Pending unflag time (server clock), -1 when none.
	var faction_points: int = 0
	var gear_skill_timers: Dictionary = {} # "armor" / "head" / "feet" -> seconds left.
	var sprint_buff_seconds: float = 0.0
	var sprint_buff_speed: float = 0.0
	var dodge_timer: float = 0.0
	var dodge_immunity: float = 0.0
	var parry_cooldown: float = 0.0 # Server-owned timed melee defense.
	var rage: float = 0.0 # Built by trading blows; spent on Rage.
	var rage_seconds: float = 0.0 # Rage active: harder, faster, tougher, free swings.
	var kick_cooldown: float = 0.0
	var knocked_seconds: float = 0.0 # Bowled over by a pouncing/charging infected: can't move or fight.
	var parry_window: float = 0.0 # First valid infected melee consumes it.
	var edge_coating_weapon: String = "" # Nonpersistent selected melee gear.
	var edge_coating_seconds: float = 0.0 # 120s server-owned bonus only vs infected.
	var riposte_seconds: float = 0.0 # Earned, private, short-lived PvE counter.
	var riposte_target_id: int = -1 # Exact attacking infected.
	var riposte_weapon: String = "" # Equipped weapon at parry impact.
	var finisher_cooldown: float = 0.0 # Server-owned, nonpersistent PvE execution timer.
	var arcane_cooldown: float = 0.0 # Classless Arcane Bolt; server-owned, nonpersistent.
	var ultimate_cooldown: float = 0.0 # Classless Cataclysm ultimate; server-owned, nonpersistent.
	var breath: float = 100.0 # Air left while diving; refills at the surface. Nonpersistent.
	var combat_energy: float = 100.0
	var sharpened_weapon: String = "" # Prepared, owned melee weapon.
	var sharpened_hits: int = 0 # Only confirmed ordinary infected contacts spend charges.
	var sighted_weapon: String = "" # Prepared owned ranged weapon.
	var sighted_hits: int = 0 # Only confirmed PvE ranged contacts spend charges.
	var wedge_charges: int = 0 # Three server-confirmed loud T2+ mine yields; persisted.
	var plated_armor: String = "" # Protected armor ID, tied to carried equipped item.
	var plated_hits: int = 0 # Three paid ordinary infected-melee mitigations.
	var noise_radius: float = 0.0
	var noise_timer: float = 0.0
	var smoke_cooldown: float = 0.0 # Session-only temporary PvE obscurant.
	var flare_seconds: float = 0.0 # Paid fuel, saved to defeat relog refills.
	var recall: Dictionary = {} # Ephemeral channel, no character persistence.
	var recall_ready_at: float = 0.0
	var crouching: bool = false # Ephemeral, server-authorized posture.
	var mounted: bool = false # Session-only; never saved.
	var bike_lamp_enabled: bool = true # Night visibility versus stealth (session-only).
	var bike_lamp_last_toggle: float = -1.0 # Server-owned anti-spam timer.
	var mount_cooldown: float = 0.0
	var chain_wrap_seconds: float = 0.0 # Validated, persisted noise protection.
	var bike_service_meters: float = 0.0 # Chain service measured from actual cycling.
	var bike_integrity: float = 100.0 # Persisted frame condition, server-owned.
	var tire_grip_seconds: float = 0.0 # Paid, validated off-road tire duration.
	var decoy_timer: float = 0.0 # Anti-spam timer; no persistent character data.
	var flash_cooldown: float = 0.0 # Persistent item-paid tactical cooldown.
	var ruin_survey: Dictionary = {} # One owner-only temporary expedition waypoint.
	var action: Dictionary = {} # Current gathering or fishing: {"remaining": s, "total": s, ...}
	var resource_next_hit_at: float = 0.0 # Server-owned strike rate limit; never client supplied.
	var fish_next_at: float = 0.0
	var respawn_timer: float = 0.0
	var keep_inventory_on_respawn: bool = false
	var last_death_full_loot: bool = false
	var combat_tag_until: float = 0.0 # Only server ticks mark PvP combat, never persisted.
	var kills: int = 0
	var deaths: int = 0
	var pvp_infamy: float = 0.0 # Persistent server-only criminal reputation.
	var defense_target: int = -1 # Last verified PvP aggressor in this session.
	var defense_until: float = 0.0 # Current server-clock expiry; never saved.
	var pvp_kills: int = 0
	var pvp_honor: int = 0
	var arena_rating: int = ArenaRating.START_RATING
	var arena_wins: int = 0
	var arena_losses: int = 0
	var zone_notice: int = -1
	var spore_exposed: bool = false # Session-only enter/exit warning state.
	var dirty_inventory: bool = true
	var dirty_stash: bool = true
	var user_id: String = "" # Nakama account, empty in offline mode.
	var guild_id: String = "" # Trusted Nakama group membership; session cache only.
	var guild_name: String = "" # Public verified guild name, never loaded from character storage.
	var guild_rank: int = -1 # Nakama rank 0/1/2; -1 means no verified membership.
	var dirty_character: bool = false # Something worth saving changed.

var players: Dictionary = {} # peer id -> Player
var zombies: Dictionary = {} # zombie id -> Zombie
# Optional native phase-based staggering for very dense encounters.
# Under this population threshold, every NPC retains previous scan timings.
const AI_STAGGER_MIN_POPULATION := 128
const AI_STAGGER_SLOTS := 4
const AI_BATCH_MAX_SIZE := 4096 # Match the native guard; larger populations use safe scalar calls.
var _ai_update_scheduler: Variant = null
var _flank_slot_reservations: Variant = null # Shared native AI Smart Object leases per server.
var _pack_spatial_grid: Variant = null # Shared stateless C++ broadphase for pack alerts and passive separation.
const AI_EQS_REPLAN_MIN_POPULATION := 64
const AI_EQS_REPLAN_QUOTA := 8 # Regular tactical queries per authoritative tick.
const AI_EQS_GLOBAL_QUOTA_US := 600 # Shared ordinary EQS CPU time per tick (soft).
const AI_EQS_GLOBAL_URGENT_US := 240 # Independent bounded slot-recovery pool.
var _eqs_tick_budget: Variant = null # Native, main-thread-only instance shared by infected.
var _eqs_tick_budget_active: bool = false
var last_eqs_replan_stats: Dictionary = {"enabled": false, "population": 0, "eligible": 0,
	"granted": 0, "deferred": 0, "urgent": 0}
const AI_CROWD_SEPARATION_MIN := 32
const AI_CROWD_SEPARATION_MAX := 1024 # Native source index safety limit.
const AI_CROWD_SEPARATION_TICKS := 5 # 4Hz, not every 20Hz movement tick.
const AI_CROWD_SEPARATION_RADIUS := 2.5
const AI_CROWD_LOOKAHEAD_SECONDS := 0.75 # Mass-style desired-velocity anticipation.
var _crowd_separation_enabled: bool = false
var last_crowd_separation_stats: Dictionary = {"enabled": false, "population": 0, "sources": 0}
# ORCA crowd avoidance for chasing infected near players (CgameCrowdAvoidance). Native only: the
# GDScript ORCA fallback is too slow for the 20 Hz server tick, so without the native class this
# stays off and pursuit movement is exactly the pre-existing behaviour.
const CrowdFacade = preload("res://scripts/native/cgame_crowd_facade.gd")
const AI_CHASE_AVOIDANCE_TICKS := 2 # 10 Hz; corrections persist between refreshes.
const AI_CHASE_AVOIDANCE_NEAR := 40.0 # Only infected this close to a living player take part.
const AI_CHASE_AVOIDANCE_MAX_AGENTS := 512
const AI_CHASE_AVOIDANCE_RADIUS := 0.55 # Body radius used by ORCA (m).
const AI_CHASE_AVOIDANCE_HORIZON := 1.0
const AI_CHASE_AVOIDANCE_NEIGHBOR_DIST := 4.0
const AI_CHASE_AVOIDANCE_NEIGHBORS := 8
var crowd_avoidance_enabled: bool = CrowdFacade.has_native_crowd() # Server flag; forced off without native.
var last_chase_avoidance_stats: Dictionary = {"enabled": false, "agents": 0, "chasers": 0}
var _chase_avoidance_dirty: bool = false # Some infected may hold a correction that must be cleared.
# Off-zone horde simulation (CgamePopulationLOD through cgame_crowd_facade). Free-roaming infected
# (spawn_id < 0: incidents, hordes, earlier promotions) that leave every player's active radius are
# folded into abstract herds instead of vanishing; herds migrate toward noise, corpses and (at night)
# survivors, and promote back into real infected near players under the existing caps and spawn
# rules. Spawn-point infected keep their unchanged respawn-at-spawn persistence (folding them too
# would duplicate them). Default on only with the native class; the GDScript fallback works but is
# kept opt-in for the server tick. Herds are session-only, like every other infected.
const HERD_CELL_SIZE := 64.0
const HERD_PROMOTE_RADIUS := 110.0 # < ZOMBIE_ACTIVE_RADIUS so promoted infected are not unloaded at once.
const HERD_PROMOTE_PER_PASS := 12 # New infected per population pass (1 s) at most.
const HERD_MIN_SPAWN_DISTANCE := 12.0 # Same "never appear in front of a player" rule as spawn points.
var herd_simulation_enabled: bool = CrowdFacade.has_native_population_lod()
var _herds: Object = null # Lazily created population LOD.
var _herd_last_time: float = -1.0
var last_herd_stats: Dictionary = {"enabled": false}
# EQS-style nearest cue query: one native spatial index for 3 passive senses.
const AI_CUE_NATIVE_MIN_NPCS := 32
const AI_CUE_NATIVE_MIN_SOURCES := 4
var last_ai_cue_query_stats: Dictionary = {"native": false, "channel": "", "sources": 0, "cues": 0}
# Mass-style per-agent sensing broadphase, never used for active combat.
const AI_PERCEPTION_INTEREST_MIN_NPCS := 64
const AI_PERCEPTION_INTEREST_MIN_PLAYERS := 8
var last_perception_interest_stats: Dictionary = {"native": false, "sources": 0, "players": 0, "pairs": 0}
# Native Mass-style cylinder counts for simultaneously armed camp sentries.
var last_camp_alarm_query_stats: Dictionary = {"native": false, "centers": 0, "targets": 0}
# Cross-set Mass/Chaos-style native broadphase for PvE snares; script owns exact hits.
const AI_SNARE_BROADPHASE_MIN_NPCS := 32
const AI_SNARE_BROADPHASE_MIN_TRAPS := 8
const AI_SNARE_BROADPHASE_MAX_NPCS := 4096
var last_snare_query_stats: Dictionary = {"native": false, "population": 0, "traps": 0, "candidates": 0}
var last_pack_query_stats: Dictionary = {"native": false, "population": 0, "sources": 0, "max_alerts": 12, "alerts_sent": 0}
var last_ai_schedule_stats: Dictionary = {"enabled": false, "population": 0, "phase_due": 0, "phase_deferred": 0}
var last_population_query_stats: Dictionary = {} # Last once-per-second maintenance broadphase counters.
# Prepared only during one synchronous network snapshot broadcast.
# Standalone snapshot_for callers retain the exact non-indexed behavior.
var _snapshot_players_grid: Variant = null
var _snapshot_zombies_grid: Variant = null
# Reusable on-demand nearest-K native index; rebuilt every cast.
var _ultimate_spatial_grid: Variant = null
var last_ultimate_spatial_stats: Dictionary = {"native": false}
var _snapshot_interest_prepared: bool = false
var _snapshot_interest_tick: int = -1
# Precomputed once per 10 Hz broadcast; never sent to clients or saved.
var _snapshot_player_ids_by_peer: Dictionary = {}
var _snapshot_zombie_ids_by_peer: Dictionary = {}
var last_snapshot_interest_stats: Dictionary = {"enabled": false}
# Broadcast-scoped scripted index also works without the optional native
# player/zombie relevancy grids. Stale direct snapshots rebuild authoritatively.
var _snapshot_wall_index: Dictionary = {}
var _snapshot_wall_tick: int = -1
var _snapshot_wall_revision: int = -1
var _snapshot_wall_queries: int = 0
var last_snapshot_wall_stats: Dictionary = {"enabled": false}
var depleted: Dictionary = {} # node id -> time it comes back
var opened_crates: Dictionary = {} # crate id -> time it refills
var next_supply_drop_at: float = SupplyDrops.INTERVAL_SECONDS # Server-owned session clock.
var next_incident_at: float = 45.0 # First random world incident soon after start.
var incident_spawn_cap: int = 10 # Server-only adaptive cap on *new* random incident enemies.
var next_horde_at: float = NightHorde.START_DELAY # Separate night event schedule.
var night_horde: Dictionary = {} # Active IDs, expiry, tier, public event coordinates.
var caravan_ambushes: Array[Dictionary] = [] # Bounded server waves with expiry.
var ruin_ambushes: Array[Dictionary] = [] # One-shot infected packs awakened by real ruin looting.
var next_ruin_ambush_at: float = 0.0 # Global anti-spam cooldown; no client timer.
var caravan_escort_progress: Dictionary = {} # Session-only verified co-travel for live parties.
var spawn_state: Dictionary = {} # spawn id -> {"zombie": id or -1, "next": time}
var barricades: Dictionary = {}
# Only actual infected wall damage creates a temporary private base warning.
var _wall_infected_attack_until: Dictionary = {}
const WALL_ATTACK_WARNING_SECONDS := 12.0
var last_zombie_wall_query_stats: Dictionary = {"queries": 0, "matches": 0, "walls": 0}
var siege_charges: Dictionary = {} # Armed, paid PvP devices: transient world state only.
var siege_braces: Dictionary = {} # Temporary one-hit barricade shields; never saved.
var siege_last_by_wall: Dictionary = {} # Session timers only; no character persistence.
var last_siege_time: float = -1000000.0
var siege_waves_started: int = 0 # Server-owned structures; authenticated walls may persist.
var raid_boss_id: int = -1
var last_raid_spawn_time: float = -1000000.0
var raid_started_at: float = 0.0
var raid_next_slam_at: float = 0.0
var raid_pending_slam: Dictionary = {} # World position & deadline are server-owned.
var raid_next_cone_at: float = 0.0 # Independent cooldown for aimed raid attack.
var raid_pending_cone: Dictionary = {} # Locked origin and aim; server-only until strike.
var raid_exposed_until: float = 0.0 # Post-slam PvE counterattack window, never persisted.
var raid_wave: int = 0 # Number of completed reinforcement phases.
var raid_minions: Array[int] = [] # Raid-only infected are cleared with boss.
var lightning_pending: Dictionary = {} # One globally bounded storm ground warning.
var next_lightning_at: float = 65.0 # Server-only schedule, never persisted.
var campfires: Dictionary = {} # Temporary shared warmth, never checkpointed.
var shelters: Dictionary = {} # Public, temporary weather tarps; never checkpointed.
var decoys: Dictionary = {} # Temporary physical sound lures; server-owned, never persisted.
var smoke_clouds: Dictionary = {} # Temporary visual cover, never checkpointed.
var infected_snares: Dictionary = {} # Temporary PvE tripwires, never checkpointed.
var fish_traps: Dictionary = {} # Paid coastal traps, session-only.
var acid_pools: Dictionary = {} # Temporary nonpersistent corrosive terrain.
var ember_pools: Dictionary = {} # Session-only PvE fire, no persistence.
var _ember_last_hit: Dictionary = {} # Global per-infected burn throttle.
var _acid_last_hit: Dictionary = {} # Peer -> last pooled acid hit time; no stacking.
var _acid_wall_last_hit: Dictionary = {} # Wall id -> last corrosion time; no overlap stacking.
var trades: Dictionary = {} # trade id -> offer/accept/expiry
var market_orders: Dictionary = {} # id -> escrowed listing (goods held by the market).
var data_layers: Array = [] # Active Data Layers (data_layers.gd), sent to every client.
var data_layers_override = null # Array from --layers, or null to follow the calendar.
var _layers_checked_at := -INF
var pounces: Dictionary = {} # zombie id -> {kind, phase, t, target, from, to}
var pounce_ready_at: Dictionary = {} # zombie id -> server time its next leap/charge is allowed
var downed_until: Dictionary = {} # zombie id -> server time it gets back up (knocked down).
var market_payouts: Dictionary = {} # account -> silver owed from sales, collected at the hub.
var market_bids: Dictionary = {} # id -> Albion-style buy order with escrowed silver.
var farm_plots: Dictionary = {} # id -> homestead crop plot (persisted with the world).
var craft_quality_enabled: bool = true # Crafted gear rolls Normal..Masterpiece; suites about other systems may turn it off.
var guild_banks: Dictionary = {} # guild id -> {item id: count} (persisted with the world).
var guild_ledgers: Dictionary = {} # guild id -> recent [{who, action, item, count, at}].
var guild_alliances: Dictionary = {} # alliance id -> {"guilds": {guild id: guild name}} (persisted).
var guild_to_alliance: Dictionary = {} # guild id -> alliance id (derived from guild_alliances).
var alliance_invites: Dictionary = {} # invited guild id -> {"from": guild id, "from_name", "expires"}.
var market_returns: Dictionary = {} # account -> {item: count} unsold or cancelled goods.
var market_sales: Array = [] # Bounded session-only receipts, NOT durable settlement.
# Atomic two-account settlement. When the network layer has a persistent backend it sets pair_persistence; every
# completed player trade or market sale between two online players then queues one commit that saves BOTH characters
# in a single backend transaction (Nakama character_pair_save, idempotent by transaction ID). Until that commit is
# confirmed, both players are locked out of further trades and market deals, so a crash can never keep one half.
var pair_persistence := false
var pair_commits: Array = [] # [{a: peer, b: peer, tx: String}], drained by Net.
var pair_locks: Dictionary = {} # peer -> transaction ID awaiting confirmation.
var market_buy_requests: Dictionary = {} # Peer -> last request ID, arguments and result.
var loot_sweep_next: Dictionary = {} # Session-only authenticated pickup throttle.
var resource_hit_progress: Dictionary = {} # World node id -> {hits, expires}; multiplayer-shared and bounded.
var trade_by_player: Dictionary = {} # peer -> active trade
var parties = Party.new() # Server-only session groups and short-lived invitations.
var territory # Session outposts generated from this world seed.
var siege_contracts = SiegeContracts.new() # Session-only declared siege windows and honor.
var guild_siege_wins: Dictionary = {} # Historical Nakama totals cached for connected guilds.
var outpost_fortify_requests: Dictionary = {} # Peer -> last request and cached result.
var outpost_provision_requests: Dictionary = {} # Peer -> last provision receipt.
var outpost_breach_requests: Dictionary = {} # Peer -> last command and cached result.
var training_invites: Dictionary = {} # Target peer -> verified invitation.
var training_matches: Dictionary = {} # Both peer IDs reference the same session.
var training_invite_last: Dictionary = {} # Bounded per peer by disconnect cleanup.
var arena_recent_pairs: Dictionary = {} # Server-session account-pair ranked cooldowns.
var arena_queue: Dictionary = {} # Peer -> account and instance of explicit rated opt-in.
var pvp_honor_ledger: Dictionary = {} # Bounded server-only account/guest kill cooldowns.
var siege_declare_requests: Dictionary = {} # Peer -> last declared request and cached result.
var world_structure_revision: int = 0
var bags: Dictionary = {} # Session loot; optional server-owned PvE reservations
var events: Array = [] # Things that happened this tick, for the network layer to announce.
var _next_id: int = 5_000_000_000


func _init(p_world, p_seed: int = 1) -> void:
	world = p_world
	PcgSpawns.attach(p_world) # PCG loot caches and encounter spots (no-op without the engine module).
	territory = TerritoryControl.new(p_world)
	rng.seed = p_seed


func new_id() -> int:
	_next_id += 1
	return _next_id


## Called only by the authoritative ENet/Nakama gateway, never an RPC.
## Membership cannot be restored from client saves or assigned to guests.
func set_verified_guild(peer_id: int, backend_result: Dictionary) -> bool:
	var player: Player = players.get(peer_id)
	if player == null or player.user_id.is_empty():
		return false
	var checked: Dictionary = GuildIdentity.normalize(backend_result)
	if checked.is_empty():
		return false
	player.guild_id = checked["guild_id"]
	player.guild_name = checked["guild_name"]
	player.guild_rank = checked["rank"]
	return true


# --- Players ---------------------------------------------------------------------------------------------

func add_player(peer_id: int, p_name: String, p_user_id: String = "", saved: Dictionary = {}) -> Player:
	var player := Player.new()
	player.id = peer_id
	player.user_id = p_user_id
	player.name = p_name.strip_edges().substr(0, MAX_NAME_LENGTH)
	if player.name == "":
		player.name = "Survivor%d" % (peer_id % 1000)
	player.inventory = Inventory.new()
	player.stash = Inventory.new(Defs.STASH_SLOTS)
	player.survival = Survival.new()
	player.progression = Progression.new()
	player.skills = Skills.new()
	player.contract_state = Contracts.empty_state()
	player.story_state = StoryCampaign.empty_state()
	player.story2_state = StoryChapterTwo.empty_state()
	player.story3_state = StoryChapterThree.empty_state()
	player.equipment_presets = EquipmentPresets.empty_slots()
	player.caravan_state = {}
	player.caravan_view = {}
	player.caravan_ambushed = false
	player.caravan_defended = false
	player.caravan_night = {}
	player.daily_bounty = DailyBounties.empty_state()
	player.renown = 0
	players[peer_id] = player
	# Bind restored account-owned structures to this authenticated session.
	# Never match a stale numerical peer ID in place of the account identity.
	if not p_user_id.is_empty():
		for wall in barricades.values():
			if str(wall.get("owner_account", "")) == p_user_id:
				wall["owner"] = peer_id
	if saved.is_empty() or not apply_character(player, saved):
		_spawn_player(player)
	else:
		events.append({"type": "spawn", "peer": player.id})
	return player


## The part of a player that survives between sessions.
func character_data(player: Player) -> Dictionary:
	var alive := _alive(player)
	# Never write invalid bonuses for sold or lost equipment.
	var sharp_valid: bool = FieldWhetstone.valid_state(
		player.sharpened_weapon, player.sharpened_hits, player.inventory)
	var plate_valid: bool = FieldArmorPlate.valid_state(
		player.plated_armor, player.plated_hits, player.inventory)
	var sight_valid: bool = FieldSightingKit.valid_state(
		player.sighted_weapon, player.sighted_hits, player.inventory)
	return {
		"version": 1,
		"health": player.survival.health, "hunger": player.survival.hunger, "thirst": player.survival.thirst,
		"stamina": player.survival.stamina, "infection": player.survival.infection,
		"food_poisoning": player.survival.food_poisoning,
		"bleeding": player.survival.bleeding, "fracture": player.survival.fracture,
		"exposure": player.survival.exposure, "wetness": player.survival.wetness,
		"warmth_seconds": player.survival.warmth_seconds,
		"scent_mask_seconds": player.survival.scent_mask_seconds,
		"alive": alive, "kills": player.kills, "deaths": player.deaths,
		"pvp_infamy": player.pvp_infamy,
		"faction": player.faction, "faction_points": player.faction_points,
		"pvp_kills": player.pvp_kills, "pvp_honor": player.pvp_honor,
		"arena_rating": player.arena_rating, "arena_wins": player.arena_wins,
		"arena_losses": player.arena_losses,
		"x": player.position.x, "z": player.position.z,
		"inventory": player.inventory.to_dict(),
		"stash": player.stash.to_dict(),
		"progression": player.progression.to_dict(),
		"skills": player.skills.to_dict(),
		"equipment_presets": player.equipment_presets.duplicate(true),
		"contracts": player.contract_state.duplicate(true),
		"story": player.story_state.duplicate(true),
		"story2": player.story2_state.duplicate(true),
		"story3": player.story3_state.duplicate(true),
		"caravan": player.caravan_state.duplicate(true),
		"caravan_ambushed": player.caravan_ambushed,
		"caravan_defended": player.caravan_defended,
		"caravan_night": player.caravan_night.duplicate(true),
		"daily_bounty": player.daily_bounty.duplicate(true),
		"renown": player.renown,
		"discovered_sites": WorldDiscovery.to_saved(player.discovered_sites),
		"rest_cooldown": player.rest_cooldown, "rested_xp_credit": player.rested_xp_credit,
		"lake_drink_cooldown": player.lake_drink_cooldown,
		"rain_cooldown": player.rain_cooldown,
		"stim_cooldown": player.stim_cooldown,
		"spore_filter_seconds": player.spore_filter_seconds,
		"wound_seal_seconds": player.wound_seal_seconds,
		"soft_sole_seconds": player.soft_sole_seconds,
		"storm_insulator_seconds": player.storm_insulator_seconds,
		"flare_seconds": player.flare_seconds,
		"spore_sample_cooldown": player.spore_sample_cooldown,
		"chain_wrap_seconds": player.chain_wrap_seconds,
		"bike_service_meters": player.bike_service_meters,
		"bike_integrity": player.bike_integrity,
		"tire_grip_seconds": player.tire_grip_seconds,
		"flash_cooldown": player.flash_cooldown,
		"meal_seconds": player.meal_seconds, "meal_tier": player.meal_tier,
		"ration_seconds": player.ration_seconds, "ration_tier": player.ration_tier,
		"sharpened_weapon": player.sharpened_weapon if sharp_valid else "",
		"sharpened_hits": player.sharpened_hits if sharp_valid else 0,
		"sighted_weapon": player.sighted_weapon if sight_valid else "",
		"sighted_hits": player.sighted_hits if sight_valid else 0,
		"wedge_charges": player.wedge_charges if MiningWedges.valid_state(player.wedge_charges) else 0,
		"plated_armor": player.plated_armor if plate_valid else "",
		"plated_hits": player.plated_hits if plate_valid else 0,
	}


## Restores a saved character. Returns false (and changes nothing) if the data is not usable.
func apply_character(player: Player, data: Dictionary) -> bool:
	if data.get("version", 0) != 1:
		return false
	# Both containers use the same strict parser. Never coerce fractional, textual,
	# unknown or oversized quantities from persisted JSON into valid stacks.
	var parsed_bag: Dictionary = SaveValidation.parse_inventory(data.get("inventory"), Defs.INVENTORY_SLOTS)
	if parsed_bag.is_empty():
		return false
	var parsed_stash: Dictionary = {}
	if data.has("stash"):
		parsed_stash = SaveValidation.parse_inventory(data["stash"], Defs.STASH_SLOTS, false)
	else:
		# Legacy version-1 Nakama characters did not have a protected stash.
		parsed_stash = {"inventory": Inventory.new(Defs.STASH_SLOTS)}
	if parsed_stash.is_empty():
		return false

	# Check all persisted scalar values before changing the live Player.
	if not SaveValidation.finite_number(data.get("health", 100.0), 0.0, Defs.MAX_HEALTH + Skills.MAX_HEALTH_BONUS):
		return false
	if not SaveValidation.finite_number(data.get("hunger", 80.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("thirst", 80.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("stamina", Defs.MAX_STAMINA), 0.0, Defs.MAX_STAMINA):
		return false
	if not SaveValidation.finite_number(data.get("infection", 0.0), 0.0, Defs.INFECTION_MAX):
		return false
	if not FoodSafety.valid_severity(data.get("food_poisoning", 0.0)):
		return false
	if not SaveValidation.finite_number(data.get("bleeding", 0.0), 0.0, Defs.BLEEDING_MAX):
		return false
	if not SaveValidation.finite_number(data.get("fracture", 0.0), 0.0, Defs.FRACTURE_MAX):
		return false
	if not SaveValidation.finite_number(data.get("exposure", 0.0), 0.0, 100.0):
		return false
	if not SaveValidation.finite_number(data.get("wetness", 0.0), 0.0, WetClothing.MAX_WETNESS):
		return false
	if not SaveValidation.finite_number(data.get("warmth_seconds", 0.0), 0.0, Defs.THERMAL_WRAP_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("scent_mask_seconds", 0.0), 0.0, FieldScentMask.DURATION_SECONDS):
		return false
	if not SaveValidation.valid_counter(data.get("kills", 0)):
		return false
	if not SaveValidation.valid_counter(data.get("deaths", 0)):
		return false
	if not PvpInfamy.valid(data.get("pvp_infamy", 0.0)):
		return false
	if not (data.get("faction", "") is String) or (str(data.get("faction", "")) != "" and not Factions.valid_faction(str(data.get("faction", "")))):
		return false
	if not Factions.valid_points(data.get("faction_points", 0)):
		return false
	for key in ["pvp_kills", "pvp_honor"]:
		if not SaveValidation.valid_counter(data.get(key, 0)) or \
				float(data.get(key, 0)) > PvPHonor.MAX_POINTS:
			return false
	if not ArenaRating.valid_rating(data.get("arena_rating", ArenaRating.START_RATING)) or \
			not ArenaRating.valid_record(data.get("arena_wins", 0)) or \
			not ArenaRating.valid_record(data.get("arena_losses", 0)):
		return false
	if not SaveValidation.finite_number(data.get("rest_cooldown", 0.0), 0.0, CampRest.COOLDOWN):
		return false
	if not RestedTraining.valid_credit(data.get("rested_xp_credit", 0)):
		return false
	if not SaveValidation.finite_number(data.get("lake_drink_cooldown", 0.0), 0.0, FieldWater.COOLDOWN_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("rain_cooldown", 0.0), 0.0, RainHarvest.COOLDOWN_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("stim_cooldown", 0.0), 0.0, FrontierStim.COOLDOWN):
		return false
	if not SaveValidation.finite_number(data.get("spore_filter_seconds", 0.0),
			0.0, SporeHazard.FILTER_DURATION_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("wound_seal_seconds", 0.0),
			0.0, WoundSealant.DURATION_SECONDS):
		return false
	if not SoftSoleWraps.valid_remaining(data.get("soft_sole_seconds", 0.0)):
		return false
	if not SaveValidation.finite_number(data.get("storm_insulator_seconds", 0.0),
			0.0, StormInsulator.DURATION_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("flare_seconds", 0.0),
			0.0, HandFlare.BURN_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("spore_sample_cooldown", 0.0),
			0.0, SporeSampling.COOLDOWN_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("chain_wrap_seconds", 0.0),
			0.0, BikeChain.DURATION_SECONDS):
		return false
	if not BikeService.valid_remaining(data.get("bike_service_meters", 0.0)):
		return false
	if not BikeIntegrity.valid(data.get("bike_integrity", BikeIntegrity.MAX_INTEGRITY)):
		return false
	if not SaveValidation.finite_number(data.get("tire_grip_seconds", 0.0),
			0.0, BikeGrip.DURATION_SECONDS):
		return false
	if not SaveValidation.finite_number(data.get("flash_cooldown", 0.0), 0.0, FlashCharge.COOLDOWN_SECONDS):
		return false
	if not HeartyMeal.valid_state(data.get("meal_seconds", 0.0), data.get("meal_tier", 0)):
		return false
	if not TrailRation.valid_state(data.get("ration_seconds", 0.0), data.get("ration_tier", 0)):
		return false
	if not FieldWhetstone.valid_state(data.get("sharpened_weapon", ""),
			data.get("sharpened_hits", 0), parsed_bag["inventory"]):
		return false
	if not FieldSightingKit.valid_state(data.get("sighted_weapon", ""),
			data.get("sighted_hits", 0), parsed_bag["inventory"]):
		return false
	if not FieldArmorPlate.valid_state(data.get("plated_armor", ""),
			data.get("plated_hits", 0), parsed_bag["inventory"]):
		return false
	if not MiningWedges.valid_state(data.get("wedge_charges", 0)):
		return false
	if not (data.get("alive", true) is bool):
		return false

	var survival = Survival.new()
	survival.health = clampf(float(data.get("health", 100.0)), 1.0, Defs.MAX_HEALTH + Skills.MAX_HEALTH_BONUS)
	survival.hunger = float(data.get("hunger", 80.0))
	survival.thirst = float(data.get("thirst", 80.0))
	# Legacy v1 characters without stamina are restored fully rested.
	survival.stamina = float(data.get("stamina", Defs.MAX_STAMINA))
	# Older version-1 saves without infection remain compatible.
	survival.infection = float(data.get("infection", 0.0))
	survival.food_poisoning = float(data.get("food_poisoning", 0.0))
	# Legacy version-1 accounts predate the persistent wound mechanic.
	survival.bleeding = float(data.get("bleeding", 0.0))
	survival.fracture = float(data.get("fracture", 0.0)) # Legacy v1 defaults to healthy.
	# Legacy survivors predating regional climate start with no exposure.
	survival.exposure = float(data.get("exposure", 0.0))
	survival.wetness = float(data.get("wetness", 0.0))
	survival.warmth_seconds = float(data.get("warmth_seconds", 0.0))
	survival.scent_mask_seconds = float(data.get("scent_mask_seconds", 0.0))
	var x: Variant = data.get("x", 0.0)
	var z: Variant = data.get("z", 0.0)
	# Invalid old logout coordinates can still safely fall back to the hub.
	var restore_position := Vector3.ZERO
	var can_restore_position := (
		SaveValidation.finite_number(x, -50000.0, 50000.0)
		and SaveValidation.finite_number(z, -50000.0, 50000.0)
		and absf(float(x)) < 50000.0 and absf(float(z)) < 50000.0
		and bool(data.get("alive", true))
	)
	if can_restore_position and not world.is_water(float(x), float(z)):
		restore_position = Vector3(float(x), world.height_at(float(x), float(z)), float(z))
	else:
		var angle := rng.randf() * TAU
		var spot := Vector2.from_angle(angle) * rng.randf_range(10.0, 22.0)
		restore_position = Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	var loaded_progression = Progression.new()
	if data.has("progression") and not loaded_progression.load_dict(data["progression"]):
		return false
	# Legacy v1 characters without contracts start from the first mission.
	var loaded_contracts: Variant = data.get("contracts", Contracts.empty_state())
	if not Contracts.valid_state(loaded_contracts):
		return false
	# Old saves predate the chapter; invalid new saves must never skip
	# checkpoints or mint a story reward by forging completed stage data.
	var loaded_story: Variant = data.get("story", StoryCampaign.empty_state())
	if not StoryCampaign.valid_state(loaded_story):
		return false
	# The second chapter has a separate saved journal so stage 4 of the
	# original campaign stays a completed, immutable Chapter I ending.
	var loaded_story2: Variant = data.get("story2", StoryChapterTwo.empty_state())
	if not StoryChapterTwo.valid_state(loaded_story2):
		return false
	if int((loaded_story2 as Dictionary)["stage"]) > 0 and \
			int((loaded_story as Dictionary)["stage"]) != StoryCampaign.LAST_STAGE:
		return false
	# The third journal must match the actual permanent Chapter II choice;
	# legacy saves without Chapter III remain valid and begin at its first step.
	var loaded_story3: Variant = data.get("story3", StoryChapterThree.empty_state())
	if not StoryChapterThree.valid_state(loaded_story3):
		return false
	if int((loaded_story3 as Dictionary)["stage"]) > 0 and (
			int((loaded_story2 as Dictionary)["stage"]) != StoryChapterTwo.LAST_STAGE or
			str((loaded_story3 as Dictionary)["source"]) != str((loaded_story2 as Dictionary)["ending"])):
		return false
	var loaded_presets: Variant = data.get("equipment_presets", EquipmentPresets.empty_slots())
	if not EquipmentPresets.valid_state(loaded_presets):
		return false
	var loaded_caravan: Variant = data.get("caravan", {})
	if not CaravanRoutes.valid_state(world, loaded_caravan):
		return false
	var caravan_view: Dictionary = CaravanRoutes.from_saved(world, loaded_caravan)
	if (loaded_caravan as Dictionary).is_empty():
		caravan_view = {}
	# A completed ambush flag cannot be attached to an empty or altered
	# route. Legacy saved characters start without a live ambush mark.
	var loaded_caravan_ambushed: Variant = data.get("caravan_ambushed", false)
	if not (loaded_caravan_ambushed is bool) or \
			(bool(loaded_caravan_ambushed) and caravan_view.is_empty()):
		return false
	var loaded_caravan_defended: Variant = data.get("caravan_defended", false)
	if not (loaded_caravan_defended is bool) or (bool(loaded_caravan_defended) and
			(not bool(loaded_caravan_ambushed) or caravan_view.is_empty())):
		return false
	var loaded_caravan_night: Variant = data.get("caravan_night", {})
	if not NightCaravan.valid_state(loaded_caravan_night, caravan_view):
		return false
	var loaded_daily: Variant = data.get("daily_bounty", DailyBounties.empty_state())
	if not DailyBounties.valid_state(loaded_daily) \
			or int(loaded_daily["day"]) > DailyBounties.utc_day():
		return false
	# Old version-one characters predate renown and begin at rank zero.
	var loaded_renown: Variant = data.get("renown", 0)
	if not Reputation.valid_points(loaded_renown):
		return false
	# Old characters start empty; each saved record must belong to this world seed.
	var loaded_discoveries: Dictionary = WorldDiscovery.from_saved(
		data.get("discovered_sites", []), world)
	if loaded_discoveries.is_empty():
		return false

	# Characters saved before the skill tree start with a blank sheet. A sheet that is present must be consistent.
	var loaded_skills = Skills.new()
	if data.has("skills") and not loaded_skills.load_dict(data["skills"]):
		return false

	# One commit point: a failed parse cannot partially replace the player's
	# inventory, protected stash, progression or survival state.
	player.progression = loaded_progression
	player.skills = loaded_skills
	player.dirty_skills = true
	player.contract_state = (loaded_contracts as Dictionary).duplicate(true)
	player.story_state = (loaded_story as Dictionary).duplicate(true)
	player.story2_state = (loaded_story2 as Dictionary).duplicate(true)
	player.story3_state = (loaded_story3 as Dictionary).duplicate(true)
	player.equipment_presets = (loaded_presets as Array).duplicate(true)
	player.caravan_state = (loaded_caravan as Dictionary).duplicate(true)
	player.caravan_view = caravan_view.duplicate(true)
	player.caravan_ambushed = bool(loaded_caravan_ambushed)
	player.caravan_defended = bool(loaded_caravan_defended)
	player.caravan_night = (loaded_caravan_night as Dictionary).duplicate(true)
	if player.caravan_night.is_empty() and not caravan_view.is_empty():
		player.caravan_night = NightCaravan.initial(caravan_view)
	player.daily_bounty = (loaded_daily as Dictionary).duplicate(true)
	player.renown = int(loaded_renown)
	player.discovered_sites = loaded_discoveries["journal"]
	player.pvp_infamy = float(data.get("pvp_infamy", 0.0))
	player.faction = str(data.get("faction", ""))
	player.faction_points = int(data.get("faction_points", 0))
	player.faction_flagged = false # Flags never survive a relog.
	player.pvp_kills = int(data.get("pvp_kills", 0))
	player.pvp_honor = int(data.get("pvp_honor", 0))
	player.arena_rating = int(data.get("arena_rating", ArenaRating.START_RATING))
	player.arena_wins = int(data.get("arena_wins", 0))
	player.arena_losses = int(data.get("arena_losses", 0))
	player.rest_cooldown = float(data.get("rest_cooldown", 0.0))
	player.rested_xp_credit = int(data.get("rested_xp_credit", 0))
	player.lake_drink_cooldown = float(data.get("lake_drink_cooldown", 0.0))
	player.rain_cooldown = float(data.get("rain_cooldown", 0.0))
	player.stim_cooldown = float(data.get("stim_cooldown", 0.0))
	player.spore_filter_seconds = float(data.get("spore_filter_seconds", 0.0))
	player.wound_seal_seconds = float(data.get("wound_seal_seconds", 0.0))
	player.soft_sole_seconds = float(data.get("soft_sole_seconds", 0.0))
	player.storm_insulator_seconds = float(data.get("storm_insulator_seconds", 0.0))
	player.flare_seconds = float(data.get("flare_seconds", 0.0))
	player.spore_sample_cooldown = float(data.get("spore_sample_cooldown", 0.0))
	player.chain_wrap_seconds = float(data.get("chain_wrap_seconds", 0.0))
	player.bike_service_meters = float(data.get("bike_service_meters", 0.0))
	player.bike_integrity = float(data.get("bike_integrity", BikeIntegrity.MAX_INTEGRITY))
	player.tire_grip_seconds = float(data.get("tire_grip_seconds", 0.0))
	player.flash_cooldown = float(data.get("flash_cooldown", 0.0))
	player.meal_seconds = float(data.get("meal_seconds", 0.0))
	player.meal_tier = int(data.get("meal_tier", 0))
	player.ration_seconds = float(data.get("ration_seconds", 0.0))
	player.ration_tier = int(data.get("ration_tier", 0))
	player.sharpened_weapon = str(data.get("sharpened_weapon", ""))
	player.sharpened_hits = int(data.get("sharpened_hits", 0))
	player.sighted_weapon = str(data.get("sighted_weapon", ""))
	player.sighted_hits = int(data.get("sighted_hits", 0))
	player.plated_armor = str(data.get("plated_armor", ""))
	player.plated_hits = int(data.get("plated_hits", 0))
	player.wedge_charges = int(data.get("wedge_charges", 0))
	player.inventory = parsed_bag["inventory"]
	player.stash = parsed_stash["inventory"]
	player.kills = int(data.get("kills", 0))
	player.deaths = int(data.get("deaths", 0))
	player.survival = survival
	_apply_skill_bonuses(player)
	survival.health = minf(survival.health, survival.max_health)
	player.position = restore_position
	player.dirty_inventory = true
	player.dirty_stash = true
	player.dirty_character = true
	return true


## Check a complete saved character without modifying a live player or the spawn RNG.
## The loader refuses corrupt existing accounts instead of minting a new starter kit.
func valid_character_data(data: Dictionary) -> bool:
	var previous_state: int = rng.state
	var probe := Player.new()
	var valid := apply_character(probe, data)
	rng.state = previous_state
	return valid


## Call before building a logout save. A live player disconnecting while
## PvP-tagged in a full-loot zone drops equipment once, then respawns safely.
## This applies to voluntary exits and network loss alike. Safes and PvE are
## exempt; stash and character progression are never dropped.
func prepare_disconnect(peer_id: int) -> bool:
	var player: Player = players.get(peer_id)
	if player == null:
		return false
	var zone: int = world.zone_at(player.position.x, player.position.z) if player.position.is_finite() else -1
	if not CombatLogout.penalize_on_disconnect(player, zone, time):
		return false
	player.combat_tag_until = 0.0 # Idempotent even if remove_player runs later.
	# The same confirmed full-loot death path handles the drops, persistence
	# flags, equipped gear, respawn starter kit and active trades.
	player.survival.hurt(player.survival.health)
	_on_player_death(player, -1)
	_spawn_player(player)
	return true


func remove_player(peer_id: int) -> void:
	arena_queue.erase(peer_id)
	_acid_last_hit.erase(peer_id) # Network peer reuse cannot inherit old hit cooldown.
	_abort_training(peer_id, "disconnected")
	training_invite_last.erase(peer_id)
	# Direct server removals must obey the same rule as authenticated Net.leave.
	prepare_disconnect(peer_id)
	# Prevent a recycled peer ID inheriting another survivor's guilt.
	for survivor in players.values():
		if survivor.defense_target == peer_id:
			survivor.defense_target = -1
			survivor.defense_until = 0.0
		if survivor.guard_link_target == peer_id:
			survivor.guard_link_target = -1
			survivor.guard_link_seconds = 0.0
	market_buy_requests.erase(peer_id)
	loot_sweep_next.erase(peer_id)
	outpost_fortify_requests.erase(peer_id)
	outpost_provision_requests.erase(peer_id)
	outpost_breach_requests.erase(peer_id)
	siege_declare_requests.erase(peer_id)
	_cancel_market_seller(peer_id)
	_cancel_player_trade(peer_id, "disconnected")
	CaravanEscortRewards.clear_peer(caravan_escort_progress, peer_id)
	_clear_caravan_waves(peer_id)
	parties.disconnect_peer(peer_id)
	# A recycled network peer ID must never inherit the previous camp alarm.
	for fire in campfires.values():
		if int(fire.get("alarm_owner", -1)) == peer_id:
			fire["alarm_until"] = time
	var player: Player = players.get(peer_id)
	if player != null and not player.user_id.is_empty():
		for wall in barricades.values():
			if str(wall.get("owner_account", "")) == player.user_id:
				wall["owner"] = -1
	players.erase(peer_id)


func _spawn_player(player: Player) -> void:
	var spot := Vector2(12.0, 6.0)
	for attempt in 20: # Not inside the workbench or a building: take the first free spot.
		var candidate := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 22.0)
		var blocked := false
		for blocker in world.blockers_near(candidate.x, candidate.y, Defs.PLAYER_RADIUS + 1.0):
			if Vector2(blocker["x"] - candidate.x, blocker["z"] - candidate.y).length() < Defs.PLAYER_RADIUS + float(blocker["radius"]) + 0.3:
				blocked = true
		if not blocked:
			spot = candidate
			break
	# A survivor who built a bed wakes up beside it instead of in the settlement.
	if player.user_id != "" or players.has(player.id):
		var bed_spot: Vector2 = _bed_spawn(player)
		if bed_spot.is_finite():
			spot = bed_spot
			events.append({"type": "bed_respawn", "peer": player.id})
	player.position = Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	_apply_skill_bonuses(player)
	player.survival.reset()
	player.combat_stress = 0.0
	player.stress_pressure = 0.0
	player.stress_scan_seconds = 0.0
	player.spore_exposed = false
	player.defense_target = -1
	player.defense_until = 0.0
	player.guard_link_target = -1
	player.guard_link_seconds = 0.0
	player.guard_link_cooldown = 0.0
	player.shield_wall_seconds = 0.0
	GuardianRetribution.clear(player)
	var kept_gear: bool = player.keep_inventory_on_respawn
	player.keep_inventory_on_respawn = false
	if not kept_gear:
		player.inventory = Inventory.new()
		for id in STARTER_KIT:
			player.inventory.add(id, STARTER_KIT[id])
	player.action = {}
	player.resource_next_hit_at = 0.0
	player.recall = {}
	player.threat_scan = {} # Death cannot preserve a scouting advantage.
	player.sharpened_weapon = ""
	player.sharpened_hits = 0
	player.sighted_weapon = ""
	player.sighted_hits = 0
	player.wedge_charges = 0
	player.plated_armor = ""
	player.plated_hits = 0
	player.mounted = false
	player.mount_cooldown = 0.0
	if not kept_gear:
		player.bike_integrity = BikeIntegrity.MAX_INTEGRITY
	player.chain_wrap_seconds = 0.0
	player.soft_sole_seconds = 0.0
	player.bike_service_meters = 0.0
	player.tire_grip_seconds = 0.0
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.dodge_timer = 0.0
	player.dodge_immunity = 0.0
	player.parry_cooldown = 0.0
	player.parry_window = 0.0
	player.edge_coating_seconds = 0.0
	player.edge_coating_weapon = ""
	ParryRiposte.clear(player)
	player.finisher_cooldown = 0.0
	player.arcane_cooldown = 0.0
	player.ultimate_cooldown = 0.0
	player.breath = Swimming.MAX_BREATH
	player.party_aid_timer = 0.0
	player.feast_timer = 0.0
	player.guardian_timer = 0.0
	player.guardian_brace = 0.0
	player.meal_seconds = 0.0
	player.meal_tier = 0
	player.ration_seconds = 0.0
	player.ration_tier = 0
	player.combat_energy = Defs.COMBAT_ENERGY_MAX
	player.noise_radius = 0.0
	player.noise_timer = 0.0
	player.smoke_cooldown = 0.0
	player.flare_seconds = 0.0
	player.storm_insulator_seconds = 0.0
	player.crouching = false
	player.dirty_inventory = true
	events.append({"type": "spawn", "peer": player.id})


func _alive(player: Player) -> bool:
	return player.survival.alive


func _is_safe(position: Vector3) -> bool:
	return world.is_safe(position.x, position.z)


# --- Commands (the network layer calls these) -------------------------------------------------------

## A movement input measured by the client. `dt` is how long the client says it moved. The server
## accepts at most as much movement time as real time has passed, so a modified client cannot speed up.
## Bike ownership and eligibility are validated exclusively on the server.
## Use one real chart to map the nearest unopened dangerous ruin crate.
## Clients choose neither the crate nor coordinates; no guaranteed loot.
func cmd_survey_ruins(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if RuinSurvey.active(player.ruin_survey, time, opened_crates):
		return {"ok": false, "reason": "already_marked"}
	if player.inventory.count(RuinSurvey.ITEM_ID) < 1:
		return {"ok": false, "reason": "not_carried"}
	var found: Dictionary = RuinSurvey.nearest(world, player.position, opened_crates)
	if found.is_empty():
		return {"ok": false, "reason": "no_untouched_ruins"}
	if not player.inventory.remove(RuinSurvey.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	player.ruin_survey = {"id": int(found["id"]), "x": float(found["x"]),
		"z": float(found["z"]), "zone": int(found["zone"]),
		"until": time + RuinSurvey.MARK_SECONDS}
	player.dirty_inventory = true
	player.dirty_character = true
	# Target is sent privately in the command result and owner snapshot.
	return {"ok": true, "x": float(found["x"]), "z": float(found["z"]),
		"zone": int(found["zone"]), "seconds": RuinSurvey.MARK_SECONDS}


func cmd_toggle_mount(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		_dismount(player, false)
		return {"ok": true, "mounted": false, "cooldown": player.mount_cooldown}
	var reason: String = Mounts.refusal(player, time)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "cooldown": player.mount_cooldown}
	player.mounted = true
	player.crouching = false
	_cancel_recall(player, "mounted")
	events.append({"type": "mount", "peer": peer_id, "mounted": true})
	return {"ok": true, "mounted": true}


func _dismount(player: Player, hit: bool) -> void:
	if not player.mounted:
		return
	player.mounted = false
	if hit:
		player.bike_integrity = BikeIntegrity.after_hit(player.bike_integrity)
		player.dirty_character = true
	player.mount_cooldown = maxf(player.mount_cooldown,
		Mounts.HIT_COOLDOWN if hit else Mounts.MANUAL_COOLDOWN)
	events.append({"type": "mount", "peer": player.id, "mounted": false})


func submit_input(peer_id: int, seq: int, move_x: float, move_z: float, sprint: bool, yaw: float, dt: float, crouch: bool = false) -> void:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player) or seq <= player.last_input_seq:
		return
	if not (is_finite(move_x) and is_finite(move_z) and is_finite(dt) and is_finite(yaw)):
		return
	player.last_input_seq = seq
	dt = clampf(dt, 0.0, Movement.MAX_DELTA)
	var allowed := minf(dt, player.input_budget)
	player.input_budget -= allowed
	player.yaw = yaw
	if allowed > 0.0 and player.knocked_seconds > 0.0:
		allowed = 0.0 # On the ground: no walking until back up.
	if allowed > 0.0:
		player.crouching = crouch # Only input within the server time budget applies.
		# No client-supplied cargo, stamina or sound radius: server owns all three.
		var before_move: Vector3 = player.position
		var factor: float = BikeCargo.movement_factor(player.inventory,
			player.skills.bonus("carry_capacity"), player.mounted)
		var moving := move_x * move_x + move_z * move_z > 0.00001
		if player.mounted and (player.crouching or factor < 0.9999 or
				player.survival.fracture > 0.0 or not BikeIntegrity.can_ride(player.bike_integrity) or
				player.inventory.count(Mounts.ITEM_ID) < 1):
			_dismount(player, false)
			# Supported weight vanishes immediately after dismount.
			factor = BikeCargo.movement_factor(player.inventory,
				player.skills.bonus("carry_capacity"), false)
		var sprint_allowed: bool = sprint and not player.mounted and not player.crouching and moving and factor >= 0.9999 and WadingTravel.can_sprint(world, player.position) and player.survival.try_sprint(allowed)
		player.position = Movement.step(world, player.position, {
			"x": move_x, "z": move_z, "sprint": sprint_allowed, "mounted": player.mounted,
			"raft": player.inventory.count("raft") > 0, # Carried boat, from the authoritative inventory.
			"crouch": player.crouching, "cargo_factor": factor, "speed_bonus": player.skills.bonus("move_speed") + player.sprint_buff_speed,
			"injury_factor": Survival.fracture_speed_factor(player.survival.fracture),
			"tire_grip_seconds": player.tire_grip_seconds,
			"bike_integrity": player.bike_integrity,
			"weather_time": time,
		}, allowed)
		var moved: float = Vector2(player.position.x - before_move.x, player.position.z - before_move.z).length()
		if moved > 0.0:
			_record_caravan_escort_move(player, moved)
			if not player.caravan_night.is_empty() and NightCaravan.record(
					player.caravan_night, player.caravan_view,
					before_move, player.position, WorldCycle.is_night(time),
					world.zone_at(player.position.x, player.position.z),
					player.inventory.count(str(player.caravan_view.get("cargo", ""))),
					_is_safe(player.position)):
				player.dirty_character = true
		if not player.recall.is_empty():
			var origin: Vector3 = player.recall["origin"]
			if Vector2(player.position.x, player.position.z).distance_to(
					Vector2(origin.x, origin.z)) > HubRecall.MAX_MOVEMENT:
				_cancel_recall(player, "moved")
		# Distance on foot trains athletics (running) and explorer (any travel); never more than the
		# server itself moved the player.
		if moved > 0.0:
			player.travel_meters += moved
			while player.travel_meters >= SKILL_METERS_PER_EXPLORER_XP:
				player.travel_meters -= SKILL_METERS_PER_EXPLORER_XP
				_award(player, "explorer", 1.0)
			if sprint_allowed:
				player.run_meters += moved
				while player.run_meters >= SKILL_METERS_PER_ATHLETICS_XP:
					player.run_meters -= SKILL_METERS_PER_ATHLETICS_XP
					_award(player, "athletics", 1.0)
		if sprint_allowed and player.position.distance_to(before_move) > 0.01:
			player.noise_radius = maxf(player.noise_radius,
				SoftSoleWraps.sprint_noise(Defs.SPRINT_NOISE_RADIUS, player.soft_sole_seconds))
			player.noise_timer = maxf(player.noise_timer, Defs.SPRINT_NOISE_SECONDS)
		# A laden backpack rattles only after the server observes real travel.
		# Crouching suppresses this sound; mounted noise follows bike rules.
		var pack_noise: float = CargoRattle.radius(factor, moved,
			player.crouching, player.mounted)
		if pack_noise > 0.0:
			player.noise_radius = maxf(player.noise_radius, pack_noise)
			player.noise_timer = maxf(player.noise_timer, CargoRattle.NOISE_SECONDS)
		# Never trust movement or noise from a client. The server measures
		# actual travel after collision, and only an owned mount creates rattle.
		if player.mounted and moved > 0.0 and player.bike_service_meters > 0.0:
			player.bike_service_meters = BikeService.remaining_after_move(
				player.bike_service_meters, world.biome_at(before_move.x, before_move.z), moved)
			player.dirty_character = true
		var bike_noise: float = Mounts.noise_for_distance(moved) if player.mounted else 0.0
		if bike_noise > 0.0:
			player.noise_radius = maxf(player.noise_radius,
				BikeService.riding_noise_radius(player.bike_service_meters,
					BikeChain.riding_radius(player.chain_wrap_seconds)))
			player.noise_timer = maxf(player.noise_timer, Mounts.NOISE_SECONDS)
		if player.mounted and moved > 0.0:
			player.bike_integrity = BikeIntegrity.after_ride(player.bike_integrity,
				world.biome_at(before_move.x, before_move.z), moved)
			player.dirty_character = true
			if not BikeIntegrity.can_ride(player.bike_integrity):
				_dismount(player, false)
		# Walking away cancels gathering and shoreline fishing.
		if not player.action.is_empty():
			if player.action.has("fish"):
				var cast_at := Vector2(float(player.action["cast_x"]), float(player.action["cast_z"]))
				if Vector2(player.position.x, player.position.z).distance_to(cast_at) > 0.45:
					player.action = {}
			else:
				var node := _find_node(int(player.action["node"]))
				if node.is_empty() or _distance_xz(player.position, node) > Defs.REACH + 0.8 + _stone_reach_margin(node):
					player.action = {}


## Only an actual server-resolved movement update can record escort travel.
## Late party joins never qualify without traversing all checkpoints.
func _record_caravan_escort_move(escort: Player, moved: float) -> void:
	var group_id: int = parties.group_of(escort.id)
	if group_id <= 0 or not _alive(escort):
		return
	for member_id in parties.members_of(escort.id):
		if int(member_id) == escort.id:
			continue
		var courier: Player = players.get(int(member_id))
		if courier == null or not _alive(courier) or \
				courier.caravan_state.is_empty() or courier.caravan_view.is_empty():
			continue
		if courier.inventory.count(str(courier.caravan_view.get("cargo", ""))) < 1:
			continue
		CaravanEscortRewards.record(caravan_escort_progress,
			courier.id, escort.id, group_id, courier.caravan_view,
			courier.position, escort.position, moved)


## Fishing is a delayed, cancelable server action; no catch count is supplied
## by clients. Distinct from lake drinking and free berry scavenging.
## An authentic rod and procedural shore determine the maximum output tier;
## client sends no location, reward or duration, only intent to place.
func cmd_place_fish_trap(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	if fish_traps.size() >= ShoreFishTrap.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	for trap in fish_traps.values():
		if float(trap["expires"]) > time and Structures.can_manage(
				trap, peer_id, player.user_id):
			return {"ok": false, "reason": "owner_limit"}
	var rod: String = player.inventory.best_tool("fishing")
	if rod.is_empty():
		return {"ok": false, "reason": "need_rod"}
	var site: Dictionary = ShoreFishTrap.site(world, player.position, fish_traps, time)
	if not bool(site.get("ok", false)):
		return site
	if not player.inventory.remove(ShoreFishTrap.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var tier: int = Fishing.catch_tier(world.zone_at(player.position.x,
		player.position.z), Defs.tier_of(rod),
		player.progression.gathering_level("fishing"))
	var id := new_id()
	fish_traps[id] = {"id": id, "x": float(site["x"]),
		"z": float(site["z"]), "y": Defs.WATER_LEVEL,
		"owner": peer_id, "owner_account": player.user_id, "tier": tier,
		"ready_at": time + ShoreFishTrap.CATCH_SECONDS,
		"expires": time + ShoreFishTrap.LIFETIME_SECONDS}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "seconds": ShoreFishTrap.CATCH_SECONDS,
		"tier": tier}


## Authoritative pickup: no remote looting, expired nets, phantom XP or
## partial inventory transfers. Rights survive authenticated reconnection.
func cmd_collect_fish_trap(peer_id: int, trap_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	var trap: Dictionary = fish_traps.get(trap_id, {})
	if trap.is_empty() or time >= float(trap["expires"]):
		return {"ok": false, "reason": "no_trap"}
	if not Structures.can_manage(trap, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if not ShoreFishTrap.collectable(player.position, trap) or world.is_water(
			player.position.x, player.position.z):
		return {"ok": false, "reason": "out_of_range"}
	if time < float(trap["ready_at"]):
		return {"ok": false, "reason": "not_ready",
			"remaining": float(trap["ready_at"]) - time}
	var tier: int = int(trap["tier"])
	var fish_id: String = Fishing.catch_item(tier)
	if fish_id.is_empty() or player.inventory.free_space_for(fish_id) < ShoreFishTrap.COUNT:
		return {"ok": false, "reason": "no_space"}
	if player.inventory.add(fish_id, ShoreFishTrap.COUNT) != 0:
		return {"ok": false, "reason": "no_space"}
	fish_traps.erase(trap_id)
	player.progression.award_gather("fishing", tier, ShoreFishTrap.COUNT)
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "item": fish_id, "tier": tier, "count": ShoreFishTrap.COUNT}


func cmd_fish(peer_id: int, baited: bool = false, storm_cast: bool = false) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if bool(player.action.get("fish", false)):
		return _hook_fish(player) # Casting again while the line is out strikes at a bite.
	if not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	if time < player.fish_next_at:
		return {"ok": false, "reason": "cooldown"}
	if storm_cast and baited:
		return {"ok": false, "reason": "incompatible_modes"}
	var eligibility: Dictionary = Fishing.validate_start(world, player.position,
		player.inventory, player.progression.gathering_level("fishing"), baited)
	if not bool(eligibility.get("ok", false)):
		return eligibility
	if storm_cast and not StormFishing.qualifies(world, player.position, time):
		return {"ok": false, "reason": "not_storm_coast"}
	if storm_cast and player.inventory.free_space_for(str(eligibility["item"])) < StormFishing.MIN_FREE_FISH:
		return {"ok": false, "reason": "no_space"}
	var cast_seconds: float = StormFishing.CAST_SECONDS if storm_cast else Fishing.CAST_SECONDS
	player.action = {"fish": true, "cast_x": player.position.x, "cast_z": player.position.z,
		"tier": int(eligibility["tier"]), "catch_id": str(eligibility["item"]),
		"baited": baited, "storm_cast": storm_cast,
		"remaining": cast_seconds, "total": cast_seconds,
		"bite_at": Fishing.bite_at(cast_seconds, rng.randf()), "hooked": false, "struck": false}
	player.fish_next_at = time + cast_seconds + Fishing.COOLDOWN_SECONDS
	return {"ok": true, "seconds": cast_seconds,
		"tier": int(eligibility["tier"]), "item": str(eligibility["item"]),
		"baited": baited, "storm_cast": storm_cast}


## Down the hatch of a bunker into its dungeon (`down`), or up the stairs of the first room back to the hatch.
func cmd_dungeon(peer_id: int, down: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.action.is_empty() or not player.recall.is_empty():
		return {"ok": false, "reason": "busy"}
	var at := Vector2(player.position.x, player.position.z)
	if down:
		if Dungeon.is_underground(at.x):
			return {"ok": false, "reason": "already_below"}
		var bunker: Dictionary = Dungeon.bunker_at(world, at.x, at.y)
		if bunker.is_empty():
			return {"ok": false, "reason": "no_hatch"}
		var region: Vector2i = Dungeon.region_of_site(bunker)
		if world.dungeon_bunker(region).is_empty():
			return {"ok": false, "reason": "no_hatch"}
		var below: Vector2 = Dungeon.arrival(region)
		player.position = Vector3(below.x, Dungeon.FLOOR_Y, below.y)
		if StoryChapterTwo.record_descent(player.story2_state):
			player.dirty_character = true
			_story2_event(player)
		events.append({"type": "dungeon_entered", "peer": peer_id, "zone": world.zone_at(below.x, below.y)})
		return {"ok": true, "down": true, "zone": world.zone_at(below.x, below.y)}
	if not Dungeon.is_underground(at.x) or not Dungeon.at_stairs(at.x, at.y):
		return {"ok": false, "reason": "no_stairs"}
	var above: Dictionary = world.dungeon_bunker(Dungeon.region_of(at.x, at.y))
	if above.is_empty():
		return {"ok": false, "reason": "no_stairs"}
	var out: Vector2 = Dungeon.hatch(world, above) + Vector2(0, 1.6)
	player.position = Vector3(out.x, world.height_at(out.x, out.y), out.y)
	events.append({"type": "dungeon_left", "peer": peer_id})
	return {"ok": true, "down": false}


## What a player is visibly doing, for the others: "fish", "chop" (a tree), "harvest" (anything else gathered) or "".
## Only the kind of work: never the node, the catch, the timing or the bite.
func _public_action(player: Player) -> String:
	if player.action.is_empty():
		return ""
	if bool(player.action.get("fish", false)):
		return "fish"
	var node: Dictionary = _find_node(int(player.action.get("node", -1)))
	return "chop" if str(node.get("kind", "")) == "tree" else "harvest"


## One strike per cast: inside the bite window it hooks the fish (a bigger catch), outside it the fish slips away.
func _hook_fish(player: Player) -> Dictionary:
	if bool(player.action.get("struck", false)):
		return {"ok": false, "reason": "already_struck"}
	player.action["struck"] = true
	if Fishing.biting(float(player.action.get("remaining", 0.0)), float(player.action.get("bite_at", -1.0))):
		player.action["hooked"] = true
		events.append({"type": "fish_hooked", "peer": player.id})
		return {"ok": true, "hooked": true}
	return {"ok": false, "reason": "no_bite"}


func cmd_gather(peer_id: int, node_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	var node := _find_node_near(node_id, player.position)
	if node.is_empty():
		return {"ok": false, "reason": "no_such_node"}
	if depleted.has(node_id):
		return {"ok": false, "reason": "depleted"}
	if _distance_xz(player.position, node) > Defs.REACH + 0.5 + _stone_reach_margin(node):
		return {"ok": false, "reason": "too_far"}
	var info := Defs.node_info(node["kind"])
	var required_tool := Defs.tool_tier_for_node(node["kind"])
	var tool_tier := 0
	var speed := 1.0
	if required_tool != "":
		var tool_id: String = player.inventory.best_tool(required_tool)
		tool_tier = Defs.tier_of(tool_id) if tool_id != "" else 0
		# Hands only manage tier 1; better tools gather faster.
		if tool_tier < int(node["tier"]) and not (tool_tier == 0 and int(node["tier"]) == 1):
			return {"ok": false, "reason": "need_tool", "tier": node["tier"], "tool": required_tool}
		speed = 0.45 if tool_tier == 0 else 1.0 + 0.6 * (tool_tier - 1) + 0.5
	# Tool tier and profession tier are independent: a bought tool is not enough.
	if not player.progression.can_gather(String(node["kind"]), int(node["tier"])):
		return {"ok": false, "reason": "need_skill", "skill": Progression.resource_skill(String(node["kind"])), "tier": node["tier"]}
	var gather_skill := Skills.skill_for_node(String(node["kind"]))
	if gather_skill != "":
		speed *= 1.0 + player.skills.bonus("gather_speed." + gather_skill)
	# Loose pebbles are picked up immediately and do not start mining.
	# Still use the authoritative inventory/depletion/event pipeline.
	if str(node["kind"]) == "pebble":
		if player.inventory.free_space_for("stone_1") < 1:
			return {"ok": false, "reason": "inventory_full"}
		player.action = {"node": node_id, "remaining": 0.0, "total": 0.0}
		_finish_gather(player, node)
		return {"ok": true, "pickup": true}
	var total := float(info["seconds"]) / speed
	player.action = {"node": node_id, "remaining": total, "total": total}
	return {"ok": true, "seconds": total}


## E: immediate, server-authoritative pickup of a loose ground stone or fallen branch.
func cmd_resource_pickup(peer_id: int, node_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted or not player.recall.is_empty() or not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	var node: Dictionary = _find_node_near(node_id, player.position)
	if node.is_empty() or not ResourceGathering.is_pickup(str(node.get("kind", ""))):
		return {"ok": false, "reason": "not_pickup"}
	if depleted.has(node_id):
		return {"ok": false, "reason": "depleted"}
	# Match the client model-footprint reach and reject invalid positions.
	var pickup_distance: float = _distance_xz(player.position, node) if player.position.is_finite() else INF
	if not is_finite(pickup_distance) or pickup_distance > Defs.REACH + 0.5 + ResourceGathering.reach_margin(node):
		return {"ok": false, "reason": "too_far"}
	if not player.progression.can_gather(str(node["kind"]), int(node["tier"])):
		return {"ok": false, "reason": "need_skill",
			"skill": Progression.resource_skill(str(node["kind"])), "tier": node["tier"]}
	var info: Dictionary = Defs.node_info(str(node["kind"]))
	var item_id: String = str(info["yield"])
	if item_id in ["wood", "stone", "ore", "fiber"]:
		item_id = "%s_%d" % [item_id, int(node["tier"])]
	if player.inventory.free_space_for(item_id) < int(info["amount"]):
		return {"ok": false, "reason": "inventory_full"}
	_finish_gather(player, node)
	return {"ok": true, "item": item_id}


## LMB: one validated swing against a real generated world node (not cosmetic props).
## Shared per-node progress avoids two players each claiming the full harvest.
func cmd_resource_hit(peer_id: int, node_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted or not player.recall.is_empty() or not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	var node: Dictionary = _find_node_near(node_id, player.position)
	if node.is_empty() or not ResourceGathering.is_strike(str(node.get("kind", ""))):
		return {"ok": false, "reason": "not_mineable"}
	if depleted.has(node_id):
		return {"ok": false, "reason": "depleted"}
	if not ResourceGathering.aimed_at(player.position, node, Vector2(dir_x, dir_z)):
		return {"ok": false, "reason": "too_far_or_not_aimed"}
	var kind: String = str(node["kind"])
	var tier: int = int(node["tier"])
	var tool: String = Defs.tool_tier_for_node(kind)
	var tool_id: String = player.inventory.best_tool(tool)
	var tool_tier: int = Defs.tier_of(tool_id) if not tool_id.is_empty() else 0
	if tool_tier < tier and not (tool_tier == 0 and tier == 1):
		return {"ok": false, "reason": "need_tool", "tier": tier, "tool": tool}
	if not player.progression.can_gather(kind, tier):
		return {"ok": false, "reason": "need_skill", "skill": Progression.resource_skill(kind), "tier": tier}
	if time < player.resource_next_hit_at:
		return {"ok": false, "reason": "swing_cooldown"}
	var hits_needed: int = ResourceGathering.strikes_needed(kind)
	var progress: Dictionary = resource_hit_progress.get(node_id, {})
	# An abandoned half-mined node must not reset and yield its first hits forever.
	if not progress.is_empty() and time >= float(progress.get("expires", 0.0)):
		resource_hit_progress.erase(node_id)
		depleted[node_id] = time + float(Defs.node_info(kind)["respawn"])
		world.set_node_depleted(node_id, true)
		return {"ok": false, "reason": "depleted"}
	var current_hits: int = int(progress.get("hits", 0))
	var hit: int = mini(current_hits + 1, hits_needed)
	var accurate: bool = ResourceGathering.precise_strike(
		player.position, node, Vector2(dir_x, dir_z), current_hits)
	# A perfect weak-spot strike adds one resource immediately. Neither the
	# client nor a repeated RPC can invent or replay this bonus.
	var amount: int = ResourceGathering.strike_yield(kind, hit) + (1 if accurate else 0)
	var item_id: String = "%s_%d" % [str(Defs.node_info(kind)["yield"]), tier]
	if amount > 0 and player.inventory.free_space_for(item_id) < amount:
		return {"ok": false, "reason": "inventory_full"}
	player.resource_next_hit_at = time + ResourceGathering.swing_cooldown(tool_tier)
	var finished: bool = hit >= hits_needed
	if not finished:
		resource_hit_progress[node_id] = {"hits": hit,
			"expires": time + ResourceGathering.PROGRESS_EXPIRE_SECONDS,
			"respawn": float(Defs.node_info(kind)["respawn"]),
			"x": float(node["x"]), "z": float(node["z"])}
	_finish_gather(player, node, amount, finished, true, hit, accurate)
	return {"ok": true, "hit": hit, "total_hits": hits_needed,
		"finished": finished, "item": item_id, "precise": accurate}


func cmd_craft(peer_id: int, recipe_id: String, times: int = 1,
		from_stash: bool = false, use_focus: bool = false) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	# Using account-protected items is an exclusive hub bank privilege,
	# never available at rural benches, field outposts or wilderness fires.
	if from_stash and not _market_at_hub(player):
		return {"ok": false, "reason": "no_station"}
	times = clampi(times, 1, 50)
	var recipe: Dictionary = Defs.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	var recipe_tier: int = maxi(1, Defs.tier_of(String(recipe["output"])))
	if not player.progression.can_craft_tier(recipe_tier):
		return {"ok": false, "reason": "need_skill", "skill": "crafting", "tier": recipe_tier}
	var focus_needed: int = ReturnRate.focus_cost(String(recipe["output"]), recipe_tier, times) if use_focus else 0
	if use_focus:
		if not (player.position.is_finite() and _is_safe(player.position) and _at_workbench(Vector2(player.position.x, player.position.z))):
			return {"ok": false, "reason": "focus_needs_city"}
		if player.progression.focus < float(focus_needed):
			return {"ok": false, "reason": "need_focus", "focus": int(player.progression.focus), "cost": focus_needed}
	var at_bench: bool = player.position.is_finite() and (
		_at_workbench(Vector2(player.position.x, player.position.z))
		or territory.has_field_workbench(peer_id, players, parties, time)
		or _near_piece(player.position, "workbench"))
	var at_fire: bool = String(recipe["station"]) == "campfire" and FieldCampfire.has_warmth(
			campfires, player.position, time)
	var status: int = CraftFromStash.craft(
		player.inventory, player.stash, recipe_id, times
	) if from_stash else Crafting.craft(
		player.inventory, recipe_id, at_bench, times, at_fire)
	if status == Crafting.Result.OK:
		player.progression.award_craft(recipe_tier, times)
		_award(player, "crafting", 8.0 * float(recipe_tier) * float(times))
		# Skill: each batch may save a unit of one of its materials.
		var input_ids: Array = recipe["inputs"].keys()
		for batch in times:
			if not input_ids.is_empty() and rng.randf() < player.skills.bonus("craft_refund"):
				player.inventory.add(String(input_ids[rng.randi() % input_ids.size()]), 1)
		# Albion-style focus: crafting with focus at a city workbench returns part of the materials.
		var in_settlement: bool = player.position.is_finite() and _is_safe(player.position) \
			and _at_workbench(Vector2(player.position.x, player.position.z))
		var spent: Dictionary = {}
		for input_id in recipe["inputs"]:
			spent[input_id] = int(recipe["inputs"][input_id]) * times
		var returned: Dictionary = {}
		if use_focus and in_settlement:
			returned = ReturnRate.returned(spent, ReturnRate.FOCUS_RATE, rng)
			player.progression.focus = maxf(0.0, player.progression.focus - float(focus_needed))
		for input_id in returned:
			var target_bag = player.stash if from_stash else player.inventory
			var overflow: int = target_bag.add(String(input_id), int(returned[input_id]))
			if overflow > 0 and target_bag != player.inventory:
				player.inventory.add(String(input_id), overflow)
		# Quality: each crafted piece of gear rolls Normal..Masterpiece; higher crafting rank helps.
		var output: String = String(recipe["output"])
		var best: int = 1
		if craft_quality_enabled and Defs.can_have_quality(output):
			var luck: float = 0.1 * float(maxi(0, player.progression.crafting_level() - recipe_tier))
			for unit in times * int(recipe.get("count", 1)):
				var q: int = Defs.roll_quality(rng, luck)
				if q > 1 and player.inventory.remove(output, 1):
					if player.inventory.add(Defs.with_quality(output, q), 1) > 0:
						player.inventory.add(output, 1)
					else:
						best = maxi(best, q)
		if best >= 4:
			events.append({"type": "masterwork", "peer": peer_id, "item": Defs.with_quality(output, best)})
		player.inventory.unequip_missing()
		player.dirty_inventory = true
		if from_stash:
			player.dirty_stash = true
		player.dirty_character = true
		return {"ok": true, "recipe": recipe_id, "times": times,
			"from_stash": from_stash, "best_quality": best, "returned": returned}
	return {"ok": false, "reason": ["ok", "unknown_recipe", "missing_inputs", "no_station", "no_space"][status],
		"from_stash": from_stash}


## Recycle unused equipment at the settlement workbench.
## No client-provided refund amounts: recipe and inventory are server-owned.
func cmd_salvage_gear(peer_id: int, item_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var at := Vector2(player.position.x, player.position.z)
	if not player.position.is_finite() or not _is_safe(player.position) or (
			at.distance_to(WORKBENCH_POSITION) > WORKBENCH_RANGE):
		return {"ok": false, "reason": "no_station"}
	var outcome: Dictionary = GearSalvage.transact(player.inventory, item_id)
	if bool(outcome.get("ok", false)):
		player.dirty_inventory = true
		player.dirty_character = true
	return outcome


# --- Cooperative survivor parties (classic MMO-style group play) -----------------------
## Invite only a real nearby player. All membership and leadership is
## session-owned; no client supplies a party ID or its member list.

## Mutual, proximity-checked hub sparring: no loot, crimes or PvP rewards.
## Voluntary ranked match search. Queueing means consenting to a rated
## match against a valid opponent, with existing nonlethal duel protections.
func cmd_arena_queue_join(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	var reason: String = ArenaMatchmaking.join_reason(world, player, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	if training_matches.has(peer_id) or training_invites.has(peer_id):
		return {"ok": false, "reason": "already_dueling"}
	for invitation in training_invites.values():
		if int(invitation.get("from", -1)) == peer_id:
			return {"ok": false, "reason": "invite_pending"}
	if arena_queue.has(peer_id):
		return {"ok": true, "status": "queued"}
	if arena_queue.size() >= ArenaMatchmaking.MAX_QUEUED:
		return {"ok": false, "reason": "queue_full"}
	arena_queue[peer_id] = {"account": player.user_id,
		"instance": player.get_instance_id(), "at": time}
	events.append({"type": "arena_queue", "peer": peer_id, "status": "queued"})
	return {"ok": true, "status": "queued"}


func cmd_arena_queue_leave(peer_id: int) -> Dictionary:
	if not arena_queue.has(peer_id):
		return {"ok": false, "reason": "not_queued"}
	arena_queue.erase(peer_id)
	events.append({"type": "arena_queue", "peer": peer_id, "status": "left"})
	return {"ok": true, "status": "left"}


func _tick_arena_queue() -> void:
	# Revalidate after movement, death, reconnect and direct challenges. A
	# queue entry never extends a duel or combat-tag permission.
	for peer_id in arena_queue.keys():
		var player: Player = players.get(peer_id)
		if not ArenaMatchmaking.entry_valid(arena_queue[peer_id], player, world,
				time, training_matches, training_invites):
			arena_queue.erase(peer_id)
			if player != null:
				events.append({"type": "arena_queue", "peer": peer_id, "status": "cancelled"})
	var pair: Array[int] = ArenaMatchmaking.choose(arena_queue, players, world,
		time, arena_recent_pairs, training_matches, training_invites)
	if pair.size() != 2:
		return
	# The two users already opted in. Reuse the ordinary validated duel
	# invitation/acceptance path instead of minting a second combat system.
	var invitation: Dictionary = cmd_duel_invite(pair[0], pair[1], true)
	if not bool(invitation.get("ok", false)):
		return
	var result: Dictionary = cmd_duel_accept(pair[1])
	if not bool(result.get("ok", false)):
		training_invites.erase(pair[1])
		return
	arena_queue.erase(pair[0])
	arena_queue.erase(pair[1])


func _arena_queue_state(peer_id: int) -> Dictionary:
	var state: Dictionary = arena_queue.get(peer_id, {})
	if state.is_empty():
		return {"queued": false}
	return {"queued": true, "seconds": maxf(0.0, time - float(state["at"])),
		"search_gap": ArenaMatchmaking.gap_after(time - float(state["at"]))}


func cmd_duel_invite(peer_id: int, target_id: int, ranked: bool = false) -> Dictionary:
	var source: Player = players.get(peer_id)
	var target: Player = players.get(target_id)
	var denial: String = TrainingDuel.invitation_reason(world, source, target, time)
	if denial != "":
		return {"ok": false, "reason": denial}
	if training_matches.has(peer_id) or training_matches.has(target_id):
		return {"ok": false, "reason": "already_dueling"}
	if ranked:
		var eligibility: String = ArenaRating.eligibility(source, target, time, arena_recent_pairs)
		if eligibility != "":
			return {"ok": false, "reason": eligibility}
	if time < float(training_invite_last.get(peer_id, -INF)) + TrainingDuel.INVITE_COOLDOWN:
		return {"ok": false, "reason": "cooldown"}
	if training_invites.has(target_id) and float(training_invites[target_id].get("until", 0.0)) > time:
		return {"ok": false, "reason": "invite_pending"}
	training_invite_last[peer_id] = time
	training_invites[target_id] = {"from": peer_id, "ranked": ranked,
		"until": time + TrainingDuel.INVITE_SECONDS,
		"from_instance": source.get_instance_id(), "to_instance": target.get_instance_id()}
	events.append({"type": "duel", "peer": target_id, "phase": "invited",
		"name": source.name, "by": peer_id, "ranked": ranked})
	return {"ok": true, "phase": "invited", "ranked": ranked}


func cmd_duel_accept(peer_id: int) -> Dictionary:
	var invite: Dictionary = training_invites.get(peer_id, {})
	if invite.is_empty() or float(invite.get("until", 0.0)) <= time:
		training_invites.erase(peer_id)
		return {"ok": false, "reason": "no_invite"}
	var first: Player = players.get(int(invite["from"]))
	var second: Player = players.get(peer_id)
	if first == null or second == null or first.get_instance_id() != int(invite["from_instance"]) or \
			second.get_instance_id() != int(invite["to_instance"]):
		training_invites.erase(peer_id)
		return {"ok": false, "reason": "stale_invite"}
	var denial: String = TrainingDuel.invitation_reason(world, first, second, time)
	if denial != "" or training_matches.has(first.id) or training_matches.has(second.id):
		training_invites.erase(peer_id)
		return {"ok": false, "reason": denial if denial != "" else "already_dueling"}
	if bool(invite.get("ranked", false)):
		var status: String = ArenaRating.eligibility(first, second, time, arena_recent_pairs)
		if status != "":
			training_invites.erase(peer_id)
			return {"ok": false, "reason": status}
	training_invites.erase(peer_id)
	var duel: Dictionary = {"a": first.id, "b": second.id,
		"ranked": bool(invite.get("ranked", false)),
		"until": time + TrainingDuel.MATCH_SECONDS,
		"a_hp": first.survival.health, "b_hp": second.survival.health}
	training_matches[first.id] = duel
	training_matches[second.id] = duel
	arena_queue.erase(first.id)
	arena_queue.erase(second.id)
	for member in [first, second]:
		events.append({"type": "duel", "peer": member.id, "phase": "started",
			"opponent": second.name if member.id == first.id else first.name,
			"seconds": TrainingDuel.MATCH_SECONDS, "ranked": bool(duel["ranked"])})
	return {"ok": true, "phase": "started", "ranked": bool(duel["ranked"])}


func cmd_duel_cancel(peer_id: int) -> Dictionary:
	if training_matches.has(peer_id):
		var duel: Dictionary = training_matches[peer_id]
		var winner: int = -1
		if bool(duel.get("ranked", false)):
			winner = int(duel["b"]) if peer_id == int(duel["a"]) else int(duel["a"])
		_end_training(peer_id, winner, "surrender" if winner > 0 else "cancelled")
		return {"ok": true, "phase": "cancelled"}
	if training_invites.has(peer_id):
		training_invites.erase(peer_id)
		return {"ok": true, "phase": "declined"}
	var found: bool = false
	for target_id in training_invites.keys():
		if int(training_invites[target_id].get("from", -1)) == peer_id:
			training_invites.erase(target_id)
			found = true
	return {"ok": found, "reason": "" if found else "no_duel"}


func _end_training(peer_id: int, winner_id: int, reason: String) -> void:
	var duel: Dictionary = training_matches.get(peer_id, {})
	if duel.is_empty():
		return
	var a: int = int(duel["a"])
	var b: int = int(duel["b"])
	training_matches.erase(a)
	training_matches.erase(b)
	var rating_result: Dictionary = {}
	if bool(duel.get("ranked", false)) and winner_id in [a, b] and reason in ["knockout", "surrender", "disconnected"]:
		var winner: Player = players.get(winner_id)
		var loser: Player = players.get(b if winner_id == a else a)
		if winner != null and loser != null:
			rating_result = ArenaRating.settle(winner, loser, time, arena_recent_pairs)
	for member_id in [a, b]:
		var member: Player = players.get(member_id)
		if member == null:
			continue
		if _alive(member):
			var initial: float = float(duel["a_hp"] if member_id == a else duel["b_hp"])
			member.survival.health = maxf(member.survival.health, initial)
		events.append({"type": "duel", "peer": member_id, "phase": "finished",
			"winner": winner_id, "reason": reason, "ranked": bool(duel.get("ranked", false)),
			"rating": member.arena_rating, "rating_change": int(rating_result.get("change", 0)) if member_id == winner_id else -int(rating_result.get("change", 0))})


func _abort_training(peer_id: int, reason: String) -> void:
	var duel: Dictionary = training_matches.get(peer_id, {})
	var winner_id: int = -1
	if reason == "disconnected" and bool(duel.get("ranked", false)):
		winner_id = int(duel["b"]) if peer_id == int(duel["a"]) else int(duel["a"])
	_end_training(peer_id, winner_id, reason)
	training_invites.erase(peer_id)
	for target_id in training_invites.keys():
		if int(training_invites[target_id].get("from", -1)) == peer_id:
			training_invites.erase(target_id)


func _tick_training() -> void:
	for peer_id in training_matches.keys():
		var duel: Dictionary = training_matches.get(peer_id, {})
		if duel.is_empty() or int(duel["a"]) != int(peer_id):
			continue
		var first: Player = players.get(int(duel["a"]))
		var second: Player = players.get(int(duel["b"]))
		if not TrainingDuel.active_for(training_matches, world, first, second, time):
			_end_training(int(peer_id), -1, "expired_or_left_hub")
	for peer_id in training_invites.keys():
		if float(training_invites[peer_id]["until"]) <= time:
			training_invites.erase(peer_id)


func _training_snapshot(peer_id: int) -> Dictionary:
	var match_data: Dictionary = training_matches.get(peer_id, {})
	if not match_data.is_empty():
		return {"active": true, "ranked": bool(match_data.get("ranked", false)),
			"opponent": int(match_data["b"]) if peer_id == int(match_data["a"]) else int(match_data["a"]),
			"seconds": maxf(0.0, float(match_data["until"]) - time)}
	var invite: Dictionary = training_invites.get(peer_id, {})
	if not invite.is_empty() and float(invite["until"]) > time:
		return {"active": false, "invite_from": int(invite["from"]),
			"ranked": bool(invite.get("ranked", false)),
			"seconds": float(invite["until"]) - time}
	return {}


func cmd_party_invite(peer_id: int, target_id: int) -> Dictionary:
	var source: Player = players.get(peer_id)
	var target: Player = players.get(target_id)
	if source == null or target == null or not _alive(source) or not _alive(target):
		return {"ok": false, "reason": "unavailable"}
	if not _party_invite_in_range(source, target):
		return {"ok": false, "reason": "too_far"}
	return parties.invite(peer_id, target_id, time)


func _party_invite_in_range(first: Player, second: Player) -> bool:
	var a := Vector2(first.position.x, first.position.z)
	var b := Vector2(second.position.x, second.position.z)
	return a.is_finite() and b.is_finite() and a.distance_to(b) <= Party.INVITE_RANGE


func cmd_party_accept(peer_id: int) -> Dictionary:
	var target: Player = players.get(peer_id)
	if target == null or not _alive(target):
		return {"ok": false, "reason": "dead"}
	var invite: Dictionary = parties.invites.get(peer_id, {})
	if invite.is_empty():
		return {"ok": false, "reason": "no_invite"}
	if time >= float(invite["expires"]):
		return parties.accept(peer_id, time)
	var leader: Player = players.get(int(invite["from"]))
	if leader == null or not _alive(leader):
		return {"ok": false, "reason": "leader_offline"}
	if not _party_invite_in_range(leader, target):
		return {"ok": false, "reason": "too_far"}
	return parties.accept(peer_id, time)


func cmd_party_decline(peer_id: int) -> Dictionary:
	return parties.decline(peer_id)


func cmd_party_leave(peer_id: int) -> Dictionary:
	var outcome: Dictionary = parties.leave(peer_id)
	if bool(outcome.get("ok", false)):
		CaravanEscortRewards.clear_peer(caravan_escort_progress, peer_id)
	return outcome


func cmd_party_kick(peer_id: int, target_id: int) -> Dictionary:
	var outcome: Dictionary = parties.kick(peer_id, target_id)
	if bool(outcome.get("ok", false)):
		CaravanEscortRewards.clear_peer(caravan_escort_progress, target_id)
	return outcome


## The server determines the caller's identity and current simulation time.
func cmd_party_ready_start(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	# Nobody should claim a raid is ready while a teammate is down.
	for member_id in parties.members_of(peer_id):
		var member: Player = players.get(int(member_id))
		if member == null or not _alive(member):
			return {"ok": false, "reason": "member_unavailable"}
	return parties.start_ready_check(peer_id, time)


func cmd_party_ready_answer(peer_id: int, ready: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	return parties.answer_ready_check(peer_id, ready, time)


## Only actual, positive HP restored to a nearby party member already engaged
## with an infected can create healer threat. This is never an RPC command.
## One multi-target cast adds at most one bounded entry per living infected.
func _record_party_healing_threat(medic: Player, patients: Array) -> void:
	if medic == null or not _alive(medic) or not medic.position.is_finite() \
			or _is_safe(medic.position) or patients.is_empty():
		return
	var group_id: int = parties.group_of(medic.id)
	if group_id == 0:
		return
	var zone: int = world.zone_at(medic.position.x, medic.position.z)
	for infected in zombies.values():
		if not infected.is_alive() or not infected.position.is_finite() or \
				world.zone_at(infected.position.x, infected.position.z) != zone:
			continue
		var total_healed: float = 0.0
		for entry in patients:
			var recipient: Player = entry.get("recipient", null)
			var restored: float = float(entry.get("healed", 0.0))
			if recipient == null or not _alive(recipient) or \
				parties.group_of(recipient.id) != group_id or \
				_is_safe(recipient.position) or \
				world.zone_at(recipient.position.x, recipient.position.z) != zone:
				continue
			if HealingAggro.can_credit(infected, medic.position,
					recipient.position, recipient.id):
				total_healed += restored
		var generated: float = HealingAggro.threat_for(total_healed)
		if generated > 0.0:
			Threat.record(infected.threat, medic.id, generated)


## Panic button for medics: ask the nearest real, armed guardian to cover them.
## No client-controlled enemy IDs, guardian IDs, range, aggro, threat or damage.
## Only currently engaged non-boss infected with genuine medic attention qualify.
func cmd_medic_cover(peer_id: int) -> Dictionary:
	var medic: Player = players.get(peer_id)
	if medic == null or not _alive(medic):
		return {"ok": false, "reason": "dead"}
	if medic.mounted:
		return {"ok": false, "reason": "mounted"}
	if not medic.position.is_finite() or _is_safe(medic.position):
		return {"ok": false, "reason": "safe_zone"}
	if parties.members_of(peer_id).size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	if not MedicCover.has_staff(medic):
		return {"ok": false, "reason": "need_restoration_staff"}
	if medic.medic_cover_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown",
			"remaining": medic.medic_cover_cooldown}
	if medic.combat_energy < MedicCover.ENERGY_COST:
		return {"ok": false, "reason": "no_energy"}
	var guardian = MedicCover.guardian_for(medic, players, parties, world)
	if guardian == null:
		return {"ok": false, "reason": "no_guardian"}
	var candidates: Array = []
	for infected in zombies.values():
		if MedicCover.can_redirect(infected, medic, guardian, world):
			candidates.append(infected)
	if candidates.is_empty():
		return {"ok": false, "reason": "no_engaged_infected"}
	# Stable target selection avoids positional jitter in a crowded battle.
	candidates.sort_custom(func(a, b): return a.id < b.id)
	var redirected: int = 0
	for i in range(mini(MedicCover.MAX_ENEMIES, candidates.size())):
		var infected = candidates[i]
		if infected.force_taunt(guardian.id, MedicCover.TAUNT_SECONDS):
			MedicCover.fade_threat(infected, medic.id)
			redirected += 1
	if redirected <= 0:
		return {"ok": false, "reason": "no_engaged_infected"}
	medic.combat_energy -= MedicCover.ENERGY_COST
	medic.medic_cover_cooldown = MedicCover.COOLDOWN
	medic.action = {}
	events.append({"type": "medic_cover", "peer": peer_id,
		"by": guardian.id, "count": redirected})
	return {"ok": true, "guardian": guardian.id, "count": redirected,
		"cooldown": MedicCover.COOLDOWN, "energy": medic.combat_energy}


## A trusted survival check broadcasts only a genuine low-supply request
## to the current party. The client supplies neither coordinates nor level.
func cmd_party_supply_request(peer_id: int, need: String) -> Dictionary:
	var requester: Player = players.get(peer_id)
	if requester == null or not _alive(requester):
		return {"ok": false, "reason": "dead"}
	var group_id: int = parties.group_of(peer_id)
	if group_id == 0 or parties.members_of(peer_id).size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	if not PartySupplyRequest.valid_need(need):
		return {"ok": false, "reason": "invalid_need"}
	if not PartySupplyRequest.eligible(need, requester.survival.hunger, requester.survival.thirst):
		return {"ok": false, "reason": "no_need"}
	if not PartySupplyRequest.can_send(time, requester.supply_request_last_at):
		return {"ok": false, "reason": "cooldown"}
	if not requester.position.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	var level: float = PartySupplyRequest.level(need,
		requester.survival.hunger, requester.survival.thirst)
	requester.supply_request_last_at = time
	events.append({"type": "party_supply_request", "peer": peer_id,
		"group": group_id, "name": requester.name, "need": need,
		"level": roundi(level), "x": requester.position.x,
		"z": requester.position.z,
		"expires": time + PartySupplyRequest.ALERT_SECONDS})
	return {"ok": true, "need": need, "level": roundi(level),
		"seconds": PartySupplyRequest.COOLDOWN}


## Item-powered party medicine and provisions, resolved only on the server.
func cmd_party_aid(peer_id: int, target_id: int, item_id: String) -> Dictionary:
	var source: Player = players.get(peer_id)
	var recipient: Player = players.get(target_id)
	if source == null or not _alive(source):
		return {"ok": false, "reason": "dead"}
	if peer_id == target_id:
		return {"ok": false, "reason": "self"}
	if recipient == null:
		return {"ok": false, "reason": "invalid_target"}
	if not _alive(recipient):
		return {"ok": false, "reason": "dead"}
	var group: int = parties.group_of(peer_id)
	if group == 0 or parties.group_of(target_id) != group:
		return {"ok": false, "reason": "not_in_party"}
	if not PartyAid.can_reach(source.position, recipient.position):
		return {"ok": false, "reason": "too_far"}
	if source.party_aid_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var selected_item_id: String = item_id
	if selected_item_id == "auto":
		selected_item_id = PartyAid.best_item(source.inventory,
			recipient.survival.health, recipient.survival.infection,
			recipient.survival.bleeding, recipient.survival.fracture,
			recipient.survival.max_health, recipient.survival.food_poisoning)
		if selected_item_id.is_empty():
			return {"ok": false, "reason": "no_treatment"}
	var data: Dictionary = Defs.item(selected_item_id)
	if not PartyAid.supported_item(selected_item_id, data):
		return {"ok": false, "reason": "not_shareable"}
	if source.inventory.count(selected_item_id) < 1:
		return {"ok": false, "reason": "not_carried"}
	if selected_item_id == WoundSealant.ITEM_ID:
		# Party first aid can prepare an ally BEFORE combat. The existing
		# party, reach, carried-inventory and five-second cooldown checks
		# have already run. Never allow a teammate to refresh this buff.
		if not SaveValidation.finite_number(recipient.wound_seal_seconds,
				0.0, WoundSealant.DURATION_SECONDS):
			return {"ok": false, "reason": "invalid_state"}
		if recipient.wound_seal_seconds > 0.0:
			return {"ok": false, "reason": "already_sealed",
				"remaining": recipient.wound_seal_seconds}
		if source.mounted or recipient.mounted:
			return {"ok": false, "reason": "mounted"}
		# Real PvE pursuits matter even without a PvP combat tag. Reuse the
		# trusted infected pressure scan; no client may declare safety.
		if CombatStress.pressure(zombies, source.id, source.position) > 0.0 or \
				CombatStress.pressure(zombies, recipient.id, recipient.position) > 0.0:
			return {"ok": false, "reason": "in_combat"}
		if source.combat_tag_until > time or recipient.combat_tag_until > time or \
				source.attack_timer > 0.0 or recipient.attack_timer > 0.0 or \
				source.skill_timer > 0.0 or recipient.skill_timer > 0.0 or \
				not source.action.is_empty() or not recipient.action.is_empty():
			return {"ok": false, "reason": "in_combat"}
		if not source.inventory.remove(selected_item_id, 1):
			return {"ok": false, "reason": "not_carried"}
		recipient.wound_seal_seconds = WoundSealant.DURATION_SECONDS
		source.party_aid_timer = PartyAid.COOLDOWN
		source.dirty_inventory = true
		source.dirty_character = true
		recipient.dirty_character = true
		events.append({"type": "party_aid", "peer": target_id, "by": peer_id,
			"item": selected_item_id, "wound_seal_seconds": WoundSealant.DURATION_SECONDS})
		return {"ok": true, "peer": target_id, "item": selected_item_id,
			"wound_seal_seconds": WoundSealant.DURATION_SECONDS}
	if not PartyAid.has_effect(data, recipient.survival.health, recipient.survival.infection,
			recipient.survival.bleeding, recipient.survival.fracture,
			recipient.survival.hunger, recipient.survival.thirst,
			recipient.survival.max_health, recipient.survival.food_poisoning):
		return {"ok": false, "reason": "no_effect"}
	var hp_before: float = recipient.survival.health
	var infection_before: float = recipient.survival.infection
	var poison_before: float = recipient.survival.food_poisoning
	var bleeding_before: float = recipient.survival.bleeding
	var fracture_before: float = recipient.survival.fracture
	var hunger_before: float = recipient.survival.hunger
	var thirst_before: float = recipient.survival.thirst
	if not source.inventory.remove(selected_item_id, 1):
		return {"ok": false, "reason": "not_carried"}
	recipient.survival.heal(PartyMedicMastery.heal_amount(
		float(data.get("heal", 0.0)), source.skills.bonus("heal_power")))
	recipient.survival.treat_infection(float(data.get("cure", 0.0)))
	if bool(data.get("stop_bleeding", false)):
		recipient.survival.stop_bleeding()
	recipient.survival.treat_fracture(float(data.get("fracture_treatment", 0.0)))
	recipient.survival.treat_food_poisoning(float(data.get("food_poison_treatment", 0.0)))
	recipient.survival.eat(float(data.get("food", 0.0)))
	recipient.survival.drink(float(data.get("drink", 0.0)))
	source.party_aid_timer = PartyAid.COOLDOWN
	source.action = {}
	source.dirty_inventory = true
	source.dirty_character = true
	recipient.dirty_character = true
	var healed: float = recipient.survival.health - hp_before
	_record_party_healing_threat(source, [{"recipient": recipient, "healed": healed}])
	var cured: float = infection_before - recipient.survival.infection
	var poison_treated: float = poison_before - recipient.survival.food_poisoning
	var staunched: float = bleeding_before - recipient.survival.bleeding
	var splinted: float = fracture_before - recipient.survival.fracture
	var fed: float = recipient.survival.hunger - hunger_before
	var hydrated: float = recipient.survival.thirst - thirst_before
	var mastery_xp: float = PartyMedicMastery.training_xp(healed, staunched,
		cured, splinted, poison_treated)
	if mastery_xp > 0.0:
		_award(source, "medic", mastery_xp)
	events.append({"type": "party_aid", "peer": target_id, "by": peer_id,
		"item": selected_item_id, "heal": healed, "cure": cured,
		"bleeding_stopped": staunched, "fracture_treated": splinted,
		"food_poison_treated": poison_treated, "food": fed, "drink": hydrated})
	return {"ok": true, "peer": target_id, "item": selected_item_id,
		"heal": healed, "cure": cured, "bleeding_stopped": staunched,
		"fracture_treated": splinted, "food_poison_treated": poison_treated,
		"food": fed, "drink": hydrated}


## Transfer only known real provisions between living party allies by ONE
## actual campfire. This reuses the aid cooldown and inventory save flags.
func cmd_party_provision(peer_id: int, target_id: int, kind: String) -> Dictionary:
	var giver: Player = players.get(peer_id)
	var receiver: Player = players.get(target_id)
	if giver == null or not _alive(giver):
		return {"ok": false, "reason": "dead"}
	if peer_id == target_id:
		return {"ok": false, "reason": "self"}
	if receiver == null:
		return {"ok": false, "reason": "invalid_target"}
	if not _alive(receiver):
		return {"ok": false, "reason": "dead"}
	var group: int = parties.group_of(peer_id)
	if group <= 0 or parties.group_of(target_id) != group:
		return {"ok": false, "reason": "not_in_party"}
	if CampProvisions.package_items(kind).is_empty():
		return {"ok": false, "reason": "invalid_package"}
	if giver.mounted or receiver.mounted:
		return {"ok": false, "reason": "mounted"}
	if not giver.recall.is_empty() or not receiver.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if giver.combat_tag_until > time or receiver.combat_tag_until > time:
		return {"ok": false, "reason": "in_combat"}
	if not PartyAid.can_reach(giver.position, receiver.position):
		return {"ok": false, "reason": "too_far"}
	if not CampProvisions.shared_fire(campfires, giver.position, receiver.position, time):
		return {"ok": false, "reason": "no_fire"}
	if giver.party_aid_timer > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": giver.party_aid_timer}
	var error: String = CampProvisions.transfer(giver.inventory, receiver.inventory, kind)
	if error != "":
		return {"ok": false, "reason": error}
	giver.party_aid_timer = PartyAid.COOLDOWN
	giver.dirty_inventory = true
	giver.dirty_character = true
	receiver.dirty_inventory = true
	receiver.dirty_character = true
	var items: Dictionary = CampProvisions.package_items(kind)
	events.append({"type": "party_provision", "peer": target_id,
		"by": peer_id, "kind": kind, "items": items})
	return {"ok": true, "peer": target_id, "kind": kind,
		"items": items, "cooldown": giver.party_aid_timer}


## One authenticated medic spends one crafted pack for up to three injured
## current teammates. Target selection is never client-authored.
func cmd_party_triage(peer_id: int) -> Dictionary:
	var medic: Player = players.get(peer_id)
	if medic == null or not _alive(medic):
		return {"ok": false, "reason": "dead"}
	var group: Array = parties.members_of(peer_id)
	if group.size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	if medic.party_aid_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if medic.inventory.count(PartyTriage.ITEM_ID) < 1:
		return {"ok": false, "reason": "not_carried"}
	var candidates: Array = []
	for member_id in group:
		var member_peer: int = int(member_id)
		if member_peer == peer_id:
			continue # The pack treats allies, not its bearer.
		var ally: Player = players.get(member_peer)
		if ally == null or not _alive(ally):
			continue
		if not PartyTriage.can_reach(medic.position, ally.position):
			continue
		var score: float = PartyTriage.urgency(ally.survival.health,
			ally.survival.max_health, ally.survival.bleeding)
		if score <= 0.0:
			continue
		candidates.append({"peer": member_peer, "score": score, "player": ally})
	if candidates.is_empty():
		return {"ok": false, "reason": "no_wounded_allies"}
	# Prioritize urgent treatment and resolve equal wounds by peer ID.
	candidates.sort_custom(func(a, b):
		return float(a["score"]) > float(b["score"]) if float(a["score"]) != float(b["score"]) else int(a["peer"]) < int(b["peer"]))
	# Spend only after all checks and the complete eligible roster are resolved.
	if not medic.inventory.remove(PartyTriage.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var treated: int = mini(candidates.size(), PartyTriage.MAX_RECIPIENTS)
	var healed: float = 0.0
	var heal_each: float = PartyMedicMastery.heal_amount(
		PartyTriage.HEAL, medic.skills.bonus("heal_power"))
	var bleeding_stopped: float = 0.0
	var healing_events: Array = []
	for i in range(treated):
		var recipient: Player = candidates[i]["player"]
		var old_health: float = recipient.survival.health
		var old_bleeding: float = recipient.survival.bleeding
		recipient.survival.heal(heal_each)
		recipient.survival.bleeding = maxf(0.0,
			recipient.survival.bleeding - PartyTriage.BLEEDING_TREATMENT)
		var hp_gain: float = recipient.survival.health - old_health
		var wound_care: float = old_bleeding - recipient.survival.bleeding
		healed += hp_gain
		healing_events.append({"recipient": recipient, "healed": hp_gain})
		bleeding_stopped += wound_care
		recipient.dirty_character = true
		events.append({"type": "party_triage", "peer": recipient.id, "by": peer_id,
			"heal": hp_gain, "bleeding_stopped": wound_care})
	_record_party_healing_threat(medic, healing_events)
	var mastery_xp: float = PartyMedicMastery.training_xp(healed, bleeding_stopped,
		0.0, 0.0, 0.0)
	if mastery_xp > 0.0:
		_award(medic, "medic", mastery_xp)
	medic.party_aid_timer = PartyTriage.COOLDOWN
	medic.action = {}
	medic.dirty_inventory = true
	medic.dirty_character = true
	return {"ok": true, "treated": treated, "heal": healed,
		"bleeding_stopped": bleeding_stopped, "cooldown": PartyTriage.COOLDOWN}


## Expedition support: one real cooked fish per eligible party member.
## The client only picks a recipe, not recipient count, fire or bonus strength.
func cmd_party_feast(peer_id: int, item_id: String) -> Dictionary:
	var source: Player = players.get(peer_id)
	if source == null or not _alive(source):
		return {"ok": false, "reason": "dead"}
	if source.feast_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var group: Array = parties.members_of(peer_id)
	if group.size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	var tier: int = PartyFeast.food_tier(item_id)
	if tier <= 0:
		return {"ok": false, "reason": "not_prepared_food"}
	var fire: Dictionary = PartyFeast.camp_for(campfires, source.position, time)
	if fire.is_empty():
		return {"ok": false, "reason": "no_fire"}
	var recipients: Array = []
	for member_id in group:
		var member: Player = players.get(int(member_id))
		if member == null or not _alive(member):
			continue
		if not PartyFeast.near_fire(fire, member.position, time):
			continue
		# A low-tier feast must never overwrite a more powerful meal.
		if member.meal_seconds > 0.0 and member.meal_tier > tier:
			continue
		recipients.append(member)
	if recipients.size() < 2:
		return {"ok": false, "reason": "no_companions"}
	var portions: int = recipients.size()
	if source.inventory.count(item_id) < portions:
		return {"ok": false, "reason": "need_food", "portions": portions}
	# This removal is atomic: no teammate is changed on any failed attempt.
	if not source.inventory.remove(item_id, portions):
		return {"ok": false, "reason": "need_food", "portions": portions}
	var seconds: float = HeartyMeal.duration(tier)
	for member in recipients:
		member.survival.eat(float(Defs.item(item_id).get("food", 0.0)) *
			(1.0 + member.skills.bonus("food_power")))
		member.meal_tier = tier
		member.meal_seconds = seconds
		member.dirty_character = true
		events.append({"type": "party_feast", "peer": member.id, "by": peer_id,
			"tier": tier, "seconds": seconds})
	source.feast_timer = PartyFeast.COOLDOWN
	source.action = {}
	source.dirty_inventory = true
	source.dirty_character = true
	return {"ok": true, "served": portions, "tier": tier, "seconds": seconds}


## A real item-paid rally standard. Clients never set location, recipients,
## recovery strength, or its deadline; all rules use the live server party.
func cmd_party_standard(peer_id: int) -> Dictionary:
	var leader: Player = players.get(peer_id)
	if leader == null or not _alive(leader):
		return {"ok": false, "reason": "dead"}
	if not leader.position.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	if _is_safe(leader.position):
		return {"ok": false, "reason": "safe_hub"}
	if world.is_water(leader.position.x, leader.position.z):
		return {"ok": false, "reason": "in_water"}
	var reason: String = parties.standard_reason(peer_id, leader.position, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	# Material-paid support only exists if at least one real living ally is nearby.
	var companions: int = 0
	for member_id in parties.members_of(peer_id):
		if int(member_id) == peer_id:
			continue
		var member: Player = players.get(int(member_id))
		if member != null and _alive(member) and RallyStandard.within_range(
				leader.position, member.position):
			companions += 1
	if companions == 0:
		return {"ok": false, "reason": "no_companions"}
	if leader.inventory.count(RallyStandard.ITEM_ID) < 1:
		return {"ok": false, "reason": "not_carried"}
	if not leader.inventory.remove(RallyStandard.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var result: Dictionary = parties.raise_standard(peer_id, leader.position, time)
	# Invariant: the pure server-side preflight passed in this same method.
	if not bool(result.get("ok", false)):
		leader.inventory.add(RallyStandard.ITEM_ID, 1)
		return result
	leader.dirty_inventory = true
	leader.dirty_character = true
	events.append({"type": "party_standard", "peer": peer_id,
		"seconds": RallyStandard.DURATION, "group": parties.group_of(peer_id)})
	return result


## Secure, ephemeral tactical marker; movement and rewards are unaffected.
func cmd_party_ping(peer_id: int, x: float, z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	return parties.mark_ping(peer_id, Vector2(x, z), time)


## No position, bag ID or payout is client-selected. Even a dead member
## may ask their existing party to help recover lost equipment.
func cmd_party_corpse_rescue(peer_id: int) -> Dictionary:
	return PartyCorpseRescue.request(players.get(peer_id), parties, bags, time)


func cmd_party_rally(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	# Position comes from the authoritative player model, not any RPC argument.
	return parties.mark_rally(peer_id, player.position, time)


## Leader marks the closest currently living infected in real server space.
## No client-specified target, range, damage, position or enemy identity.
func cmd_party_focus(peer_id: int) -> Dictionary:
	var leader: Player = players.get(peer_id)
	if leader == null or not _alive(leader):
		return {"ok": false, "reason": "dead"}
	var reason: String = parties.focus_reason(peer_id, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	var best_id: int = -1
	var best_distance: float = INF
	for enemy in zombies.values():
		if not enemy.is_alive() or not PartyFocus.in_range(leader.position, enemy.position):
			continue
		var distance: float = Vector2(leader.position.x - enemy.position.x,
			leader.position.z - enemy.position.z).length_squared()
		if distance < best_distance - 0.0001 or (absf(distance - best_distance) <= 0.0001 and (best_id < 0 or enemy.id < best_id)):
			best_id = enemy.id
			best_distance = distance
	if best_id < 0:
		return {"ok": false, "reason": "no_infected_nearby"}
	return parties.start_focus(peer_id, best_id, time)


## Only the authenticated party leader configures FUTURE raid loot bags.
func cmd_party_loot_mode(peer_id: int, mode: String) -> Dictionary:
	var leader: Player = players.get(peer_id)
	if leader == null or not _alive(leader):
		return {"ok": false, "reason": "dead"}
	return parties.set_loot_mode(peer_id, mode)


## Every ballot is validated against a frozen server entitlement list.
## Voters must be nearby living survivors; no client-provided identity,
## loot contents, roll value, winner or deadline is accepted.
func cmd_raid_vote(peer_id: int, bag_id: int, choice: String) -> Dictionary:
	var voter: Player = players.get(peer_id)
	if voter == null or not _alive(voter):
		return {"ok": false, "reason": "dead"}
	var bag: Dictionary = bags.get(bag_id, {})
	if bag.is_empty() or not bag.has("raid_need_greed"):
		return {"ok": false, "reason": "no_vote"}
	var point := Vector2(float(bag["x"]), float(bag["z"]))
	var voter_at := Vector2(voter.position.x, voter.position.z)
	if not voter.position.is_finite() or voter_at.distance_to(point) > Party.ASSIST_RANGE:
		return {"ok": false, "reason": "too_far"}
	if not RaidLoot.can_open(bag, voter, time):
		return {"ok": false, "reason": "raid_reserved"}
	var result: Dictionary = RaidNeedGreed.vote(bag, voter, choice, time)
	if bool(result.get("ok", false)):
		result["bag"] = bag_id
	return result


func _party_state_for(peer_id: int) -> Dictionary:
	var state: Dictionary = parties.state_for(peer_id, time)
	var roster: Array = []
	for id in state["members"]:
		var member: Player = players.get(id)
		if member != null:
			roster.append({"id": int(id), "name": member.name,
				"alive": _alive(member), "health": member.survival.health})
	state["roster"] = roster
	state["corpse_rescue"] = PartyCorpseRescue.shared(peer_id, players, parties, bags, time)
	state["escort_caravan"] = CaravanEscort.shared_route(peer_id, players, parties)
	var shared: Dictionary = state["escort_caravan"]
	state["escort_progress"] = {}
	if not shared.is_empty() and int(shared["owner"]) != peer_id:
		var courier: Player = players.get(int(shared["owner"]))
		if courier != null:
			state["escort_progress"] = CaravanEscortRewards.status(
				caravan_escort_progress, courier.id, peer_id,
				parties.group_of(peer_id), courier.caravan_view)
	var invite_from: int = int(state["invite_from"])
	var sender: Player = players.get(invite_from)
	state["invite_name"] = sender.name if sender != null else ""
	return state


# --- Outpost fortification: server-authoritative supplies for siege defense. ----------
# Every client command includes a monotonic request ID so an ambiguous response
# cannot cause the same upgrade to spend the player's resources twice.
## Bounded resource convoys. Monotonic request IDs cache the result of every
## command, so duplicated network packets cannot spend or extend twice.
func cmd_outpost_provision(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > PROVISION_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = outpost_provision_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var player: Player = players[peer_id]
	var result: Dictionary
	if not _alive(player):
		result = {"ok": false, "reason": "dead"}
	else:
		result = territory.deliver_provisions(site_id, player, players, parties, time)
	if bool(result.get("ok", false)):
		player.dirty_inventory = true
		player.dirty_character = true
		var flag: Dictionary = territory.site_by_id(site_id)
		events.append({"type": "outpost_provisioned", "id": site_id,
			"owner": flag["owner"], "x": flag["x"], "z": flag["z"],
			"extended": OutpostProvisions.EXTRA_SECONDS,
			"total": flag["provisioned_seconds"]})
	result["request_id"] = request_id
	outpost_provision_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": result.duplicate(true),
	}
	return result


func cmd_outpost_fortify(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > FORTIFY_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = outpost_fortify_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var outcome: Dictionary = _execute_outpost_fortify(peer_id, site_id)
	outcome["request_id"] = request_id
	outpost_fortify_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": outcome.duplicate(true),
	}
	return outcome


func _execute_outpost_fortify(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var site: Dictionary = territory.site_by_id(site_id)
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	var group_id: int = parties.group_of(peer_id)
	var rival_present: bool = territory.contested_by_rivals(site, group_id, players, parties)
	var result: Dictionary = OutpostFortification.fortify(
		site, player.inventory, group_id, player.position, time, rival_present)
	if result.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({
			"type": "outpost_fortified", "id": site_id, "level": result["level"],
			"x": site["x"], "z": site["z"], "owner": group_id,
		})
	return result


# --- Siege breaches. A hostile party can spend crafted T2 materials to
# dismantle defensive tiers, countering the permanent defender time bonus.
# Request IDs are monotonic per peer and never accepted twice with new terms.
func cmd_outpost_breach(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > BREACH_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = outpost_breach_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var result: Dictionary = _execute_outpost_breach(peer_id, site_id)
	result["request_id"] = request_id
	outpost_breach_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": result.duplicate(true),
	}
	return result


func _execute_outpost_breach(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var site: Dictionary = territory.site_by_id(site_id)
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if GuildTerritory.same_owner_guild(site, player, players, parties):
		return {"ok": false, "reason": "guild_ally"}
	var attacker_group: int = parties.group_of(peer_id)
	var occupied: Dictionary = territory._occupied_groups(site, players, parties)
	var ally_count: int = int(occupied.get(attacker_group, 0)) if attacker_group > 0 else 0
	var result: Dictionary = OutpostBreach.breach(
		site, player.inventory, attacker_group, player.position, ally_count, time)
	if result.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({
			"type": "outpost_breached", "id": site_id, "level": result["level"],
			"x": site["x"], "z": site["z"], "by_group": attacker_group,
		})
	return result


# --- Siege declarations: leadership, preparation and scored territory captures. ---
# Parties remain session-based until authenticated Nakama clan membership exists.
func cmd_siege_declare(peer_id: int, site_id: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > SIEGE_DECLARE_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = siege_declare_requests.get(peer_id, {})
	if not last.is_empty():
		if request_id < int(last["id"]):
			return {"ok": false, "reason": "stale_request"}
		if request_id == int(last["id"]):
			if site_id != int(last["site"]):
				return {"ok": false, "reason": "request_conflict"}
			return (last["result"] as Dictionary).duplicate(true)
	var outcome: Dictionary = _execute_siege_declare(peer_id, site_id)
	outcome["request_id"] = request_id
	siege_declare_requests[peer_id] = {
		"id": request_id, "site": site_id, "result": outcome.duplicate(true),
	}
	return outcome


func _execute_siege_declare(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var site: Dictionary = territory.site_by_id(site_id)
	if site.is_empty():
		return {"ok": false, "reason": "unknown_outpost"}
	if GuildTerritory.same_owner_guild(site, player, players, parties):
		return {"ok": false, "reason": "guild_ally"}
	var group_id: int = parties.group_of(peer_id)
	var is_leader: bool = group_id > 0 and parties.groups.has(group_id) \
		and int(parties.groups[group_id]["leader"]) == peer_id
	var allies_near := 0
	if group_id > 0:
		var point := Vector2(float(site["x"]), float(site["z"]))
		for member_id in parties.members_of(peer_id):
			var ally: Player = players.get(member_id)
			if ally != null and _alive(ally) and ally.position.is_finite() and \
					Vector2(ally.position.x, ally.position.z).distance_squared_to(point) <= \
					SiegeContracts.DECLARE_RADIUS * SiegeContracts.DECLARE_RADIUS:
				allies_near += 1
	var result: Dictionary = siege_contracts.declare(
		site, player.inventory, player.position, group_id, is_leader, allies_near, time)
	if result.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({
			"type": "siege_contract_declared", "site": site_id,
			"x": site["x"], "z": site["z"],
			"attacker": group_id, "defender": site["owner"],
		})
	return result


# --- Direct player trade -------------------------------------------------------------------------------
# All operations are synchronous on the authoritative tick; no client-provided
# price, inventory balance or confirmation flag is trusted.

func _trade_available(first_id: int, second_id: int) -> bool:
	var first: Player = players.get(first_id)
	var second: Player = players.get(second_id)
	if first == null or second == null or not _alive(first) or not _alive(second):
		return false
	var first_at := Vector2(first.position.x, first.position.z)
	var second_at := Vector2(second.position.x, second.position.z)
	return first_at.is_finite() and second_at.is_finite() \
		and _is_safe(first.position) and _is_safe(second.position) \
		and first_at.distance_to(second_at) <= TRADE_RANGE


func _get_trade(peer_id: int, trade_id: int) -> Dictionary:
	var trade: Dictionary = trades.get(trade_id, {})
	if trade.is_empty() or (int(trade["a"]) != peer_id and int(trade["b"]) != peer_id):
		return {}
	return trade


func _announce_trade(trade: Dictionary, phase: String, reason: String = "") -> void:
	events.append({
		"type": "trade", "phase": phase, "reason": reason, "id": trade["id"],
		"a": trade["a"], "b": trade["b"], "revision": trade["revision"],
		"offer_a": trade["offers"][trade["a"]].duplicate(),
		"offer_b": trade["offers"][trade["b"]].duplicate(),
		"accepted_a": trade["accepted"][trade["a"]],
		"accepted_b": trade["accepted"][trade["b"]],
	})


func _close_trade(trade: Dictionary, phase: String, reason: String = "") -> void:
	trades.erase(trade["id"])
	trade_by_player.erase(trade["a"])
	trade_by_player.erase(trade["b"])
	_announce_trade(trade, phase, reason)


func _cancel_player_trade(peer_id: int, reason: String) -> void:
	if not trade_by_player.has(peer_id):
		return
	var trade_id: int = int(trade_by_player[peer_id])
	var trade: Dictionary = trades.get(trade_id, {})
	if not trade.is_empty():
		_close_trade(trade, "cancelled", reason)
	else:
		trade_by_player.erase(peer_id)


## Queues the durable settlement of a two-player deal that has just been applied in memory.
func _queue_pair_commit(peer_a: int, peer_b: int, kind: String) -> void:
	if not pair_persistence:
		return
	var tx := "%s-%d-%s" % [kind, new_id(), Crypto.new().generate_random_bytes(6).hex_encode()]
	pair_locks[peer_a] = tx
	pair_locks[peer_b] = tx
	pair_commits.append({"a": peer_a, "b": peer_b, "tx": tx})


## The backend confirmed (or finally gave up on) a settlement: the two players may trade again.
func release_pair_commit(tx: String) -> void:
	for peer in pair_locks.keys():
		if pair_locks[peer] == tx:
			pair_locks.erase(peer)


func _pair_locked(peer_ids: Array) -> bool:
	for peer in peer_ids:
		if pair_locks.has(int(peer)):
			return true
	return false


func cmd_trade_invite(peer_id: int, target_id: int) -> Dictionary:
	if peer_id == target_id or not players.has(peer_id) or not players.has(target_id):
		return {"ok": false, "reason": "invalid_target"}
	if _pair_locked([peer_id, target_id]):
		return {"ok": false, "reason": "saving_previous_deal"}
	if trade_by_player.has(peer_id) or trade_by_player.has(target_id):
		return {"ok": false, "reason": "busy"}
	if not _trade_available(peer_id, target_id):
		return {"ok": false, "reason": "not_in_safe_range"}
	var trade_id := new_id()
	var trade := {
		"id": trade_id, "a": peer_id, "b": target_id,
		"offers": {}, "accepted": {},
		"revision": 0, "expires": time + TRADE_TIMEOUT,
	}
	# Explicit integer keys: identifiers in dictionary literals can be string keys.
	trade["offers"][peer_id] = {}
	trade["offers"][target_id] = {}
	trade["accepted"][peer_id] = false
	trade["accepted"][target_id] = false
	trades[trade_id] = trade
	trade_by_player[peer_id] = trade_id
	trade_by_player[target_id] = trade_id
	_announce_trade(trade, "invited")
	return {"ok": true, "trade_id": trade_id, "revision": 0}


## A zero count removes an offer line. Every change clears BOTH confirmations.
func cmd_trade_offer(peer_id: int, trade_id: int, item_id: String, count: int) -> Dictionary:
	var trade := _get_trade(peer_id, trade_id)
	if trade.is_empty():
		return {"ok": false, "reason": "unknown_trade"}
	if not _trade_available(int(trade["a"]), int(trade["b"])) or time >= float(trade["expires"]):
		_close_trade(trade, "cancelled", "out_of_range")
		return {"ok": false, "reason": "out_of_range"}
	if not Defs.is_item(item_id) or count < 0 or count > Defs.stack_size(item_id):
		return {"ok": false, "reason": "invalid_stack"}
	var offer: Dictionary = trade["offers"][peer_id]
	if count > 0 and players[peer_id].inventory.count(item_id) < count:
		return {"ok": false, "reason": "missing_items"}
	if count > 0 and not offer.has(item_id) and offer.size() >= PlayerTrade.MAX_OFFER_LINES:
		return {"ok": false, "reason": "too_many_items"}
	if count == 0:
		offer.erase(item_id)
	else:
		offer[item_id] = count
	trade["accepted"][trade["a"]] = false
	trade["accepted"][trade["b"]] = false
	trade["revision"] = int(trade["revision"]) + 1
	trade["expires"] = time + TRADE_TIMEOUT
	_announce_trade(trade, "offered")
	return {"ok": true, "trade_id": trade_id, "revision": trade["revision"]}


## The revision is the number from the latest trade event. Stale confirmation
## packets cannot accept a new or changed proposal.
func cmd_trade_accept(peer_id: int, trade_id: int, revision: int) -> Dictionary:
	var trade := _get_trade(peer_id, trade_id)
	if trade.is_empty():
		return {"ok": false, "reason": "unknown_trade"}
	if not _trade_available(int(trade["a"]), int(trade["b"])) or time >= float(trade["expires"]):
		_close_trade(trade, "cancelled", "out_of_range")
		return {"ok": false, "reason": "out_of_range"}
	if revision != int(trade["revision"]):
		return {"ok": false, "reason": "stale_revision", "revision": trade["revision"]}
	if trade["accepted"][peer_id]:
		return {"ok": false, "reason": "already_accepted"}
	trade["accepted"][peer_id] = true
	if not trade["accepted"][trade["a"]] or not trade["accepted"][trade["b"]]:
		_announce_trade(trade, "accepted")
		return {"ok": true, "completed": false, "revision": revision}
	if _pair_locked([trade["a"], trade["b"]]):
		trade["accepted"][peer_id] = false
		return {"ok": false, "reason": "saving_previous_deal"}
	var first: Player = players[int(trade["a"])]
	var second: Player = players[int(trade["b"])]
	var result: Dictionary = PlayerTrade.exchange(
		first.inventory, second.inventory,
		trade["offers"][trade["a"]], trade["offers"][trade["b"]]
	)
	if not result.get("ok", false):
		trade["accepted"][trade["a"]] = false
		trade["accepted"][trade["b"]] = false
		trade["revision"] = int(trade["revision"]) + 1
		_announce_trade(trade, "rejected", str(result["reason"]))
		return {"ok": false, "reason": result["reason"], "revision": trade["revision"]}
	first.dirty_inventory = true
	second.dirty_inventory = true
	first.dirty_character = true
	second.dirty_character = true
	_close_trade(trade, "completed")
	_queue_pair_commit(int(trade["a"]), int(trade["b"]), "trade")
	return {"ok": true, "completed": true, "trade_id": trade_id}


func cmd_trade_cancel(peer_id: int, trade_id: int) -> Dictionary:
	var trade := _get_trade(peer_id, trade_id)
	if trade.is_empty():
		return {"ok": false, "reason": "unknown_trade"}
	_close_trade(trade, "cancelled", "by_player")
	return {"ok": true}


func _tick_trades() -> void:
	for trade_id in trades.keys():
		var trade: Dictionary = trades.get(trade_id, {})
		if trade.is_empty():
			continue
		if time >= float(trade["expires"]):
			_close_trade(trade, "cancelled", "expired")
		elif not _trade_available(int(trade["a"]), int(trade["b"])):
			_close_trade(trade, "cancelled", "out_of_range")


# --- Player market board: online-only listings with execution-time inventory checks. ---
# Posting a listing does NOT debit goods. A new durable backend journal is
# required before adding offline listings or player escrow.

## The hub's workbench or the one of a settlement (village, fort) out in the world. Crafting, the vendor and contracts work at
## either; the bank, the market and camp rest stay in the hub's safe zone.
## Albion-style enchanting at a workbench: runes / souls / relics plus a silver fee raise one
## carried piece of gear to its next enchantment level (.1, .2, .3).
func cmd_enchant(peer_id: int, item_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not player.position.is_finite() or not _at_workbench(Vector2(player.position.x, player.position.z)):
		return {"ok": false, "reason": "no_station"}
	var result: Dictionary = Enchanting.enchant(player.inventory, str(item_id))
	if bool(result.get("ok", false)):
		player.dirty_character = true
	return result


## Albion-style gear repair: at a workbench, pay silver to restore every damaged
## carried item to 100% durability. Costs scale with item value and wear.
func cmd_repair_gear(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not player.position.is_finite() or not _at_workbench(Vector2(player.position.x, player.position.z)):
		return {"ok": false, "reason": "no_station"}
	var cost: int = player.inventory.repair_cost()
	if cost <= 0:
		return {"ok": false, "reason": "nothing_to_repair"}
	if player.inventory.count("silver") < cost:
		return {"ok": false, "reason": "need_silver", "cost": cost}
	player.inventory.remove("silver", cost)
	var repaired: Array = player.inventory.repair_all()
	player.dirty_character = true
	return {"ok": true, "cost": cost, "items": repaired}


func _at_workbench(spot: Vector2) -> bool:
	if not spot.is_finite():
		return false
	return spot.distance_to(WORKBENCH_POSITION) <= WORKBENCH_RANGE or world.settlement_station_near(spot.x, spot.y, WORKBENCH_RANGE)


func _market_at_hub(player: Player) -> bool:
	if player == null or not _alive(player):
		return false
	var spot := Vector2(player.position.x, player.position.z)
	return spot.is_finite() and _is_safe(player.position) \
		and spot.distance_to(WORKBENCH_POSITION) <= WORKBENCH_RANGE


## Market accounts: a signed-in survivor's account id survives logouts and restarts; a guest's
## session id does not (guest listings and proceeds are not saved with the world).
func _market_account(player: Player) -> String:
	if player == null:
		return ""
	return player.user_id if not player.user_id.is_empty() else "peer:%d" % player.id


## Escrow market: listings hold their goods, so they stay up while the seller is away.
func _cancel_market_seller(_peer_id: int) -> void:
	pass


## Expired listings send their unsold goods back to the seller's market returns.
func _tick_market() -> void:
	for bid_id in market_bids.keys():
		if time >= float(market_bids[bid_id]["expires"]) or int(market_bids[bid_id]["remaining"]) < 1:
			_refund_bid(market_bids[bid_id])
			market_bids.erase(bid_id)
	for listing_id in market_orders.keys():
		var listing: Dictionary = market_orders[listing_id]
		if time >= float(listing["expires"]) or int(listing["remaining"]) < 1:
			_market_return(str(listing["account"]), str(listing["item"]), int(listing["remaining"]))
			market_orders.erase(listing_id)


func _market_return(account: String, item_id: String, count: int) -> void:
	if count < 1 or account.is_empty():
		return
	var pending: Dictionary = market_returns.get(account, {})
	pending[item_id] = int(pending.get(item_id, 0)) + count
	market_returns[account] = pending


## Moves proceeds and returned goods into the backpack, as far as there is room. Hub only.
func _market_collect(player: Player) -> Dictionary:
	var account: String = _market_account(player)
	var silver: int = 0
	var items: int = 0
	var owed: int = int(market_payouts.get(account, 0))
	if owed > 0:
		var left: int = player.inventory.add("silver", owed)
		silver = owed - left
		if left > 0:
			market_payouts[account] = left
		else:
			market_payouts.erase(account)
	var pending: Dictionary = market_returns.get(account, {})
	for item_id in pending.keys():
		var count: int = int(pending[item_id])
		var left: int = player.inventory.add(str(item_id), count)
		items += count - left
		if left > 0:
			pending[item_id] = left
		else:
			pending.erase(item_id)
	if pending.is_empty():
		market_returns.erase(account)
	if silver > 0 or items > 0:
		player.dirty_inventory = true
		player.dirty_character = true
	return {"silver": silver, "items": items}


func cmd_market_list(peer_id: int) -> Dictionary:
	var viewer: Player = players.get(peer_id)
	if viewer == null:
		return {"ok": false, "reason": "unknown_player"}
	_tick_market()
	var collected: Dictionary = {}
	if _market_at_hub(viewer):
		collected = _market_collect(viewer)
	var account: String = _market_account(viewer)
	var public_orders: Array = []
	for listing_id in market_orders.keys():
		var order: Dictionary = market_orders[listing_id]
		public_orders.append({
			"id": listing_id, "item": order["item"], "quantity": order["remaining"],
			"price": order["price"], "seller_name": order.get("seller_name", "?"),
			"own": str(order["account"]) == account,
			"expires_in": maxf(0.0, float(order["expires"]) - time),
		})
	public_orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return MarketBoard.cheaper_first(a, b))
	var public_bids: Array = []
	for bid_id in market_bids.keys():
		var bid: Dictionary = market_bids[bid_id]
		public_bids.append({"id": bid_id, "item": bid["item"], "quantity": bid["remaining"], "price": bid["price"],
			"buyer_name": bid.get("buyer_name", "?"), "own": str(bid["account"]) == account})
	public_bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return MarketBids.best_first(a, b))
	return {"ok": true, "action": "list", "orders": public_orders, "bids": public_bids,
		"collected_silver": int(collected.get("silver", 0)), "collected_items": int(collected.get("items", 0)),
		"pending_silver": int(market_payouts.get(account, 0))}


## Albion-style alliances (hub, guild leaders): "invite" a leader by peer id, "accept", "leave", "status".
func cmd_alliance(peer_id: int, action: String, target_peer: int = -1) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.guild_id.is_empty():
		return {"ok": false, "reason": "no_guild"}
	var mine: String = player.guild_id
	match action:
		"status":
			pass
		"invite":
			if not GuildAlliances.is_leader(player.guild_rank):
				return {"ok": false, "reason": "leaders_only"}
			if not _market_at_hub(player):
				return {"ok": false, "reason": "no_station"}
			var other: Player = players.get(target_peer)
			if other == null or other.guild_id.is_empty() or other.guild_id == mine:
				return {"ok": false, "reason": "invalid_target"}
			if not GuildAlliances.is_leader(other.guild_rank):
				return {"ok": false, "reason": "target_not_leader"}
			if guild_to_alliance.has(other.guild_id):
				return {"ok": false, "reason": "target_allied"}
			var alliance_id: int = int(guild_to_alliance.get(mine, -1))
			if alliance_id >= 0 and (guild_alliances[alliance_id]["guilds"] as Dictionary).size() >= GuildAlliances.MAX_GUILDS:
				return {"ok": false, "reason": "alliance_full"}
			alliance_invites[other.guild_id] = {"from": mine, "from_name": player.guild_name, "expires": time + GuildAlliances.INVITE_SECONDS}
			events.append({"type": "alliance_invite", "peer": other.id, "from": player.guild_name})
		"accept":
			if not GuildAlliances.is_leader(player.guild_rank):
				return {"ok": false, "reason": "leaders_only"}
			var invite: Dictionary = alliance_invites.get(mine, {})
			if invite.is_empty() or time > float(invite["expires"]):
				alliance_invites.erase(mine)
				return {"ok": false, "reason": "no_invite"}
			if guild_to_alliance.has(mine):
				return {"ok": false, "reason": "already_allied"}
			var host: String = str(invite["from"])
			var alliance_id: int = int(guild_to_alliance.get(host, -1))
			if alliance_id < 0:
				alliance_id = new_id()
				guild_alliances[alliance_id] = {"guilds": {host: str(invite["from_name"])}}
			if (guild_alliances[alliance_id]["guilds"] as Dictionary).size() >= GuildAlliances.MAX_GUILDS:
				return {"ok": false, "reason": "alliance_full"}
			guild_alliances[alliance_id]["guilds"][mine] = player.guild_name
			alliance_invites.erase(mine)
			_rebuild_alliance_index()
		"leave":
			if not GuildAlliances.is_leader(player.guild_rank):
				return {"ok": false, "reason": "leaders_only"}
			var alliance_id: int = int(guild_to_alliance.get(mine, -1))
			if alliance_id < 0:
				return {"ok": false, "reason": "not_allied"}
			(guild_alliances[alliance_id]["guilds"] as Dictionary).erase(mine)
			if (guild_alliances[alliance_id]["guilds"] as Dictionary).size() < 2:
				guild_alliances.erase(alliance_id) # A lone guild is not an alliance.
			_rebuild_alliance_index()
		_:
			return {"ok": false, "reason": "unknown_action"}
	var current: int = int(guild_to_alliance.get(mine, -1))
	var members: Array = []
	if current >= 0:
		members = (guild_alliances[current]["guilds"] as Dictionary).values()
	return {"ok": true, "action": action, "allied_guilds": members,
		"invite_from": str(alliance_invites.get(mine, {}).get("from_name", ""))}


func _rebuild_alliance_index() -> void:
	guild_to_alliance.clear()
	for alliance_id in guild_alliances:
		for guild in guild_alliances[alliance_id]["guilds"]:
			guild_to_alliance[str(guild)] = int(alliance_id)


## Same verified guild or an allied guild: never friendly fire.
func _guild_friendly(a: Player, b: Player) -> bool:
	if a == null or b == null or a.user_id.is_empty() or b.user_id.is_empty():
		return false
	return GuildAlliances.friendly(a.guild_id, b.guild_id, guild_to_alliance)


## Albion-style guild bank at the hub: "list", "deposit" (any member), "withdraw" (officers).
func cmd_guild_bank(peer_id: int, action: String, item_id: String = "", quantity: int = 0) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.guild_id.is_empty():
		return {"ok": false, "reason": "no_guild"}
	if not _market_at_hub(player):
		return {"ok": false, "reason": "no_station"}
	var vault: Dictionary = guild_banks.get(player.guild_id, {})
	var ledger: Array = guild_ledgers.get(player.guild_id, [])
	match action:
		"list":
			pass
		"deposit":
			var reason: String = GuildBank.deposit_refusal(vault, item_id, quantity)
			if reason != "":
				return {"ok": false, "reason": reason}
			var spare: int = player.inventory.count(item_id) - (1 if player.inventory.is_equipped(item_id) else 0)
			if spare < quantity:
				return {"ok": false, "reason": "missing_items"}
			player.inventory.remove(item_id, quantity)
			vault[item_id] = int(vault.get(item_id, 0)) + quantity
			GuildBank.add_ledger(ledger, player.name, "deposit", item_id, quantity, time)
		"withdraw":
			if not GuildBank.can_withdraw(player.guild_rank):
				return {"ok": false, "reason": "officers_only"}
			if quantity < 1 or int(vault.get(item_id, 0)) < quantity:
				return {"ok": false, "reason": "not_in_vault"}
			var left: int = player.inventory.add(item_id, quantity)
			var taken: int = quantity - left
			if taken < 1:
				return {"ok": false, "reason": "no_space"}
			vault[item_id] = int(vault[item_id]) - taken
			if int(vault[item_id]) <= 0:
				vault.erase(item_id)
			GuildBank.add_ledger(ledger, player.name, "withdraw", item_id, taken, time)
		_:
			return {"ok": false, "reason": "unknown_action"}
	guild_banks[player.guild_id] = vault
	guild_ledgers[player.guild_id] = ledger
	if action != "list":
		player.dirty_inventory = true
		player.dirty_character = true
	return {"ok": true, "action": action, "guild": player.guild_name, "vault": vault.duplicate(),
		"ledger": ledger.duplicate(true), "can_withdraw": GuildBank.can_withdraw(player.guild_rank)}


## Homestead farming: plant a carried seed 1.5 m in front of you (green zone only).
func cmd_plant(peer_id: int, seed_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var crop: String = Farming.crop_for_seed(str(seed_id))
	if crop == "":
		return {"ok": false, "reason": "not_a_seed"}
	if player.inventory.count(seed_id) < 1:
		return {"ok": false, "reason": "missing_seed"}
	if not player.position.is_finite() or not is_finite(player.yaw):
		return {"ok": false, "reason": "invalid_position"}
	var spot := Vector2(player.position.x, player.position.z) + Vector2(sin(player.yaw), cos(player.yaw)) * 1.5
	if not spot.is_finite():
		return {"ok": false, "reason": "invalid_position"
	var account: String = _market_account(player)
	var own := 0
	for plot in farm_plots.values():
		if str(plot["account"]) == account:
			own += 1
	var refusal: String = Farming.placement_refusal(world.zone_at(spot.x, spot.y), world.is_water(spot.x, spot.y),
		spot, farm_plots, own)
	if refusal != "":
		return {"ok": false, "reason": refusal}
	player.inventory.remove(seed_id, 1)
	var plot_id: int = new_id()
	farm_plots[plot_id] = {"account": account, "owner_name": player.name, "crop": crop,
		"x": spot.x, "z": spot.y, "planted": time, "grow": float(Farming.CROPS[crop]["seconds"])}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": plot_id, "crop": crop, "seconds": float(Farming.CROPS[crop]["seconds"])}


## Harvest the nearest ripe plot of your own within reach.
func cmd_harvest(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not player.position.is_finite() or not is_finite(time):
		return {"ok": false, "reason": "invalid_position"}
	var account: String = _market_account(player)
	var here := Vector2(player.position.x, player.position.z)
	var best_id: int = -1
	var best_distance_squared: float = Farming.PLANT_REACH * Farming.PLANT_REACH
	var unripe := false
	for plot_id in farm_plots:
		var plot: Dictionary = farm_plots[plot_id]
		if str(plot["account"]) != account:
			continue
		var site := Vector2(float(plot.get("x", NAN)), float(plot.get("z", NAN)))
		if not site.is_finite():
			continue
		var distance_squared: float = here.distance_squared_to(site)
		if distance_squared > Farming.PLANT_REACH * Farming.PLANT_REACH:
			continue
		if not Farming.is_ripe(plot, time):
			unripe = true
			continue
		# Same-distance plots keep a stable ID priority, not Dictionary order.
		if best_id < 0 or distance_squared < best_distance_squared or (
				distance_squared == best_distance_squared and int(plot_id) < best_id):
			best_distance_squared = distance_squared
			best_id = int(plot_id)
	if best_id < 0:
		return {"ok": false, "reason": "not_ripe" if unripe else "no_plot"}
	var harvest: Dictionary = Farming.harvest_yield(str(farm_plots[best_id]["crop"]), rng)
	var overflow: Dictionary = _give_items(player, harvest)
	farm_plots.erase(best_id)
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "items": harvest, "dropped": overflow}


## Faction warfare commands: "enlist" (hub, with faction id), "flag", "unflag", "redeem".
func cmd_faction(peer_id: int, action: String, faction_id: String = "") -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	match action:
		"enlist":
			if not _market_at_hub(player):
				return {"ok": false, "reason": "no_station"}
			if not Factions.valid_faction(faction_id):
				return {"ok": false, "reason": "unknown_faction"}
			if player.faction_flagged:
				return {"ok": false, "reason": "flagged"}
			if player.faction != faction_id:
				player.faction = faction_id
				player.faction_points = 0 # Switching sides forfeits unspent standing.
		"flag":
			if player.faction == "":
				return {"ok": false, "reason": "not_enlisted"}
			player.faction_flagged = true
			player.faction_unflag_at = -1.0
		"unflag":
			if not player.faction_flagged:
				return {"ok": false, "reason": "not_flagged"}
			player.faction_unflag_at = time + Factions.UNFLAG_SECONDS
		"redeem":
			if not _market_at_hub(player):
				return {"ok": false, "reason": "no_station"}
			if player.faction_points < Factions.REDEEM_COST:
				return {"ok": false, "reason": "need_points", "points": player.faction_points}
			var overflow: Dictionary = _give_items(player, Factions.REDEEM_REWARD)
			if not overflow.is_empty():
				return {"ok": false, "reason": "no_space"}
			player.faction_points -= Factions.REDEEM_COST
		_:
			return {"ok": false, "reason": "unknown_action"}
	player.dirty_character = true
	return {"ok": true, "action": action, "faction": player.faction, "flagged": player.faction_flagged,
		"points": player.faction_points, "unflag_in": maxf(0.0, player.faction_unflag_at - time) if player.faction_unflag_at >= 0.0 else 0.0}


func _faction_enemies(a: Player, b: Player) -> bool:
	if a == null or b == null or a.id == b.id:
		return false
	return Factions.can_fight(a.faction, a.faction_flagged, b.faction, b.faction_flagged,
		world.zone_at(a.position.x, a.position.z), world.zone_at(b.position.x, b.position.z),
		_is_safe(a.position), _is_safe(b.position))


func _award_faction_points(player: Player, points: int, reason: String) -> void:
	if player == null or player.faction == "" or not player.faction_flagged or points <= 0:
		return
	player.faction_points = mini(Factions.MAX_POINTS, player.faction_points + points)
	player.dirty_character = true
	events.append({"type": "faction_points", "peer": player.id, "points": points, "total": player.faction_points, "reason": reason})


## Albion-style buy order: escrows quantity * price silver from the buyer (hub only).
func cmd_market_bid(peer_id: int, item_id: String, quantity: int, unit_price: int) -> Dictionary:
	var buyer: Player = players.get(peer_id)
	if not _market_at_hub(buyer):
		return {"ok": false, "reason": "no_station"}
	_tick_market()
	var reason: String = MarketBids.validate_bid(buyer.inventory.count("silver"), str(item_id), quantity, unit_price)
	if reason != "":
		return {"ok": false, "reason": reason}
	if market_bids.size() >= MarketBids.MAX_BIDS:
		return {"ok": false, "reason": "market_full"}
	var account: String = _market_account(buyer)
	var mine := 0
	for bid in market_bids.values():
		if str(bid["account"]) == account:
			mine += 1
	if mine >= MarketBids.MAX_PER_BUYER:
		return {"ok": false, "reason": "too_many_bids"}
	buyer.inventory.remove("silver", quantity * unit_price)
	var bid_id: int = new_id()
	market_bids[bid_id] = {"account": account, "buyer_name": buyer.name, "item": str(item_id),
		"remaining": quantity, "price": unit_price, "expires": time + MarketBids.BID_LIFETIME}
	buyer.dirty_inventory = true
	buyer.dirty_character = true
	return {"ok": true, "action": "bid_created", "id": bid_id, "escrowed": quantity * unit_price}


## Sell straight into a buy order: the seller is paid now (minus tax); the buyer's goods wait at the hub.
func cmd_market_fill(peer_id: int, bid_id: int, quantity: int) -> Dictionary:
	var seller: Player = players.get(peer_id)
	if not _market_at_hub(seller):
		return {"ok": false, "reason": "no_station"}
	_tick_market()
	var bid: Dictionary = market_bids.get(bid_id, {})
	if bid.is_empty():
		return {"ok": false, "reason": "unknown_bid"}
	if str(bid["account"]) == _market_account(seller):
		return {"ok": false, "reason": "self_trade"}
	if quantity < 1 or quantity > int(bid["remaining"]):
		return {"ok": false, "reason": "invalid_quantity"}
	var item_id: String = str(bid["item"])
	if MarketBids.sellable(seller.inventory, item_id) < quantity:
		return {"ok": false, "reason": "missing_items"}
	var total: int = int(bid["price"]) * quantity
	var tax: int = MarketBoard.sale_tax(total)
	seller.inventory.remove(item_id, quantity)
	seller.inventory.unequip_missing()
	var unpaid: int = seller.inventory.add("silver", total - tax)
	if unpaid > 0:
		var seller_account: String = _market_account(seller)
		market_payouts[seller_account] = int(market_payouts.get(seller_account, 0)) + unpaid
	_market_return(str(bid["account"]), item_id, quantity)
	bid["remaining"] = int(bid["remaining"]) - quantity
	if int(bid["remaining"]) <= 0:
		market_bids.erase(bid_id)
	seller.dirty_inventory = true
	seller.dirty_character = true
	return {"ok": true, "action": "filled", "id": bid_id, "item": item_id, "quantity": quantity, "total": total, "tax": tax}


func cmd_market_cancel_bid(peer_id: int, bid_id: int) -> Dictionary:
	var buyer: Player = players.get(peer_id)
	var bid: Dictionary = market_bids.get(bid_id, {})
	if buyer == null or bid.is_empty():
		return {"ok": false, "reason": "unknown_bid"}
	if str(bid["account"]) != _market_account(buyer):
		return {"ok": false, "reason": "not_owner"}
	_refund_bid(bid)
	market_bids.erase(bid_id)
	return {"ok": true, "action": "bid_cancelled", "id": bid_id}


## Unspent escrow goes to the buyer's market payouts (collected at the hub).
func _refund_bid(bid: Dictionary) -> void:
	var refund: int = int(bid["remaining"]) * int(bid["price"])
	if refund > 0:
		var account: String = str(bid["account"])
		market_payouts[account] = int(market_payouts.get(account, 0)) + refund


func cmd_market_create(peer_id: int, item_id: String, quantity: int, unit_price: int) -> Dictionary:
	if _pair_locked([peer_id]):
		return {"ok": false, "reason": "saving_previous_deal"}
	var seller: Player = players.get(peer_id)
	if not _market_at_hub(seller):
		return {"ok": false, "reason": "no_station"}
	_tick_market()
	var validation: String = MarketBoard.validate_listing(seller.inventory, item_id, quantity, unit_price)
	if validation != "":
		return {"ok": false, "reason": validation}
	if market_orders.size() >= MarketBoard.MAX_LISTINGS:
		return {"ok": false, "reason": "market_full"}
	var account: String = _market_account(seller)
	var count := 0
	for order in market_orders.values():
		if str(order["account"]) == account:
			count += 1
	if count >= MarketBoard.MAX_PER_SELLER:
		return {"ok": false, "reason": "too_many_listings"}
	# Escrow: the goods leave the backpack now, so the offer stays good while the seller is away.
	if not seller.inventory.remove(item_id, quantity):
		return {"ok": false, "reason": "missing_items"}
	seller.inventory.unequip_missing()
	seller.dirty_inventory = true
	seller.dirty_character = true
	var listing_id: int = new_id()
	market_orders[listing_id] = {
		"account": account, "seller_name": seller.name, "item": item_id, "remaining": quantity,
		"price": unit_price, "expires": time + MarketBoard.LISTING_LIFETIME,
	}
	return {"ok": true, "action": "created", "id": listing_id}


func cmd_market_cancel(peer_id: int, listing_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	var order: Dictionary = market_orders.get(listing_id, {})
	if order.is_empty() or player == null:
		return {"ok": false, "reason": "unknown_listing"}
	if str(order["account"]) != _market_account(player):
		return {"ok": false, "reason": "not_owner"}
	market_orders.erase(listing_id)
	# Goods come back to the backpack when there is room; the rest waits in market returns.
	var left: int = player.inventory.add(str(order["item"]), int(order["remaining"]))
	_market_return(str(order["account"]), str(order["item"]), left)
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "action": "cancelled", "id": listing_id, "returned_later": left}


## A market purchase must have a monotonically increasing, session-scoped request ID.
## A retry returns the original result, never a second transfer, even after a partial fill.
## Old IDs are refused rather than evicted and potentially executed a second time.
func cmd_market_buy(peer_id: int, listing_id: int, quantity: int, request_id: int) -> Dictionary:
	if not players.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	if request_id < 1 or request_id > MARKET_MAX_REQUEST_ID:
		return {"ok": false, "reason": "invalid_request_id"}
	var last: Dictionary = market_buy_requests.get(peer_id, {})
	if not last.is_empty():
		var used_id: int = int(last["id"])
		if request_id < used_id:
			return {"ok": false, "reason": "stale_request"}
		if request_id == used_id:
			if int(last["listing"]) != listing_id or int(last["quantity"]) != quantity:
				return {"ok": false, "reason": "request_conflict"}
			var cached: Dictionary = last["result"]
			return cached.duplicate(true)
	var result: Dictionary = _execute_market_buy(peer_id, listing_id, quantity)
	result["request_id"] = request_id
	market_buy_requests[peer_id] = {
		"id": request_id, "listing": listing_id, "quantity": quantity,
		"result": result.duplicate(true),
	}
	return result


func _execute_market_buy(peer_id: int, listing_id: int, quantity: int) -> Dictionary:
	var buyer: Player = players.get(peer_id)
	if not _market_at_hub(buyer):
		return {"ok": false, "reason": "no_station"}
	_tick_market()
	var listing: Dictionary = market_orders.get(listing_id, {})
	if listing.is_empty():
		return {"ok": false, "reason": "unknown_listing"}
	if str(listing["account"]) == _market_account(buyer):
		return {"ok": false, "reason": "self_purchase"}
	if _pair_locked([peer_id]):
		return {"ok": false, "reason": "saving_previous_deal"}
	var transaction: Dictionary = MarketBoard.purchase_from_escrow(buyer.inventory, listing, quantity)
	if not transaction.get("ok", false):
		return transaction
	listing["remaining"] = int(listing["remaining"]) - quantity
	if int(listing["remaining"]) <= 0:
		market_orders.erase(listing_id)
	var account: String = str(listing["account"])
	market_payouts[account] = int(market_payouts.get(account, 0)) + int(transaction["seller_net"])
	buyer.dirty_inventory = true
	buyer.dirty_character = true
	# An online seller at the hub is paid at once; anyone else collects at the hub later.
	for seller in players.values():
		if _market_account(seller) == account and _market_at_hub(seller):
			_market_collect(seller)
			events.append({"type": "market_sale", "peer": seller.id, "item": listing["item"],
				"quantity": quantity, "net": transaction["seller_net"]})
	var receipt_id: int = new_id()
	market_sales.append({
		"id": receipt_id, "buyer": peer_id, "seller_account": account,
		"listing": listing_id, "item": listing["item"],
		"quantity": quantity, "total": transaction["total"],
		"tax": transaction["tax"], "seller_net": transaction["seller_net"],
	})
	if market_sales.size() > 128:
		market_sales.pop_front()
	return {
		"ok": true, "action": "bought", "id": listing_id,
		"receipt": receipt_id, "quantity": quantity,
		"item": listing["item"], "total": transaction["total"],
		"tax": transaction["tax"], "seller_net": transaction["seller_net"],
	}


## The safe-hub vendor uses server position and inventory only.
## A rejected trade leaves every item and silver balance unchanged.
func cmd_vendor(peer_id: int, item_id: String, quantity: int, buy: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var location := Vector2(player.position.x, player.position.z)
	if not location.is_finite() or not _at_workbench(location):
		return {"ok": false, "reason": "no_station"}
	# The quote depends only on the real server player position and
	# deterministic settlement identity. A client cannot name a town or rate.
	var offer: Dictionary = RegionalTrade.local_offer(world, player.position)
	var quoted_unit: int = RegionalTrade.sell_price(item_id, offer) if not buy else 0
	var outcome: Dictionary = Vendor.transact(player.inventory, item_id, quantity, buy,
		player.renown, player.pvp_infamy, quoted_unit if not buy else 0)
	if outcome.get("ok", false):
		player.dirty_inventory = true
		player.dirty_character = true
		if not buy and not offer.is_empty() and \
				str(offer["category"]) == RegionalTrade.category(item_id):
			outcome["regional_bonus"] = int(outcome["unit_price"]) - int(Vendor.SELL_PRICES[item_id])
			outcome["settlement"] = str(offer["name"])
	return outcome


## Captured frontier outpost supplies: authenticated server-owned ownership,
## exact on-site position, live enemy contest, one account claim per capture.
## No client may specify the reward, party, token, or cache contents.
func cmd_outpost_supplies(peer_id: int, site_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var result: Dictionary = territory.claim_supplies(site_id, player,
		players, parties, world, time)
	if bool(result.get("ok", false)):
		player.dirty_inventory = true
		player.dirty_character = true
	return result


## Only confirmed server events award reputation; no client RPC can submit
## an arbitrary score, rank or vendor discount.
func _earn_renown(player: Player, points: int, source: String) -> void:
	var previous: int = player.renown
	player.renown = Reputation.apply_earned(previous, points)
	if player.renown == previous:
		return
	player.dirty_character = true
	events.append({"type": "renown", "peer": player.id,
		"earned": player.renown - previous,
		"total": player.renown,
		"rank": Reputation.title(player.renown),
		"source": source})


## Camp contracts use the same real hub distance check as the vendor and bank.
## The only client input is accept/claim, never rewards, progress or prices.
## Camp recovery is an authoritative, resource-paid sanctuary action.
## Recent combat and noise lockouts prevent instant healing during danger.
func cmd_rest(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var point := Vector2(player.position.x, player.position.z)
	if not point.is_finite():
		return {"ok": false, "reason": "no_station"}
	var at_hub: bool = _is_safe(player.position) and point.distance_to(WORKBENCH_POSITION) <= WORKBENCH_RANGE
	var at_fire: bool = not at_hub and FieldCampfire.has_warmth(campfires, player.position, time)
	if not at_hub and not at_fire:
		return {"ok": false, "reason": "no_station"}
	if player.rest_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.rest_cooldown}
	if player.attack_timer > 0.0 or player.skill_timer > 0.0 or player.noise_timer > 0.0:
		return {"ok": false, "reason": "in_combat"}
	if not CampRest.needs_recovery(player.survival):
		return {"ok": false, "reason": "fully_rested"}
	if at_fire:
		var threat: String = FieldRest.danger(world, player, players, parties, zombies)
		if not threat.is_empty():
			return {"ok": false, "reason": threat}
		if not FieldRest.has_supplies(player.inventory):
			return {"ok": false, "reason": "missing_items"}
		if not FieldRest.recover(player.inventory, player.survival):
			return {"ok": false, "reason": "transaction_failed"}
	else:
		if not CampRest.has_supplies(player.inventory):
			return {"ok": false, "reason": "missing_items"}
		if not CampRest.recover(player.inventory, player.survival):
			return {"ok": false, "reason": "transaction_failed"}
	player.rest_cooldown = CampRest.COOLDOWN
	# Paid and safe recovery earns a limited reserve of extra skill training.
	player.rested_xp_credit = RestedTraining.refill(player.rested_xp_credit, at_fire)
	player.action = {}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "rested": true, "field": at_fire,
		"cooldown": player.rest_cooldown, "rested_xp_credit": player.rested_xp_credit,
		"health": player.survival.health, "stamina": player.survival.stamina}

## Roll forward once at midnight UTC, persisting a fresh daily journal.
## A backwards-moving host clock cannot revive a previously claimed day.
func _refresh_daily(player: Player) -> int:
	var today: int = DailyBounties.utc_day()
	if DailyBounties.refresh(player.daily_bounty, today):
		player.dirty_character = true
	return today


## Cancel orphaned event mobs after route disposal or disconnect. They must
## not become a reward for a new player who inherits the same network peer ID.
func _clear_caravan_waves(peer_id: int) -> void:
	for index in range(caravan_ambushes.size() - 1, -1, -1):
		var wave: Dictionary = caravan_ambushes[index]
		if int(wave.get("owner", -1)) != peer_id:
			continue
		for infected_id in wave["ids"]:
			zombies.erase(int(infected_id))
		caravan_ambushes.remove_at(index)


## Cross-settlement resource couriers: the server selects and validates
## both real NPC stations. Goods are gathered by the player, not spawned.
func cmd_caravan(peer_id: int, action: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if action == "abandon":
		if player.caravan_state.is_empty():
			return {"ok": false, "reason": "no_active"}
		_clear_caravan_waves(peer_id)
		player.caravan_state = {}
		player.caravan_view = {}
		player.caravan_ambushed = false
		player.caravan_defended = false
		player.caravan_night = {}
		caravan_escort_progress.erase(peer_id)
		player.dirty_character = true
		return {"ok": true, "action": "abandon"}
	if action != "accept" and action != "deliver":
		return {"ok": false, "reason": "unknown_action"}
	var station: Dictionary = CaravanRoutes.station_at(world, player.position)
	if station.is_empty():
		return {"ok": false, "reason": "no_station"}
	if action == "accept":
		if not player.caravan_state.is_empty():
			return {"ok": false, "reason": "already_active"}
		var offer: Dictionary = CaravanRoutes.offer_for(world, station)
		if offer.is_empty():
			return {"ok": false, "reason": "no_route"}
		_clear_caravan_waves(peer_id)
		player.caravan_state = CaravanRoutes.saved_state(offer)
		player.caravan_view = offer.duplicate(true)
		player.caravan_night = NightCaravan.initial(player.caravan_view)
		caravan_escort_progress.erase(peer_id)
		player.caravan_ambushed = false
		player.caravan_defended = false
		player.dirty_character = true
		return {"ok": true, "action": "accept", "route": offer.duplicate(true)}
	if player.caravan_state.is_empty() or player.caravan_view.is_empty():
		return {"ok": false, "reason": "no_active"}
	if int(station["id"]) != int(player.caravan_view["dst_id"]):
		return {"ok": false, "reason": "wrong_destination"}
	var eligible_escorts: Array = []
	var group_id: int = parties.group_of(peer_id)
	if group_id > 0:
		for member_id in parties.members_of(peer_id):
			if int(member_id) == peer_id:
				continue
			var member: Player = players.get(int(member_id))
			if member == null or not _alive(member):
				continue
			if CaravanEscortRewards.qualifies(caravan_escort_progress,
					peer_id, member.id, group_id, player.caravan_view,
					player.position, member.position):
				eligible_escorts.append(member)
	var outcome: Dictionary = CaravanEscortRewards.settle(
		player, eligible_escorts, player.caravan_view, player.caravan_defended,
		player.caravan_night)
	if not bool(outcome.get("ok", false)):
		return outcome
	caravan_escort_progress.erase(peer_id)
	_clear_caravan_waves(peer_id)
	player.caravan_state = {}
	player.caravan_view = {}
	player.caravan_ambushed = false
	player.caravan_defended = false
	player.caravan_night = {}
	player.dirty_inventory = true
	player.dirty_character = true
	for member in eligible_escorts:
		member.dirty_inventory = true
		member.dirty_character = true
		_award(member, "explorer", 10.0)
		_earn_renown(member, 2, "caravan_escort")
		var payout: int = 0
		for receipt in outcome.get("escorts", []):
			if int(receipt["peer"]) == member.id:
				payout = int(receipt["silver"])
				break
		events.append({"type": "caravan_escort_paid", "peer": member.id,
			"silver": payout})
	_award(player, "explorer", 20.0)
	_earn_renown(player, 4, "caravan")
	# Only a successful, fully settled NPC-to-NPC delivery recovers
	# Chapter III's convoy waypoint. Escort payouts alone never count.
	if StoryChapterThree.record_delivery(player.story3_state):
		player.dirty_character = true
		_story3_event(player)
	outcome["action"] = "deliver"
	return outcome


## Only owner-visible server-authored narrative events; no targets, location,
## chapter checkpoint or rewards are accepted from remote client RPC data.
func _story3_event(player: Player) -> void:
	events.append({"type": "story3", "peer": player.id,
		"stage": int(player.story3_state["stage"]),
		"line": StoryChapterThree.current_line(player.story3_state),
		"objective": StoryChapterThree.objective(player.story3_state)})


func _story2_event(player: Player) -> void:
	events.append({"type": "story2", "peer": player.id,
		"stage": int(player.story2_state["stage"]),
		"line": StoryChapterTwo.current_line(player.story2_state),
		"objective": StoryChapterTwo.objective(player.story2_state)})


## All chapter radio commands require a living authenticated survivor at
## a real workbench; Chapter III requires the saved Chapter II finale.
func cmd_story(peer_id: int, action: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if action != "listen" and action != "transmit" and action != "decode" \
			and action != "seal" and action != "broadcast" and action != "trace" \
			and action != "guide" and action != "mask":
		return {"ok": false, "reason": "unknown_action"}
	var position := Vector2(player.position.x, player.position.z)
	if not _at_workbench(position):
		return {"ok": false, "reason": "no_station"}
	if action == "trace" or action == "guide" or action == "mask":
		if int(player.story2_state.get("stage", 0)) != StoryChapterTwo.LAST_STAGE:
			return {"ok": false, "reason": "chapter_two_incomplete"}
		var continuation: Dictionary = StoryChapterThree.begin(player.story3_state,
			str(player.story2_state["ending"])) if action == "trace" else \
			StoryChapterThree.resolve(player.story3_state, player.inventory, action)
		if bool(continuation.get("ok", false)):
			player.dirty_character = true
			if action == "guide" or action == "mask":
				player.dirty_inventory = true
			_story3_event(player)
		return continuation
	if action == "decode" or action == "seal" or action == "broadcast":
		if int(player.story_state.get("stage", 0)) != StoryCampaign.LAST_STAGE:
			return {"ok": false, "reason": "chapter_one_incomplete"}
		var followup: Dictionary = StoryChapterTwo.begin(player.story2_state) if action == "decode" \
			else StoryChapterTwo.resolve(player.story2_state, player.inventory, action)
		if bool(followup.get("ok", false)):
			player.dirty_character = true
			if action == "seal" or action == "broadcast":
				player.dirty_inventory = true
			_story2_event(player)
		return followup
	var result: Dictionary = StoryCampaign.listen(player.story_state) if action == "listen" \
		else StoryCampaign.transmit(player.story_state, player.inventory)
	if bool(result.get("ok", false)):
		player.dirty_character = true
		if action == "transmit":
			player.dirty_inventory = true
		events.append({"type": "story", "peer": peer_id,
			"stage": int(player.story_state["stage"]),
			"line": StoryCampaign.current_line(player.story_state),
			"objective": StoryCampaign.objective(player.story_state)})
	return result


func cmd_contract(peer_id: int, action: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var at: Vector2 = Vector2(player.position.x, player.position.z)
	if not at.is_finite() or not _at_workbench(at):
		return {"ok": false, "reason": "no_station"}
	var result: Dictionary = {}
	match action:
		"accept": result = Contracts.accept(player.contract_state)
		"claim": result = Contracts.claim(player.inventory, player.contract_state)
		"daily_claim":
			var today: int = _refresh_daily(player)
			result = DailyBounties.claim(player.inventory, player.daily_bounty, today)
		_: return {"ok": false, "reason": "unknown_action"}
	if bool(result.get("ok", false)):
		player.dirty_character = true
		if action == "claim":
			player.dirty_inventory = true
			_earn_renown(player, Reputation.CONTRACT_RENOWN, "contract")
		elif action == "daily_claim":
			player.dirty_inventory = true
			_earn_renown(player, int(result.get("renown", 0)), "daily_bounty")
	return result


## Authoritative hub bank: move a bounded item stack only when the actual
## server position is near the workbench. A failed operation changes nothing.
func cmd_stash(peer_id: int, item_id: String, count: int, deposit: bool) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var distance: float = Vector2(player.position.x, player.position.z).distance_to(WORKBENCH_POSITION)
	if (not is_finite(distance) or distance > WORKBENCH_RANGE) and not _near_piece(player.position, "chest", player):
		return {"ok": false, "reason": "no_station"}
	if not Defs.is_item(item_id) or count < 1 or count > Defs.stack_size(item_id):
		return {"ok": false, "reason": "invalid_stack"}
	var source = player.inventory if deposit else player.stash
	var destination = player.stash if deposit else player.inventory
	if source.count(item_id) < count:
		return {"ok": false, "reason": "missing_items"}
	if destination.free_space_for(item_id) < count:
		return {"ok": false, "reason": "no_space"}
	# Source and destination are exclusively server-owned. The destination
	# has been capacity-checked so these operations cannot partially succeed.
	if not source.remove(item_id, count):
		return {"ok": false, "reason": "missing_items"}
	var left: int = destination.add(item_id, count)
	if left != 0:
		# Defensive rollback if future inventory implementations change.
		destination.remove(item_id, count - left)
		source.add(item_id, count)
		return {"ok": false, "reason": "transaction_failed"}
	if deposit:
		player.inventory.unequip_missing()
	player.dirty_inventory = true
	player.dirty_stash = true
	player.dirty_character = true
	return {"ok": true, "item": item_id, "count": count, "deposit": deposit}


## Players may record and swap three owned gear sets only at the hub workbench.
## Client requests carry no gear IDs: server owns the inventory and saved sets.
## Combat, movement actions, mounts and recall cannot become instant gear swaps.
func cmd_equipment_preset(peer_id: int, action: String, slot: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "unknown_player"}
	if not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not _market_at_hub(player):
		return {"ok": false, "reason": "no_station"}
	if slot < 0 or slot >= EquipmentPresets.SLOT_COUNT:
		return {"ok": false, "reason": "invalid_slot"}
	if player.mounted or not player.recall.is_empty() or \
			player.combat_tag_until > time or player.attack_timer > 0.0 or \
			player.skill_timer > 0.0 or not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	var result: Dictionary = {}
	match action:
		"save":
			result = EquipmentPresets.save_slot(player.equipment_presets, slot, player.inventory)
		"equip":
			result = EquipmentPresets.equip_slot(player.equipment_presets, slot, player.inventory)
		"clear":
			result = EquipmentPresets.clear_slot(player.equipment_presets, slot)
		_:
			return {"ok": false, "reason": "invalid_action"}
	if not bool(result.get("ok", false)):
		return result
	if action == "equip":
		if bool(result.get("weapon_changed", false)):
			player.edge_coating_seconds = 0.0
			player.edge_coating_weapon = ""
			player.sharpened_weapon = ""
			player.sharpened_hits = 0
			player.parry_window = 0.0
			ParryRiposte.clear(player)
		if bool(result.get("armor_changed", false)):
			player.plated_armor = ""
			player.plated_hits = 0
		player.guardian_brace = 0.0
		player.dirty_inventory = true
	player.dirty_character = true
	result["action"] = action
	return result


## One server-authorized action banks raw and refined crafting inputs.
## The client selects no item IDs, quantities or receipt; failed operations
## do not modify either inventory or the account-bound protected bank.
func cmd_expedition_restock(peer_id: int, preset_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var at := Vector2(player.position.x, player.position.z)
	if not at.is_finite() or at.distance_to(WORKBENCH_POSITION) > WORKBENCH_RANGE:
		return {"ok": false, "reason": "no_station"}
	var result: Dictionary = ExpeditionLoadout.restock(
		player.inventory, player.stash, preset_id)
	if bool(result.get("ok", false)):
		player.dirty_inventory = true
		player.dirty_stash = true
		player.dirty_character = true
	return result


func cmd_stash_bulk(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var at := Vector2(player.position.x, player.position.z)
	if (not at.is_finite() or at.distance_to(WORKBENCH_POSITION) > WORKBENCH_RANGE) and not _near_piece(player.position, "chest", player):
		return {"ok": false, "reason": "no_station"}
	var result: Dictionary = StashBulk.deposit(player.inventory, player.stash)
	if not bool(result.get("ok", false)):
		return result
	player.inventory.unequip_missing()
	player.dirty_inventory = true
	player.dirty_stash = true
	player.dirty_character = true
	return result


## Validate and build entirely on the authority. Clients only request a location.
## Building is intentionally forbidden inside the town sanctuary.
## The client requests coordinates, but cannot claim warmth, time or a free
## fire. All placement and inventory costs are validated by the server.
## The client supplies a direction, not the position, price or affected NPCs.
## Cost and flight-path validation happen atomically on this simulation.
## Deploy only by spending a real crafted kit at a verified outdoor site.
## Account-bound owner caps prevent relogging to bypass the three-trap limit.
func cmd_place_infected_snare(peer_id: int, x: float, z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if infected_snares.size() >= InfectedSnare.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owner_key: String = "account:" + player.user_id if player.user_id != "" else "guest:" + str(peer_id)
	var owned: int = 0
	for trap in infected_snares.values():
		if str(trap["owner_key"]) == owner_key and float(trap["expires"]) > time:
			owned += 1
	if owned >= InfectedSnare.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var site := Vector2(x, z)
	var origin := Vector2(player.position.x, player.position.z)
	var reason: String = InfectedSnare.valid_site(world, site, origin, infected_snares)
	if reason != "":
		return {"ok": false, "reason": reason}
	# No immediate telefragging or trapping players under their own feet.
	for other in players.values():
		if _alive(other) and site.distance_to(Vector2(other.position.x, other.position.z)) <= InfectedSnare.TRIGGER_RADIUS:
			return {"ok": false, "reason": "blocked"}
	for infected in zombies.values():
		if infected.is_alive() and site.distance_to(Vector2(infected.position.x, infected.position.z)) <= InfectedSnare.TRIGGER_RADIUS:
			return {"ok": false, "reason": "blocked"}
	if player.inventory.count(InfectedSnare.ITEM_ID) < 1 or not player.inventory.remove(InfectedSnare.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var id: int = new_id()
	infected_snares[id] = {"id": id, "x": x, "y": world.height_at(x, z), "z": z,
		"owner_key": owner_key, "expires": time + InfectedSnare.DURATION}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "seconds": InfectedSnare.DURATION}


## A one-shot, inventory-paid, obstacle-checked PvE interrupt. Never trust
## player-supplied impact positions, affected zombie IDs, or target counts.
func cmd_throw_flash(peer_id: int, direction_x: float, direction_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	if player.flash_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.flash_cooldown}
	var site: Dictionary = FlashCharge.landing(world, player.position,
		Vector2(direction_x, direction_z))
	if site.is_empty():
		return {"ok": false, "reason": "invalid_landing"}
	var candidates: Array = FlashCharge.targets(world, site, zombies)
	if candidates.is_empty():
		return {"ok": false, "reason": "no_targets"}
	if player.inventory.count(FlashCharge.ITEM_ID) < 1 or not player.inventory.remove(
			FlashCharge.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var interrupted: int = 0
	for infected in candidates:
		if infected.apply_stagger(FlashCharge.STAGGER_SECONDS):
			interrupted += 1
			events.append({"type": "stagger", "id": infected.id,
				"seconds": infected.stagger_seconds,
				"x": infected.position.x, "z": infected.position.z})
	player.flash_cooldown = FlashCharge.COOLDOWN_SECONDS
	player.noise_radius = maxf(player.noise_radius, FlashCharge.PLAYER_NOISE_RADIUS)
	player.noise_timer = maxf(player.noise_timer, FlashCharge.NOISE_SECONDS)
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "flash_thrown", "peer": peer_id,
		"x": site["x"], "z": site["z"], "hits": interrupted})
	return {"ok": true, "hits": interrupted, "cooldown": player.flash_cooldown}


## Inventory-paid, obstacle-checked PvE fire. Shares the persistent flash
## timer to avoid rapid alternating charges or reconnect cooldown bypasses.
func cmd_throw_ember(peer_id: int, direction_x: float, direction_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if not player.action.is_empty():
		return {"ok": false, "reason": "busy"}
	if player.flash_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if ember_pools.size() >= EmberFlask.MAX_ACTIVE:
		return {"ok": false, "reason": "world_limit"}
	var owned: int = 0
	for field in ember_pools.values():
		if int(field["owner"]) == peer_id and EmberFlask.remaining(field, time) > 0.0:
			owned += 1
	if owned >= EmberFlask.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var site: Dictionary = EmberFlask.landing(world, player.position,
		Vector2(direction_x, direction_z))
	if site.is_empty():
		return {"ok": false, "reason": "invalid_landing"}
	if player.inventory.count(EmberFlask.ITEM_ID) < 1 or not player.inventory.remove(
			EmberFlask.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var id: int = new_id()
	ember_pools[id] = EmberFlask.make_pool(id, site, peer_id, time)
	player.flash_cooldown = EmberFlask.COOLDOWN_SECONDS
	player.noise_radius = maxf(player.noise_radius, EmberFlask.NOISE_RADIUS)
	player.noise_timer = maxf(player.noise_timer, EmberFlask.NOISE_SECONDS)
	player.action = {}
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "ember_thrown", "peer": peer_id, "id": id,
		"x": site["x"], "z": site["z"]})
	return {"ok": true, "id": id, "seconds": EmberFlask.DURATION,
		"cooldown": player.flash_cooldown}


func cmd_throw_decoy(peer_id: int, direction_x: float, direction_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.decoy_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if decoys.size() >= NoiseDecoy.MAX_ACTIVE:
		return {"ok": false, "reason": "world_limit"}
	var owned: int = 0
	for lure in decoys.values():
		if int(lure["owner"]) == peer_id and float(lure["expires"]) > time:
			owned += 1
	if owned >= NoiseDecoy.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var site: Dictionary = NoiseDecoy.landing(world, player.position,
			Vector2(direction_x, direction_z))
	if site.is_empty():
		return {"ok": false, "reason": "invalid_landing"}
	if player.inventory.count(NoiseDecoy.ITEM_ID) < 1:
		return {"ok": false, "reason": "not_carried"}
	if not player.inventory.remove(NoiseDecoy.ITEM_ID, 1):
		return {"ok": false, "reason": "not_carried"}
	var id: int = new_id()
	decoys[id] = {"id": id, "x": site["x"], "y": site["y"], "z": site["z"],
		"owner": peer_id, "expires": time + NoiseDecoy.DURATION}
	player.decoy_timer = NoiseDecoy.COOLDOWN
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "decoy_thrown", "peer": peer_id,
		"x": site["x"], "z": site["z"]})
	return {"ok": true, "id": id, "seconds": NoiseDecoy.DURATION}


## Shared expedition tarp: weather reduction, not PvP protection.
func cmd_pitch_shelter(peer_id: int, x: float, z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if shelters.size() >= PortableShelter.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owned := 0
	for tarp in shelters.values():
		if Structures.can_manage(tarp, peer_id, player.user_id):
			owned += 1
	if owned >= PortableShelter.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var point := Vector2(x, z)
	var origin := Vector2(player.position.x, player.position.z)
	var reason: String = PortableShelter.valid_site(world, point, origin,
		shelters, campfires)
	if reason != "":
		return {"ok": false, "reason": reason}
	for other in players.values():
		if _alive(other) and point.distance_to(
				Vector2(other.position.x, other.position.z)) < (
				PortableShelter.CANOPY_RADIUS + Defs.PLAYER_RADIUS + 0.15):
			return {"ok": false, "reason": "blocked"}
	for infected in zombies.values():
		if infected.is_alive() and point.distance_to(
				Vector2(infected.position.x, infected.position.z)) < (
				PortableShelter.CANOPY_RADIUS + 0.7):
			return {"ok": false, "reason": "blocked"}
	if not player.inventory.has_all(PortableShelter.COST):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in PortableShelter.COST:
		player.inventory.remove(str(item_id), int(PortableShelter.COST[item_id]))
	var id := new_id()
	shelters[id] = {"id": id, "x": point.x, "y": world.height_at(x, z),
		"z": point.y, "owner": peer_id, "owner_account": player.user_id,
		"expires": time + PortableShelter.DURATION, "anchored": false}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "seconds": PortableShelter.DURATION}


func cmd_pack_shelter(peer_id: int, shelter_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var tarp: Dictionary = shelters.get(shelter_id, {})
	if tarp.is_empty() or float(tarp["expires"]) <= time:
		return {"ok": false, "reason": "no_shelter"}
	if not Structures.can_manage(tarp, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if Vector2(player.position.x, player.position.z).distance_squared_to(
			Vector2(float(tarp["x"]), float(tarp["z"]))) > (
			PortableShelter.PACK_RANGE * PortableShelter.PACK_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	shelters.erase(shelter_id)
	return {"ok": true, "id": shelter_id}


func cmd_light_campfire(peer_id: int, x: float, z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if campfires.size() >= FieldCampfire.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owned := 0
	for fire in campfires.values():
		if Structures.can_manage(fire, peer_id, player.user_id):
			owned += 1
	if owned >= FieldCampfire.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	var position := Vector2(x, z)
	var origin := Vector2(player.position.x, player.position.z)
	var reason: String = FieldCampfire.valid_site(world, position, origin, campfires)
	if reason != "":
		return {"ok": false, "reason": reason}
	for other in players.values():
		if _alive(other) and position.distance_to(Vector2(other.position.x, other.position.z)) < (
				FieldCampfire.CAMP_RADIUS + Defs.PLAYER_RADIUS + 0.15):
			return {"ok": false, "reason": "blocked"}
	for infected in zombies.values():
		if infected.is_alive() and position.distance_to(
				Vector2(infected.position.x, infected.position.z)) < FieldCampfire.CAMP_RADIUS + 0.7:
			return {"ok": false, "reason": "blocked"}
	if not player.inventory.has_all(FieldCampfire.COST):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in FieldCampfire.COST:
		player.inventory.remove(str(item_id), int(FieldCampfire.COST[item_id]))
	var id := new_id()
	campfires[id] = {"id": id, "x": x, "y": world.height_at(x, z), "z": z,
		"owner": peer_id, "owner_account": player.user_id,
		"expires": time + FieldCampfire.DURATION}
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "seconds": FieldCampfire.DURATION}


## Nearby survivors may cooperatively fuel an existing fire. The server
## validates its deadline and charges the correct backpack before extending it.
## The account/session owner can extinguish an ephemeral campfire early.
## Fuel is already burned and never refunded; strangers cannot delete the
## group's heating by guessing a network entity ID.
func cmd_extinguish_campfire(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var camp: Dictionary = campfires.get(id, {})
	if camp.is_empty() or float(camp["expires"]) <= time:
		return {"ok": false, "reason": "no_fire"}
	if not Structures.can_manage(camp, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	if not Structures.within_range(Vector2(player.position.x, player.position.z),
			Vector2(float(camp["x"]), float(camp["z"])), FieldCampfire.REFUEL_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	campfires.erase(id)
	events.append({"type": "campfire_extinguished", "id": id, "peer": peer_id})
	return {"ok": true, "id": id}


## Attach a crafted 3-minute infected warning kit to a burning campfire.
## Only a real nearby survivor can pay; server chooses who hears the signal.
func cmd_arm_camp_alarm(peer_id: int, fire_id: int) -> Dictionary:
	var survivor: Player = players.get(peer_id)
	if survivor == null or not _alive(survivor):
		return {"ok": false, "reason": "dead"}
	if survivor.mounted:
		return {"ok": false, "reason": "mounted"}
	if not survivor.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if survivor.combat_tag_until > time or survivor.attack_timer > 0.0 or (
			survivor.skill_timer > 0.0 or not survivor.action.is_empty()):
		return {"ok": false, "reason": "in_combat"}
	var fire: Dictionary = campfires.get(fire_id, {})
	var reason: String = CampAlarm.arm_reason(fire, survivor.position, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	if not survivor.inventory.remove(CampAlarm.ITEM_ID, 1):
		return {"ok": false, "reason": "missing_kit"}
	CampAlarm.install(fire, peer_id, parties.group_of(peer_id), time)
	campfires[fire_id] = fire
	survivor.dirty_inventory = true
	survivor.dirty_character = true
	return {"ok": true, "id": fire_id, "seconds": CampAlarm.seconds_left(fire, time),
		"radius": CampAlarm.DETECTION_RADIUS}


func cmd_refuel_campfire(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var camp: Dictionary = campfires.get(id, {})
	var reason: String = FieldCampfire.refuel_reason(camp, player.position, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	if not player.inventory.has_all(FieldCampfire.REFUEL_COST):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in FieldCampfire.REFUEL_COST:
		player.inventory.remove(str(item_id), int(FieldCampfire.REFUEL_COST[item_id]))
	camp["expires"] = minf(time + FieldCampfire.MAX_REMAINING_SECONDS,
			float(camp["expires"]) + FieldCampfire.REFUEL_SECONDS)
	campfires[id] = camp
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "campfire_refueled", "id": id, "peer": peer_id})
	return {"ok": true, "id": id, "remaining": float(camp["expires"]) - time}


## House pieces snap to the 3 m grid; each slot (cell edge, floor, roof, corner) holds one piece.
const MAX_PIECES_PER_OWNER := 80
const MAX_PIECES_GLOBAL := 2500


func cmd_build_piece(peer_id: int, piece: String, x: float, z: float, facing: float = 0.0) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not HousePieces.valid(piece):
		return {"ok": false, "reason": "invalid_piece"}
	var snapped: Vector3 = HousePieces.snap(piece, Vector2(x, z), facing)
	var reason: String = HousePieces.placement_reason(world, piece, snapped, Vector2(player.position.x, player.position.z))
	if reason != "":
		return {"ok": false, "reason": reason}
	if barricades.size() >= MAX_PIECES_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owned := 0
	for item in barricades.values():
		if Structures.can_manage(item, peer_id, player.user_id):
			owned += 1
		var other_piece: String = str(item.get("piece", ""))
		if other_piece != "" and HousePieces.slot(other_piece) == HousePieces.slot(piece) \
				and Vector2(float(item["x"]) - snapped.x, float(item["z"]) - snapped.y).length() < 0.2:
			return {"ok": false, "reason": "occupied"}
	if owned >= MAX_PIECES_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	if HousePieces.blocks(piece):
		for circle in HousePieces.blockers(piece, snapped.x, snapped.y, snapped.z):
			var at := Vector2(float(circle[0]), float(circle[1]))
			for other in players.values():
				if _alive(other) and Structures.within_range(at, Vector2(other.position.x, other.position.z), float(circle[2]) + Defs.PLAYER_RADIUS + 0.1):
					return {"ok": false, "reason": "blocked"}
			for infected in zombies.values():
				if infected.is_alive() and Structures.within_range(at, Vector2(infected.position.x, infected.position.z), float(circle[2]) + 0.6):
					return {"ok": false, "reason": "blocked"}
	var cost: Dictionary = HousePieces.COST[piece]
	if not player.inventory.has_all(cost):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in cost:
		player.inventory.remove(item_id, int(cost[item_id]))
	var id := new_id()
	var item := {"id": id, "x": snapped.x, "y": world.height_at(snapped.x, snapped.y) + HousePieces.elevation(piece), "z": snapped.y,
		"hp": Structures.MAX_HEALTH, "tier": 1, "owner": peer_id,
		"owner_account": player.user_id, "owner_guild": player.guild_id,
		"yaw": snapped.z, "piece": piece, "open": true, "upkeep_until": time + Structures.UPKEEP_SECONDS}
	barricades[id] = item
	world_structure_revision += 1
	world.add_structure_blockers(id, HousePieces.blockers_of(item))
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_built", "id": id, "peer": peer_id})
	return {"ok": true, "id": id, "piece": piece}


## A house piece of this kind within range of the spot; `owner` limits it to pieces that player may manage.
func _near_piece(spot: Vector3, piece: String, owner: Player = null) -> bool:
	if not spot.is_finite():
		return false
	var at := Vector2(spot.x, spot.z)
	for item in barricades.values():
		if str(item.get("piece", "")) != piece:
			continue
		if owner != null and not Structures.can_manage(item, owner.id, owner.user_id):
			continue
		if at.distance_to(Vector2(float(item["x"]), float(item["z"]))) <= HousePieces.STATION_RANGE:
			return true
	return false


## Open or shut a door. Its owner, their party and their guild may; everyone else has to break it.
func cmd_toggle_door(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not barricades.has(id) or str(barricades[id].get("piece", "")) != "door":
		return {"ok": false, "reason": "no_door"}
	var door: Dictionary = barricades[id]
	var at := Vector2(float(door["x"]), float(door["z"]))
	if at.distance_to(Vector2(player.position.x, player.position.z)) > HousePieces.DOOR_REACH:
		return {"ok": false, "reason": "too_far"}
	var allowed: bool = Structures.can_manage(door, peer_id, player.user_id)
	if not allowed:
		var owner_peer: int = int(door.get("owner", -1))
		if owner_peer > 0 and parties.group_of(owner_peer) != 0 and parties.group_of(owner_peer) == parties.group_of(peer_id):
			allowed = true
		elif str(door.get("owner_guild", "")) != "" and str(door.get("owner_guild", "")) == str(player.guild_id):
			allowed = true
	if not allowed:
		return {"ok": false, "reason": "locked"}
	var opening: bool = not bool(door.get("open", true))
	if not opening:
		# Never shut a door on someone standing in it.
		for other in players.values():
			if _alive(other) and at.distance_to(Vector2(other.position.x, other.position.z)) < 0.5 + Defs.PLAYER_RADIUS:
				return {"ok": false, "reason": "blocked"}
		for infected in zombies.values():
			if infected.is_alive() and at.distance_to(Vector2(infected.position.x, infected.position.z)) < 1.0:
				return {"ok": false, "reason": "blocked"}
	door["open"] = opening
	world.add_structure_blockers(id, HousePieces.blockers_of(door))
	world_structure_revision += 1
	events.append({"type": "door", "id": id, "open": opening, "x": at.x, "z": at.y})
	return {"ok": true, "open": opening}


## The nearest intact bed this survivor built, as a respawn spot beside it, or Vector2.INF.
func _bed_spawn(player: Player) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for item in barricades.values():
		if str(item.get("piece", "")) != "bed" or not Structures.can_manage(item, player.id, player.user_id):
			continue
		var bed := Vector2(float(item["x"]), float(item["z"]))
		var d: float = bed.distance_to(Vector2(player.position.x, player.position.z)) if player.position.is_finite() else 0.0
		if d < best_distance:
			best_distance = d
			best = bed
	if not best.is_finite():
		return Vector2.INF
	for attempt in 12:
		var candidate: Vector2 = best + Vector2.from_angle(TAU * float(attempt) / 12.0) * HousePieces.BED_RESPAWN_RANGE * 0.6
		var free := true
		for blocker in world.blockers_near(candidate.x, candidate.y, Defs.PLAYER_RADIUS + 1.0):
			if Vector2(float(blocker["x"]) - candidate.x, float(blocker["z"]) - candidate.y).length() < Defs.PLAYER_RADIUS + float(blocker["radius"]) + 0.1:
				free = false
				break
		if free and not world.is_water(candidate.x, candidate.y):
			return candidate
	return Vector2.INF


func cmd_build(peer_id: int, x: float, z: float, yaw: float = 0.0) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var point := Vector2(x, z)
	var from := Vector2(player.position.x, player.position.z)
	var reason: String = Structures.placement_reason(world, point, from)
	if reason != "":
		return {"ok": false, "reason": reason}
	if barricades.size() >= Structures.MAX_GLOBAL:
		return {"ok": false, "reason": "world_limit"}
	var owned := 0
	for item in barricades.values():
		if Structures.can_manage(item, peer_id, player.user_id):
			owned += 1
	if owned >= Structures.MAX_PER_OWNER:
		return {"ok": false, "reason": "owner_limit"}
	# Check the same blockers the movement solver queries; forbid overlapping
	# players and infected as well, before consuming building materials.
	for blocker in world.blockers_near(x, z, Structures.RADIUS + 1.0):
		var offset := Vector2(x - float(blocker["x"]), z - float(blocker["z"]))
		if offset.length() < Structures.RADIUS + float(blocker["radius"]) + 0.1:
			return {"ok": false, "reason": "blocked"}
	for other in players.values():
		if _alive(other) and Structures.within_range(point, Vector2(other.position.x, other.position.z), Structures.RADIUS + Defs.PLAYER_RADIUS + 0.2):
			return {"ok": false, "reason": "blocked"}
	for infected in zombies.values():
		if infected.is_alive() and Structures.within_range(point, Vector2(infected.position.x, infected.position.z), Structures.RADIUS + 0.65):
			return {"ok": false, "reason": "blocked"}
	if not player.inventory.has_all(Structures.COST):
		return {"ok": false, "reason": "missing_materials"}
	# No action between cost validation and removal: server simulation single thread.
	for item_id in Structures.COST:
		player.inventory.remove(item_id, int(Structures.COST[item_id]))
	var id := new_id()
	var item := {"id": id, "x": x, "y": world.height_at(x, z), "z": z,
		"hp": Structures.MAX_HEALTH, "tier": 1, "owner": peer_id,
		"owner_account": player.user_id, "owner_guild": player.guild_id,
		"yaw": Structures.snap_yaw(yaw), "upkeep_until": time + Structures.UPKEEP_SECONDS}
	barricades[id] = item
	world_structure_revision += 1
	world.add_dynamic_blocker(id, x, z, Structures.RADIUS)
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_built", "id": id, "peer": peer_id})
	return {"ok": true, "id": id}


func cmd_repair(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var item: Dictionary = barricades.get(id, {})
	if item.is_empty():
		return {"ok": false, "reason": "no_structure"}
	if not Structures.can_manage(item, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	var origin := Vector2(player.position.x, player.position.z)
	var target := Vector2(float(item["x"]), float(item["z"]))
	if not Structures.within_range(origin, target, Structures.REPAIR_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	var tier: int = Structures.tier_of(item)
	var max_hp: float = Structures.max_health(tier)
	var cost: Dictionary = Structures.repair_cost(tier)
	if max_hp <= 0.0:
		return {"ok": false, "reason": "invalid_tier"}
	if float(item["hp"]) >= max_hp:
		return {"ok": false, "reason": "full_health"}
	if not player.inventory.has_all(cost):
		return {"ok": false, "reason": "missing_materials"}
	for item_id in cost:
		player.inventory.remove(str(item_id), int(cost[item_id]))
	item["hp"] = minf(max_hp, float(item["hp"]) + Structures.repair_amount(tier))
	item["upkeep_until"] = time + Structures.UPKEEP_SECONDS
	barricades[id] = item
	world_structure_revision += 1
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "id": id, "hp": float(item["hp"]), "tier": tier}


## Upgrade the closest existing wall, not an arbitrary remote structure.
## Item costs are server-derived from the target tier, never RPC parameters.
func cmd_upgrade(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var item: Dictionary = barricades.get(id, {})
	if item.is_empty():
		return {"ok": false, "reason": "no_structure"}
	if not Structures.can_manage(item, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	var origin := Vector2(player.position.x, player.position.z)
	var target := Vector2(float(item["x"]), float(item["z"]))
	if not Structures.within_range(origin, target, Structures.UPGRADE_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	var old_tier: int = Structures.tier_of(item)
	if not Structures.valid_tier(old_tier):
		return {"ok": false, "reason": "invalid_tier"}
	if old_tier >= Structures.MAX_TIER:
		return {"ok": false, "reason": "max_tier"}
	var next_tier: int = old_tier + 1
	var cost: Dictionary = Structures.upgrade_cost(next_tier)
	if not player.inventory.has_all(cost):
		return {"ok": false, "reason": "missing_materials"}
	# Preserve damage ratio: upgrades do not secretly repair the wall.
	var fraction: float = clampf(float(item["hp"]) / Structures.max_health(old_tier), 0.0, 1.0)
	for item_id in cost:
		player.inventory.remove(str(item_id), int(cost[item_id]))
	item["tier"] = next_tier
	item["upkeep_until"] = time + Structures.UPKEEP_SECONDS
	item["hp"] = Structures.max_health(next_tier) * fraction
	barricades[id] = item
	world_structure_revision += 1
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_upgraded", "id": id, "tier": next_tier, "peer": peer_id})
	return {"ok": true, "id": id, "tier": next_tier, "hp": float(item["hp"])}


## Owner-only, local, all-or-nothing structure salvage.
## Never remove a world collider until the inventory accepts the full refund.
func cmd_dismantle(peer_id: int, id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	var structure: Dictionary = barricades.get(id, {})
	if structure.is_empty():
		return {"ok": false, "reason": "no_structure"}
	if not Structures.can_manage(structure, peer_id, player.user_id):
		return {"ok": false, "reason": "not_owner"}
	var origin := Vector2(player.position.x, player.position.z)
	var target := Vector2(float(structure["x"]), float(structure["z"]))
	if not Structures.within_range(origin, target, Structures.DISMANTLE_RANGE):
		return {"ok": false, "reason": "out_of_range"}
	var salvage: Dictionary = Structures.salvage_for_health(float(structure["hp"]), Structures.tier_of(structure))
	var trial = Inventory.new(player.inventory.slots.size())
	trial.load_dict(player.inventory.to_dict())
	for item_id in salvage:
		if trial.add(str(item_id), int(salvage[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	# Atomic gameplay commit: a failed attempt cannot erase a barricade or mint loot.
	player.inventory.load_dict(trial.to_dict())
	barricades.erase(id)
	_acid_wall_last_hit.erase(id)
	siege_last_by_wall.erase(id)
	siege_braces.erase(id)
	world_structure_revision += 1
	world.remove_dynamic_blocker(id)
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "barricade_dismantled", "id": id, "peer": peer_id})
	return {"ok": true, "id": id, "salvage": salvage}


func damage_barricade(id: int, damage: float) -> bool:
	# Returns true when the structure breaks. Can be used by zombie AI or
	# future server-side explosions. Never trusts a client-provided damage.
	if not barricades.has(id) or not is_finite(damage) or damage <= 0.0:
		return false
	var item: Dictionary = barricades[id]
	item["hp"] = maxf(0.0, float(item["hp"]) - damage * Structures.damage_factor(Structures.tier_of(item)))
	world_structure_revision += 1
	if float(item["hp"]) <= 0.0:
		barricades.erase(id)
		_acid_wall_last_hit.erase(id)
		siege_last_by_wall.erase(id)
		siege_braces.erase(id)
		world.remove_dynamic_blocker(id)
		events.append({"type": "barricade_broken", "id": id})
		return true
	barricades[id] = item
	return false


## Called only after a server-confirmed ranged shot found no living target
## in front of its first solid obstacle. No client can supply a wall ID or HP.
func _damage_ranged_cover(attacker: Player, origin: Vector2,
		direction: Vector2, reach: float, damage: float) -> bool:
	var surface: Dictionary = RangedCover.first_blocker(world, origin, direction, reach)
	var id: int = int(surface.get("id", -1))
	if not barricades.has(id):
		return false # Terrain and structures without server-owned HP stay indestructible.
	var wall: Dictionary = barricades[id]
	if not BarricadeBallistics.can_damage(attacker, wall,
			world.zone_at(attacker.position.x, attacker.position.z),
			world.zone_at(float(wall["x"]), float(wall["z"]))):
		return false
	# A reconstructed wall never inherits a forged client damage amount.
	var actual: float = BarricadeBallistics.raw_damage(damage)
	if actual <= 0.0:
		return false
	var old_hp: float = float(wall["hp"])
	var tier: int = Structures.tier_of(wall)
	var destroyed: bool = damage_barricade(id, actual)
	var new_hp: float = 0.0 if destroyed else float(barricades[id]["hp"])
	events.append({"type": "barricade_shot", "peer": attacker.id, "id": id,
		"hp": new_hp, "damage": old_hp - new_hp, "tier": tier})
	return true


## Smart field treatment, selected from the player's server-owned wounds and items.
## Server verifies food/drink intent and selects one carried, safe ration.
func cmd_smart_provision(peer_id: int, intent: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead", "smart_provision": true}
	if intent != "food" and intent != "drink":
		return {"ok": false, "reason": "invalid_intent", "smart_provision": true}
	if player.mounted:
		return {"ok": false, "reason": "mounted", "smart_provision": true}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling", "smart_provision": true}
	var item_id: String = SmartProvisions.pick(player.inventory, player.survival, intent)
	if item_id.is_empty():
		return {"ok": false, "reason": "no_provision", "smart_provision": true}
	var result: Dictionary = cmd_use(peer_id, item_id)
	result["smart_provision"] = true
	result["item"] = item_id
	result["intent"] = intent
	return result


func cmd_quick_medicine(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead", "quick_medicine": true}
	if player.mounted:
		return {"ok": false, "reason": "mounted", "quick_medicine": true}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling", "quick_medicine": true}
	var item_id: String = QuickMedicine.pick(player.inventory, player.survival)
	if item_id.is_empty():
		return {"ok": false, "reason": "no_treatment", "quick_medicine": true}
	var result: Dictionary = cmd_use(peer_id, item_id)
	result["quick_medicine"] = true
	result["item"] = item_id
	return result


func cmd_use(peer_id: int, item_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted and item_id != BikeLantern.ITEM_ID:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	var data := Defs.item(item_id)
	if data.is_empty() or player.inventory.count(item_id) < 1:
		return {"ok": false, "reason": "not_carried"}
	match data["kind"]:
		"resource":
			# Existing fish remain tradeable/craftable resources, but can be
			# eaten raw when desperate. Never accept arbitrary resources as food.
			var raw_tier: int = FoodSafety.raw_fish_tier(item_id)
			if raw_tier == 0 or not bool(data.get("unsafe_food", false)):
				return {"ok": false, "reason": "not_usable"}
			if not FoodSafety.can_eat_raw(player.survival.hunger):
				return {"ok": false, "reason": "not_hungry"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.survival.eat(FoodSafety.raw_hunger(raw_tier))
			player.survival.add_food_poisoning(FoodSafety.raw_poison(raw_tier))
			player.dirty_inventory = true
			player.dirty_character = true
			events.append({"type": "food_poisoning", "peer": peer_id,
				"severity": player.survival.food_poisoning})
			return {"ok": true, "ate_raw_fish": true,
				"severity": player.survival.food_poisoning}
		"water_pouch":
			if item_id != "empty_water_pouch":
				return {"ok": false, "reason": "not_usable"}
			if player.lake_drink_cooldown > 0.0:
				return {"ok": false, "reason": "cooldown",
					"remaining": player.lake_drink_cooldown}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					player.skill_timer > 0.0 or not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat"}
			if not FieldWater.can_access_lake(world, player.position):
				return {"ok": false, "reason": "no_water"}
			# A validated and rolled-back item swap works even with a packed bag.
			var saved_slots: Dictionary = player.inventory.to_dict()
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			if player.inventory.free_space_for("murky_water") < 1:
				player.inventory.load_dict(saved_slots)
				return {"ok": false, "reason": "no_space"}
			if player.inventory.add("murky_water", 1) != 0:
				player.inventory.load_dict(saved_slots)
				return {"ok": false, "reason": "no_space"}
			player.lake_drink_cooldown = FieldWater.COOLDOWN_SECONDS
			player.dirty_inventory = true
			player.dirty_character = true
			return {"ok": true, "item": "murky_water", "count": 1,
				"cooldown": player.lake_drink_cooldown}
		"survey_signal":
			if item_id != SurveySignal.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "survey_signal": true}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					player.skill_timer > 0.0 or not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat", "survey_signal": true}
			var discovered: Dictionary = SurveySignal.candidate(
				player, parties, depleted, time)
			if not bool(discovered.get("ok", false)):
				return {"ok": false, "reason": str(discovered.get("reason", "invalid_survey")),
					"survey_signal": true}
			# Charge only a valid group broadcast. Failed party validation does
			# not spend the crafted kit or create a free shared map marker.
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "survey_signal": true}
			var broadcast: Dictionary = SurveySignal.broadcast(
				parties, player.id, discovered, time)
			if not bool(broadcast.get("ok", false)):
				player.inventory.add(item_id, 1)
				return {"ok": false, "reason": str(broadcast.get("reason", "invalid_party")),
					"survey_signal": true}
			player.dirty_inventory = true
			player.dirty_character = true
			return {"ok": true, "survey_signal": true,
				"tier": int(broadcast["tier"]), "material": str(broadcast["material"]),
				"seconds": float(broadcast["seconds"])}
		"bike_light":
			if item_id != BikeLantern.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var lamp_reason: String = BikeLantern.toggle_reason(
				player.inventory, time, player.bike_lamp_last_toggle)
			if lamp_reason != "":
				return {"ok": false, "reason": lamp_reason, "bike_lamp": true}
			player.bike_lamp_enabled = not player.bike_lamp_enabled
			player.bike_lamp_last_toggle = time
			# Session preference has no inventory cost or new persistence field.
			return {"ok": true, "bike_lamp": true,
				"bike_lamp_enabled": player.bike_lamp_enabled,
				"bike_lamp_lit": BikeLantern.lit(player.inventory, player.mounted,
					_alive(player), WorldCycle.is_night(time), player.bike_lamp_enabled)}
		"mining_wedges":
			if item_id != MiningWedges.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "mining_wedges": true}
			var wedge_reason: String = MiningWedges.use_reason(
				player.inventory, player.wedge_charges)
			if not wedge_reason.is_empty():
				return {"ok": false, "reason": wedge_reason, "mining_wedges": true}
			if player.attack_timer > 0.0 or player.skill_timer > 0.0 or (
					player.combat_tag_until > time or not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat", "mining_wedges": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "mining_wedges": true}
			player.wedge_charges = MiningWedges.CHARGES
			player.dirty_inventory = true
			player.dirty_character = true
			return {"ok": true, "mining_wedges": true,
				"charges": player.wedge_charges}
		"fire_briquette":
			if item_id != StormproofBriquette.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					player.skill_timer > 0.0) or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			var site: Dictionary = StormproofBriquette.nearest(campfires, player.position, time)
			if not bool(site.get("ok", false)):
				return site
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			var camp_id: int = int(site["id"])
			var fire: Dictionary = campfires[camp_id]
			fire["expires"] = minf(time + FieldCampfire.MAX_REMAINING_SECONDS,
				float(fire["expires"]) + StormproofBriquette.FUEL_SECONDS)
			fire["stormproof_until"] = time + StormproofBriquette.SHIELD_SECONDS
			campfires[camp_id] = fire
			player.dirty_inventory = true
			player.dirty_character = true
			events.append({"type": "campfire_stormproofed", "id": camp_id,
				"x": fire["x"], "z": fire["z"]})
			return {"ok": true, "id": camp_id,
				"remaining": float(fire["expires"]) - time,
				"stormproof_seconds": StormproofBriquette.SHIELD_SECONDS}
		"tarp_anchor":
			if item_id != StormTarpAnchors.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "tarp_anchor": true}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					player.skill_timer > 0.0 or not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat", "tarp_anchor": true}
			var selected: Dictionary = StormTarpAnchors.nearest(shelters, player, time)
			if not bool(selected.get("ok", false)):
				selected["tarp_anchor"] = true
				return selected
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "tarp_anchor": true}
			var anchor_id: int = int(selected["id"])
			var strengthened: Dictionary = shelters[anchor_id]
			# Compute expiration BEFORE marking the one-shot upgrade consumed.
			strengthened["expires"] = StormTarpAnchors.new_expiry(strengthened, time)
			strengthened["anchored"] = true
			shelters[anchor_id] = strengthened
			player.dirty_inventory = true
			player.dirty_character = true
			events.append({"type": "tarp_anchored", "id": anchor_id,
				"x": float(strengthened["x"]), "z": float(strengthened["z"])})
			return {"ok": true, "tarp_anchor": true,
				"anchored": true, "id": anchor_id,
				"remaining": float(strengthened["expires"]) - time}
		"prospecting_chart":
			if item_id != ProspectingChart.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "prospecting": true}
			if not player.position.is_finite():
				return {"ok": false, "reason": "invalid_position", "prospecting": true}
			if _is_safe(player.position):
				return {"ok": false, "reason": "safe_zone", "prospecting": true}
			if ProspectingChart.active(player.prospect_mark, time, depleted):
				return {"ok": false, "reason": "already_marked", "prospecting": true}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat", "prospecting": true}
			var vein: Dictionary = ProspectingChart.nearest(world, player.position, depleted)
			if vein.is_empty():
				return {"ok": false, "reason": "no_rich_vein", "prospecting": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "prospecting": true}
			player.prospect_mark = {"id": int(vein["id"]), "kind": str(vein["kind"]),
				"tier": int(vein["tier"]), "x": float(vein["x"]),
				"z": float(vein["z"]), "until": time + ProspectingChart.MARK_SECONDS}
		"threat_scanner":
			if item_id != ThreatScan.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not player.position.is_finite():
				return {"ok": false, "reason": "invalid_position", "threat_scan": true}
			if _is_safe(player.position):
				return {"ok": false, "reason": "safe_zone", "threat_scan": true}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat", "threat_scan": true}
			# No requested target/position is accepted from the remote client.
			var target: Dictionary = ThreatScan.nearest(player.position, zombies)
			if target.is_empty():
				return {"ok": false, "reason": "no_threat_nearby",
					"threat_scan": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "threat_scan": true}
			var scan_members: Array = parties.members_of(peer_id)
			scan_members.sort()
			var scan_group: int = parties.group_of(peer_id) if scan_members.size() >= 2 else 0
			player.threat_scan = {"target": int(target["target"]),
				"expires": time + ThreatScan.MARK_SECONDS,
				"group": scan_group,
				"members": scan_members if scan_group > 0 else []}
		"weapon_coating":
			if item_id != AntisepticEdge.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var oil_reason: String = AntisepticEdge.use_reason(
				player.inventory, player.edge_coating_seconds)
			if oil_reason != "":
				return {"ok": false, "reason": oil_reason}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.edge_coating_weapon = player.inventory.weapon
			player.edge_coating_seconds = AntisepticEdge.SECONDS
			player.action = {}
		"siege_brace":
			if item_id != SiegeBlastBrace.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "siege_brace": true}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or 					player.skill_timer > 0.0 or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat", "siege_brace": true}
			var preparation: Dictionary = SiegeBlastBrace.nearest(world, player,
				barricades, siege_braces, siege_charges, time)
			if not bool(preparation.get("ok", false)):
				preparation["siege_brace"] = true
				return preparation
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "siege_brace": true}
			var wall_id: int = int(preparation["wall"])
			siege_braces[wall_id] = time + SiegeBlastBrace.DURATION
			player.dirty_inventory = true
			player.dirty_character = true
			world_structure_revision += 1
			events.append({"type": "siege_brace_placed",
				"x": float(preparation["x"]), "z": float(preparation["z"])})
			return {"ok": true, "siege_brace": true, "wall": wall_id,
				"seconds": SiegeBlastBrace.DURATION}
		"siege_defusal":
			if item_id != SiegeDefusal.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "defusal": true}
			if not player.action.is_empty():
				return {"ok": false, "reason": "busy", "defusal": true}
			var choice: Dictionary = SiegeDefusal.nearest(world, player,
				siege_charges, barricades, time)
			if not bool(choice.get("ok", false)):
				choice["defusal"] = true
				return choice
			# Verify everything before consuming the actual crafted tool.
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "defusal": true}
			siege_charges.erase(int(choice["id"]))
			player.dirty_inventory = true
			player.dirty_character = true
			events.append({"type": "siege_charge_disarmed",
				"id": int(choice["id"]), "x": float(choice["x"]),
				"z": float(choice["z"])})
			return {"ok": true, "defusal": true,
				"id": int(choice["id"]), "wall": int(choice["wall"])}
		"siege_charge":
			if item_id != SiegeCharge.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var selection: Dictionary = SiegeCharge.nearest_wall(world, player, barricades)
			if not bool(selection.get("ok", false)):
				return selection
			var selected_wall: int = int(selection["wall"])
			var limit: String = SiegeCharge.placement_reason(siege_charges, selected_wall, player)
			if limit != "":
				return {"ok": false, "reason": limit}
			# Commit only after all distance, ownership, zone and limit checks.
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			var charge_id: int = new_id()
			siege_charges[charge_id] = {
				"id": charge_id, "wall": selected_wall,
				"x": float(selection["x"]), "z": float(selection["z"]),
				"owner": SiegeCharge.owner_token(player),
				"until": time + SiegeCharge.FUSE_SECONDS}
			player.action = {}
			player.dirty_inventory = true
			player.dirty_character = true
			events.append({"type": "siege_charge_armed", "id": charge_id,
				"x": float(selection["x"]), "z": float(selection["z"]),
				"seconds": SiegeCharge.FUSE_SECONDS})
			return {"ok": true, "id": charge_id, "wall": selected_wall,
				"seconds": SiegeCharge.FUSE_SECONDS}
		"hand_flare":
			if item_id != HandFlare.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var problem: String = HandFlare.ignite_reason(
				player.flare_seconds, time, player.position, _is_safe(player.position))
			if problem != "":
				return {"ok": false, "reason": problem}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.flare_seconds = HandFlare.BURN_SECONDS
		"smoke_charge":
			if item_id != FieldSmoke.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not player.position.is_finite():
				return {"ok": false, "reason": "invalid_position"}
			if _is_safe(player.position):
				return {"ok": false, "reason": "safe_zone"}
			if player.smoke_cooldown > 0.0:
				return {"ok": false, "reason": "cooldown", "remaining": player.smoke_cooldown}
			if smoke_clouds.size() >= FieldSmoke.MAX_GLOBAL:
				return {"ok": false, "reason": "world_limit"}
			for cloud in smoke_clouds.values():
				if float(cloud["expires"]) > time and int(cloud["owner"]) == peer_id:
					return {"ok": false, "reason": "owner_limit"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			var cloud_id := new_id()
			smoke_clouds[cloud_id] = {"id": cloud_id,
				"x": player.position.x, "y": player.position.y, "z": player.position.z,
				"expires": time + FieldSmoke.DURATION, "owner": peer_id}
			player.smoke_cooldown = FieldSmoke.COOLDOWN
			player.noise_radius = maxf(player.noise_radius, FieldSmoke.USE_NOISE_RADIUS)
			player.noise_timer = maxf(player.noise_timer, FieldSmoke.USE_NOISE_SECONDS)
			player.action = {}
		"recall":
			if item_id != HubRecall.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if training_matches.has(peer_id) or arena_queue.has(peer_id):
				return {"ok": false, "reason": "in_duel"}
			var reason: String = HubRecall.start_reason(world, player, zombies, time)
			if reason != "":
				return {"ok": false, "reason": reason}
			player.recall = {"origin": player.position, "until": time + HubRecall.CHANNEL_SECONDS,
				"health": player.survival.health}
			events.append({"type": "recall_started", "peer": peer_id})
			return {"ok": true, "recall_cast": HubRecall.CHANNEL_SECONDS}
		"acid_neutralizer":
			if item_id != AcidNeutralizer.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not player.position.is_finite() or _is_safe(player.position):
				return {"ok": false, "reason": "safe_zone"}
			# Never accept target IDs, positions or counts from a client.
			var ids: Array[int] = AcidNeutralizer.targets(
				acid_pools, player.position, time)
			if ids.is_empty():
				return {"ok": false, "reason": "no_acid_nearby"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			for acid_id in ids:
				acid_pools.erase(acid_id)
			player.dirty_inventory = true
			player.dirty_character = true
			return {"ok": true, "neutralized": ids.size()}
		"stimulant":
			if item_id != FrontierStim.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var reason: String = FrontierStim.ready(player.survival,
				player.combat_energy, player.stim_cooldown)
			if reason != "":
				return {"ok": false, "reason": reason,
					"remaining": player.stim_cooldown}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.combat_energy = FrontierStim.apply(player.survival, player.combat_energy)
			player.stim_cooldown = FrontierStim.COOLDOWN
		"tire_grips":
			if item_id != BikeGrip.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var grip_reason: String = BikeGrip.apply_reason(
				player.inventory, player.tire_grip_seconds)
			if grip_reason != "":
				return {"ok": false, "reason": grip_reason, "tire_grips": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "tire_grips": true}
			player.tire_grip_seconds = BikeGrip.DURATION_SECONDS
		"bike_frame_repair":
			if item_id != BikeIntegrity.KIT_ID:
				return {"ok": false, "reason": "not_usable"}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			var frame_reason: String = BikeIntegrity.repair_reason(player.inventory, player.bike_integrity)
			if frame_reason != "":
				return {"ok": false, "reason": frame_reason}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.bike_integrity = BikeIntegrity.after_repair(player.bike_integrity)
		"armor_plate":
			if item_id != FieldArmorPlate.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var current_armor: String = FieldArmorPlate.armor_equipped(player.inventory)
			if current_armor.is_empty():
				return {"ok": false, "reason": "need_armor"}
			if player.attack_timer > 0.0 or player.skill_timer > 0.0 or (
					player.combat_tag_until > time) or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			if player.plated_hits > 0 and player.plated_armor == current_armor:
				return {"ok": false, "reason": "already_plated"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.plated_armor = current_armor
			player.plated_hits = FieldArmorPlate.HITS
		"sighting_kit":
			if item_id != FieldSightingKit.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var prepared_ranged: String = FieldSightingKit.ranged_weapon(player.inventory)
			if prepared_ranged.is_empty():
				return {"ok": false, "reason": "need_ranged"}
			if player.attack_timer > 0.0 or player.skill_timer > 0.0 or (
					player.combat_tag_until > time) or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			if player.sighted_hits > 0 and player.sighted_weapon == prepared_ranged:
				return {"ok": false, "reason": "already_sighted"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.sighted_weapon = prepared_ranged
			player.sighted_hits = FieldSightingKit.HITS
		"whetstone":
			if item_id != FieldWhetstone.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var prepared_weapon: String = FieldWhetstone.melee_weapon(player.inventory)
			if prepared_weapon.is_empty():
				return {"ok": false, "reason": "need_melee"}
			if player.attack_timer > 0.0 or player.skill_timer > 0.0 or (
					player.combat_tag_until > time) or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			if player.sharpened_hits > 0 and player.sharpened_weapon == prepared_weapon:
				return {"ok": false, "reason": "already_sharpened"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.sharpened_weapon = prepared_weapon
			player.sharpened_hits = FieldWhetstone.HITS
		"bike_service":
			if item_id != BikeService.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			var service_reason: String = BikeService.repair_reason(player.inventory, player.bike_service_meters)
			if service_reason != "":
				return {"ok": false, "reason": service_reason}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.bike_service_meters = BikeService.MAX_METERS
		"bike_wrap":
			if item_id != BikeChain.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var wrap_reason: String = BikeChain.apply_reason(
				player.inventory, player.chain_wrap_seconds)
			if wrap_reason != "":
				return {"ok": false, "reason": wrap_reason, "chain_wrap": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "chain_wrap": true}
			player.chain_wrap_seconds = BikeChain.DURATION_SECONDS
		"storm_insulator":
			if item_id != StormInsulator.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			var insulation_reason: String = StormInsulator.apply_reason(
				player.storm_insulator_seconds)
			if insulation_reason != "":
				return {"ok": false, "reason": insulation_reason, "storm_insulator": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "storm_insulator": true}
			player.storm_insulator_seconds = StormInsulator.DURATION_SECONDS
		"spore_filter":
			if item_id != SporeHazard.FILTER_ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not SaveValidation.finite_number(player.spore_filter_seconds,
					0.0, SporeHazard.FILTER_DURATION_SECONDS):
				return {"ok": false, "reason": "invalid_state"}
			if player.spore_filter_seconds > 0.0:
				return {"ok": false, "reason": "already_filtered",
					"remaining": player.spore_filter_seconds}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.spore_filter_seconds = SporeHazard.FILTER_DURATION_SECONDS
		"wound_seal":
			if item_id != WoundSealant.ITEM_ID:
				return {"ok": false, "reason": "not_usable", "wound_seal": true}
			if not SaveValidation.finite_number(player.wound_seal_seconds,
					0.0, WoundSealant.DURATION_SECONDS):
				return {"ok": false, "reason": "invalid_state", "wound_seal": true}
			if player.wound_seal_seconds > 0.0:
				return {"ok": false, "reason": "already_sealed",
					"wound_seal": true, "remaining": player.wound_seal_seconds}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					player.skill_timer > 0.0 or not player.action.is_empty()):
				return {"ok": false, "reason": "in_combat", "wound_seal": true}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried", "wound_seal": true}
			player.wound_seal_seconds = WoundSealant.DURATION_SECONDS
		"footstep_wrap":
			if item_id != SoftSoleWraps.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not SoftSoleWraps.valid_remaining(player.soft_sole_seconds):
				return {"ok": false, "reason": "invalid_state"}
			if player.soft_sole_seconds > 0.0:
				return {"ok": false, "reason": "already_wrapped"}
			if player.combat_tag_until > time or player.attack_timer > 0.0 or (
					player.skill_timer > 0.0) or not player.action.is_empty():
				return {"ok": false, "reason": "in_combat"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			player.soft_sole_seconds = SoftSoleWraps.DURATION_SECONDS
		"scent_mask":
			if item_id != FieldScentMask.ITEM_ID:
				return {"ok": false, "reason": "not_usable"}
			if not FieldScentMask.can_apply(player.survival):
				return {"ok": false, "reason": "already_masked"}
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			FieldScentMask.apply(player.survival)
		"thermal":
			if not player.survival.apply_thermal_wrap():
				return {"ok": false, "reason": "already_warm"}
			player.inventory.remove(item_id, 1)
		"food":
			var was_hungry: bool = player.survival.hunger <= SKILL_NOURISH_THRESHOLD
			var hydration: float = float(data.get("drink", 0.0))
			var was_thirsty: bool = hydration > 0.0 and player.survival.thirst <= SKILL_NOURISH_THRESHOLD
			if not player.inventory.remove(item_id, 1):
				return {"ok": false, "reason": "not_carried"}
			var food_power: float = 1.0 + player.skills.bonus("food_power")
			player.survival.eat(float(data["food"]) * food_power)
			# Dual-purpose stew consumes one real item and replenishes both vitals.
			# Ordinary food has no drink value, so its previous behavior is unchanged.
			if hydration > 0.0:
				player.survival.drink(hydration * food_power)
			# Prepared fish or stew refreshes the same non-stacking recovery buff.
			var cooked_tier: int = HeartyMeal.tier_for_food(item_id)
			if cooked_tier > 0:
				player.meal_tier = cooked_tier
				player.meal_seconds = HeartyMeal.duration(cooked_tier)
			# Smoked fish only reduces hunger decay, not combat or wound damage.
			var travel_tier: int = TrailRation.tier_for_food(item_id)
			if travel_tier > 0 and (player.ration_seconds <= 0.0 or
					travel_tier >= player.ration_tier):
				player.ration_tier = travel_tier
				player.ration_seconds = TrailRation.duration(travel_tier)
			# One legitimate survival lesson per consumed item, not two for stew.
			if was_hungry or was_thirsty:
				_award(player, "survivalist", 3.0)
		"drink":
			var was_thirsty: bool = player.survival.thirst <= SKILL_NOURISH_THRESHOLD
			player.inventory.remove(item_id, 1)
			player.survival.drink(float(data["drink"]) * (1.0 + player.skills.bonus("food_power")))
			if was_thirsty:
				_award(player, "survivalist", 3.0)
		"medical":
			var healing: float = float(data.get("heal", 0.0))
			var curing: float = float(data.get("cure", 0.0))
			var staunch: bool = bool(data.get("stop_bleeding", false))
			var splint: float = float(data.get("fracture_treatment", 0.0))
			var stomach: float = float(data.get("food_poison_treatment", 0.0))
			if (healing <= 0.0 or player.survival.health >= player.survival.max_health) and (
					curing <= 0.0 or player.survival.infection <= 0.0) and (
					not staunch or player.survival.bleeding <= 0.0) and (
					splint <= 0.0 or player.survival.fracture <= 0.0) and (
					stomach <= 0.0 or player.survival.food_poisoning <= 0.0):
				return {"ok": false, "reason": "no_effect"}
			player.inventory.remove(item_id, 1)
			player.survival.heal(healing * (1.0 + player.skills.bonus("heal_power")))
			player.survival.treat_infection(curing)
			if staunch:
				player.survival.stop_bleeding()
			player.survival.treat_fracture(splint)
			player.survival.treat_food_poisoning(stomach)
			_award(player, "medic", 6.0)
		"head", "cape", "hands", "feet":
			player.inventory.equip(item_id) # Worn pieces: a hood, a cloak, gloves, boots.
		"weapon", "armor":
			var previous_weapon: String = player.inventory.weapon
			var previous_armor: String = player.inventory.armor
			player.inventory.equip(item_id)
			if previous_armor != player.inventory.armor:
				player.plated_armor = ""
				player.plated_hits = 0
			if previous_weapon != player.inventory.weapon:
				player.edge_coating_seconds = 0.0
				player.edge_coating_weapon = ""
				player.sharpened_weapon = ""
				player.sharpened_hits = 0
				player.sighted_weapon = ""
				player.sighted_hits = 0
		_:
			return {"ok": false, "reason": "not_usable"}
	player.dirty_inventory = true
	player.dirty_character = true
	if TrailRation.tier_for_food(item_id) > 0:
		return {"ok": true, "trail_ration": true,
			"tier": player.ration_tier, "seconds": player.ration_seconds}
	if item_id == FoodSafety.REMEDY_ITEM:
		return {"ok": true, "stomach_remedy": true,
			"remaining": player.survival.food_poisoning}
	if item_id == ProspectingChart.ITEM_ID:
		var detected: Dictionary = ProspectingChart.public_mark(
			player.prospect_mark, time, depleted)
		return {"ok": true, "prospecting": true,
			"kind": str(detected.get("kind", "rock")),
			"tier": int(detected.get("tier", 2)),
			"x": float(detected.get("x", 0.0)),
			"z": float(detected.get("z", 0.0)),
			"seconds": ProspectingChart.MARK_SECONDS}
	if item_id == ThreatScan.ITEM_ID:
		var found: Dictionary = ThreatScan.public_mark(
			player.threat_scan, zombies, player.position, time)
		return {"ok": true, "threat_scan": true,
			"party_shared": int(player.threat_scan.get("group", 0)) > 0,
			"kind": found.get("kind", "elite"),
			"x": float(found.get("x", 0.0)), "z": float(found.get("z", 0.0)),
			"seconds": ThreatScan.MARK_SECONDS}
	if item_id == FieldWhetstone.ITEM_ID:
		return {"ok": true, "weapon": player.sharpened_weapon,
			"hits": player.sharpened_hits}
	if item_id == FieldSightingKit.ITEM_ID:
		return {"ok": true, "weapon": player.sighted_weapon,
			"hits": player.sighted_hits}
	if item_id == FieldArmorPlate.ITEM_ID:
		return {"ok": true, "armor": player.plated_armor,
			"hits": player.plated_hits}
	if item_id == BikeGrip.ITEM_ID:
		return {"ok": true, "tire_grip_seconds": player.tire_grip_seconds}
	if item_id == BikeChain.ITEM_ID:
		return {"ok": true, "chain_wrap_seconds": player.chain_wrap_seconds}
	if item_id == BikeService.ITEM_ID:
		return {"ok": true, "bike_service_meters": player.bike_service_meters}
	if item_id == StormInsulator.ITEM_ID:
		return {"ok": true, "storm_insulator_seconds": player.storm_insulator_seconds}
	if item_id == WoundSealant.ITEM_ID:
		return {"ok": true, "wound_seal": true,
			"wound_seal_seconds": player.wound_seal_seconds}
	if item_id == BikeIntegrity.KIT_ID:
		return {"ok": true, "bike_integrity": player.bike_integrity}
	if item_id == HandFlare.ITEM_ID:
		return {"ok": true, "flare_seconds": player.flare_seconds}
	if item_id == AntisepticEdge.ITEM_ID:
		return {"ok": true, "coating_seconds": player.edge_coating_seconds,
			"coating_weapon": player.edge_coating_weapon}
	if item_id == FieldSmoke.ITEM_ID:
		return {"ok": true, "smoke_seconds": FieldSmoke.DURATION,
			"cooldown": player.smoke_cooldown}
	return {"ok": true}


## A dangerous-swamp research loop; world, kit, protective suit, filtration,
## infection exposure and output are exclusively server-owned.
func cmd_sample_spores(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.recall.is_empty():
		return {"ok": false, "reason": "recall_channeling"}
	if player.spore_sample_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.spore_sample_cooldown}
	var site: String = SporeSampling.site_reason(world, player.position)
	if site != "":
		return {"ok": false, "reason": site}
	var outcome: Dictionary = SporeSampling.transact(player.inventory)
	if not bool(outcome.get("ok", false)):
		return outcome
	var armor: String = player.inventory.armor
	if armor != "" and player.inventory.count(armor) < 1:
		armor = ""
	var hazard: Dictionary = SporeHazard.status(world, player.position,
		time, armor, player.spore_filter_seconds)
	var infection: float = SporeSampling.infection_cost(
		float(hazard.get("protection", 0.0)))
	player.survival.add_infection(infection)
	player.spore_sample_cooldown = SporeSampling.COOLDOWN_SECONDS
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "spore_sampled", "peer": peer_id,
		"count": SporeSampling.CULTURES_PER_KIT, "infection": infection})
	return {"ok": true, "count": SporeSampling.CULTURES_PER_KIT,
		"infection": infection, "cooldown": player.spore_sample_cooldown}


## Convert a crafted tarp into clean bottled stormwater. The server decides
## climate, terrain, swamp contamination, costs and output, never the client.
func cmd_collect_rain(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.rain_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown",
			"remaining": player.rain_cooldown}
	var reason: String = RainHarvest.site_reason(world, player.position, time)
	if reason != "":
		return {"ok": false, "reason": reason}
	var needs_filter: bool = RainHarvest.needs_filter(world, player.position)
	var result: Dictionary = RainHarvest.transact(player.inventory, needs_filter)
	if not bool(result.get("ok", false)):
		return result
	player.rain_cooldown = RainHarvest.COOLDOWN_SECONDS
	player.dirty_inventory = true
	player.dirty_character = true
	events.append({"type": "rain_collected", "peer": player.id,
		"count": RainHarvest.WATER_COUNT, "filtered": needs_filter})
	return {"ok": true, "count": RainHarvest.WATER_COUNT,
		"filtered": needs_filter, "cooldown": player.rain_cooldown}


## Lake water hydrates but can infect: clean bottles remain a risk-free alternative.
## Filtration is item-paid, never a free client flag or cure.
## Bottle clean water at an actual shore with either a charcoal filter or
## two wood beside a LIVE campfire. Shared persisted cooldown prevents
## alternating methods and reconnect bypass. The client chooses only method.
func cmd_refill_canteen(peer_id: int, boil: bool = false) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.lake_drink_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.lake_drink_cooldown}
	if not FieldWater.can_access_lake(world, player.position):
		return {"ok": false, "reason": "no_water"}
	if boil and not FieldCanteen.can_boil(campfires, player.position, time):
		return {"ok": false, "reason": "no_fire"}
	var result: String = (FieldCanteen.boil(player.inventory) if boil
		else FieldCanteen.fill(player.inventory))
	if result != "":
		return {"ok": false, "reason": result}
	player.lake_drink_cooldown = FieldWater.COOLDOWN_SECONDS
	player.dirty_inventory = true
	player.dirty_character = true
	return {"ok": true, "item": FieldCanteen.OUTPUT_ITEM, "count": 1,
		"boiled": boil, "cooldown": player.lake_drink_cooldown}


func cmd_drink_water(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.lake_drink_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.lake_drink_cooldown}
	if not FieldWater.needs_drink(player.survival):
		return {"ok": false, "reason": "not_thirsty"}
	if not FieldWater.can_access_lake(world, player.position):
		return {"ok": false, "reason": "no_water"}
	var filtered: bool = player.inventory.count(FieldWater.FILTER_ITEM) > 0
	if filtered:
		if not player.inventory.remove(FieldWater.FILTER_ITEM, 1):
			return {"ok": false, "reason": "filter_unavailable"}
		player.dirty_inventory = true
	_award(player, "survivalist", 2.0) # needs_drink() above guarantees the player really was thirsty.
	player.survival.drink(FieldWater.THIRST_RESTORED * (1.0 + player.skills.bonus("food_power")))
	if not filtered:
		player.survival.add_infection(FieldWater.UNTREATED_INFECTION)
	player.lake_drink_cooldown = FieldWater.COOLDOWN_SECONDS
	player.dirty_character = true
	return {"ok": true, "filtered": filtered, "infection": player.survival.infection,
		"cooldown": player.lake_drink_cooldown}


## Attack in the direction the player is facing. Melee hits the closest enemy in range; a pistol
## shoots a ray that hits the first enemy along it.
func cmd_attack(peer_id: int, dir_x: float, dir_z: float, charge: float = 0.0) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player != null and player.knocked_seconds > 0.0:
		return {"ok": false, "reason": "knocked_down"}
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if player.attack_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	direction = direction.normalized()
	var weapon: String = player.inventory.weapon
	# Dropped/stolen gear must not keep its statistics through a stale slot.
	if weapon != "" and player.inventory.count(weapon) < 1:
		weapon = ""
	var kind: String = Defs.item(weapon).get("weapon", "melee") if weapon != "" else "melee"
	# Melee swings cost stamina; holding the attack charges a power blow. Ranged ignores both.
	charge = clampf(charge, 0.0, 1.0) if is_finite(charge) and kind != "ranged" else 0.0
	var raging: bool = player.rage_seconds > 0.0
	var exhausted := false
	if kind != "ranged" and not raging:
		var cost: float = Brawl.swing_cost(charge)
		if player.survival.stamina >= cost:
			player.survival.stamina -= cost
		else:
			exhausted = true
			charge = 0.0
			player.survival.stamina = 0.0
		player.survival.stamina_recovery_delay = Defs.STAMINA_RECOVERY_DELAY
	player.attack_timer = Combat.weapon_cooldown(weapon) * (
		Brawl.cooldown_factor(charge, exhausted, raging) if kind != "ranged" else 1.0)
	player.action = {} # Fighting interrupts gathering.
	player.yaw = atan2(direction.x, direction.y)
	var origin := Vector2(player.position.x, player.position.z)
	var damage: float = Combat.weapon_damage(weapon)
	# Mastery is server-owned. Missing/ghost equipment grants no bonus.
	if weapon != "" and player.inventory.count(weapon) > 0:
		damage *= player.progression.combat_damage_multiplier(weapon)
		# Broken (0%) weapons strike at half strength; every swing wears the weapon.
		damage *= player.inventory.effectiveness(weapon)
		player.inventory.damage_item(weapon, GearDurability.WEAPON_WEAR_PER_HIT)
	var reach: float = Combat.weapon_reach(weapon)
	if kind == "ranged":
		var ammo: String = Defs.item(weapon).get("ammo", "")
		if player.inventory.count(ammo) < 1:
			player.attack_timer = 0.3
			return {"ok": false, "reason": "no_ammo"}
		if rng.randf() >= player.skills.bonus("ammo_save"):
			player.inventory.remove(ammo, 1)
		player.dirty_inventory = true
		# Arrows are much quieter than firearms, but still attract nearby infected.
		var shot_noise: Dictionary = Combat.ranged_noise(weapon)
		player.noise_radius = maxf(player.noise_radius, float(shot_noise["radius"]))
		player.noise_timer = maxf(player.noise_timer, float(shot_noise["seconds"]))
		reach = Combat.ranged_range(weapon)
	var is_ranged := kind == "ranged"
	damage *= 1.0 + player.skills.bonus("ranged_damage" if is_ranged else "melee_damage")
	if not is_ranged:
		damage *= Brawl.damage_factor(charge, exhausted, raging)
	var crit: bool = not is_ranged and rng.randf() < float(player.skills.bonus("crit_chance"))
	if crit:
		damage *= 1.5 + player.skills.bonus("crit_damage")
	var hit := _find_hit(player, origin, direction, reach, kind == "ranged")
	# An earned counterattack belongs to ONE infected, never another survivor.
	# The first normal melee swing consumes it even if it misses or hits PvP.
	var guard_counterstrike: bool = false
	if not is_ranged and player.guard_counter_seconds > 0.0:
		var guarded_target = zombies.get(int(hit["id"])) if not hit.is_empty() and \
				str(hit["kind"]) == "zombie" else null
		guard_counterstrike = GuardianRetribution.consume(
			player, guarded_target, parties, world)
	# The FIRST legal attack spends a server-earned counter, including misses.
	var riposte: bool = false
	if player.riposte_seconds > 0.0:
		if not is_ranged and not hit.is_empty() and str(hit["kind"]) == "zombie":
			riposte = ParryRiposte.can_strike(player,
				zombies.get(int(hit["id"])), weapon)
		ParryRiposte.clear(player)
	events.append({"type": "attack", "peer": peer_id, "dir": direction, "ranged": kind == "ranged", "x": player.position.x, "z": player.position.z, "charge": charge})
	if hit.is_empty():
		var cover_hit: bool = is_ranged and _damage_ranged_cover(player,
			origin, direction, reach, damage)
		return {"ok": true, "hit": false, "cover_hit": cover_hit}
	# Only server-confirmed ordinary melee PvE attacks may ambush.
	var ambush: bool = false
	if not is_ranged and str(hit["kind"]) == "zombie":
		var factor: float = StealthAmbush.multiplier(
			player, zombies.get(int(hit["id"])), weapon)
		if factor > 1.0:
			ambush = true
			# Avoid combining the opener with a random critical hit.
			if crit:
				damage /= 1.5 + player.skills.bonus("crit_damage")
				crit = false
			damage *= factor
			events.append({"type": "stealth_ambush", "peer": peer_id,
				"zombie": int(hit["id"]), "multiplier": factor})
	# Prevent multiplying reactive damage with random crits or stealth openers.
	if riposte and not ambush:
		if crit:
			damage /= 1.5 + player.skills.bonus("crit_damage")
			crit = false
		damage *= ParryRiposte.DAMAGE_FACTOR
	else:
		riposte = false
	# Misses, player targets, ranged attacks and ghost gear cannot apply the bonus.
	var sharpened: bool = not is_ranged and str(hit["kind"]) == "zombie" and (
		FieldWhetstone.bonus_active(player.sharpened_weapon,
			player.sharpened_hits, player.inventory, weapon))
	if sharpened:
		damage *= FieldWhetstone.DAMAGE_FACTOR
		player.sharpened_hits -= 1
		if player.sharpened_hits == 0:
			player.sharpened_weapon = ""
		player.dirty_character = true
	# Apply a paid 12% bonus only after a confirmed infected ranged hit.
	# Ammo exhaustion, misses, cover, PvP and skill attacks do not spend charges.
	var sighted: bool = is_ranged and str(hit["kind"]) == "zombie" and (
		FieldSightingKit.bonus_active(player.sighted_weapon,
			player.sighted_hits, player.inventory, weapon))
	if sighted:
		damage *= FieldSightingKit.DAMAGE_FACTOR
		player.sighted_hits -= 1
		if player.sighted_hits == 0:
			player.sighted_weapon = ""
		player.dirty_character = true
	if guard_counterstrike:
		damage = GuardianRetribution.amplify(damage)
		events.append({"type": "guardian_retribution", "peer": peer_id,
			"zombie": int(hit["id"])})
	# Only this ordinary, server-selected melee collision can earn the
	# cooperative flank; skills, ranged fire and direct damage paths cannot.
	var flanked: bool = not is_ranged and str(hit["kind"]) == "zombie" and \
		PartyFlank.qualifies(player, zombies.get(int(hit["id"])), players, parties, world)
	# Brawling: power blows stagger and floor, a downed enemy takes a ground finisher.
	var downed_hit := false
	if not is_ranged and str(hit["kind"]) == "zombie":
		var struck = zombies.get(int(hit["id"]))
		if struck != null and float(downed_until.get(struck.id, 0.0)) > time:
			downed_hit = true
			damage *= Brawl.GROUND_FINISHER
			downed_until.erase(struck.id)
			events.append({"type": "ground_finisher", "peer": peer_id, "zombie": struck.id})
		elif struck != null and charge >= Brawl.POWER_STAGGER_CHARGE:
			_brawl_impact(player, struck, Brawl.POWER_STAGGER_SECONDS, Brawl.POWER_KNOCKBACK)
	player.rage = Brawl.gain_rage(player.rage, damage * Brawl.RAGE_PER_DAMAGE_DEALT) if not raging else player.rage
	_damage_target(player, hit, damage, "ranged" if is_ranged else "melee", not is_ranged)
	return {"ok": true, "hit": true, "target": hit["kind"], "party_flank": flanked,
		"charge": charge, "exhausted": exhausted, "ground_finisher": downed_hit,
		"crit": crit, "ambush": ambush, "riposte": riposte,
		"sharpened": sharpened, "guardian_retribution": guard_counterstrike}


## Party frontline role: no client-authored targets, aggro, radius or damage.
func cmd_guardian_taunt(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if _is_safe(player.position):
		return {"ok": false, "reason": "safe_zone"}
	var allies: Array = parties.members_of(peer_id)
	if allies.size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	if not GuardianTaunt.melee_equipped(player.inventory):
		return {"ok": false, "reason": "need_melee"}
	if player.guardian_timer > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.guardian_timer}
	if player.combat_energy < GuardianTaunt.ENERGY_COST:
		return {"ok": false, "reason": "no_energy"}
	var targets: Array = []
	for infected in zombies.values():
		if infected.target_id == peer_id or not GuardianTaunt.eligible_enemy(
				infected, player.position, allies, world):
			continue
		var victim: Player = players.get(infected.target_id)
		if victim == null or not _alive(victim) or _is_safe(victim.position):
			continue
		if world.zone_at(victim.position.x, victim.position.z) != world.zone_at(
				player.position.x, player.position.z):
			continue
		targets.append(infected)
	if targets.is_empty():
		return {"ok": false, "reason": "no_engaged_infected"}
	targets.sort_custom(func(a, b): return a.position.distance_squared_to(
		player.position) < b.position.distance_squared_to(player.position))
	var count := mini(GuardianTaunt.MAX_TARGETS, targets.size())
	for index in count:
		targets[index].force_taunt(peer_id, GuardianTaunt.FOCUS_SECONDS)
	player.combat_energy -= GuardianTaunt.ENERGY_COST
	player.guardian_timer = GuardianTaunt.COOLDOWN
	player.guardian_brace = GuardianTaunt.GUARD_SECONDS
	player.action = {}
	events.append({"type": "guardian_taunt", "peer": peer_id,
		"x": player.position.x, "z": player.position.z, "count": count})
	return {"ok": true, "count": count, "cooldown": player.guardian_timer,
		"brace_seconds": player.guardian_brace, "energy": player.combat_energy}


## Short nonstacking party frontline stance. No client-provided coordinates,
## protected targets, damage values, enemy IDs or shared buff durations.
func cmd_party_shield_wall(peer_id: int) -> Dictionary:
	var guardian: Player = players.get(peer_id)
	if guardian == null or not _alive(guardian):
		return {"ok": false, "reason": "dead"}
	if guardian.mounted:
		return {"ok": false, "reason": "mounted"}
	if not guardian.position.is_finite() or _is_safe(guardian.position):
		return {"ok": false, "reason": "safe_zone"}
	if parties.group_of(peer_id) <= 0 or parties.members_of(peer_id).size() < 2:
		return {"ok": false, "reason": "not_in_party"}
	if not GuardianTaunt.melee_equipped(guardian.inventory):
		return {"ok": false, "reason": "need_melee"}
	if guardian.shield_wall_seconds > 0.0:
		return {"ok": false, "reason": "already_active"}
	if guardian.shield_wall_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown",
			"remaining": guardian.shield_wall_cooldown}
	if guardian.combat_energy < PartyShieldWall.ENERGY_COST:
		return {"ok": false, "reason": "no_energy"}
	var nearby_allies: int = 0
	for member_id in parties.members_of(peer_id):
		var member: Player = players.get(int(member_id))
		if PartyShieldWall.can_protect(guardian, member, parties, world):
			nearby_allies += 1
	if nearby_allies == 0:
		return {"ok": false, "reason": "no_nearby_ally"}
	guardian.combat_energy -= PartyShieldWall.ENERGY_COST
	guardian.shield_wall_seconds = PartyShieldWall.DURATION
	guardian.shield_wall_cooldown = PartyShieldWall.COOLDOWN
	guardian.action = {}
	return {"ok": true, "seconds": guardian.shield_wall_seconds,
		"cooldown": guardian.shield_wall_cooldown,
		"allies": nearby_allies, "energy": guardian.combat_energy}


## Protect exactly one verified party ally from their next infected MELEE hit.
## Client supplies an ally ID, never the enemy, damage amount or hit outcome.
func cmd_guardian_intercept(peer_id: int, target_id: int) -> Dictionary:
	var guardian: Player = players.get(peer_id)
	if guardian == null or not _alive(guardian):
		return {"ok": false, "reason": "dead"}
	if target_id == peer_id:
		return {"ok": false, "reason": "self"}
	var ally: Player = players.get(target_id)
	if ally == null or not _alive(ally):
		return {"ok": false, "reason": "invalid_target"}
	if guardian.guard_link_seconds > 0.0:
		return {"ok": false, "reason": "already_guarding"}
	if guardian.guard_link_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown",
			"remaining": guardian.guard_link_cooldown}
	if parties.group_of(peer_id) == 0 or parties.group_of(peer_id) != parties.group_of(target_id):
		return {"ok": false, "reason": "not_in_party"}
	if not GuardianTaunt.melee_equipped(guardian.inventory):
		return {"ok": false, "reason": "need_melee"}
	if not GuardianIntercept.can_guard(guardian, ally, parties, world):
		return {"ok": false, "reason": "too_far_or_unsafe"}
	if guardian.combat_energy < GuardianIntercept.ENERGY_COST:
		return {"ok": false, "reason": "no_energy"}
	guardian.combat_energy -= GuardianIntercept.ENERGY_COST
	guardian.guard_link_target = target_id
	guardian.guard_link_seconds = GuardianIntercept.DURATION
	guardian.guard_link_cooldown = GuardianIntercept.COOLDOWN
	guardian.action = {}
	return {"ok": true, "target": target_id, "seconds": guardian.guard_link_seconds,
		"cooldown": guardian.guard_link_cooldown}


## Called only after an authentic zombie brain emits a MELEE hit.
## One selected guardian takes reduced damage, fully preventing this hit's
## physical wounds for the warded ally. AoE, acid and PvP use other paths.
func _try_guardian_intercept(ally: Player, infected, raw_damage: float) -> bool:
	if ally == null or infected == null or not infected.is_alive() or \
			not is_finite(raw_damage) or raw_damage <= 0.0:
		return false
	var chosen: Player = null
	var best_distance: float = INF
	for guardian in players.values():
		if not GuardianIntercept.can_intercept(guardian, ally, parties, world):
			continue
		var d: float = guardian.position.distance_squared_to(ally.position)
		if d < best_distance - 0.001 or (absf(d - best_distance) <= 0.001 and
				(chosen == null or guardian.id < chosen.id)):
			chosen = guardian
			best_distance = d
	if chosen == null:
		return false
	# Consume before resolving the damage/death callback, so recursive hits
	# and repeated network commands cannot spend the same shield twice.
	chosen.guard_link_target = -1
	chosen.guard_link_seconds = 0.0
	var armor_id: String = chosen.inventory.armor
	var equipped: bool = armor_id != "" and chosen.inventory.count(armor_id) > 0
	var damage: float = Combat.apply_gear(GuardianIntercept.damage(raw_damage), chosen.inventory)
	damage = _infected_damage_for(chosen, damage)
	var taken: float = _hurt_player(chosen, damage)
	chosen.dirty_character = true
	# Only a guardian who survives the real interception can counter.
	# Feed this confirmed result into the private combat notification.
	var counter_ready: bool = _alive(chosen) and GuardianRetribution.arm(
		chosen, infected, parties, world)
	if counter_ready:
		infected.force_taunt(chosen.id, GuardianRetribution.TAUNT_SECONDS)
	events.append({"type": "guardian_intercept", "peer": ally.id,
		"by": chosen.id, "zombie": infected.id, "damage": taken,
		"counter_ready": counter_ready})
	if not _alive(chosen):
		_on_player_death(chosen, -infected.id)
	return true


## Resolve active combat on the server; the client supplies only aim direction.
## Albion-style armor abilities (R chest / D helmet / F boots), granted by the equipped piece.
func cmd_gear_skill(peer_id: int, slot: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if not GearSkills.SLOTS.has(slot):
		return {"ok": false, "reason": "unknown_slot"}
	var item_id: String = GearSkills.equipped_in(player.inventory, slot)
	var skill: Dictionary = GearSkills.skill_for(slot, item_id)
	if skill.is_empty():
		return {"ok": false, "reason": "no_item", "slot": slot}
	if float(player.gear_skill_timers.get(slot, 0.0)) > 0.0:
		return {"ok": false, "reason": "cooldown", "slot": slot, "remaining": float(player.gear_skill_timers[slot])}
	player.gear_skill_timers[slot] = float(skill["cooldown"])
	match str(skill["id"]):
		"iron_skin":
			player.survival.guard_seconds = float(skill["seconds"])
			player.survival.guard_reduction = float(skill["guard"])
		"second_wind":
			player.survival.regen_seconds = float(skill["seconds"])
			player.survival.regen_per_second = float(skill["heal_total"]) / float(skill["seconds"])
		"sprint":
			player.sprint_buff_seconds = float(skill["seconds"])
			player.sprint_buff_speed = float(skill["speed"])
	player.dirty_character = true
	events.append({"type": "gear_skill", "peer": peer_id, "skill": skill["id"],
		"x": player.position.x, "z": player.position.z})
	return {"ok": true, "skill": skill["id"], "slot": slot, "cooldown": skill["cooldown"]}


func cmd_skill(peer_id: int, dir_x: float, dir_z: float, ultimate: bool = false) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	# Q and the weapon ultimate (E) keep separate cooldowns, Albion-style.
	if player.attack_timer > 0.0 or (player.ultimate_timer if ultimate else player.skill_timer) > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var weapon: String = player.inventory.weapon
	var skill: Dictionary = Combat.active_skill(weapon)
	if ultimate:
		skill = GearSkills.ultimate(skill)
		if not skill.is_empty():
			skill["damage"] = float(skill["damage"]) * player.progression.mastery_ultimate_multiplier(weapon)
	if skill.is_empty() or player.inventory.count(weapon) < 1:
		return {"ok": false, "reason": "no_skill"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	var cost: float = float(skill["energy_cost"])
	if player.combat_energy < cost:
		return {"ok": false, "reason": "no_energy"}
	# The staff selects injured verified teammates on the server; the
	# caller cannot submit a target ID, health value, or heal quantity.
	# Rejected pulses cost no energy and never start a cooldown.
	var heal_candidates: Array = []
	if skill.has("party_heal"):
		var group: Array = parties.members_of(peer_id)
		if group.size() < 2:
			return {"ok": false, "reason": "not_in_party"}
		var caster_zone: int = world.zone_at(player.position.x, player.position.z)
		for member_id in group:
			var target_id: int = int(member_id)
			if target_id == peer_id:
				continue # Healing allies is not a free self-heal.
			var ally: Player = players.get(target_id)
			if ally == null or not _alive(ally):
				continue
			if world.zone_at(ally.position.x, ally.position.z) != caster_zone:
				continue
			if not RestorationStaff.can_reach(player.position, ally.position):
				continue
			var urgency: float = RestorationStaff.urgency(
				ally.survival.health, ally.survival.max_health)
			if urgency <= 0.0:
				continue
			heal_candidates.append({"id": target_id, "urgency": urgency, "player": ally})
		if heal_candidates.is_empty():
			return {"ok": false, "reason": "no_wounded_allies"}
		heal_candidates.sort_custom(func(a, b):
			return float(a["urgency"]) > float(b["urgency"]) if float(a["urgency"]) != float(b["urgency"]) else int(a["id"]) < int(b["id"]))
	var ranged: bool = bool(skill.get("ranged", false))
	var ammo: String = str(skill.get("ammo", ""))
	# Validate and consume exactly one physical cartridge before charging energy.
	# A failed shot must not start cooldown, change action, emit noise or cost XP.
	if ranged and (ammo.is_empty() or player.inventory.count(ammo) < 1):
		return {"ok": false, "reason": "no_ammo"}
	if ranged:
		if not player.inventory.remove(ammo, 1):
			return {"ok": false, "reason": "no_ammo"}
		player.dirty_inventory = true
	direction = direction.normalized()
	player.combat_energy -= cost
	if ultimate:
		player.ultimate_timer = float(skill["cooldown"])
	else:
		player.skill_timer = float(skill["cooldown"])
	player.attack_timer = float(skill["attack_lock"])
	player.action = {}
	player.yaw = atan2(direction.x, direction.y)
	if skill.has("party_heal"):
		var treated: int = mini(heal_candidates.size(), RestorationStaff.MAX_TARGETS)
		var total_healed: float = 0.0
		var healing_events: Array = []
		for index in range(treated):
			var recipient: Player = heal_candidates[index]["player"]
			var before_health: float = recipient.survival.health
			recipient.survival.heal(float(skill["party_heal"]))
			var gained: float = recipient.survival.health - before_health
			total_healed += gained
			healing_events.append({"recipient": recipient, "healed": gained})
			recipient.dirty_character = true
		_record_party_healing_threat(player, healing_events)
		player.dirty_character = true
		# Public effect contains no recipient IDs or medical details.
		events.append({"type": "restoration_pulse", "peer": peer_id,
			"count": treated, "x": player.position.x, "z": player.position.z})
		return {"ok": true, "treated": treated, "healed": total_healed,
			"energy": player.combat_energy}
	if ranged:
		var shot_noise: Dictionary = Combat.ranged_noise(weapon)
		player.noise_radius = maxf(player.noise_radius, float(shot_noise["radius"]))
		player.noise_timer = maxf(player.noise_timer, float(shot_noise["seconds"]))
	var origin := Vector2(player.position.x, player.position.z)
	events.append({"type": "attack", "peer": peer_id, "dir": direction, "ranged": ranged, "skill": skill["id"], "x": player.position.x, "z": player.position.z})
	# Piercing thrust follows a thin line; machete cleave sweeps the
	# existing melee cone. Each distinct target goes through the ordinary
	# server-side zombie / party / guild / zone protection checks.
	var max_hits: int = clampi(int(skill.get("cleave_targets",
		skill.get("pierce_targets", 1))), 1, 3)
	var use_line: bool = ranged or (max_hits > 1 and not skill.has("cleave_targets"))
	var ignored: Dictionary = {}
	var count := 0
	var finishers := 0
	var first_target: String = ""
	var skilled_damage: float = float(skill["damage"]) * player.progression.combat_damage_multiplier(weapon) \
		* (1.0 + player.skills.bonus("ranged_damage" if ranged else "melee_damage"))
	for i in max_hits:
		var hit: Dictionary = _find_hit(player, origin, direction, float(skill["range"]), use_line, ignored)
		if hit.is_empty():
			break
		ignored[str(hit["kind"]) + ":" + str(hit["id"])] = true
		if count == 0:
			first_target = str(hit["kind"])
		# Execute bonus is resolved on pre-hit infected health. Do not use
		# client health/target IDs, and never boost damage against survivors.
		var hit_damage: float = skilled_damage
		if hit["kind"] == "zombie" and skill.has("execute_threshold"):
			var marked = zombies.get(hit["id"])
			if marked != null and marked.is_alive():
				var multiplier: float = FinishingStrike.multiplier(
					marked.health, float(marked.data.get("health", 0.0)),
					marked.elite, marked.raid_boss)
				if multiplier > 1.0:
					hit_damage *= multiplier
					finishers += 1
					events.append({"type": "finishing_strike",
						"peer": peer_id, "id": marked.id,
						"x": marked.position.x, "z": marked.position.z})
		_damage_target(player, hit, hit_damage, "ranged" if ranged else "melee")
		# The armor debuff begins AFTER this strike, benefiting subsequent
		# real infected hits without giving the applicator free extra damage.
		# Player PvP hits and enemies killed by the strike are never marked.
		if hit["kind"] == "zombie" and skill.has("sunder_seconds"):
			var sundered = zombies.get(hit["id"])
			if sundered != null and sundered.apply_sunder(time,
					float(skill["sunder_seconds"])):
				events.append({"type": "armor_sunder", "id": sundered.id,
					"x": sundered.position.x, "z": sundered.position.z})
		# PvE-only crowd control follows a real resolved hit. Never stun players,
		# corpses or raid bosses, and never trust client-provided stun duration.
		if hit["kind"] == "zombie" and skill.has("stagger_seconds"):
			var infected = zombies.get(hit["id"])
			if infected != null and infected.apply_stagger(float(skill["stagger_seconds"])):
				events.append({"type": "stagger", "id": infected.id,
					"seconds": infected.stagger_seconds,
					"x": infected.position.x, "z": infected.position.z})
		# A hammer physically shoves living PvE targets away using collision
		# sweeps. Dead enemies, rooted enemies and raid bosses cannot move.
		if hit["kind"] == "zombie" and skill.has("knockback_meters"):
			var pushed = zombies.get(hit["id"])
			if pushed != null:
				var moved: float = pushed.apply_knockback(world, player.position,
					float(skill["knockback_meters"]))
				if moved > 0.001:
					events.append({"type": "knockback", "id": pushed.id,
						"x": pushed.position.x, "z": pushed.position.z,
						"distance": moved})
		# Pinning bolts only root a living infected hit by a real projectile.
		# Existing snare rules protect raid bosses and exclude PvP players.
		if hit["kind"] == "zombie" and skill.has("snare_seconds"):
			var pinned = zombies.get(hit["id"])
			if pinned != null and pinned.apply_snare(float(skill["snare_seconds"])):
				events.append({"type": "pinning_bolt", "id": pinned.id,
					"seconds": pinned.snared_seconds,
					"x": pinned.position.x, "z": pinned.position.z})
		count += 1
	if count == 0:
		var cover_hit: bool = ranged and _damage_ranged_cover(player,
			origin, direction, float(skill["range"]), skilled_damage)
		return {"ok": true, "hit": false, "hits": 0,
			"cover_hit": cover_hit, "energy": player.combat_energy}
	return {"ok": true, "hit": true, "target": first_target,
		"hits": count, "finishers": finishers,
		"energy": player.combat_energy}


## Classless evasion: no client-supplied distance, speed, stamina or invulnerability.
## Reuse swept-in-small-steps world collision and restrict zombie immunity to 0.30 s.
## Timed, one-hit melee parry. Facing, ownership and the actual enemy strike
## are evaluated on the authoritative server; no client target is accepted.
## The caller chooses no enemy: server selects the nearest visible and
## genuinely stunned infected. Bosses, players and barriers are excluded.
func cmd_stagger_finisher(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if player.finisher_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.finisher_cooldown}
	if player.attack_timer > 0.0 or player.skill_timer > 0.0:
		return {"ok": false, "reason": "attack_lock"}
	if not MeleeParry.equipped(player.inventory):
		return {"ok": false, "reason": "need_melee"}
	if not player.position.is_finite() or _is_safe(player.position):
		return {"ok": false, "reason": "safe_zone"}
	if player.combat_energy < StaggerFinisher.ENERGY_COST:
		return {"ok": false, "reason": "no_energy"}
	var target = StaggerFinisher.nearest(world, player, zombies)
	if target == null:
		return {"ok": false, "reason": "no_staggered_target"}
	var damage: float = StaggerFinisher.damage(
		player.inventory.weapon, player.progression, player.skills)
	player.combat_energy -= StaggerFinisher.ENERGY_COST
	player.finisher_cooldown = StaggerFinisher.COOLDOWN_SECONDS
	player.attack_timer = StaggerFinisher.ATTACK_LOCK
	player.skill_timer = maxf(player.skill_timer, StaggerFinisher.ATTACK_LOCK)
	player.parry_window = 0.0
	player.action = {}
	player.dirty_character = true
	# A finishing blow consumes the once-only stagger even if the target lives.
	target.stagger_seconds = 0.0
	target.attack_timer = maxf(target.attack_timer, StaggerFinisher.RECOVERY_SECONDS)
	_damage_target(player, {"kind": "zombie", "id": target.id}, damage, "melee")
	events.append({"type": "stagger_finisher", "peer": peer_id,
		"zombie": target.id, "killed": not target.is_alive()})
	return {"ok": true, "target": target.id, "damage": damage,
		"killed": not target.is_alive(), "cooldown": player.finisher_cooldown,
		"energy": player.combat_energy}


## A chasing infected may crouch and leap (or a brute charge) when its prey is at the right range.
func _maybe_start_pounce(zombie, delta: float) -> bool:
	var kind: String = InfectedPounce.kind_for(zombie.type)
	if kind == "" or zombie.raid_boss or not zombie.is_alive() or zombie.target_id == -1:
		return false
	if zombie.stagger_seconds > 0.0 or zombie.snared_seconds > 0.0 or time < float(pounce_ready_at.get(zombie.id, 0.0)):
		return false
	var prey: Player = players.get(zombie.target_id)
	if prey == null or not _alive(prey) or _is_safe(prey.position) or prey.knocked_seconds > 0.0:
		return false
	var spec: Dictionary = InfectedPounce.spec(kind)
	var d: float = Vector2(zombie.position.x, zombie.position.z).distance_to(Vector2(prey.position.x, prey.position.z))
	if d < float(spec["min"]) or d > float(spec["max"]) or rng.randf() > InfectedPounce.CHANCE_PER_SECOND * delta:
		return false
	if not InfectedMeleeCover.clear_attack(world, zombie.position, prey.position, false):
		return false
	pounces[zombie.id] = {"kind": kind, "phase": "windup", "t": 0.0, "target": prey.id}
	pounce_ready_at[zombie.id] = time + float(spec["cooldown"])
	zombie.yaw = atan2(prey.position.x - zombie.position.x, prey.position.z - zombie.position.z)
	events.append({"type": "pounce_warning", "id": zombie.id, "kind": kind, "seconds": spec["windup"],
		"target": prey.id, "x": zombie.position.x, "z": zombie.position.z})
	return true


func _tick_pounce(zombie, delta: float) -> void:
	var state: Dictionary = pounces[zombie.id]
	var spec: Dictionary = InfectedPounce.spec(str(state["kind"]))
	var prey: Player = players.get(int(state["target"]))
	if not zombie.is_alive() or zombie.stagger_seconds > 0.0 or prey == null or not _alive(prey):
		pounces.erase(zombie.id) # Interrupted (staggered mid-windup, target gone).
		return
	state["t"] = float(state["t"]) + delta
	if str(state["phase"]) == "windup":
		zombie.yaw = atan2(prey.position.x - zombie.position.x, prey.position.z - zombie.position.z)
		if float(state["t"]) < float(spec["windup"]):
			return
		# Commit to where the prey stands NOW (plus a little past): sidestepping late still works.
		var from := Vector2(zombie.position.x, zombie.position.z)
		var aim := Vector2(prey.position.x, prey.position.z)
		var to: Vector2 = aim + (aim - from).normalized() * 0.4
		# Walls and trees stop the leap: sweep the path in 3 m steps (the sweep's own limit).
		var end: Vector3 = zombie.position
		var left: Vector2 = to - from
		while left.length() > 0.01:
			var piece: Vector2 = left.limit_length(3.0)
			var next: Vector3 = Movement.sweep_displacement(world, end, piece)
			left -= piece
			if Vector2(next.x - end.x, next.z - end.z).length() < piece.length() * 0.6:
				end = next
				break
			end = next
		state["from"] = from
		state["to"] = Vector2(end.x, end.z)
		state["phase"] = "air"
		state["t"] = 0.0
		events.append({"type": "pounce", "id": zombie.id, "kind": state["kind"]})
		return
	var k: float = clampf(float(state["t"]) / float(spec["flight"]), 0.0, 1.0)
	var flat: Vector2 = (state["from"] as Vector2).lerp(state["to"], k)
	zombie.position = Vector3(flat.x, world.height_at(flat.x, flat.y) + sin(k * PI) * float(spec["arc"]), flat.y)
	if k < 1.0:
		return
	pounces.erase(zombie.id)
	_resolve_pounce(zombie, prey, str(state["kind"]), spec)


func _resolve_pounce(zombie, prey: Player, kind: String, spec: Dictionary) -> void:
	var gap: float = Vector2(zombie.position.x, zombie.position.z).distance_to(Vector2(prey.position.x, prey.position.z))
	if gap > InfectedPounce.HIT_RANGE or prey.dodge_immunity > 0.0:
		zombie.apply_stagger(InfectedPounce.MISS_STAGGER) # Whiffed and stumbled: punish it.
		events.append({"type": "evaded", "peer": prey.id, "zombie": zombie.id, "pounce": kind})
		return
	if MeleeParry.can_block(prey, zombie):
		# Perfectly timed: the attacker is thrown down for a ground finisher.
		prey.parry_window = 0.0
		ParryRiposte.arm(prey, zombie)
		zombie.apply_stagger(Brawl.DOWN_SECONDS)
		zombie.stagger_seconds = maxf(zombie.stagger_seconds, Brawl.DOWN_SECONDS)
		downed_until[zombie.id] = time + Brawl.DOWN_SECONDS
		events.append({"type": "parried", "peer": prey.id, "zombie": zombie.id})
		events.append({"type": "knockdown", "zombie": zombie.id, "peer": prey.id,
			"x": zombie.position.x, "z": zombie.position.z, "seconds": Brawl.DOWN_SECONDS})
		return
	var damage: float = Combat.apply_gear(float(zombie.data["damage"]) * float(spec["damage"]), prey.inventory)
	damage = _infected_damage_for(prey, damage)
	var applied: float = _hurt_player(prey, damage)
	prey.knocked_seconds = float(spec["down"])
	prey.attack_timer = maxf(prey.attack_timer, float(spec["down"]))
	prey.parry_window = 0.0
	prey.action = {}
	_dismount(prey, true)
	# Bowled backward along the attack line.
	var push := Vector2(prey.position.x - zombie.position.x, prey.position.z - zombie.position.z).normalized() * float(spec["shove"])
	if push.is_finite() and push.length() > 0.01:
		prey.position = Movement.move(world, prey.position, push.normalized(), push.length() / 0.1, 0.1)
	zombie.attack_timer = maxf(zombie.attack_timer, 0.6)
	events.append({"type": "hit", "kind": "player", "id": prey.id, "damage": applied, "by": -zombie.id})
	events.append({"type": "knocked_down", "peer": prey.id, "zombie": zombie.id, "kind": kind,
		"seconds": prey.knocked_seconds, "x": prey.position.x, "z": prey.position.z})


## A tree ambusher watches the ground; prey close below (or being hurt) makes it drop and strike.
func _tick_percher(zombie) -> void:
	if not zombie.is_alive():
		return
	var here := Vector2(zombie.position.x, zombie.position.z)
	var prey: Player = null
	var best: float = TreeAmbush.TRIGGER_RANGE
	for player in players.values():
		if not _alive(player) or _is_safe(player.position) or player.mounted:
			continue
		var d: float = here.distance_to(Vector2(player.position.x, player.position.z))
		if d < best:
			best = d
			prey = player
	if prey == null and zombie.target_id != -1:
		prey = players.get(zombie.target_id) # Shot or struck while perched.
	if prey == null:
		zombie.yaw += 0.01
		return
	var toward := Vector2(prey.position.x, prey.position.z) - here
	var landing2: Vector2 = Vector2(prey.position.x, prey.position.z) - toward.normalized() * TreeAmbush.LAND_OFFSET \
			if toward.length() > TreeAmbush.LAND_OFFSET else here
	var from: Vector3 = zombie.position
	var landing := Vector3(landing2.x, world.height_at(landing2.x, landing2.y), landing2.y)
	zombie.perched = false
	zombie.position = landing
	zombie.yaw = atan2(toward.x, toward.y)
	zombie.target_id = prey.id
	zombie.attack_timer = maxf(zombie.attack_timer, 0.9)
	events.append({"type": "zombie_leap", "id": zombie.id, "fx": from.x, "fy": from.y, "fz": from.z,
		"x": landing.x, "y": landing.y, "z": landing.z, "target": prey.id})
	if prey.dodge_immunity <= 0.0 and landing2.distance_to(Vector2(prey.position.x, prey.position.z)) <= TreeAmbush.LAND_HIT_RANGE:
		var zone: int = world.zone_at(prey.position.x, prey.position.z)
		var hurt: float = _hurt_player(prey, TreeAmbush.damage(zone))
		if hurt > 0.0:
			events.append({"type": "hit", "kind": "player", "id": prey.id, "damage": hurt, "by": -zombie.id})
			if not _alive(prey):
				_on_player_death(prey, -zombie.id) # The landing can be the killing blow.


## Stagger, shove and — if already reeling — knock the infected flat.
func _brawl_impact(attacker: Player, zombie, stagger_seconds: float, knockback: float) -> void:
	if downed_until.size() > 256:
		for id in downed_until.keys():
			if float(downed_until[id]) <= time or not zombies.has(id):
				downed_until.erase(id)
	var was_staggered: bool = zombie.stagger_seconds > 0.0
	zombie.apply_knockback(world, attacker.position, knockback)
	zombie.apply_stagger(stagger_seconds)
	if was_staggered and not zombie.raid_boss:
		zombie.stagger_seconds = maxf(zombie.stagger_seconds, Brawl.DOWN_SECONDS)
		downed_until[zombie.id] = time + Brawl.DOWN_SECONDS
		events.append({"type": "knockdown", "zombie": zombie.id, "peer": attacker.id,
			"x": zombie.position.x, "z": zombie.position.z, "seconds": Brawl.DOWN_SECONDS})


## Kick: cheap shove that staggers; a staggered target goes down for a ground finisher.
func cmd_kick(peer_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player != null and player.knocked_seconds > 0.0:
		return {"ok": false, "reason": "knocked_down"}
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if player.kick_cooldown > 0.0 or player.attack_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	direction = direction.normalized()
	if player.rage_seconds <= 0.0:
		if player.survival.stamina < Brawl.KICK_STAMINA:
			return {"ok": false, "reason": "no_stamina"}
		player.survival.stamina -= Brawl.KICK_STAMINA
		player.survival.stamina_recovery_delay = Defs.STAMINA_RECOVERY_DELAY
	player.kick_cooldown = Brawl.KICK_COOLDOWN
	player.attack_timer = maxf(player.attack_timer, 0.45)
	player.action = {}
	player.yaw = atan2(direction.x, direction.y)
	player.dirty_character = true
	events.append({"type": "kick", "peer": peer_id, "dir": direction, "x": player.position.x, "z": player.position.z})
	var hit := _find_hit(player, Vector2(player.position.x, player.position.z), direction, Brawl.KICK_RANGE, false)
	if hit.is_empty():
		return {"ok": true, "hit": false}
	if str(hit["kind"]) == "zombie":
		var zombie = zombies.get(int(hit["id"]))
		if zombie != null:
			_brawl_impact(player, zombie, Brawl.KICK_STAGGER_SECONDS, Brawl.KICK_KNOCKBACK)
	_damage_target(player, hit, Brawl.KICK_DAMAGE * (Brawl.RAGE_DAMAGE if player.rage_seconds > 0.0 else 1.0), "melee", false)
	return {"ok": true, "hit": true, "target": hit["kind"]}


## Rage: spend a full bar for a short frenzy.
func cmd_rage(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.rage_seconds > 0.0:
		return {"ok": false, "reason": "already_raging"}
	if player.rage < Brawl.RAGE_MAX:
		return {"ok": false, "reason": "rage_not_full", "rage": player.rage}
	player.rage = 0.0
	player.rage_seconds = Brawl.RAGE_SECONDS
	player.survival.stamina = Defs.MAX_STAMINA
	player.dirty_character = true
	events.append({"type": "rage", "peer": peer_id, "active": true, "seconds": Brawl.RAGE_SECONDS,
		"x": player.position.x, "z": player.position.z})
	return {"ok": true, "seconds": Brawl.RAGE_SECONDS}


func cmd_parry(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player != null and player.knocked_seconds > 0.0:
		return {"ok": false, "reason": "knocked_down"}
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if player.parry_cooldown > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": player.parry_cooldown}
	if player.attack_timer > 0.0 or player.dodge_immunity > 0.0:
		return {"ok": false, "reason": "attack_lock"}
	if not MeleeParry.equipped(player.inventory):
		return {"ok": false, "reason": "need_melee"}
	if player.survival.hunger <= 5.0 or player.survival.thirst <= 5.0:
		return {"ok": false, "reason": "exhausted"}
	if player.survival.stamina < MeleeParry.STAMINA_COST:
		return {"ok": false, "reason": "no_stamina"}
	player.survival.stamina -= MeleeParry.STAMINA_COST
	player.survival.stamina_recovery_delay = Defs.STAMINA_RECOVERY_DELAY
	player.parry_cooldown = MeleeParry.COOLDOWN_SECONDS
	player.parry_window = MeleeParry.WINDOW_SECONDS
	ParryRiposte.clear(player)
	player.attack_timer = maxf(player.attack_timer, MeleeParry.ATTACK_LOCK)
	player.action = {}
	player.dirty_character = true
	return {"ok": true, "window": player.parry_window,
		"cooldown": player.parry_cooldown, "stamina": player.survival.stamina}


## Arcane Bolt: a classless magic projectile. Same line-of-fire, cover and PvP
## protection rules as any shot; no ammo, paid with combat energy.
func cmd_arcane_bolt(peer_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "dead"}
	var reason: String = ArcaneAbilities.refusal(_alive(player), player.mounted,
		player.attack_timer > 0.0, player.arcane_cooldown, player.combat_energy, ArcaneAbilities.BOLT_ENERGY_COST)
	if reason != "":
		return {"ok": false, "reason": reason, "remaining": player.arcane_cooldown}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	direction = direction.normalized()
	player.combat_energy -= ArcaneAbilities.BOLT_ENERGY_COST
	player.arcane_cooldown = ArcaneAbilities.BOLT_COOLDOWN
	player.attack_timer = maxf(player.attack_timer, ArcaneAbilities.BOLT_ATTACK_LOCK)
	player.action = {}
	player.yaw = atan2(direction.x, direction.y)
	player.dirty_character = true
	var origin := Vector2(player.position.x, player.position.z)
	var hit: Dictionary = _find_hit(player, origin, direction, ArcaneAbilities.BOLT_RANGE, true)
	var reach: float = ArcaneAbilities.BOLT_RANGE
	if not hit.is_empty():
		var target_position := Vector2.ZERO
		if hit["kind"] == "zombie" and zombies.has(hit["id"]):
			var z = zombies[hit["id"]]
			target_position = Vector2(z.position.x, z.position.z)
		elif hit["kind"] == "player" and players.has(hit["id"]):
			var o: Player = players[hit["id"]]
			target_position = Vector2(o.position.x, o.position.z)
		reach = minf(reach, origin.distance_to(target_position))
		_damage_target(player, hit, ArcaneAbilities.bolt_damage(player.skills.bonus("ranged_damage")), "ranged")
	else:
		reach = minf(reach, RangedCover.first_blocker_distance(world, origin, direction, ArcaneAbilities.BOLT_RANGE))
	var end := origin + direction * reach
	events.append({"type": "arcane_bolt", "peer": peer_id, "x": player.position.x, "z": player.position.z,
		"to_x": end.x, "to_z": end.y, "hit": not hit.is_empty()})
	return {"ok": true, "hit": not hit.is_empty(), "energy": player.combat_energy,
		"cooldown": player.arcane_cooldown}


## Cataclysm ultimate: every living infected within the blast takes falloff damage
## and is staggered. PvE only; survivors are never damaged by it.
func cmd_ultimate(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "dead"}
	var reason: String = ArcaneAbilities.refusal(_alive(player), player.mounted,
		player.attack_timer > 0.0, player.ultimate_cooldown, player.combat_energy, ArcaneAbilities.ULTIMATE_ENERGY_COST)
	if reason != "":
		return {"ok": false, "reason": reason, "remaining": player.ultimate_cooldown}
	if not player.position.is_finite() or _is_safe(player.position):
		return {"ok": false, "reason": "safe_zone"}
	player.combat_energy -= ArcaneAbilities.ULTIMATE_ENERGY_COST
	player.ultimate_cooldown = ArcaneAbilities.ULTIMATE_COOLDOWN
	player.attack_timer = maxf(player.attack_timer, ArcaneAbilities.ULTIMATE_ATTACK_LOCK)
	player.action = {}
	player.dirty_character = true
	var center := Vector2(player.position.x, player.position.z)
	var targets: Array = []
	var native_selection := false
	if _ultimate_spatial_grid == null and ClassDB.class_exists("SpatialRelevancyGrid2D"):
		_ultimate_spatial_grid = ClassDB.instantiate("SpatialRelevancyGrid2D")
	# Choose at most K authoritative living targets in native C++ and avoid
	# a large GDScript distance-sort of the whole infected crowd.
	# Rebuild for each rare cast to avoid stale/dead target positions.
	if _ultimate_spatial_grid != null and _ultimate_spatial_grid.has_method("query_nearest_ids"):
		var ids := PackedInt64Array()
		var positions := PackedVector2Array()
		for zombie in zombies.values():
			if not zombie.is_alive() or not zombie.position.is_finite():
				continue
			ids.append(zombie.id)
			positions.append(Vector2(zombie.position.x, zombie.position.z))
		if _ultimate_spatial_grid.rebuild(ids, positions):
			var selected: PackedInt64Array = _ultimate_spatial_grid.query_nearest_ids(
				center, ArcaneAbilities.ULTIMATE_RADIUS, ArcaneAbilities.ULTIMATE_MAX_TARGETS)
			for id in selected:
				var zombie = zombies.get(id)
				if zombie != null and zombie.is_alive():
					targets.append({"zombie": zombie,
						"distance": center.distance_to(Vector2(zombie.position.x, zombie.position.z))})
			native_selection = true
			last_ultimate_spatial_stats = {"native": true, "candidates": ids.size(),
				"selected": targets.size(), "grid": _ultimate_spatial_grid.get_stats()}
			# A cast is rare. Never retain last cast's enemy positions in
			# idle server memory or accidentally consult a stale index.
			_ultimate_spatial_grid.clear()
	# Vanilla Godot, older Cgame versions and malformed/oversized indices
	# retain the original exact authoritative radius/ID ordering policy.
	if not native_selection:
		for zombie in zombies.values():
			if not zombie.is_alive():
				continue
			var distance: float = center.distance_to(Vector2(zombie.position.x, zombie.position.z))
			if distance <= ArcaneAbilities.ULTIMATE_RADIUS:
				targets.append({"zombie": zombie, "distance": distance})
		targets.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]) \
			if float(a["distance"]) != float(b["distance"]) else int(a["zombie"].id) < int(b["zombie"].id))
		last_ultimate_spatial_stats = {"native": false, "candidates": zombies.size(),
			"selected": mini(targets.size(), ArcaneAbilities.ULTIMATE_MAX_TARGETS)}
	var melee_bonus: float = player.skills.bonus("melee_damage")
	var hits := 0
	var kills := 0
	for entry in targets.slice(0, ArcaneAbilities.ULTIMATE_MAX_TARGETS):
		var zombie = entry["zombie"]
		_damage_target(player, {"kind": "zombie", "id": zombie.id},
			ArcaneAbilities.ultimate_damage(float(entry["distance"]), melee_bonus), "melee")
		hits += 1
		if not zombie.is_alive():
			kills += 1
		elif zombie.apply_stagger(ArcaneAbilities.ULTIMATE_STAGGER_SECONDS):
			events.append({"type": "stagger", "id": zombie.id, "seconds": zombie.stagger_seconds,
				"x": zombie.position.x, "z": zombie.position.z})
	events.append({"type": "cataclysm", "peer": peer_id, "x": player.position.x, "z": player.position.z,
		"radius": ArcaneAbilities.ULTIMATE_RADIUS, "hits": hits})
	return {"ok": true, "hits": hits, "kills": kills, "energy": player.combat_energy,
		"cooldown": player.ultimate_cooldown}


func cmd_dodge(peer_id: int, dir_x: float, dir_z: float) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player != null and player.knocked_seconds > 0.0:
		return {"ok": false, "reason": "knocked_down"}
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if player.dodge_timer > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if player.attack_timer > 0.0:
		return {"ok": false, "reason": "attack_lock"}
	var direction := Vector2(dir_x, dir_z)
	if not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared() < 0.0001:
		return {"ok": false, "reason": "no_direction"}
	if player.inventory.movement_factor() < 0.9999:
		return {"ok": false, "reason": "overweight"}
	if player.survival.hunger <= 5.0 or player.survival.thirst <= 5.0:
		return {"ok": false, "reason": "exhausted"}
	if player.survival.stamina < Evasion.STAMINA_COST:
		return {"ok": false, "reason": "no_stamina"}
	var new_position: Vector3 = Evasion.destination(world, player.position, direction)
	if Evasion.moved_distance(player.position, new_position) < Evasion.MIN_DISPLACEMENT:
		return {"ok": false, "reason": "blocked"}
	player.position = new_position
	player.yaw = atan2(direction.x, direction.y)
	player.survival.stamina -= Evasion.STAMINA_COST
	player.survival.stamina_recovery_delay = Defs.STAMINA_RECOVERY_DELAY
	player.dodge_timer = Evasion.COOLDOWN
	player.dodge_immunity = Evasion.INVULNERABLE_TO_INFECTED
	player.parry_window = 0.0 # An actual dodge cancels the remaining parry.
	ParryRiposte.clear(player)
	player.attack_timer = maxf(player.attack_timer, Evasion.ATTACK_LOCK)
	player.action = {}
	player.noise_radius = Defs.SPRINT_NOISE_RADIUS
	player.noise_timer = Defs.SPRINT_NOISE_SECONDS
	player.dirty_character = true
	events.append({"type": "dodge", "peer": peer_id, "x": new_position.x, "z": new_position.z})
	return {"ok": true, "x": new_position.x, "y": new_position.y,
		"z": new_position.z, "stamina": player.survival.stamina}


## A contributor may voluntarily pass only their OWN active raid turn.
## The server owns identities, world distance, timers and the bag contents.
func cmd_raid_skip_turn(peer_id: int, entity_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not bags.has(entity_id):
		return {"ok": false, "reason": "nothing_there"}
	var bag: Dictionary = bags[entity_id]
	if _distance_xz(player.position, bag) > Defs.REACH + 0.5:
		return {"ok": false, "reason": "too_far"}
	var guards: int = SupplyDrops.living_guards(bag, zombies)
	if guards > 0:
		return {"ok": false, "reason": "guards_alive", "remaining": guards}
	if not RaidRoundRobin.active(bag, time):
		return {"ok": false, "reason": "not_active"}
	if not RaidLoot.can_open(bag, player, time):
		return {"ok": false, "reason": "raid_reserved", "remaining": RaidLoot.remaining(bag, time)}
	if not LootRights.can_loot(bag, player, time):
		return {"ok": false, "reason": "reserved"}
	return RaidRoundRobin.skip_turn(bag, player, time)


## Explicit type selection only applies to live round-robin raid bags;
## ordinary scavenging stays unchanged, including the keyboard pickup.
func cmd_raid_claim_selected(peer_id: int, entity_id: int, item_id: String) -> Dictionary:
	if item_id.is_empty() or item_id.length() > 96:
		return {"ok": false, "reason": "invalid_item"}
	if not bags.has(entity_id):
		return {"ok": false, "reason": "nothing_there"}
	if not RaidRoundRobin.active(bags[entity_id], time):
		return {"ok": false, "reason": "not_active"}
	return cmd_loot(peer_id, entity_id, item_id)


## Authorized, reach-limited pickup from at most five existing PvE bags.
## Raid, PvP death, supply and crate loot are always manual.
func cmd_loot_sweep(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if not player.position.is_finite():
		return {"ok": false, "reason": "invalid_position"}
	if time < float(loot_sweep_next.get(peer_id, -1000000.0)):
		return {"ok": false, "reason": "cooldown",
			"remaining": maxf(0.0, float(loot_sweep_next[peer_id]) - time)}
	loot_sweep_next[peer_id] = time + LootSweep.COOLDOWN
	var ids: Array[int] = LootSweep.candidates(bags, player.position, player, time)
	if ids.is_empty():
		return {"ok": false, "reason": "nothing_to_sweep"}
	var moved: int = 0
	var collected: int = 0
	var emptied: int = 0
	for bag_id in ids:
		if not bags.has(bag_id):
			continue
		var original: Dictionary = (bags[bag_id]["items"] as Dictionary).duplicate()
		# Recheck ownership, proximity, guards and inventory at transaction time.
		var claimed: Dictionary = cmd_loot(peer_id, bag_id)
		if not bool(claimed.get("ok", false)):
			continue
		var remaining: Dictionary = bags[bag_id]["items"] if bags.has(bag_id) else {}
		var count: int = 0
		for item_id in original.keys():
			count += maxi(0, int(original[item_id]) - int(remaining.get(item_id, 0)))
		if count > 0:
			moved += count
			collected += 1
			if not bags.has(bag_id):
				emptied += 1
	if moved == 0:
		return {"ok": false, "reason": "inventory_full"}
	return {"ok": true, "items": moved, "bags": collected, "emptied": emptied}


func cmd_loot(peer_id: int, entity_id: int, requested_item: String = "") -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null or not _alive(player):
		return {"ok": false, "reason": "dead"}
	if player.mounted:
		return {"ok": false, "reason": "mounted"}
	if bags.has(entity_id):
		var bag: Dictionary = bags[entity_id]
		if _distance_xz(player.position, bag) > Defs.REACH + 0.5:
			return {"ok": false, "reason": "too_far"}
		var remaining_guards: int = SupplyDrops.living_guards(bag, zombies)
		if remaining_guards > 0:
			return {"ok": false, "reason": "guards_alive", "remaining": remaining_guards}
		# Raid trophies are reserved briefly for the killing group members
		# who actually participated. The server owns the access list and time.
		if not RaidLoot.can_open(bag, player, time):
			return {"ok": false, "reason": "raid_reserved",
				"remaining": RaidLoot.remaining(bag, time)}
		if not LootRights.can_loot(bag, player, time):
			return {"ok": false, "reason": "reserved"}
		# Optional MMORPG raid mode: each eligible survivor claims one
		# bounded share at a time. The physical bag is never cloned.
		if RaidRoundRobin.active(bag, time):
			var claim: Dictionary = RaidRoundRobin.offer(bag, player, time, requested_item)
			if not bool(claim.get("ok", false)):
				return {"ok": false, "reason": claim.get("reason", "not_your_turn"),
					"remaining": float(claim.get("remaining", 0.0))}
			var item_id: String = str(claim["item"])
			var desired: int = int(claim["quantity"])
			var leftover: Dictionary = _give_items(player, {item_id: desired})
			var received: int = desired - int(leftover.get(item_id, 0))
			if received <= 0:
				return {"ok": false, "reason": "inventory_full"}
			var unclaimed: int = int(bag["items"].get(item_id, 0)) - received
			if unclaimed > 0:
				bag["items"][item_id] = unclaimed
			else:
				bag["items"].erase(item_id)
			RaidRoundRobin.complete(bag, int(claim["index"]), time)
			_award(player, "scavenging", 3.0)
			var complete: bool = bag["items"].is_empty()
			if complete:
				bags.erase(entity_id)
			return {"ok": true, "complete": complete, "item": item_id,
				"quantity": received, "round_robin": true}
		# Need/Greed freezes only the core trophy; ordinary supplies in the
		# same raid bag are always available to eligible scavengers.
		var protected: Dictionary = RaidNeedGreed.protection(bag, player, time)
		if bool(protected.get("locked", false)):
			var supplies: Dictionary = (bag["items"] as Dictionary).duplicate()
			supplies.erase(RaidNeedGreed.ITEM_ID)
			if supplies.is_empty():
				return {"ok": false, "reason": str(protected["reason"]),
					"remaining": float(protected.get("remaining", 0.0))}
			var before_supplies: int = _item_total(supplies)
			var supply_left: Dictionary = _give_items(player, supplies)
			if _item_total(supply_left) >= before_supplies:
				return {"ok": false, "reason": "inventory_full"}
			for supply_id in supplies:
				if supply_left.has(supply_id):
					bag["items"][supply_id] = int(supply_left[supply_id])
				else:
					bag["items"].erase(supply_id)
			_award(player, "scavenging", 3.0)
			return {"ok": true, "complete": false, "need_greed": true,
				"core_locked": true}
		var taken_before: int = _item_total(bag["items"])
		var left := _give_items(player, bag["items"])
		if _item_total(left) < taken_before:
			_award(player, "scavenging", 3.0)
		if left.is_empty():
			bags.erase(entity_id)
		else:
			bag["items"] = left
		return {"ok": true, "complete": left.is_empty()}
	var crate := _find_crate(entity_id)
	if not crate.is_empty():
		if opened_crates.has(entity_id):
			return {"ok": false, "reason": "empty"}
		if _distance_xz(player.position, crate) > Defs.REACH + 0.5:
			return {"ok": false, "reason": "too_far"}
		# Sunken caches lie on the bottom: only a diver (crouch in deep water) reaches them.
		var sunken: bool = bool(crate.get("sunken", false))
		if sunken and not _is_diving(player):
			return {"ok": false, "reason": "dive_to_reach"}
		var local_rng := RandomNumberGenerator.new()
		local_rng.seed = WorldGen.mix(entity_id, int(time), world.world_seed, 3)
		var zone: int = int(crate["zone"])
		# Evaluate the bonus at the level earned BEFORE this crate. Only a
		# real reachable unopened world crate can grant XP or extra materials.
		var loot: Dictionary = Scavenging.enriched_loot(zone,
			player.progression.scavenging_level(), Combat.crate_loot(zone, local_rng))
		# Newly discovered cache categories come exclusively from the real
		# world chunk, never from player-supplied loot or a claimed item type.
		# Existing vanilla crates retain exactly their previous drop table.
		if bool(crate.get("roadside_cache", false)):
			loot = Scavenging.exploration_bonus(zone, loot, "roadside")
		elif bool(crate.get("urban_cache", false)):
			loot = Scavenging.exploration_bonus(zone, loot, "urban")
		# The kit is consumed only after a real, reachable, unopened crate has
		# passed server checks. The client cannot request bonus contents or zone.
		var unlocked: bool = false
		if Scavenging.can_unlock(zone, player.inventory.count(Scavenging.LOCKPICK_ITEM)):
			if player.inventory.remove(Scavenging.LOCKPICK_ITEM, 1):
				unlocked = true
				player.dirty_inventory = true
				player.dirty_character = true
				var sealed: Dictionary = Scavenging.sealed_compartment_loot(zone, local_rng)
				for item_id in sealed:
					loot[item_id] = int(loot.get(item_id, 0)) + int(sealed[item_id])
		_apply_loot_skills(player, loot, local_rng)
		if unlocked:
			events.append({"type": "lockpick", "peer": peer_id, "tier": zone + 1})
		_award(player, "scavenging", 12.0 + 4.0 * float(zone))
		var left: Dictionary = _give_items(player, loot)
		if not left.is_empty():
			# Whatever does not fit stays on the ground next to the crate.
			_make_bag(Vector3(crate["x"], crate["y"], crate["z"]), left, peer_id)
		opened_crates[entity_id] = time + 600.0
		var gained_xp: int = player.progression.award_scavenge(zone)
		if gained_xp > 0:
			player.dirty_character = true
			events.append({"type": "scavenging", "peer": peer_id, "xp": gained_xp,
				"level": player.progression.scavenging_level()})
		if Contracts.record_crate(player.contract_state, entity_id):
			player.dirty_character = true
		# Evidence counts only after this actual unopened, nearby cache has
		# been committed as looted. Client-supplied cache IDs never advance story.
		if StoryCampaign.record_ruin_cache(player.story_state, entity_id, zone):
			player.dirty_character = true
			events.append({"type": "story", "peer": peer_id,
				"stage": int(player.story_state["stage"]),
				"line": StoryCampaign.current_line(player.story_state),
				"objective": StoryCampaign.objective(player.story_state)})
		if bool(crate.get("dungeon", false)) and Dungeon.is_underground(player.position.x) \
				and Dungeon.region_of(player.position.x, player.position.z) == \
				Dungeon.region_of(float(crate["x"]), float(crate["z"])) \
				and StoryChapterTwo.record_underground_cache(player.story2_state, entity_id):
			player.dirty_character = true
			_story2_event(player)
		# Evidence is a real unopened surface cache in a dangerous region,
		# never a dungeon chest, a fake RPC ID, or a safe-zone supply box.
		if not bool(crate.get("dungeon", false)) and not bool(crate.get("sunken", false)) \
				and not Dungeon.is_underground(player.position.x) \
				and StoryChapterThree.record_manifest(player.story3_state, entity_id, zone):
			player.dirty_character = true
			_story3_event(player)
		if DailyBounties.record_crate(player.daily_bounty, _refresh_daily(player), entity_id):
			player.dirty_character = true
		events.append({"type": "crate", "peer": peer_id, "id": entity_id})
		# The cache is already committed as opened: no repeated RPC can create
		# another mob wave or another lockpick reward for this same opening.
		if sunken:
			# Disturbing the silt stirs whatever lives down there.
			var zone_here: int = world.zone_at(player.position.x, player.position.z)
			if Swimming.eel_chance(zone_here, _is_safe(player.position), 1.0) > 0.0:
				var bite: float = _hurt_player(player, Swimming.eel_damage(zone_here))
				events.append({"type": "eel_bite", "peer": peer_id, "damage": bite,
					"x": player.position.x, "z": player.position.z})
				if not _alive(player):
					_on_player_death(player, -1)
			return {"ok": true, "scavenging_xp": gained_xp, "sunken": true}
		_trigger_ruin_ambush(player, crate, unlocked)
		return {"ok": true, "scavenging_xp": gained_xp}
	return {"ok": false, "reason": "nothing_there"}


## Server-only PvE consequence of successfully opening a dangerous ruin.
## A sealed cache always makes enough noise to wake a pack; an ordinary
## cache wakes one with a deterministic chance based on its real world ID.
func _trigger_ruin_ambush(player: Player, crate: Dictionary, lockpicked: bool) -> void:
	if player == null or not _alive(player) or not player.position.is_finite() or \
			time < next_ruin_ambush_at or raid_boss_id >= 0 or not night_horde.is_empty():
		return
	var zone: int = int(crate.get("zone", -1))
	# Reject a survivor reaching across a protected boundary into a dangerous
	# crate: every awakened enemy must have a legal, non-safe pursuit target.
	if world.is_safe(player.position.x, player.position.z) or \
			world.zone_at(player.position.x, player.position.z) != zone:
		return
	if not RuinAmbush.awakens(zone, int(crate.get("id", -1)),
			int(world.world_seed), lockpicked):
		return
	var capacity: int = RuinAmbush.available(ruin_ambushes, zombies)
	if capacity <= 0:
		return
	var survivors: Array[Vector3] = []
	for nearby in players.values():
		if _alive(nearby) and nearby.position.is_finite():
			survivors.append(nearby.position)
	var spots: Array[Dictionary] = RuinAmbush.sites(
		world, crate, survivors, zombies, capacity,
		int(crate["id"]) % SupplyDrops.GUARD_ANGLES)
	if spots.is_empty():
		return
	var targets := {player.id: {"position": player.position, "alive": true, "safe": false}}
	var ids: Array[int] = []
	for spot in spots:
		var x: float = float(spot["x"])
		var z: float = float(spot["z"])
		var enemy_id: int = new_id()
		var enemy = Zombie.new(enemy_id, str(spot["kind"]),
			Vector3(x, world.height_at(x, z), z), -1)
		enemy.receive_pack_alert(player.id, targets)
		zombies[enemy_id] = enemy
		ids.append(enemy_id)
	ruin_ambushes.append({"ids": ids, "defeated": [], "cleared": false,
		"owner": player.id, "group": parties.group_of(player.id),
		"expires": time + RuinAmbush.LIFETIME_SECONDS})
	next_ruin_ambush_at = time + RuinAmbush.COOLDOWN_SECONDS
	events.append({"type": "ruin_ambush", "peer": player.id,
		"group": parties.group_of(player.id), "count": ids.size(), "tier": zone + 1})


## Remove only temporary ruin encounters. Missing or dead enemies are safe to
## sweep; natural spawn slots, rewards and persistent world data are untouched.
func _tick_ruin_ambush() -> void:
	for index in range(ruin_ambushes.size() - 1, -1, -1):
		var wave: Dictionary = ruin_ambushes[index]
		if time < float(wave["expires"]):
			continue
		for id in wave["ids"]:
			zombies.erase(int(id))
		ruin_ambushes.remove_at(index)


# --- Skills -------------------------------------------------------------------------------------------------

## Turns the skill sheet into the numbers the survival model uses. Cheap; called whenever a level or perk changes.
func _apply_skill_bonuses(player: Player) -> void:
	var s = player.skills
	var survival = player.survival
	var old_max: float = survival.max_health
	survival.max_health = Defs.MAX_HEALTH + s.bonus("max_health")
	if survival.max_health > old_max:
		survival.health = minf(survival.health + (survival.max_health - old_max), survival.max_health)
	survival.hunger_mult = 1.0 - s.bonus("hunger_rate")
	survival.thirst_mult = 1.0 - s.bonus("thirst_rate")
	survival.stamina_drain_mult = 1.0 - s.bonus("stamina_drain")
	survival.stamina_regen_mult = 1.0 + s.bonus("stamina_regen")
	player.dirty_skills = true


## The one place XP is granted. Callers pass what the action was worth; refused actions never call it.
func _award(player: Player, skill: String, amount: float) -> void:
	# Only confirmed server skill awards qualify for cross-training. Credits
	# buy XP that actually fits below the skill cap, not the discarded excess.
	if not Skills.SKILLS.has(skill) or not is_finite(amount) or amount <= 0.0:
		return
	var old_xp: int = int(player.skills.xp[skill])
	var base_scaled: int = clampi(roundi(amount * (1.0 + player.skills.bonus("xp_gain"))), 1, 100000)
	var base_gained: int = maxi(0, mini(Skills.MAX_XP - old_xp, base_scaled))
	var cross_active: bool = CrossTraining.active_for(player.practice_state, skill, amount, time)
	var depth_active: bool = DeepPractice.active_for(player.deep_practice_state, skill, amount, time)
	var extra: int = RestedTraining.bonus_for(amount, player.rested_xp_credit,
		player.skills.level(skill), cross_active, depth_active)
	var result: Dictionary = player.skills.add_xp(skill, amount + float(extra))
	var gained: int = int(result["gained"])
	if gained <= 0:
		return
	var bonus_gained: int = maxi(0, gained - base_gained)
	player.rested_xp_credit = maxi(0, player.rested_xp_credit - mini(extra, bonus_gained))
	player.practice_state = CrossTraining.record(player.practice_state, skill, amount, time)
	player.deep_practice_state = DeepPractice.record(player.deep_practice_state, skill, amount, time)
	player.pending_xp[skill] = int(player.pending_xp.get(skill, 0)) + int(result["gained"])
	player.dirty_skills = true
	player.dirty_character = true
	if not result["levels"].is_empty():
		for reached in result["levels"]:
			events.append({"type": "skill_up", "peer": player.id, "skill": skill, "level": int(reached), "points": player.skills.points_available()})
		_apply_skill_bonuses(player)


## Tells the player what they have gained in the last second, in one message.
func _flush_xp(player: Player) -> void:
	if player.pending_xp.is_empty():
		return
	events.append({"type": "xp", "peer": player.id, "gains": player.pending_xp.duplicate()})
	player.pending_xp = {}


func _item_total(items: Dictionary) -> int:
	var total := 0
	for id in items:
		total += int(items[id])
	return total


## Scavenging skill: more silver, and sometimes an extra item, from what a crate holds.
func _apply_loot_skills(player: Player, loot: Dictionary, local_rng: RandomNumberGenerator) -> void:
	if loot.has("silver"):
		loot["silver"] = int(round(float(loot["silver"]) * (1.0 + player.skills.bonus("loot_silver"))))
	if local_rng.randf() < player.skills.bonus("loot_extra"):
		var extras: Array = []
		for id in loot:
			if id != "silver":
				extras.append(id)
		if not extras.is_empty():
			var pick: String = String(extras[local_rng.randi() % extras.size()])
			loot[pick] = int(loot[pick]) + 1


## Damage a player takes: toughness reduces it and trains from it.
func _is_diving(player: Player) -> bool:
	return not player.mounted and player.crouching and player.inventory.count("raft") < 1 and \
		Swimming.submerged(world, player.position.x, player.position.z, true)


## Breath, drowning and eel bites for divers. Returns true when the survivor died.
func _tick_underwater(player: Player, delta: float) -> bool:
	var diving: bool = _is_diving(player)
	var before: float = player.breath
	var air: Vector2 = Swimming.breathe(player.breath, diving, delta)
	player.breath = air.x
	if not is_equal_approx(before, player.breath):
		player.dirty_character = true
	var hurt: float = 0.0
	if air.y > 0.0:
		hurt += _hurt_player(player, air.y)
		if player.breath <= 0.0 and before > 0.0:
			events.append({"type": "drowning", "peer": player.id,
				"x": player.position.x, "z": player.position.z})
	if diving:
		var zone: int = world.zone_at(player.position.x, player.position.z)
		var chance: float = Swimming.eel_chance(zone, _is_safe(player.position), delta)
		if chance > 0.0 and rng.randf() < chance:
			var bite: float = _hurt_player(player, Swimming.eel_damage(zone))
			hurt += bite
			events.append({"type": "eel_bite", "peer": player.id, "damage": bite,
				"x": player.position.x, "z": player.position.z})
			events.append({"type": "hit", "kind": "player", "id": player.id, "damage": bite, "by": -1})
	if hurt > 0.0:
		player.dirty_character = true
		if not _alive(player):
			_on_player_death(player, -1)
			return true
	return false


func _hurt_player(victim: Player, raw_damage: float) -> float:
	var reduced: float = raw_damage * (1.0 - victim.skills.bonus("damage_reduction"))
	if victim.rage_seconds > 0.0:
		reduced *= Brawl.RAGE_TAKEN
	var applied: float = victim.survival.hurt(reduced)
	if applied > 0.0 and victim.rage_seconds <= 0.0:
		victim.rage = Brawl.gain_rage(victim.rage, applied * Brawl.RAGE_PER_DAMAGE_TAKEN)
	if applied > 0.0:
		_dismount(victim, true)
		_cancel_recall(victim, "hurt")
		_award(victim, "toughness", minf(applied * 0.4, 6.0))
	return applied


func cmd_perk(peer_id: int, perk_id: String) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player"}
	var status: int = player.skills.buy_perk(perk_id)
	if status != Skills.Buy.OK:
		return {"ok": false, "reason": ["ok", "unknown_perk", "max_rank", "need_level", "need_perk", "need_points"][status]}
	_apply_skill_bonuses(player)
	player.dirty_character = true
	events.append({"type": "perk", "peer": peer_id, "perk": perk_id, "rank": player.skills.rank(perk_id)})
	return {"ok": true, "rank": player.skills.rank(perk_id), "points": player.skills.points_available()}


# --- Helpers ----------------------------------------------------------------------------------------------

## Legacy helper shared by mining and tree chopping, including fallen logs.
func _stone_reach_margin(node: Dictionary) -> float:
	return ResourceGathering.reach_margin(node)


func _distance_xz(position: Vector3, thing: Dictionary) -> float:
	return Vector2(position.x - float(thing["x"]), position.z - float(thing["z"])).length()


## Authoritative short-range resource lookup for E/LMB. The incoming ID
## encodes its owning chunk, so only that chunk needs an entity scan. Retain
## the original maximum reach window: the caller still verifies exact distance.
func _find_node_near(node_id: int, position: Vector3) -> Dictionary:
	if node_id <= 0 or not position.is_finite():
		return {}
	var extent: float = Defs.REACH + 0.5 + ResourceGathering.MAX_REACH_MARGIN
	var from_cell: Vector2i = WorldGen.cell_of(position.x - extent, position.z - extent)
	var to_cell: Vector2i = WorldGen.cell_of(position.x + extent, position.z + extent)
	var cell: Vector2i = WorldGen.entity_cell(node_id)
	if cell.x < from_cell.x or cell.x > to_cell.x or cell.y < from_cell.y or cell.y > to_cell.y:
		return {}
	for node in world.chunk(cell)["nodes"]:
		if int(node["id"]) == node_id:
			return node
	return {}


## Legacy non-command lookups retain the same 3x3 proximity-to-any-player
## eligibility as before, without accessing those 9 chunks per player.
func _entity_cell_near_players(cell: Vector2i) -> bool:
	for player in players.values():
		if not player.position.is_finite():
			continue
		var player_cell: Vector2i = WorldGen.cell_of(player.position.x, player.position.z)
		if absi(cell.x - player_cell.x) <= 1 and absi(cell.y - player_cell.y) <= 1:
			return true
	return false


func _find_node(node_id: int) -> Dictionary:
	if node_id <= 0:
		return {}
	var cell: Vector2i = WorldGen.entity_cell(node_id)
	if not _entity_cell_near_players(cell):
		return {}
	for node in world.chunk(cell)["nodes"]:
		if int(node["id"]) == node_id:
			return node
	return {}


func _find_crate(crate_id: int) -> Dictionary:
	if crate_id <= 0:
		return {}
	var cell: Vector2i = WorldGen.entity_cell(crate_id)
	if not _entity_cell_near_players(cell):
		return {}
	var data: Dictionary = world.chunk(cell)
	for crate in data["crates"]:
		if int(crate["id"]) == crate_id:
			var result: Dictionary = crate.duplicate()
			result["zone"] = data["zone"]
			return result
	return {}


## Moves items into a player's inventory; returns what did not fit.
func _give_items(player: Player, items: Dictionary) -> Dictionary:
	player.dirty_character = true
	var left: Dictionary = {}
	for id in items:
		var remaining: int = player.inventory.add(id, int(items[id]))
		if remaining > 0:
			left[id] = remaining
	player.dirty_inventory = true
	return left


func _make_bag(position: Vector3, items: Dictionary, owner_peer: int = -1) -> int:
	if items.is_empty():
		return -1
	var bag_id := new_id()
	var bag: Dictionary = {"id": bag_id, "x": position.x, "y": position.y, "z": position.z,
		"items": items.duplicate(), "expires": time + BAG_LIFETIME}
	# Ordinary infected and crate overflow belong to the killer/scavenger's
	# party for a brief window. PvP full-loot and raid bags use other rules.
	if owner_peer > 0 and players.has(owner_peer):
		var participants: Array = [players[owner_peer]]
		for member_id in parties.members_of(owner_peer):
			var member = players.get(int(member_id))
			if member != null:
				participants.append(member)
		bag.merge(LootRights.reservation(participants, time))
	bags[bag_id] = bag
	events.append({"type": "bag", "id": bag_id})
	return bag_id


func _find_hit(attacker: Player, origin: Vector2, direction: Vector2, reach: float,
		ranged: bool, ignored: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var attacker_zone: int = world.zone_at(attacker.position.x, attacker.position.z)
	# Server-owned collision blocks both normal shots and ranged skills.
	# Compute once per shot before choosing a target. Melee rules are unchanged.
	var cover_distance: float = INF
	if ranged:
		cover_distance = RangedCover.first_blocker_distance(world, origin, direction, reach)
	# Zombies.
	for zombie in zombies.values():
		if not zombie.is_alive() or ignored.has("zombie:" + str(zombie.id)):
			continue
		var distance := _hit_distance(origin, direction, Vector2(zombie.position.x, zombie.position.z), reach, ranged, 0.55)
		if distance >= 0.0 and distance < best_distance and distance < cover_distance:
			best = {"kind": "zombie", "id": zombie.id}
			best_distance = distance
	# PvP zones remain unchanged; only the mutually accepted hub opponent
	# may be targetable in the otherwise peaceful settlement.
	# Judge survivors where the attacker saw them (zombies are server-paced, never rewound).
	var rewind: float = LagCompensation.rewind_for(float(peer_round_trip.get(attacker.id, 0.0)))
	if ZoneRisk.allows_pvp(attacker_zone) or training_matches.has(attacker.id) or attacker.faction_flagged:
		for other in players.values():
			if other.id == attacker.id or not _alive(other) or ignored.has("player:" + str(other.id)):
				continue
			# Friendly party members do not intercept attacks aimed at enemies.
			var training: bool = TrainingDuel.active_for(training_matches, world, attacker, other, time)
			var group_id: int = parties.group_of(attacker.id)
			if not training and group_id != 0 and parties.group_of(other.id) == group_id:
				continue
			if not training and _guild_friendly(attacker, other):
				continue # Verified guildmates cannot intercept PvP attacks.
			if not training and not ZoneRisk.can_pvp(attacker_zone, world.zone_at(other.position.x, other.position.z)) \
					and not _faction_enemies(attacker, other):
				continue
			var seen: Vector3 = other.position if rewind <= 0.0 else \
				lag_history.position_at(other.id, time - rewind, other.position)
			var distance := _hit_distance(origin, direction, Vector2(seen.x, seen.z), reach, ranged, 0.5)
			if distance >= 0.0 and distance < best_distance and distance < cover_distance:
				best = {"kind": "player", "id": other.id}
				best_distance = distance
	return best


## Distance along the attack to the target, or -1 if it is missed. Melee needs the target within a
## cone in front; a bullet needs the ray to pass within `radius` of the target.
func _hit_distance(origin: Vector2, direction: Vector2, target: Vector2, reach: float, ranged: bool, radius: float) -> float:
	var to_target := target - origin
	var along := to_target.dot(direction)
	if along < -0.1 or along > reach + radius:
		return -1.0
	if ranged:
		var across := absf(to_target.cross(direction))
		return along if across <= radius else -1.0
	# Melee: within the reach and no more than about 70 degrees off the facing direction.
	var distance := to_target.length()
	if distance > reach + radius:
		return -1.0
	if distance < 0.001:
		return 0.0
	return distance if to_target.normalized().dot(direction) >= 0.34 else -1.0


func _damage_target(attacker: Player, hit: Dictionary, damage: float, source: String = "melee", basic_melee: bool = false) -> void:
	attacker.dirty_character = true
	if hit["kind"] == "zombie":
		var zombie = zombies.get(hit["id"])
		if zombie == null:
			return
		# PvE relic traits are derived from physically carried gear on the server.
		# Never grant these against survivors or for stale equipment IDs.
		var equipped_weapon: String = attacker.inventory.weapon
		var physically_owned: bool = equipped_weapon != "" and attacker.inventory.count(equipped_weapon) > 0
		damage = Combat.against_infected(damage, equipped_weapon, physically_owned)
		damage = AntisepticEdge.damage(damage, attacker.inventory,
			attacker.edge_coating_weapon, attacker.edge_coating_seconds, zombie)
		damage *= 1.0 + attacker.skills.bonus("zombie_damage")
		# True group flanking uses the infected's current LIVE target and
		# both real server positions. No damage or targets from the client.
		var flanking: bool = basic_melee and source == "melee" and \
			PartyFlank.qualifies(attacker, zombie, players, parties, world)
		if flanking and damage > 0.0:
			damage = PartyFlank.damage(damage, zombie.raid_boss)
			events.append({"type": "party_flank", "peer": attacker.id,
				"zombie": zombie.id, "bonus": 10 if zombie.raid_boss else 18})
		# A modest PvE-only team bonus: exact marked infected and living
		# party member in range. Never applied to player-vs-player attacks.
		damage = PartyFocus.damage(damage, zombie.is_alive() and _alive(attacker) and
			PartyFocus.in_range(attacker.position, zombie.position) and
			parties.has_focus(attacker.id, zombie.id, time))
		# The same short-lived exposed state benefits nearby survivors
		# regardless of weapon choice, but never applies to player PvP.
		damage = SunderMark.amplify(damage, zombie, time)
		# Boss armor recovery is applied only to the current live raid boss,
		# after an actual server-resolved slam; no PvP or other infected bonus.
		if zombie.id == raid_boss_id:
			damage = RaidRecovery.amplify(damage, zombie, raid_exposed_until, time)
			# Active raid guards reduce only their own boss incoming PvE damage.
			damage = RaidWard.absorb(damage, zombie, raid_boss_id, raid_minions, zombies)
		# Only real, positive, server-applied hits can qualify for group XP.
		if damage > 0.0 and zombie.is_alive() and (zombie.contributors.size() < 16 or zombie.contributors.has(attacker.id)):
			var equipped: String = attacker.inventory.weapon
			if equipped != "" and attacker.inventory.count(equipped) > 0:
				zombie.contributors[attacker.id] = {"time": time, "weapon": equipped,
					"group": parties.group_of(attacker.id)}
		# A real hit on a living enemy trains the weapon skill (more for heavier hits).
		_award(attacker, "marksman" if source == "ranged" else "melee", 1.0 + damage / 6.0)
		var hit_event: Dictionary = {"type": "hit", "kind": "zombie", "id": zombie.id, "damage": damage,
			"x": zombie.position.x, "z": zombie.position.z, "by": attacker.id, "ranged": source == "ranged",
			"weapon": attacker.inventory.weapon}
		events.append(hit_event)
		if zombie.take_damage(damage, attacker.id):
			hit_event["fatal"] = true
			attacker.kills += 1
			_earn_renown(attacker, Reputation.kill_points(zombie.type,
				zombie.elite, zombie.raid_boss), "infected")
			# Award XP once, when a living infected is defeated with owned/equipped
			# gear. Ordinary hits, missed shots and re-killing corpses award none.
			var weapon: String = attacker.inventory.weapon
			if weapon != "" and attacker.inventory.count(weapon) > 0:
				var mastery_xp: int = attacker.progression.award_combat(
					weapon, int(zombie.data.get("xp", 0)))
				if mastery_xp > 0:
					events.append({"type": "mastery", "peer": attacker.id,
						"skill": Progression.combat_skill_for_weapon(weapon),
						"xp": mastery_xp})
			_party_award_assists(attacker, zombie)
			_award(attacker, "slayer", float(Defs.ZOMBIES[zombie.type].get("xp", 5)) * 2.0)
			if Contracts.record_kill(attacker.contract_state):
				attacker.dirty_character = true
			# Only this confirmed lethal PvE branch can record story combat.
			var previous_story_stage: int = int(attacker.story_state["stage"])
			if StoryCampaign.record_infected_kill(attacker.story_state):
				attacker.dirty_character = true
				if int(attacker.story_state["stage"]) != previous_story_stage:
					events.append({"type": "story", "peer": attacker.id,
						"stage": int(attacker.story_state["stage"]),
						"line": StoryCampaign.current_line(attacker.story_state),
						"objective": StoryCampaign.objective(attacker.story_state)})
			# Exactly the real, server-spawned deepest-room guardian, killed
			# by a character still in that same underground dungeon.
			if zombie.elite and bool(zombie.get_meta("_story_dungeon_guardian", false)) \
					and Dungeon.is_underground(attacker.position.x) \
					and Dungeon.region_of(attacker.position.x, attacker.position.z) == \
					Dungeon.region_of(zombie.position.x, zombie.position.z) \
					and StoryChapterTwo.record_guardian(attacker.story2_state):
				attacker.dirty_character = true
				_story2_event(attacker)
			if DailyBounties.record_kill(attacker.daily_bounty, _refresh_daily(attacker)):
				attacker.dirty_character = true
			_on_zombie_death(zombie, attacker)
		elif zombie.id == raid_boss_id and not raid_pending_slam.is_empty() and \
				physically_owned and _alive(attacker) and attacker.position.is_finite() and \
				not _is_safe(attacker.position) and \
				Vector2(attacker.position.x, attacker.position.z).distance_to(
					Vector2(zombie.position.x, zombie.position.z)) <= RaidInterrupt.MAX_DISTANCE:
			# Only server-applied, nonlethal hits with an owned, equipped weapon
			# can count. The warning tracks distinct real party members.
			if RaidInterrupt.record_hit(raid_pending_slam, zombie, attacker.id,
					parties.group_of(attacker.id), damage, time):
				var center := Vector2(float(raid_pending_slam["x"]),
					float(raid_pending_slam["z"]))
				raid_pending_slam = {}
				var exposed: float = RaidRecovery.window_seconds(zombie)
				raid_exposed_until = maxf(raid_exposed_until, time + exposed)
				events.append({"type": "raid_interrupted", "id": zombie.id,
					"x": center.x, "z": center.y, "exposed_seconds": exposed})
	else:
		var victim: Player = players.get(hit["id"])
		if victim == null or not _alive(victim):
			return
		if TrainingDuel.active_for(training_matches, world, attacker, victim, time):
			# Nonlethal combat. No PvP points, infamy, deaths, item loss, XP,
			# bleeding or combat logout penalty can originate from sparring.
			var strike: float = maxf(0.0, Combat.apply_gear(damage, victim.inventory))
			strike *= 1.0 - clampf(victim.skills.bonus("damage_reduction"), 0.0, 0.4)
			var previous: float = victim.survival.health
			var applied: float = victim.survival.hurt(minf(strike, maxf(0.0, previous - 1.0)))
			if applied > 0.0:
				_dismount(victim, true)
				victim.dirty_character = true
			if strike >= previous - 1.0 and strike > 0.0:
				_end_training(victim.id, attacker.id, "knockout")
			return
		# Parties are cooperative: do not allow friendly fire in red zones.
		var attacker_party: int = parties.group_of(attacker.id)
		if attacker_party != 0 and attacker_party == parties.group_of(victim.id):
			return
		if _guild_friendly(attacker, victim):
			return # Direct damage paths also obey guild alliances.
		var faction_fight: bool = _faction_enemies(attacker, victim)
		if not ZoneRisk.can_pvp(world.zone_at(attacker.position.x, attacker.position.z),
				world.zone_at(victim.position.x, victim.position.z)) and not faction_fight:
			return
		_award(attacker, "marksman" if source == "ranged" else "melee", 1.0 + damage / 6.0)
		var final_damage: float = Combat.apply_gear(damage, victim.inventory)
		var applied: float = _hurt_player(victim, final_damage)
		if applied > 0.0:
			# Both participants are combat-tagged from actual server-applied PvP
			# damage, including the attacker after a lethal finishing strike.
			CombatLogout.mark(attacker, time)
			CombatLogout.mark(victim, time)
		# Only genuine dangerous-zone player damage grants retaliation.
		# A legally counterattacking victim cannot justify the original
		# initiator's aggression, and wanted outlaws get no immunity.
		if applied > 0.0 and _alive(victim) and not PvpInfamy.is_outlaw(victim.pvp_infamy) 				and not PvpInfamy.can_retaliate(attacker.defense_target,
				attacker.defense_until, victim.id, time):
			var fresh: bool = not PvpInfamy.can_retaliate(victim.defense_target,
				victim.defense_until, attacker.id, time)
			victim.defense_target = attacker.id
			victim.defense_until = time + PvpInfamy.SELF_DEFENSE_SECONDS
			if fresh:
				events.append({"type": "self_defense", "peer": victim.id,
					"seconds": PvpInfamy.SELF_DEFENSE_SECONDS})
		var wielded: String = attacker.inventory.weapon
		if applied > 0.0 and _alive(victim) and wielded != "" and attacker.inventory.count(wielded) > 0 \
				and str(Defs.item(wielded).get("weapon", "")) == "melee":
			if victim.survival.add_bleeding(Defs.PVP_MELEE_BLEEDING_PER_HIT):
				victim.dirty_character = true
				events.append({"type": "bleeding", "peer": victim.id,
					"severity": victim.survival.bleeding, "source": "pvp"})
		events.append({"type": "hit", "kind": "player", "id": victim.id, "damage": final_damage, "by": attacker.id})
		if not _alive(victim):
			attacker.kills += 1
			if faction_fight:
				_award_faction_points(attacker, Factions.POINTS_PLAYER_KILL, "player_kill")
			var lawful: String = PvpInfamy.lawful_kill_reason(victim.pvp_infamy,
				attacker.defense_target, attacker.defense_until, victim.id, time)
			if faction_fight:
				lawful = "faction_war" # Faction warfare is sanctioned: no infamy.
			elif ZoneRisk.lawless(world.zone_at(victim.position.x, victim.position.z)):
				lawful = "black_zone" # Albion black zone: open full-loot PvP, no reputation loss.
			if lawful != "":
				events.append({"type": "justice", "peer": attacker.id, "reason": lawful})
			else:
				var old_score: float = attacker.pvp_infamy
				attacker.pvp_infamy = PvpInfamy.gain_for_kill(old_score)
				if attacker.pvp_infamy > old_score:
					attacker.dirty_character = true
					events.append({"type": "infamy", "peer": attacker.id,
						"score": attacker.pvp_infamy,
						"outlaw": PvpInfamy.is_outlaw(attacker.pvp_infamy)})
			var zone: int = world.zone_at(victim.position.x, victim.position.z)
			var honor_result: Dictionary = PvPHonor.record(attacker, victim,
				zone, time, pvp_honor_ledger)
			if bool(honor_result.get("ok", false)):
				attacker.dirty_character = true
				events.append({"type": "pvp_honor", "peer": attacker.id,
					"earned": int(honor_result["awarded"]),
					"honor": attacker.pvp_honor,
					"rank": str(honor_result["rank"])})
			# The honor ledger already enforces the stable-account victim
			# cooldown. Never pay silver for replayed kills, guests or alts.
			var bounty: int = OutlawBounty.reward_for_kill(attacker, victim, zone, honor_result)
			if bounty > 0:
				var overflow: Dictionary = _give_items(attacker, {"silver": bounty})
				if not overflow.is_empty():
					_make_bag(attacker.position, overflow, attacker.id)
				events.append({"type": "outlaw_bounty", "peer": attacker.id,
					"silver": bounty, "zone": zone})
			_on_player_death(victim, attacker.id)


## Nearby party members gain modest weapon mastery XP only if they personally
## hit this infected in the last 20 seconds. AFK/nonparticipants receive none.
## The killing blow and contract progress still belong to the actual killer.
func _party_award_assists(killer: Player, zombie) -> void:
	var group: Array = parties.members_of(killer.id)
	if group.size() < 2:
		return
	var encounter_zone: int = world.zone_at(zombie.position.x, zombie.position.z)
	var shared_xp: int = Party.assist_xp(int(zombie.data.get("xp", 0)))
	if shared_xp <= 0:
		return
	for member_id in group:
		if int(member_id) == killer.id:
			continue
		var participant: Player = players.get(int(member_id))
		if participant == null or not _alive(participant):
			continue
		if not Party.in_assist_range(participant.position, zombie.position):
			continue
		# Prevent XP being shared across green/red risk zone borders.
		if world.zone_at(participant.position.x, participant.position.z) != encounter_zone:
			continue
		var hit: Dictionary = zombie.contributors.get(int(member_id), {})
		if hit.is_empty() or time - float(hit.get("time", -INF)) > Party.ASSIST_WINDOW:
			continue
		# Only a hit that happened inside THIS party earns an assist reward.
		if int(hit.get("group", 0)) != parties.group_of(killer.id):
			continue
		var used_weapon: String = str(hit.get("weapon", ""))
		if used_weapon.is_empty() or participant.inventory.count(used_weapon) < 1:
			continue
		var actual: int = participant.progression.award_combat(used_weapon, shared_xp)
		if actual > 0:
			participant.dirty_character = true
			events.append({"type": "mastery", "peer": participant.id,
				"skill": Progression.combat_skill_for_weapon(used_weapon),
				"xp": actual, "assist": true})


func _on_zombie_death(zombie, killer: Player) -> void:
	parties.clear_focus_target(zombie.id)
	# Confirmed kill of a real raid reinforcement weakens the same boss.
	if zombie.id != raid_boss_id and raid_boss_id > 0 and raid_minions.has(zombie.id):
		var current_boss = zombies.get(raid_boss_id)
		if current_boss != null and current_boss.is_alive():
			var remaining: int = RaidWard.living_count(current_boss,
				raid_boss_id, raid_minions, zombies)
			events.append({"type": "raid_ward_changed", "id": raid_boss_id,
				"x": current_boss.position.x, "z": current_boss.position.z,
				"guards": remaining,
				"reduction_percent": RaidWard.reduction_percent(remaining)})
	# A caravan is defended only after every originally summoned infected
	# is confirmed dead, not when the wave disappears or its timer expires.
	for wave in caravan_ambushes:
		if time >= float(wave["expires"]) or not CaravanAmbush.record_kill(wave, zombie.id):
			continue
		var courier: Player = players.get(int(wave.get("owner", -1)))
		if (courier != null and _alive(courier) and courier.caravan_ambushed and
				not courier.caravan_defended and courier.deaths == int(wave.get("deaths", -1)) and
				courier.caravan_state == wave.get("route", {}) and
				courier.inventory.count(str(courier.caravan_view.get("cargo", ""))) > 0):
			courier.caravan_defended = true
			courier.dirty_character = true
			events.append({"type": "caravan_defended", "peer": courier.id})
		break
	# Completion is awarded only for real zombie deaths, never for expiry or
	# missing mobs. No free crate rewards or separate repeatable loot.
	for wave in ruin_ambushes:
		if time >= float(wave["expires"]) or not RuinAmbush.record_kill(wave, zombie.id):
			continue
		events.append({"type": "ruin_ambush_cleared",
			"peer": int(wave.get("owner", -1)),
			"group": int(wave.get("group", 0)),
			"count": wave["ids"].size()})
		break
	var zone: int = world.zone_at(zombie.position.x, zombie.position.z)
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = WorldGen.mix(zombie.id, int(time * 10.0), world.world_seed, 5)
	var loot: Dictionary = Combat.zombie_loot(zombie.type, zone, loot_rng)
	if zombie.elite:
		loot = EliteInfected.enhanced_loot(loot, zone)
	if loot.has("silver"):
		loot["silver"] = int(round(float(loot["silver"]) * (1.0 + killer.skills.bonus("zombie_silver"))))
	if zone >= Factions.MIN_ZONE:
		_award_faction_points(killer, Factions.POINTS_ELITE_KILL if zombie.elite else Factions.POINTS_INFECTED_KILL, "infected")
	# Albion-style enchantment materials: runes (infected), souls (elites), relics (raid bosses).
	var enchant_drop: Dictionary = Enchanting.material_drop(zone, zombie.elite, zombie.raid_boss, loot_rng)
	for material in enchant_drop:
		loot[material] = int(loot.get(material, 0)) + int(enchant_drop[material])
	if zombie.raid_boss:
		# A speed bonus uses only the authoritative encounter start, live boss
		# identity and death timestamp; no client-supplied result or reward.
		var tempo_bonus: Dictionary = {}
		if zombie.id == raid_boss_id and raid_started_at > 0.0 and \
				is_finite(time) and time >= raid_started_at:
			tempo_bonus = RaidTempo.bonus(zone, time - raid_started_at)
		# Fixed server-side reward bag; no player gets multiple personal copies.
		var boss_treasure: Dictionary = RaidEncounter.treasure(zone)
		for item_id in boss_treasure:
			loot[item_id] = int(loot.get(item_id, 0)) + int(boss_treasure[item_id])
		for item_id in tempo_bonus:
			loot[item_id] = int(loot.get(item_id, 0)) + int(tempo_bonus[item_id])
		raid_boss_id = -1
		raid_pending_slam = {}
		raid_pending_cone = {}
		raid_exposed_until = 0.0
		_clear_raid_minions()
		raid_wave = 0
		events.append({"type": "raid_defeated", "id": zombie.id,
			"x": zombie.position.x, "z": zombie.position.z,
			"tempo_rank": RaidTempo.rank(time - raid_started_at) if not tempo_bonus.is_empty() else ""})
	var loot_bag_id: int = _make_bag(zombie.position, loot, -1 if zombie.raid_boss else killer.id)
	if loot_bag_id >= 0 and not _is_safe(zombie.position):
		CorpseScent.mark(bags[loot_bag_id], time)
	if zombie.raid_boss and loot_bag_id >= 0:
		# Entitlements are frozen at the confirmed kill; guests use object
		# identity, accounts survive reconnect. No client-authored loot rights.
		var eligible: Array = RaidLoot.eligible(killer, zombie, players, parties, world, time)
		RaidLoot.reserve(bags[loot_bag_id], eligible, time)
		if parties.loot_mode_for(killer.id) == "round_robin" and eligible.size() > 1:
			RaidRoundRobin.activate(bags[loot_bag_id], eligible, zombie.id, time)
		elif parties.loot_mode_for(killer.id) == "need_greed" and eligible.size() > 1:
			RaidNeedGreed.activate(bags[loot_bag_id], eligible, zombie.id, time)
	if spawn_state.has(zombie.spawn_id):
		spawn_state[zombie.spawn_id] = {"zombie": -1, "next": time + (240.0 if zone < 2 else 360.0)}
	# The client must learn when ALL original guards are down. A per-cache
	# latch prevents duplicate "clear" events on corpse reprocessing.
	if zombie.supply_cache_id >= 0 and bags.has(zombie.supply_cache_id):
		var cache: Dictionary = bags[zombie.supply_cache_id]
		if SupplyDrops.mark_cleared(cache, zombies):
			events.append({"type": "supply_cleared", "id": int(cache["id"]),
				"x": float(cache["x"]), "z": float(cache["z"])})
	# Only death of the final real horde member can release the one-shot
	# public trophy; a missing/despawned mob never counts as a victory.
	if not night_horde.is_empty() and time < float(night_horde["expires"]):
		var horde_ids: Array = night_horde["ids"]
		if horde_ids.has(zombie.id) and NightHorde.fully_defeated(horde_ids, zombies):
			var horde_zone: int = int(night_horde["zone"])
			var reward_id: int = _make_bag(zombie.position, NightHorde.loot(horde_zone))
			if reward_id >= 0:
				bags[reward_id]["horde_cache"] = true
				bags[reward_id]["expires"] = time + NightHorde.CACHE_DURATION
				events.append({"type": "horde_cleared", "id": reward_id,
					"x": zombie.position.x, "z": zombie.position.z, "tier": horde_zone + 1})
			night_horde = {}
	events.append({"type": "zombie_died", "id": zombie.id, "x": zombie.position.x, "z": zombie.position.z})


## Full-loot deaths occur in red/black. Green/yellow deaths retain gear.
func _on_player_death(victim: Player, killer: int) -> void:
	victim.flare_seconds = 0.0
	victim.storm_insulator_seconds = 0.0
	_cancel_recall(victim, "dead")
	_abort_training(victim.id, "death")
	_cancel_market_seller(victim.id)
	_cancel_player_trade(victim.id, "dead")
	victim.deaths += 1
	victim.combat_stress = 0.0
	victim.stress_pressure = 0.0
	victim.stress_scan_seconds = 0.0
	# A courier must survive their defense; a later respawn cannot reclaim it.
	victim.caravan_defended = false
	victim.caravan_night = NightCaravan.initial(victim.caravan_view)
	victim.dirty_character = true
	victim.action = {}
	victim.sharpened_weapon = ""
	victim.sharpened_hits = 0
	victim.sighted_weapon = ""
	victim.sighted_hits = 0
	victim.wedge_charges = 0
	victim.plated_armor = ""
	victim.plated_hits = 0
	victim.ruin_survey = {} # Dead scouts cannot retain private map beacons.
	victim.prospect_mark = {} # Death clears paid exploration marks.
	victim.dodge_immunity = 0.0
	victim.sprint_buff_seconds = 0.0
	victim.sprint_buff_speed = 0.0
	ParryRiposte.clear(victim)
	victim.guardian_brace = 0.0
	victim.guard_link_target = -1
	victim.guard_link_seconds = 0.0
	victim.shield_wall_seconds = 0.0
	GuardianRetribution.clear(victim)
	for teammate in players.values():
		if teammate.guard_link_target == victim.id:
			teammate.guard_link_target = -1
			teammate.guard_link_seconds = 0.0
	victim.spore_filter_seconds = 0.0
	victim.wound_seal_seconds = 0.0
	victim.soft_sole_seconds = 0.0
	victim.chain_wrap_seconds = 0.0
	victim.tire_grip_seconds = 0.0
	parties.clear_standard_by(victim.id)
	parties.cancel_ready_check_for(victim.id)
	parties.cancel_focus_by(victim.id)
	parties.clear_ping_by(victim.id)
	victim.meal_seconds = 0.0
	victim.meal_tier = 0
	victim.ration_seconds = 0.0
	victim.ration_tier = 0
	victim.defense_target = -1
	victim.defense_until = 0.0
	var zone: int = world.zone_at(victim.position.x, victim.position.z)
	var drops_gear: bool = ZoneRisk.full_loot(zone)
	victim.last_death_full_loot = drops_gear
	victim.keep_inventory_on_respawn = not drops_gear
	if not drops_gear:
		# Albion-style: a death that keeps your gear still costs durability.
		victim.inventory.wear_equipped(GearDurability.DEATH_WEAR)
	if drops_gear:
		var everything: Dictionary = victim.inventory.take_everything()
		var death_bag_id: int = _make_bag(victim.position, everything)
		if death_bag_id >= 0:
			DeathRecovery.tag(bags[death_bag_id], victim)
			if not _is_safe(victim.position):
				CorpseScent.mark(bags[death_bag_id], time)
	victim.respawn_timer = Defs.RESPAWN_SECONDS
	victim.dirty_inventory = true
	events.append({"type": "death", "peer": victim.id, "killer": killer, "full_loot": drops_gear, "zone": zone})


# --- The simulation tick -------------------------------------------------------------------------------

func _tick_data_layers() -> void:
	if time - _layers_checked_at < 60.0:
		return
	_layers_checked_at = time
	var wanted: Array = data_layers_override if data_layers_override is Array else DataLayers.scheduled(Time.get_unix_time_from_system())
	if wanted != data_layers:
		data_layers = wanted.duplicate()
		events.append({"type": "data_layers", "layers": data_layers})


func tick(delta: float) -> void:
	# Events from commands that arrived since the last tick are kept: the network layer drains them.
	if events.size() > 2000:
		events = events.slice(events.size() - 1000)
	time += delta
	tick_count += 1
	_tick_data_layers()
	_tick_market()
	_tick_trades()
	parties.expire(time)
	_tick_players(delta)
	for tracked in players.values():
		lag_history.record(tracked.id, time, tracked.position)
	if tick_count % 64 == 0:
		lag_history.prune(players)
	_tick_siege_charges()
	if tick_count % WorldDiscovery.SCAN_EVERY_TICKS == 0:
		_tick_site_discoveries()
	_tick_training()
	if tick_count % ArenaMatchmaking.CHECK_EVERY_TICKS == 0:
		_tick_arena_queue()
	var capture_events: Array = territory.tick(delta, time, players, parties)
	events.append_array(capture_events)
	events.append_array(siege_contracts.tick(time, territory.sites, parties, capture_events))
	if tick_count % SiegeWaves.CHECK_EVERY_TICKS == 0:
		_tick_siege_waves()
	_tick_raid_encounter()
	_tick_lightning()
	_tick_zombies(delta)
	_tick_acid_pools()
	_tick_ember_pools()
	_tick_recalls()
	if tick_count % Defs.TICK_RATE == 0:
		_tick_barricade_upkeep(float(Defs.TICK_RATE) * delta)
		# Prevent destroyed/replaced wall IDs from accumulating in session state.
		for wall_id in _wall_infected_attack_until.keys():
			if not barricades.has(wall_id) or time >= float(_wall_infected_attack_until[wall_id]):
				_wall_infected_attack_until.erase(wall_id)
	_tick_world(delta)


## Walls whose owner comes by stay kept; walls left alone past their upkeep crumble and are gone at zero health.
func _tick_barricade_upkeep(seconds: float) -> void:
	var crumbled: Array = []
	# Index connected owners just once for all structures in this upkeep pass.
	# Account rights and guest peer IDs keep their original authoritative rules.
	var active_owners: Dictionary = WallUpkeepIndex.live_owners(
		players, func(survivor) -> bool: return _alive(survivor))
	for id in barricades:
		var wall: Dictionary = barricades[id]
		if WallUpkeepIndex.owner_near(wall, active_owners):
			wall["upkeep_until"] = time + Structures.UPKEEP_SECONDS
		if time <= float(wall.get("upkeep_until", time + 1.0)):
			continue
		wall["hp"] = float(wall["hp"]) - Structures.decay_per_second(Structures.tier_of(wall)) * seconds
		world_structure_revision += 1
		if float(wall["hp"]) <= 0.0:
			crumbled.append(id)
	for id in crumbled:
		barricades.erase(id)
		_acid_wall_last_hit.erase(id)
		siege_last_by_wall.erase(id)
		siege_braces.erase(id)
		world.remove_dynamic_blocker(id)
		events.append({"type": "barricade_decayed", "id": id})


## One server-wide storm hazard, never selected by a client. It is announced
## before damage, then resolved at the locked world coordinate. There can be
## only one pending bolt, independent of the number of connected players.
func _tick_lightning() -> void:
	if not lightning_pending.is_empty():
		if time < float(lightning_pending["at"]):
			return
		var strike: Dictionary = lightning_pending
		lightning_pending = {}
		if not StormLightning.strike_valid(world, strike, time):
			return
		var center := Vector2(float(strike["x"]), float(strike["z"]))
		for survivor in players.values():
			if not _alive(survivor) or _is_safe(survivor.position) or \
					not StormLightning.in_blast(center, survivor.position):
				continue
			if survivor.dodge_immunity > 0.0:
				events.append({"type": "evaded", "peer": survivor.id, "zombie": -1})
				continue
			var shock_damage: float = StormInsulator.lightning_damage(
				StormLightning.DAMAGE, survivor.storm_insulator_seconds)
			var taken: float = survivor.survival.hurt(shock_damage)
			if taken > 0.0:
				_dismount(survivor, true)
				survivor.dirty_character = true
				events.append({"type": "hit", "kind": "player",
					"id": survivor.id, "damage": taken, "by": -1})
			if not _alive(survivor):
				_on_player_death(survivor, -1)
		events.append({"type": "lightning_struck", "x": center.x,
			"z": center.y, "radius": StormLightning.RADIUS})
		return
	if time < next_lightning_at:
		return
	next_lightning_at = time + StormLightning.RETRY_INTERVAL
	var candidates: Array = players.keys()
	candidates.sort() # Deterministic regardless of session insertion order.
	for peer in candidates:
		var survivor: Player = players[peer]
		if not _alive(survivor):
			continue
		var warning: Dictionary = StormLightning.create_warning(
			world, survivor.position, time)
		if warning.is_empty():
			continue
		lightning_pending = warning
		next_lightning_at = time + StormLightning.CHECK_INTERVAL
		events.append({"type": "lightning_warning",
			"x": warning["x"], "z": warning["z"],
			"radius": StormLightning.RADIUS, "at": warning["at"]})
		break


## Armed charges resolve exactly once. The charge has been paid for and fixed
## to a real wall; disconnecting or moving cannot move/double-spend the blast.
func _tick_siege_charges() -> void:
	var ready: Array = siege_charges.keys()
	ready.sort()
	for charge_id in ready:
		var charge: Dictionary = siege_charges.get(charge_id, {})
		if charge.is_empty() or time < float(charge.get("until", INF)):
			continue
		siege_charges.erase(charge_id) # Remove before applying damage or broadcasting.
		var x: float = float(charge["x"])
		var z: float = float(charge["z"])
		if not SiegeCharge.valid_detonation(world, charge, barricades):
			events.append({"type": "siege_charge_fizzled", "id": charge_id,
				"x": x, "z": z})
			continue
		var wall_id: int = int(charge["wall"])
		var prior_hp: float = float(barricades[wall_id]["hp"])
		var protection: Dictionary = SiegeBlastBrace.absorb(siege_braces,
			wall_id, SiegeCharge.DAMAGE, time)
		var broken: bool = damage_barricade(wall_id, float(protection["damage"]))
		if float(protection["absorbed"]) > 0.0:
			events.append({"type": "siege_brace_absorbed",
				"x": x, "z": z, "raw_absorbed": float(protection["absorbed"])})
		var hp: float = 0.0 if broken else float(barricades[wall_id]["hp"])
		events.append({"type": "siege_charge_detonated", "id": charge_id,
			"x": x, "z": z, "wall": wall_id, "hp": hp,
			"damage": prior_hp - hp, "broken": broken})
		# Explosions attract infected to the actual wall position, never by
		# falsely marking all nearby players as loud. Reuse bounded sound lures.
		if decoys.size() < NoiseDecoy.MAX_ACTIVE:
			var noise_id: int = new_id()
			decoys[noise_id] = {"id": noise_id, "x": x,
				"y": world.height_at(x, z), "z": z,
				"owner": -1, "expires": time + SiegeCharge.NOISE_SECONDS}


## Completion occurs after all AI, melee, infection and acid damage in tick().
func _cancel_recall(player: Player, reason: String) -> void:
	if player.recall.is_empty():
		return
	player.recall = {}
	events.append({"type": "recall_cancelled", "peer": player.id, "reason": reason})


func _tick_recalls() -> void:
	for player in players.values():
		if player.recall.is_empty():
			continue
		var reason: String = HubRecall.cancel_reason(world, player, zombies, time)
		if training_matches.has(player.id) or arena_queue.has(player.id):
			reason = "in_duel"
		if reason != "":
			_cancel_recall(player, reason)
			continue
		if time < float(player.recall.get("until", INF)):
			continue
		var at: Vector3 = HubRecall.destination(world)
		if not at.is_finite():
			_cancel_recall(player, "no_safe_destination")
			continue
		if not player.inventory.remove(HubRecall.ITEM_ID, 1):
			_cancel_recall(player, "not_carried")
			continue
		player.position = at
		player.recall = {}
		player.recall_ready_at = time + HubRecall.COOLDOWN_SECONDS
		player.dirty_inventory = true
		player.dirty_character = true
		events.append({"type": "recall_completed", "peer": player.id})


## Generated POI bounds and player coordinates are read exclusively from
## the server simulation. No client discovery, site-ID or reward command exists.
func _tick_site_discoveries() -> void:
	for player in players.values():
		if not _alive(player) or not player.position.is_finite():
			continue
		var found: Dictionary = WorldDiscovery.reveal(
			world, player.position, player.discovered_sites)
		if found.is_empty():
			continue
		var zone: int = int(found["zone"])
		_award(player, "explorer", WorldDiscovery.explorer_xp(zone))
		_earn_renown(player, WorldDiscovery.renown(zone), "landmark")
		player.dirty_character = true
		events.append({"type": "site_discovered", "peer": player.id,
			"id": int(found["id"]), "name": str(found["display"]),
			"zone": zone, "count": player.discovered_sites.size()})


func _tick_players(delta: float) -> void:
	for player in players.values():
		if not RuinSurvey.active(player.ruin_survey, time, opened_crates):
			player.ruin_survey = {}
		if not ProspectingChart.active(player.prospect_mark, time, depleted):
			player.prospect_mark = {}
		player.input_budget = minf(player.input_budget + delta, 0.25)
		player.mount_cooldown = maxf(0.0, player.mount_cooldown - maxf(0.0, delta))
		player.smoke_cooldown = maxf(0.0, player.smoke_cooldown - maxf(0.0, delta))
		player.edge_coating_seconds = AntisepticEdge.tick(player.inventory,
			player.edge_coating_weapon, player.edge_coating_seconds,
			maxf(0.0, delta), _alive(player))
		if player.edge_coating_seconds <= 0.0:
			player.edge_coating_weapon = ""
		if player.storm_insulator_seconds > 0.0:
			player.storm_insulator_seconds = StormInsulator.remaining(
				player.storm_insulator_seconds, delta)
			player.dirty_character = true
		if player.flare_seconds > 0.0:
			player.flare_seconds = HandFlare.remaining(player.flare_seconds, delta)
			player.dirty_character = true
		if player.soft_sole_seconds > 0.0:
			player.soft_sole_seconds = maxf(0.0,
				player.soft_sole_seconds - maxf(0.0, delta))
			player.dirty_character = true
		if player.chain_wrap_seconds > 0.0:
			player.chain_wrap_seconds = maxf(0.0,
				player.chain_wrap_seconds - maxf(0.0, delta))
			player.dirty_character = true
		if player.tire_grip_seconds > 0.0:
			player.tire_grip_seconds = maxf(0.0,
				player.tire_grip_seconds - maxf(0.0, delta))
			player.dirty_character = true
		if player.inventory.count(Mounts.ITEM_ID) < 1 and player.bike_integrity < BikeIntegrity.MAX_INTEGRITY:
			player.bike_integrity = BikeIntegrity.MAX_INTEGRITY
			player.dirty_character = true
		if player.inventory.count(Mounts.ITEM_ID) < 1 and player.bike_service_meters > 0.0:
			player.bike_service_meters = 0.0
			player.dirty_character = true
		if player.mounted and (not _alive(player) or
				player.inventory.count(Mounts.ITEM_ID) < 1 or
				not BikeIntegrity.can_ride(player.bike_integrity) or
				BikeCargo.movement_factor(player.inventory,
					player.skills.bonus("carry_capacity"), true) < 0.9999 or
				player.survival.fracture > 0.0):
			_dismount(player, false)
		var old_infamy: float = player.pvp_infamy
		player.pvp_infamy = PvpInfamy.decay(old_infamy, delta)
		if player.pvp_infamy < old_infamy:
			player.dirty_character = true
		if not FieldWhetstone.valid_state(player.sharpened_weapon,
				player.sharpened_hits, player.inventory):
			player.sharpened_weapon = ""
			player.sharpened_hits = 0
			player.dirty_character = true
		if not FieldSightingKit.valid_state(player.sighted_weapon,
				player.sighted_hits, player.inventory):
			player.sighted_weapon = ""
			player.sighted_hits = 0
			player.dirty_character = true
		if not FieldArmorPlate.valid_state(player.plated_armor,
				player.plated_hits, player.inventory):
			player.plated_armor = ""
			player.plated_hits = 0
			player.dirty_character = true
		player.rest_cooldown = maxf(0.0, player.rest_cooldown - maxf(0.0, delta))
		player.party_aid_timer = maxf(0.0, player.party_aid_timer - maxf(0.0, delta))
		player.medic_cover_cooldown = maxf(0.0, player.medic_cover_cooldown - maxf(0.0, delta))
		player.feast_timer = maxf(0.0, player.feast_timer - maxf(0.0, delta))
		player.guardian_timer = maxf(0.0, player.guardian_timer - maxf(0.0, delta))
		player.guardian_brace = maxf(0.0, player.guardian_brace - maxf(0.0, delta))
		player.guard_link_cooldown = maxf(0.0, player.guard_link_cooldown - maxf(0.0, delta))
		player.shield_wall_cooldown = maxf(0.0, player.shield_wall_cooldown - maxf(0.0, delta))
		player.shield_wall_seconds = maxf(0.0, player.shield_wall_seconds - maxf(0.0, delta))
		if player.shield_wall_seconds > 0.0 and (not _alive(player) or player.mounted or \
				not player.position.is_finite() or _is_safe(player.position) or \
				not GuardianTaunt.melee_equipped(player.inventory) or \
				parties.members_of(player.id).size() < 2):
			player.shield_wall_seconds = 0.0
		player.guard_counter_seconds = maxf(0.0, player.guard_counter_seconds - maxf(0.0, delta))
		if player.guard_counter_seconds <= 0.0 or not _alive(player) or player.mounted or \
				parties.group_of(player.id) != player.guard_counter_party or \
				player.inventory.weapon != player.guard_counter_weapon or \
				not GuardianTaunt.melee_equipped(player.inventory) or \
				not zombies.has(player.guard_counter_target) or \
				not zombies[player.guard_counter_target].is_alive():
			GuardianRetribution.clear(player)
		player.guard_link_seconds = maxf(0.0, player.guard_link_seconds - maxf(0.0, delta))
		if player.guard_link_seconds > 0.0 and not GuardianIntercept.can_guard(
				player, players.get(player.guard_link_target), parties, world):
			player.guard_link_seconds = 0.0
		if player.guard_link_seconds <= 0.0:
			player.guard_link_target = -1
		# A disconnected teammate or removed weapon cannot prolong protection.
		if player.guardian_brace > 0.0 and (parties.members_of(player.id).size() < 2 or
				not GuardianTaunt.melee_equipped(player.inventory)):
			player.guardian_brace = 0.0
		player.lake_drink_cooldown = maxf(0.0, player.lake_drink_cooldown - maxf(0.0, delta))
		player.rain_cooldown = maxf(0.0, player.rain_cooldown - maxf(0.0, delta))
		player.spore_sample_cooldown = maxf(0.0, player.spore_sample_cooldown - maxf(0.0, delta))
		var previous_seal: float = player.wound_seal_seconds
		player.wound_seal_seconds = maxf(0.0, previous_seal - maxf(0.0, delta))
		if player.wound_seal_seconds != previous_seal:
			player.dirty_character = true
		player.stim_cooldown = maxf(0.0, player.stim_cooldown - maxf(0.0, delta))
		player.decoy_timer = maxf(0.0, player.decoy_timer - maxf(0.0, delta))
		player.flash_cooldown = maxf(0.0, player.flash_cooldown - maxf(0.0, delta))
		player.attack_timer = maxf(player.attack_timer - delta, 0.0)
		player.skill_timer = maxf(player.skill_timer - delta, 0.0)
		player.ultimate_timer = maxf(player.ultimate_timer - delta, 0.0)
		if player.faction_unflag_at >= 0.0 and time >= player.faction_unflag_at:
			player.faction_flagged = false
			player.faction_unflag_at = -1.0
			player.dirty_character = true
		player.progression.focus = minf(ReturnRate.MAX_FOCUS, player.progression.focus + ReturnRate.REGEN_PER_SECOND * maxf(0.0, delta))
		for gear_slot in player.gear_skill_timers.keys():
			player.gear_skill_timers[gear_slot] = maxf(float(player.gear_skill_timers[gear_slot]) - delta, 0.0)
		if player.sprint_buff_seconds > 0.0:
			player.sprint_buff_seconds = maxf(player.sprint_buff_seconds - delta, 0.0)
			if player.sprint_buff_seconds <= 0.0:
				player.sprint_buff_speed = 0.0
				player.dirty_character = true
		player.dodge_timer = maxf(player.dodge_timer - delta, 0.0)
		player.dodge_immunity = maxf(player.dodge_immunity - delta, 0.0)
		player.parry_cooldown = maxf(0.0, player.parry_cooldown - maxf(0.0, delta))
		player.kick_cooldown = maxf(0.0, player.kick_cooldown - maxf(0.0, delta))
		player.knocked_seconds = maxf(0.0, player.knocked_seconds - maxf(0.0, delta))
		if player.rage_seconds > 0.0:
			player.rage_seconds = maxf(0.0, player.rage_seconds - maxf(0.0, delta))
			if player.rage_seconds <= 0.0:
				events.append({"type": "rage", "peer": player.id, "active": false})
		player.finisher_cooldown = maxf(0.0,
			player.finisher_cooldown - maxf(0.0, delta))
		player.arcane_cooldown = maxf(0.0, player.arcane_cooldown - maxf(0.0, delta))
		player.ultimate_cooldown = maxf(0.0, player.ultimate_cooldown - maxf(0.0, delta))
		player.parry_window = maxf(0.0, player.parry_window - maxf(0.0, delta))
		ParryRiposte.tick(player, delta)
		player.noise_timer = maxf(player.noise_timer - delta, 0.0)
		if player.noise_timer <= 0.0:
			player.noise_radius = 0.0
		if not _alive(player):
			if player.respawn_timer <= 0.0 and player.survival.health <= 0.0:
				# Safety net: a damage path that skipped its death check must still drop
				# the loot and count the death, never grant a free instant respawn.
				_on_player_death(player, -1)
				continue
			player.respawn_timer -= delta
			if player.respawn_timer <= 0.0:
				_spawn_player(player)
			continue
		# Integrate only the fraction of the tick while the cooked meal is active.
		var meal_effect_tier: int = player.meal_tier
		var active_meal: float = HeartyMeal.bonus_seconds(player.meal_seconds, delta)
		var stamina_meal_seconds: float = HeartyMeal.stamina_seconds(
			active_meal, player.survival.stamina_recovery_delay)
		player.meal_seconds = maxf(0.0, player.meal_seconds - maxf(0.0, delta))
		if player.meal_seconds <= 0.0 and player.meal_tier > 0:
			player.meal_tier = 0
		if active_meal > 0.0:
			player.dirty_character = true
		var ration_active: float = TrailRation.active_seconds(player.ration_seconds, delta)
		var hunger_factor: float = TrailRation.hunger_factor(
			player.ration_tier, player.ration_seconds, delta)
		player.ration_seconds = maxf(0.0, player.ration_seconds - maxf(0.0, delta))
		if player.ration_seconds <= 0.0:
			player.ration_tier = 0
		if ration_active > 0.0:
			player.dirty_character = true
		var nourished: bool = player.survival.hunger > 20.0 and player.survival.thirst > 20.0
		var energy_bonus: float = (
			HeartyMeal.energy_per_second(meal_effect_tier) * active_meal) if nourished else 0.0
		# Temporary field standard: only the actual group and present members
		# may benefit. Source position and expiration come from the server.
		var standard: Dictionary = parties.standard_at(player.id, player.position, time, delta)
		var standard_seconds: float = 0.0
		if nourished and not standard.is_empty():
			standard_seconds = RallyStandard.bonus_seconds(time, delta,
				float(standard["placed_at"]), float(standard["expires"]))
		player.combat_energy = minf(Defs.COMBAT_ENERGY_MAX,
			player.combat_energy + Defs.COMBAT_ENERGY_REGEN * delta + energy_bonus +
				RallyStandard.ENERGY_PER_SECOND * standard_seconds)
		# Session-only stress from infected currently hunting THIS survivor.
		# Sample rarely (not on every world tick) and never consider nearby
		# neutral creatures, other players' PvP, or idle/investigating zombies.
		player.stress_scan_seconds -= maxf(0.0, delta)
		if player.stress_scan_seconds <= 0.0:
			player.stress_scan_seconds = CombatStress.SCAN_SECONDS
			player.stress_pressure = CombatStress.pressure(
				zombies, player.id, player.position)
		var in_sanctuary: bool = _is_safe(player.position)
		var safe_rest: bool = in_sanctuary or FieldCampfire.has_warmth(
			campfires, player.position, time) or PortableShelter.covers(
			shelters, player.position, time)
		var accompanied: bool = CombatStress.has_live_companion(
			player.id, player.position, players, parties)
		player.combat_stress = CombatStress.advance(
			player.combat_stress, delta, player.stress_pressure,
			in_sanctuary, safe_rest, accompanied)
		var stamina_before_stress_tick: float = player.survival.stamina
		var stamina_recovery_delay_before_tick: float = player.survival.stamina_recovery_delay
		var had_food_poisoning: float = player.survival.food_poisoning
		var had_bleeding: bool = player.survival.bleeding > 0.0
		var had_fracture: bool = player.survival.fracture > 0.0
		var had_scent_mask: bool = player.survival.scent_mask_seconds > 0.0
		# Apply only to survival; preserve trained hunger-rate skills afterwards.
		var normal_hunger_mult: float = player.survival.hunger_mult
		player.survival.hunger_mult = normal_hunger_mult * hunger_factor
		var damage: float = player.survival.tick(delta)
		player.survival.hunger_mult = normal_hunger_mult
		if not is_equal_approx(player.survival.food_poisoning, had_food_poisoning):
			player.dirty_character = true
		# Only ordinary passive stamina regen is damped. Purchased food,
		# party standards, skills and explicit healing stay unchanged.
		var passive_gain: float = maxf(0.0,
			player.survival.stamina - stamina_before_stress_tick)
		player.survival.stamina -= passive_gain * (
			1.0 - CombatStress.regen_multiplier(player.combat_stress))
		if damage > 0.0:
			_dismount(player, true)
		if had_scent_mask:
			player.dirty_character = true
		if nourished and stamina_meal_seconds > 0.0:
			player.survival.stamina = minf(Defs.MAX_STAMINA,
				player.survival.stamina +
					HeartyMeal.stamina_per_second(meal_effect_tier) * stamina_meal_seconds)
		if standard_seconds > 0.0 and player.survival.fracture <= 0.0:
			# Preserve sprint/dodge exhaustion delay rather than adding free stamina.
			var rested_seconds: float = RallyStandard.bonus_seconds(time, delta,
				float(standard["placed_at"]), float(standard["expires"]))
			var ready_seconds: float = maxf(0.0,
				rested_seconds - maxf(0.0, stamina_recovery_delay_before_tick))
			if ready_seconds > 0.0:
				player.survival.stamina = minf(Defs.MAX_STAMINA,
					player.survival.stamina + RallyStandard.STAMINA_PER_SECOND * ready_seconds)
		# Holding a contested PvP outpost grants a small local rally advantage.
		# Only the server owns party identity, site control and stamina.
		if player.survival.stamina_recovery_delay <= 0.0 and \
				player.survival.hunger > 20.0 and player.survival.thirst > 20.0 and \
				territory.has_rally_bonus(player.id, player.position, parties, time, players):
			player.survival.stamina = minf(Defs.MAX_STAMINA,
				player.survival.stamina + TerritoryControl.RALLY_STAMINA_PER_SECOND * delta)
		var conditions: Dictionary = Weather.conditions(world, player.position.x, player.position.z, time)
		# An old armor ID after an inventory transfer must not provide warmth.
		var worn_armor: String = player.inventory.armor
		if worn_armor != "" and player.inventory.count(worn_armor) <= 0:
			worn_armor = ""
		var at_warm_fire: bool = FieldCampfire.has_warmth(campfires,
			player.position, time)
		var under_tarp: bool = PortableShelter.covers(shelters, player.position, time)
		var old_wetness: float = player.survival.wetness
		player.survival.wetness = WetClothing.next_wetness(old_wetness, delta,
			conditions, worn_armor, under_tarp, at_warm_fire)
		# Walking into a shallow ocean/ford soaks clothes, even beneath a
		# roof or while standing near a fire. Terrain is server-owned.
		var water_depth: float = WadingWetness.depth_at(world, player.position)
		player.survival.wetness = WadingWetness.after_weather(old_wetness,
			player.survival.wetness, delta, water_depth)
		if not is_equal_approx(old_wetness, player.survival.wetness):
			player.dirty_character = true
		# Average the old and new moisture when a large simulation tick
		# crosses the rain-to-soaked boundary. A fire always overrides cold.
		var average_wet: float = 0.5 * (old_wetness + player.survival.wetness)
		var weather_severity: float = Weather.effective_severity(conditions, worn_armor)
		# Regional server wind now raises exposure in cold open terrain. The
		# existing fire, tarp and thermal-wrap protection applies afterward.
		var wind: Vector2 = Weather.wind_at(world, player.position.x, player.position.z, time)
		weather_severity = clampf(weather_severity +
			WetClothing.cold_penalty(average_wet, conditions, worn_armor) +
			WindChill.penalty(conditions, wind, average_wet, worn_armor), 0.0, 1.0)
		if at_warm_fire:
			weather_severity = 0.0
		weather_severity = PortableShelter.exposure_severity(weather_severity,
			under_tarp, StormTarpAnchors.anchored_covers(shelters, player.position, time))
		damage += player.survival.weather_tick(delta, weather_severity)
		# The filter only protects for the portion of a tick it actually covers.
		# An oversized server tick cannot extend the buff past its remaining time.
		var remaining_filter: float = player.spore_filter_seconds
		var filtered_seconds: float = minf(maxf(0.0, remaining_filter), maxf(0.0, delta))
		var unfiltered_seconds: float = maxf(0.0, delta) - filtered_seconds
		var spores: Dictionary = SporeHazard.status(world, player.position, time,
			worn_armor, remaining_filter)
		var in_spores: bool = bool(spores["active"])
		if in_spores != player.spore_exposed:
			player.spore_exposed = in_spores
			events.append({"type": "spore_enter" if in_spores else "spore_exit",
				"peer": player.id, "rate": float(spores["rate"])})
		var spore_dose: float = float(spores["rate"]) * filtered_seconds
		if unfiltered_seconds > 0.0:
			var bare_spores: Dictionary = SporeHazard.status(world, player.position, time, worn_armor)
			spore_dose += float(bare_spores["rate"]) * unfiltered_seconds
		if in_spores and player.survival.add_infection(spore_dose):
			player.dirty_character = true
		if remaining_filter > 0.0 and delta > 0.0:
			player.spore_filter_seconds = maxf(0.0, remaining_filter - delta)
			player.dirty_character = true
		if player.survival.exposure > 0.0 or player.survival.warmth_seconds > 0.0:
			player.dirty_character = true
		if player.survival.infection > 0.0 or had_bleeding or had_fracture or damage > 0.0:
			# Persist the last clotting tick and its health loss, not only active wounds.
			player.dirty_character = true
		if damage > 0.0 and not _alive(player):
			_on_player_death(player, -1)
			continue
		if _tick_underwater(player, delta):
			continue
		var zone: int = world.zone_at(player.position.x, player.position.z)
		if zone != player.zone_notice:
			player.zone_notice = zone
			events.append({"type": "zone", "peer": player.id, "zone": zone})
			var region_bit: int = 1 << zone
			if zone >= 1 and int(player.skills.zones_seen) & region_bit == 0:
				player.skills.zones_seen = int(player.skills.zones_seen) | region_bit
				_award(player, "explorer", 40.0 * float(zone))
		player.xp_report_timer += delta
		if player.xp_report_timer >= 1.0:
			player.xp_report_timer = 0.0
			_flush_xp(player)
		if not player.action.is_empty():
			if player.action.has("fish"):
				var cast_at := Vector2(float(player.action["cast_x"]), float(player.action["cast_z"]))
				if bool(player.action.get("storm_cast", false)) and not StormFishing.qualifies(
						world, player.position, time):
					player.action = {}
					events.append({"type": "storm_cast_lost", "peer": player.id})
					continue
				var current_catch: Dictionary = Fishing.validate_start(world, player.position,
					player.inventory, player.progression.gathering_level("fishing"))
				if not bool(current_catch.get("ok", false)) \
						or str(current_catch.get("item", "")) != str(player.action.get("catch_id", "")) \
						or Vector2(player.position.x, player.position.z).distance_to(cast_at) > 0.45:
					player.action = {}
					continue
				player.action["remaining"] = float(player.action["remaining"]) - delta
				if float(player.action["remaining"]) <= 0.0:
					_finish_fishing(player)
			else:
				var node := _find_node(int(player.action["node"]))
				if node.is_empty() or depleted.has(int(player.action["node"])):
					player.action = {}
					continue
				player.action["remaining"] = float(player.action["remaining"]) - delta
				if float(player.action["remaining"]) <= 0.0:
					_finish_gather(player, node)


func _finish_fishing(player: Player) -> void:
	var item_id: String = str(player.action.get("catch_id", Fishing.CATCH_ID))
	var tier: int = int(player.action.get("tier", 1))
	var requested_bait: bool = bool(player.action.get("baited", false))
	var storm_cast: bool = bool(player.action.get("storm_cast", false))
	var hooked: bool = bool(player.action.get("hooked", false))
	player.action = {}
	if item_id != Fishing.catch_item(tier):
		return # Never trust an inconsistent pending action.
	if storm_cast and (requested_bait or not StormFishing.qualifies(world, player.position, time)):
		return # Never reward a forged or expired storm action.
	var amount: int = 1 + (1 if rng.randf() < 0.35 else 0) + (Fishing.HOOK_BONUS if hooked else 0)
	# Risk rewards and consumable bait cannot stack.
	var storm_bonus: int = StormFishing.bonus_for(
		player.inventory, item_id, amount) if storm_cast else 0
	var bait_used: bool = FishingBait.spend_for_bonus(
		player.inventory, item_id, amount, requested_bait)
	if bait_used:
		amount += FishingBait.BONUS_FISH
	amount += storm_bonus
	var added: int = amount - player.inventory.add(item_id, amount)
	if added > 0:
		player.progression.award_gather("fishing", tier, added)
		player.dirty_inventory = true
		player.dirty_character = true
	events.append({"type": "fished", "peer": player.id, "item": item_id,
		"amount": added, "tier": tier, "bait_used": bait_used,
		"storm_cast": storm_cast, "storm_bonus": storm_bonus, "hooked": hooked})


func _finish_gather(player: Player, node: Dictionary, base_amount: int = -1,
		finish_node: bool = true, from_strike: bool = false,
		hit_number: int = 0, precise: bool = false) -> void:
	var info := Defs.node_info(node["kind"])
	var item_id: String = info["yield"]
	if item_id in ["wood", "stone", "ore", "fiber"]:
		item_id = "%s_%d" % [item_id, int(node["tier"])]
	var amount: int = int(info["amount"]) if base_amount < 0 else base_amount
	if finish_node and str(node["kind"]) != "pebble" and rng.randf() < 0.3:
		amount += 1
	var gather_skill := Skills.skill_for_node(String(node["kind"]))
	if finish_node and gather_skill != "" and rng.randf() < player.skills.bonus("gather_yield." + gather_skill):
		amount += 1 # Skill: a lucky harvest.
	var outpost_bonus: int = territory.harvest_bonus(player.id, node, players,
		parties, time, world) if finish_node else 0
	var ordinary_amount: int = amount
	amount += outpost_bonus
	# Only the actual server-started, in-range and skill/tool-qualified mine
	# may spend a paid wedge charge. A full bag keeps all remaining charges.
	var wedge_authenticated: bool = finish_node and (from_strike or
		int(player.action.get("node", -1)) == int(node["id"])) and (
		player.position.is_finite() and _distance_xz(player.position, node) <= Defs.REACH + 0.5 + _stone_reach_margin(node) and
		player.progression.can_gather(String(node["kind"]), int(node["tier"])) and
		Defs.tier_of(player.inventory.best_tool("pickaxe")) >= int(node["tier"]))
	var wedge_bonus: int = MiningWedges.bonus(String(node["kind"]), int(node["tier"]),
		player.wedge_charges, player.inventory.free_space_for(item_id), amount,
		wedge_authenticated)
	amount += wedge_bonus
	var left: int = player.inventory.add(item_id, amount)
	var wedge_spent: bool = wedge_bonus > 0 and left == 0
	if wedge_spent:
		player.wedge_charges -= 1
	# One optional medicinal plant per actual successful bush/berry harvest.
	# The server reads biome and risk from the generated world itself. A full
	# bag, an invalid habitat, and exhausted nodes cannot mint extra supplies.
	var herbs_added: int = 0
	if finish_node and amount - left > 0:
		var found_herb: String = HerbalForaging.roll(String(node["kind"]),
			world.biome_at(float(node.get("x", player.position.x)), float(node.get("z", player.position.z))),
			world.zone_at(float(node.get("x", player.position.x)), float(node.get("z", player.position.z))), rng)
		if found_herb != "" and player.inventory.add(found_herb, 1) == 0:
			herbs_added = 1
	# Never advertise an outpost bonus if a full bag could not accept it.
	var paid_outpost_bonus: int = mini(outpost_bonus, maxi(0, amount - left - ordinary_amount))
	if gather_skill != "" and amount - left > 0:
		_award(player, gather_skill, (3.0 + 2.0 * float(amount - left)) * float(int(node["tier"])))
	# No XP for items that did not fit, nor for repeat attempts on depleted nodes.
	player.progression.award_gather(String(node["kind"]), int(node["tier"]), amount - left)
	# Each server-confirmed strike or forage gives away the player's position.
	# Uses the same short-lived channel as footsteps and gunfire; existing
	# infected hearing, chase leashes, safe zones and camouflage rules apply.
	var harvest_noise: float = GatheringNoise.radius(String(node["kind"]),
		player.crouching, amount - left)
	harvest_noise = MiningWedges.harvest_noise(harvest_noise,
		wedge_bonus if wedge_spent else 0)
	if harvest_noise > 0.0:
		player.noise_radius = maxf(player.noise_radius, harvest_noise)
		player.noise_timer = maxf(player.noise_timer, GatheringNoise.SOUND_SECONDS)
	player.dirty_inventory = true
	player.dirty_character = true
	if finish_node:
		player.action = {}
		resource_hit_progress.erase(int(node["id"]))
		depleted[int(node["id"])] = time + float(info["respawn"])
		world.set_node_depleted(int(node["id"]), true)
		SurveySignal.clear_depleted(parties, int(node["id"]))
	events.append({"type": "gathered", "peer": player.id, "item": item_id,
		"amount": amount - left, "node": node["id"], "final": finish_node, "strike": from_strike,
		"hit": hit_number, "precise": precise,
		"x": float(node["x"]), "z": float(node["z"]),
		"herbs": herbs_added, "harvest_noise": harvest_noise,
		"outpost_bonus": paid_outpost_bonus,
		"wedge_bonus": wedge_bonus if wedge_spent else 0})


## Rare dangerous-zone group boss. One live boss per simulation and a 10-minute
## cooldown; normal elite infected and nightly barricade sieges remain separate.
func _tick_raid_encounter() -> void:
	if raid_boss_id != -1:
		var boss = zombies.get(raid_boss_id)
		if boss == null or not boss.is_alive():
			raid_boss_id = -1
			raid_pending_slam = {}
			raid_pending_cone = {}
			raid_exposed_until = 0.0
			_clear_raid_minions()
			raid_wave = 0
			return
		var at := Vector2(boss.position.x, boss.position.z)
		if time >= raid_started_at + RaidEncounter.MAX_ENCOUNTER_SECONDS \
				or _nearest_player_distance(at) > ZOMBIE_ACTIVE_RADIUS:
			zombies.erase(raid_boss_id)
			events.append({"type": "raid_expired", "id": raid_boss_id,
				"x": at.x, "z": at.y})
			raid_boss_id = -1
			raid_pending_slam = {}
			raid_pending_cone = {}
			raid_exposed_until = 0.0
			_clear_raid_minions()
			raid_wave = 0
			return
		_tick_raid_reinforcements(boss)
		if RaidEncounter.try_enrage(boss):
			# Phase transition is one-time per encounter. Never cancel a
			# telegraphed strike already in flight.
			raid_next_slam_at = minf(raid_next_slam_at,
				time + RaidEncounter.ENRAGE_SLAM_COOLDOWN)
			events.append({"type": "raid_enraged", "id": raid_boss_id,
				"x": at.x, "z": at.y, "hp": boss.health})
		if not raid_pending_slam.is_empty():
			if time >= float(raid_pending_slam["at"]):
				var center := Vector2(float(raid_pending_slam["x"]),
					float(raid_pending_slam["z"]))
				var boss_id: int = int(raid_pending_slam["id"])
				raid_pending_slam = {}
				_resolve_raid_slam(boss_id, center)
			return
		if not raid_pending_cone.is_empty():
			if time >= float(raid_pending_cone["at"]):
				var strike: Dictionary = raid_pending_cone
				raid_pending_cone = {}
				_resolve_raid_cone(strike)
			return
		if raid_next_cone_at > 0.0 and time >= raid_next_cone_at and _raid_boss_plan(boss) == "charge":
			if _start_raid_cone(boss):
				return
		if time >= raid_next_slam_at and boss.target_id != -1:
			raid_pending_slam = {"id": raid_boss_id,
				"x": at.x, "z": at.y,
				"at": time + RaidEncounter.SLAM_WARNING,
				"party": 0, "contributors": {}}
			raid_next_slam_at = time + RaidEncounter.slam_cooldown(boss)
			events.append({"type": "raid_warning", "id": raid_boss_id,
				"x": at.x, "z": at.y,
				"radius": RaidEncounter.SLAM_RADIUS,
				"seconds": RaidEncounter.SLAM_WARNING})
			return
		if raid_next_cone_at > 0.0 and time >= raid_next_cone_at:
			_start_raid_cone(boss)
		return

	if time < RaidEncounter.START_DELAY or \
			time - last_raid_spawn_time < RaidEncounter.COOLDOWN or \
			zombies.size() >= RaidEncounter.MAX_INFECTED or \
			tick_count % SiegeWaves.CHECK_EVERY_TICKS != 0:
		return
	var leader_id: int = RaidEncounter.eligible_leader(world, players, parties)
	if leader_id == -1:
		return
	var leader: Player = players.get(leader_id)
	var site: Vector2 = RaidEncounter.spawn_site(world, players,
		leader.position, tick_count % RaidEncounter.SPAWN_ANGLES)
	if site == Vector2.INF:
		return
	var spawn_id: int = new_id()
	var boss = Zombie.new(spawn_id, "brute",
		Vector3(site.x, world.height_at(site.x, site.y), site.y), -1)
	RaidEncounter.empower(boss)
	var targets: Dictionary = {}
	targets[leader_id] = {"position": leader.position, "alive": true, "safe": false}
	boss.receive_pack_alert(leader_id, targets)
	zombies[spawn_id] = boss
	raid_boss_id = spawn_id
	raid_wave = 0
	raid_minions.clear()
	raid_started_at = time
	raid_exposed_until = 0.0
	raid_pending_cone = {}
	raid_next_cone_at = time + 16.0
	last_raid_spawn_time = time
	raid_next_slam_at = time + 9.0
	events.append({"type": "raid_started", "id": spawn_id,
		"x": site.x, "z": site.y, "zone": world.zone_at(site.x, site.y),
		"health": boss.health})


## Telegraphs the boss cone strike at its current target; false if it cannot aim.
func _start_raid_cone(boss) -> bool:
	var target: Player = players.get(boss.target_id)
	if target != null and _alive(target) and not _is_safe(target.position) and \
			world.zone_at(target.position.x, target.position.z) >= RaidEncounter.MIN_ZONE and \
			RaidCone.can_aim(boss.position, target.position):
		var aim: Vector2 = RaidCone.direction(boss.position, target.position)
		raid_pending_cone = {"id": raid_boss_id, "x": boss.position.x,
			"y": boss.position.y, "z": boss.position.z,
			"dx": aim.x, "dz": aim.y,
			"at": time + RaidCone.WINDUP_SECONDS}
		raid_next_cone_at = time + RaidCone.cooldown(boss)
		events.append({"type": "raid_cone_warning", "id": raid_boss_id,
			"x": boss.position.x, "z": boss.position.z,
			"dx": aim.x, "dz": aim.y, "reach": RaidCone.REACH,
			"half_angle": RaidCone.HALF_ANGLE_DEGREES,
			"seconds": RaidCone.WINDUP_SECONDS})
		return true
	return false


## HTN decision layer (infected_raid_domain.gd): a target outside the slam
## radius makes the boss open with its reaching cone strike instead of a
## slam that cannot land. Enrage and reinforcements keep their own phases.
func _raid_boss_plan(boss) -> String:
	var target: Player = players.get(boss.target_id)
	var far: bool = target != null and Vector2(target.position.x - boss.position.x,
		target.position.z - boss.position.z).length() > RaidEncounter.SLAM_RADIUS
	var steps: Array[String] = HTNPlanner.plan(InfectedRaidDomain.htn_domain(), "boss_turn",
		{"low_health": false, "enraged": true, "surrounded": false, "adds_alive": true,
		"target_far": far, "stamina_ok": true})
	for step in steps:
		if step == "charge" or step == "slam":
			return step
	return "slam"


## Two one-time health phases; no client command may create minions.
## The existing boss enrage and slam remain intact.
func _tick_raid_reinforcements(boss) -> void:
	var phase: int = RaidReinforcements.next_phase(
		boss.health, float(boss.data["health"]), raid_wave)
	var free_slots: int = RaidEncounter.MAX_INFECTED - zombies.size()
	if phase == 0 or free_slots <= 0:
		return
	var points: Array[Vector2] = RaidReinforcements.sites(
		world, players, zombies, boss.position, phase,
		mini(free_slots, RaidReinforcements.MAX_WAVE))
	if points.is_empty():
		return
	var types: Array[String] = RaidReinforcements.kinds(phase)
	var target: Player = players.get(boss.target_id)
	var visible_targets: Dictionary = {}
	if target != null and _alive(target) and not _is_safe(target.position):
		visible_targets[boss.target_id] = {"position": target.position,
			"alive": true, "safe": false}
	for i in points.size():
		var spot: Vector2 = points[i]
		var enemy_id: int = new_id()
		var minion = Zombie.new(enemy_id, types[i],
			Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y), -1)
		if not visible_targets.is_empty():
			minion.receive_pack_alert(boss.target_id, visible_targets)
		zombies[enemy_id] = minion
		raid_minions.append(enemy_id)
	raid_wave = phase
	var active_guards: int = RaidWard.living_count(boss, raid_boss_id,
		raid_minions, zombies)
	events.append({"type": "raid_reinforcements", "id": boss.id,
		"x": boss.position.x, "z": boss.position.z,
		"phase": phase, "count": points.size(), "guards": active_guards,
		"reduction_percent": RaidWard.reduction_percent(active_guards)})


func _clear_raid_minions() -> void:
	for enemy_id in raid_minions:
		zombies.erase(enemy_id)
	raid_minions.clear()


## Shared by infected melee and telegraphed boss hits, never the PvP
## damage branch. Weapon and group are rechecked at hit time.
func _infected_damage_for(victim: Player, armored_damage: float) -> float:
	return GuardianTaunt.brace_damage(armored_damage, victim.guardian_brace,
		GuardianTaunt.melee_equipped(victim.inventory),
		parties.members_of(victim.id).size() >= 2)


## A telegraphed cone locks the boss position and direction at wind-up.
## No attacker-supplied victim list; dodge, safety and armor are verified at impact.
func _resolve_raid_cone(strike: Dictionary) -> void:
	var boss_id: int = int(strike.get("id", -1))
	var boss = zombies.get(boss_id)
	if boss_id != raid_boss_id or boss == null or not boss.is_alive() or not boss.raid_boss:
		return
	var origin := Vector3(float(strike["x"]), float(strike["y"]), float(strike["z"]))
	var direction := Vector2(float(strike["dx"]), float(strike["dz"]))
	if not origin.is_finite() or not direction.is_finite() or absf(direction.length_squared() - 1.0) > 0.01:
		return
	for survivor in players.values():
		if not _alive(survivor) or _is_safe(survivor.position) or \
				world.zone_at(survivor.position.x, survivor.position.z) < RaidEncounter.MIN_ZONE or \
				not RaidCone.in_sector(origin, direction, survivor.position):
			continue
		if survivor.dodge_immunity > 0.0:
			events.append({"type": "evaded", "peer": survivor.id, "zombie": boss_id})
			continue
		var damage: float = Combat.apply_gear(RaidCone.damage(boss), survivor.inventory)
		damage = _infected_damage_for(survivor, damage)
		var taken: float = survivor.survival.hurt(damage)
		if taken > 0.0:
			_dismount(survivor, true)
		events.append({"type": "hit", "kind": "player", "id": survivor.id,
			"damage": damage, "by": -boss_id})
		if not _alive(survivor):
			_on_player_death(survivor, -boss_id)
	events.append({"type": "raid_cone_struck", "id": boss_id,
		"x": origin.x, "z": origin.z, "dx": direction.x,
		"dz": direction.y, "reach": RaidCone.REACH})


func _resolve_raid_slam(boss_id: int, center: Vector2) -> void:
	var boss = zombies.get(boss_id)
	if boss == null or not boss.is_alive() or not boss.raid_boss:
		return
	# This bonus starts after the real telegraph has resolved, even when
	# every survivor dodged. An unrelated infected cannot trigger it.
	var exposed_seconds: float = RaidRecovery.window_seconds(boss) if boss_id == raid_boss_id else 0.0
	if exposed_seconds > 0.0:
		raid_exposed_until = time + exposed_seconds
	for survivor in players.values():
		if not _alive(survivor) or _is_safe(survivor.position) \
				or world.zone_at(survivor.position.x, survivor.position.z) < RaidEncounter.MIN_ZONE \
				or not RaidEncounter.in_slam(center, survivor.position):
			continue
		if survivor.dodge_immunity > 0.0:
			events.append({"type": "evaded", "peer": survivor.id, "zombie": boss_id})
			continue
		var damage: float = Combat.apply_gear(RaidEncounter.slam_damage(boss), survivor.inventory)
		damage = _infected_damage_for(survivor, damage)
		var taken: float = survivor.survival.hurt(damage)
		if taken > 0.0:
			_dismount(survivor, true)
		events.append({"type": "hit", "kind": "player", "id": survivor.id,
			"damage": damage, "by": -boss_id})
		if not _alive(survivor):
			_on_player_death(survivor, -boss_id)
	events.append({"type": "raid_slam", "id": boss_id,
		"x": center.x, "z": center.y,
		"radius": RaidEncounter.SLAM_RADIUS,
		"exposed_seconds": exposed_seconds})


## Night-only server raids on defended survivors. Neither clients nor
## old persistent-world snapshots get to dictate wave locations or strength.
func _tick_siege_waves() -> void:
	if not WorldCycle.is_night(time) or time - last_siege_time < SiegeWaves.GLOBAL_COOLDOWN:
		return
	if zombies.size() >= SiegeWaves.MAX_ACTIVE_ZOMBIES or barricades.is_empty() or players.is_empty():
		return
	var wall_ids: Array = barricades.keys()
	wall_ids.sort()
	for wall_id in wall_ids:
		if time - float(siege_last_by_wall.get(wall_id, -1000000.0)) < SiegeWaves.WALL_COOLDOWN:
			continue
		var wall: Dictionary = barricades[wall_id]
		for player in players.values():
			if not _alive(player) or _is_safe(player.position):
				continue
			if not SiegeWaves.eligible(wall, player.position, time):
				continue
			var budget: int = mini(SiegeWaves.wave_size(Structures.tier_of(wall)),
				SiegeWaves.MAX_ACTIVE_ZOMBIES - zombies.size())
			var sites: Array[Vector2] = SiegeWaves.spawn_sites(world, wall,
				player.position, budget, rng.randi_range(0, SiegeWaves.SPAWN_ANGLES - 1))
			if sites.is_empty():
				continue
			var target_info: Dictionary = {player.id: {"position": player.position,
				"alive": true, "safe": false}}
			for index in sites.size():
				var at: Vector2 = sites[index]
				var kind := "walker"
				if Structures.tier_of(wall) >= 4 and index == sites.size() - 1:
					kind = "brute"
				elif Structures.tier_of(wall) >= 2 and index % 3 == 2:
					kind = "runner"
				var spawned_id: int = new_id()
				var infected = Zombie.new(spawned_id, kind,
					Vector3(at.x, world.height_at(at.x, at.y), at.y), -1)
				infected.receive_pack_alert(player.id, target_info)
				zombies[spawned_id] = infected
			last_siege_time = time
			siege_last_by_wall[wall_id] = time
			siege_waves_started += 1
			events.append({"type": "siege_started", "id": wall_id,
				"peer": player.id, "x": wall["x"], "z": wall["z"],
				"count": sites.size(), "tier": Structures.tier_of(wall)})
			return # At most one wave per scheduler check.


## Fixed-position corrosive AoE: dodge or walk away during a visible
## 1.4-second telegraph. No target/position/damage comes from the client.
func _resolve_spit_impact(zombie, center: Vector2) -> void:
	if not zombie.is_alive() or zombie.type != "spitter" or not center.is_finite():
		return
	for survivor in players.values():
		if not _alive(survivor) or _is_safe(survivor.position) 				or world.zone_at(survivor.position.x, survivor.position.z) < AcidSpitter.MIN_ZONE 				or not AcidSpitter.hits(center, survivor.position):
			continue
		if survivor.dodge_immunity > 0.0:
			events.append({"type": "evaded", "peer": survivor.id, "zombie": zombie.id})
			continue
		var armor_id: String = survivor.inventory.armor
		var owned: bool = armor_id != "" and survivor.inventory.count(armor_id) > 0
		var impact: float = Combat.apply_gear(float(zombie.data["damage"]), survivor.inventory)
		impact = _infected_damage_for(survivor, impact)
		var applied: float = _hurt_player(survivor, impact)
		if applied > 0.0 and _alive(survivor):
			var wound: float = Combat.infected_wound_amount(
				AcidSpitter.INFECTION_PER_HIT, armor_id, owned, "infection")
			wound = WardenAura.mitigate_wound(wound,
				WardenAura.active_for(survivor, players, parties, world))
			if survivor.survival.add_infection(wound):
				survivor.dirty_character = true
				events.append({"type": "infection", "peer": survivor.id,
					"severity": survivor.survival.infection, "source": "spitter"})
		events.append({"type": "hit", "kind": "player", "id": survivor.id,
			"damage": impact, "by": -zombie.id})
		if not _alive(survivor):
			_on_player_death(survivor, -zombie.id)
	events.append({"type": "spit_impact", "id": zombie.id, "x": center.x,
		"z": center.y, "radius": AcidSpitter.RADIUS})
	# Only dangerous land can hold the hazard. Capacity limits are server
	# owned: a full pool budget skips lingering effects, never the splash.
	if acid_pools.size() < AcidSpitter.MAX_ACTIVE_POOLS 			and world.zone_at(center.x, center.y) >= AcidSpitter.MIN_ZONE 			and not world.is_water(center.x, center.y) and not world.is_safe(center.x, center.y):
		var id: int = new_id()
		var pool: Dictionary = AcidSpitter.make_pool(id, center,
			world.height_at(center.x, center.y), time, zombie.id)
		if not pool.is_empty():
			acid_pools[id] = pool


## Damage from lingering acid is once per second per survivor ACROSS ALL
## active pools; it is not a new attack or a source of loot/experience.
## Existing armor, dodge, group defense, ward and safe zones still apply.
func _tick_acid_pools() -> void:
	if acid_pools.is_empty():
		return
	var pool_ids: Array = acid_pools.keys()
	pool_ids.sort()
	for id in pool_ids:
		var pool: Dictionary = acid_pools[id]
		if AcidSpitter.pool_remaining(pool, time) <= 0.0:
			acid_pools.erase(id)
			continue
		if time < float(pool["next_tick"]):
			continue
		# Skip late intervals rather than applying a burst of backlogged
		# damage after a frame stall.
		pool["next_tick"] = time + AcidSpitter.POOL_TICK_SECONDS
		var center := Vector2(float(pool["x"]), float(pool["z"]))
		# Acid pools corrode player-built defenses, not natural scenery.
		# A global per-wall cooldown prevents overlapping terrain damage.
		for wall_id in barricades.keys():
			var wall: Dictionary = barricades[wall_id]
			var at := Vector2(float(wall["x"]), float(wall["z"]))
			if not AcidSpitter.corrodes_wall(center, at, Structures.RADIUS):
				continue
			if time - float(_acid_wall_last_hit.get(wall_id, -INF)) < AcidSpitter.POOL_TICK_SECONDS:
				continue
			_acid_wall_last_hit[wall_id] = time
			damage_barricade(int(wall_id), AcidSpitter.STRUCTURE_CORROSION_DAMAGE)
		for survivor in players.values():
			if not _alive(survivor) or _is_safe(survivor.position) 					or world.zone_at(survivor.position.x, survivor.position.z) < AcidSpitter.MIN_ZONE 					or not AcidSpitter.hits(center, survivor.position) 					or survivor.dodge_immunity > 0.0:
				continue
			if time - float(_acid_last_hit.get(survivor.id, -INF)) < AcidSpitter.POOL_TICK_SECONDS:
				continue
			var armor_id: String = survivor.inventory.armor
			var owned: bool = armor_id != "" and survivor.inventory.count(armor_id) > 0
			var impact: float = Combat.apply_gear(AcidSpitter.POOL_DAMAGE, survivor.inventory)
			impact = _infected_damage_for(survivor, impact)
			var applied: float = _hurt_player(survivor, impact)
			_acid_last_hit[survivor.id] = time
			if applied > 0.0 and _alive(survivor):
				var wound: float = Combat.infected_wound_amount(
					AcidSpitter.POOL_INFECTION, armor_id, owned, "infection")
				wound = WardenAura.mitigate_wound(wound,
					WardenAura.active_for(survivor, players, parties, world))
				if survivor.survival.add_infection(wound):
					survivor.dirty_character = true
					events.append({"type": "infection", "peer": survivor.id,
						"severity": survivor.survival.infection, "source": "acid_pool"})
			events.append({"type": "hit", "kind": "player", "id": survivor.id,
				"damage": impact, "by": -int(pool["source"])})
			if not _alive(survivor):
				_on_player_death(survivor, -int(pool["source"]))


## Bounded environmental burning: no player damage, global overlap guard,
## cover checks every second, and real kill credit through _damage_target.
func _tick_ember_pools() -> void:
	if ember_pools.is_empty():
		_ember_last_hit.clear()
		return
	var ids: Array = ember_pools.keys()
	ids.sort()
	for field_id in ids:
		var field: Dictionary = ember_pools[field_id]
		if EmberFlask.remaining(field, time) <= 0.0:
			ember_pools.erase(field_id)
			continue
		var caster: Player = players.get(int(field["owner"]))
		if caster == null or not _alive(caster) or _is_safe(caster.position):
			ember_pools.erase(field_id)
			continue
		if time < float(field["next_tick"]):
			continue
		field["next_tick"] = time + EmberFlask.TICK_SECONDS
		var center := Vector2(float(field["x"]), float(field["z"]))
		var candidates: Array = zombies.keys()
		candidates.sort()
		var hits: int = 0
		for target_id in candidates:
			if hits >= EmberFlask.MAX_TARGETS_PER_TICK:
				break
			var infected = zombies.get(target_id)
			if infected == null or not infected.is_alive():
				continue
			if time - float(_ember_last_hit.get(infected.id, -INF)) < EmberFlask.TICK_SECONDS:
				continue
			if not EmberFlask.affects(world, center, infected.position):
				continue
			_ember_last_hit[infected.id] = time
			var burn: float = EmberFlask.DAMAGE_PER_TICK * (
				0.5 if infected.raid_boss else 1.0)
			_damage_target(caster, {"kind": "zombie", "id": infected.id},
				burn, "ranged")
			hits += 1
	if ember_pools.is_empty():
		_ember_last_hit.clear()
	elif _ember_last_hit.size() > 1024:
		for target_id in _ember_last_hit.keys():
			if time - float(_ember_last_hit[target_id]) > EmberFlask.DURATION:
				_ember_last_hit.erase(target_id)


## Single source of truth for infected sight and owner HUD replication.
func _visual_signature_for(player: Player) -> float:
	var armor_id: String = player.inventory.armor
	var owns: bool = armor_id != "" and player.inventory.count(armor_id) > 0
	var stance: float = StealthStance.visual_signature(
		Camouflage.visual_signature(armor_id, owns, player.noise_timer, _alive(player)),
		player.crouching, player.noise_timer, _alive(player))
	var tarp: float = PortableShelter.visual_signature(stance, shelters, player.position, time,
		player.crouching, player.noise_timer, _alive(player))
	return FieldSmoke.signature(tarp, smoke_clouds, player.position, time,
		player.noise_timer, _alive(player))


func get_ai_schedule_stats() -> Dictionary:
	# Server-side only; useful when tuning large encounter performance.
	return last_ai_schedule_stats.duplicate(true)


func get_eqs_replan_stats() -> Dictionary:
	# Server-only profile counters; never serialized or sent to clients.
	return last_eqs_replan_stats.duplicate(true)


## Server-only diagnostic snapshot: steering is never replicated to clients.
func get_crowd_separation_stats() -> Dictionary:
	return last_crowd_separation_stats.duplicate(true)


## Reuse the native pack-neighbor grid to calculate bounded passive steering.
## Nearby active NPCs are obstacles, but ONLY wander/investigate agents receive
## a vector. The normal world collider and combat paths are unchanged.
func _refresh_passive_crowd_separation(cohort: Array) -> void:
	if _pack_spatial_grid == null and ClassDB.class_exists("AIProximityGrid2D"):
		_pack_spatial_grid = ClassDB.instantiate("AIProximityGrid2D")
	var available: bool = _pack_spatial_grid != null \
		and _pack_spatial_grid.has_method("query_separation_batch") \
		and cohort.size() >= AI_CROWD_SEPARATION_MIN \
		and cohort.size() <= AI_CROWD_SEPARATION_MAX
	if not available:
		for infected in cohort:
			infected.set_passive_crowd_separation(Vector2.ZERO)
		_crowd_separation_enabled = false
		last_crowd_separation_stats = {"enabled": false, "population": cohort.size(), "sources": 0}
		return
	var positions := PackedVector2Array()
	var desired_velocities := PackedVector2Array()
	var source_indices := PackedInt32Array()
	var source_agents: Array = []
	for infected in cohort:
		infected.set_passive_crowd_separation(Vector2.ZERO)
		if not infected.is_alive() or not infected.position.is_finite():
			continue
		var index: int = positions.size()
		var here := Vector2(infected.position.x, infected.position.z)
		positions.append(here)
		var desired_velocity := Vector2.ZERO
		var passive: bool = not infected.raid_boss and not infected.perched \
			and (infected.state == Zombie.State.WANDER \
			or infected.state == Zombie.State.INVESTIGATE)
		if passive:
			source_indices.append(index)
			source_agents.append(infected)
			# The engine is stateless; derive only the game's existing passive
			# movement intention. Chase/attack agents remain static obstacles.
			if infected.snared_seconds <= 0.0 and infected.stagger_seconds <= 0.0:
				var goal: Vector2 = infected.wander_target if infected.state == Zombie.State.WANDER \
					else infected.last_known_target
				var toward: Vector2 = goal - here
				if toward.is_finite() and toward.length_squared() > 0.0001:
					var speed_factor: float = 0.4 if infected.state == Zombie.State.WANDER else 0.7
					var speed: float = clampf(float(infected.data["speed"]) * speed_factor, 0.0, 20.0)
					desired_velocity = toward.normalized() * speed
		desired_velocities.append(desired_velocity)
	if source_agents.is_empty():
		_crowd_separation_enabled = false
		last_crowd_separation_stats = {"enabled": false, "population": cohort.size(), "sources": 0}
		return
	var predictive: bool = _pack_spatial_grid.has_method("query_predictive_separation_batch")
	var steering := PackedVector2Array()
	if predictive:
		steering = _pack_spatial_grid.query_predictive_separation_batch(
			positions, desired_velocities, source_indices,
			AI_CROWD_SEPARATION_RADIUS, 3.0, 8, AI_CROWD_LOOKAHEAD_SECONDS)
	if steering.size() != source_agents.size():
		# An older engine (or a rejected predictive request) retains the
		# previously shipped static crowd separation, never an invented force.
		predictive = false
		steering = _pack_spatial_grid.query_separation_batch(
			positions, source_indices, AI_CROWD_SEPARATION_RADIUS, 3.0, 8)
	if steering.size() != source_agents.size():
		_crowd_separation_enabled = false
		last_crowd_separation_stats = {"enabled": false, "population": cohort.size(), "sources": 0}
		return
	for i in range(source_agents.size()):
		source_agents[i].set_passive_crowd_separation(steering[i])
	_crowd_separation_enabled = true
	last_crowd_separation_stats = {"enabled": true, "population": cohort.size(),
		"sources": source_agents.size(), "period_ticks": AI_CROWD_SEPARATION_TICKS,
		"predictive": predictive}


func get_chase_avoidance_stats() -> Dictionary:
	return last_chase_avoidance_stats.duplicate(true)


## ORCA velocity correction for infected chasing a survivor near players. Every alive infected
## within AI_CHASE_AVOIDANCE_NEAR of a living player is an ORCA agent (sorted by id, so the result
## is independent of dictionary order); only out-of-reach CHASE agents get a preferred velocity
## toward their target and receive the correction, which Zombie applies to its flank-pursuit step
## only. Attack, leap/pounce, perch, flank-goal and target logic are untouched.
func _refresh_chase_crowd_avoidance(cohort: Array, info: Dictionary) -> void:
	var active: bool = crowd_avoidance_enabled and CrowdFacade.has_native_crowd()
	if not active and not _chase_avoidance_dirty:
		last_chase_avoidance_stats = {"enabled": false, "agents": 0, "chasers": 0}
		return # Off (flag or no native class): zero per-tick cost, pursuit unchanged.
	var anchors: Array = []
	if active:
		for peer_id in info:
			var entry: Dictionary = info[peer_id]
			if bool(entry["alive"]):
				var p: Vector3 = entry["position"]
				anchors.append(Vector2(p.x, p.z))
	var agents: Array = []
	if active and not anchors.is_empty():
		var near_sq: float = AI_CHASE_AVOIDANCE_NEAR * AI_CHASE_AVOIDANCE_NEAR
		for infected in cohort:
			if not infected.is_alive() or not infected.position.is_finite():
				continue
			var here := Vector2(infected.position.x, infected.position.z)
			for anchor in anchors:
				if here.distance_squared_to(anchor) <= near_sq:
					agents.append(infected)
					break
		agents.sort_custom(func(a, b) -> bool: return int(a.id) < int(b.id))
		if agents.size() > AI_CHASE_AVOIDANCE_MAX_AGENTS:
			agents.resize(AI_CHASE_AVOIDANCE_MAX_AGENTS)
	var chasers: Array = []
	var chaser_slots := PackedInt32Array()
	var positions := PackedVector2Array()
	var preferred := PackedVector2Array()
	var max_speed: float = 0.1
	for infected in agents:
		var here := Vector2(infected.position.x, infected.position.z)
		var want := Vector2.ZERO
		if infected.state == Zombie.State.CHASE and info.has(infected.target_id) \
				and not infected.raid_boss and not infected.perched and not pounces.has(infected.id) \
				and infected.snared_seconds <= 0.0 and infected.stagger_seconds <= 0.0:
			var target_pos: Vector3 = info[infected.target_id]["position"]
			var toward: Vector2 = Vector2(target_pos.x, target_pos.z) - here
			var speed: float = clampf(float(infected.data["speed"]), 0.0, 20.0)
			if toward.length() > float(infected.data["attack_range"]) and speed > 0.0:
				want = toward.normalized() * speed
				max_speed = maxf(max_speed, speed)
				chasers.append(infected)
				chaser_slots.append(positions.size())
		positions.append(here)
		preferred.append(want)
	# Clear every stale correction first; only this refresh's chasers get a new one.
	for infected in cohort:
		infected.set_chase_crowd_correction(Vector2.ZERO)
	_chase_avoidance_dirty = false
	if chasers.size() < 2:
		last_chase_avoidance_stats = {"enabled": active, "agents": agents.size(), "chasers": chasers.size()}
		return
	var result: PackedVector2Array = CrowdFacade.compute_velocities(positions, preferred, preferred,
		AI_CHASE_AVOIDANCE_RADIUS, max_speed, AI_CHASE_AVOIDANCE_HORIZON,
		AI_CHASE_AVOIDANCE_NEIGHBOR_DIST, AI_CHASE_AVOIDANCE_NEIGHBORS, 0.05 * AI_CHASE_AVOIDANCE_TICKS)
	if result.size() != positions.size():
		last_chase_avoidance_stats = {"enabled": false, "agents": agents.size(), "chasers": chasers.size()}
		return
	var corrected := 0
	for k in chasers.size():
		var slot: int = chaser_slots[k]
		var want: Vector2 = preferred[slot]
		var correction: Vector2 = (result[slot] - want) / maxf(want.length(), 0.1)
		if correction.is_finite() and correction.length_squared() > 0.0004:
			chasers[k].set_chase_crowd_correction(correction)
			_chase_avoidance_dirty = true
			corrected += 1
	last_chase_avoidance_stats = {"enabled": true, "agents": agents.size(),
		"chasers": chasers.size(), "corrected": corrected, "period_ticks": AI_CHASE_AVOIDANCE_TICKS}


## Server-only profiling; candidate counts are prefilters, never confirmed hits.
func get_snare_query_stats() -> Dictionary:
	return last_snare_query_stats.duplicate(true)


## Always revalidate a fresh server-owned trap; the native broadphase
## supplies indices only and can never authorize a trap trigger itself.
func _try_trigger_infected_snare(zombie, trap_id: int) -> bool:
	var trap: Dictionary = infected_snares.get(trap_id, {})
	if trap.is_empty() or not InfectedSnare.catches(trap, zombie, time):
		return false
	if not zombie.apply_snare(InfectedSnare.root_duration(zombie)):
		return false
	infected_snares.erase(trap_id)
	events.append({"type": "snare_triggered", "id": trap_id,
		"zombie": zombie.id, "x": trap["x"], "z": trap["z"]})
	return true


## A separate per-tick budget for expensive tactical EQS replans.
## Never throttles zombie.think(), targeting, movement, attack, status or
## authoritative Smart Object lease expiry. On unavailable native API the
## previous full-frequency behavior is retained without guessed masks.
func _budget_eqs_replans(cohort: Array, delta: float) -> void:
	_eqs_tick_budget_active = false
	for agent in cohort:
		agent.flank_replan_allowed = true
		agent.flank_incremental_enabled = false
		agent.flank_tick_budget = null
		agent.flank_step_urgent = false
	var enabled: bool = cohort.size() >= AI_EQS_REPLAN_MIN_POPULATION and \
			cohort.size() <= 4096 and tick_count >= 0 and \
			ClassDB.class_exists("EnvironmentQuery3D") and \
			ClassDB.class_has_method("EnvironmentQuery3D", "schedule_query_mask")
	if not enabled:
		last_eqs_replan_stats = {"enabled": false, "population": cohort.size(),
			"eligible": 0, "granted": 0, "deferred": 0, "urgent": 0}
		return
	# Every active AI query in this large cohort is stepped, never evaluated
	# to completion, on its assigned scheduling phase. Older engines simply
	# follow the preexisting synchronous path.
	var incremental_available: bool = ClassDB.class_has_method(
		"EnvironmentQuery3D", "begin_incremental_top_positions")
	# A single ledger coordinates every query in this authoritative tick.
	# The old per-agent 120us limit remains as an additional safety bound.
	if incremental_available and ClassDB.class_exists("EnvironmentQueryTickBudget"):
		if _eqs_tick_budget == null:
			_eqs_tick_budget = ClassDB.instantiate("EnvironmentQueryTickBudget")
		if _eqs_tick_budget != null and _eqs_tick_budget.has_method("begin_tick"):
			_eqs_tick_budget_active = bool(_eqs_tick_budget.begin_tick(
				tick_count, AI_EQS_GLOBAL_QUOTA_US, AI_EQS_GLOBAL_URGENT_US))
	for agent in cohort:
		agent.flank_incremental_enabled = incremental_available
		agent.flank_tick_budget = _eqs_tick_budget if _eqs_tick_budget_active else null
	var eligible: Array = []
	var urgent := PackedByteArray()
	for agent in cohort:
		if not agent.is_alive() or agent.raid_boss or agent.type == "brute" or \
				agent.state != Zombie.State.CHASE or agent.target_id <= 0:
			continue
		var victim: Player = players.get(agent.target_id)
		if victim == null or not _alive(victim):
			continue
		var here := Vector2(agent.position.x, agent.position.z)
		var destination := Vector2(victim.position.x, victim.position.z)
		var distance: float = here.distance_to(destination)
		if distance < Zombie.FLANK_FROM or distance > Zombie.FLANK_RANGE:
			continue
		# Cached flanks require no new query until a timer/target/movement
		# change (or preempted Smart Object lease) invalidates them.
		var invalid_lease: bool = agent._flank_slot_id_cached > 0 and \
				_flank_slot_reservations != null and \
				_flank_slot_reservations.has_method("get_actor_slot") and \
				int(_flank_slot_reservations.get_actor_slot(agent.id)) != agent._flank_slot_id_cached
		var cache_valid: bool = not invalid_lease and \
				agent._flank_replan_remaining > delta and \
				agent._flank_target_id_cached == agent.target_id and \
				here.distance_squared_to(agent._flank_here_cached) <= 3.24 and \
				destination.distance_squared_to(agent._flank_target_cached) <= 1.0
		if cache_valid:
			continue
		eligible.append(agent)
		agent.flank_step_urgent = invalid_lease
		urgent.append(1 if invalid_lease else 0)
	if eligible.is_empty():
		last_eqs_replan_stats = {"enabled": true, "population": cohort.size(),
			"eligible": 0, "granted": 0, "deferred": 0, "urgent": 0}
		return
	var mask: PackedByteArray = ClassDB.class_call_static("EnvironmentQuery3D",
		"schedule_query_mask", eligible.size(), tick_count, AI_EQS_REPLAN_QUOTA, urgent)
	if mask.size() != eligible.size():
		# Fail open for optional optimization, not for safety/combat.
		last_eqs_replan_stats = {"enabled": false, "population": cohort.size(),
			"eligible": eligible.size(), "granted": eligible.size(), "deferred": 0, "urgent": 0}
		return
	var granted: int = 0
	var urgent_count: int = 0
	for i in range(eligible.size()):
		eligible[i].flank_replan_allowed = mask[i] != 0
		if mask[i] != 0:
			granted += 1
		if urgent[i] != 0:
			urgent_count += 1
	last_eqs_replan_stats = {"enabled": true, "population": cohort.size(),
		"eligible": eligible.size(), "granted": granted,
		"deferred": eligible.size() - granted, "urgent": urgent_count}


## An optional broadphase of *potential* nearby players for passive target
## selection. Threat, forced targets and active combat always receive the
## full authoritative player table. The native query cannot authorize sight,
## hearing, blood scent, safe zones, or an attack.
func get_perception_interest_stats() -> Dictionary:
	return last_perception_interest_stats.duplicate(true)


func _prepare_passive_target_candidates(cohort: Array, info: Dictionary,
		delta: float) -> Dictionary:
	last_perception_interest_stats = {"native": false, "sources": 0,
		"players": 0, "pairs": 0}
	if cohort.size() < AI_PERCEPTION_INTEREST_MIN_NPCS or cohort.size() > 4096 \
			or info.size() < AI_PERCEPTION_INTEREST_MIN_PLAYERS \
			or info.size() > 8192:
		return {}
	if _pack_spatial_grid == null and ClassDB.class_exists("AIProximityGrid2D"):
		_pack_spatial_grid = ClassDB.instantiate("AIProximityGrid2D")
	if _pack_spatial_grid == null or not _pack_spatial_grid.has_method(
			"query_cross_variable_radius_batch"):
		return {}
	var player_ids: Array = []
	var player_sites := PackedVector2Array()
	for id in info:
		var entry: Dictionary = info[id]
		if not bool(entry.get("alive", false)) or bool(entry.get("safe", true)):
			continue
		var player_position: Vector3 = entry.get("position", Vector3.INF)
		if not player_position.is_finite():
			continue
		player_ids.append(id)
		player_sites.append(Vector2(player_position.x, player_position.z))
	if player_sites.is_empty():
		return {}
	var agent_ids: Array = []
	var agent_sites := PackedVector2Array()
	var scan_radii := PackedFloat32Array()
	for zombie in cohort:
		# For these agents, Zombie._select_target() only needs currently
		# eligible survivors inside their lose-leash plus the passive AI LOD
		# far threshold (24m) plus its 4m hysteresis band. Further
		# targets are behaviorally equivalent to infinite nearest distance.
		if not zombie.is_alive() or zombie.raid_boss or zombie.target_id != -1 \
				or zombie.forced_target_seconds > 0.0 or not zombie.threat.is_empty() \
				or (zombie.state != Zombie.State.IDLE \
				and zombie.state != Zombie.State.WANDER \
				and zombie.state != Zombie.State.INVESTIGATE) \
				or zombie.think_timer > delta or not zombie.position.is_finite():
			continue
		var lose: float = float(zombie.data.get("lose", NAN))
		var radius: float = lose + 28.125 # 24m far + 4m hysteresis + float safety.
		if not is_finite(radius) or radius <= 0.0 or radius > 256.0:
			return {} # Avoid silently clipping any agent's detection or LOD.
		agent_ids.append(zombie.id)
		agent_sites.append(Vector2(zombie.position.x, zombie.position.z))
		scan_radii.append(radius)
	if agent_sites.is_empty():
		return {}
	var batches: Array = _pack_spatial_grid.query_cross_variable_radius_batch(
		agent_sites, scan_radii, player_sites)
	if batches.size() != agent_sites.size():
		return {}
	# Fail atomically: no partial player tables reach Zombie.think() if an
	# outdated native module returns malformed indices.
	for nearby_indices in batches:
		for index in nearby_indices:
			if index < 0 or index >= player_ids.size():
				return {}
	var relevant: Dictionary = {}
	var total_pairs := 0
	for i in range(agent_ids.size()):
		var per_agent: Dictionary = {}
		for index in batches[i]:
			var pid: int = int(player_ids[index])
			per_agent[pid] = info[pid] # Reuse server-authorized metadata exactly.
			total_pairs += 1
		relevant[agent_ids[i]] = per_agent
	last_perception_interest_stats = {"native": true, "sources": agent_ids.size(),
		"players": player_sites.size(), "pairs": total_pairs}
	return relevant


func _tick_zombies(delta: float) -> void:
	var info: Dictionary = {}
	# Day/night and detection multipliers are global for this server tick.
	# Reuse each survivor's server-verified status for noise, firelight and
	# blood scent; those checks were previously repeated several times.
	var night: bool = WorldCycle.is_night(time)
	var notice: float = WorldCycle.notice_multiplier(time)
	for player in players.values():
		var alive: bool = _alive(player)
		var safe: bool = _is_safe(player.position)
		var weather_here: Dictionary = Weather.conditions(
			world, player.position.x, player.position.z, time)
		info[player.id] = {"position": player.position, "alive": alive,
			"health_fraction": player.survival.health / maxf(1.0, player.survival.max_health),
			"safe": safe, "noise": player.noise_radius if player.noise_timer > 0.0 else 0.0,
			"wind": Weather.wind_at(world, player.position.x, player.position.z, time),
			"notice_multiplier": notice,
			"weather_sight": Weather.sight_multiplier(weather_here),
			"firelight": maxf(BikeLantern.reveal_radius(player.inventory, player.mounted,
				alive, night, player.bike_lamp_enabled),
				maxf(CampfireThreat.reveal_radius(campfires, player.position, time, night),
					HandFlare.infected_radius(player.flare_seconds, alive, night, safe))),
			"visual_signature": _visual_signature_for(player),
			# Only actual server wounds contribute; never trust client input.
			"scent": BloodScent.detection_radius(player.survival.bleeding,
				alive, safe, FieldScentMask.active(player.survival))}
	# One server-owned claim table for the entire infected pack; simulation
	# delta expires abandoned leases, including dead and despawned agents.
	if _flank_slot_reservations == null:
		_flank_slot_reservations = ClassDB.instantiate("SmartObjectSlotReservations") \
			if ClassDB.class_exists("SmartObjectSlotReservations") else FlankSlotReservations.new()
	_flank_slot_reservations.advance_time(delta)
	# Activate spawns near players and put far-away zombies to sleep.
	if tick_count % 20 == 1:
		_manage_zombie_population()
	var stagger_decisions: bool = zombies.size() >= AI_STAGGER_MIN_POPULATION
	if stagger_decisions and _ai_update_scheduler == null and ClassDB.class_exists("AIUpdateScheduler"):
		_ai_update_scheduler = ClassDB.instantiate("AIUpdateScheduler")
		if _ai_update_scheduler != null:
			_ai_update_scheduler.set_slots_per_cycle(AI_STAGGER_SLOTS)
	stagger_decisions = stagger_decisions and _ai_update_scheduler != null
	var phase_due := 0
	var phase_deferred := 0
	# Every fourth of a second alert only idle, non-raid infected within
	# hearing range. Active chases and combat threat always take priority.
	if tick_count % 5 == 0 and not decoys.is_empty():
		_alert_noise_decoys()
	# The optional native batch computes one phase mask for the exact snapshot
	# of infected iterated below. Masks use array indices, never client IDs.
	# Older engines or cohorts above the safety cap use the scalar native API.
	var ai_cohort: Array = zombies.values()
	var passive_player_interest: Dictionary = _prepare_passive_target_candidates(
		ai_cohort, info, delta)
	_budget_eqs_replans(ai_cohort, delta)
	# A single native 3x3-cell query every five server ticks feeds gentle
	# steering for noncombat infected only. Clear stale vectors immediately
	# when the crowd falls below the large-group threshold.
	if tick_count % AI_CROWD_SEPARATION_TICKS == 0 \
			or (_crowd_separation_enabled and (ai_cohort.size() < AI_CROWD_SEPARATION_MIN \
			or ai_cohort.size() > AI_CROWD_SEPARATION_MAX)):
		_refresh_passive_crowd_separation(ai_cohort)
	# Native ORCA correction for chasing packs near players (flag + native class gated).
	if tick_count % AI_CHASE_AVOIDANCE_TICKS == 0:
		_refresh_chase_crowd_avoidance(ai_cohort, info)
	# Snapshot trap order once and use source-to-target spatial hashing.
	# Exact trap rules remain in _try_trigger_infected_snare(), and removed
	# traps are ignored when later NPCs encounter the same index.
	var snare_ids: Array = []
	var snare_batches: Array = []
	var snare_batch_used := false
	if ai_cohort.size() >= AI_SNARE_BROADPHASE_MIN_NPCS \
			and ai_cohort.size() <= AI_SNARE_BROADPHASE_MAX_NPCS \
			and infected_snares.size() >= AI_SNARE_BROADPHASE_MIN_TRAPS \
			and infected_snares.size() <= InfectedSnare.MAX_GLOBAL:
		if _pack_spatial_grid == null and ClassDB.class_exists("AIProximityGrid2D"):
			_pack_spatial_grid = ClassDB.instantiate("AIProximityGrid2D")
		if _pack_spatial_grid != null and _pack_spatial_grid.has_method("query_cross_radius_batch"):
			var sources := PackedVector2Array()
			var targets := PackedVector2Array()
			for zombie in ai_cohort:
				sources.append(Vector2(zombie.position.x, zombie.position.z))
			for trap_id in infected_snares:
				var trap: Dictionary = infected_snares[trap_id]
				snare_ids.append(trap_id)
				targets.append(Vector2(float(trap["x"]), float(trap["z"])))
			# Expand candidate radius by 1mm for float32/float64 parity.
			# The authoritative InfectedSnare.catches() still uses 1.35m.
			snare_batches = _pack_spatial_grid.query_cross_radius_batch(
				sources, targets, InfectedSnare.TRIGGER_RADIUS + 0.001, 2.0)
			snare_batch_used = snare_batches.size() == ai_cohort.size()
	var snare_candidates := 0
	if snare_batch_used:
		for candidates in snare_batches:
			snare_candidates += candidates.size()
	last_snare_query_stats = {"native": snare_batch_used, "population": ai_cohort.size(),
		"traps": infected_snares.size(), "candidates": snare_candidates}
	var due_mask := PackedByteArray()
	if stagger_decisions and _ai_update_scheduler.has_method("get_due_mask") \
			and ai_cohort.size() <= AI_BATCH_MAX_SIZE:
		var cohort_ids := PackedInt64Array()
		cohort_ids.resize(ai_cohort.size())
		for i in range(ai_cohort.size()):
			cohort_ids[i] = int(ai_cohort[i].id)
		due_mask = _ai_update_scheduler.get_due_mask(cohort_ids, tick_count)
	var batch_used: bool = stagger_decisions and not due_mask.is_empty() \
		and due_mask.size() == ai_cohort.size()
	var eqs_cpu_us: int = 0
	var eqs_scored_candidates: int = 0
	var eqs_timed_steps: int = 0
	# Construct once only if a real chase reaches a stuck wall. The same
	# immutable grid serves all infected in this server tick.
	var wall_attack_index: Dictionary = {}
	var wall_attack_queries: int = 0
	var wall_attack_matches: int = 0
	for i in range(ai_cohort.size()):
		var zombie = ai_cohort[i]
		zombie.flank_reservations = _flank_slot_reservations
		# Only candidate pairs reach the unchanged authoritative narrowphase.
		# Stable trap-index order preserves the one-shot winner when two NPCs
		# enter a trap simultaneously. Old engines keep the exact full scan.
		if snare_batch_used:
			var nearby_trap_indices: PackedInt32Array = snare_batches[i]
			for trap_index in nearby_trap_indices:
				if _try_trigger_infected_snare(zombie, int(snare_ids[trap_index])):
					break
		else:
			for trap_id in infected_snares.keys():
				if _try_trigger_infected_snare(zombie, int(trap_id)):
					break
		if zombie.perched:
			_tick_percher(zombie)
			continue
		if pounces.has(zombie.id) or _maybe_start_pounce(zombie, delta):
			_tick_pounce(zombie, delta)
			continue
		# Only the optional expensive target scan is staggered. Zombie.think()
		# still runs every frame: pursuit, attacks, status effects and timers
		# cannot be postponed by this optimization.
		zombie.ai_selection_allowed = true
		if stagger_decisions and zombie.think_timer <= delta:
			# Cached native decision is identical to the per-agent scalar hash.
			# Urgent first contact, taunts and combat threats still bypass this
			# optional gate inside Zombie.think(), as before this change.
			if batch_used:
				zombie.ai_selection_allowed = due_mask[i] != 0
			else:
				zombie.ai_selection_allowed = _ai_update_scheduler.is_due(zombie.id, tick_count)
			if zombie.ai_selection_allowed:
				phase_due += 1
			else:
				phase_deferred += 1
		# Only an unengaged passive agent uses the conservative spatial
		# candidate table; active targets and combat keep the exact full info.
		var perception_info: Dictionary = info
		if zombie.target_id == -1 and zombie.forced_target_seconds <= 0.0 \
				and zombie.threat.is_empty() and not zombie.raid_boss \
				and (zombie.state == Zombie.State.IDLE \
				or zombie.state == Zombie.State.WANDER \
				or zombie.state == Zombie.State.INVESTIGATE):
			perception_info = passive_player_interest.get(zombie.id, info)
		var result: Dictionary = zombie.think(world, perception_info, delta, rng)
		# These are authoritative native scorer timings only; never count
		# script movement, physics, sleep, networking or claim handling.
		eqs_cpu_us += zombie.flank_last_step_us
		eqs_scored_candidates += zombie.flank_last_step_candidates
		eqs_timed_steps += zombie.flank_last_timed_steps
		if zombie.consume_howl():
			_howl(zombie, info)
		# Zombies chip away at obstacles only while actually stuck pursuing
		# a survivor. No instantaneous destruction or client damage commands.
		if zombie.stuck_time >= 0.12 and zombie.target_id != -1 and zombies.has(zombie.id):
			var chase_target: Player = players.get(zombie.target_id)
			if chase_target != null and _alive(chase_target):
				var here := Vector2(zombie.position.x, zombie.position.z)
				var toward := Vector2(chase_target.position.x, chase_target.position.z) - here
				if toward.length_squared() > 0.01:
					if wall_attack_index.is_empty():
						wall_attack_index = ZombieWallAttackGrid.build(barricades)
					var nearby_walls: Array[int] = ZombieWallAttackGrid.candidates(
						wall_attack_index, here, toward, Structures.ZOMBIE_REACH)
					wall_attack_queries += 1
					wall_attack_matches += nearby_walls.size()
					for wall_id in nearby_walls:
						# An earlier infected may have demolished a wall during
						# this tick; never attack the stale indexed ID.
						if not barricades.has(wall_id):
							continue
						var damage: float = float(zombie.data["damage"]) * delta * 2.0
						if damage > 0.0 and is_finite(damage):
							_wall_infected_attack_until[wall_id] = time + WALL_ATTACK_WARNING_SECONDS
							damage_barricade(wall_id, damage)
						break
		if result.has("spit_warning"):
			events.append({"type": "spit_warning", "id": zombie.id,
				"x": float(result["x"]), "z": float(result["z"]),
				"seconds": AcidSpitter.WINDUP_SECONDS,
				"radius": AcidSpitter.RADIUS})
			continue
		if result.has("spit_impact"):
			_resolve_spit_impact(zombie, Vector2(float(result["x"]), float(result["z"])))
			continue
		if result.has("hit"):
			var victim: Player = players.get(result["hit"])
			if victim != null and _alive(victim):
				# Independently verify that server-resolved claws still have a
				# clear path BEFORE parry, plates, intercept or wound effects.
				# A last-moment obstruction cannot consume defensive resources.
				if not InfectedMeleeCover.clear_attack(
						world, zombie.position, victim.position, zombie.raid_boss):
					continue
				# An active dodge avoids infected wounds; normal PvP attacks still land.
				if victim.dodge_immunity > 0.0:
					events.append({"type": "evaded", "peer": victim.id, "zombie": zombie.id})
					continue
				if _try_guardian_intercept(victim, zombie, float(result["damage"])):
					continue
				var parried: bool = MeleeParry.can_block(victim, zombie)
				if parried:
					victim.parry_window = 0.0
					zombie.attack_timer = maxf(zombie.attack_timer, MeleeParry.STAGGER_SECONDS)
					ParryRiposte.arm(victim, zombie)
					events.append({"type": "parried", "peer": victim.id, "zombie": zombie.id})
				var armor_id: String = victim.inventory.armor
				var armor_owned: bool = armor_id != "" and victim.inventory.count(armor_id) > 0
				var damage: float = Combat.apply_gear(float(result["damage"]), victim.inventory)
				damage = _infected_damage_for(victim, damage)
				if parried:
					damage *= MeleeParry.DAMAGE_FACTOR
				# Only ordinary confirmed claws consume this plate. Raid boss, acid
				# and player attacks retain their original combat rules.
				if not zombie.raid_boss and damage > 0.0 and FieldArmorPlate.active(
						victim.plated_armor, victim.plated_hits, victim.inventory):
					damage *= FieldArmorPlate.DAMAGE_FACTOR
					victim.plated_hits -= 1
					if victim.plated_hits == 0:
						victim.plated_armor = ""
					victim.dirty_character = true
				# Unlike taunt/intercept, the group wall mitigates melee damage
				# to nearby allies only; never run this for acid, AoE or PvP.
				var wall_guardian: int = PartyShieldWall.protector_for(
					victim, players, parties, world)
				if wall_guardian > 0 and damage > 0.0:
					var reduced: float = PartyShieldWall.mitigate(damage, zombie.raid_boss)
					events.append({"type": "party_shield_wall_block",
						"peer": victim.id, "by": wall_guardian,
						"prevented": maxf(0.0, damage - reduced)})
					damage = reduced
				var applied: float = _hurt_player(victim, damage)
				# Only real carried armor protects from infected secondary wounds.
				# PvP bleeding continues to follow its ordinary rules.
				var wound_bleeding: float = Combat.infected_wound_amount(
					float(Defs.ZOMBIE_BLEEDING_PER_HIT.get(zombie.type, 0.0)),
					armor_id, armor_owned, "bleeding")
				var wound_infection: float = Combat.infected_wound_amount(
					float(Defs.ZOMBIE_INFECTION_PER_HIT.get(zombie.type, 0.0)),
					armor_id, armor_owned, "infection")
				if parried:
					wound_bleeding *= MeleeParry.WOUND_FACTOR
					wound_infection *= MeleeParry.WOUND_FACTOR
				# Nearby living party guardians wearing BOTH earned relic pieces
				# provide a single nonstacking PvE wound ward. PvP is untouched.
				var warded: bool = WardenAura.active_for(victim, players, parties, world)
				wound_bleeding = WardenAura.mitigate_wound(wound_bleeding, warded)
				wound_infection = WardenAura.mitigate_wound(wound_infection, warded)
				# Apply only to infected melee; not environmental poison or PvP.
				wound_infection = WoundSealant.mitigate(wound_infection,
					victim.wound_seal_seconds)
				if applied > 0.0 and _alive(victim) and victim.survival.add_bleeding(wound_bleeding):
					victim.dirty_character = true
					events.append({"type": "bleeding", "peer": victim.id,
						"severity": victim.survival.bleeding, "source": zombie.type})
				var trauma: float = float(Defs.ZOMBIE_FRACTURE_PER_HIT.get(zombie.type, 0.0))
				if parried:
					trauma *= MeleeParry.WOUND_FACTOR
				if applied > 0.0 and _alive(victim) and victim.survival.add_fracture(trauma):
					victim.dirty_character = true
					events.append({"type": "fracture", "peer": victim.id,
						"severity": victim.survival.fracture, "source": zombie.type})
				if victim.survival.add_infection(wound_infection):
					victim.dirty_character = true
					events.append({"type": "infection", "peer": victim.id,
						"severity": victim.survival.infection, "source": zombie.type})
				events.append({"type": "hit", "kind": "player", "id": victim.id, "damage": damage, "by": -zombie.id})
				if not _alive(victim):
					_on_player_death(victim, -zombie.id)
	last_zombie_wall_query_stats = {"queries": wall_attack_queries,
		"matches": wall_attack_matches, "walls": barricades.size()}
	last_ai_schedule_stats = {
		"enabled": stagger_decisions,
		"population": zombies.size(),
		"slots": AI_STAGGER_SLOTS if stagger_decisions else 1,
		"phase_due": phase_due,
		"phase_deferred": phase_deferred,
		"batch_used": batch_used,
		"batch_size": due_mask.size() if batch_used else 0,
	}
	# Diagnostics cover exactly this complete authoritative infected tick.
	# Urgent work can exceed the eight-regular-request admission budget.
	last_eqs_replan_stats["cpu_us"] = eqs_cpu_us
	last_eqs_replan_stats["scored_candidates"] = eqs_scored_candidates
	last_eqs_replan_stats["timed_steps"] = eqs_timed_steps
	# Additional shared-budget instrumentation is separate from native
	# score-only timings, since sub-microsecond debits round up to 1us.
	last_eqs_replan_stats["global_enabled"] = _eqs_tick_budget_active
	last_eqs_replan_stats["regular_budget_us"] = AI_EQS_GLOBAL_QUOTA_US if _eqs_tick_budget_active else 0
	last_eqs_replan_stats["urgent_budget_us"] = AI_EQS_GLOBAL_URGENT_US if _eqs_tick_budget_active else 0
	last_eqs_replan_stats["global_regular_used_us"] = int(_eqs_tick_budget.get_regular_spent_us()) if _eqs_tick_budget_active else 0
	last_eqs_replan_stats["global_urgent_used_us"] = int(_eqs_tick_budget.get_urgent_spent_us()) if _eqs_tick_budget_active else 0
	last_eqs_replan_stats["global_denied"] = int(_eqs_tick_budget.get_denied_count()) if _eqs_tick_budget_active else 0
	last_eqs_replan_stats["global_regular_steps"] = int(_eqs_tick_budget.get_regular_completed()) if _eqs_tick_budget_active else 0
	last_eqs_replan_stats["global_urgent_steps"] = int(_eqs_tick_budget.get_urgent_completed()) if _eqs_tick_budget_active else 0
	# Real survivors are considered before idle infected investigate remains.
	# Reuse existing investigate_decoy: never replace combat targets or spawn mobs.
	if tick_count % 5 == 0 and not bags.is_empty():
		_alert_corpse_scents()
	# Evaluate real survivors before luring unattended infected toward light.
	# This prevents a campfire from delaying direct player detection.
	if tick_count % 5 == 0 and not campfires.is_empty() and WorldCycle.is_night(time):
		_alert_campfire_lights()
	# Pack communication is authoritative and runs at most four times per second.
	if tick_count % 5 == 0:
		_alert_infected_pack(info)


## Shares target awareness inside a bounded 2D neighborhood. Bucket lookup
## avoids checking every zombie against every other zombie in crowded ruins.
## Reuses one stateless C++ EQS nearest-target query for noise, corpse scent
## and night firelight. World cues are already server-filtered (including TTL).
## The result selects a candidate only; Zombie.investigate_decoy still owns
## state, territory/leash, combat priority and final behavior.
func get_ai_cue_query_stats() -> Dictionary:
	return last_ai_cue_query_stats.duplicate(true)


func _try_native_ai_cues(index: Dictionary, radius: float, channel: String) -> bool:
	last_ai_cue_query_stats = {"native": false, "channel": channel,
		"sources": 0, "cues": 0}
	if zombies.size() < AI_CUE_NATIVE_MIN_NPCS or zombies.size() > 4096:
		return false
	var cues: Array = []
	for bucket in index.values():
		cues.append_array(bucket)
	if cues.size() < AI_CUE_NATIVE_MIN_SOURCES or cues.size() > 8192:
		return false
	if _pack_spatial_grid == null and ClassDB.class_exists("AIProximityGrid2D"):
		_pack_spatial_grid = ClassDB.instantiate("AIProximityGrid2D")
	if _pack_spatial_grid == null or not _pack_spatial_grid.has_method("query_cross_nearest_batch"):
		return false
	var targets := PackedVector2Array()
	var target_ids := PackedInt64Array()
	for cue in cues:
		var x: float = float(cue["x"])
		var z: float = float(cue["z"])
		if not is_finite(x) or not is_finite(z):
			return false
		targets.append(Vector2(x, z))
		target_ids.append(int(cue["id"]))
	var agents: Array = []
	var sources := PackedVector2Array()
	for infected in zombies.values():
		if not infected.is_alive() or infected.raid_boss or not infected.position.is_finite():
			continue
		agents.append(infected)
		sources.append(Vector2(infected.position.x, infected.position.z))
	if sources.is_empty():
		return true # No eligible source may acquire a cue.
	var nearest: PackedInt32Array = _pack_spatial_grid.query_cross_nearest_batch(
		sources, targets, target_ids, radius, radius)
	if nearest.size() != sources.size():
		return false
	# Validate all indices before any zombie is allowed to react: invalid
	# native results cannot cause a partially applied cue followed by fallback.
	for index_id in nearest:
		if index_id < -1 or index_id >= cues.size():
			return false
	for i in range(agents.size()):
		var candidate_index: int = nearest[i]
		if candidate_index == -1:
			continue
		var cue: Dictionary = cues[candidate_index]
		agents[i].investigate_decoy(Vector2(float(cue["x"]), float(cue["z"])))
	last_ai_cue_query_stats = {"native": true, "channel": channel,
		"sources": sources.size(), "cues": cues.size()}
	return true


func _alert_noise_decoys() -> void:
	# One spatial index per four-times-per-second hearing pass, rather than
	# an O(infected * all lures) loop. Never give a decoy active player aggro.
	var buckets: Dictionary = NoiseDecoy.sound_buckets(decoys, time)
	if buckets.is_empty():
		return
	if _try_native_ai_cues(buckets, NoiseDecoy.HEARING_RADIUS, "noise"):
		return
	for infected in zombies.values():
		if not infected.is_alive() or infected.raid_boss:
			continue
		var lure: Dictionary = NoiseDecoy.closest_audible(buckets, infected.position, time)
		if not lure.is_empty():
			infected.investigate_decoy(Vector2(float(lure["x"]), float(lure["z"])))


## Spatial-indexed investigation of confirmed, unlooted fresh corpses.
func _alert_corpse_scents() -> void:
	var scent_index: Dictionary = CorpseScent.buckets(bags, time)
	if scent_index.is_empty():
		return
	if _try_native_ai_cues(scent_index, CorpseScent.RADIUS, "corpse"):
		return
	for infected in zombies.values():
		if not infected.is_alive() or infected.raid_boss:
			continue
		var corpse: Dictionary = CorpseScent.closest(scent_index, infected.position, time)
		if not corpse.is_empty():
			infected.investigate_decoy(Vector2(float(corpse["x"]), float(corpse["z"])))


## Night campfires lure idle infected, but never steal active combat aggro.
func _alert_campfire_lights() -> void:
	var buckets: Dictionary = CampfireThreat.light_buckets(campfires, time, true)
	if buckets.is_empty():
		return
	if _try_native_ai_cues(buckets, CampfireThreat.LURE_RADIUS, "campfire"):
		return
	for infected in zombies.values():
		if not infected.is_alive() or infected.raid_boss:
			continue
		var fire: Dictionary = CampfireThreat.nearest_light(buckets, infected.position)
		if not fire.is_empty():
			infected.investigate_decoy(Vector2(float(fire["x"]), float(fire["z"])))


## A howler's scream wakes every idle infected within its howl radius onto the same survivor.
func _howl(howler, player_info: Dictionary) -> void:
	var radius: float = float(howler.data.get("howl_radius", 40.0))
	var woken := 0
	for other in zombies.values():
		if other.id == howler.id or not other.is_alive():
			continue
		var offset: Vector3 = other.position - howler.position
		offset.y = 0.0
		if offset.length_squared() <= radius * radius and other.receive_pack_alert(howler.target_id, player_info):
			woken += 1
	events.append({"type": "howl", "id": howler.id, "x": howler.position.x, "z": howler.position.z,
		"radius": radius, "woken": woken})


func _alert_infected_pack(player_info: Dictionary) -> void:
	# Freeze the authorized sources *before* notifying any infected. This
	# prevents a source joining the chase from waking a whole crowd at once.
	var alive: Array = []
	var positions := PackedVector2Array()
	var source_indices := PackedInt32Array()
	var alert_sources: Array = []
	for infected in zombies.values():
		if not infected.is_alive():
			continue
		var index: int = alive.size()
		alive.append(infected)
		positions.append(Vector2(infected.position.x, infected.position.z))
		if infected.target_id != -1 and (infected.state == Zombie.State.CHASE or infected.state == Zombie.State.ATTACK):
			var target: Dictionary = player_info.get(infected.target_id, {})
			if not target.is_empty() and bool(target.get("alive", false)) and not bool(target.get("safe", true)):
				source_indices.append(index)
				alert_sources.append(infected)
	last_pack_query_stats = {"native": false, "population": alive.size(),
		"sources": alert_sources.size(), "max_alerts": ZOMBIE_PACK_MAX_ALERTS, "alerts_sent": 0}
	if alert_sources.is_empty():
		return

	# New C++ builds select only the K nearest members in one bounded query.
	# Physics, line-of-sight, safe zones, combat state and territorial checks
	# remain inside the server-owned Zombie.receive_pack_alert().
	if _pack_spatial_grid == null and ClassDB.class_exists("AIProximityGrid2D"):
		_pack_spatial_grid = ClassDB.instantiate("AIProximityGrid2D")
	if _pack_spatial_grid != null and _pack_spatial_grid.has_method("query_nearest_batch") \
			and alive.size() <= 8192 and source_indices.size() <= 1024:
		var batches: Array = _pack_spatial_grid.query_nearest_batch(
			positions, source_indices, ZOMBIE_PACK_ALERT_RADIUS,
			ZOMBIE_PACK_BUCKET_SIZE, ZOMBIE_PACK_MAX_ALERTS)
		if batches.size() == alert_sources.size():
			var sent: int = 0
			for i in range(batches.size()):
				var source = alert_sources[i]
				var neighbor_indices: PackedInt32Array = batches[i]
				for neighbor_index in neighbor_indices:
					var nearby = alive[neighbor_index]
					if nearby.id != source.id and nearby.state != Zombie.State.DEAD:
						if nearby.receive_pack_alert(source.target_id, player_info):
							sent += 1
			last_pack_query_stats["native"] = true
			last_pack_query_stats["alerts_sent"] = sent
			return

	# Stock Godot or older forks: same spatial buckets and the same nearest
	# ranking, keeping the per-source cap independent of the engine binary.
	var buckets: Dictionary = {}
	for index in range(alive.size()):
		var point: Vector2 = positions[index]
		var bucket := Vector2i(floori(point.x / ZOMBIE_PACK_BUCKET_SIZE), floori(point.y / ZOMBIE_PACK_BUCKET_SIZE))
		if not buckets.has(bucket):
			buckets[bucket] = []
		buckets[bucket].append(index)
	var sent: int = 0
	for source_slot in range(source_indices.size()):
		var source = alert_sources[source_slot]
		var source_index: int = source_indices[source_slot]
		var origin: Vector2 = positions[source_index]
		var cell := Vector2i(floori(origin.x / ZOMBIE_PACK_BUCKET_SIZE), floori(origin.y / ZOMBIE_PACK_BUCKET_SIZE))
		var candidates: Array[int] = []
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var members: Array = buckets.get(cell + Vector2i(dx, dz), [])
				for index in members:
					candidates.append(int(index))
		var chosen: PackedInt32Array = PackNeighborSelection.choose(
			positions, source_index, candidates,
			ZOMBIE_PACK_ALERT_RADIUS, ZOMBIE_PACK_MAX_ALERTS)
		for neighbor_index in chosen:
			var nearby = alive[neighbor_index]
			if nearby.id != source.id and nearby.state != Zombie.State.DEAD:
				if nearby.receive_pack_alert(source.target_id, player_info):
					sent += 1
	last_pack_query_stats["alerts_sent"] = sent

func _manage_zombie_population() -> void:
	var active_cells: Dictionary = {}
	var player_positions: Array[Vector2] = []
	for player in players.values():
		if not _alive(player) or not player.position.is_finite():
			continue
		player_positions.append(Vector2(player.position.x, player.position.z))
		var cell := WorldGen.cell_of(player.position.x, player.position.z)
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				active_cells[Vector2i(cell.x + dx, cell.y + dz)] = true
	# Reuse one authoritative index for spawn suppression and unload checks;
	# retain exact 2D world-space radius semantics on cell boundaries.
	# Native Cgame broadphase; stock Godot keeps identical GDScript rules.
	var presence = ClassDB.instantiate("SpatialPointGrid2D") if ClassDB.class_exists("SpatialPointGrid2D") else PlayerPresenceGrid.new()
	presence.rebuild(player_positions)
	var herds_on: bool = herd_simulation_enabled
	if herds_on:
		_tick_herds(player_positions, presence)
	for cell in active_cells:
		var data: Dictionary = world.chunk(cell)
		for spawn in data["spawns"]:
			var state: Dictionary = spawn_state.get(spawn["id"], {"zombie": -1, "next": 0.0})
			spawn_state[spawn["id"]] = state
			if state["zombie"] != -1 or time < float(state["next"]):
				continue
			if presence.any_within(Vector2(spawn["x"], spawn["z"]), 12.0, false):
				continue # Never appear in front of a player.
			var zombie_id := new_id()
			var z := Zombie.new(zombie_id, spawn["type"], Vector3(spawn["x"], world.height_at(spawn["x"], spawn["z"]), spawn["z"]), spawn["id"])
			# Only dangerous-zone ruins can roll a deterministic champion.
			if EliteInfected.is_elite_spawn(int(spawn["id"]),
					world.zone_at(float(spawn["x"]), float(spawn["z"])),
					bool(spawn["ruin"]), world.world_seed) or bool(spawn.get("dungeon_boss", false)):
				z.become_elite() # The guardian of a dungeon's deepest room is always a champion.
			elif not bool(spawn.get("ruin", false)) and TreeAmbush.rolls(int(spawn["id"]),
					world.zone_at(float(spawn["x"]), float(spawn["z"])), world.world_seed):
				var tree: Dictionary = TreeAmbush.tree_near(data["nodes"], float(spawn["x"]), float(spawn["z"]))
				if not tree.is_empty():
					z.perched = true
					z.position = Vector3(float(tree["x"]) + 0.45, world.height_at(float(tree["x"]), float(tree["z"])) + TreeAmbush.PERCH_HEIGHT, float(tree["z"]))
			# WorldGen flags precisely one deepest-room dungeon boss per
			# bunker; keep its identity in server-owned actor metadata so an
			# ordinary elite cannot spoof the story guardian milestone.
			if bool(spawn.get("dungeon_boss", false)):
				z.set_meta("_story_dungeon_guardian", true)
			zombies[zombie_id] = z
			state["zombie"] = zombie_id
	# Batch the proximity checks for living, unprotected infected. One native
	# query processes the whole set instead of crossing the script/C++ boundary
	# once per zombie. Dead/loot-guard/night-horde rules are not changed.
	var gone: Array = []
	var probe_positions := PackedVector2Array()
	var probe_zombie_ids: Array[int] = []
	var probe_spawn_ids: Array[int] = []
	for zombie in zombies.values():
		if not zombie.is_alive():
			gone.append(zombie.id)
			if herds_on and zombie.position.is_finite():
				# A fresh corpse draws distant herds for a couple of minutes.
				_herds.add_attractor("corpse", Vector2(zombie.position.x, zombie.position.z), 1.0, 192.0, 120.0)
		elif zombie.supply_cache_id >= 0 and bags.has(zombie.supply_cache_id):
			continue # Loot guards cannot be unloaded to reset their loot.
		elif not night_horde.is_empty() and night_horde.get("ids", []).has(zombie.id):
			continue # Keep active night-horde participants until the fight ends.
		else:
			probe_positions.append(Vector2(zombie.position.x, zombie.position.z))
			probe_zombie_ids.append(zombie.id)
			probe_spawn_ids.append(zombie.spawn_id)
	var near_players: PackedByteArray = presence.any_within_batch(probe_positions, ZOMBIE_ACTIVE_RADIUS)
	var folds: Dictionary = {} # herd region -> Array of type names (ids visited in cohort order)
	for i in range(probe_zombie_ids.size()):
		if near_players[i] == 0:
			gone.append(probe_zombie_ids[i])
			if spawn_state.has(probe_spawn_ids[i]):
				spawn_state[probe_spawn_ids[i]] = {"zombie": -1, "next": 0.0}
			elif herds_on and _herd_foldable(zombies[probe_zombie_ids[i]]):
				var region: int = _herds.region_of(probe_positions[i])
				if not folds.has(region):
					folds[region] = []
				(folds[region] as Array).append(str(zombies[probe_zombie_ids[i]].type))
	if not folds.is_empty():
		var fold_regions: Array = folds.keys()
		fold_regions.sort()
		var folded := 0
		for region in fold_regions:
			_herds.demote(folds[region], int(region))
			folded += (folds[region] as Array).size()
		last_herd_stats["folded"] = int(last_herd_stats.get("folded", 0)) + folded
	for id in gone:
		zombies.erase(id)
	last_population_query_stats = presence.snapshot()


func get_herd_stats() -> Dictionary:
	var out: Dictionary = last_herd_stats.duplicate(true)
	if _herds != null:
		out["population"] = _herds.stats()
	return out


## Plain free-roaming infected only: spawn-point, loot-guard, elite, raid and perched infected keep
## their existing lifecycle rules.
func _herd_foldable(zombie) -> bool:
	return zombie.spawn_id < 0 and not zombie.elite and not zombie.raid_boss and not zombie.perched \
		and zombie.supply_cache_id < 0 and Defs.ZOMBIES.has(zombie.type)


func _ensure_herds() -> Object:
	if _herds != null:
		return _herds
	_herds = CrowdFacade.make_population_lod()
	var cells: int = int(ceil(2.0 * WorldGen.WORLD_RADIUS / HERD_CELL_SIZE))
	var origin := Vector2(-WorldGen.WORLD_RADIUS, -WorldGen.WORLD_RADIUS)
	_herds.setup(cells, cells, HERD_CELL_SIZE, world.world_seed, origin)
	_herds.set("max_herd_size", 24)
	_herds.set("herd_speed", 3.0) # A shambling migration, slower than a walking survivor.
	_herds.set("promote_radius", HERD_PROMOTE_RADIUS + HERD_CELL_SIZE) # Server pre-filters by herd position.
	_herds.set("max_concrete_agents", 0) # Budget is opened per promotion call.
	_herd_last_time = time
	return _herds


## One herd step per population pass: attractors, migration, then promotion near players.
func _tick_herds(player_positions: Array[Vector2], presence) -> void:
	_ensure_herds()
	var dt: float = clampf(time - _herd_last_time, 0.0, 5.0)
	_herd_last_time = time
	var night: bool = WorldCycle.is_night(time)
	_herds.set_night(night)
	for player in players.values():
		if not _alive(player) or not player.position.is_finite():
			continue
		var at := Vector2(player.position.x, player.position.z)
		if player.noise_timer > 0.0 and player.noise_radius > 0.0:
			# Gunfire carries far through the abstract world. One active signal
			# per living player prevents repeated pulses from growing without
			# bound while the player is moving and making noise.
			var loudness: float = clampf(player.noise_radius / 20.0, 0.2, 3.0)
			var reach: float = maxf(player.noise_radius * 3.0, 96.0)
			if _herds.has_method("set_source_attractor"):
				_herds.call("set_source_attractor", "noise", player.id, at,
					loudness, reach, 20.0)
			else:
				# Older native Cgame builds keep their original signal API.
				_herds.add_attractor("noise", at, loudness, reach, 20.0)
		if night and not _is_safe(player.position):
			var night_ttl: float = maxf(dt, 1.0) * 1.5
			if _herds.has_method("set_source_attractor"):
				_herds.call("set_source_attractor", "night", player.id, at,
					0.5, 256.0, night_ttl)
			else:
				_herds.add_attractor("night", at, 0.5, 256.0, night_ttl)
	var packed := PackedVector2Array(player_positions)
	_herds.tick(dt, packed)
	var promoted := 0
	var rejected := 0
	# Existing global infected cap and the slow-server reinforcement throttle both apply.
	var budget: int = mini(HERD_PROMOTE_PER_PASS, WorldIncidents.MAX_ACTIVE_INFECTED - zombies.size())
	budget = mini(budget, clampi(incident_spawn_cap, 0, HERD_PROMOTE_PER_PASS))
	if budget > 0 and not player_positions.is_empty():
		var regions: Array[int] = []
		var seen_regions: Dictionary = {}
		for herd_id in _herds.herd_ids():
			var herd: Dictionary = CrowdFacade.herd_info(_herds, int(herd_id))
			var pos: Vector2 = herd.get("pos", Vector2.INF)
			if pos.is_finite() and presence.any_within(pos, HERD_PROMOTE_RADIUS, true):
				var region: int = int(herd["region"])
				if not seen_regions.has(region):
					seen_regions[region] = true
					regions.append(region)
		regions.sort()
		for region in regions:
			if budget <= 0:
				break
			_herds.set("max_concrete_agents", int(_herds.get("concrete_count")) + budget)
			var specs: Array = _herds.promote(int(region), packed)
			var back: Array = []
			for spec in specs:
				var type: String = str(spec["type"])
				var spot: Vector2 = spec["position"]
				var spot3 := Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
				# Same spawn rules as spawn points: never in sight range, water or safe ground,
				# and inside the active radius so the new infected is not unloaded straight away.
				if budget <= 0 or not Defs.ZOMBIES.has(type) or world.is_water(spot.x, spot.y) or _is_safe(spot3) \
						or presence.any_within(spot, HERD_MIN_SPAWN_DISTANCE, false) \
						or not presence.any_within(spot, ZOMBIE_ACTIVE_RADIUS - 5.0, true):
					back.append(type)
					continue
				var zombie_id: int = new_id()
				var infected := Zombie.new(zombie_id, type, spot3, -1)
				var heading: Vector2 = spec.get("heading", Vector2.ZERO)
				infected.state = Zombie.State.WANDER
				infected.wander_target = spot + (heading.normalized() * 20.0 if heading.length_squared() > 0.0001 else Vector2.ZERO)
				zombies[zombie_id] = infected
				promoted += 1
				budget -= 1
			if not back.is_empty():
				_herds.demote(back, int(region)) # Conserve the herd: unplaceable agents stay abstract.
				rejected += back.size()
	_herds.set("max_concrete_agents", 0)
	last_herd_stats["enabled"] = true
	last_herd_stats["promoted"] = int(last_herd_stats.get("promoted", 0)) + promoted
	last_herd_stats["rejected"] = int(last_herd_stats.get("rejected", 0)) + rejected
	last_herd_stats["abstract"] = int(_herds.abstract_count())


func _nearest_player_distance(point: Vector2) -> float:
	var best := INF
	for player in players.values():
		if _alive(player):
			best = minf(best, point.distance_to(Vector2(player.position.x, player.position.z)))
	return best


## Periodic server-owned public caches in dangerous PvP zones.
## Random incidents near a survivor outside safe ground: a horde drawn toward them, a guarded
## survivors' cache, or a screamer with an escort. All spawns are server-owned and capped.
func _tick_world_incidents() -> void:
	if time < next_incident_at:
		return
	next_incident_at = time + WorldIncidents.RETRY_SECONDS
	if zombies.size() >= WorldIncidents.MAX_ACTIVE_INFECTED:
		return
	var candidates: Array = []
	for player in players.values():
		if _alive(player) and player.position.is_finite() and not _is_safe(player.position):
			candidates.append(player)
	if candidates.is_empty():
		return
	var target: Player = candidates[rng.randi_range(0, candidates.size() - 1)]
	# The server observes actual nearby infected and survivor condition. Do not
	# spawn fresh waves into a saturated crowd or exceed global entity limits.
	var nearby_threat: int = WorldEncounterDirector.nearby_infected(zombies, target.position)
	var health_ratio: float = target.survival.health / maxf(target.survival.max_health, 1.0)
	var incident_budget: int = WorldEncounterDirector.spawn_budget(
		zombies.size(), nearby_threat, health_ratio,
		world.zone_at(target.position.x, target.position.z))
	# A slow server can suppress *additional* random reinforcements; all
	# existing actors still receive their normal authoritative simulation.
	incident_budget = mini(incident_budget, clampi(incident_spawn_cap, 0, 10))
	if incident_budget == 0:
		return
	var site: Dictionary = WorldIncidents.site_near(world, target.position, rng)
	if site.is_empty():
		return
	var kind: String = WorldIncidents.pick_kind(rng)
	var zone: int = int(site["zone"])
	var center := Vector2(float(site["x"]), float(site["z"]))
	var lure := Vector2(target.position.x, target.position.z)
	var bag_id := -1
	if kind == "cache":
		var loot: Dictionary = Combat.crate_loot(zone, rng)
		loot["silver"] = int(loot.get("silver", 0)) + rng.randi_range(10, 25) * (zone + 1)
		bag_id = _make_bag(Vector3(center.x, float(site["y"]), center.y), loot)
		lure = center # Guards hold the cache instead of hunting.
	var spawned := 0
	for type in WorldEncounterDirector.bounded_roster(
			WorldIncidents.roster(kind, zone, rng), incident_budget):
		if zombies.size() >= WorldIncidents.MAX_ACTIVE_INFECTED:
			break
		var spot: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 7.0)
		if world.is_water(spot.x, spot.y):
			continue
		var enemy_id: int = new_id()
		var enemy = Zombie.new(enemy_id, str(type), Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y), -1)
		enemy.investigate_decoy(lure)
		enemy.investigate_time = 30.0 if kind != "cache" else 600.0
		if bag_id >= 0:
			enemy.supply_cache_id = bag_id
		zombies[enemy_id] = enemy
		spawned += 1
	if spawned == 0 and bag_id < 0:
		return
	next_incident_at = time + WorldEncounterDirector.respite_seconds(
		WorldIncidents.next_delay(rng), nearby_threat, health_ratio)
	events.append({"type": "incident", "kind": kind, "x": center.x, "z": center.y,
		"count": spawned, "zone": zone, "peer": target.id})


func _tick_supply_drop() -> void:
	if time < next_supply_drop_at:
		return
	next_supply_drop_at = time + SupplyDrops.RETRY_SECONDS
	var eligible: Array = []
	for player in players.values():
		if _alive(player) and ZoneRisk.full_loot(world.zone_at(player.position.x, player.position.z)):
			eligible.append(player)
	if eligible.is_empty():
		return
	var first: int = rng.randi_range(0, eligible.size() - 1)
	for offset in eligible.size():
		var player: Player = eligible[(first + offset) % eligible.size()]
		var site: Dictionary = SupplyDrops.site_near(world, player.position, rng)
		if site.is_empty():
			continue
		var bag_id: int = _make_bag(Vector3(float(site["x"]), float(site["y"]), float(site["z"])),
			SupplyDrops.loot_for_zone(int(site["zone"]), rng))
		if bag_id < 0:
			return
		bags[bag_id]["supply_drop"] = true
		bags[bag_id]["expires"] = time + SupplyDrops.LIFETIME_SECONDS
		# Spawn a bounded, collidable, one-time infected escort for this crate.
		# The public bag stays lootable even if no safe guard site exists.
		var guard_ids: Array[int] = _spawn_supply_guards(site, bag_id)
		bags[bag_id]["supply_guard_ids"] = guard_ids
		next_supply_drop_at = time + SupplyDrops.INTERVAL_SECONDS
		events.append({"type": "supply_drop", "id": bag_id, "x": site["x"],
			"z": site["z"], "tier": int(site["zone"]) + 1, "guards": guard_ids.size()})
		return


## Guards patrol toward the crate using the existing investigation state.
## They neither fake a player target nor respawn from world spawn slots.
func _spawn_supply_guards(site: Dictionary, bag_id: int) -> Array[int]:
	var ids: Array[int] = []
	var capacity: int = SupplyDrops.MAX_ACTIVE_INFECTED - zombies.size()
	if capacity <= 0:
		return ids
	var positions: Array[Vector3] = []
	for player in players.values():
		if _alive(player) and player.position.is_finite():
			positions.append(player.position)
	var sites: Array[Dictionary] = SupplyDrops.guard_sites(world, site, positions,
		zombies, capacity, rng.randi_range(0, SupplyDrops.GUARD_ANGLES - 1))
	var target := Vector2(float(site["x"]), float(site["z"]))
	for spot in sites:
		var x: float = float(spot["x"])
		var z: float = float(spot["z"])
		var enemy_id: int = new_id()
		var guard = Zombie.new(enemy_id, str(spot["kind"]),
			Vector3(x, world.height_at(x, z), z), -1)
		guard.investigate_decoy(target)
		guard.supply_cache_id = bag_id
		zombies[enemy_id] = guard
		ids.append(enemy_id)
	return ids


## One short-lived PvPvE hunt at a time. Spawn, expiry and the reward are
## entirely owned by the simulation; no client can request or claim an event.
func _tick_night_horde() -> void:
	if not night_horde.is_empty():
		if time >= float(night_horde["expires"]):
			for id in night_horde["ids"]:
				zombies.erase(int(id)) # Event-specific spawns have no respawn slot.
			events.append({"type": "horde_expired", "x": float(night_horde["x"]),
				"z": float(night_horde["z"])})
			night_horde = {}
			next_horde_at = maxf(next_horde_at, time + NightHorde.RETRY_SECONDS)
		return
	if time < next_horde_at or tick_count % NightHorde.CHECK_EVERY_TICKS != 0:
		return
	next_horde_at = time + NightHorde.RETRY_SECONDS
	if not WorldCycle.is_night(time) or raid_boss_id >= 0 or \
			zombies.size() >= NightHorde.MAX_ACTIVE_INFECTED:
		return
	var eligible: Array = []
	for player in players.values():
		if _alive(player) and player.position.is_finite() and \
				ZoneRisk.full_loot(world.zone_at(player.position.x, player.position.z)):
			eligible.append(player)
	if eligible.is_empty():
		return
	var start: int = rng.randi_range(0, eligible.size() - 1)
	var survivors: Array[Vector3] = []
	for player in players.values():
		if _alive(player) and player.position.is_finite():
			survivors.append(player.position)
	for shift in eligible.size():
		var target: Player = eligible[(start + shift) % eligible.size()]
		var available: int = NightHorde.MAX_ACTIVE_INFECTED - zombies.size()
		var positions: Array[Dictionary] = NightHorde.sites(world, target.position,
			survivors, zombies, available, rng.randi_range(0, NightHorde.ANGLES - 1))
		if positions.size() < 2:
			continue # No one-enemy "horde" or isolated, trivial trophy.
		var ids: Array[int] = []
		var visible: Dictionary = {target.id: {"position": target.position,
			"alive": true, "safe": false}}
		for spawn in positions:
			var x: float = float(spawn["x"])
			var z: float = float(spawn["z"])
			var enemy_id: int = new_id()
			var enemy = Zombie.new(enemy_id, str(spawn["kind"]),
				Vector3(x, world.height_at(x, z), z), -1)
			enemy.receive_pack_alert(target.id, visible)
			zombies[enemy_id] = enemy
			ids.append(enemy_id)
		var zone: int = world.zone_at(target.position.x, target.position.z)
		night_horde = {"ids": ids, "zone": zone,
			"x": target.position.x, "z": target.position.z,
			"expires": time + NightHorde.MAX_DURATION}
		next_horde_at = time + NightHorde.COOLDOWN_SECONDS
		events.append({"type": "horde_started", "x": target.position.x,
			"z": target.position.z, "tier": zone + 1, "count": ids.size()})
		return


## Finite caravan ambushes spawn only during actual cargo transport in a
## dangerous zone. No RPC can request enemies, wave count or threat positions.
func _tick_caravan_ambush() -> void:
	for index in range(caravan_ambushes.size() - 1, -1, -1):
		var wave: Dictionary = caravan_ambushes[index]
		if time < float(wave["expires"]):
			continue
		for id in wave["ids"]:
			zombies.erase(int(id)) # Event enemies never occupy world respawn slots.
		caravan_ambushes.remove_at(index)
	if tick_count % CaravanAmbush.CHECK_EVERY_TICKS != 0 or \
			raid_boss_id >= 0 or not night_horde.is_empty():
		return
	var capacity: int = CaravanAmbush.available(caravan_ambushes, zombies)
	if capacity < 2:
		return
	var survivors: Array[Vector3] = []
	for nearby in players.values():
		if _alive(nearby) and nearby.position.is_finite():
			survivors.append(nearby.position)
	for peer_id in players.keys():
		var player: Player = players[peer_id]
		var route: Dictionary = player.caravan_view
		var cargo: int = player.inventory.count(str(route.get("cargo", ""))) if not route.is_empty() else 0
		if not CaravanAmbush.eligible(world, player.position, route,
				cargo, player.caravan_ambushed, _alive(player)):
			continue
		var positions: Array[Dictionary] = CaravanAmbush.placement(world,
				player.position, survivors, zombies, capacity,
				rng.randi_range(0, NightHorde.ANGLES - 1))
		if positions.size() < 2:
			continue
		var visible := {player.id: {"position": player.position,
			"alive": true, "safe": false}}
		var ids: Array[int] = []
		for spot in positions:
			var x: float = float(spot["x"])
			var z: float = float(spot["z"])
			var enemy_id: int = new_id()
			var enemy = Zombie.new(enemy_id, str(spot["kind"]),
				Vector3(x, world.height_at(x, z), z), -1)
			enemy.receive_pack_alert(player.id, visible)
			zombies[enemy_id] = enemy
			ids.append(enemy_id)
		player.caravan_ambushed = true
		player.dirty_character = true
		caravan_ambushes.append({"ids": ids, "defeated": [], "owner": player.id,
			"route": player.caravan_state.duplicate(true), "deaths": player.deaths,
			"expires": time + CaravanAmbush.LIFETIME_SECONDS})
		events.append({"type": "caravan_ambushed", "peer": player.id,
			"group": parties.group_of(player.id), "count": ids.size(), "zone": world.zone_at(player.position.x,
				player.position.z)})
		return # One encounter per check interval, not an unbounded global burst.


## Build one native XZ spatial hash for every camp alarm ready to scan.
## This is a purely server-owned optimization; CampAlarm.scan still enforces
## fuel, expiration, 2s scan cadence, cooldown and private event limits.
func get_camp_alarm_query_stats() -> Dictionary:
	return last_camp_alarm_query_stats.duplicate(true)


func _native_camp_alarm_counts() -> Dictionary:
	last_camp_alarm_query_stats = {"native": false, "centers": 0, "targets": 0}
	if zombies.size() < 32 or zombies.size() > 8192 or campfires.size() < 4:
		return {}
	if _pack_spatial_grid == null and ClassDB.class_exists("AIProximityGrid2D"):
		_pack_spatial_grid = ClassDB.instantiate("AIProximityGrid2D")
	if _pack_spatial_grid == null or not _pack_spatial_grid.has_method("query_cylinder_counts_batch"):
		return {}
	var ids := PackedInt64Array()
	var centers := PackedVector3Array()
	for id in campfires:
		var fire: Dictionary = campfires[id]
		if CampAlarm.seconds_left(fire, time) <= 0.0 \
				or time < float(fire.get("alarm_next_scan", INF)):
			continue
		var owner: Player = players.get(int(fire.get("alarm_owner", -1)))
		if owner == null or not _alive(owner):
			continue
		var center := Vector3(float(fire.get("x", NAN)),
			float(fire.get("y", NAN)), float(fire.get("z", NAN)))
		if not center.is_finite():
			return {}
		ids.append(int(id))
		centers.append(center)
	if centers.size() < 4 or centers.size() > 4096:
		return {}
	var targets := PackedVector3Array()
	for infected in zombies.values():
		if infected != null and infected.is_alive() and infected.position.is_finite():
			targets.append(infected.position)
	var matches: PackedInt32Array = _pack_spatial_grid.query_cylinder_counts_batch(
		centers, targets, CampAlarm.DETECTION_RADIUS,
		CampAlarm.DETECTION_HEIGHT, CampAlarm.MAX_DETECTED)
	if matches.size() != centers.size():
		return {}
	# Validate the complete native output before any alarm state changes.
	for value in matches:
		if value < 0 or value > CampAlarm.MAX_DETECTED:
			return {}
	var result: Dictionary = {}
	for i in range(ids.size()):
		result[int(ids[i])] = int(matches[i])
	last_camp_alarm_query_stats = {"native": true, "centers": centers.size(),
		"targets": targets.size()}
	return result


func _tick_world(delta: float) -> void:
	for id in fish_traps.keys():
		if time >= float(fish_traps[id]["expires"]):
			fish_traps.erase(id)
	for id in infected_snares.keys():
		if time >= float(infected_snares[id]["expires"]):
			infected_snares.erase(id)
	_tick_supply_drop()
	_tick_night_horde()
	_tick_caravan_ambush()
	_tick_world_incidents()
	_tick_ruin_ambush()
	for id in decoys.keys():
		if time >= float(decoys[id]["expires"]):
			decoys.erase(id)
	for id in smoke_clouds.keys():
		if time >= float(smoke_clouds[id]["expires"]):
			smoke_clouds.erase(id)
		else:
			# Wind advances only server-owned clouds. Clients receive updated
			# positions through ordinary interest-limited world snapshots.
			smoke_clouds[id] = FieldSmoke.drift(smoke_clouds[id],
				world, time, delta)
	for id in shelters.keys():
		if time >= float(shelters[id]["expires"]):
			shelters.erase(id)
	# Snapshot only the count candidates; fuel/weather and alarm cooldown are
	# checked again per live campfire immediately before any notification.
	var alarm_native_counts: Dictionary = _native_camp_alarm_counts()
	for id in campfires.keys():
		var fire: Dictionary = campfires[id]
		if time >= float(fire["expires"]):
			campfires.erase(id)
			continue
		# Weather must be read at the server-owned fire position, not from a client.
		# The normal fuel tick has already advanced the simulation clock.
		var local_weather: Dictionary = Weather.conditions(world,
			float(fire["x"]), float(fire["z"]), time)
		var storm_exposed: float = StormproofBriquette.exposed_seconds(delta, time, fire)
		var extra: float = FieldCampfire.storm_extra_fuel(storm_exposed, local_weather)
		if extra > 0.0:
			fire["expires"] = maxf(time, float(fire["expires"]) - extra)
			if float(fire["expires"]) <= time:
				campfires.erase(id)
				events.append({"type": "campfire_doused", "id": id,
					"x": fire["x"], "z": fire["z"]})
				continue
		# Sampling every two seconds bounds CPU work even with many camps.
		var alarm_owner: int = int(fire.get("alarm_owner", -1))
		var observer: Player = players.get(alarm_owner)
		if observer == null or not _alive(observer):
			continue
		var detected: int = CampAlarm.scan(fire, zombies, time,
			int(alarm_native_counts.get(id, -1)))
		if detected > 0:
			events.append({"type": "camp_alarm", "peer": alarm_owner,
				"group": int(fire.get("alarm_group", 0)),
				"x": float(fire["x"]), "z": float(fire["z"]),
				"count": detected})
	for id in depleted.keys():
		if time >= float(depleted[id]):
			depleted.erase(id)
			world.set_node_depleted(int(id), false)
	for id in resource_hit_progress.keys():
		if time >= float(resource_hit_progress[id]["expires"]):
			depleted[id] = time + float(resource_hit_progress[id]["respawn"])
			world.set_node_depleted(int(id), true)
			resource_hit_progress.erase(id)
	for id in opened_crates.keys():
		if time >= float(opened_crates[id]):
			opened_crates.erase(id)
	for id in bags.keys():
		if time >= float(bags[id]["expires"]):
			bags.erase(id)
	SiegeBlastBrace.sweep(siege_braces, barricades, time)


## Returns the events since the last call and forgets them.
func drain_events() -> Array:
	var result := events
	events = []
	return result


# --- Snapshots --------------------------------------------------------------------------------------------------

## Resolves paid scouting intel for the viewer. A party may relay the
## original scout's signal only while its exact live roster is unchanged.
## The client never supplies a target, source, position, or party membership.
func threat_scan_for(peer_id: int) -> Dictionary:
	var viewer: Player = players.get(peer_id)
	if viewer == null or not _alive(viewer):
		return {}
	var personal: Dictionary = ThreatScan.public_mark(
		viewer.threat_scan, zombies, viewer.position, time)
	if not personal.is_empty():
		return personal
	var group_id: int = parties.group_of(peer_id)
	if group_id <= 0:
		return {}
	var members: Array = parties.members_of(peer_id)
	members.sort()
	if members.size() < 2:
		return {}
	for member_id in members:
		if int(member_id) == peer_id:
			continue
		var scout: Player = players.get(int(member_id))
		if scout == null or not _alive(scout):
			continue
		var state: Dictionary = scout.threat_scan
		if int(state.get("group", 0)) != group_id or state.get("members", []) != members:
			continue
		var shared: Dictionary = ThreatScan.public_mark(
			state, zombies, viewer.position, time)
		if shared.is_empty():
			continue
		shared["shared_by"] = scout.id
		return shared
	return {}


## Build the Replication Graph-style spatial lists just once for a packet
## broadcast. Only transient authoritative server values enter these grids.
func prepare_snapshot_interest() -> bool:
	_snapshot_interest_prepared = false
	_snapshot_player_ids_by_peer.clear()
	_snapshot_zombie_ids_by_peer.clear()
	last_snapshot_interest_stats = {"enabled": false}
	_snapshot_wall_index = BarricadeSnapshotIndex.build(
		barricades, time, _wall_infected_attack_until)
	_snapshot_wall_tick = tick_count
	_snapshot_wall_revision = world_structure_revision
	_snapshot_wall_queries = 0
	if not ClassDB.class_exists("SpatialRelevancyGrid2D"):
		return false
	if _snapshot_players_grid == null:
		_snapshot_players_grid = ClassDB.instantiate("SpatialRelevancyGrid2D")
		_snapshot_zombies_grid = ClassDB.instantiate("SpatialRelevancyGrid2D")
	if _snapshot_players_grid == null or _snapshot_zombies_grid == null:
		return false
	if not _snapshot_players_grid.has_method("query_many") or not _snapshot_zombies_grid.has_method("query_many"):
		return false # A mismatched older Cgame build still uses direct scans.
	var player_ids := PackedInt64Array()
	var player_positions := PackedVector2Array()
	for other in players.values():
		player_ids.append(other.id)
		player_positions.append(Vector2(other.position.x, other.position.z))
	var infected_ids := PackedInt64Array()
	var infected_positions := PackedVector2Array()
	for infected in zombies.values():
		if infected.is_alive():
			infected_ids.append(infected.id)
			infected_positions.append(Vector2(infected.position.x, infected.position.z))
	# A failed/oversized/invalid index cannot hide entities from a client:
	# both actor lists fall back to the original authoritative full scans.
	if not _snapshot_players_grid.rebuild(player_ids, player_positions):
		return false
	if not _snapshot_zombies_grid.rebuild(infected_ids, infected_positions):
		return false
	# Gather all viewer sets with only TWO native calls for the broadcast,
	# instead of two calls for every connected survivor.
	var nearby_players_by_viewer: Array = _snapshot_players_grid.query_many(
		player_positions, Defs.INTEREST_RADIUS)
	var nearby_infected_by_viewer: Array = _snapshot_zombies_grid.query_many(
		player_positions, Defs.INTEREST_RADIUS)
	if (nearby_players_by_viewer.size() != player_ids.size()
			or nearby_infected_by_viewer.size() != player_ids.size()):
		return false # Resource guard: fall back rather than hide entities.
	for i in player_ids.size():
		var peer_id: int = int(player_ids[i])
		_snapshot_player_ids_by_peer[peer_id] = nearby_players_by_viewer[i]
		_snapshot_zombie_ids_by_peer[peer_id] = nearby_infected_by_viewer[i]
	_snapshot_interest_prepared = true
	_snapshot_interest_tick = tick_count
	return true


func finish_snapshot_interest() -> void:
	if not _snapshot_wall_index.is_empty():
		last_snapshot_wall_stats = {"enabled": true,
			"walls": (_snapshot_wall_index["entries"] as Array).size(),
			"cells": (_snapshot_wall_index["tiles"] as Dictionary).size(),
			"queries": _snapshot_wall_queries}
	else:
		last_snapshot_wall_stats = {"enabled": false}
	_snapshot_wall_index.clear()
	_snapshot_wall_tick = -1
	_snapshot_wall_revision = -1
	if _snapshot_interest_prepared:
		last_snapshot_interest_stats = {
			"enabled": true,
			"players": _snapshot_players_grid.get_stats(),
			"zombies": _snapshot_zombies_grid.get_stats(),
		}
	_snapshot_interest_prepared = false
	_snapshot_player_ids_by_peer.clear()
	_snapshot_zombie_ids_by_peer.clear()


## What one player is allowed to know: their own full state and nearby entities.
func snapshot_for(peer_id: int) -> Dictionary:
	var player: Player = players.get(peer_id)
	if player == null:
		return {}
	_refresh_daily(player)
	var here := Vector2(player.position.x, player.position.z)
	var nearby_players: Array = []
	var player_candidates: Array = []
	if (_snapshot_interest_prepared and _snapshot_interest_tick == tick_count
			and _snapshot_player_ids_by_peer.has(peer_id)):
		var player_ids: PackedInt64Array = _snapshot_player_ids_by_peer[peer_id]
		for candidate_id in player_ids:
			var candidate = players.get(candidate_id)
			if candidate != null:
				player_candidates.append(candidate)
	else:
		player_candidates = players.values()
	for other in player_candidates:
		if other.id == peer_id:
			continue
		var p: Vector3 = other.position
		if here.distance_to(Vector2(p.x, p.z)) <= Defs.INTEREST_RADIUS:
			nearby_players.append({"id": other.id, "name": other.name, "x": p.x, "y": p.y, "z": p.z, "yaw": other.yaw,
				"alive": _alive(other), "crouching": other.crouching, "mounted": other.mounted,
				"rafting": other.inventory.count("raft") > 0 and Swimming.is_swimming(world, other.position.x, other.position.z),
				"flare_lit": HandFlare.lit(other.flare_seconds, _alive(other)),
				"bike_panniers": BikeCargo.installed(other.inventory),
				"bike_lamp_lit": BikeLantern.lit(other.inventory, other.mounted,
					_alive(other), WorldCycle.is_night(time), other.bike_lamp_enabled),
				"weapon": other.inventory.weapon,
				"gear": other.inventory.gear.duplicate(), # Worn pieces show on the character for everyone.
				"doing": _public_action(other), # What they are visibly busy with: a pose for everyone else.
				"outlaw": PvpInfamy.is_outlaw(other.pvp_infamy),
				"faction": other.faction, "faction_flagged": other.faction_flagged,
				"guild": {"id": other.guild_id, "name": other.guild_name},
				"pvp_rank": PvPHonor.rank(other.pvp_honor),
				"arena_tier": ArenaRating.tier(other.arena_rating)})
	var nearby_zombies: Array = []
	var party_flank_hint: Dictionary = {}
	var zombie_candidates: Array = []
	if (_snapshot_interest_prepared and _snapshot_interest_tick == tick_count
			and _snapshot_zombie_ids_by_peer.has(peer_id)):
		var infected_ids: PackedInt64Array = _snapshot_zombie_ids_by_peer[peer_id]
		for candidate_id in infected_ids:
			var candidate = zombies.get(candidate_id)
			if candidate != null:
				zombie_candidates.append(candidate)
	else:
		zombie_candidates = zombies.values()
	for zombie in zombie_candidates:
		var p: Vector3 = zombie.position
		if zombie.is_alive() and here.distance_to(Vector2(p.x, p.z)) <= Defs.INTEREST_RADIUS:
			# Only one per-viewer hint. Enemy aggro and party membership are
			# never copied into the public infected entity list.
			if party_flank_hint.is_empty() and PartyFlank.qualifies(
					player, zombie, players, parties, world):
				party_flank_hint = {"zombie": zombie.id,
					"bonus": 10 if zombie.raid_boss else 18}
			nearby_zombies.append({"id": zombie.id, "type": zombie.type, "x": p.x, "y": p.y, "z": p.z, "yaw": zombie.yaw, "hp": zombie.health, "state": zombie.state, "perched": zombie.perched,
					"elite": zombie.elite, "raid_boss": zombie.raid_boss,
					"raid_enraged": zombie.raid_enraged,
					"raid_exposed_seconds": RaidRecovery.remaining(zombie, raid_exposed_until, time) if zombie.id == raid_boss_id else 0.0,
					"raid_ward_guards": RaidWard.living_count(zombie, raid_boss_id, raid_minions, zombies) if zombie.id == raid_boss_id else 0,
					"raid_ward_reduction": RaidWard.reduction_percent(RaidWard.living_count(zombie, raid_boss_id, raid_minions, zombies)) if zombie.id == raid_boss_id else 0,
					"max_hp": float(zombie.data.get("health", zombie.health)),
					"wound_phase": InfectedWounds.phase(zombie),
					"snared_seconds": zombie.snared_seconds,
					"stagger_seconds": zombie.stagger_seconds,
					"melee_blocked": zombie.melee_blocked,
					"resolve_stacks": zombie.stagger_resolve_stacks if zombie.stagger_resolve_seconds > 0.0 else 0,
					"resolve_seconds": zombie.stagger_resolve_seconds,
					"sunder_seconds": SunderMark.remaining(zombie, time)})
	# Replicate only pending, living spit warnings within sight of this
	# survivor. Client visual effects never authorize an actual hit.
	var spit_zones: Array = []
	for infected in zombies.values():
		if infected.type != "spitter" or not infected.is_alive() or not infected.spit_pending:
			continue
		if here.distance_to(infected.spit_center) <= Defs.INTEREST_RADIUS:
			spit_zones.append({"id": infected.id, "x": infected.spit_center.x,
				"y": world.height_at(infected.spit_center.x, infected.spit_center.y),
				"z": infected.spit_center.y, "radius": AcidSpitter.RADIUS,
				"remaining": infected.spit_seconds})
	# Only public position, radius and remaining duration are replicated;
	# source IDs, tick scheduling and player hit cooldowns stay server-only.
	var nearby_acid_pools: Array = []
	for pool in acid_pools.values():
		if AcidSpitter.pool_remaining(pool, time) <= 0.0:
			continue
		if here.distance_to(Vector2(float(pool["x"]), float(pool["z"]))) <= Defs.INTEREST_RADIUS:
			nearby_acid_pools.append({"id": int(pool["id"]),
				"x": float(pool["x"]), "y": float(pool["y"]),
				"z": float(pool["z"]), "radius": AcidSpitter.RADIUS,
				"remaining": AcidSpitter.pool_remaining(pool, time)})
	# Replicate only public position/radius/lifetime, never owner or tick data.
	var nearby_ember_pools: Array = []
	for field in ember_pools.values():
		if EmberFlask.remaining(field, time) > 0.0 and here.distance_to(
				Vector2(float(field["x"]), float(field["z"]))) <= Defs.INTEREST_RADIUS:
			nearby_ember_pools.append(EmberFlask.public_state(field, time))
	# A complete per-broadcast wall index replaces the per-viewer scan of
	# every world structure. Standalone/stale snapshots rebuild once here,
	# preserving the original authoritative state and interest ordering.
	var wall_cache_ready: bool = (_snapshot_wall_tick == tick_count
		and _snapshot_wall_revision == world_structure_revision
		and not _snapshot_wall_index.is_empty()
		and (_snapshot_wall_index["entries"] as Array).size() == barricades.size())
	var wall_index: Dictionary = _snapshot_wall_index if wall_cache_ready else (
		BarricadeSnapshotIndex.build(barricades, time, _wall_infected_attack_until))
	if wall_cache_ready:
		_snapshot_wall_queries += 1
	var owner_base_state: Dictionary = BarricadeSnapshotIndex.private_status(
		wall_index, player.id, player.user_id)
	var nearby_barricades: Array = []
	for wall in BarricadeSnapshotIndex.visible(wall_index, here, Defs.INTEREST_RADIUS):
		var public_wall: Dictionary = Structures.public_state(wall)
		public_wall["blast_brace_seconds"] = maxf(0.0,
			float(siege_braces.get(int(wall["id"]), time)) - time)
		nearby_barricades.append(public_wall)
	var nearby_plots: Array = []
	var viewer_account: String = _market_account(player)
	for plot_id in farm_plots:
		var plot: Dictionary = farm_plots[plot_id]
		var px: float = float(plot["x"])
		var pz: float = float(plot["z"])
		if Vector2(px - player.position.x, pz - player.position.z).length() <= Defs.INTEREST_RADIUS:
			nearby_plots.append({"id": plot_id, "crop": plot["crop"], "x": px, "y": world.height_at(px, pz), "z": pz,
				"progress": Farming.progress(plot, time), "own": str(plot["account"]) == viewer_account,
				"owner": str(plot.get("owner_name", ""))})
	var nearby_campfires: Array = FieldCampfire.visible(campfires,
			player.position, time, Defs.INTEREST_RADIUS)
	var nearby_shelters: Array = PortableShelter.visible(shelters,
			player.position, time, Defs.INTEREST_RADIUS)
	var nearby_snares: Array = InfectedSnare.visible(
		infected_snares, player.position, time, Defs.INTEREST_RADIUS)
	var nearby_fish_traps: Array = ShoreFishTrap.visible(
		fish_traps, player.position, time, Defs.INTEREST_RADIUS)
	# Viewer-only rights let E target owned nets, without revealing account IDs.
	for i in nearby_fish_traps.size():
		var shown_trap: Dictionary = nearby_fish_traps[i]
		var source_trap: Dictionary = fish_traps.get(int(shown_trap["id"]), {})
		shown_trap["own"] = Structures.can_manage(source_trap, peer_id, player.user_id)
		nearby_fish_traps[i] = shown_trap
	var nearby_smoke: Array = FieldSmoke.visible(smoke_clouds,
			player.position, time, Defs.INTEREST_RADIUS)
	var nearby_decoys: Array = []
	for lure in decoys.values():
		if NoiseDecoy.is_audible(lure, player.position, time) or (
				here.distance_to(Vector2(float(lure["x"]), float(lure["z"]))) <= Defs.INTEREST_RADIUS and
				float(lure["expires"]) > time):
			nearby_decoys.append(NoiseDecoy.visible_state(lure, time))
	var nearby_bags: Array = []
	for bag in bags.values():
		if here.distance_to(Vector2(bag["x"], bag["z"])) <= Defs.INTEREST_RADIUS:
			var bag_view: Dictionary = LootRights.visible_state(bag, player, time)
			bag_view["raid"] = bag.has("raid_reserved_until")
			if bool(bag_view["raid"]):
				# Raid contribution entitlement supersedes ordinary party looting.
				bag_view["reserved_seconds"] = RaidLoot.remaining(bag, time)
				bag_view["reserved"] = float(bag_view["reserved_seconds"]) > 0.0
				bag_view["can_loot"] = RaidLoot.can_open(bag, player, time)
				if RaidRoundRobin.active(bag, time):
					var turn: Dictionary = RaidRoundRobin.visible(bag, player, time)
					bag_view["raid_round_robin"] = true
					bag_view["raid_your_turn"] = bool(turn["your_turn"])
					bag_view["raid_turn_seconds"] = float(turn["seconds"])
					bag_view["can_loot"] = bool(bag_view["can_loot"]) and bool(turn["your_turn"])
					# Only the eligible current turn holder sees the real bag choices.
					if bool(bag_view["can_loot"]):
						bag_view["raid_item_choices"] = RaidRoundRobin.choice_ids(bag)
				var ballot: Dictionary = RaidNeedGreed.visible(bag, player, time)
				if not ballot.is_empty():
					bag_view["raid_need_greed"] = ballot
				var core_lock: Dictionary = RaidNeedGreed.protection(bag, player, time)
				if bool(core_lock.get("locked", false)) and bag["items"].size() == 1:
					bag_view["can_loot"] = false
			bag_view["horde_cache"] = bool(bag.get("horde_cache", false))
			bag_view["supply_drop"] = bool(bag.get("supply_drop", false))
			bag_view["corpse_scent"] = CorpseScent.active(bag, time)
			bag_view["guards_remaining"] = SupplyDrops.living_guards(bag, zombies)
			if int(bag_view["guards_remaining"]) > 0:
				bag_view["can_loot"] = false
			nearby_bags.append(bag_view)
	var gone_nodes: Array = []
	for id in depleted:
		gone_nodes.append(id)
	# Share only live strike progress near this viewer. New joiners see the
	# correct rotating marker without scanning full world chunks every tick.
	var nearby_resource_hits: Array = []
	for node_id in resource_hit_progress:
		var progress: Dictionary = resource_hit_progress[node_id]
		if time >= float(progress.get("expires", 0.0)):
			continue
		var point := Vector2(float(progress["x"]), float(progress["z"]))
		if here.distance_squared_to(point) <= 144.0:
			nearby_resource_hits.append({"id": node_id, "hits": int(progress["hits"])})
	var used_crates: Array = []
	for id in opened_crates:
		used_crates.append(id)
	# A player's private raid threat HUD never reveals unrelated hate tables.
	# Compute it only for a visible, live boss and an eligible nearby party.
	var raid_aggro_state: Dictionary = {}
	if raid_boss_id > 0:
		raid_aggro_state = RaidAggroView.for_viewer(
			zombies.get(raid_boss_id), player, players, parties, world)
	var guardian_guarded_seconds: float = 0.0
	var guardian_guarded_by: int = -1
	for supporter in players.values():
		if GuardianIntercept.can_intercept(supporter, player, parties, world):
			if supporter.guard_link_seconds > guardian_guarded_seconds:
				guardian_guarded_seconds = supporter.guard_link_seconds
				guardian_guarded_by = supporter.id
	# The protected survivor sees exactly one nearest legitimate guardian.
	# Unrelated players do not receive party wall IDs or countdowns.
	var wall_guardian_id: int = PartyShieldWall.protector_for(
		player, players, parties, world)
	var wall_guarded_seconds: float = 0.0
	if wall_guardian_id > 0:
		wall_guarded_seconds = players[wall_guardian_id].shield_wall_seconds
	var snapshot := {
		"tick": tick_count, "time": time, "ack": player.last_input_seq,
		"outposts": siege_contracts.public_state(territory.public_state(time, players, parties), time),
		"you": {
			"base_upkeep": owner_base_state,
			"party": _party_state_for(peer_id),
			"raid_aggro": raid_aggro_state,
			"party_flank_hint": party_flank_hint,
			"caravan": player.caravan_view.duplicate(true),
			"caravan_night": NightCaravan.public_state(player.caravan_view, player.caravan_night),
			"equipment_presets": player.equipment_presets.duplicate(true),
			"death_recovery": DeathRecovery.public_mark(bags, player, time),
			"caravan_defended": player.caravan_defended,
			"guild": {"id": player.guild_id, "name": player.guild_name, "rank": player.guild_rank},
			"guild_siege_wins": int(guild_siege_wins.get(player.guild_id, 0)),
			"siege_wins": int(siege_contracts.victories.get(parties.group_of(peer_id), 0)),
			"x": player.position.x, "y": player.position.y, "z": player.position.z, "yaw": player.yaw,
			"health": player.survival.health, "hunger": player.survival.hunger, "thirst": player.survival.thirst,
			"stamina": player.survival.stamina,
			"combat_stress": player.combat_stress,
			"combat_stress_regen": CombatStress.regen_multiplier(player.combat_stress),
			"crouching": player.crouching,
			"mounted": player.mounted, "mount_cooldown": player.mount_cooldown,
			"rafting": player.inventory.count("raft") > 0 and Swimming.is_swimming(world, player.position.x, player.position.z),
			"smoke_cooldown": player.smoke_cooldown,
			"smoke_concealed": FieldSmoke.inside(smoke_clouds, player.position, time),
			"chain_wrap_seconds": player.chain_wrap_seconds,
			"storm_insulator_seconds": player.storm_insulator_seconds,
			"tire_grip_seconds": player.tire_grip_seconds,
			"flash_cooldown": player.flash_cooldown,
			"meal_seconds": player.meal_seconds, "meal_tier": player.meal_tier,
			"ration_seconds": player.ration_seconds, "ration_tier": player.ration_tier,
			"coating_seconds": player.edge_coating_seconds,
			"coating_weapon": player.edge_coating_weapon,
			"alive": _alive(player), "kills": player.kills, "deaths": player.deaths, "zone": player.zone_notice,
			"pvp_infamy": player.pvp_infamy, "outlaw": PvpInfamy.is_outlaw(player.pvp_infamy),
			"combat_tag_seconds": CombatLogout.remaining(player.combat_tag_until, time),
			"recall_seconds": maxf(0.0, float(player.recall.get("until", time)) - time) if not player.recall.is_empty() else 0.0,
			"recall_cooldown": maxf(0.0, player.recall_ready_at - time),
			"duel": _training_snapshot(peer_id),
			"arena_queue": _arena_queue_state(peer_id),
			"self_defense_seconds": PvpInfamy.defense_remaining(
				player.defense_target, player.defense_until, time),
			"pvp_kills": player.pvp_kills, "pvp_honor": player.pvp_honor,
			"pvp_rank": PvPHonor.rank(player.pvp_honor),
			"arena_rating": player.arena_rating, "arena_wins": player.arena_wins,
			"arena_losses": player.arena_losses,
			"arena_tier": ArenaRating.tier(player.arena_rating),
			"action": player.action.duplicate(),
			"ruin_survey": RuinSurvey.public_mark(player.ruin_survey, time, opened_crates),
			"prospect_mark": ProspectingChart.public_mark(
				player.prospect_mark, time, depleted) if _alive(player) else {},
			"threat_scan": threat_scan_for(peer_id),
			"infection": player.survival.infection,
			"food_poisoning": player.survival.food_poisoning,
			"bleeding": player.survival.bleeding,
			"fracture": player.survival.fracture,
			"blood_scent_radius": BloodScent.detection_radius(player.survival.bleeding,
				_alive(player), _is_safe(player.position), FieldScentMask.active(player.survival)),
			"scent_mask_seconds": player.survival.scent_mask_seconds,
			"soft_sole_seconds": player.soft_sole_seconds,
			"exposure": player.survival.exposure,
			"wetness": player.survival.wetness,
			"wading_depth_m": WadingWetness.depth_at(world, player.position),
			"swimming": not player.mounted and Swimming.is_swimming(world, player.position.x, player.position.z),
			"diving": _is_diving(player), "breath": player.breath,
			"warmth_seconds": player.survival.warmth_seconds,
			"campfire_warm": FieldCampfire.has_warmth(campfires, player.position, time),
			"tent_sheltered": PortableShelter.covers(shelters, player.position, time),
			"tent_anchored": StormTarpAnchors.anchored_covers(shelters, player.position, time),
			"tent_camouflaged": PortableShelter.camouflaged(shelters, player.position,
				time, player.crouching, player.noise_timer, _alive(player)),
			"weather": Weather.conditions(world, player.position.x, player.position.z, time),
			"data_layers": data_layers,
			"wind_chill": WindChill.visible(world, player.position, time,
				player.survival.wetness,
				player.inventory.armor if player.inventory.count(player.inventory.armor) > 0 else "",
				FieldCampfire.has_warmth(campfires, player.position, time),
				PortableShelter.covers(shelters, player.position, time)),
			"weather_sight": Weather.sight_multiplier(
				Weather.conditions(world, player.position.x, player.position.z, time)),
			"spore": SporeHazard.status(world, player.position, time,
				player.inventory.armor if player.inventory.count(player.inventory.armor) > 0 else "",
				player.spore_filter_seconds),
			"spore_filter_seconds": player.spore_filter_seconds,
			"wound_seal_seconds": player.wound_seal_seconds,
			"weather_insulation": Weather.protection(
				player.inventory.armor if player.inventory.count(player.inventory.armor) > 0 else ""),
			"lake_drink_cooldown": player.lake_drink_cooldown,
			"rain_cooldown": player.rain_cooldown,
			"spore_sample_cooldown": player.spore_sample_cooldown,
			"combat_energy": player.combat_energy, "skill_cooldown": player.skill_timer,
			"sharpened_hits": player.sharpened_hits if FieldWhetstone.valid_state(
				player.sharpened_weapon, player.sharpened_hits, player.inventory) else 0,
			"sighted_hits": player.sighted_hits if FieldSightingKit.valid_state(
				player.sighted_weapon, player.sighted_hits, player.inventory) else 0,
			"mining_wedge_charges": player.wedge_charges if MiningWedges.valid_state(player.wedge_charges) else 0,
			"plated_hits": player.plated_hits if FieldArmorPlate.valid_state(
				player.plated_armor, player.plated_hits, player.inventory) else 0,
			"guardian_cooldown": player.guardian_timer,
			"guardian_intercept_cooldown": player.guard_link_cooldown,
			"guardian_intercept_seconds": player.guard_link_seconds,
			"shield_wall_seconds": player.shield_wall_seconds,
			"shield_wall_cooldown": player.shield_wall_cooldown,
			"shield_wall_guarded_seconds": wall_guarded_seconds,
			"shield_wall_guarded_by": wall_guardian_id,
			"guardian_counter_seconds": player.guard_counter_seconds,
			"guardian_counter_target": player.guard_counter_target if player.guard_counter_seconds > 0.0 else -1,
			"guardian_intercept_target": player.guard_link_target if player.guard_link_seconds > 0.0 else -1,
			"guardian_guarded_seconds": guardian_guarded_seconds,
			"guardian_guarded_by": guardian_guarded_by,
			"warden_ward": WardenAura.active_for(player, players, parties, world),
			"guardian_brace": player.guardian_brace,
			"dodge_cooldown": player.dodge_timer, "dodge_immunity": player.dodge_immunity,
			"parry_cooldown": player.parry_cooldown, "parry_window": player.parry_window,
			"rage": player.rage, "rage_seconds": player.rage_seconds, "kick_cooldown": player.kick_cooldown,
			"knocked_seconds": player.knocked_seconds,
			"riposte_seconds": player.riposte_seconds,
			"finisher_cooldown": player.finisher_cooldown,
			"arcane_cooldown": player.arcane_cooldown, "ultimate_cooldown": player.ultimate_cooldown,
			"rest_cooldown": player.rest_cooldown,
			"rested_xp_credit": player.rested_xp_credit,
			"practice_branches": CrossTraining.branches_count(player.practice_state, time),
			"deep_practice_branches": DeepPractice.trained_branches(player.deep_practice_state, time),
			"cross_training_active": CrossTraining.branches_count(player.practice_state, time) >= CrossTraining.REQUIRED_BRANCHES,
			"party_aid_cooldown": player.party_aid_timer, "party_feast_cooldown": player.feast_timer,
			"medic_cover_cooldown": player.medic_cover_cooldown,
			"stim_cooldown": player.stim_cooldown, "flare_seconds": player.flare_seconds,
			"weapon": player.inventory.weapon, "armor": player.inventory.armor,
			"visual_signature": _visual_signature_for(player),
			"last_death_full_loot": player.last_death_full_loot,
			"is_night": WorldCycle.is_night(time),
			"gathering_levels": player.progression.levels(), "crafting_level": player.progression.crafting_level(),
			"crafting_xp": player.progression.crafting_xp,
			"fishing_level": player.progression.gathering_level("fishing"),
			"scavenging_level": player.progression.scavenging_level(),
			"scavenging_xp": player.progression.scavenging_xp,
			"combat_levels": player.progression.combat_levels(),
			"focus": int(player.progression.focus),
			"faction": player.faction, "faction_flagged": player.faction_flagged, "faction_points": player.faction_points,
			"faction_unflag_in": maxf(0.0, player.faction_unflag_at - time) if player.faction_unflag_at >= 0.0 else 0.0,
			"weapon_mastery": {"family": Progression.weapon_family(player.inventory.weapon),
				"level": player.progression.weapon_mastery_level(player.inventory.weapon),
				"fame": int(player.progression.weapon_fame.get(Progression.weapon_family(player.inventory.weapon), 0)),
				"item_power": Defs.item_power(player.inventory.weapon) + player.progression.mastery_item_power(player.inventory.weapon)},
			"contract": player.contract_state.duplicate(true),
			"story": StoryCampaign.public_state(player.story_state),
			"story2": StoryChapterTwo.public_state(player.story2_state) \
				if int(player.story_state.get("stage", 0)) == StoryCampaign.LAST_STAGE else {},
			"story3": StoryChapterThree.public_state(player.story3_state) \
				if int(player.story2_state.get("stage", 0)) == StoryChapterTwo.LAST_STAGE else {},
			"discovered_site_ids": WorldDiscovery.ids(player.discovered_sites),
			"discovered_count": player.discovered_sites.size(),
			"daily_bounty": player.daily_bounty.duplicate(true),
			"daily_description": DailyBounties.description(player.daily_bounty, DailyBounties.utc_day()),
			"daily_utc_day": DailyBounties.utc_day(),
			"renown": player.renown,

			"renown_rank": Reputation.title(player.renown),
			"vendor_discount": Reputation.discount_percent(player.renown),
			"regional_trade": RegionalTrade.public_offer(world, player.position),
			"renown_next": Reputation.next_threshold(player.renown),
			"on_road": RoadTravel.on_road(world, player.position),
			"storm_mud_factor": StormMud.factor(world, player.position, time, player.mounted),
			"carry_kg": player.inventory.total_weight(),
			"trail_pack_kg": TrailBackpack.support_kg(player.inventory, player.mounted),
			"cargo_factor": BikeCargo.movement_factor(player.inventory,
				player.skills.bonus("carry_capacity"), player.mounted),
			"bike_cargo_kg": BikeCargo.SUPPORTED_KG if player.mounted and BikeCargo.installed(player.inventory) else 0.0,
			"bike_service_meters": player.bike_service_meters,
			"bike_integrity": player.bike_integrity,
			"bike_lamp_lit": BikeLantern.lit(player.inventory, player.mounted,
				_alive(player), WorldCycle.is_night(time), player.bike_lamp_enabled),
			"bike_lamp_enabled": player.bike_lamp_enabled,
			"max_health": player.survival.max_health,
			"skill_cd": player.skill_timer, "ultimate_cd": player.ultimate_timer, "gear_cd": player.gear_skill_timers.duplicate(),
			"guard_s": player.survival.guard_seconds, "regen_s": player.survival.regen_seconds, "sprint_s": player.sprint_buff_seconds,
			"speed_bonus": player.skills.bonus("move_speed") + player.sprint_buff_speed, "carry_bonus": player.skills.bonus("carry_capacity"),
		},
		"players": nearby_players, "zombies": nearby_zombies, "bags": nearby_bags,
		"spit_zones": spit_zones, "acid_pools": nearby_acid_pools,
		"ember_pools": nearby_ember_pools,
		"farm_plots": nearby_plots, "barricades": nearby_barricades, "campfires": nearby_campfires,
		"shelters": nearby_shelters,
		"decoys": nearby_decoys, "smoke_clouds": nearby_smoke,
		"fish_traps": nearby_fish_traps,
		"infected_snares": nearby_snares,
		"depleted": gone_nodes, "crates_used": used_crates,
		"resource_hits": nearby_resource_hits,
	}
	# A lightning warning is public only to nearby survivors, not to global
	# clients watching a different part of the island.
	if not lightning_pending.is_empty():
		var lightning_at := Vector2(float(lightning_pending["x"]),
			float(lightning_pending["z"]))
		if here.distance_to(lightning_at) <= Defs.INTEREST_RADIUS:
			snapshot["lightning_telegraph"] = lightning_pending.duplicate(true)
	# Send a ground telegraph only to survivors close enough to see it.
	# The server remains the sole authority on the slam center and deadline.
	if not raid_pending_slam.is_empty():
		var warning_at := Vector2(float(raid_pending_slam["x"]),
			float(raid_pending_slam["z"]))
		if here.distance_to(warning_at) <= Defs.INTEREST_RADIUS:
			snapshot["raid_telegraph"] = {"id": int(raid_pending_slam["id"]),
				"x": warning_at.x,
				"y": world.height_at(warning_at.x, warning_at.y),
				"z": warning_at.y, "radius": RaidEncounter.SLAM_RADIUS,
				"until": float(raid_pending_slam["at"])}
			# The countdown area is public; live interrupt progress is party-only.
			var interrupt: Dictionary = RaidInterrupt.public_progress(
				raid_pending_slam, time, parties.group_of(peer_id))
			if not interrupt.is_empty():
				snapshot["raid_interrupt"] = interrupt
	if not raid_pending_cone.is_empty():
		var cone_at := Vector2(float(raid_pending_cone["x"]), float(raid_pending_cone["z"]))
		if here.distance_to(cone_at) <= Defs.INTEREST_RADIUS:
			snapshot["raid_cone_telegraph"] = {"id": int(raid_pending_cone["id"]),
				"x": cone_at.x, "y": float(raid_pending_cone["y"]),
				"z": cone_at.y, "dx": float(raid_pending_cone["dx"]),
				"dz": float(raid_pending_cone["dz"]), "reach": RaidCone.REACH,
				"half_angle": RaidCone.HALF_ANGLE_DEGREES,
				"until": float(raid_pending_cone["at"])}
	# The skill sheet is small, but snapshots can be lost: resend it when it changed and every few seconds.
	if player.dirty_skills or time - player.skills_sent_at > SNAPSHOT_REPEAT_SECONDS:
		var sheet: Dictionary = player.skills.to_dict()
		sheet["points"] = player.skills.points_available()
		snapshot["skills"] = sheet
		player.skills_sent_at = time
		player.dirty_skills = false
	# Snapshots are unreliable, so a change that was reported once could be lost for good: repeat the
	# containers every few seconds as well as when they change.
	if player.dirty_inventory or time - player.inventory_sent_at > SNAPSHOT_REPEAT_SECONDS:
		snapshot["inventory"] = player.inventory.to_dict()
		player.dirty_inventory = false
		player.inventory_sent_at = time
	if player.dirty_stash or time - player.stash_sent_at > SNAPSHOT_REPEAT_SECONDS:
		snapshot["stash"] = player.stash.to_dict()
		player.dirty_stash = false
		player.stash_sent_at = time
	return snapshot
