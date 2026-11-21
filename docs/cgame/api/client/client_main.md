# client_main.gd

> (no header comment)

`res://scripts/client/client_main.gd`

## Constants

- `const ShaderWarmup = preload("res://scripts/client/shader_warmup.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")`
- `const EmberFlask = preload("res://scripts/shared/ember_flask.gd")`
- `const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")`
- `const Camouflage = preload("res://scripts/shared/camouflage.gd")`
- `const StealthStance = preload("res://scripts/shared/stealth_stance.gd")`
- `const FieldSmoke = preload("res://scripts/shared/field_smoke.gd")`
- `const BloodScent = preload("res://scripts/shared/blood_scent.gd")`
- `const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")`
- `const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")`
- `const TrailRation = preload("res://scripts/shared/trail_ration.gd")`
- `const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")`
- `const RuinSurvey = preload("res://scripts/shared/ruin_survey.gd")`
- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const MoonVisuals = preload("res://scripts/client/moon_visuals.gd")`
- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const Atmosphere = preload("res://scripts/client/atmosphere.gd")`
- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const ContactShadowBatch = preload("res://scripts/client/contact_shadow_batch.gd")`
- `const AmbientMotes = preload("res://scripts/client/ambient_motes.gd")`
- `const GroundMist = preload("res://scripts/client/ground_mist.gd")`
- `const RainVfx = preload("res://scripts/client/rain_vfx.gd")`
- `const FootprintDecals = preload("res://scripts/client/footprint_decals.gd")`
- `const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const GameServer = preload("res://scripts/server/game_server.gd")`
- `const RaidWard = preload("res://scripts/shared/raid_ward.gd")`
- `const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const Vendor = preload("res://scripts/shared/vendor.gd")`
- `const RegionalTrade = preload("res://scripts/shared/regional_trade.gd")`
- `const RoadTravel = preload("res://scripts/shared/road_travel.gd")`
- `const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")`
- `const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")`
- `const Contracts = preload("res://scripts/shared/contracts.gd")`
- `const DailyBounties = preload("res://scripts/shared/daily_bounties.gd")`
- `const Reputation = preload("res://scripts/shared/reputation.gd")`
- `const CampRest = preload("res://scripts/shared/camp_rest.gd")`
- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")`
- `const StormMud = preload("res://scripts/shared/storm_mud.gd")`
- `const WindChill = preload("res://scripts/shared/wind_chill.gd")`
- `const LightningVisual = preload("res://scripts/client/storm_lightning_visual.gd")`
- `const StormThunder = preload("res://scripts/client/storm_thunder.gd")`
- `const StormLightning = preload("res://scripts/shared/storm_lightning.gd")`
- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")`
- `const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")`
- `const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")`
- `const LOCAL_PLAYER_ID := 2`
- `const TERRAIN_STEP := 8.0`

_41 private function(s) starting with `_` are not listed._
