extends Node3D
## The online game client (dedicated server + Nakama): connect screen, the isometric camera, controls, and the glue between the
## network state and what is drawn.

const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const WoundFx = preload("res://scripts/client/wound_fx.gd")
const BrawlMeter = preload("res://scripts/client/brawl_meter.gd")
const FarField = preload("res://scripts/client/far_field.gd")
const PcgWorldDressing = preload("res://scripts/client/pcg_world_dressing.gd")
const SeaSurface = preload("res://scripts/client/sea_surface.gd")
const Buoyancy = preload("res://scripts/client/buoyancy.gd")
const RaftVisual = preload("res://scripts/client/raft_visual.gd")
const StreamingProfiler = preload("res://scripts/client/streaming_profiler.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const MoonVisuals = preload("res://scripts/client/moon_visuals.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")
const NetProtocol = preload("res://scripts/shared/net_protocol.gd")
const GameClient = preload("res://scripts/client/game_client.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const TerrainRvt = preload("res://scripts/client/terrain_rvt.gd")
const AbBenchmark = preload("res://scripts/client/ab_benchmark.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const RaidTelegraph = preload("res://scripts/client/raid_telegraph.gd")
const LightningVisual = preload("res://scripts/client/storm_lightning_visual.gd")
const StormThunder = preload("res://scripts/client/storm_thunder.gd")
const Hud = preload("res://scripts/client/hud.gd")
const UiAccessibilityLayer = preload("res://scripts/client/ui_accessibility_layer.gd")
const UiAccess = preload("res://scripts/client/ui_access.gd")
const UiSettings = preload("res://scripts/client/ui_settings.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const FirstSteps = preload("res://scripts/client/first_steps.gd")
const HousePieces = preload("res://scripts/shared/house_pieces.gd")
const FirstPersonView = preload("res://scripts/client/first_person_view.gd")
const RenderProfile = preload("res://scripts/client/render_profile.gd")
const FirstPersonViewmodel = preload("res://scripts/client/first_person_viewmodel.gd")
const NetTimeouts = preload("res://scripts/shared/net_timeouts.gd")
const ContactShadowBatch = preload("res://scripts/client/contact_shadow_batch.gd")
const AmbientMotes = preload("res://scripts/client/ambient_motes.gd")
const AmbientBirds = preload("res://scripts/client/ambient_birds.gd")
const SnowVfx = preload("res://scripts/client/snow_vfx.gd")
const FishShoals = preload("res://scripts/client/fish_shoals.gd")
const DuskBats = preload("res://scripts/client/dusk_bats.gd")
const BreathVapor = preload("res://scripts/client/breath_vapor.gd")
const Tumbleweeds = preload("res://scripts/client/tumbleweeds.gd")
const DamageNumbers = preload("res://scripts/client/damage_numbers.gd")
const OcclusionSilhouette = preload("res://scripts/client/occlusion_silhouette.gd")
const DamageDirection = preload("res://scripts/client/damage_direction.gd")
const BloodDecals = preload("res://scripts/client/blood_decals.gd")
const HoverOutline = preload("res://scripts/client/hover_outline.gd")
const BlobShadow = preload("res://scripts/client/blob_shadow.gd")
const AbilityBar = preload("res://scripts/client/ability_bar.gd")
const WetDrips = preload("res://scripts/client/wet_drips.gd")
const ZombieFlies = preload("res://scripts/client/zombie_flies.gd")
const Dragonflies = preload("res://scripts/client/dragonflies.gd")
const ShootingStars = preload("res://scripts/client/shooting_stars.gd")
const DustDevils = preload("res://scripts/client/dust_devils.gd")
const RainSplashes = preload("res://scripts/client/rain_splashes.gd")
const GroundMist = preload("res://scripts/client/ground_mist.gd")
const FootprintDecals = preload("res://scripts/client/footprint_decals.gd")
const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")
const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")
const HubView = preload("res://scripts/client/hub_view.gd")
const Audio = preload("res://scripts/client/audio.gd")
const Assets = preload("res://scripts/client/assets.gd")
const Social = preload("res://scripts/client/social.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const GraphicsTextureStreaming = preload("res://scripts/client/graphics_texture_streaming.gd")
const TerrainLivePatch = preload("res://scripts/client/terrain_live_patch.gd")
const VirtualGeometryPageInspector = preload("res://scripts/client/virtual_geometry_page_inspector.gd")
const ObjectPopulationProfiler = preload("res://scripts/client/object_population_profiler.gd")
const AmbientTickBudget = preload("res://scripts/client/ambient_tick_budget.gd")
const AMBIENT_CPU_BUDGET_US := [900, 1500, 2500, 4000] # Quality tiers, main-thread cosmetics only.
const GraphicsCinematicDof = preload("res://scripts/client/graphics_cinematic_dof.gd")
const RainGear = preload("res://scripts/client/character_rain_gear.gd")
const DungeonOcclusion = preload("res://scripts/client/dungeon_occlusion.gd")
const WorldStreamingPolicy = preload("res://scripts/client/world_streaming_policy.gd")
const GraphicsColorGrade = preload("res://scripts/client/graphics_color_grade.gd")
const GraphicsLensRain = preload("res://scripts/client/graphics_lens_rain.gd")
const RenderBenchmark = preload("res://scripts/client/render_benchmark.gd")
const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")
const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")
const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")
const GraphicsAutoQuality = preload("res://scripts/client/graphics_auto_quality.gd")
const GraphicsVramBudget = preload("res://scripts/client/graphics_vram_budget.gd")
const ShaderWarmup = preload("res://scripts/client/shader_warmup.gd")
const FrameHitchAnalyzer = preload("res://scripts/native/frame_hitch_analyzer.gd") # Native CgameHitchCorrelator when built in.
const TraceCapture = preload("res://scripts/native/trace_capture.gd") # Native CgameTrace singleton when built in.
const SeaFftDetail = preload("res://scripts/client/sea_fft_detail.gd")
const BarricadeDebris = preload("res://scripts/client/barricade_debris.gd")
const PerfOverlay = preload("res://scripts/client/perf_overlay.gd")
const RtEffects = preload("res://scripts/client/rt_effects.gd")
const VfxPresets = preload("res://scripts/native/cgame_vfx_facade.gd") # Native VFXGraphInstance3D when built in.
const Rendering = preload("res://scripts/native/cgame_rendering.gd") # Native cgame_rendering module when built in.
const GraphicsDynamicResolution = preload("res://scripts/client/graphics_dynamic_resolution.gd")
const OutpostView = preload("res://scripts/client/outpost_view.gd")
const WorldMap = preload("res://scripts/client/world_map.gd")
const WorldOverlay = preload("res://scripts/client/world_overlay.gd")
const HelpPanel = preload("res://scripts/client/help_panel.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Effects = preload("res://scripts/client/effects.gd")
const CombatVfx = preload("res://scripts/client/combat_vfx.gd")
const CombatCameraFeedback = preload("res://scripts/client/combat_camera_feedback.gd")
const ImpactDecals = preload("res://scripts/client/impact_decals.gd")
const CameraPostFx = preload("res://scripts/client/camera_post_fx.gd")
const PhysicsWorldFx = preload("res://scripts/client/physics_world_fx.gd")
const PlantInteraction = preload("res://scripts/client/plant_interaction.gd")
const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")
const UiTheme = preload("res://scripts/client/ui_theme.gd")
const TitleBanner = preload("res://scripts/client/title_banner.gd")
const LocalServer = preload("res://scripts/client/local_server.gd")
const SoloSlots = preload("res://scripts/client/solo_slots.gd")
const SkillsPanel = preload("res://scripts/client/skills_panel.gd")
const Skills = preload("res://scripts/shared/skills.gd")

const CAMERA_OFFSET := Vector3(0.0, 17.0, 12.5)
const DAY_LENGTH := WorldCycle.DAY_LENGTH # Shared with server simulation and local client.

var net
var client
var peer: ENetMultiplayerPeer
var _rpc_protocol_failed := false
var streamer: WorldStreamer
var _terrain_rvt: Node
# Last displayed position, not input intent: online prediction uses actual
# corrected player motion and resets on teleport/network resync.
var _stream_previous_position := Vector3.ZERO
var _stream_has_previous_position := false
var _world_streaming_status_elapsed := 0.0
var _stream_velocity := Vector3.ZERO
var chunk_root: Node3D
var entities: Node3D
var camera: Camera3D
var _wound_fx: Node3D # Cuts, bullet wounds, blood spray and severed limbs on struck enemies.
var sun: DirectionalLight3D
var environment: Environment
var water: MeshInstance3D
var hud
var avatar: Node3D
var avatar_model
var bike_visual
var flare_visual
var audio
var _storm_thunder: Node3D
var hub_view
var outposts
var world_map
var overlay
var _site_id := -1
var _area_name := ""
var _place_timer := 0.0
var help_panel
var demo_phase := -1.0
var demo_storm := false
var _wind_sample_left := 0.0
var _visual_weather_wind := Vector2.ZERO
var _visual_biome := "plains"
var atmosphere
var _ambient_motes
var _ambient_budget: Variant = AmbientTickBudget.new()
var _ambient_rates_supported: bool = false
var _ambient_lane_enabling_supported: bool = false
var _ambient_rate_cache: Dictionary = {}
var _ambient_deadline_supported: bool = false
var _ambient_deadline_cache: Dictionary = {}
var _ambient_was_underground := false
var _ambient_monitors: Array[StringName] = []
var _object_population_profiler: RefCounted = null # Only created on the debug hotkey.
var _ambient_birds
var _fish_shoals
var _dusk_bats
var _breath
var _wet_drips
var _zombie_flies
var _dragonflies
var _shooting_stars
var _dust_devils
var _rain_splashes
var _tumbleweeds
var _damage_numbers
var _damage_direction
var _blood_decals
var _hover_outline = HoverOutline.new()
var _hover_left := 0.0
var _ground_mist
var _grade_material: ShaderMaterial
var _grade_elapsed := 0.20 # Update color grading 5 times per second, not every render frame.
var _auto_quality := GraphicsAutoQuality.new()
var _vram_budget = Rendering.vram_budget_new()
var _hitch_analyzer := FrameHitchAnalyzer.new()
var _trace := TraceCapture.new()
var _trace_path := ""
var _perf: CanvasLayer
var _adaptive_resolution := GraphicsDynamicResolution.new()
var _auto_graphics := true
var _quality_picker: OptionButton
var _access # UiAccessibilityLayer: Esc settings menu, captions, colour-blind filter, FPS overlay.
var effects
var combat_vfx
var _footprints: Node3D
var decals
var camera_fx
var physics_fx
var skills_panel
var social
var chat_edit: LineEdit
var account := {} # Result of the Nakama sign-in, empty when playing without accounts.
var connect_panel: PanelContainer
var local_server := LocalServer.new()
var solo_slot_picker: OptionButton
var solo_slot_info: Label
var _solo_offline_account: bool = false
var _solo_attempts_left := 0
var address_edit: LineEdit
var name_edit: LineEdit
var status_label: Label
var _zoom := 1.0
# First-person view: middle mouse toggles it; scrolling in past the closest zoom enters it, scrolling out leaves.
var _first_person := false
var _fp_yaw := PI
var _fp_pitch := 0.0
var _demo_house_plan: Array = []
var _demo_house_done_at := -1
var _start_first_person := false # --first-person launch flag (also for screenshots).
var _jump_time := -1.0 # Seconds into the current cosmetic first-person hop, or -1 on the ground.
var _crosshair: Control
var _viewmodel: Node3D # FirstPersonViewmodel: the held item in front of the first-person camera.
var _bob_phase := 0.0
var _fp_roll := 0.0
var _knock := 0.0 # 0..1: first-person camera thrown to the ground while knocked down.
var _land_time := -1.0 # Seconds since the cosmetic hop landed, -1 when not dipping.
var _hit_marker := 0.0 # Crosshair hit flash, decays.
var _own_attack_time := -10.0 # Engine ticks (s) of your last attack, for zombie hit markers.
var _third_person_near := 0.05
var _fp_body_refresh := 0.0
var _brawl_meter: Control
var _far_field: Node3D
var _raft_visual: Node3D
var _profiler: Control # World streaming profiler (Ctrl+F3).
var _pcg_dressing: Node3D # Engine PCG graphs: roadside props, ground clutter, ruin debris (null without the module).
var _sea # SeaSurface: depth map for shore-aware swell.
var _last_charge: Dictionary = {} # peer -> charge of their latest swing (for power-hit gore).
var _underwater_tint: ColorRect # Blue murk while the camera is below the surface.
var _breath_label: Label # Air left while diving.
var _dof_elapsed := 0.35 # Coalesce cinematic focus updates to ~3 Hz.
var _attack_cooldown := 0.0
var _resource_weakspot: MeshInstance3D # One reusable marker, never one object per resource.
var _resource_marker_rescan_at: int = 0
var _resource_marker_target: Dictionary = {}
var _hold_pickup_since_ms: int = -1 # -1 unless the initial E press collected a loose resource.
var _hold_pickup_next_ms: int = 0
var _hold_pickup_pending: Dictionary = {} # node id -> retry-until milliseconds
const HOLD_PICKUP_DELAY_MS := 360
const HOLD_PICKUP_INTERVAL_MS := 260
const HOLD_PICKUP_RETRY_MS := 1500
var _charge_msec := -1 # Melee attack held since (ms); release = light swing or power blow.
const CHARGE_START_MS := 220 # A shorter press is a quick swing.
const CHARGE_FULL_MS := 850
var _build_mode := false # U: a ghost wall follows the aim until it is placed or cancelled.
var _build_yaw := 0.0
var _build_ghost: MeshInstance3D
var _build_reason := ""
# "" builds the old free-standing barricade; otherwise a house piece snapped to the 3 m grid.
var _build_piece := "wall"
const BUILD_PIECES := ["wall", "door", "window", "floor", "roof", "pillar", "bed", "lamp", "chest", "workbench", ""]
var _move_input := Vector2.ZERO # This frame's movement keys, for facing the way you walk.
var _last_attack_msec := -100000
var _fishing_line: MeshInstance3D # Line from the rod tip to the bobber while fishing.
var _bobber: MeshInstance3D
var _bobber_spot := Vector3.INF
var _last_cast_spot := Vector3.INF # Kept after the cast ends, for the splash of the catch.
var _party_rally_marker: Node3D
var _party_supply_marker: Node3D
var _raid_telegraph: Node3D
var _lightning_visual: Node3D
var _screenshot_path := ""
var _capture_path := "" # --capture: one PNG of the normal game after 60 s in the world (no benchmark mode).
var _capture_time := 0.0
# Frames sampled by the screenshot benchmark; CGAME_BENCH_FRAMES="start:end" moves the window past streaming.
var _bench_window := Vector2i(540, 700)
var _screenshot_frames := 0
var _frame_ms: Array[float] = [] # CPU process deltas in the screenshot capture window.
var _gpu_frame_ms: Array[float] = [] # Native viewport GPU timings, sampled independently.
var _demo := ""
var _frames := 0
var _demo_frames := 0 # Frames since the first snapshot arrived.


func _exit_tree() -> void:
	if _trace.enabled and _trace_path != "":
		_trace.save(_trace_path)
	for monitor_name in _ambient_monitors:
		Performance.remove_custom_monitor(monitor_name)
	_ambient_monitors.clear()
	# GPU timestamp queries belong to the active online viewport only.
	if get_viewport() != null:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	CharacterModel.clear_templates() # Cached survivor models live outside the tree.
	local_server.stop() # A solo world ends with the game.


func _ready() -> void:
	Engine.physics_ticks_per_second = 30
	# Prefer the native Godot scheduler when the fork exposes it. Standard
	# Godot builds retain the same pure GDScript behavior automatically.
	if EngineFeatures.has("FrameUpdateBudget"):
		var native_budget: Object = EngineFeatures.make("FrameUpdateBudget")
		if native_budget != null and native_budget.has_method("record_cost") \
				and native_budget.has_method("set_frame_time_budget_us") \
				and native_budget.has_method("last_frame_cost_us") \
				and native_budget.has_method("set_lane_importance") \
				and native_budget.has_method("get_reserved_estimated_cost_us"):
			var registered_all := true
			for lane in AmbientTickBudget.LANES:
				if not bool(native_budget.call("register_lane", StringName(lane))):
					registered_all = false
			if registered_all:
				_ambient_budget = native_budget
	# Older custom binaries keep their existing importance/cost scheduler.
	_ambient_rates_supported = _ambient_budget.has_method("set_lane_rate_scale")
	_ambient_lane_enabling_supported = _ambient_budget.has_method("set_lane_enabled")
	_ambient_deadline_supported = _ambient_budget.has_method("set_lane_max_deferred_frames")
	# Client-side cosmetic update budget, exposed to Godot's built-in profiler.
	for monitor in [
		[&"Albion/AmbientUpdates", Callable(_ambient_budget, "updated_total")],
		[&"Albion/AmbientSkipped", Callable(_ambient_budget, "skipped_total")],
		[&"Albion/AmbientSlots", Callable(_ambient_budget, "current_budget")],
		[&"Albion/AmbientPressurePct", Callable(_ambient_budget, "pressure_percent")],
		[&"Albion/AmbientCPUus", Callable(_ambient_budget, "last_frame_cost_us")],
		[&"Albion/AmbientCPUBudgetus", Callable(_ambient_budget, "get_frame_time_budget_us")],
		[&"Albion/AmbientPlannedCPUus", Callable(_ambient_budget, "get_reserved_estimated_cost_us")],
	]:
		var monitor_name: StringName = monitor[0]
		if not Performance.has_custom_monitor(monitor_name):
			Performance.add_custom_monitor(monitor_name, monitor[1])
			_ambient_monitors.append(monitor_name)
	# Count visually significant lanes currently beyond their soft deferral
	# deadlines; this is independent of FPS/CPU pressure measurements.
	if _ambient_budget.has_method("get_deadline_overdue_lane_count"):
		var overdue_monitor: StringName = &"Albion/AmbientDeadlineOverdue"
		if not Performance.has_custom_monitor(overdue_monitor):
			Performance.add_custom_monitor(overdue_monitor,
				Callable(_ambient_budget, "get_deadline_overdue_lane_count"))
			_ambient_monitors.append(overdue_monitor)
	# Optional per-subsystem CPU stats. Older custom native builds keep their
	# existing aggregate monitors without requiring the new method.
	if _ambient_budget.has_method("get_lane_last_frame_cost_us"):
		for lane in AmbientTickBudget.LANES:
			var lane_monitor := StringName("Albion/AmbientCPUus/" + lane)
			if not Performance.has_custom_monitor(lane_monitor):
				Performance.add_custom_monitor(lane_monitor,
					Callable(_ambient_budget, "get_lane_last_frame_cost_us").bind(StringName(lane)))
				_ambient_monitors.append(lane_monitor)
	# Unreal STAT STREAMING-style diagnostics for the live game. These
	# callbacks only load atomics and are removed in _exit_tree with other
	# Albion monitors; older engines register nothing.
	_ambient_monitors.append_array(GraphicsTextureStreaming.register_profiler_monitors())
	GraphicsQuality.load_preference()
	_access = UiAccessibilityLayer.new() # Loads settings, language and key bindings; must precede the menus below.
	add_child(_access)
	# Both graphics selectors use the same renderer and budget application.
	_access.menu.connect("graphics_selected", Callable(self, "_apply_graphics_selection"))
	var graphics_config := ConfigFile.new()
	if graphics_config.load(GraphicsQuality.SETTINGS_PATH) == OK:
		_auto_graphics = bool(graphics_config.get_value("rendering", "auto", false))
	if _auto_graphics:
		GraphicsQuality.set_level(_auto_quality.level, false)
	_access.menu.call("set_graphics_choice", GraphicsQuality.level(), _auto_graphics)
	_adaptive_resolution.configure(GraphicsQuality.level(),
		GraphicsQuality.metalfx_resolution_floor())
	_update_gpu_measurements()
	_build_environment()
	_build_connect_screen()
	var args := OS.get_cmdline_user_args()
	var address := "127.0.0.1:24565"
	var player_name := "Survivor"
	var i := 0
	while i < args.size():
		match args[i]:
			"--server":
				i += 1
				address = args[i]
			"--name":
				i += 1
				player_name = args[i]
			"--trace":
				# Insights-style capture; open the JSON in chrome://tracing or ui.perfetto.dev.
				i += 1
				_trace_path = args[i]
				_trace.enabled = true
			"--screenshot":
				i += 1
				_screenshot_path = args[i]
				var window: PackedStringArray = OS.get_environment("CGAME_BENCH_FRAMES").split(":")
				if window.size() == 2 and window[0].is_valid_int() and window[1].is_valid_int():
					_bench_window = Vector2i(maxi(window[0].to_int(), 1), maxi(window[1].to_int(), window[0].to_int() + 1))
			"--capture":
				i += 1
				_capture_path = args[i]
			"--demo":
				i += 1
				_demo = args[i]
			"--phase":
				i += 1
				demo_phase = float(args[i]) # 0..1 around the day, for screenshots.
			"--storm":
				demo_storm = true
			"--first-person":
				_start_first_person = true
			"--connect":
				address_edit.text = address
		i += 1
	# Screenshot benchmarks opt in to viewport GPU timestamps even if Auto
	# quality is disabled; normal manual-quality runs incur no query cost.
	_update_gpu_measurements()
	address_edit.text = address
	name_edit.text = player_name
	if _demo != "" and _screenshot_path != "":
		# A scripted screenshot run must not take the keyboard from whoever is working at this machine.
		get_window().unfocusable = true
	if "--connect" in args:
		_connect_remote()


func _make_party_rally_marker() -> void:
	_party_rally_marker = Node3D.new()
	_party_rally_marker.name = "PartyRally"
	_party_rally_marker.visible = false
	var beacon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	beacon.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.4, 0.9, 1.0)
	beacon.material_override = material
	_party_rally_marker.add_child(beacon)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.75
	label.text = "PARTY RALLY"
	_party_rally_marker.add_child(label)
	add_child(_party_rally_marker)


func _update_party_rally_marker() -> void:
	var rally: Dictionary = client.you.get("party", {}).get("rally", {})
	_party_rally_marker.visible = not rally.is_empty()
	if rally.is_empty():
		return
	_party_rally_marker.position = Vector3(float(rally["x"]),
			float(rally["y"]) + 1.8, float(rally["z"]))
	var label := _party_rally_marker.get_node("Label") as Label3D
	label.text = "PARTY RALLY  %ds" % int(ceil(float(rally["remaining"])))


## A short-lived help beacon is visible only to current group members.
## All its coordinates come from a previously server-authorized event.
func _make_party_supply_marker() -> void:
	_party_supply_marker = Node3D.new()
	_party_supply_marker.name = "PartySupplyHelp"
	_party_supply_marker.visible = false
	var beacon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	beacon.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.68, 0.28)
	beacon.material_override = material
	_party_supply_marker.add_child(beacon)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.8
	_party_supply_marker.add_child(label)
	add_child(_party_supply_marker)


func _update_party_supply_marker() -> void:
	var signal_state: Dictionary = client.active_supply_beacon()
	_party_supply_marker.visible = not signal_state.is_empty()
	if signal_state.is_empty():
		return
	var x: float = float(signal_state["x"])
	var z: float = float(signal_state["z"])
	_party_supply_marker.position = Vector3(x, client.world.height_at(x, z) + 1.8, z)
	var label := _party_supply_marker.get_node("Label") as Label3D
	label.text = "PARTY NEEDS %s (%ds)" % [
		str(signal_state["need"]).to_upper(),
		ceili(maxf(0.0, float(signal_state["expires"]) - client.server_time))]


func _build_environment() -> void:
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	_ground_mist = GroundMist.new()
	_ground_mist.name = "RegionalGroundMist"
	add_child(_ground_mist)
	environment = atmosphere.environment
	sun = atmosphere.sun
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.far = 700.0
	camera.position = CAMERA_OFFSET * 3.0
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	# Compile every spatial shader pipeline during loading, not mid-fight.
	Rendering.shader_warmup_start(camera)
	_perf = PerfOverlay.new()
	_perf.name = "PerfOverlay"
	add_child(_perf)
	_perf.set("trace", _trace)
	_perf.set("loaded_cells_source", func() -> int: return streamer.get_loaded_count() if streamer != null else 0)
	# Hardware ray-traced sun shadows + AO (ray query): Ultra only, and only where the GPU
	# reports SUPPORTS_RAY_QUERY on Forward+. attach() is a no-op everywhere else.
	if GraphicsQuality.level() >= 3:
		var rt := RtEffects.new()
		rt.name = "RayTracedEffects"
		add_child(rt)
		rt.quality = GraphicsQuality.level()
		if not rt.attach(camera, self, sun, str(RenderingServer.get_current_rendering_method())):
			rt.queue_free()
	_make_party_rally_marker()
	_make_party_supply_marker()
	_raid_telegraph = RaidTelegraph.new()
	_raid_telegraph.name = "RaidGroundSlamWarning"
	add_child(_raid_telegraph)
	_lightning_visual = LightningVisual.new()
	_lightning_visual.name = "StormLightningWarning"
	add_child(_lightning_visual)
	camera.current = true
	# The project supports occlusion, but the title screen and open world should
	# never start with the extra software-culling pass enabled.
	DungeonOcclusion.update_viewport(get_viewport(), GraphicsQuality.level(),
		str(RenderingServer.get_current_rendering_method()), false)
	# Only one light manager for every streamed underground room.
	# Nearest torches glow and flicker; distant torches contribute no GPU light passes.
	var dungeon_lights := DungeonLightBudget.new()
	dungeon_lights.name = "DungeonLightBudget"
	add_child(dungeon_lights)
	# A tiny shared probe pool captures the nearest dungeon room once, not per frame.
	var dungeon_reflections := DungeonReflectionBudget.new()
	dungeon_reflections.name = "DungeonReflectionBudget"
	add_child(dungeon_reflections)
	# Only one pool of high-end architectural reflection captures in the world.
	var outdoor_reflections := OutdoorReflectionBudget.new()
	outdoor_reflections.name = "OutdoorReflectionBudget"
	outdoor_reflections.atmosphere = atmosphere
	add_child(outdoor_reflections)
	if camera.has_method("set_shake_max_offset"):
		# Trauma shake (engine feature of this fork): small offsets for a top-down view, quick decay.
		camera.set_shake_max_offset(Vector3(0.35, 0.25, 0.35))
		camera.set_shake_max_rotation(0.02)
		camera.set_shake_decay(1.6)
	chunk_root = Node3D.new()
	chunk_root.name = "Chunks"
	add_child(chunk_root)
	entities = EntityView.new()
	add_child(entities)
	# Measure local visual interpolation recovery separately from server
	# tick rate and actual network transport loss.
	for network_monitor in [
		[&"Albion/NetworkEstimatedMissingSnapshots", Callable(entities, "network_missing_snapshot_estimate")],
		[&"Albion/NetworkRecoveryHoldRemaining", Callable(entities, "network_recovery_hold_remaining")],
	]:
		var network_monitor_name: StringName = network_monitor[0]
		if not Performance.has_custom_monitor(network_monitor_name):
			Performance.add_custom_monitor(network_monitor_name, network_monitor[1])
			_ambient_monitors.append(network_monitor_name)
	# One GPU draw grounds local/remote players, infected and streamed NPCs.
	# This avoids a separate transparent shadow MeshInstance for every actor.
	var ground_shadows := ContactShadowBatch.new()
	ground_shadows.name = "GroundContactShadows"
	ground_shadows.setup(atmosphere)
	add_child(ground_shadows)
	# The sea: one big plane that follows the player.
	water = MeshInstance3D.new()
	water.mesh = SeaSurface.build_mesh() # Radial LOD rings: Gerstner swell needs vertices.
	_sea = SeaSurface.new()
	var water_material := ShaderMaterial.new()
	water_material.shader = load("res://assets/shaders/water.gdshader")
	water_material.set_shader_parameter("gerstner_amplitude", 1.0)
	water_material.set_shader_parameter("shore_map_rect", Vector4(-SeaSurface.MAP_EXTENT * 0.5, -SeaSurface.MAP_EXTENT * 0.5, SeaSurface.MAP_EXTENT, SeaSurface.MAP_EXTENT))
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position.y = Defs.WATER_LEVEL - 0.35
	add_child(water)
	# FFT chop on the swell (High/Ultra); follows quality presets on its own.
	var sea_fft := SeaFftDetail.new()
	sea_fft.name = "SeaFftDetail"
	add_child(sea_fft)
	sea_fft.setup(water_material, GraphicsQuality.level(), 1337)
	effects = Effects.new()
	add_child(effects)
	# Report real main-thread PackedScene cache work separately from
	# particle simulation and combat CPU. Both native/script pools expose it.
	for monitor in [
		[&"Albion/VFXPoolMaintenanceCPUus", Callable(effects, "get_pool_maintenance_work_usec")],
		[&"Albion/VFXPoolMaintenancePending", Callable(effects, "get_pool_maintenance_pending_count")],
	]:
		var pool_monitor_name: StringName = monitor[0]
		if not Performance.has_custom_monitor(pool_monitor_name):
			Performance.add_custom_monitor(pool_monitor_name, monitor[1])
			_ambient_monitors.append(pool_monitor_name)
	combat_vfx = CombatVfx.new()
	add_child(combat_vfx)
	_footprints = FootprintDecals.new()
	_footprints.name = "TerrainFootprints"
	add_child(_footprints)
	decals = ImpactDecals.new()
	add_child(decals)
	physics_fx = PhysicsWorldFx.new()
	add_child(physics_fx)
	# The finishing pass over the 3D view (tilt-shift, grading, vignette), drawn under every interface layer.
	var post := CanvasLayer.new()
	post.layer = -10
	add_child(post)
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_material = ShaderMaterial.new()
	_grade_material.shader = load("res://assets/shaders/post_grade.gdshader")
	grade.material = _grade_material
	post.add_child(grade)
	camera_fx = CameraPostFx.new()
	camera_fx.name = "CameraPostFx"
	add_child(camera_fx)
	camera_fx.setup(camera)
	GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
		streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics)


func _build_connect_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	# Title screen: the sky panorama behind a dark vignette, the name in gold, the sign-in card below it.
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = UiTheme.get_theme()
	layer.add_child(backdrop)
	var panorama := load("res://assets/textures/sky/day_sky.jpg") as Texture2D
	if panorama != null:
		var sky := TextureRect.new()
		sky.texture = panorama
		sky.set_anchors_preset(Control.PRESET_FULL_RECT)
		sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sky.modulate = Color(0.85, 0.8, 0.74)
		backdrop.add_child(sky)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.02, 0.03, 0.15))
	gradient.set_color(1, Color(0.02, 0.02, 0.03, 0.88))
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5, 0.42)
	fade.fill_to = Vector2(1.15, 1.1)
	shade.texture = fade
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.add_child(shade)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	backdrop.add_child(column)
	# The sign-in card is a hanging banner with the title woven in (title_banner.gd).
	connect_panel = PanelContainer.new()
	connect_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	connect_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(connect_panel)
	var banner := TitleBanner.new()
	banner.custom_minimum_size = Vector2(460, 0)
	connect_panel.add_child(banner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	banner.add_child(box)
	var title := Label.new()
	title.text = "ALBION AFTER"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.74))
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.03, 0.03))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Gather. Craft. Survive. Lose everything."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", UiTheme.GOLD)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	box.add_child(gap)
	var field_style := UiTheme._box(UiTheme.PAPER, 18, 2.0, Color(0.55, 0.4, 0.2), 10)
	field_style.shadow_size = 0
	var field_focus := UiTheme._box(UiTheme.CREAM, 18, 2.0, UiTheme.GOLD, 10)
	field_focus.shadow_size = 0
	for field in [["Survivor name", "Name"], ["Server", "host:port"]]:
		var caption := Label.new()
		caption.text = field[0]
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", Color(0.95, 0.84, 0.66))
		box.add_child(caption)
		var edit := LineEdit.new()
		edit.placeholder_text = field[1]
		edit.custom_minimum_size = Vector2(0, 40)
		edit.add_theme_stylebox_override("normal", field_style)
		edit.add_theme_stylebox_override("focus", field_focus)
		edit.add_theme_color_override("font_color", UiTheme.INK)
		edit.add_theme_color_override("font_placeholder_color", UiTheme.INK_SOFT)
		edit.add_theme_color_override("caret_color", UiTheme.INK)
		edit.text_submitted.connect(func(_text: String) -> void: _connect_remote())
		box.add_child(edit)
		if name_edit == null:
			name_edit = edit
		else:
			address_edit = edit
	var slot_caption := Label.new()
	slot_caption.text = "Solo survivor"
	slot_caption.add_theme_font_size_override("font_size", 14)
	slot_caption.add_theme_color_override("font_color", Color(0.95, 0.84, 0.66))
	box.add_child(slot_caption)
	solo_slot_picker = OptionButton.new()
	solo_slot_picker.custom_minimum_size = Vector2(0, 40)
	for state in ["normal", "hover", "pressed", "focus"]:
		solo_slot_picker.add_theme_stylebox_override(state, field_style if state != "hover" else field_focus)
	solo_slot_picker.add_theme_color_override("font_color", UiTheme.INK)
	solo_slot_picker.add_theme_color_override("font_hover_color", UiTheme.INK)
	solo_slot_picker.add_theme_color_override("font_pressed_color", UiTheme.INK)
	solo_slot_picker.add_theme_color_override("font_focus_color", UiTheme.INK)
	for slot in range(1, SoloSlots.SLOT_COUNT + 1):
		solo_slot_picker.add_item("Survivor %d" % slot, slot)
	solo_slot_picker.select(0)
	solo_slot_picker.item_selected.connect(func(_index: int) -> void: _update_solo_slot_info())
	box.add_child(solo_slot_picker)
	solo_slot_info = Label.new()
	solo_slot_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	solo_slot_info.add_theme_font_size_override("font_size", 12)
	solo_slot_info.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(solo_slot_info)
	_update_solo_slot_info()
	var graphics_caption := Label.new()
	graphics_caption.text = "Graphics quality (Ctrl+F11 in game)"
	graphics_caption.add_theme_font_size_override("font_size", 14)
	graphics_caption.add_theme_color_override("font_color", Color(0.95, 0.84, 0.66))
	box.add_child(graphics_caption)
	var quality_picker := OptionButton.new()
	_quality_picker = quality_picker
	quality_picker.custom_minimum_size = Vector2(0, 40)
	for state in ["normal", "hover", "pressed", "focus"]:
		quality_picker.add_theme_stylebox_override(state, field_style if state != "hover" else field_focus)
	quality_picker.add_theme_color_override("font_color", UiTheme.INK)
	quality_picker.add_theme_color_override("font_hover_color", UiTheme.INK)
	quality_picker.add_theme_color_override("font_pressed_color", UiTheme.INK)
	for quality_level in GraphicsQuality.NAMES.size():
		quality_picker.add_item(GraphicsQuality.NAMES[quality_level], quality_level)
	quality_picker.add_item("Auto (GPU-aware 3D + details)", GraphicsQuality.NAMES.size())
	quality_picker.select(GraphicsQuality.NAMES.size() if _auto_graphics else GraphicsQuality.level())
	quality_picker.item_selected.connect(func(index: int) -> void:
		_apply_graphics_selection(quality_picker.get_item_id(index)))
	box.add_child(quality_picker)
	# The same Settings window is available from the connection screen.
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(0, 40)
	settings_button.pressed.connect(func() -> void:
		if _access != null and is_instance_valid(_access.menu):
			_access.menu.open())
	box.add_child(settings_button)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap2)
	var solo := Button.new()
	solo.text = "PLAY SOLO"
	solo.tooltip_text = "Runs the world on this computer (every system, saved between sessions) and joins it."
	solo.custom_minimum_size = Vector2(0, 50)
	solo.add_theme_font_size_override("font_size", 20)
	solo.add_theme_stylebox_override("normal", _pill(Color(0.72, 0.13, 0.1)))
	solo.add_theme_stylebox_override("hover", _pill(Color(0.84, 0.2, 0.14)))
	solo.add_theme_stylebox_override("pressed", _pill(Color(0.55, 0.08, 0.06)))
	solo.pressed.connect(_play_solo)
	box.add_child(solo)
	var button := Button.new()
	button.text = "Join server"
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _pill(Color(0.3, 0.2, 0.13)))
	button.add_theme_stylebox_override("hover", _pill(Color(0.42, 0.29, 0.17)))
	button.add_theme_stylebox_override("pressed", _pill(Color(0.22, 0.14, 0.08)))
	button.pressed.connect(_connect_remote)
	box.add_child(button)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(0, 34)
	quit.add_theme_font_size_override("font_size", 14)
	quit.add_theme_stylebox_override("normal", _pill(Color(0.18, 0.15, 0.13)))
	quit.add_theme_stylebox_override("hover", _pill(Color(0.3, 0.24, 0.2)))
	quit.add_theme_stylebox_override("pressed", _pill(Color(0.12, 0.1, 0.08)))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", "dev"))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 11)
	version.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62, 0.7))
	box.add_child(version)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.55))
	box.add_child(status_label)
	var credits := Label.new()
	credits.text = "Models and textures: Poly Haven, Quaternius, Kenney, KayKit (CC0) and more - see docs/ASSETS.md"
	credits.add_theme_font_size_override("font_size", 12)
	credits.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68, 0.8))
	credits.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	credits.grow_horizontal = Control.GROW_DIRECTION_BOTH
	credits.position.y -= 34
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	backdrop.add_child(credits)
	# The whole title screen comes and goes with the sign-in card.
	connect_panel.visibility_changed.connect(func() -> void: backdrop.visible = connect_panel.visible)


## A rounded pill button with a gold rim, the main action of the title screen.
static func _pill(color: Color) -> StyleBoxFlat:
	var style := UiTheme._box(color, 24, 3.0, UiTheme.GOLD, 8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style


func _device_id() -> String:
	var path := "user://device_id.txt"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	var id := "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(id)
	return id


## Remote servers always use the ordinary Nakama sign-in path.
func _connect_remote() -> void:
	_solo_offline_account = false
	_solo_attempts_left = 0
	_connect()


func _connect() -> void:
	var parts := address_edit.text.split(":")
	var host := parts[0]
	var port := int(parts[1]) if parts.size() > 1 else 24565
	if net == null:
		status_label.text = "Entering offline survivor..." if _solo_offline_account else "Signing in..."
		# Additional solo slots are deliberately local even if Nakama is running.
		# Do not sign in or open a live guild/chat session for these characters.
		social = Social.new()
		add_child(social)
		account = {}
		if not _solo_offline_account:
			var nakama_port := int(OS.get_environment("NAKAMA_PORT")) if OS.get_environment("NAKAMA_PORT") != "" else 7350
			account = await social.sign_in(host, nakama_port, _device_id() + ("-" + name_edit.text if OS.get_environment("MULTI_CLIENT") != "" else ""), name_edit.text)
			if not account.get("ok", false):
				account = {}
		net = Net.new()
		net.name = "Net"
		net.role = "client"
		get_tree().root.add_child.call_deferred(net) # RPC paths must match the server: /root/Net.
		client = GameClient.new(net)
		if not NetProtocol.install(multiplayer as SceneMultiplayer, net,
				Callable(self, "_on_rpc_protocol_rejected")):
			status_label.text = "Cannot initialize network RPC protocol."
			return
		multiplayer.peer_authentication_failed.connect(_on_rpc_authentication_failed)
		multiplayer.connected_to_server.connect(func() -> void:
			NetTimeouts.apply(peer, 1) # Loading the world must not time the link out.
			status_label.text = "Joining..."
			client.join(name_edit.text, account.get("token", ""), account.get("refresh", "")))
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(func() -> void:
			if not _rpc_protocol_failed:
				status_label.text = "Disconnected."
			connect_panel.visible = true)
		net.welcomed.connect(_on_welcomed)
		net.join_refused.connect(func(reason: String) -> void: status_label.text = reason)
	_open_peer(host, port)


## The ENet connection alone, so a solo world that is still starting can be retried without signing in again.
func _open_peer(host: String, port: int) -> void:
	_rpc_protocol_failed = false
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(host, port) != OK:
		status_label.text = "Could not connect."
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting..." if _solo_attempts_left == 0 else "Starting your world..."


func _on_rpc_protocol_rejected(_peer_id: int) -> void:
	_rpc_protocol_failed = true
	status_label.text = "Incompatible RPC protocol. Restart/update both client and server from the same build."
	connect_panel.visible = true


func _on_rpc_authentication_failed(peer_id: int) -> void:
	# Also covers old servers that do not implement the pre-RPC handshake.
	_on_rpc_protocol_rejected(peer_id)


func _on_connection_failed() -> void:
	if _rpc_protocol_failed:
		return
	if _solo_attempts_left > 0 and local_server.is_running():
		_solo_attempts_left -= 1
		await get_tree().create_timer(1.5).timeout
		var parts := address_edit.text.split(":")
		_open_peer(parts[0], int(parts[1]))
		return
	status_label.text = "Connection failed."


## The selection changes only which local world is launched, not gameplay rules.
func _update_solo_slot_info() -> void:
	if solo_slot_picker == null or solo_slot_info == null:
		return
	var slot: int = solo_slot_picker.get_selected_id()
	solo_slot_info.text = SoloSlots.description(slot)


## Start the selected local character on its private single-player ENet port.
func _play_solo() -> void:
	var selected_slot: int = solo_slot_picker.get_selected_id() if solo_slot_picker != null else 1
	var address: String = local_server.start(selected_slot)
	if address.is_empty():
		status_label.text = "Could not start a local world."
		return
	address_edit.text = address
	_solo_offline_account = selected_slot > 1
	_solo_attempts_left = 12
	status_label.text = "Starting survivor %d..." % selected_slot
	await get_tree().create_timer(3.0).timeout # Let the server import and open its port.
	_connect()


## Chopping and harvesting loops while the server says this player is gathering.
func _gather_animation() -> String:
	var action: Dictionary = client.you.get("action", {})
	if action.is_empty():
		return ""
	if action.has("fish"):
		return "Idle_Torch_Loop" # The rod held out over the water.
	var node: Dictionary = client.node_by_id(int(action.get("node", 0)), client.predicted)
	return "TreeChopping_Loop" if node.get("kind", "") == "tree" else "Farm_Harvest"


## While a cast runs: a line from the rod tip to a bobber on the water that rides the waves and dips when a fish bites
## (the last second of the cast); a splash ring when it ends with a catch.
func _update_fishing_line(_delta: float) -> void:
	var action: Dictionary = client.you.get("action", {})
	var fishing: bool = action.has("fish") and avatar.visible
	if not fishing:
		if _fishing_line != null:
			_fishing_line.visible = false
			_bobber.visible = false
		_bobber_spot = Vector3.INF
		return
	if _fishing_line == null:
		_fishing_line = MeshInstance3D.new()
		_fishing_line.mesh = ImmediateMesh.new()
		var thread := StandardMaterial3D.new()
		thread.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		thread.albedo_color = Color(0.92, 0.92, 0.88, 0.85)
		thread.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fishing_line.material_override = thread
		add_child(_fishing_line)
		_bobber = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.07
		ball.height = 0.14
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.9, 0.15, 0.1)
		ball.material = paint
		_bobber.mesh = ball
		add_child(_bobber)
	var here: Vector3 = avatar.global_position
	if _bobber_spot == Vector3.INF:
		# The water the cast reaches: straight ahead if it is water, else the nearest water around, 2 to 3.6 m out.
		var forward := Vector2(sin(avatar.rotation.y), cos(avatar.rotation.y))
		var best := Vector2(here.x, here.z) + forward * 3.0
		if not client.world.is_water(best.x, best.y):
			for i in 16:
				var probe := Vector2(here.x, here.z) + Vector2.from_angle(float(i) * TAU / 16.0) * 3.0
				if client.world.is_water(probe.x, probe.y):
					best = probe
					break
		_bobber_spot = Vector3(best.x, Defs.WATER_LEVEL, best.y)
		_last_cast_spot = _bobber_spot
	var remaining: float = float(action.get("remaining", 1.0))
	var bite_left: float = float(action.get("bite_at", -10.0))
	var bite: bool = remaining <= bite_left and remaining > bite_left - Fishing.BITE_WINDOW and not bool(action.get("struck", false))
	var hooked: bool = bool(action.get("hooked", false))
	var time: float = Time.get_ticks_msec() / 1000.0
	var bob: Vector3 = _bobber_spot + Vector3(0, 0.03 * sin(time * 2.4) - (0.12 + 0.05 * sin(time * 30.0) if bite else 0.0), 0)
	if hooked: # The fish has it under and pulls toward the shore.
		bob = _bobber_spot.lerp(Vector3(here.x, Defs.WATER_LEVEL, here.z), 0.25) - Vector3(0, 0.25, 0)
	_bobber.visible = true
	_bobber.global_position = bob
	var forward3 := Vector3(sin(avatar.rotation.y), 0, cos(avatar.rotation.y))
	var tip: Vector3 = avatar_model.rod_tip()
	if tip == Vector3.INF:
		tip = here + Vector3(0, 2.0, 0) + forward3 * 1.4
	var mesh := _fishing_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9: # A slight sag between tip and bobber.
		var k: float = float(i) / 8.0
		mesh.surface_add_vertex(tip.lerp(bob, k) - Vector3(0, sin(k * PI) * 0.35, 0))
	mesh.surface_end()
	_fishing_line.visible = true


var _carried_light: OmniLight3D


## A warm light around you underground (a lantern's worth), so the rooms between torches are not black.
func _set_carried_light(on: bool) -> void:
	if avatar == null:
		return
	if _carried_light == null:
		_carried_light = OmniLight3D.new()
		_carried_light.light_color = Color(1.0, 0.8, 0.55)
		_carried_light.light_energy = 1.3
		_carried_light.omni_range = 8.0
		_carried_light.position = Vector3(0, 2.4, 0)
		avatar.add_child(_carried_light)
	_carried_light.visible = on


## Where the planned wall would stand: 2.8 m out along the aim.
func _build_target() -> Vector2:
	var direction: Vector2 = _aim_direction()
	if direction.length_squared() < 0.001:
		direction = Vector2(sin(avatar.rotation.y), cos(avatar.rotation.y))
	return Vector2(client.predicted.x, client.predicted.z) + direction.normalized() * 2.8


## Where a house piece would go: aimed 3.5 m ahead, snapped to the grid (x, z, yaw).
func _piece_target() -> Vector3:
	var direction: Vector2 = _aim_direction()
	if direction.length_squared() < 0.001:
		direction = Vector2(sin(avatar.rotation.y), cos(avatar.rotation.y))
	var aim := Vector2(client.predicted.x, client.predicted.z) + direction.normalized() * 3.5
	return HousePieces.snap(_build_piece, aim, atan2(direction.x, direction.y))


func _piece_reason(snapped: Vector3) -> String:
	var reason: String = HousePieces.placement_reason(client.world, _build_piece, snapped, Vector2(client.predicted.x, client.predicted.z))
	if reason != "":
		return reason
	for item in client.barricades.values():
		var other: String = str(item.get("piece", ""))
		if other != "" and HousePieces.slot(other) == HousePieces.slot(_build_piece) \
				and Vector2(float(item["x"]) - snapped.x, float(item["z"]) - snapped.y).length() < 0.2:
			return "occupied"
	if not client.inventory.has_all(HousePieces.COST[_build_piece]):
		return "missing_materials"
	return ""


func _select_build_piece(index: int) -> void:
	_build_piece = BUILD_PIECES[posmod(index, BUILD_PIECES.size())]
	if _build_ghost != null:
		_build_ghost.mesh = EntityView.piece_mesh(_build_piece, 1) if _build_piece != "" else EntityView.wall_mesh(1)


## The ghost wall of build mode: the real tier-1 model, see-through, green where it may stand and red where not.
func _update_build_ghost() -> void:
	if not _build_mode or not bool(client.you.get("alive", false)):
		if _build_ghost != null:
			_build_ghost.visible = false
		return
	if _build_piece != "":
		if _build_ghost == null:
			_update_build_ghost_legacy_setup()
		var snapped: Vector3 = _piece_target()
		_build_reason = _piece_reason(snapped)
		_build_ghost.visible = true
		_build_ghost.global_position = Vector3(snapped.x, client.world.height_at(snapped.x, snapped.y) + HousePieces.elevation(_build_piece), snapped.y)
		_build_ghost.rotation.y = snapped.z
		(_build_ghost.material_override as StandardMaterial3D).albedo_color = \
			Color(0.35, 1.0, 0.45, 0.45) if _build_reason == "" else Color(1.0, 0.3, 0.25, 0.45)
		return
	_update_build_ghost_legacy()


func _update_build_ghost_legacy_setup() -> void:
	_build_ghost = MeshInstance3D.new()
	_build_ghost.mesh = EntityView.piece_mesh(_build_piece, 1) if _build_piece != "" else EntityView.wall_mesh(1)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_build_ghost.material_override = glass
	_build_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_build_ghost)


func _update_build_ghost_legacy() -> void:
	if _build_ghost == null:
		_build_ghost = MeshInstance3D.new()
		_build_ghost.mesh = EntityView.wall_mesh(1)
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_build_ghost.material_override = glass
		_build_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_build_ghost)
	var target: Vector2 = _build_target()
	_build_reason = Structures.placement_reason(client.world, target, Vector2(client.predicted.x, client.predicted.z))
	if _build_reason == "" and not client.inventory.has_all(Structures.COST):
		_build_reason = "missing_materials"
	_build_ghost.visible = true
	_build_ghost.global_position = Vector3(target.x, client.world.height_at(target.x, target.y), target.y)
	_build_ghost.rotation.y = _build_yaw
	(_build_ghost.material_override as StandardMaterial3D).albedo_color = \
		Color(0.35, 1.0, 0.45, 0.45) if _build_reason == "" else Color(1.0, 0.3, 0.25, 0.45)


func _place_wall() -> void:
	_update_build_ghost()
	if _build_reason != "":
		hud.say("Cannot build here: %s." % _build_reason.replace("_", " "))
		return
	if _build_piece != "":
		var snapped: Vector3 = _piece_target()
		client.build_piece(_build_piece, Vector2(snapped.x, snapped.y), snapped.z)
		return # Stay in build mode: houses take many pieces.
	client.build(_build_target(), _build_yaw)
	_end_build_mode()


func _end_build_mode() -> void:
	_build_mode = false
	if _build_ghost != null:
		_build_ghost.visible = false


## Camera shake through the fork's built-in Camera3D trauma, which decays by itself.
func _shake(amount: float) -> void:
	if camera != null and camera.has_method("add_trauma"):
		camera.add_trauma(amount * UiSettings.shake_scale()) # "Reduce screen shake" accessibility option.


## Particles for what just happened, at the place it happened.
func _spawn_effects(event: Dictionary) -> void:
	var here: Vector3 = client.display_position() + Vector3(0, 1.0, 0)
	# The real server emits this once at impact; never flash on mere warning,
	# ordinary rain, or while underground. No new dynamic light is allocated.
	if str(event.get("type", "")) == "lightning_struck" and atmosphere != null and UiSettings.flash_scale() > 0.0 and \
			event.has("x") and event.has("z") and \
			not Dungeon.is_underground(float(client.you.get("x", 0.0))):
		var strike_xz := Vector2(float(event["x"]), float(event["z"]))
		if strike_xz.is_finite():
			var distance_m: float = Vector2(here.x, here.z).distance_to(strike_xz)
			atmosphere.trigger_lightning(distance_m)
	var at := here
	if event.has("x") and event.has("z"):
		at = Vector3(event["x"], client.world.height_at(event["x"], event["z"]) + 1.0, event["z"])
	# Trigger from the server-confirmed impact only. Accessibility flash
	# settings do not silence thunder; underground areas remain sheltered.
	if str(event.get("type", "")) in ["lightning_struck", "distant_thunder"] \
			and _storm_thunder != null and client != null and client.world != null:
		_storm_thunder.on_strike(event, here, client.world.height_at,
			Dungeon.is_underground(float(client.you.get("x", 0.0))))
	if str(event.get("type", "")) == "fish_hooked" and int(event.get("peer", -1)) == client.peer_id and _last_cast_spot != Vector3.INF:
		effects.ring(_last_cast_spot + Vector3(0, 0.05, 0), Color(1.0, 1.0, 1.0), 0.8, 0.4)
		_shake(0.12)
	if str(event.get("type", "")) == "fished" and int(event.get("peer", -1)) == client.peer_id and _last_cast_spot != Vector3.INF:
		effects.ring(_last_cast_spot + Vector3(0, 0.05, 0), Color(0.85, 0.95, 1.0), 1.4, 0.7) # The fish breaks the surface.
	combat_vfx.handle_event(event, here, at, client.world.biome_at(at.x, at.z))
	camera_fx.on_event(event, client.peer_id, at.distance_to(here))
	if _damage_numbers != null:
		_damage_numbers.on_event(event, at, client.peer_id)
	if _ambient_birds != null and str(event.get("type", "")) in ["flash_thrown", "barricade_broken", "lightning_struck", "ember_thrown"]:
		_ambient_birds.startle(at) # RDR2-style: loud events flush the birds overhead.
	# VFX-graph sparks bounce off the ground and leave embers where they land.
	if str(event.get("type", "")) == "lightning_struck":
		var strike := Vector3(float(event.get("x", 0.0)), 0.0, float(event.get("z", 0.0)))
		strike.y = client.world.height_at(strike.x, strike.z)
		VfxPresets.spawn(self, VfxPresets.lightning_sparks(GraphicsQuality.level()), strike, int(strike.x * 31.0 + strike.z))
	if _blood_decals != null and str(event.get("type", "")) == "lightning_struck" \
			and BloodDecals.enabled(GraphicsQuality.level(), str(RenderingServer.get_current_rendering_method())):
		_blood_decals.scorch(client.world, float(event.get("x", 0.0)), float(event.get("z", 0.0)), float(event.get("radius", 3.0)))
	if _blood_decals != null and str(event.get("type", "")) == "hit" and float(event.get("damage", 0.0)) >= 4.0 \
			and BloodDecals.enabled(GraphicsQuality.level(), str(RenderingServer.get_current_rendering_method())):
		_blood_decals.splat(client.world, at.x, at.z, str(event.get("kind", "")) == "zombie", float(event.get("damage", 0.0)))
	# Hit flash on your own character too (remote ones flash from snapshot HP).
	if str(event.get("type", "")) == "hit" and str(event.get("kind", "")) != "zombie" \
			and int(event.get("id", -1)) == client.peer_id and avatar_model != null:
		avatar_model.hit_flash(0.6 + float(event.get("damage", 0.0)) / 40.0)
		if _damage_direction != null:
			var by: int = int(event.get("by", -1))
			var source: Dictionary = client.players.get(by, {}) if by > 0 else client.zombies.get(-by, {})
			if by != -1 and source.has("x"):
				_damage_direction.on_hit(Vector3(float(source["x"]), 0.0, float(source["z"])), float(event.get("damage", 0.0)))
	if str(event.get("type", "")) == "attack":
		_last_charge[int(event.get("peer", -1))] = float(event.get("charge", 0.0))
	if _wound_fx != null and str(event.get("type", "")) == "hit" and str(event.get("kind", "")) == "zombie":
		_wound_on_zombie(event)
	if _wound_fx != null and str(event.get("type", "")) == "ground_finisher":
		var peer_info: Dictionary = client.players.get(int(event.get("peer", -1)), {})
		var weapon_id: String = str(client.inventory.weapon) if int(event.get("peer", -1)) == client.peer_id else str(peer_info.get("weapon", ""))
		_wound_fx.finisher(entities.model_of("zombie", int(event.get("zombie", -1))), weapon_id, true)
	if str(event.get("type", "")) == "gathered" and streamer != null:
		for cell in streamer.get_loaded_cells():
			var chunk = streamer.get_chunk(cell)
			if chunk != null and chunk.has_method("shake"):
				chunk.shake(int(event.get("node", -1)))
	if str(event.get("type", "")) == "pounce_warning":
		entities.telegraph(int(event.get("id", -1)), float(event.get("seconds", 0.5)), str(event.get("kind", "")) == "charge")
	if str(event.get("type", "")) == "knocked_down" and int(event.get("peer", -1)) == client.peer_id:
		hud.say("Knocked down! Dodge (Shift+Space) or parry (RMB) the next leap.")
		if avatar_model != null:
			avatar_model.play_hit(true)
	if str(event.get("type", "")) == "zombie_leap":
		entities.leap(int(event.get("id", -1)), Vector3(float(event.get("fx", 0.0)), float(event.get("fy", 0.0)), float(event.get("fz", 0.0))),
			Vector3(float(event.get("x", 0.0)), float(event.get("y", 0.0)), float(event.get("z", 0.0))))
		if hud != null and int(event.get("target", -1)) == client.peer_id:
			hud.say("Infected drops from the tree!")
	if str(event.get("type", "")) == "knockdown":
		entities.play_hit("zombie", int(event.get("zombie", -1)), true)
	physics_fx.on_event(event, at)
	match event["type"]:
		"hit":
			if str(event.get("kind", "")) == "zombie":
				effects.hit_zombie(at)
				decals.splat(at, Color(0.3, 0.42, 0.12, 0.85), 0.8)
				entities.play_hit("zombie", int(event.get("id", -1)), float(event.get("damage", 0.0)) >= 30.0)
				CombatCameraFeedback.apply(camera, "hit_zombie", at, here, UiSettings.shake_scale())
			else:
				effects.hit_player(at)
				decals.splat(at, Color(0.45, 0.04, 0.04, 0.85), 0.7)
				if int(event.get("id", -1)) == client.peer_id:
					_shake(0.42) # You were hit.
					if avatar_model != null:
						avatar_model.play_hit(float(event.get("damage", 0.0)) >= 25.0)
				else:
					entities.play_hit("player", int(event.get("id", -1)))
		"zombie_died":
			effects.zombie_died(at)
			decals.splat(at, Color(0.25, 0.35, 0.1, 0.9), 1.6)
			CombatCameraFeedback.apply(camera, "zombie_died", at, here, UiSettings.shake_scale())
		"arcane_bolt":
			var bolt_end := Vector3(float(event.get("to_x", at.x)), at.y, float(event.get("to_z", at.z)))
			var bolt_from := at + Vector3(0, 0.3, 0)
			for step in 6:
				effects.burst(bolt_from.lerp(bolt_end, (step + 1) / 6.0), Color(0.55, 0.45, 1.0), 4, 0.6, 0.35, 0.12, 0.0, 0.0)
			effects.ring(bolt_end - Vector3(0, 1.0, 0), Color(0.6, 0.5, 1.0, 0.9), 1.4 if bool(event.get("hit", false)) else 0.7, 0.4)
		"howl":
			effects.ring(at - Vector3(0, 1.0, 0), Color(0.85, 0.7, 1.0, 0.7), minf(float(event.get("radius", 40.0)), 14.0), 1.1)
			effects.ring(at - Vector3(0, 0.9, 0), Color(0.85, 0.7, 1.0, 0.5), 6.0, 0.7)
		"eel_bite":
			effects.burst(at - Vector3(0, 0.6, 0), Color(0.6, 0.1, 0.1), 14, 1.6, 0.6, 0.1, -0.5)
			if int(event.get("peer", -1)) == client.peer_id:
				_shake(0.35)
		"drowning":
			effects.burst(at, Color(0.8, 0.95, 1.0), 20, 1.2, 1.0, 0.08, -3.0)
		"cataclysm":
			var blast_radius: float = float(event.get("radius", 7.0))
			effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.2, 1.0), blast_radius, 0.8)
			effects.ring(at - Vector3(0, 0.9, 0), Color(0.7, 0.4, 1.0, 0.9), blast_radius * 0.6, 0.6)
			effects.burst(at, Color(1.0, 0.6, 0.25), 60, blast_radius * 1.2, 0.9, 0.18, 2.0, 1.2)
			CombatCameraFeedback.apply(camera, "knockback", at, here, UiSettings.shake_scale())
			_shake(0.55)
		"restoration_pulse":
			effects.ring(at - Vector3(0, 1.0, 0), Color(0.4, 1.0, 0.55, 0.9), 6.0, 0.9)
			effects.burst(at, Color(0.5, 1.0, 0.6), 22, 2.4, 0.9, 0.1, -1.5)
		"knockback":
			effects.burst(at - Vector3(0, 0.8, 0), Color(0.62, 0.55, 0.45), 16, 3.2, 0.5, 0.14, 4.0)
			CombatCameraFeedback.apply(camera, "knockback", at, here, UiSettings.shake_scale())
		"pinning_bolt":
			effects.ring(at - Vector3(0, 1.0, 0), Color(0.45, 0.75, 1.0, 0.9), 1.6, 0.5)
		"flash_thrown":
			effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 1.0, 0.9, 1.0), 7.0, 0.45)
			effects.burst(at, Color(1.0, 1.0, 0.85), 30, 6.0, 0.35, 0.14, 0.0)
			CombatCameraFeedback.apply(camera, "flash_thrown", at, here, UiSettings.shake_scale())
		"ember_thrown":
			effects.burst(at, Color(1.0, 0.55, 0.15), 26, 2.6, 1.0, 0.1, -0.5)
		"decoy_thrown":
			effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.35, 0.8), 3.0, 0.8)
		"snare_triggered":
			effects.burst(at - Vector3(0, 0.6, 0), Color(0.5, 0.38, 0.22), 14, 2.0, 0.5, 0.1)
		"barricade_broken":
			effects.burst(at, Color(0.55, 0.38, 0.2), 34, 5.0, 0.9, 0.16, 9.0)
			# Physical Voronoi debris near the camera; far walls keep only the burst.
			BarricadeDebris.spawn(self, at, here)
			CombatCameraFeedback.apply(camera, "barricade_broken", at, here, UiSettings.shake_scale())
		"outpost_taken", "siege_contract_result":
			if at.distance_to(here) < 60.0:
				effects.ring(at - Vector3(0, 1.0, 0), Color(1.0, 0.82, 0.35, 0.9), 14.0, 1.4)
		"finishing_strike":
			effects.burst(at, Color(0.95, 0.22, 0.38),
				20, 4.3, 0.7, 0.12)
		"armor_sunder":
			effects.burst(at, Color(0.98, 0.55, 0.2),
				16, 2.8, 0.65, 0.11)
		"attack":
			if bool(event.get("ranged", false)):
				effects.muzzle_flash(at + Vector3(0, 0.2, 0))
				if int(event.get("peer", -1)) == client.peer_id:
					_shake(0.1)
		"gathered":
			var item: String = str(event.get("item", ""))
			var chips := Color(0.4, 0.7, 0.25)
			if item.begins_with("wood"):
				chips = Color(0.55, 0.38, 0.2)
			elif item.begins_with("stone") or item.begins_with("ore"):
				chips = Color(0.6, 0.6, 0.62)
			effects.gathered(at, chips)
			if bool(event.get("precise", false)):
				var node_for_impact: Dictionary = client.node_by_id(
					int(event.get("node", -1)), at)
				if not node_for_impact.is_empty():
					var impact: Vector3 = ResourceGathering.weakspot_position(
						node_for_impact, maxi(0, int(event.get("hit", 1)) - 1))
					effects.ring(impact, Color(1.0, 0.77, 0.25), 0.65, 0.32)
		"crate":
			effects.loot(here)
		"skill_up":
			effects.level_up(client.display_position() + Vector3(0, 0.6, 0))


func _on_skill_event(event: Dictionary) -> void:
	_spawn_effects(event)
	if event["type"] == "gathered":
		var gatherer: int = int(event.get("peer", -1))
		if gatherer == client.peer_id and int(event.get("amount", 0)) > 0:
			var reward: String = "+%d %s" % [int(event["amount"]),
				str(Defs.item(str(event.get("item", ""))).get("name", event.get("item", "")))]
			hud.say(("WEAK SPOT! " if bool(event.get("precise", false)) else "") + reward)
		if bool(event.get("strike", false)):
			var source: Dictionary = client.node_by_id(int(event.get("node", -1)),
				Vector3(float(event.get("x", client.predicted.x)), 0.0,
					float(event.get("z", client.predicted.z))))
			var clip: String = "TreeChopping_Loop" if str(source.get("kind", "")) == "tree" else "Farm_Harvest"
			if gatherer == client.peer_id and avatar_model != null:
				avatar_model.play_action(clip)
			elif gatherer != client.peer_id:
				entities.play_action_on("player", gatherer, clip)
	if event["type"] == "attack" and avatar_model != null:
		# Everyone's swings and shots: this player's own model, or the one drawn for that player.
		if int(event.get("peer", -1)) == client.peer_id:
			var mine: String = str(client.you.get("weapon", ""))
			avatar_model.play_action(EntityView.attack_animation(mine, bool(event.get("ranged", false))))
			var own_dir: Variant = event.get("dir", Vector2.ZERO)
			if own_dir is Vector2 and not bool(event.get("ranged", false)):
				entities.warp_model(avatar_model, avatar_model.global_position, mine, own_dir)
		else:
			var other: Dictionary = client.players.get(int(event.get("peer", -1)), {})
			var swing_dir: Variant = event.get("dir", Vector2.ZERO)
			entities.play_attack(int(event.get("peer", -1)), str(other.get("weapon", "")), bool(event.get("ranged", false)),
				swing_dir if swing_dir is Vector2 else Vector2.ZERO)
	# Throws show an overhand throw on whoever threw; opening a crate shows the lid going up.
	if event["type"] in ["flash_thrown", "ember_thrown", "decoy_thrown"]:
		var thrower: int = int(event.get("peer", -1))
		if thrower == client.peer_id and avatar_model != null:
			avatar_model.play_action("OverhandThrow", 1.2)
		else:
			entities.play_action_on("player", thrower, "OverhandThrow")
	elif event["type"] == "crate":
		if int(event.get("peer", -1)) == client.peer_id and avatar_model != null:
			avatar_model.play_action("Chest_Open", 1.3)
		else:
			entities.play_action_on("player", int(event.get("peer", -1)), "Chest_Open")
	match event["type"]:
		"finishing_strike":
			if int(event.get("peer", -1)) == client.peer_id:
				hud.say("FINISHING STRIKE — wounded infected!")
		"xp":
			var parts: Array[String] = []
			for skill_id in event["gains"]:
				parts.append("+%d %s" % [event["gains"][skill_id], Skills.SKILLS[skill_id]["name"] if Skills.SKILLS.has(skill_id) else skill_id])
			hud.say("  ".join(parts))
		"skill_up":
			var skill_name: String = Skills.SKILLS[event["skill"]]["name"] if Skills.SKILLS.has(event["skill"]) else str(event["skill"])
			hud.say("LEVEL UP: %s %d  (%d skill points, press K)" % [skill_name, event["level"], event["points"]])
			audio.play_ui("coin", -2.0)
		"perk":
			hud.say("Perk learned: %s" % Skills.PERKS[event["perk"]]["name"])
		"supply_drop":
			var guard_count: int = int(event.get("guards", 0))
			hud.say("SUPPLY DROP (T%d) at %.0f, %.0f — %d infected guards!" % [
				int(event.get("tier", 3)), float(event.get("x", 0)),
				float(event.get("z", 0)), guard_count])
		"supply_cleared":
			hud.say("SUPPLY CLEARED at %.0f, %.0f! The crate is public — collect it before rival parties!" % [
				float(event.get("x", 0)), float(event.get("z", 0))])
		"horde_started":
			hud.say("NIGHT HORDE (T%d): %d infected at %.0f, %.0f! Defeat them for a public trophy." % [
				int(event.get("tier", 3)), int(event.get("count", 0)),
				float(event.get("x", 0)), float(event.get("z", 0))])
		"horde_cleared":
			hud.say("HORDE DEFEATED! Public trophy at %.0f, %.0f — rival survivors can claim it!" % [
				float(event.get("x", 0)), float(event.get("z", 0))])
		"horde_expired":
			hud.say("The night horde dispersed at %.0f, %.0f." % [
				float(event.get("x", 0)), float(event.get("z", 0))])


func _setup_chat() -> void:
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Enter to chat. /g guild text, /guild name, /guilds, /join name, /leave"
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Offsets, not size: bottom-wide anchors would override size after _ready().
	chat_edit.offset_left = 320.0
	chat_edit.offset_right = -320.0
	chat_edit.offset_top = -44.0
	chat_edit.offset_bottom = -12.0
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_on_chat_submitted)
	hud.add_child(chat_edit)
	if not account.is_empty():
		social.message_received.connect(func(channel: String, sender: String, text: String) -> void: hud.say("[%s] %s: %s" % [channel, sender, text]))
		var started: bool = await social.start_chat("albion-world")
		hud.say("Chat connected. Press Enter to talk." if started else "Chat is unavailable.")
	else:
		hud.say("Playing without an account: nothing is saved, no chat.")


func _on_chat_submitted(text: String) -> void:
	chat_edit.text = ""
	chat_edit.visible = false
	chat_edit.release_focus()
	text = text.strip_edges()
	if text == "" or account.is_empty():
		return
	if text.begins_with("/g "):
		if not await social.say_guild(text.substr(3)):
			hud.say("You are not in a guild.")
	elif text.begins_with("/guilds"):
		var names: Array[String] = []
		for g in await social.list_guilds():
			names.append("%s (%d)" % [g["name"], g["members"]])
		hud.say("Guilds: " + (", ".join(names) if not names.is_empty() else "none yet"))
	elif text.begins_with("/guild "):
		var result: Dictionary = await social.create_guild(text.substr(7))
		hud.say("Guild founded." if result["ok"] else "Could not found a guild: %s" % result["reason"])
	elif text.begins_with("/join "):
		var wanted := text.substr(6).strip_edges()
		var found := false
		for g in await social.list_guilds(wanted):
			if g["name"] == wanted:
				var result: Dictionary = await social.join_guild(g["id"])
				hud.say("Joined %s." % wanted if result["ok"] else "Could not join: %s" % result.get("reason", "?"))
				found = true
		if not found:
			hud.say("No guild named %s." % wanted)
	elif text.begins_with("/leave"):
		hud.say("You left the guild." if await social.leave_guild() else "You are not in a guild.")
	else:
		await social.say(text)


func _on_welcomed() -> void:
	connect_panel.visible = false
	if _start_first_person:
		_set_first_person.call_deferred(true)
	hud = Hud.new()
	add_child(hud)
	hud.setup(client)
	camera_fx.hud = hud
	# Albion-style gear ability bar above the bottom HUD edge.
	var ability_bar := AbilityBar.new()
	ability_bar.name = "AbilityBar"
	ability_bar.client = client
	ability_bar.aim = _aim_direction
	ability_bar.anchor_left = 0.5
	ability_bar.anchor_right = 0.5
	ability_bar.anchor_top = 1.0
	ability_bar.anchor_bottom = 1.0
	ability_bar.offset_left = -310.0
	ability_bar.offset_right = 310.0
	ability_bar.offset_top = -168.0
	ability_bar.offset_bottom = -124.0
	hud.add_child(ability_bar)
	_access.setup(client, camera, func() -> bool: return _build_mode or hud.is_menu_open() or _typing())
	hud.social = social
	skills_panel = SkillsPanel.new()
	hud.add_child(skills_panel)
	skills_panel.setup(client)
	help_panel = HelpPanel.new()
	hud.add_child(help_panel)
	world_map = WorldMap.new()
	hud.add_child(world_map)
	world_map.setup(client)
	world_map.personal_waypoint_changed.connect(hud._radar.set_personal_waypoint)
	overlay = WorldOverlay.new()
	overlay.name = "WorldOverlay"
	hud.add_child(overlay)
	hud.move_child(overlay, 0) # Under every panel and card.
	overlay.setup(client, camera)
	outposts = OutpostView.new()
	add_child(outposts)
	hud.say("F2 shows every control." if not FirstSteps.active() else "Welcome, survivor. Follow FIRST STEPS (top left); F2 lists every control.")
	UiTheme.apply(hud)
	client.event_received.connect(_on_skill_event)
	client.event_received.connect(_first_person_hit_marker) # Crosshair hit flash and held-item swing in first person.
	_setup_chat()
	# Distant landscape beyond the streamed chunks: far terrain ring + impostor forests.
	_far_field = FarField.new()
	_far_field.name = "FarField"
	add_child(_far_field)
	_far_field.setup(client.world)
	var buoyancy = Buoyancy.new()
	buoyancy.name = "Buoyancy"
	buoyancy.world = client.world
	add_child(buoyancy)
	_pcg_dressing = PcgWorldDressing.new()
	_pcg_dressing.name = "PcgDressing"
	add_child(_pcg_dressing)
	_pcg_dressing.setup(client.world)
	# Streaming: chunks are built from the seed as the player walks.
	streamer = WorldStreamer.new()
	streamer.cell_size = Defs.CHUNK_SIZE
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.load_radius = 150.0
	streamer.unload_radius = 220.0
	streamer.update_interval = 0.15
	# Unreal-style independent simulation tier: keep far terrain and props
	# loaded, but pause ChunkView's grass/decor/shadow/windmill CPU updates.
	# Only client cosmetics opt in; networking and collision stay untouched.
	if "simulation_radius" in streamer:
		streamer.simulation_radius = 110.0
		streamer.simulation_hysteresis = 20.0
		streamer.max_simulation_transitions_per_update = 4
	# Unreal-style reduced cosmetic tick rate for distant but still active
	# scene chunks. GraphicsQuality.apply supplies radius/interval per preset.
	if "tick_throttle_radius" in streamer:
		streamer.max_tick_throttle_transitions_per_update = 4
	# Recover from transient generator/resource failures without an unbounded retry loop.
	# A null chunk remains an intentionally empty world cell.
	# Older engine builds lack the retry API; skip it instead of erroring.
	if "max_auto_retries" in streamer:
		streamer.max_auto_retries = 2
		streamer.retry_initial_delay = 0.5
		streamer.retry_max_delay = 3.0
		# Spread correlated failures across updates instead of retrying an
		# entire damaged procedural region on the same client frame.
		if streamer.has_method("set_retry_delay_spread"):
			streamer.set_retry_delay_spread(0.30)
			streamer.set_max_retry_releases_per_update(2)
	# Prioritize content ahead of actual movement while keeping the same
	# resident-world radius and unload hysteresis.
	streamer.lookahead_seconds = 2.0
	# Time-sliced chunk creation: allow several cheap chunks on a fast frame,
	# but stop after the first expensive one. Each chunk is indivisible.
	# The engine ensures that both streaming update paths share one drain.
	streamer.max_instantiations_per_frame = 3
	streamer.max_chunk_work_usec = 2500
	# Learn per-cell generator/finalization CPU cost and avoid scheduling a
	# second predicted-expensive cosmetic chunk inside the same frame.
	# A first chunk always runs; collisions/server simulation are unaffected.
	if streamer.has_method("set_predictive_chunk_work_budget_enabled"):
		streamer.set_predictive_chunk_work_budget_enabled(true)
	# Retain only 1-2 immutable *client visual* chunks after unload; reattaching
	# them when the player backtracks avoids regenerating their terrain/props.
	# Hard native cap + per-node opt-in; no server entities or physics cached.
	if "max_cached_chunks" in streamer:
		streamer.max_cached_chunks = 2 if GraphicsQuality.level() >= 2 else 1
	if streamer.has_method("set_max_cached_chunk_bytes"):
		streamer.set_max_cached_chunk_bytes(
			GraphicsQuality.streamed_chunk_cache_bytes_for_quality(GraphicsQuality.level()))
	if streamer.has_method("set_cached_chunk_retention_seconds"):
		streamer.set_cached_chunk_retention_seconds(
			GraphicsQuality.streamed_chunk_cache_retention_for_quality(GraphicsQuality.level()))
	if streamer.has_method("set_max_cached_expirations_per_frame"):
		streamer.set_max_cached_expirations_per_frame(
			GraphicsQuality.streamed_cache_expirations_for_quality(GraphicsQuality.level()))
		streamer.set_max_cached_expiration_work_usec(
			GraphicsQuality.streamed_cache_expiration_usec_for_quality(GraphicsQuality.level()))
	# Slow-frame backpressure is an opt-in extension. Older Godot forks
	# retain their unchanged fixed streaming budgets.
	if "adaptive_chunk_budget_enabled" in streamer:
		streamer.adaptive_chunk_budget_enabled = true
	# Stage the initial *cosmetic* world area from nearby terrain outward.
	# No authority/physics/quest streaming is deferred by this client-only
	# startup ramp. Older engine builds retain their immediate full radius.
	if streamer.has_method("begin_loading_range_ramp"):
		streamer.begin_loading_range_ramp(
			GraphicsQuality.startup_streaming_area_for_quality(GraphicsQuality.level()),
			0.4, GraphicsQuality.startup_streaming_ramp_duration(GraphicsQuality.level()))
	streamer.set_chunk_generator(_generate_chunk)
	add_child(streamer)
	# Terrain runtime virtual texture: the finished ground material baked into pages around the camera.
	_terrain_rvt = TerrainRvt.new()
	_terrain_rvt.name = "TerrainRvt"
	add_child(_terrain_rvt)
	_terrain_rvt.setup(camera, streamer, Defs.CHUNK_SIZE)
	# CGAME_AB="setting:a:b": same-scene A/B timing of one engine setting (ab_benchmark.gd).
	var ab: Node = AbBenchmark.from_environment()
	if ab != null:
		add_child(ab)
	# The map can now show native streaming-source readiness without any
	# gameplay RPC, scene creation, or extra work when the map is closed.
	world_map.world_streamer = streamer
	# Game-time, read-only startup ramp telemetry (100% once complete).
	if streamer.has_method("get_loading_range_area_percent"):
		var loading_area_monitor: StringName = &"Albion/StreamLoadAreaPct"
		if not Performance.has_custom_monitor(loading_area_monitor):
			Performance.add_custom_monitor(loading_area_monitor,
				Callable(streamer, "get_loading_range_area_percent"))
			_ambient_monitors.append(loading_area_monitor)
	# Retries respect the normal generation/activation budgets; these
	# counters expose waiting failures and admission pressure separately.
	if streamer.has_method("get_last_retry_deferred_count") and streamer.has_method("get_retry_pending_count") \
			and streamer.has_method("get_last_retry_release_count"):
		for monitor in [
			[&"Albion/StreamRetryPending", Callable(streamer, "get_retry_pending_count")],
			[&"Albion/StreamRetryReleased", Callable(streamer, "get_last_retry_release_count")],
			[&"Albion/StreamRetryDeferred", Callable(streamer, "get_last_retry_deferred_count")],
		]:
			var retry_monitor_name: StringName = monitor[0]
			if not Performance.has_custom_monitor(retry_monitor_name):
				Performance.add_custom_monitor(retry_monitor_name, monitor[1])
				_ambient_monitors.append(retry_monitor_name)
	# Native forecast telemetry is intentionally distinct from measured CPU.
	if streamer.has_method("get_last_predicted_deferred_chunk_count"):
		for monitor in [
			[&"Albion/StreamGeneratorPredictedCPUus", Callable(streamer, "get_estimated_generator_work_usec")],
			[&"Albion/StreamFinalizePredictedCPUus", Callable(streamer, "get_estimated_finalization_work_usec")],
			[&"Albion/StreamPredictiveDeferred", Callable(streamer, "get_last_predicted_deferred_chunk_count")],
		]:
			var monitor_name: StringName = monitor[0]
			if not Performance.has_custom_monitor(monitor_name):
				Performance.add_custom_monitor(monitor_name, monitor[1])
				_ambient_monitors.append(monitor_name)
	# Read-only, engine-sourced telemetry: stream backpressure, real main-
	# thread chunk work and the currently effective CPU/count limits.
	if streamer.has_method("get_last_frame_chunk_work_usec"):
		for monitor in [
			[&"Albion/StreamChunkCPUus", Callable(streamer, "get_last_frame_chunk_work_usec")],
			[&"Albion/StreamChunkAttempts", Callable(streamer, "get_last_frame_chunk_attempt_count")],
			[&"Albion/StreamPressurePct", Callable(streamer, "get_streaming_frame_pressure_percent")],
			[&"Albion/StreamEffectiveSlots", Callable(streamer, "get_effective_instantiations_per_frame")],
			[&"Albion/StreamEffectiveCPUus", Callable(streamer, "get_effective_chunk_work_usec")],
		]:
			var monitor_name: StringName = monitor[0]
			if not Performance.has_custom_monitor(monitor_name):
				Performance.add_custom_monitor(monitor_name, monitor[1])
				_ambient_monitors.append(monitor_name)
	if streamer.has_method("get_simulation_active_count"):
		var simulation_monitor: StringName = &"Albion/StreamSimulationActive"
		if not Performance.has_custom_monitor(simulation_monitor):
			Performance.add_custom_monitor(simulation_monitor,
				Callable(streamer, "get_simulation_active_count"))
			_ambient_monitors.append(simulation_monitor)
	if streamer.has_method("get_tick_throttled_count"):
		var tick_monitor: StringName = &"Albion/StreamCosmeticTickThrottled"
		if not Performance.has_custom_monitor(tick_monitor):
			Performance.add_custom_monitor(tick_monitor,
				Callable(streamer, "get_tick_throttled_count"))
			_ambient_monitors.append(tick_monitor)
	if streamer.has_method("get_chunk_cache_hit_count"):
		for monitor in [
			[&"Albion/StreamCacheRetained", Callable(streamer, "get_cached_chunk_count")],
			[&"Albion/StreamCacheHits", Callable(streamer, "get_chunk_cache_hit_count")],
			[&"Albion/StreamCacheEvictions", Callable(streamer, "get_chunk_cache_eviction_count")],
		]:
			var monitor_name: StringName = monitor[0]
			if not Performance.has_custom_monitor(monitor_name):
				Performance.add_custom_monitor(monitor_name, monitor[1])
				_ambient_monitors.append(monitor_name)
	if streamer.has_method("get_cached_chunk_bytes"):
		var cache_bytes_monitor: StringName = &"Albion/StreamCacheEstimatedBytes"
		if not Performance.has_custom_monitor(cache_bytes_monitor):
			Performance.add_custom_monitor(cache_bytes_monitor,
				Callable(streamer, "get_cached_chunk_bytes"))
			_ambient_monitors.append(cache_bytes_monitor)
	if streamer.has_method("get_chunk_cache_expiration_count"):
		var cache_expiry_monitor: StringName = &"Albion/StreamCacheExpired"
		if not Performance.has_custom_monitor(cache_expiry_monitor):
			Performance.add_custom_monitor(cache_expiry_monitor,
				Callable(streamer, "get_chunk_cache_expiration_count"))
			_ambient_monitors.append(cache_expiry_monitor)
	if streamer.has_method("get_last_cached_expiration_work_usec"):
		for monitor in [
			[&"Albion/StreamCacheExpiryCPUus", Callable(streamer, "get_last_cached_expiration_work_usec")],
			[&"Albion/StreamCacheExpiryDeferred", Callable(streamer, "get_last_deferred_cached_expiration_count")],
		]:
			var monitor_name: StringName = monitor[0]
			if not Performance.has_custom_monitor(monitor_name):
				Performance.add_custom_monitor(monitor_name, monitor[1])
				_ambient_monitors.append(monitor_name)
	# The engine reports how many stale visual cells were retired versus
	# deferred by this quality-tier unload budget. Counters only update
	# during real streaming refreshes, not from a HUD polling loop.
	if streamer.has_method("get_last_deferred_unload_count"):
		for monitor in [
			[&"Albion/StreamUnloadedLastUpdate", Callable(streamer, "get_last_unload_count")],
			[&"Albion/StreamUnloadsDeferred", Callable(streamer, "get_last_deferred_unload_count")],
		]:
			var monitor_name: StringName = monitor[0]
			if not Performance.has_custom_monitor(monitor_name):
				Performance.add_custom_monitor(monitor_name, monitor[1])
				_ambient_monitors.append(monitor_name)
	# Wall-clock retirements include synchronous chunk unload callbacks.
	if streamer.has_method("get_last_unload_work_usec"):
		var unload_cpu_monitor: StringName = &"Albion/StreamUnloadCPUus"
		if not Performance.has_custom_monitor(unload_cpu_monitor):
			Performance.add_custom_monitor(unload_cpu_monitor,
				Callable(streamer, "get_last_unload_work_usec"))
			_ambient_monitors.append(unload_cpu_monitor)
	# Engine-driven effective visual cleanup budget, exposed in the game profiler.
	if streamer.has_method("get_effective_unloads_per_update"):
		var unload_monitor: StringName = &"Albion/StreamEffectiveUnloads"
		if not Performance.has_custom_monitor(unload_monitor):
			Performance.add_custom_monitor(unload_monitor,
				Callable(streamer, "get_effective_unloads_per_update"))
			_ambient_monitors.append(unload_monitor)
	_access.set_world_streamer(streamer)
	# Streamer is created after the initial renderer setup; apply its draw-distance budget now.
	GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
		streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics)
	hub_view = HubView.new()
	add_child(hub_view)
	hub_view.build(client.world)
	# Footprint projectors use the exact heightmap under each foot, not a
	# fixed y value that can float above sloped terrain.
	if _footprints != null:
		_footprints.setup(client.world)
	physics_fx.setup(client.world) # Debris, blasts and plant shakes need the terrain heightmap.
	# One GPU MultiMesh for forest fireflies and floating pollen; placements
	# follow terrain height, biome and the server-synchronised day cycle.
	_ambient_motes = AmbientMotes.new()
	_ambient_motes.setup(client.world)
	add_child(_ambient_motes)
	# Circling bird flock overhead in daylight; one MultiMesh draw call.
	_ambient_birds = AmbientBirds.new(client.world.world_seed)
	add_child(_ambient_birds)
	# Native Flock3D fish shoal in nearby deep water (empty on engines without it).
	_fish_shoals = FishShoals.new()
	add_child(_fish_shoals)
	_dusk_bats = DuskBats.new()
	add_child(_dusk_bats)
	_tumbleweeds = Tumbleweeds.new()
	add_child(_tumbleweeds)
	_zombie_flies = ZombieFlies.new()
	add_child(_zombie_flies)
	_dragonflies = Dragonflies.new()
	add_child(_dragonflies)
	_shooting_stars = ShootingStars.new()
	_shooting_stars.camera = camera
	add_child(_shooting_stars)
	_dust_devils = DustDevils.new()
	add_child(_dust_devils)
	_rain_splashes = RainSplashes.new()
	add_child(_rain_splashes)
	_damage_numbers = DamageNumbers.new()
	add_child(_damage_numbers)
	_wound_fx = WoundFx.new()
	add_child(_wound_fx)
	_blood_decals = BloodDecals.new()
	add_child(_blood_decals)
	_damage_direction = DamageDirection.new()
	_damage_direction.camera = camera
	add_child(_damage_direction)
	audio = Audio.new()
	add_child(audio)
	# Engine/stock audio voice-steal hold protects new combat audio attacks.
	var audio_hold_monitor: StringName = &"Albion/AudioVoiceHoldRejects"
	if not Performance.has_custom_monitor(audio_hold_monitor):
		Performance.add_custom_monitor(audio_hold_monitor,
			Callable(audio, "get_voice_hold_rejections"))
		_ambient_monitors.append(audio_hold_monitor)
	# Thunder has its own bounded event queue and 3D emitter so storm
	# arrival never steals slots from short combat and movement sounds.
	_storm_thunder = StormThunder.new()
	_storm_thunder.name = "PhysicalLightningThunder"
	add_child(_storm_thunder)
	client.event_received.connect(func(event: Dictionary) -> void: audio.on_event(event, client.peer_id, client.world.height_at))
	_raid_telegraph.clear()
	client.event_received.connect(func(event: Dictionary) -> void: _raid_telegraph.consume(event, client.world))
	client.snapshot_received.connect(func() -> void: _raid_telegraph.update_interrupt(client.raid_interrupt))
	avatar = Node3D.new()
	avatar_model = CharacterModel.new()
	avatar_model.setup(Color(1.0, 0.95, 0.5) if not Assets.has_characters() else Color.WHITE, 2.0, 1.0, Assets.CHARACTER_NAMES[abs(hash(name_edit.text)) % Assets.CHARACTER_NAMES.size()], false, abs(hash(name_edit.text)) / Assets.CHARACTER_NAMES.size())
	avatar.add_child(avatar_model)
	# Diablo/PoE-style X-ray rim where buildings or trees hide your character.
	OcclusionSilhouette.apply(avatar_model)
	avatar.add_child(BlobShadow.make(BlobShadow.wanted(bool(GraphicsQuality.profile(GraphicsQuality.level())["shadows"]))))
	bike_visual = TrailBikeVisual.new()
	bike_visual.name = "TrailBike"
	avatar.add_child(bike_visual)
	flare_visual = HandFlareVisual.new()
	flare_visual.name = "HandFlare"
	avatar.add_child(flare_visual)
	# No name over your own head: your name is on the portrait plate; other players keep theirs.
	add_child(avatar)
	# RDR2-style visible breath in cold air for the local character.
	_breath = BreathVapor.new()
	_breath.model = avatar_model
	add_child(_breath)
	_wet_drips = WetDrips.new()
	avatar.add_child(_wet_drips)


func _generate_chunk(cell: Vector3i) -> Node:
	var view := ChunkView.new()
	view.build(client.world, Vector2i(cell.x, cell.z))
	return view


func _physics_process(delta: float) -> void:
	if client == null or not client.welcomed or not client.you.has("x"):
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	var alive: bool = bool(client.you.get("alive", true))
	var move := Vector2.ZERO
	var sprint := false
	var crouch := false
	if alive and not _typing():
		var polled := UiAccess.read_move() # Rebindable keys, gamepad stick, hold-or-toggle sprint/crouch.
		move = polled["move"]
		sprint = polled["sprint"]
		crouch = polled["crouch"]
	else:
		UiAccess.clear_latches()
	move = move.limit_length(1.0)
	if _first_person:
		move = FirstPersonView.to_world_move(move, _fp_yaw)
	_move_input = move
	var aim := _aim_direction()
	var yaw: float = atan2(aim.x, aim.y) if aim != Vector2.ZERO else float(client.yaw)
	client.send_input(move, sprint, yaw, delta, crouch)
	_update_held_pickups()
	var can_swing: bool = alive and not _build_mode and not hud.is_menu_open() and not _access.is_open() and aim != Vector2.ZERO
	var hit_node: Dictionary = {}
	if can_swing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hit_node = client.nearest_strike_node(client.predicted, aim)
	if not hit_node.is_empty():
		# Mining/chopping takes priority over combat only when aimed at a nearby node.
		_charge_msec = -1
		if _attack_cooldown <= 0.0:
			client.resource_hit(int(hit_node["id"]), _resource_swing_aim(hit_node, aim))
			var tool: String = Defs.tool_tier_for_node(str(hit_node["kind"]))
			var equipped: String = client.inventory.best_tool(tool)
			var tier: int = Defs.tier_of(equipped) if not equipped.is_empty() else 0
			_attack_cooldown = ResourceGathering.swing_cooldown(tier)
			_last_attack_msec = Time.get_ticks_msec()
	elif can_swing and _melee_equipped():
		# Brawling: tap to swing, hold to wind up a power blow, release to strike.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _charge_msec < 0 and _attack_cooldown <= 0.0:
				_charge_msec = Time.get_ticks_msec()
		elif _charge_msec >= 0:
			var held: int = Time.get_ticks_msec() - _charge_msec
			_charge_msec = -1
			if held < CHARGE_START_MS:
				client.attack(aim)
			else:
				client.power_attack(aim, clampf(float(held - CHARGE_START_MS) / float(CHARGE_FULL_MS - CHARGE_START_MS), 0.0, 1.0))
			_attack_cooldown = 0.18
			_last_attack_msec = Time.get_ticks_msec()
	elif can_swing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _attack_cooldown <= 0.0:
		client.attack(aim)
		_attack_cooldown = 0.18
		_last_attack_msec = Time.get_ticks_msec()
	else:
		_charge_msec = -1


func _process(delta: float) -> void:
	if _capture_path != "" and client != null and client.welcomed:
		_capture_time += delta
		if _capture_time >= 60.0:
			get_viewport().get_texture().get_image().save_png(_capture_path)
			print("CLIENT capture saved: ", _capture_path)
			_capture_path = ""
	_frames += 1
	# Attribute frame hitches to shader compiles, streaming or VRAM growth.
	var hitch: Dictionary = _hitch_analyzer.sample(delta, FrameHitchAnalyzer.read_counters(
		streamer.get_loaded_count() if streamer != null else 0), Time.get_ticks_msec() / 1000.0)
	if _trace.enabled:
		_trace.frame_marker(_frames)
		_trace.counter("frame_ms", delta * 1000.0)
		_trace.counter("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_trace.counter("pipeline_compiles", float(int(FrameHitchAnalyzer.read_counters().get("compiles", 0))))
		if not hitch.is_empty():
			_trace.instant("hitch", hitch)
	if not hitch.is_empty():
		print_verbose("CLIENT hitch %.0f ms (median %.1f ms): %s" % [hitch["ms"], hitch["median_ms"], hitch["cause"]])
	# Resize only the Forward+ 3D target before changing costly world LOD.
	if _auto_graphics and client != null and client.welcomed:
		var rd: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
		# Godot returns GPU duration in milliseconds from the previous rendered
		# frame. It excludes CPU scripting/physics stalls and V-Sync waiting.
		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(
			get_viewport().get_viewport_rid()) if rd else 0.0
		if rd and _adaptive_resolution.sample_frame(delta, gpu_ms):
			GraphicsQuality.apply_resolution(get_viewport(), _adaptive_resolution.scale, true)
			_auto_quality.set_mode("auto")
		var quality_limit: bool = GraphicsAutoQuality.at_resolution_limit(
			rd, _adaptive_resolution.at_floor(), _adaptive_resolution.at_ceiling(), delta, gpu_ms)
		var step_down: bool = quality_limit and _auto_quality.sample_frame(delta, gpu_ms)
		# GPU memory pressure steps down too, before the driver starts paging textures.
		if not step_down and _auto_quality.mode == "auto" and _vram_budget.sample(
				Rendering.vram_used_bytes(), _auto_quality.level, delta):
			_auto_quality.level -= 1
			step_down = true
		if step_down:
			GraphicsQuality.set_level(_auto_quality.level, false)
			_adaptive_resolution.configure(GraphicsQuality.level(),
		GraphicsQuality.metalfx_resolution_floor())
			GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
				streamer, _adaptive_resolution.scale if rd else -1.0, rd)
	if _demo == "title" and _screenshot_path != "" and _frames == 90: # The title screen alone (screenshots).
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		get_tree().quit()
	if client == null or not client.welcomed or not client.you.has("x"):
		return
	client.decay_correction(delta)
	var position: Vector3 = client.display_position()
	physics_fx.update(delta, position)
	_update_grass_crushers(position)
	if avatar != null:
		avatar.position = position
		# The body turns where it walks; it faces the cursor while fighting, aiming (right mouse) or working, so walking
		# away from the cursor is a turn and a walk, not a moonwalk.
		var facing: float = client.yaw
		var busy: bool = not client.you.get("action", {}).is_empty() or Time.get_ticks_msec() - _last_attack_msec < 900 \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if not busy and _move_input.length() > 0.1:
			facing = atan2(_move_input.x, _move_input.y)
		elif not busy:
			facing = avatar.rotation.y
		avatar.rotation.y = lerp_angle(avatar.rotation.y, facing, 1.0 - exp(-12.0 * delta))
		avatar.visible = bool(client.you.get("alive", true))
		# Your own body would fill the screen from inside; other players still see it.
		avatar_model.visible = true # In first person its meshes are shadow-only (set_body_shadow_only).
		avatar_model.set_stance(bool(client.you.get("crouching", false)), bool(client.you.get("mounted", false)) and avatar.visible,
			float(client.you.get("wading_depth_m", 0.0)) > 1.05)
		# Chopping shows the axe; otherwise the equipped weapon is in hand.
		var in_hand: String = str(client.you.get("weapon", ""))
		if _gather_animation() == "TreeChopping_Loop":
			in_hand = "axe_1"
		elif client.you.get("action", {}).has("fish"):
			in_hand = "fishing_rod"
		if _first_person and in_hand != str(avatar_model.get("_held_id")):
			avatar_model.set_weapon(in_hand)
			FirstPersonView.set_body_shadow_only(avatar_model, true) # The new hand item too (added synchronously).
		else:
			avatar_model.set_weapon(in_hand)
		if _viewmodel != null and _first_person:
			_viewmodel.set_item(in_hand)
		_update_fishing_line(delta)
		_update_build_ghost()
		avatar_model.set_gear(client.inventory.gear)
		avatar_model.update_motion(delta)
		avatar_model.set_dead(not bool(client.you.get("alive", true)))
		avatar_model.set_action_loop(_gather_animation())
		var riding: bool = bool(client.you.get("mounted", false)) and avatar.visible
		bike_visual.set_panniers(client.inventory.count("bike_panniers") > 0)
		bike_visual.set_lamp(bool(client.you.get("bike_lamp_lit", false)))
		bike_visual.set_riding(riding, avatar_model.speed, delta)
		if _raft_visual == null:
			_raft_visual = RaftVisual.new()
			avatar.add_child(_raft_visual)
			_raft_visual.position.y = 0.05
		_raft_visual.set_rafting(bool(client.you.get("rafting", false)) and avatar.visible)
		flare_visual.set_burning(avatar.visible and float(client.you.get("flare_seconds", 0.0)) > 0.0)
		audio.set_footsteps(avatar_model._moving and avatar.visible and not riding)
		if not riding:
			effects.footsteps(position, avatar_model.speed, delta)
			combat_vfx.update_player(position, client.world.height_at(position.x, position.z), avatar_model.speed, delta, _visual_biome)
	if streamer != null:
		streamer.focus_position = position
		if _far_field != null:
			_far_field.update(position)
		_apply_data_layers(delta)
		if _pcg_dressing != null:
			_pcg_dressing.update(position, delta)
		# Cheap, local movement hint for native chunk queue ordering. Server
		# correction and teleports never prefetch in an unrelated direction.
		var moved: Vector3 = position - _stream_previous_position
		if _stream_has_previous_position and is_finite(delta) and delta > 0.0001 \
				and moved.length_squared() < 576.0:
			var measured_velocity: Vector3 = (moved / delta).limit_length(18.0)
			_stream_velocity = _stream_velocity.lerp(measured_velocity,
				clampf(delta * 7.0, 0.0, 1.0))
		else:
			_stream_velocity = Vector3.ZERO
		_stream_previous_position = position
		_stream_has_previous_position = true
		streamer.velocity_hint = _stream_velocity
		# Longer forward streaming on the bike; idle/teleport uses exact nearby cells.
		WorldStreamingPolicy.apply(streamer, bool(client.you.get("mounted", false)), _stream_velocity)
		# A single bounded native grid query twice per second, not once per frame.
		# Terrain remains server-independent; this is a client visual readiness cue.
		_world_streaming_status_elapsed += maxf(delta, 0.0)
		if _world_streaming_status_elapsed >= 0.5:
			_world_streaming_status_elapsed = fmod(_world_streaming_status_elapsed, 0.5)
			if hud != null:
				hud.world_streaming_notice = WorldStreamingPolicy.focus_loading_notice(streamer)
		# The private map marker only prefetches when near the player; the
		# native engine keeps extra cells bounded and never streams distant
		# objectives. No network RPC or simulation change is involved.
		WorldStreamingPolicy.apply_waypoint(streamer, world_map.waypoint, position,
			bool(client.you.get("mounted", false)))
		_apply_world_state()
	entities.update_from(client)
	_lightning_visual.set_warning(client.lightning_telegraph)
	outposts.update_from(client)
	_update_party_rally_marker()
	_update_party_supply_marker()
	# The camera glides after the player.
	camera_fx.update(delta, client.you, _move_input, avatar_model.speed if avatar_model != null else 0.0, GraphicsQuality.level())
	var target: Vector3 = position + CAMERA_OFFSET * _zoom * camera_fx.zoom_mul + camera_fx.look
	if camera_fx.photo_active:
		camera_fx.photo_camera(camera, position)
	elif _first_person:
		_update_first_person_camera(position, delta)
	else:
		camera.position = camera.position.lerp(target, 1.0 - exp(-10.0 * delta))
		camera.look_at(position + Vector3(0, 0.8, 0) + camera_fx.look)
	_update_first_person_mouse()
	if _jump_time >= 0.0:
		_jump_time += delta
		if _jump_time >= FirstPersonView.JUMP_SECONDS:
			_jump_time = -1.0
			_land_time = 0.0
	if _land_time >= 0.0:
		_land_time += delta
		if _land_time >= 0.35:
			_land_time = -1.0
	if _crosshair != null:
		_crosshair.visible = _first_person and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _screenshot_path != "")
		if _crosshair.visible:
			_hit_marker = move_toward(_hit_marker, 0.0, delta * 4.0)
			FirstPersonView.layout_crosshair(_crosshair, FirstPersonView.crosshair_spread(
				avatar_model.speed if avatar_model != null else 0.0, _jump_time >= 0.0), _hit_marker)
	if _brawl_meter == null and hud != null:
		_brawl_meter = BrawlMeter.new()
		hud.add_child(_brawl_meter)
	if _brawl_meter != null:
		_brawl_meter.visible = _first_person
		_brawl_meter.update_state(charge_amount(), _charge_msec >= 0, float(client.you.get("rage", 0.0)),
			float(client.you.get("rage_seconds", 0.0)), delta)
	_update_underwater()
	_tick_first_steps(delta)
	if _demo == "sky":
		# A low view toward the horizon to show the sky (screenshots only).
		camera.position = position + Vector3(0.0, 14.0, 6.0)
		camera.look_at(position + Vector3(0.0, 20.0, -60.0))
	# Camera-visible chunks load first while residency remains player-centered.
	if streamer != null:
		# Surface cosmetic chunks need no CPU animation when the survivor is
		# underground. Scene streaming and collision stay enabled throughout.
		WorldStreamingPolicy.apply_simulation_layers(streamer,
			Dungeon.is_underground(position.x))
		WorldStreamingPolicy.apply_view(streamer, camera, GraphicsQuality.level())
	# Native far-only DOF tracks player zoom/photo orbit at a bounded rate.
	# The character and nearby combat remain in focus; CanvasLayer HUD never
	# participates in 3D depth blur. Native DOF adds its own renderer cost,
	# but we avoid a duplicate custom fullscreen blur shader.
	_dof_elapsed += maxf(delta, 0.0)
	if _dof_elapsed >= 0.35:
		_dof_elapsed = fmod(_dof_elapsed, 0.35)
		GraphicsCinematicDof.apply(atmosphere.world_environment as WorldEnvironment,
			GraphicsQuality.level(), str(RenderingServer.get_current_rendering_method()),
			camera.global_position.distance_to(position + Vector3(0.0, 0.8, 0.0)),
			camera_fx.photo_active)
	water.position.x = position.x
	water.position.z = position.z
	if _sea != null and _sea.texture == null and client.world != null and _sea.step_depth_map(client.world):
		var sea_material := water.material_override as ShaderMaterial
		sea_material.set_shader_parameter("shore_map", _sea.texture)
		sea_material.set_shader_parameter("has_shore_map", 1.0)
	_update_time_of_day(delta)
	_track_places(delta)
	_update_prompt()
	_run_demo()


func _apply_world_state() -> void:
	# Depletion changes geometry and terrain contact; strike progress changes
	# only GPU instance tint. Never rescan every resource on an ordinary hit.
	var revision: int = client.world_state_revision
	var damage_revision: int = client.resource_damage_revision
	var hidden: Dictionary = {}
	for cell in streamer.get_loaded_cells():
		var chunk := streamer.get_chunk(cell)
		if chunk == null or not chunk.has_method("apply_state"):
			continue
		var geometry_dirty: bool = not chunk.has_meta("aa_state_revision") \
			or int(chunk.get_meta("aa_state_revision")) != revision
		var damage_dirty: bool = not chunk.has_meta("aa_damage_revision") \
			or int(chunk.get_meta("aa_damage_revision")) != damage_revision
		if not geometry_dirty and not damage_dirty:
			continue
		if geometry_dirty:
			if hidden.is_empty():
				hidden.merge(client.depleted)
				hidden.merge(client.crates_used)
			chunk.apply_state(hidden)
			chunk.set_meta("aa_state_revision", revision)
		if damage_dirty and chunk.has_method("apply_resource_damage"):
			chunk.apply_resource_damage(client.resource_hits)
			chunk.set_meta("aa_damage_revision", damage_revision)


## Announces the settlement or the region you walk into.
func _track_places(delta: float) -> void:
	_place_timer -= delta
	if _place_timer > 0.0 or client == null or not client.you.has("x"):
		return
	_place_timer = 0.4
	var spot: Vector3 = client.predicted
	if Vector2(spot.x, spot.z).length() < Defs.HUB_SAFE_RADIUS:
		_site_id = -1
		return
	var site: Dictionary = client.world.poi.site_at(spot.x, spot.z)
	var site_id: int = int(site.get("id", -1))
	if site_id != _site_id:
		_site_id = site_id
		if site_id != -1:
			hud.banner(str(site["display"]), WorldMap.KIND_COLORS.get(site["kind"], Color.WHITE))
			var detail := "a workbench and a trader here: crafting, vendor, contracts" if bool(site["station"]) else "loot and danger"
			hud.say("%s - %s" % [str(site["display"]), detail])
			return
	if site_id == -1:
		var area: String = client.world.area_name(spot.x, spot.z)
		if area != _area_name:
			_area_name = area
			hud.banner(area, Color(0.8, 0.9, 1.0))


func _update_time_of_day(delta: float) -> void:
	var weather: Dictionary = client.you.get("weather", {})
	# No rain under the settlement roofs, where the server also treats the player as sheltered.
	var storming: bool = demo_storm or (str(weather.get("condition", "clear")) == "storm" and not bool(weather.get("sheltered", false)))
	var clock: float = client.server_time if demo_phase < 0.0 else demo_phase * WorldCycle.DAY_LENGTH
	var underground: bool = client != null and client.you.has("x") and Dungeon.is_underground(float(client.you["x"]))
	# Only cosmetic ambience is time-sliced; network interpolation and combat
	# still update every frame. Force an immediate refresh across dungeon edges.
	var ambient_quality: int = GraphicsQuality.level()
	_ambient_budget.set_frame_time_budget_us(AMBIENT_CPU_BUDGET_US[ambient_quality])
	# Scene significance controls optional effects; encounter/physics/AI never
	# enter this scheduler. Importance is updated before lane reservations.
	var cosmetic_importance: Dictionary = AmbientTickBudget.suggested_importance(
		WorldCycle.daylight(clock), storming, underground)
	for lane in cosmetic_importance:
		var significance: float = float(cosmetic_importance[lane])
		_ambient_budget.set_lane_importance(lane, significance)
		# Four outdoor-only channels stop reserving CPU slots inside caves.
		# The entrance/exit force flag still performs a one-frame hide/restore.
		if _ambient_lane_enabling_supported:
			_ambient_budget.call("set_lane_enabled", StringName(lane), not underground)
		# Adapt desired frequency only when relevance changes. Cost forecasts,
		# finite frame slots, and starvation aging stay managed in the engine.
		if _ambient_rates_supported:
			var rate_scale: float = AmbientTickBudget.rate_scale_for_importance(significance)
			if float(_ambient_rate_cache.get(lane, -1.0)) != rate_scale:
				if bool(_ambient_budget.call("set_lane_rate_scale", lane, rate_scale)):
					_ambient_rate_cache[lane] = rate_scale
		# Updating only on significance-class transitions avoids per-frame
		# setter calls and keeps low-importance underground work cheap.
		if _ambient_deadline_supported:
			var deadline_frames: int = AmbientTickBudget.deadline_frames_for_importance(significance)
			if int(_ambient_deadline_cache.get(lane, -1)) != deadline_frames:
				if bool(_ambient_budget.call("set_lane_max_deferred_frames", lane, deadline_frames)):
					_ambient_deadline_cache[lane] = deadline_frames
	_ambient_budget.begin_frame(delta, ambient_quality)
	var ambient_force: bool = underground != _ambient_was_underground
	_ambient_was_underground = underground
	# Occlusion has a CPU cost: enable it only when enclosed dungeon walls
	# provide opportunities to hide other rooms behind them.
	DungeonOcclusion.update_viewport(get_viewport(), GraphicsQuality.level(),
		str(RenderingServer.get_current_rendering_method()), underground)
	# A compact scene-aware leak policy for native SDFGI: extra occlusion rays
	# are useful inside enclosed ruins but waste GPU time in open landscapes.
	# Setter is cached and runs only when underground/graphics tier changes.
	GraphicsQuality.update_dynamic_sdfgi(environment, underground)
	# Stable 256m regional wind is only sampled four times per second.
	_wind_sample_left -= maxf(delta, 0.0)
	if underground:
		_visual_weather_wind = Vector2.ZERO
		_visual_biome = "plains"
		_wind_sample_left = 0.0
	elif _wind_sample_left <= 0.0 and client != null and client.world != null and client.you.has("x"):
		var here: Vector3 = client.display_position()
		_visual_weather_wind = Weather.wind_at(client.world, here.x, here.z, clock)
		_visual_biome = client.world.biome_at(here.x, here.z)
		_wind_sample_left = 0.25
	atmosphere.underground_view = underground
	if underground:
		# Below ground: no sky, no weather; the torches of the rooms and the light you carry.
		atmosphere.update(0.0, -0.3, WorldCycle.phase(clock), false, delta, Vector2.ZERO)
		sun.light_energy *= 0.15
		environment.ambient_light_energy = 0.32
		environment.ambient_light_color = Color(0.45, 0.4, 0.34)
		storming = false
	else:
		atmosphere.update(WorldCycle.daylight(clock), WorldCycle.sun_height(clock), WorldCycle.phase(clock), storming, delta, _visual_weather_wind, _visual_biome, MoonVisuals.phase_at(clock))
	# One native lit froxel mist volume follows the player near the ground.
	# No extra fullscreen pass or extra nodes per chunk.
	if _ground_mist != null:
		_ground_mist.update_view(client.display_position(), _visual_biome,
			WorldCycle.daylight(clock), WorldCycle.sun_height(clock),
			atmosphere.storm, _visual_weather_wind, GraphicsQuality.level(),
			delta, underground)
	# Outfit and armor rain coating uses cached PBR variants. Weather smoothing
	# and quality tiers change the step, but ordinary render frames are no-ops.
	var gear_step: int = RainGear.step_for(atmosphere.storm, GraphicsQuality.level(),
		str(RenderingServer.get_current_rendering_method()))
	if avatar_model != null:
		avatar_model.set_wetness_step(gear_step)
	if entities != null:
		entities.set_wetness_step(gear_step)
	# Reuse native clustered decals without changing world physics or saves.
	if _footprints != null and avatar_model != null:
		var foot_at: Vector3 = client.display_position()
		var walking: bool = avatar.visible and avatar_model._moving and (
			avatar_model.speed >= 0.7) and not bool(client.you.get("mounted", false))
		_footprints.update_track(foot_at, walking, delta, atmosphere.storm,
			_visual_biome, GraphicsQuality.level(),
			str(RenderingServer.get_current_rendering_method()), underground,
			client.world.is_water(foot_at.x, foot_at.z))
	# Time-of-day and storm grading shares the existing full-screen post material.
	# Uniform updates are bounded and do not allocate GPU textures or new passes.
	_grade_elapsed += maxf(delta, 0.0)
	if _grade_material != null and _grade_elapsed >= 0.20:
		_grade_elapsed = fmod(_grade_elapsed, 0.20)
		GraphicsColorGrade.apply(_grade_material, WorldCycle.daylight(clock),
			WorldCycle.sun_height(clock), atmosphere.storm, underground)
		# Storm lens droplets share the same post material and 5 Hz update.
		# No extra CanvasLayer or fullscreen back-buffer copy is created.
		GraphicsLensRain.apply(_grade_material, atmosphere.storm,
			GraphicsQuality.level(), str(RenderingServer.get_current_rendering_method()),
			_visual_weather_wind, underground,
			bool(weather.get("sheltered", false)) and not demo_storm)
	_set_carried_light(underground)
	if audio != null:
		audio.update_music(WorldCycle.daylight(clock), delta)
		audio.update_reverb(underground, _visual_biome, delta)
		if client != null and client.you.has("x"):
			audio.update_environment(client.display_position(), client.world.height_at, underground, _visual_biome,
				WorldCycle.daylight(clock), atmosphere.storm, _visual_weather_wind.length(),
				underground or bool(weather.get("sheltered", false)), avatar_model.speed if avatar_model != null else 0.0, delta)
	var snow_fraction := 0.0
	if not underground and client != null and client.world != null and client.you.has("x"):
		var ground_at: Vector3 = client.display_position()
		snow_fraction = SnowVfx.snow_fraction(client.world.height_at(ground_at.x, ground_at.z))
	effects.update_rain(camera.global_position + Vector3(0, -2.0, 0) if camera != null else Vector3.ZERO,
		atmosphere.storm, snow_fraction)
	if _rain_splashes != null and client != null and client.world != null and client.you.has("x"):
		var splash_at: Vector3 = client.display_position()
		splash_at.y = client.world.height_at(splash_at.x, splash_at.z)
		# Snow above the snow line does not splash.
		_rain_splashes.update_view(splash_at, 0.0 if underground else atmosphere.storm * (1.0 - snow_fraction),
			bool(weather.get("sheltered", false)), GraphicsQuality.level())
	if _wet_drips != null:
		_wet_drips.update_view(0.0 if underground else atmosphere.storm,
			underground or bool(weather.get("sheltered", false)), GraphicsQuality.level(), delta)
	if underground and camera_fx != null:
		camera_fx.cold = 0.0
	if _breath != null and not underground and client != null and client.world != null and client.you.has("x"):
		var breath_at: Vector3 = client.display_position()
		var cold_now: float = BreathVapor.coldness(client.world.height_at(breath_at.x, breath_at.z),
			WorldCycle.daylight(clock), _visual_biome, atmosphere.storm * snow_fraction)
		camera_fx.cold = cold_now # Frosted screen edges creep in while you stay in the cold.
		_breath.update_view(cold_now,
			avatar_model.speed if avatar_model != null else 0.0, GraphicsQuality.level(), delta)
	if client != null and client.you.has("x"):
		var here: Vector3 = client.display_position()
		effects.update_ambience(here, atmosphere.light_level, atmosphere.storm, client.world.biome_at(here.x, here.z))
		if _ambient_motes != null:
			_ambient_motes.update_view(here, "" if underground else _visual_biome,
				atmosphere.light_level, atmosphere.storm, _visual_weather_wind,
				GraphicsQuality.level(), delta)
		if _ambient_birds != null:
			_ambient_birds.update_view(here, WorldCycle.daylight(clock), atmosphere.storm,
				GraphicsQuality.level(), delta, underground, _visual_biome)
		if _fish_shoals != null:
			_fish_shoals.update_view(client.world, here, GraphicsQuality.level(),
				WorldCycle.daylight(clock), delta, underground)
		if _damage_direction != null:
			_damage_direction.update_view(here, delta)
		_update_hover_outline(delta)
		if _dust_devils != null:
			var dust_delta: float = _ambient_budget.consume("dust_devils", delta, ambient_force)
			if dust_delta > 0.0:
				var dust_devils_start_us: int = Time.get_ticks_usec()
				_dust_devils.update_view(client.world, here, _visual_biome, _visual_weather_wind, atmosphere.storm,
					WorldCycle.daylight(clock), 0 if underground else GraphicsQuality.level(), dust_delta)
				_ambient_budget.record_cost("dust_devils", maxi(0, Time.get_ticks_usec() - dust_devils_start_us))
		if _shooting_stars != null:
			_shooting_stars.update_view(WorldCycle.daylight(clock), atmosphere.storm,
				0 if underground else GraphicsQuality.level(), delta)
		if _dragonflies != null:
			var dragonfly_delta: float = _ambient_budget.consume("dragonflies", delta, ambient_force)
			if dragonfly_delta > 0.0:
				var dragonflies_start_us: int = Time.get_ticks_usec()
				_dragonflies.update_view(client.world, here, WorldCycle.daylight(clock), atmosphere.storm,
					GraphicsQuality.level(), dragonfly_delta, underground)
				_ambient_budget.record_cost("dragonflies", maxi(0, Time.get_ticks_usec() - dragonflies_start_us))
		if _zombie_flies != null:
			_zombie_flies.update_view(entities, here, WorldCycle.daylight(clock), atmosphere.storm,
				0 if underground else GraphicsQuality.level(), delta)
		if _tumbleweeds != null:
			var tumble_delta: float = _ambient_budget.consume("tumbleweeds", delta, ambient_force)
			if tumble_delta > 0.0:
				var tumbleweeds_start_us: int = Time.get_ticks_usec()
				_tumbleweeds.update_view(client.world, here, _visual_biome, _visual_weather_wind,
					GraphicsQuality.level(), tumble_delta, underground)
				_ambient_budget.record_cost("tumbleweeds", maxi(0, Time.get_ticks_usec() - tumbleweeds_start_us))
		if _dusk_bats != null:
			var bats_delta: float = _ambient_budget.consume("dusk_bats", delta, ambient_force)
			if bats_delta > 0.0:
				var dusk_bats_start_us: int = Time.get_ticks_usec()
				_dusk_bats.update_view(here, WorldCycle.daylight(clock), atmosphere.storm,
					GraphicsQuality.level(), bats_delta, underground)
				_ambient_budget.record_cost("dusk_bats", maxi(0, Time.get_ticks_usec() - dusk_bats_start_us))


func _aim_direction() -> Vector2:
	if _first_person:
		return FirstPersonView.forward(_fp_yaw)
	var viewport := get_viewport()
	if viewport == null or client == null or not client.you.has("x"):
		return Vector2.ZERO
	var mouse := viewport.get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, client.predicted.y + 0.5)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector2.ZERO
	var offset := Vector2(hit.x - client.predicted.x, hit.z - client.predicted.z)
	return offset.normalized() if offset.length() > 0.05 else Vector2.ZERO


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or (_access != null and _access.is_open()) # The settings menu swallows game hotkeys too.


## A single bright, pulsing impact marker. It is positioned using the same
## deterministic server rules and replicated strike count, not client guesses.
## Map a click on the glowing 3D marker to its horizontal world bearing.
## Without this, isometric aiming projects to the ground below the elevated
## marker and exact mouse clicks would frequently miss the precision check.
func _resource_swing_aim(node: Dictionary, fallback: Vector2) -> Vector2:
	if node.is_empty() or camera == null or client == null:
		return fallback
	var hit_count: int = int(client.resource_hits.get(int(node["id"]), 0))
	var spot: Vector3 = ResourceGathering.weakspot_position(node, hit_count)
	if camera.is_position_behind(spot):
		return fallback
	var screen: Vector2 = camera.unproject_position(spot)
	var cursor: Vector2 = get_viewport().get_visible_rect().size * 0.5 if _first_person \
		else get_viewport().get_mouse_position()
	if not screen.is_finite() or cursor.distance_to(screen) > 36.0:
		return fallback
	var offset := Vector2(spot.x - client.predicted.x, spot.z - client.predicted.z)
	return offset.normalized() if offset.length_squared() > 0.01 else fallback


func _update_resource_weakspot(node: Dictionary) -> void:
	var can_show: bool = not node.is_empty() and ResourceGathering.is_strike(
		str(node.get("kind", ""))) and bool(client.you.get("alive", false)) \
		and not bool(client.you.get("mounted", false)) and not hud.is_menu_open()
	if not can_show:
		if _resource_weakspot != null:
			_resource_weakspot.visible = false
		return
	if _resource_weakspot == null:
		_resource_weakspot = MeshInstance3D.new()
		_resource_weakspot.name = "MiningWeakspotMarker"
		var ball := SphereMesh.new()
		ball.radius = 0.12
		ball.height = 0.24
		ball.radial_segments = 10
		ball.rings = 5
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.72, 0.18, 0.92)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.48, 0.08)
		glow.emission_energy_multiplier = 2.0
		ball.material = glow
		_resource_weakspot.mesh = ball
		_resource_weakspot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_resource_weakspot)
	var node_id: int = int(node["id"])
	var completed: int = int(client.resource_hits.get(node_id, 0))
	_resource_weakspot.position = ResourceGathering.weakspot_position(node, completed)
	var pulse: float = 1.0 + 0.17 * sin(float(Time.get_ticks_msec()) * 0.008)
	_resource_weakspot.scale = Vector3.ONE * pulse
	_resource_weakspot.visible = not client.depleted.has(node_id)


func _update_prompt() -> void:
	var text := ""
	var p: Vector3 = client.predicted
	var loot: Dictionary = client.nearest_loot(p, Defs.REACH)
	var node: Dictionary = client.nearest_node(p, Defs.REACH)
	# A pickup closer than the tree must not hide the tree's weak spot.
	# Scan a forward-facing candidate 8x/s instead of scanning every frame.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms >= _resource_marker_rescan_at:
		_resource_marker_rescan_at = now_ms + 125
		_resource_marker_target = client.nearest_strike_node(p, _aim_direction())
	_update_resource_weakspot(_resource_marker_target)
	var below: bool = Dungeon.is_underground(p.x)
	if below and Dungeon.at_stairs(p.x, p.z):
		text = "[E] Climb the stairs back to the surface"
	elif not below and not Dungeon.bunker_at(client.world, p.x, p.z).is_empty():
		var depth_zone: int = client.world.dungeon_zone(Dungeon.region_of_site(Dungeon.bunker_at(client.world, p.x, p.z)))
		text = "[E] Climb down the hatch into the bunker dungeon (%s zone)" % ["green", "yellow", "red", "black"][clampi(depth_zone, 0, 3)]
	elif not loot.is_empty():
		text = "[E] Loot" if loot["kind"] == "bag" else "[E] Search the crate"
	elif not node.is_empty():
		var resource_kind: String = str(node["kind"])
		if ResourceGathering.is_pickup(resource_kind):
			var pickup_label: String = str({
				"pebble": "Pick up loose stones",
				"branch": "Pick up fallen sticks",
				"bush": "Gather fibers",
				"berry": "Pick berries",
			}.get(resource_kind, "Collect resources"))
			text = "[E] %s (hold E for nearby resources)" % pickup_label
		elif ResourceGathering.is_strike(resource_kind):
			var hits_done: int = int(client.resource_hits.get(int(node["id"]), 0))
			var total_hits: int = ResourceGathering.strikes_needed(resource_kind)
			text = "[LMB] %s %s (T%d) | %d/%d hits | Aim at golden spot for +1" % [
				"Chop" if resource_kind == "tree" else "Mine", resource_kind,
				int(node["tier"]), hits_done, total_hits]
		else:
			text = "[E] Gather %s (tier %d)" % [resource_kind, int(node["tier"])]
		var needed := Defs.tool_tier_for_node(node["kind"])
		if needed != "":
			var tool_id: String = client.inventory.best_tool(needed)
			if Defs.tier_of(tool_id) < int(node["tier"]) and not (tool_id == "" and node["tier"] == 1):
				text = "Needs a tier %d %s" % [node["tier"], needed]
	elif client.nearest_barricade(p) != -1:
		var wall: Dictionary = client.barricades[client.nearest_barricade(p)]
		var level: int = Structures.tier_of(wall)
		var hp: int = roundi(float(wall["hp"]))
		var max_hp: int = roundi(Structures.max_health(level))
		text = "Wall T%d (%d/%d HP) | H repair | Y upgrade | X dismantle" % [level, hp, max_hp]
		if level < Structures.MAX_TIER:
			text += " | next: " + str(Structures.upgrade_cost(level + 1))
	elif Vector2(p.x, p.z).distance_to(Vector2(9.0, 0.0)) < 6.0:
		text = "Workbench: press C to craft"
	elif _near_water(p):
		text = "[F] Drink"
	if not client.you.get("action", {}).is_empty():
		var action: Dictionary = client.you["action"]
		var progress: int = int(100.0 * (1.0 - float(action["remaining"]) / maxf(float(action.get("total", action["remaining"])), 0.01)))
		text = ("Fishing... %d%%  (moving reels in)" if action.has("fish") else "Gathering... %d%%") % progress
		if action.has("fish"):
			var left: float = float(action.get("remaining", 0.0))
			var bite_left: float = float(action.get("bite_at", -10.0))
			if bool(action.get("hooked", false)):
				text = "Hooked! Reeling in... %d%%" % progress
			elif left <= bite_left and left > bite_left - Fishing.BITE_WINDOW and not bool(action.get("struck", false)):
				text = "BITE!  Press T to strike"
	if bool(client.you.get("mounted", false)):
		text += " | RIDING (F4 dismount)"
	elif client.inventory.count("salvage_bike") > 0:
		text += " | F4 ride bike"
	if int(client.you.get("sharpened_hits", 0)) > 0:
		text += " | SHARPENED: %d infected melee hits (End)" % int(client.you["sharpened_hits"])
	if int(client.you.get("sighted_hits", 0)) > 0:
		text += " | SIGHTED: %d infected ranged hits (Delete)" % int(client.you["sighted_hits"])
	if int(client.you.get("plated_hits", 0)) > 0:
		text += " | ARMOR PLATE: %d claw hits (Ins)" % int(client.you["plated_hits"])
	if float(client.you.get("soft_sole_seconds", 0.0)) > 0.0:
		text += " | QUIET SPRINT: %.0fs (Shift+/)" % float(client.you["soft_sole_seconds"])
	var nearby_fire_id: int = client.nearest_campfire(client.display_position())
	if nearby_fire_id >= 0 and client.campfires.has(nearby_fire_id):
		var protection: float = float(client.campfires[nearby_fire_id].get("stormproof_seconds", 0.0))
		if protection > 0.0:
			text += " | STORMPROOF FIRE: %.0fs" % protection
	var near_door: int = client.nearest_door(p) if not _build_mode else -1
	if near_door != -1 and client.barricades.has(near_door):
		text = "E: %s the door" % ("close" if bool(client.barricades[near_door].get("open", true)) else "open")
	if _build_mode and _build_piece != "":
		var cost: Dictionary = HousePieces.COST[_build_piece]
		var parts: Array = []
		for item_id in cost:
			parts.append("%d %s" % [int(cost[item_id]), str(item_id).replace("_1", "")])
		text = "BUILD %s  (%s)   1 wall 2 door 3 window 4 floor 5 roof 6 pillar 7 bed 8 lamp 9 chest 0 bench | roofs face where you look | wheel: next piece   click: place   right click: done" % [
			str(HousePieces.NAMES[_build_piece]).to_upper(), ", ".join(parts)]
		if _build_reason != "":
			text += "   -   " + {"out_of_range": "too far", "safe_zone": "not in the settlement",
				"bad_terrain": "ground too steep or wet", "blocked": "something is in the way", "occupied": "already built there",
				"missing_materials": "not enough materials"}.get(_build_reason, _build_reason)
	elif _build_mode:
		text = "BUILD WALL  (4 wood, 2 stone)   wheel: turn   click or U: place   right click: cancel"
		if _build_reason != "":
			text += "   -   " + {"out_of_range": "too near or too far", "safe_zone": "not in the settlement",
				"bad_terrain": "ground too steep or wet", "blocked": "something is in the way",
				"missing_materials": "not enough wood and stone"}.get(_build_reason, _build_reason)
	hud.set_prompt(text)


func _near_water(p: Vector3) -> bool:
	for angle in 8:
		var spot := Vector2(p.x, p.z) + Vector2.from_angle(angle * TAU / 8.0) * 3.0
		if client.world.is_water(spot.x, spot.y):
			return true
	return false


## Timestamp queries cost resources, so use them only during automatic
## Forward+ scaling; manual presets and Compatibility allocate none.
func _update_gpu_measurements() -> void:
	if get_viewport() == null:
		return
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),
		(_auto_graphics or _screenshot_path != "") and
		RenderingServer.get_current_rendering_method() == "forward_plus")


## Common graphics path for the title picker and in-game Settings.
## Preserves native renderer, world streamer and GPU resolution behavior.
func _apply_graphics_selection(index: int) -> void:
	var selected: int = clampi(index, 0, GraphicsQuality.NAMES.size())
	_set_auto_graphics(selected == GraphicsQuality.NAMES.size())
	if _auto_graphics:
		_auto_quality.set_mode("auto")
		GraphicsQuality.set_level(_auto_quality.level, false)
	else:
		GraphicsQuality.set_level(selected)
	_adaptive_resolution.configure(GraphicsQuality.level(),
		GraphicsQuality.metalfx_resolution_floor())
	GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,
		streamer, _adaptive_resolution.scale if _auto_graphics else -1.0, _auto_graphics)
	if is_instance_valid(_quality_picker):
		_quality_picker.select(selected)
	if _access != null and is_instance_valid(_access.menu):
		_access.menu.call("set_graphics_choice", GraphicsQuality.level(), _auto_graphics)


func _set_auto_graphics(enabled: bool) -> void:
	_auto_graphics = enabled
	_update_gpu_measurements()
	# Preserve the other rendering preferences in the same config file.
	var config := ConfigFile.new()
	config.load(GraphicsQuality.SETTINGS_PATH)
	config.set_value("rendering", "auto", enabled)
	var error := config.save(GraphicsQuality.SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save auto graphics mode: %d" % error)


## Objects and walkers near you flatten the grass under them instead of clipping through it.
func _update_grass_crushers(position: Vector3) -> void:
	var sources: Array = []
	for fire in client.campfires.values():
		sources.append(["campfire", fire])
	for shelter in client.shelters.values():
		sources.append(["shelter", shelter])
	for wall in client.barricades.values():
		sources.append(["barricade", wall])
	for bag in client.bags.values():
		sources.append(["bag", bag])
	for snare in client.infected_snares.values():
		sources.append(["snare", snare])
	for decoy in client.decoys.values():
		sources.append(["decoy", decoy])
	for other in client.players.values():
		if int(other.get("id", -1)) != client.peer_id:
			sources.append(["player", other])
	for zombie in client.zombies.values():
		sources.append(["zombie", zombie])
	physics_fx.plants.set_crushers(PlantInteraction.pick_crushers(Vector2(position.x, position.z), sources))


## Murky blue view under the surface and an air gauge while diving (server-owned breath).
func _update_underwater() -> void:
	if hud == null or camera == null:
		return
	if _underwater_tint == null:
		var layer := CanvasLayer.new()
		layer.layer = -1 # Under the HUD, over the world.
		add_child(layer)
		_underwater_tint = ColorRect.new()
		_underwater_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		_underwater_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_underwater_tint.color = Color(0.05, 0.22, 0.32, 0.55)
		layer.add_child(_underwater_tint)
		_breath_label = Label.new()
		_breath_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_breath_label.position.y -= 150.0
		_breath_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_breath_label.add_theme_font_size_override("font_size", 20)
		_breath_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_breath_label.add_theme_constant_override("outline_size", 6)
		hud.add_child(_breath_label)
	var eye: Vector3 = camera.global_position
	var surface: float = client.world.water_level_at(eye.x, eye.z) if client != null and client.world != null else Defs.WATER_LEVEL
	var under: bool = eye.y < surface - 0.05
	_underwater_tint.visible = under
	_underwater_tint.color.a = 0.28 # Thin: the real murk is the fog below.
	_apply_underwater_fog(under, surface - eye.y)
	var breath: float = float(client.you.get("breath", 100.0))
	var diving: bool = bool(client.you.get("diving", false))
	_breath_label.visible = diving or breath < 99.5
	if _breath_label.visible:
		var bars: int = clampi(int(ceil(breath / 10.0)), 0, 10)
		_breath_label.text = "Air  " + "■".repeat(bars) + "□".repeat(10 - bars) + ("   DROWNING!" if breath <= 0.0 else "")
		_breath_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if breath < 25.0 else Color(0.75, 0.92, 1.0))


var _first_steps_timer := 0.0


## Checks the guided first-session goals twice a second and celebrates progress.
func _tick_first_steps(delta: float) -> void:
	_first_steps_timer -= delta
	if _first_steps_timer > 0.0 or hud == null or client == null or not client.welcomed:
		return
	_first_steps_timer = 0.5
	var done: int = FirstSteps.update(client)
	if done > 0:
		if FirstSteps.active():
			hud.say("Goal complete! Next: " + str(FirstSteps.STEPS[FirstSteps.step]["text"]))
		else:
			hud.banner("FIRST STEPS COMPLETE — the island is yours", Color(0.55, 1.0, 0.6))


func _can_fight() -> bool:
	return client != null and client.welcomed and hud != null and not hud.is_menu_open() and not _typing() \
		and not _build_mode and bool(client.you.get("alive", false))


func _cast_arcane_bolt() -> void:
	var direction: Vector2 = _aim_direction()
	if direction == Vector2.ZERO:
		direction = Vector2(sin(client.yaw), cos(client.yaw))
	client.arcane_bolt(direction)


## First-person eye: lens from settings (+ the sprint/bike kick from camera_fx), step bob, strafe lean,
## hop and landing dip, and the held item's pose. Comfort options switch bob and lean off.
func _update_first_person_camera(feet: Vector3, delta: float) -> void:
	var crouching := bool(client.you.get("crouching", false))
	var mounted := bool(client.you.get("mounted", false))
	var speed: float = avatar_model.speed if avatar_model != null else 0.0
	var comfort: bool = bool(UiSettings.get_value("fp_head_bob")) and UiSettings.shake_scale() > 0.0
	camera_fx.base_fov = FirstPersonView.fov(float(UiSettings.get_value("fp_fov")))
	var grounded: bool = _jump_time < 0.0 and not mounted
	_bob_phase = FirstPersonView.advance_bob_phase(_bob_phase, speed if grounded else 0.0, delta)
	var bob: Vector2 = FirstPersonView.head_bob(_bob_phase, speed if grounded else 0.0, comfort)
	# Sideways speed relative to the view, from the input (right = +x).
	var lateral: float = _move_input.x * speed
	_fp_roll = lerpf(_fp_roll, FirstPersonView.strafe_roll(lateral, comfort), 1.0 - exp(-8.0 * delta))
	var knocked: bool = float(client.you.get("knocked_seconds", 0.0)) > 0.0
	_knock = lerpf(_knock, 1.0 if knocked else 0.0, 1.0 - exp(-(14.0 if knocked else 5.0) * delta))
	var eye: Transform3D = FirstPersonView.camera_transform(feet, _fp_yaw, _fp_pitch + 0.35 * _knock,
		lerpf(FirstPersonView.eye_height(crouching, mounted) + FirstPersonView.jump_offset(_jump_time)
		+ FirstPersonView.landing_dip(_land_time) + bob.y, 0.32, _knock))
	eye.origin += eye.basis.x * bob.x
	eye.basis = eye.basis * Basis(Vector3.FORWARD, _fp_roll + 0.55 * _knock)
	camera.global_transform = eye
	# Gear, rain coats and swapped tools add meshes to the body later: keep them all shadow-only.
	_fp_body_refresh -= delta
	if _fp_body_refresh <= 0.0:
		_fp_body_refresh = 0.5
		FirstPersonView.set_body_shadow_only(avatar_model, true)
	if _viewmodel != null:
		var lowered: bool = mounted or float(client.you.get("wading_depth_m", 0.0)) > 1.05 or speed > 5.6 \
			or not bool(client.you.get("alive", true))
		_viewmodel.update_pose(delta, bob, lowered)


## Your own blows light the crosshair: player hits carry the attacker id; zombie hits have none,
## so count one shortly after your own attack in front of you.
func _first_person_hit_marker(event: Dictionary) -> void:
	if not _first_person or client == null:
		return
	match str(event.get("type", "")):
		"attack":
			if int(event.get("peer", -1)) == client.peer_id:
				_own_attack_time = Time.get_ticks_msec() / 1000.0
				if _viewmodel != null:
					_viewmodel.play_attack(bool(event.get("ranged", false)))
		"hit":
			var mine := false
			if str(event.get("kind", "")) == "player":
				mine = int(event.get("by", -2)) == client.peer_id
			elif event.has("x") and Time.get_ticks_msec() / 1000.0 - _own_attack_time < 0.8:
				var here: Vector3 = client.display_position()
				var to := Vector2(float(event["x"]) - here.x, float(event["z"]) - here.z)
				mine = to.length() < 32.0 and (to.length() < 2.5 or to.normalized().dot(FirstPersonView.forward(_fp_yaw)) > 0.8)
			if mine:
				_hit_marker = 1.0


func _set_first_person(enabled: bool) -> void:
	if enabled == _first_person or client == null or not client.welcomed:
		return
	_first_person = enabled
	if _grade_material != null:
		# Tilt-shift blur reads the screen 5–9 times per pixel at output resolution; in first person the
		# "diorama" band only smears the horizon, so skip it there.
		_grade_material.set_shader_parameter("diorama_blur", not enabled)
	_jump_time = -1.0
	if _crosshair == null:
		_crosshair = FirstPersonView.make_crosshair()
		hud.add_child(_crosshair)
	if enabled:
		# Start looking the way the survivor already faces.
		_fp_yaw = avatar.rotation.y if avatar != null else float(client.yaw)
		_fp_pitch = 0.0
		_third_person_near = camera.near
		camera.near = FirstPersonView.NEAR_CLIP # The held item sits a hand's length from the eye.
		if _viewmodel == null:
			_viewmodel = FirstPersonViewmodel.new()
			_viewmodel.name = "FirstPersonViewmodel"
			camera.add_child(_viewmodel)
	else:
		camera.near = _third_person_near
		camera_fx.base_fov = camera_fx.BASE_FOV # Back to the narrow isometric lens.
	if _viewmodel != null:
		_viewmodel.visible = enabled
	# Your body stays in the world as a shadow; other players see it as always.
	FirstPersonView.set_body_shadow_only(avatar_model, enabled)
	_update_first_person_mouse()


## The cursor is captured for mouse look, but freed whenever a menu, chat or settings needs it.
func _update_first_person_mouse() -> void:
	var want_capture: bool = _first_person and not _build_mode and not hud.is_menu_open() and not _typing() \
		and not Input.is_key_pressed(KEY_ALT) and _screenshot_path.is_empty()
	var mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED if want_capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _unhandled_input(event: InputEvent) -> void:
	# Nanite P1 asset-page validation on *actual* streamed foliage/props.
	# Explicit debug keystroke only: no mesh scans/uploads per gameplay frame.
	# Consume before ordinary F8 parry to avoid gameplay effects.
	if OS.is_debug_build() and event is InputEventKey and event.pressed and \
			not event.echo and event.ctrl_pressed and event.shift_pressed and \
			event.keycode == KEY_F8:
		var page_stats: Dictionary = VirtualGeometryPageInspector.inspect_streamed_world(
			get_tree(), 8, 4096)
		var page_report: String = VirtualGeometryPageInspector.format_report(page_stats)
		print(page_report)
		if hud != null:
			hud.say(page_report)
		get_viewport().set_input_as_handled()
		return
	# P1 large-world terrain editor validation: manually sculpt a small visual
	# patch of the actually streamed ChunkedTerrain3D under the player. Debug
	# only; collision is disabled here and server ground/AI are authoritative.
	# Ctrl+Shift+F9 is consumed before the existing F9 smoke-charge action.
	if OS.is_debug_build() and event is InputEventKey and event.pressed and \
			not event.echo and event.ctrl_pressed and event.shift_pressed and \
			event.keycode == KEY_F9:
		var sculpted := false
		if client != null and client.welcomed and client.you.has("x"):
			sculpted = TerrainLivePatch.apply_to_streamed_world(
				get_tree(), client.display_position())
		if hud != null:
			hud.say("Terrain patch: edited the current streamed tile." if sculpted else
				"Terrain patch unavailable (native debug engine or surface required).")
		get_viewport().set_input_as_handled()
		return
	# Unified perf panel (UE stat unit / Insights live view): Ctrl+Shift+F3 toggles,
	# Ctrl+Shift+F4 cycles compact/full/graphs. Consumed before the gameplay F-keys.
	if _perf != null and event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed and event.shift_pressed \
			and (event.keycode == KEY_F3 or event.keycode == KEY_F4):
		if event.keycode == KEY_F3:
			_perf.toggle()
		else:
			_perf.cycle_mode()
		get_viewport().set_input_as_handled()
		return
	# Unreal MemReport-style on-demand inspection of streamed visual objects.
	# Debug builds only; one ObjectDB scan per explicit keystroke and ZERO
	# scanning in normal gameplay. Ctrl+Shift+F10 cannot trigger the ordinary
	# F10 fish-trap action, because it is intercepted here and consumed.
	if OS.is_debug_build() and event is InputEventKey and event.pressed and \
			not event.echo and event.ctrl_pressed and event.shift_pressed and \
			event.keycode == KEY_F10:
		if _object_population_profiler == null:
			_object_population_profiler = ObjectPopulationProfiler.new()
		var object_sample: Dictionary = _object_population_profiler.sample()
		var census_text: String = ObjectPopulationProfiler.format_report(object_sample)
		print(census_text)
		if hud != null:
			hud.say(census_text)
		get_viewport().set_input_as_handled()
		return
	if _first_person and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var look: Vector2 = FirstPersonView.apply_look_scaled(_fp_yaw, _fp_pitch, event.relative,
			FirstPersonView.look_sensitivity(float(UiSettings.get_value("mouse_sensitivity")), bool(UiSettings.get_value("invert_y"))))
		if _viewmodel != null:
			_viewmodel.add_look(event.relative)
		_fp_yaw = look.x
		_fp_pitch = look.y
		get_viewport().set_input_as_handled()
		return
	# Ctrl+F11 cycles graphics quality without consuming the existing F11 medicine shortcut.
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_F3:
		if _profiler == null:
			_profiler = StreamingProfiler.new()
			_profiler.streamer = streamer
			_profiler.client = client
			_profiler.far_field = _far_field
			_profiler.sea = _sea
			hud.add_child(_profiler)
		_profiler.visible = not _profiler.visible
		get_viewport().set_input_as_handled()
		return
	# Ctrl+Shift+F9: PCG debugging — crosses at every procedurally placed point, colored by asset.
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.shift_pressed \
			and event.keycode == KEY_F9 and _pcg_dressing != null:
		_pcg_dressing.set_debug_draw(not PcgWorldDressing.debug_draw)
		if hud != null:
			hud.say("PCG debug points: %s" % ("on" if PcgWorldDressing.debug_draw else "off"))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_F11:
		_apply_graphics_selection((GraphicsQuality.level() + 1) % GraphicsQuality.NAMES.size())
		var message := "Graphics: %s (Ctrl+F11 to change)" % GraphicsQuality.get_name()
		if hud != null:
			hud.say(message)
		else:
			print(message)
		get_viewport().set_input_as_handled()
		return
	if client == null or not client.welcomed or hud == null:
		return
	if audio != null and event is InputEventKey and event.pressed and event.ctrl_pressed and not _typing():
		var volume_message: String = audio.handle_key(event)
		if volume_message != "":
			hud.say(volume_message)
			get_viewport().set_input_as_handled()
			return
	# Albion-style ability bar: Alt+G weapon ultimate, Alt+H chest, Alt+J helmet, Alt+K boots.
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and not _typing() \
			and event.keycode in [KEY_G, KEY_H, KEY_J, KEY_K]:
		if not hud.is_menu_open() and bool(client.you.get("alive", false)):
			if event.keycode == KEY_G:
				var ult_direction: Vector2 = _aim_direction()
				if ult_direction == Vector2.ZERO:
					ult_direction = Vector2(sin(client.yaw), cos(client.yaw))
				client.skill_ultimate(ult_direction)
			else:
				client.gear_skill({KEY_H: "armor", KEY_J: "head", KEY_K: "feet"}[event.keycode])
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and not _typing():
		match event.keycode:
			KEY_K:
				skills_panel.toggle()
			KEY_F2:
				if Input.is_key_pressed(KEY_CTRL):
					if FirstSteps.active():
						FirstSteps.skip()
						hud.say("First Steps guide hidden. F2 still lists every control.")
				else:
					help_panel.toggle()
			KEY_J:
				world_map.toggle()
			KEY_F4:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.toggle_mount()
			KEY_BRACKETLEFT:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("bike_dynamo_lamp")
			KEY_PAGEUP:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("bike_service_kit")
			KEY_END:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					_quick_use("field_whetstone")
			KEY_DELETE:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					_quick_use("field_sighting_kit")
			KEY_INSERT:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					_quick_use("field_armor_plate")
			KEY_PAGEDOWN:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("bike_frame_patch")
			KEY_F5:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var direction: Vector2 = _aim_direction()
					if direction.length_squared() < 0.0001:
						direction = Vector2(sin(client.yaw), cos(client.yaw))
					client.throw_ember(direction)
			KEY_F3:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.survey_ruins()
			KEY_F10:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.place_fish_trap()
			KEY_F6:
				# Pitch a field tarp a few steps ahead (it used to be a button only).
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var standing: Vector3 = client.display_position()
					client.pitch_shelter(Vector2(standing.x, standing.z) + Vector2(sin(client.yaw), cos(client.yaw)) * 2.8)
			KEY_F7:
				var shelter_id: int = client.nearest_shelter(client.display_position())
				if shelter_id < 0:
					hud.say("No field tarp within reach.")
				else:
					client.pack_shelter(shelter_id)
			KEY_HOME:
				if not hud.is_menu_open():
					client.use_item("return_charm")
			KEY_F12:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var fish_trap_id: int = client.nearest_fish_trap(client.display_position())
					if fish_trap_id < 0:
						hud.say("No shoreline fish trap within reach.")
					else:
						client.collect_fish_trap(fish_trap_id)
			KEY_Q:
				if Input.is_key_pressed(KEY_SHIFT) and not hud.is_menu_open():
					client.loot_sweep()
				elif _first_person and _melee_equipped() and _can_fight() and not hud.is_menu_open():
					client.kick(_look_direction()) # First person: Q kicks; E still interacts.
				else:
					_interact()
			KEY_1:
				if Input.is_key_pressed(KEY_ALT) and Input.is_key_pressed(KEY_SHIFT):
					hud.eat_smoked()
				elif Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.smart_provision("food")
				elif Input.is_key_pressed(KEY_ALT):
					var raw_item := ""
					for tier in range(1, 5):
						var candidate: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
						if client.inventory.count(candidate) > 0:
							raw_item = candidate
							break
					if raw_item != "":
						_quick_use(raw_item)
					else:
						hud.say("No raw fish carried. Properly cooked food is safer.")
				else:
					_quick_use(Defs.CAMP_FISH_STEW if Input.is_key_pressed(KEY_SHIFT) else "canned_food")
			KEY_2:
				if Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.smart_provision("drink")
				else:
					_quick_use("empty_water_pouch" if Input.is_key_pressed(KEY_SHIFT) else "water_bottle")
			KEY_3:
				if Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.quick_medicine()
				else:
					_quick_use("expedition_trauma_kit" if Input.is_key_pressed(KEY_SHIFT) else "bandage")
			KEY_4:
				_cycle_weapon()
			KEY_5:
				_quick_use("jacket_1")
			KEY_6:
				_quick_use("antiseptic_edge_oil" if Input.is_key_pressed(KEY_SHIFT)
					else "field_antiseptic")
			KEY_7:
				_quick_use("antibiotics")
			KEY_F11:
				_quick_use("herbal_gut_tonic" if Input.is_key_pressed(KEY_SHIFT) else "herbal_poultice")
			KEY_8:
				_quick_use("thermal_wrap")
			KEY_PERIOD:
				_quick_use("frontier_stim")
			KEY_SLASH:
				_quick_use("soft_sole_wraps" if Input.is_key_pressed(KEY_SHIFT) else "herbal_scent_mask")
			KEY_SEMICOLON:
				_quick_use("spore_filter")
			KEY_R:
				if Input.is_key_pressed(KEY_CTRL):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						client.refill_canteen(Input.is_key_pressed(KEY_SHIFT))
				elif Input.is_key_pressed(KEY_SHIFT):
					if not hud.is_menu_open() and bool(client.you.get("alive", false)):
						_quick_use("field_alkali_kit")
				elif _first_person and float(client.you.get("rage", 0.0)) >= 100.0 and _can_fight():
					client.rage()
				else:
					client.drink()
			KEY_T:
				if Input.is_key_pressed(KEY_ALT):
					client.fish(false, true) # Storm cast.
				else:
					client.fish(Input.is_key_pressed(KEY_SHIFT))
			KEY_Z:
				client.rest()
			KEY_B:
				hud.toggle_inventory()
			KEY_N:
				client.vendor("water_bottle", 1, true)
			KEY_V:
				var sell_id: String = Vendor.first_fish(client.inventory) if Input.is_key_pressed(KEY_SHIFT) else Vendor.first_sellable(client.inventory)
				if sell_id.is_empty():
					hud.say("Nothing to sell.")
				else:
					client.vendor(sell_id, 1, false)
			KEY_P:
				client.contract("daily_claim" if Input.is_key_pressed(KEY_CTRL) else ("claim" if Input.is_key_pressed(KEY_SHIFT) else "accept"))
			KEY_ENTER, KEY_KP_ENTER:
				if chat_edit != null:
					chat_edit.visible = true
					chat_edit.grab_focus()
			KEY_E:
				if Input.is_key_pressed(KEY_SHIFT) and not hud.is_menu_open():
					client.loot_sweep()
				else:
					_interact()
			KEY_F:
				if Input.is_key_pressed(KEY_CTRL):
					if _can_fight():
						_cast_arcane_bolt()
				else:
					client.drink()
			KEY_F1:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.guardian_taunt()
			KEY_F8:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.parry()
			KEY_F9:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					client.use_item("smoke_charge")
			KEY_G:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_CTRL):
						client.ultimate()
					elif Input.is_key_pressed(KEY_SHIFT):
						client.stagger_finisher()
					else:
						var skill_direction: Vector2 = _aim_direction()
						if skill_direction == Vector2.ZERO:
							skill_direction = Vector2(sin(client.yaw), cos(client.yaw))
						client.skill(skill_direction)
			KEY_SPACE:
				if _first_person and not Input.is_key_pressed(KEY_SHIFT):
					# First person: Space jumps (cosmetic hop); Shift+Space keeps the dodge.
					if _jump_time < 0.0 and _can_fight() and not bool(client.you.get("mounted", false)):
						_jump_time = 0.0
				elif not hud.is_menu_open() and bool(client.you.get("alive", false)):
					# Move-direction dodge, or current aim/facing when stationary.
					var dodge_direction := Vector2(
						Input.get_axis("ui_left", "ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
						Input.get_axis("ui_up", "ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
					if dodge_direction.length_squared() < 0.0001:
						dodge_direction = _aim_direction()
					if dodge_direction.length_squared() < 0.0001:
						dodge_direction = Vector2(sin(client.yaw), cos(client.yaw))
					client.dodge(dodge_direction.normalized())
			KEY_MINUS:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var fire_id: int = client.nearest_campfire(client.display_position())
					if fire_id != -1:
						client.extinguish_campfire(fire_id)
			KEY_0:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_ALT):
						hud.quick_smoke()
					else:
						hud.quick_cook(Input.is_key_pressed(KEY_SHIFT))
			KEY_9:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_SHIFT):
						_quick_use("stormproof_briquette")
					else:
						var fire_id: int = client.nearest_campfire(client.display_position())
						if fire_id == -1:
							hud.say("No burning campfire within 3 metres.")
						else:
							client.refuel_campfire(fire_id)
			KEY_I, KEY_TAB:
				hud.toggle_inventory()
			KEY_C:
				hud.toggle_crafting()
			KEY_BACKSLASH:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var dir: Vector2 = _aim_direction()
					if dir.length_squared() < 0.0001:
						dir = Vector2(sin(client.yaw), cos(client.yaw))
					var site := Vector2(client.predicted.x, client.predicted.z) + dir * 2.8
					client.place_infected_snare(site)
			KEY_COMMA:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					var decoy_direction: Vector2 = _aim_direction()
					if decoy_direction.length_squared() < 0.0001:
						decoy_direction = Vector2(sin(client.yaw), cos(client.yaw))
					client.throw_decoy(decoy_direction)
			KEY_O:
				if not hud.is_menu_open() and bool(client.you.get("alive", false)):
					if Input.is_key_pressed(KEY_SHIFT):
						var fire_id: int = client.nearest_campfire(client.display_position())
						if fire_id < 0:
							hud.say("Camp alarm: stand within 3m of an active campfire.")
						else:
							client.arm_camp_alarm(fire_id)
					else:
						var direction: Vector2 = _aim_direction()
						if direction == Vector2.ZERO:
							direction = Vector2(sin(client.yaw), cos(client.yaw))
						var target := Vector2(client.predicted.x, client.predicted.z) + direction * 2.8
						client.light_campfire(target)
						hud.say("At night, campfire light attracts infected. Press - to extinguish.")
			KEY_U:
				if _build_mode:
					_place_wall()
				else:
					_build_mode = true
			KEY_ESCAPE:
				if _build_mode:
					_end_build_mode()
			KEY_H:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.repair(id)
			KEY_Y:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.upgrade(id)
			KEY_X:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.dismantle(id)
	if _build_mode and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_0 and event.keycode <= KEY_9:
		# Build mode: 1 wall, 2 door, 3 window, 4 floor, 5 roof, 6 pillar, 7 bed, 8 lamp, 9 chest, 0 workbench;
		# the wheel also reaches the old free-standing barricade.
		_select_build_piece(9 if event.keycode == KEY_0 else int(event.keycode - KEY_1))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and _build_mode:
		# Build mode: the wheel turns the wall, a left click places it, a right click puts the plan away.
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if _build_piece == "":
					_build_yaw = fposmod(_build_yaw + Structures.ROTATION_STEP, TAU)
				else:
					_select_build_piece(BUILD_PIECES.find(_build_piece) + 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if _build_piece == "":
					_build_yaw = fposmod(_build_yaw - Structures.ROTATION_STEP, TAU)
				else:
					_select_build_piece(BUILD_PIECES.find(_build_piece) - 1)
			MOUSE_BUTTON_LEFT:
				_place_wall()
			MOUSE_BUTTON_RIGHT:
				_end_build_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and _can_fight():
		if (event.button_index == MOUSE_BUTTON_RIGHT and _first_person) or event.button_index == MOUSE_BUTTON_XBUTTON1:
			_cast_arcane_bolt()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_XBUTTON2:
			client.ultimate()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
			and _first_person and _melee_equipped() and _can_fight() and not hud.is_menu_open():
		client.parry() # First person melee: right mouse blocks, perfectly timed it parries.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_set_first_person(not _first_person)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _zoom <= 0.55 + 0.001:
				_set_first_person(true)
			_zoom = clampf(_zoom - 0.1, 0.55, 1.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _first_person:
				_set_first_person(false)
			else:
				_zoom = clampf(_zoom + 0.1, 0.55, 1.8)


## Uses or equips an item you carry; the server decides whether it works.
func _quick_use(item_id: String) -> void:
	if client.inventory.count(item_id) < 1:
		hud.say("You do not carry %s." % str(Defs.item(item_id).get("name", item_id)))
		return
	client.use_item(item_id)


## Equips the next weapon in the backpack (crafted spears and bows included).
func _cycle_weapon() -> void:
	var owned: Array[String] = []
	for item_id in Defs.items():
		if str(Defs.item(str(item_id)).get("kind", "")) == "weapon" and client.inventory.count(str(item_id)) > 0:
			owned.append(str(item_id))
	owned.sort()
	if owned.is_empty():
		hud.say("No weapon in the backpack.")
		return
	var current: int = owned.find(client.inventory.weapon)
	client.use_item(owned[(current + 1) % owned.size()])


## Holding E after a loose-resource pickup collects nearby sticks, pebbles,
## fiber and berries one by one. A single initial press still has all its old
## door/loot/dungeon semantics; only a verified pickup starts this mode.
func _update_held_pickups() -> void:
	if _hold_pickup_since_ms < 0:
		return
	if not Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SHIFT) \
			or _typing() or _build_mode or hud.is_menu_open() or _access.is_open() \
			or not bool(client.you.get("alive", false)) \
			or bool(client.you.get("mounted", false)):
		_hold_pickup_since_ms = -1
		_hold_pickup_pending.clear()
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms < _hold_pickup_since_ms + HOLD_PICKUP_DELAY_MS \
			or now_ms < _hold_pickup_next_ms:
		return
	_hold_pickup_next_ms = now_ms + HOLD_PICKUP_INTERVAL_MS
	for id in _hold_pickup_pending.keys():
		if client.depleted.has(id) or now_ms >= int(_hold_pickup_pending[id]):
			_hold_pickup_pending.erase(id)
	var nearby: Dictionary = client.nearest_pickup_node(
		client.predicted, Defs.REACH + 0.5, _hold_pickup_pending)
	if not nearby.is_empty():
		var node_id: int = int(nearby["id"])
		_hold_pickup_pending[node_id] = now_ms + HOLD_PICKUP_RETRY_MS
		client.resource_pickup(node_id)


func _interact() -> void:
	var p: Vector3 = client.predicted
	# The hatch of a bunker leads down into its dungeon; the stairs of the first room lead back up.
	if Dungeon.is_underground(p.x) and Dungeon.at_stairs(p.x, p.z):
		client.dungeon(false)
		return
	if not Dungeon.is_underground(p.x) and not Dungeon.bunker_at(client.world, p.x, p.z).is_empty():
		client.dungeon(true)
		return
	var door_id: int = client.nearest_door(p)
	if door_id != -1:
		client.toggle_door(door_id)
		return
	var loot: Dictionary = client.nearest_loot(p, Defs.REACH)
	if not loot.is_empty():
		client.loot(loot["id"])
		return
	var node: Dictionary = client.nearest_node(p, Defs.REACH)
	if not node.is_empty():
		if ResourceGathering.is_pickup(str(node["kind"])):
			var pickup_id: int = int(node["id"])
			client.resource_pickup(pickup_id)
			_hold_pickup_since_ms = Time.get_ticks_msec()
			_hold_pickup_next_ms = _hold_pickup_since_ms + HOLD_PICKUP_DELAY_MS
			_hold_pickup_pending.clear()
			_hold_pickup_pending[pickup_id] = _hold_pickup_since_ms + HOLD_PICKUP_RETRY_MS
		elif ResourceGathering.is_strike(str(node["kind"])):
			var facing: Vector2 = _aim_direction()
			if facing == Vector2.ZERO:
				facing = _look_direction()
			client.resource_hit(int(node["id"]), _resource_swing_aim(node, facing))
		else:
			client.gather(int(node["id"]))


# --- Scripted demo for screenshots and videos --------------------------------------------------------------

func _run_demo() -> void:
	if _demo == "" or client == null or not client.you.has("x"):
		return # Wait for the server's welcome and first snapshot.
	_demo_frames += 1
	var net_ref = net
	match _demo:
		"first_person":
			# Held weapon, crosshair and a swing caught mid-motion (use with --first-person --screenshot).
			if _demo_frames == 30:
				net_ref.c_debug.rpc_id(1, "give", {"item": "machete_2", "count": 1})
			if _demo_frames == 60:
				_cycle_weapon() # Same as pressing 4: equips the next owned weapon.
			if _demo_frames == 300 or _demo_frames == 694:
				client.attack(FirstPersonView.forward(_fp_yaw))
			if _demo_frames == 40:
				var site := _find_ruin()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": site.x - 16.0, "z": site.y + 10.0})
				net_ref.c_debug.rpc_id(1, "give", {"item": "club_2", "count": 1})
				net_ref.c_debug.rpc_id(1, "give", {"item": "jacket_2", "count": 1})
				net_ref.c_debug.rpc_id(1, "zombie", {"type": "walker", "x": site.x - 8.0, "z": site.y + 12.0})
				net_ref.c_debug.rpc_id(1, "zombie", {"type": "runner", "x": site.x - 4.0, "z": site.y + 6.0})
				net_ref.c_debug.rpc_id(1, "zombie", {"type": "brute", "x": site.x, "z": site.y + 14.0})
				_screenshot_frames = 600 # Shoot while the fight is on, before the brute wins it.
			if _demo_frames == 90:
				client.use_item("club_2")
				client.use_item("jacket_2")
		"vista":
			if _demo_frames == 40:
				# A wide view over open country (screenshots of the landscape: grass, cloud shadows, light).
				var spot := _find_forest()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x + 40.0, "z": spot.y + 30.0})
				_zoom = 2.2
		"forest":
			if _demo_frames == 40:
				var spot := _find_forest()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x, "z": spot.y})
				net_ref.c_debug.rpc_id(1, "give", {"item": "axe_1", "count": 1})
		"skills":
			if _demo_frames == 30:
				for entry in [["woodcutting", 4200], ["mining", 1600], ["melee", 9000], ["slayer", 2600], ["athletics", 5200], ["toughness", 3000], ["crafting", 900], ["explorer", 2200], ["survivalist", 700]]:
					net_ref.c_debug.rpc_id(1, "xp", {"skill": entry[0], "amount": entry[1]})
			if _demo_frames == 80:
				client.buy_perk("sharp_axe")
				client.buy_perk("heavy_hands")
				client.buy_perk("swift_feet")
			if _demo_frames == 120 and skills_panel != null:
				skills_panel.toggle()
				skills_panel._tabs.current_tab = 1
		"village", "city", "farm", "camp", "outpost_site", "lighthouse", "dock", "bunker":
			if _demo_frames == 40:
				var wanted: String = "outpost" if _demo == "outpost_site" else _demo
				var site := _nearest_site(wanted)
				if not site.is_empty():
					net_ref.c_debug.rpc_id(1, "teleport", {"x": float(site["x"]) - 3.0, "z": float(site["z"]) + 7.0})
					_zoom = 1.8
					_screenshot_frames = 480
		"stones", "crystals", "greattree", "shrine", "battlefield":
			if _demo_frames == 40:
				var title: String = {"stones": "Stone Circle", "crystals": "Crystal Grove", "greattree": "Great Tree", "shrine": "Old Shrine", "battlefield": "Battlefield"}[_demo]
				var landmark := _nearest_site("landmark", title)
				if not landmark.is_empty():
					net_ref.c_debug.rpc_id(1, "teleport", {"x": float(landmark["x"]) - 4.0, "z": float(landmark["z"]) + 14.0})
					_zoom = 1.8
					_screenshot_frames = 480
		"road":
			if _demo_frames == 40:
				var spot := _nearest_signpost()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x + 3.0, "z": spot.y + 5.0})
				_zoom = 1.5
				_screenshot_frames = 480
		"inventory":
			if _demo_frames == 30:
				for entry in [["club_2", 1], ["pistol", 1], ["ammo_9mm", 24], ["jacket_2", 1], ["axe_2", 1], ["canned_food", 4], ["water_bottle", 3], ["bandage", 5], ["wood_3", 12], ["ore_4", 6], ["silver", 240], ["hood_2", 1], ["cloak_3", 1], ["gloves_2", 1], ["boots_2", 1]]:
					net_ref.c_debug.rpc_id(1, "give", {"item": entry[0], "count": entry[1]})
			if _demo_frames == 70:
				for worn in ["club_2", "jacket_2", "hood_2", "cloak_3", "gloves_2", "boots_2"]:
					client.use_item(worn)
			if _demo_frames == 110:
				hud.toggle_inventory()
				# CGAME_DEMO_TAB=n opens another tab of the window for its screenshot.
				if OS.get_environment("CGAME_DEMO_TAB").is_valid_int() and hud._inventory_tabs != null:
					hud._inventory_tabs.current_tab = int(OS.get_environment("CGAME_DEMO_TAB"))
				if OS.get_environment("CGAME_DEMO_CRAFT") == "1":
					hud.toggle_crafting()
				if OS.get_environment("CGAME_DEMO_SOCIAL") == "1": # The community window instead of the bag.
					hud.toggle_inventory()
					hud.toggle_social()
				if OS.get_environment("CGAME_DEMO_FILTER") == "1": # Only gear in the bag and the workshop.
					for key in hud._bag_filter:
						hud._bag_filter[key] = key == "gear"
						hud._craft_filter[key] = key == "gear"
				if OS.get_environment("CGAME_DEMO_QUICK") == "1": # Fill the quick-use sockets as a double click would.
					hud._put_in_doll("canned_food")
					hud._put_in_doll("bandage")
		"dungeon":
			if _demo_frames == 30:
				var best: Dictionary = {}
				for rx in range(-4, 5):
					for rz in range(-4, 5):
						for site in client.world.poi.sites_in_region(rx, rz):
							if str(site.get("kind", "")) == "bunker" and (best.is_empty() or Vector2(site["x"], site["z"]).length() < Vector2(best["x"], best["z"]).length()):
								best = site
				if not best.is_empty():
					var hatch: Vector2 = Dungeon.hatch(client.world, best)
					net_ref.c_debug.rpc_id(1, "teleport", {"x": hatch.x, "z": hatch.y})
			if _demo_frames == 80:
				client.dungeon(true)
			if _demo_frames == 120:
				# Step into the room beyond the first doorway for the picture.
				var here := Vector2(client.predicted.x, client.predicted.z)
				var region: Vector2i = Dungeon.region_of(here.x, here.y)
				var layout: Dictionary = Dungeon.layout(client.world.world_seed, region)
				var target: Vector2 = Dungeon.origin(region)
				for room in layout["rooms"]:
					if room != Vector2i.ZERO and Dungeon.linked(layout, Vector2i.ZERO, room):
						target = Dungeon.room_center(region, room).lerp(Dungeon.origin(region), 0.55)
						break
				net_ref.c_debug.rpc_id(1, "teleport", {"x": target.x, "z": target.y})
		"build":
			if _demo_frames == 30:
				for entry in [["wood_1", 20], ["stone_1", 10], ["plank_2", 8], ["stone_2", 4]]:
					net_ref.c_debug.rpc_id(1, "give", {"item": entry[0], "count": entry[1]})
				net_ref.c_debug.rpc_id(1, "teleport", {"x": 72.0, "z": 20.0})
			if _demo_frames == 70:
				var here := Vector2(client.predicted.x, client.predicted.z)
				client.build(here + Vector2(2.5, 1.2), 0.0)
				client.build(here + Vector2(-0.4, 2.8), PI / 4.0)
			if _demo_frames == 95:
				var id: int = client.nearest_barricade(client.predicted)
				if id != -1:
					client.upgrade(id)
				_build_mode = true
				_build_yaw = PI / 2.0
		"fish":
			if _demo_frames == 30:
				net_ref.c_debug.rpc_id(1, "give", {"item": "fishing_rod", "count": 1})
				var shore := _open_shore()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": shore.x, "z": shore.y})
			if _demo_frames == 70:
				# Step to the water's edge: dry ground with water about three metres out.
				var here := Vector2(client.predicted.x, client.predicted.z)
				for radius in range(0, 60, 2):
					var found := false
					for step in 24:
						var spot := here + Vector2.from_angle(float(step) * TAU / 24.0) * float(radius)
						if client.world.is_water(spot.x, spot.y):
							continue
						for look in 16:
							var probe := spot + Vector2.from_angle(float(look) * TAU / 16.0) * 3.0
							if client.world.is_water(probe.x, probe.y):
								net_ref.c_debug.rpc_id(1, "teleport", {"x": spot.x, "z": spot.y})
								found = true
								break
						if found:
							break
					if found:
						break
			if _demo_frames == 110:
				client.fish()
				_screenshot_frames = 640 # Shoot while the cast is out.
		"sky":
			if _demo_frames == 40:
				var vista := _open_shore()
				net_ref.c_debug.rpc_id(1, "teleport", {"x": vista.x, "z": vista.y})
		"map":
			if _demo_frames == 60:
				world_map.toggle()
				_screenshot_frames = 640
		"outpost":
			if _demo_frames == 40 and not client.outposts.is_empty():
				var post: Dictionary = client.outposts[0]
				net_ref.c_debug.rpc_id(1, "teleport", {"x": float(post["x"]) - 9.0, "z": float(post["z"]) + 4.0})
				_zoom = 1.7
				_screenshot_frames = 560 # Shoot before the zombies out there finish the visitor.
		"help":
			if _demo_frames == 60:
				help_panel.toggle()
		"hub":
			if _demo_frames == 40:
				net_ref.c_debug.rpc_id(1, "teleport", {"x": 14.0, "z": 6.0})
		"house":
			# Build check: a 2x2-cell cabin around the survivor (needs --debug-commands).
			if _demo_frames == 30:
				net_ref.c_debug.rpc_id(1, "teleport", {"x": 120.0, "z": 96.0})
			if _demo_frames == 60:
				net_ref.c_debug.rpc_id(1, "give", {"item": "wood_1", "count": 120})
				net_ref.c_debug.rpc_id(1, "give", {"item": "stone_1", "count": 30})
				net_ref.c_debug.rpc_id(1, "give", {"item": "cloth_1", "count": 10})
			if _demo_frames == 80:
				# The survivor stands on the shared corner of the four cells.
				var corner := Vector2(roundf(client.predicted.x / HousePieces.GRID), roundf(client.predicted.z / HousePieces.GRID)) * HousePieces.GRID
				var g := HousePieces.GRID
				_demo_house_plan.clear()
				for cell in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
					_demo_house_plan.append(["floor", corner + cell * g])
				for k in [-0.5, 0.5]:
					_demo_house_plan.append(["window" if k > 0 else "wall", corner + Vector2(-g * 0.95, k * g)])
					_demo_house_plan.append(["wall", corner + Vector2(g * 0.95, k * g)])
					_demo_house_plan.append(["door" if k < 0 else "wall", corner + Vector2(k * g, -g * 0.95)])
					_demo_house_plan.append(["wall", corner + Vector2(k * g, g * 0.95)])
				for cell in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
					_demo_house_plan.append(["roof", corner + cell * g, -PI * 0.5 if cell.x < 0.0 else PI * 0.5])
				for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					_demo_house_plan.append(["pillar", corner + c * g])
				_demo_house_plan.append(["chest", corner + Vector2(0.5, -0.5) * g])
				_demo_house_plan.append(["workbench", corner + Vector2(-0.5, -0.5) * g])
				_demo_house_plan.append(["bed", corner + Vector2(0.5, 0.5) * g])
				_demo_house_plan.append(["lamp", corner + Vector2(-0.5, 0.5) * g])
			if _demo_frames > 80 and _demo_frames % 8 == 0 and not _demo_house_plan.is_empty():
				var step: Array = _demo_house_plan.pop_front()
				client.build_piece(str(step[0]), step[1], float(step[2]) if step.size() > 2 else 0.0)
				if _demo_house_plan.is_empty():
					_demo_house_done_at = _demo_frames
			if _demo_house_done_at > 0 and _demo_frames == _demo_house_done_at + 30:
				# Stand north of the cabin so the camera (looking north) frames it below the survivor.
				net_ref.c_debug.rpc_id(1, "teleport", {"x": client.predicted.x, "z": client.predicted.z - 7.0})
		"campfire":
			# Grass crush check: a campfire lit just ahead, seen from first person (needs --debug-commands).
			if _demo_frames == 40:
				for cost_item in FieldCampfire.COST:
					net_ref.c_debug.rpc_id(1, "give", {"item": cost_item, "count": int(FieldCampfire.COST[cost_item])})
			if _demo_frames == 80:
				var ahead := Vector2(client.predicted.x, client.predicted.z) + Vector2(sin(client.yaw), cos(client.yaw)) * 2.2
				client.light_campfire(ahead)
				_fp_yaw = client.yaw
				_fp_pitch = -0.55
	if _screenshot_path != "":
		_screenshot_frames += 1
		if _screenshot_frames > _bench_window.x:
			_frame_ms.append(get_process_delta_time() * 1000.0)
			if RenderingServer.get_current_rendering_method() == "forward_plus":
				var gpu_sample: float = RenderingServer.viewport_get_measured_render_time_gpu(
					get_viewport().get_viewport_rid())
				if is_finite(gpu_sample) and gpu_sample > 0.0:
					_gpu_frame_ms.append(gpu_sample)
		if _screenshot_frames == _bench_window.y:
			# The window may be hidden behind others, in which case the last drawn frame would be stale: draw now.
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			# GPU timestamps can lag by a frame: compare the independent
			# distributions, never treat sample indices as synchronized.
			var pace: Dictionary = RenderBenchmark.summarize(_frame_ms)
			var gpu_pace: Dictionary = RenderBenchmark.summarize(_gpu_frame_ms)
			print(RenderBenchmark.describe(pace))
			print(RenderBenchmark.describe_gpu(gpu_pace))
			print("CGAME_FRAME_BENCHMARK " + JSON.stringify({
				"render_method": RenderingServer.get_current_rendering_method(),
				"cpu": pace, "gpu": gpu_pace
			}))
			print("CLIENT frame: %d fps, %d draw calls, %d primitives, %d objects" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			if _pcg_dressing != null and _pcg_dressing.has_method("get_stats"):
				print("CLIENT pcg: " + JSON.stringify(_pcg_dressing.get_stats()))
			print("CLIENT passes: " + JSON.stringify(RenderProfile.pass_counts(get_viewport())))
			print("CLIENT settings: " + JSON.stringify(RenderProfile.settings(get_viewport(), environment, GraphicsQuality.level())))
			if camera != null:
				for row in RenderProfile.geometry_by_group(self, camera):
					print("CLIENT geometry %9d tris  %6d inst  %s" % [row[1], row[2], row[0]])
				print("CLIENT instance culling: " + JSON.stringify(RenderProfile.instance_culling_estimate(self, camera)))
			# Distinguish missing streamed terrain from slow rendering in
			# automatic screenshot benchmarks, with no per-frame HUD work.
			if streamer != null:
				print("CLIENT streaming: loaded=%d queued=%d threaded=%d visual=%d" % [
					streamer.get_loaded_count(), streamer.get_queued_generation_count(),
					streamer.get_pending_count(), streamer.get_pending_visual_details_count()])
			print("CLIENT " + _hitch_analyzer.describe())
			print("CLIENT screenshot saved: ", _screenshot_path)
			get_tree().quit()


## The site of a kind closest to the hub (demos and screenshots).
## A beach facing open sea toward -z, for a clear view of the sky (demo).
func _open_shore() -> Vector2:
	var world = client.world
	for radius in range(200, 2400, 40):
		for step in 24:
			var spot := Vector2.from_angle(float(step) * TAU / 24.0) * float(radius)
			if world.is_water(spot.x, spot.y) or world.biome_at(spot.x, spot.y) != "beach":
				continue
			var open := true
			for ahead in range(10, 140, 10):
				if not world.is_water(spot.x, spot.y - float(ahead)):
					open = false
					break
			if open:
				return spot
	return Vector2(0.0, 40.0)


func _nearest_signpost() -> Vector2:
	var best := Vector2(60.0, 60.0)
	var best_distance := INF
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			for sign in client.world.roads.signs_in_cell(Vector2i(cx, cz)):
				var spot := Vector2(float(sign["x"]), float(sign["z"]))
				if spot.length() > 70.0 and spot.length() < best_distance:
					best = spot
					best_distance = spot.length()
	return best


func _nearest_site(kind: String, title: String = "") -> Dictionary:
	var best := {}
	var best_distance := INF
	for rx in range(-14, 14):
		for rz in range(-14, 14):
			for site in client.world.poi.sites_in_region(rx, rz):
				var distance: float = Vector2(float(site["x"]), float(site["z"])).length()
				if site["kind"] == kind and (title == "" or str(site.get("title", "")) == title) and distance < best_distance:
					best = site
					best_distance = distance
	return best


func _find_ruin() -> Vector2:
	for radius in range(5, 14):
		for cx in range(-radius, radius + 1):
			for cz in range(-radius, radius + 1):
				if client.world.chunk(Vector2i(cx, cz))["ruin"] and max(abs(cx), abs(cz)) == radius:
					return WorldGen.cell_origin(Vector2i(cx, cz)) + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	return Vector2(120, 120)


func _find_forest() -> Vector2:
	for radius in range(3, 12):
		for cx in range(-radius, radius + 1):
			for cz in range(-radius, radius + 1):
				if max(abs(cx), abs(cz)) != radius:
					continue
				var center := WorldGen.cell_origin(Vector2i(cx, cz)) + Vector2.ONE * 32.0
				if client.world.biome_at(center.x, center.y) == "forest" and not client.world.is_water(center.x, center.y):
					return center
	return Vector2(100, 100)


## Outline the zombie, loot bag or player under the mouse (10 Hz pick).
func _update_hover_outline(delta: float) -> void:
	_hover_left -= delta
	if _hover_left > 0.0:
		return
	_hover_left = 0.1
	var viewport := get_viewport()
	if entities == null or camera == null or viewport == null or not client.you.has("x") or _typing():
		_hover_outline.set_target({})
		return
	var mouse := viewport.get_mouse_position()
	var plane := Plane(Vector3.UP, client.predicted.y + 0.5)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		_hover_outline.set_target({})
		return
	_hover_outline.set_target(entities.call("nearest_hoverable", hit, HoverOutline.PICK_RADIUS))


## Gore at the point of impact: your own strikes follow your aim, others' come from where the attacker stands.
func _wound_on_zombie(event: Dictionary) -> void:
	var model: Node3D = entities.model_of("zombie", int(event.get("id", -1)))
	if model == null:
		return
	var chest: Vector3 = model.global_position + Vector3.UP * 1.25
	var by: int = int(event.get("by", -1))
	var origin: Vector3
	var direction: Vector3
	if by == client.peer_id and camera != null and camera.global_position.distance_to(chest) < 6.0:
		origin = camera.global_position
		direction = -camera.global_transform.basis.z
		# Melee swings land near the crosshair, not exactly on it.
		if not bool(event.get("ranged", false)):
			direction = (direction + Vector3(randf_range(-0.08, 0.08), randf_range(-0.12, 0.08), randf_range(-0.08, 0.08))).normalized()
	else:
		var attacker: Dictionary = client.players.get(by, {})
		origin = Vector3(float(attacker.get("x", chest.x + 1.0)), chest.y + 0.2, float(attacker.get("z", chest.z)))
		var aim: Vector3 = chest + Vector3(randf_range(-0.25, 0.25), randf_range(-0.6, 0.45), randf_range(-0.25, 0.25))
		direction = (aim - origin).normalized()
	var spectacular: bool = _wound_fx.on_hit(model, origin, direction, float(event.get("damage", 0.0)),
		bool(event.get("ranged", false)), bool(event.get("fatal", false)), true, str(event.get("weapon", "")),
		float(_last_charge.get(by, 0.0)))
	if audio != null and not bool(event.get("ranged", false)):
		audio.play_gore(false, model.global_position + Vector3.UP * 1.2, -8.0 + minf(float(event.get("damage", 0.0)) * 0.1, 4.0))
	if audio != null and spectacular:
		audio.play_gore(true, model.global_position + Vector3.UP * 1.0, -2.0)
	if spectacular and by == client.peer_id and camera_fx != null:
		camera_fx._start_stop(Vector2(0.32, 0.3)) # A beat of slow motion on a brutal blow.
	if bool(event.get("fatal", false)) and _blood_decals != null \
			and BloodDecals.enabled(GraphicsQuality.level(), str(RenderingServer.get_current_rendering_method())):
		# The pool spreads under the body over a few seconds.
		var spot: Vector3 = model.global_position
		for step in 3:
			get_tree().create_timer(0.8 + step * 1.4).timeout.connect(func() -> void:
				if _blood_decals != null:
					_blood_decals.splat(client.world, spot.x + randf_range(-0.2, 0.2), spot.z + randf_range(-0.2, 0.2), false, 25.0 + step * 20.0))


## How far the current melee wind-up has charged, 0..1.
func charge_amount() -> float:
	if _charge_msec < 0:
		return 0.0
	return clampf(float(Time.get_ticks_msec() - _charge_msec - CHARGE_START_MS) / float(CHARGE_FULL_MS - CHARGE_START_MS), 0.0, 1.0)


func _melee_equipped() -> bool:
	var weapon: String = str(client.inventory.weapon) if client != null and client.inventory != null else ""
	return weapon == "" or str(Defs.item(weapon).get("weapon", "melee")) != "ranged"


func _look_direction() -> Vector2:
	var aim: Vector2 = _aim_direction()
	return aim if aim != Vector2.ZERO else Vector2(sin(client.yaw), cos(client.yaw))


var _dry_fog: Dictionary = {}

## Underwater, the environment fog turns dense and green-blue and thickens with depth;
## back at the surface the weather's own fog settings return.
func _apply_underwater_fog(under: bool, depth: float) -> void:
	if atmosphere == null or not (atmosphere.world_environment is WorldEnvironment):
		return
	var env: Environment = (atmosphere.world_environment as WorldEnvironment).environment
	if env == null:
		return
	if under:
		if _dry_fog.is_empty():
			_dry_fog = {"enabled": env.fog_enabled, "density": env.fog_density, "color": env.fog_light_color,
				"sky": env.fog_sky_affect, "energy": env.fog_light_energy}
		env.fog_enabled = true
		env.fog_light_color = Color(0.05, 0.24, 0.28)
		env.fog_light_energy = clampf(1.0 - depth * 0.08, 0.35, 1.0)
		env.fog_density = clampf(0.09 + depth * 0.02, 0.09, 0.3)
		env.fog_sky_affect = 1.0
	elif not _dry_fog.is_empty():
		env.fog_enabled = _dry_fog["enabled"]
		env.fog_density = _dry_fog["density"]
		env.fog_light_color = _dry_fog["color"]
		env.fog_sky_affect = _dry_fog["sky"]
		env.fog_light_energy = _dry_fog["energy"]
		_dry_fog = {}


# --- Data Layers: follow the server's list (winter snow, festival decor) -------------------------------

var _layers_applied: Array = []
var _snow_cover := 0.0


func _apply_data_layers(delta: float) -> void:
	var layers: Array = client.you.get("data_layers", [])
	if layers != _layers_applied:
		_layers_applied = layers.duplicate()
		ChunkView.active_layers = _layers_applied
		for cell in streamer.get_loaded_cells():
			var chunk = streamer.get_chunk(cell)
			if chunk != null and chunk.has_method("set_data_layers"):
				chunk.set_data_layers(_layers_applied)
	# Snow settles and melts over ~20 s rather than popping.
	var target: float = 1.0 if _layers_applied.has("winter") else 0.0
	if not is_equal_approx(_snow_cover, target):
		_snow_cover = move_toward(_snow_cover, target, delta / 20.0)
		RenderingServer.global_shader_parameter_set("aa_snow_cover", _snow_cover)
		if _terrain_rvt != null:
			_terrain_rvt.snow_cover = _snow_cover
