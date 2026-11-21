# online_main.gd

> The online game client (dedicated server + Nakama): connect screen, the isometric camera, controls, and the glue between the network state and what is drawn.

`res://scripts/client/online_main.gd`

## Overview

The online game client (dedicated server + Nakama): connect screen, the isometric camera, controls, and the glue between the
network state and what is drawn.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WoundFx = preload("res://scripts/client/wound_fx.gd")`
- `const BrawlMeter = preload("res://scripts/client/brawl_meter.gd")`
- `const FarField = preload("res://scripts/client/far_field.gd")`
- `const PcgWorldDressing = preload("res://scripts/client/pcg_world_dressing.gd")`
- `const SeaSurface = preload("res://scripts/client/sea_surface.gd")`
- `const Buoyancy = preload("res://scripts/client/buoyancy.gd")`
- `const RaftVisual = preload("res://scripts/client/raft_visual.gd")`
- `const StreamingProfiler = preload("res://scripts/client/streaming_profiler.gd")`
- `const Fishing = preload("res://scripts/shared/fishing.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const EngineFeatures = preload("res://scripts/client/engine_features.gd")`
- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const MoonVisuals = preload("res://scripts/client/moon_visuals.gd")`
- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const Net = preload("res://scripts/shared/net.gd")`
- `const GameClient = preload("res://scripts/client/game_client.gd")`
- `const ChunkView = preload("res://scripts/client/chunk_view.gd")`
- `const EntityView = preload("res://scripts/client/entity_view.gd")`
- `const RaidTelegraph = preload("res://scripts/client/raid_telegraph.gd")`
- `const LightningVisual = preload("res://scripts/client/storm_lightning_visual.gd")`
- `const StormThunder = preload("res://scripts/client/storm_thunder.gd")`
- `const Hud = preload("res://scripts/client/hud.gd")`
- `const UiAccessibilityLayer = preload("res://scripts/client/ui_accessibility_layer.gd")`
- `const UiAccess = preload("res://scripts/client/ui_access.gd")`
- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const Meshes = preload("res://scripts/client/meshes.gd")`
- `const CharacterModel = preload("res://scripts/client/character_model.gd")`
- `const FirstSteps = preload("res://scripts/client/first_steps.gd")`
- `const HousePieces = preload("res://scripts/shared/house_pieces.gd")`
- `const FirstPersonView = preload("res://scripts/client/first_person_view.gd")`
- `const FirstPersonViewmodel = preload("res://scripts/client/first_person_viewmodel.gd")`
- `const NetTimeouts = preload("res://scripts/shared/net_timeouts.gd")`
- `const ContactShadowBatch = preload("res://scripts/client/contact_shadow_batch.gd")`
- `const AmbientMotes = preload("res://scripts/client/ambient_motes.gd")`
- `const AmbientBirds = preload("res://scripts/client/ambient_birds.gd")`
- `const SnowVfx = preload("res://scripts/client/snow_vfx.gd")`
- `const FishShoals = preload("res://scripts/client/fish_shoals.gd")`
- `const DuskBats = preload("res://scripts/client/dusk_bats.gd")`
- `const BreathVapor = preload("res://scripts/client/breath_vapor.gd")`
- `const Tumbleweeds = preload("res://scripts/client/tumbleweeds.gd")`
- `const DamageNumbers = preload("res://scripts/client/damage_numbers.gd")`
- `const OcclusionSilhouette = preload("res://scripts/client/occlusion_silhouette.gd")`
- `const DamageDirection = preload("res://scripts/client/damage_direction.gd")`
- `const BloodDecals = preload("res://scripts/client/blood_decals.gd")`
- `const HoverOutline = preload("res://scripts/client/hover_outline.gd")`
- `const BlobShadow = preload("res://scripts/client/blob_shadow.gd")`
- `const AbilityBar = preload("res://scripts/client/ability_bar.gd")`
- `const WetDrips = preload("res://scripts/client/wet_drips.gd")`
- `const ZombieFlies = preload("res://scripts/client/zombie_flies.gd")`
- `const Dragonflies = preload("res://scripts/client/dragonflies.gd")`
- `const ShootingStars = preload("res://scripts/client/shooting_stars.gd")`
- `const DustDevils = preload("res://scripts/client/dust_devils.gd")`
- `const RainSplashes = preload("res://scripts/client/rain_splashes.gd")`
- `const GroundMist = preload("res://scripts/client/ground_mist.gd")`
- `const FootprintDecals = preload("res://scripts/client/footprint_decals.gd")`
- `const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")`
- `const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")`
- `const HubView = preload("res://scripts/client/hub_view.gd")`
- `const Audio = preload("res://scripts/client/audio.gd")`
- `const Assets = preload("res://scripts/client/assets.gd")`
- `const Social = preload("res://scripts/client/social.gd")`
- `const Atmosphere = preload("res://scripts/client/atmosphere.gd")`
- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const GraphicsTextureStreaming = preload("res://scripts/client/graphics_texture_streaming.gd")`
- `const ObjectPopulationProfiler = preload("res://scripts/client/object_population_profiler.gd")`
- `const AmbientTickBudget = preload("res://scripts/client/ambient_tick_budget.gd")`
- `const AMBIENT_CPU_BUDGET_US := [900, 1500, 2500, 4000] # Quality tiers, main-thread cosmetics only.`
- `const GraphicsCinematicDof = preload("res://scripts/client/graphics_cinematic_dof.gd")`
- `const RainGear = preload("res://scripts/client/character_rain_gear.gd")`
- `const DungeonOcclusion = preload("res://scripts/client/dungeon_occlusion.gd")`
- `const WorldStreamingPolicy = preload("res://scripts/client/world_streaming_policy.gd")`
- `const GraphicsColorGrade = preload("res://scripts/client/graphics_color_grade.gd")`
- `const GraphicsLensRain = preload("res://scripts/client/graphics_lens_rain.gd")`
- `const RenderBenchmark = preload("res://scripts/client/render_benchmark.gd")`
- `const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")`
- `const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")`
- `const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")`
- `const GraphicsAutoQuality = preload("res://scripts/client/graphics_auto_quality.gd")`
- `const GraphicsVramBudget = preload("res://scripts/client/graphics_vram_budget.gd")`
- `const ShaderWarmup = preload("res://scripts/client/shader_warmup.gd")`
- `const FrameHitchAnalyzer = preload("res://scripts/client/frame_hitch_analyzer.gd")`
- `const TraceCapture = preload("res://scripts/shared/trace_capture.gd")`
- `const SeaFftDetail = preload("res://scripts/client/sea_fft_detail.gd")`
- `const BarricadeDebris = preload("res://scripts/client/barricade_debris.gd")`
- `const PerfOverlay = preload("res://scripts/client/perf_overlay.gd")`
- `const VfxPresets = preload("res://scripts/client/vfx_presets.gd")`
- `const GraphicsDynamicResolution = preload("res://scripts/client/graphics_dynamic_resolution.gd")`
- `const OutpostView = preload("res://scripts/client/outpost_view.gd")`
- `const WorldMap = preload("res://scripts/client/world_map.gd")`
- `const WorldOverlay = preload("res://scripts/client/world_overlay.gd")`
- `const HelpPanel = preload("res://scripts/client/help_panel.gd")`
- `const Vendor = preload("res://scripts/shared/vendor.gd")`
- `const Effects = preload("res://scripts/client/effects.gd")`
- `const CombatVfx = preload("res://scripts/client/combat_vfx.gd")`
- `const CombatCameraFeedback = preload("res://scripts/client/combat_camera_feedback.gd")`
- `const ImpactDecals = preload("res://scripts/client/impact_decals.gd")`
- `const CameraPostFx = preload("res://scripts/client/camera_post_fx.gd")`
- `const PhysicsWorldFx = preload("res://scripts/client/physics_world_fx.gd")`
- `const PlantInteraction = preload("res://scripts/client/plant_interaction.gd")`
- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")`
- `const UiTheme = preload("res://scripts/client/ui_theme.gd")`
- `const TitleBanner = preload("res://scripts/client/title_banner.gd")`
- `const LocalServer = preload("res://scripts/client/local_server.gd")`
- `const SoloSlots = preload("res://scripts/client/solo_slots.gd")`
- `const SkillsPanel = preload("res://scripts/client/skills_panel.gd")`
- `const Skills = preload("res://scripts/shared/skills.gd")`
- `const CAMERA_OFFSET := Vector3(0.0, 17.0, 12.5)`
- `const DAY_LENGTH := WorldCycle.DAY_LENGTH # Shared with server simulation and local client.`
- `const CHARGE_START_MS := 220 # A shorter press is a quick swing.`
- `const CHARGE_FULL_MS := 850`
- `const BUILD_PIECES := ["wall", "door", "window", "floor", "roof", "pillar", "bed", "lamp", "chest", "workbench", ""]`

## Functions

### `charge_amount`

```gdscript
func charge_amount() -> float
```

How far the current melee wind-up has charged, 0..1.

_71 private function(s) starting with `_` are not listed._
