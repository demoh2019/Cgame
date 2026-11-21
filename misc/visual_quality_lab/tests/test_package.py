"""Packaging and configuration invariants; runtime coverage requires Godot."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VisualQualityPackageTests(unittest.TestCase):
    def test_all_script_references_exist(self):
        files = [ROOT / 'demo.tscn', ROOT / 'demo.gd']
        files += sorted((ROOT / 'world').rglob('*.tscn'))
        files += sorted((ROOT / 'world').rglob('*.gd'))
        files += sorted((ROOT / 'addons').rglob('*.gd'))
        files += sorted((ROOT / 'tests').glob('*.gd'))
        for file in files:
            for path in re.findall(r'res://([^"\s]+)', file.read_text()):
                self.assertTrue((ROOT / path).is_file(), f'{file.name} -> {path}')

    def test_sky_shader_no_invalid_return(self):
        shader = (ROOT / 'addons/visual_quality/filmic_sky.gdshader').read_text()
        self.assertIn('shader_type sky;', shader)
        body = shader.split('void sky()', 1)[1]
        body = re.sub(r'//[^\n]*', '', body)
        self.assertNotRegex(body, r'\breturn\b')
        self.assertNotRegex(body, r'\bTIME\b')
        self.assertIn('AT_CUBEMAP_PASS', body)
        self.assertIn('COLOR =', body)

    def test_scaler_has_cpu_guard_hysteresis_and_restoration(self):
        script = (ROOT / 'addons/visual_quality/adaptive_resolution.gd').read_text()
        for feature in ('_fps_sum', '_samples', 'cooldown_seconds', 'low_fps_ratio',
                        'high_fps_ratio', 'restore_on_exit', 'calculate_next_scale',
                        'Performance.TIME_PROCESS', 'Performance.TIME_PHYSICS_PROCESS',
                        'is_cpu_bound', 'skip_cpu_bound_drops',
                        'viewport_set_measure_render_time',
                        'viewport_get_measured_render_time_gpu',
                        'calculate_next_scale_from_gpu', 'gpu_headroom_ratio'):
            self.assertIn(feature, script)

    def test_quality_manager_persists_only_opt_in_project_preferences(self):
        script = (ROOT / 'addons/visual_quality/quality_manager.gd').read_text()
        self.assertIn('user://visual_quality_lab.cfg', script)
        for section in ('validated_profile', 'ConfigFile.new()', 'file.load',
                        'file.save', 'restore_environment_on_exit',
                        'ssao_enabled', 'ssil_enabled', 'ssr_enabled',
                        'Sky.RADIANCE_SIZE_128', 'Sky.RADIANCE_SIZE_256',
                        'use_512_radiance_in_cinematic', '_old_radiance_size'):
            self.assertIn(section, script)
        self.assertNotIn('ProjectSettings.set_setting', script)

    def test_demo_has_accessible_clickable_settings(self):
        demo = (ROOT / 'demo.gd').read_text()
        self.assertIn('HBoxContainer.new()', demo)
        self.assertIn('Button.new()', demo)
        self.assertIn('settings_changed.connect', demo)
        self.assertIn('set_adaptive_enabled', demo)
        self.assertIn('set_profile', demo)

    def test_atmosphere_is_budgeted_and_has_restoration(self):
        source = (ROOT / 'addons/visual_quality/atmosphere_controller.gd').read_text()
        for feature in ('sunlight_factor', 'fog_density_for', 'update_interval_seconds',
                        '_saved_shader_uniforms', '_exit_tree', 'atmosphere_changed',
                        'maxf(update_interval_seconds, 0.25)', 'set_overcast',
                        'sun.light_energy', 'environment.fog_density'):
            self.assertIn(feature, source)

    def test_visual_sky_supports_night_but_no_per_frame_time(self):
        shader = (ROOT / 'addons/visual_quality/filmic_sky.gdshader').read_text()
        for parameter in ('night_amount', 'night_color', 'stars_intensity',
                          'AT_CUBEMAP_PASS', 'RADIANCE'):
            self.assertIn(parameter, shader)
        self.assertNotRegex(re.sub(r'//[^\n]*', '', shader), r'\bTIME\b')

    def test_demo_exposes_weather_and_day_night(self):
        source = (ROOT / 'demo.gd').read_text()
        self.assertIn('atmosphere.atmosphere_changed.connect', source)
        self.assertIn('_toggle_weather()', source)
        self.assertIn('_toggle_hour()', source)
        self.assertIn('_toggle_cycle()', source)

    def test_foliage_culling_chunking_and_profiles(self):
        foliage = (ROOT / 'addons/visual_quality/foliage_chunks.gd').read_text()
        for feature in ('MultiMesh.new()', 'MultiMeshInstance3D.new()',
                        'custom_aabb', 'visibility_range_end', 'visible_instance_count',
                        'sample_cell_positions', 'cell_seed', 'set_quality',
                        'safe_count * 5', 'RandomNumberGenerator.new()',
                        'get_shared_trunk_mesh', 'get_shared_leaf_mesh'):
            self.assertIn(feature, foliage)
        self.assertIn('Foliage.new()', (ROOT / 'world/forest_cell.gd').read_text())
        self.assertIn('_foliage.set_quality(_quality_profile)', (ROOT / 'world/forest_cell.gd').read_text())

    def test_walkable_player_character_and_controls(self):
        player = (ROOT / 'addons/visual_quality/character_controller.gd').read_text()
        self.assertIn('extends CharacterBody3D', player)
        for feature in ('move_and_slide()', 'floor_snap_length', 'is_on_floor()',
                        'CapsuleShape3D.new()', 'start_in_fly_mode', 'jump_buffer_seconds', 'coyote_time_seconds',
                        'step_horizontal_velocity', 'should_jump', 'MOTION_MODE_FLOATING',
                        'MOTION_MODE_GROUNDED', 'KEY_SPACE', 'KEY_V', 'MOUSE_BUTTON_RIGHT'):
            self.assertIn(feature, player)
        demo = (ROOT / 'demo.gd').read_text()
        self.assertIn('player_character = CharacterController.new()', demo)
        self.assertIn('quest.player = player_character.get_view_camera()', demo)
        self.assertIn('player_character.movement_mode_changed.connect', demo)

    def test_ground_and_obstacles_have_collision(self):
        demo = (ROOT / 'demo.gd').read_text()
        for feature in ('GroundCollision', 'BoxShape3D.new()',
                        'SphereShape3D.new()', 'StaticBody3D.new()',
                        'ground_collision.shape', 'obstacle_shape.shape'):
            self.assertIn(feature, demo)
        self.assertNotIn('var camera: Camera3D = FlyCamera.new()', demo)

    def test_gameplay_quest_is_deterministic_and_persistent(self):
        source = (ROOT / 'addons/visual_quality/exploration_quest.gd').read_text()
        for feature in ('class_name ExplorationQuest3D', 'generate_positions',
                        'nearest_pickup_id', 'ConfigFile.new()', 'save_progress()',
                        'load_progress()', 'user://visual_quality_quest_v1.cfg',
                        'get_viewport().set_input_as_handled()',
                        'collect_shard', 'collected_ids.has(index)',
                        'quest_finished.emit()', 'reset_quest'):
            self.assertIn(feature, source)

    def test_gameplay_integrated_into_scene_and_atmosphere(self):
        demo = (ROOT / 'demo.gd').read_text()
        for feature in ('ExplorationQuest.new()', 'quest.player =',
                        'quest.quest_finished.connect', '_on_quest_finished',
                        'atmosphere.set_hour(12.0)', '_build_quest_ui()',
                        'reset_button.pressed.connect', 'KEY_R'):
            self.assertIn(feature, demo)

    def test_world_streamer_engine_service(self):
        source = (ROOT / 'addons/visual_quality/world_streamer.gd').read_text()
        for feature in ('class_name WorldStreamer3D', 'register_scene_cell',
                        'unregister_scene_cell', 'ResourceLoader.load_threaded_request',
                        'ResourceLoader.load_threaded_get_status',
                        'ResourceLoader.THREAD_LOAD_LOADED',
                        'ResourceLoader.load_threaded_get(path)',
                        'max_spawns_per_update', 'max_concurrent_loads',
                        'max_unloads_per_update', 'within_cell_radius',
                        'cell_at_local_position', 'get_active_cells',
                        'cell_loaded.emit', 'cell_unloaded.emit',
                        'set_quality_profile', '_scene_cache'):
            self.assertIn(feature, source)
        self.assertIn('if resource is PackedScene:', source)
        self.assertIn('queue_free()', source)

    def test_world_streamer_immediately_integrated_in_game(self):
        demo = (ROOT / 'demo.gd').read_text()
        for feature in ('WorldStreamer.new()', 'streamer.source = player_character',
                        'streamer.register_scene_cell',
                        'streamer.cell_loaded.connect', 'streamer.set_quality_profile',
                        'streamer.active_cell_count()', 'KEY_7'):
            self.assertIn(feature, demo)
        scene = (ROOT / 'world/forest_cell.tscn').read_text()
        self.assertIn('res://world/forest_cell.gd', scene)
        world = (ROOT / 'world/forest_cell.gd').read_text()
        self.assertIn('configure_stream_cell', world)
        self.assertIn('Foliage.new()', world)
        self.assertNotIn('foliage = ChunkedFoliage.new()', demo)

    def test_world_state_store_has_versioning_and_safe_save_protocol(self):
        script = (ROOT / 'addons/visual_quality/world_state_store.gd').read_text()
        for token in ('class_name WorldStateStore3D', 'SAVE_VERSION', 'world_id',
                      'cell_about_to_unload.connect', 'cell_loaded.connect',
                      'capture_cell', 'load_from_disk', 'save_now',
                      'ConfigFile.new()', 'DirAccess.rename_absolute',
                      'sanitize_state', 'TYPE_DICTIONARY', 'MAX_SAVED_CELLS',
                      'clear_all_states', 'get_saved_state'):
            self.assertIn(token, script)

    def test_unload_signal_precedes_node_deletion(self):
        streamer = (ROOT / 'addons/visual_quality/world_streamer.gd').read_text()
        unload = streamer.split('func _unload_cell(coord: Vector2i) -> void:', 1)[1]
        unload = unload.split('func _record_failure', 1)[0]
        self.assertIn('cell_about_to_unload.emit(coord, instance)', unload)
        self.assertLess(unload.index('cell_about_to_unload.emit'), unload.index('remove_child(instance)'))
        self.assertLess(unload.index('cell_about_to_unload.emit'), unload.index('instance.queue_free()'))

    def test_gameplay_uses_stream_state_and_beacon_ui(self):
        world = (ROOT / 'world/forest_cell.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        for token in ('save_stream_state', 'load_stream_state', 'try_activate_beacon',
                      'stream_state_changed.emit', 'get_stream_cell_coord'):
            self.assertIn(token, world)
        for token in ('WorldStateStore.new()', 'world_state.streamer = streamer',
                      'world_state.saved_cell_count()', 'KEY_G', 'KEY_8',
                      '_try_activate_world_beacon', '_reset_world_beacons'):
            self.assertIn(token, demo)
        self.assertLess(demo.index('add_child(world_state)'), demo.index('add_child(streamer)'))

    def test_navmesh_tile_and_patrol_agent_engine_components(self):
        tile = (ROOT / 'addons/visual_quality/navigation_tile.gd').read_text()
        npc = (ROOT / 'addons/visual_quality/streamed_patrol_npc.gd').read_text()
        for token in ('extends NavigationRegion3D', 'make_flat_tile',
                      'NavigationMesh.new()', 'PackedVector3Array', 'add_polygon'):
            self.assertIn(token, tile)
        for token in ('extends CharacterBody3D', 'NavigationAgent3D.new()',
                      'get_next_path_position()', 'map_get_iteration_id',
                      'avoidance_enabled = false', 'should_alert', 'patrol_point',
                      'export_npc_state', 'import_npc_state',
                      'think_interval_seconds', 'move_and_slide()'):
            self.assertIn(token, npc)
        self.assertIn('if not _navigation_ready:', npc)

    def test_streamed_cell_creates_navigation_and_persists_npc_state(self):
        cell = (ROOT / 'world/forest_cell.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        for token in ('NavigationTile.new()', 'NPC.new()',
                      '_npc.player = owner_streamer.source', 'get_active_npc',
                      '_npc.export_npc_state()', '_npc.import_npc_state(state)',
                      'set_ai_enabled', 'state.merge(npc_data)'):
            self.assertIn(token, cell)
        for token in ('_count_npc_behaviors()', '_toggle_ai_simulation',
                      'npc_counts.x', 'KEY_9', 'set_ai_enabled'):
            self.assertIn(token, demo)
        self.assertLess(cell.index('add_child(_navigation_tile)'), cell.index('add_child(_npc)'))

    def test_navigation_avoids_authored_rectangles_with_clearance(self):
        nav = (ROOT / 'addons/visual_quality/navigation_tile.gd').read_text()
        for token in ('make_obstacle_tile', 'blocked_rectangles', 'obstacle_clearance',
                      'clipped.append', 'blocker.has_point', 'deduplicate_breaks',
                      'result.add_polygon', 'mini(blocked.size(), 8)'):
            self.assertIn(token, nav)

    def test_streamed_rocks_match_navigation_holes(self):
        cell = (ROOT / 'world/forest_cell.gd').read_text()
        for token in ('_navigation_tile.blocked_rectangles', '_create_rock_obstacle',
                      'NavigationRock', 'StaticBody3D.new()', 'BoxShape3D.new()',
                      'shape.size = Vector3(2.2, 2.0, 2.2)'):
            self.assertIn(token, cell)
        self.assertLess(cell.index('add_child(_navigation_tile)'), cell.index('_create_rock_obstacle()'))

    def test_ai_interest_engine_scheduler_integrated(self):
        interest = (ROOT / 'addons/visual_quality/ai_interest_manager.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        for token in ('WorldAIInterestManager3D', 'should_simulate',
                      'max_cells_per_update', 'Time.get_ticks_usec()',
                      'sleeping_npc_count', 'refresh_budgeted', 'exit_margin',
                      'set_global_enabled', 'streamer.cell_loaded.connect'):
            self.assertIn(token, interest)
        for token in ('AIInterest.new()', 'ai_interest.streamer = streamer',
                      'ai_interest.player = player_character', 'ai_interest.set_quality_profile',
                      'ai_interest.set_global_enabled', 'sleeping_npc_count()',
                      'ai_interest.last_update_micros'):
            self.assertIn(token, demo)

    def test_world_telemetry_is_bounded_and_csv_export_is_explicit(self):
        telemetry = (ROOT / 'addons/visual_quality/world_telemetry.gd').read_text()
        for token in ('class_name WorldTelemetry3D', 'Performance.TIME_PROCESS',
                      'Performance.TIME_PHYSICS_PROCESS', 'Performance.TIME_FPS',
                      'Time.get_ticks_msec()', 'sample_interval_seconds',
                      'capacity', '_next_index', 'push_snapshot',
                      'percentile_nearest_rank', 'store_csv_line',
                      'csv_path.begins_with("user://")', 'get_samples_oldest_first'):
            self.assertIn(token, telemetry)
        self.assertNotIn('FileAccess.open(csv_path, FileAccess.WRITE)', telemetry.split('func _process', 1)[1].split('func export_csv', 1)[0])

    def test_governor_uses_cpu_guard_and_streak_hysteresis(self):
        governor = (ROOT / 'addons/visual_quality/world_budget_governor.gd').read_text()
        for token in ('class_name WorldBudgetGovernor3D', 'target_cpu_ms',
                      'overload_windows', 'recovery_windows', '_overload_streak',
                      '_recovery_streak', 'high_load_ratio', 'low_load_ratio',
                      'cpu_ms > target_cpu_ms', 'is_finite(cpu_ms)',
                      'max_spawns_per_update', 'max_cells_per_update',
                      'set_quality_profile', 'set_automatic_enabled',
                      'budget_changed.emit'):
            self.assertIn(token, governor)
        self.assertNotIn('Engine.get_frames_per_second()', governor)

    def test_world_profiler_and_governor_wired_into_game_and_streamer(self):
        demo = (ROOT / 'demo.gd').read_text()
        streamer = (ROOT / 'addons/visual_quality/world_streamer.gd').read_text()
        for token in ('Telemetry.new()', 'BudgetGovernor.new()',
                      'telemetry.snapshot_captured.connect',
                      'governor.set_quality_profile(profile)',
                      'governor.set_automatic_enabled', 'KEY_0', 'KEY_B',
                      'KEY_P', 'telemetry.export_csv()', 'get_cpu_p95_ms()'):
            self.assertIn(token, demo)
        for token in ('last_update_micros', 'last_spawned_count',
                      'last_unloaded_count', 'peak_update_micros',
                      'Time.get_ticks_usec()', 'total_spawned_count'):
            self.assertIn(token, streamer)
        self.assertLess(streamer.index('var started_usec: int = Time.get_ticks_usec()'), streamer.index('_poll_background_loads()'))

    def test_streaming_planner_is_predictive_bounded_and_deterministic(self):
        planner = (ROOT / 'addons/visual_quality/world_streaming_planner.gd').read_text()
        for key in ('class_name WorldStreamingPlanner3D', 'predict_cell',
                    'build_load_queue', 'required.sort_custom',
                    'speculative.sort_custom', 'safe_keep', 'max_prefetch',
                    'max_lead_cells', 'is_speculative', 'cell_for_position'):
            self.assertIn(key, planner)
        self.assertLess(planner.index('required.sort_custom'), planner.index('speculative.sort_custom'))

    def test_streamer_profiles_cells_and_integrates_lookahead(self):
        streamer = (ROOT / 'addons/visual_quality/world_streamer.gd').read_text()
        for key in ('StreamingPlanner.build_load_queue', 'StreamingPlanner.predict_cell',
                    'velocity_local', 'last_predicted_cell', 'total_prefetched_count',
                    'last_prefetched_count', '_record_cell_timing',
                    'get_cell_profile', 'get_slowest_cells',
                    'max_profiled_cells', 'peak_spawn_us', 'is_cell_registered'):
            self.assertIn(key, streamer)
        self.assertLess(streamer.index('cell_loaded.emit(coord, node)'),
                        streamer.index('_record_cell_timing(coord, true'))

    def test_streaming_profiler_overlay_and_csv_connected_to_game(self):
        inspector = (ROOT / 'addons/visual_quality/world_streaming_inspector.gd').read_text()
        telemetry = (ROOT / 'addons/visual_quality/world_telemetry.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        for key in ('class_name WorldStreamingInspector3D', 'get_slowest_cells',
                    'export_hotspot_csv', 'FileAccess.WRITE',
                    'hotspot_csv_path.begins_with("user://")',
                    'get_active_cell', 'last_predicted_cell'):
            self.assertIn(key, inspector)
        for key in ('hottest_cell_us', 'total_prefetched', 'profiled_cells'):
            self.assertIn(key, telemetry)
        for key in ('StreamingInspector.new()', 'streaming_inspector.streamer = streamer',
                    'KEY_K', 'KEY_L', 'export_hotspot_csv()'):
            self.assertIn(key, demo)

    def test_world_interaction_router_is_spatial_and_stream_safe(self):
        router = (ROOT / 'addons/visual_quality/world_interaction_router.gd').read_text()
        for feature in ('class_name WorldInteractionRouter3D', 'select_best',
                        'last_candidate_count', 'last_scanned_cells',
                        'get_active_cell(Vector2i(x, z))', 'max_query_distance',
                        'camera.global_basis.z', 'interaction_enabled',
                        'get_interaction_targets', 'activate_interaction',
                        'PhysicsRayQueryParameters3D.create',
                        'cell_about_to_unload.connect', '_set_focus({})',
                        'is_instance_valid(provider)', 'KEY_H',
                        'focused_action_changed.emit', 'interaction_completed.emit'):
            self.assertIn(feature, router)
        # A focused node is re-discovered before invoking it, avoiding stale
        # references after WorldStreamer3D removes a scene cell.
        action = router.split('func try_interact() -> bool:', 1)[1]
        self.assertLess(action.index('find_best_action()'), action.index('provider.call("activate_interaction"'))

    def test_interaction_providers_revalidate_range_and_persist_npc_dialogue(self):
        quest = (ROOT / 'addons/visual_quality/exploration_quest.gd').read_text()
        forest = (ROOT / 'world/forest_cell.gd').read_text()
        for feature in ('get_interaction_targets', 'activate_interaction',
                        'get_interaction_message', 'pickup_distance * pickup_distance',
                        'collected_ids.has(index)'):
            self.assertIn(feature, quest)
        for feature in ('get_interaction_targets', 'activate_interaction',
                        'get_interaction_message', 'npc_talk_count',
                        'npc_talk_count + 1', 'stream_state_changed.emit()',
                        'state["npc_talk_count"]', 'state.get("npc_talk_count", 0)',
                        'try_activate_beacon(actor_eye, 2.8)'):
            self.assertIn(feature, forest)

    def test_interaction_router_is_live_in_playable_demo(self):
        demo = (ROOT / 'demo.gd').read_text()
        for feature in ('InteractionRouter.new()', 'interaction_router.streamer = streamer',
                        'interaction_router.quest = quest',
                        'interaction_router.player = player_character',
                        'interaction_router.camera = player_character.get_view_camera()',
                        'interaction_router.focused_action_changed.connect',
                        'interaction_router.interaction_completed.connect',
                        '_build_interaction_ui()', 'WorldInteractionPrompt',
                        'WorldInteractionFeedback',
                        'interaction_label.anchor_bottom = 1.0',
                        'interaction_result_label.anchor_bottom = 1.0'):
            self.assertIn(feature, demo)
        self.assertLess(demo.index('add_child(quest)'), demo.index('add_child(interaction_router)'))

    def test_item_catalog_has_validated_caps_and_declarative_recipes(self):
        source = (ROOT / 'addons/visual_quality/item_catalog.gd').read_text()
        for marker in ('class_name VisualItemCatalog', 'DEFINITIONS', 'RECIPES',
                       'max_stack', 'is_valid_item', 'get_recipe', 'forest_lantern',
                       'spark_core', 'forest_essence', 'light_shard'):
            self.assertIn(marker, source)
        self.assertIn('return RECIPES.get(recipe_id, {}).duplicate(true)', source)

    def test_inventory_supports_idempotency_limits_and_safe_persistence(self):
        source = (ROOT / 'addons/visual_quality/inventory_component.gd').read_text()
        for marker in ('class_name WorldInventory3D', 'FORMAT_VERSION',
                       'MAX_REWARD_CLAIMS', '_claimed_sources', 'grant_once',
                       'import_quest_history', 'can_add', 'add_item', 'remove_item',
                       'items_snapshot', 'valid_source_uid', 'save_now',
                       'load_from_disk', 'save_path.begins_with("user://")',
                       'ConfigFile.new()', 'DirAccess.rename_absolute',
                       '_persist_or_rollback', 'simulate_recipe', 'item_crafted.emit'):
            self.assertIn(marker, source)
        self.assertLess(source.index('save_now() == OK'), source.index('_items = old_items.duplicate(true)'))
        self.assertNotIn('get_node("', source)

    def test_crafting_is_transactional_and_never_spends_before_validation(self):
        source = (ROOT / 'addons/visual_quality/inventory_component.gd').read_text()
        body = source.split('static func simulate_recipe(', 1)[1]
        self.assertIn('current.duplicate(true)', body)
        self.assertIn('remaining == 0', body)
        self.assertIn('Catalog.max_stack(output_id) - output_count', body)
        self.assertLess(body.index('if int(updated.get(output_id, 0)) >'),
                        body.index('updated[output_id] ='))
        self.assertIn('if updated.is_empty():', source)
        self.assertIn('if not _persist_or_rollback(before, _claimed_sources, before_equipped):', source)

    def test_inventory_rewards_crafting_and_ui_are_in_playable_demo(self):
        quest = (ROOT / 'addons/visual_quality/exploration_quest.gd').read_text()
        forest = (ROOT / 'world/forest_cell.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        for marker in ('signal shard_collected(index: int)', 'shard_collected.emit(index)'):
            self.assertIn(marker, quest)
        for marker in ('signal resource_awarded(', 'resource_awarded.emit("forest_essence"'):
            self.assertIn(marker, forest)
        for marker in ('Inventory.new()', 'inventory.grant_once',
                       'inventory.import_quest_history', 'world_state.get_saved_state(coord)',
                       'quest.shard_collected.connect', 'resource_awarded',
                       'inventory.craft(recipe_id)', 'WorldInventoryPanel',
                       'KEY_I', 'KEY_C', 'KEY_J', 'KEY_T',
                       '_build_inventory_ui()', 'OmniLight3D.new()',
                       'get_view_camera().add_child(equipped_lantern)'):
            self.assertIn(marker, demo)
        self.assertLess(demo.index('add_child(inventory)'), demo.index('add_child(streamer)'))

    def test_v16_attribute_and_ability_services(self):
        stats = (ROOT / 'addons/visual_quality/attribute_component.gd').read_text()
        abilities = (ROOT / 'addons/visual_quality/ability_component.gd').read_text()
        for token in ('class_name WorldAttributes3D', 'set_equipment', 'remove_equipment',
                      'get_stat', 'validate_modifiers', 'apply_timed_effect',
                      'effect_remaining', 'try_spend_stamina', 'regen_delay_after_use',
                      'vitals_snapshot', 'restore_vitals', 'apply_damage', 'heal'):
            self.assertIn(token, stats)
        for token in ('class_name WorldAbilitySystem3D', 'cooldowns_snapshot',
                      'stamina_cost', 'can_activate', 'apply_timed_effect',
                      'try_spend_stamina', 'ability_activated.emit', 'dash', 'focus'):
            self.assertIn(token, abilities)
        activation = abilities.split('func activate(ability_id: String) -> bool:', 1)[1]
        self.assertLess(activation.index('if not can_activate(ability_id):'),
                        activation.index('_cooldowns[ability_id] ='))

    def test_v16_equipment_is_persistent_and_inventory_compatible(self):
        items = (ROOT / 'addons/visual_quality/item_catalog.gd').read_text()
        inventory = (ROOT / 'addons/visual_quality/inventory_component.gd').read_text()
        for token in ('trail_boots', 'equipment_slot', 'equipment_modifiers',
                      '"feet"', '"utility"'):
            self.assertIn(token, items)
        for token in ('signal equipment_changed', 'equip_item', 'unequip_slot',
                      'get_equipped_item', 'equipped_snapshot', '"equipped", _equipped',
                      'config.get_value("inventory", "equipped", {})',
                      'get_count(item_id) <= 0', 'old_equipped'):
            self.assertIn(token, inventory)
        self.assertIn('Catalog.equipment_slot(item_id) != slot', inventory)

    def test_v16_player_and_game_use_attributes_equipment_and_skills(self):
        character = (ROOT / 'addons/visual_quality/character_controller.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        for token in ('attributes: WorldAttributes3D', 'attributes.try_spend_stamina',
                      'attributes.get_stat("move_speed")', 'walk_speed * speed_modifier'):
            self.assertIn(token, character)
        for token in ('Attributes.new()', 'Abilities.new()',
                      'inventory.equipment_changed.connect', 'ItemCatalog.equipment_modifiers',
                      'player_character.attributes = player_attributes',
                      'player_abilities.activate(ability_id)', 'KEY_X', 'KEY_Z',
                      'KEY_Y', 'KEY_U', 'trail_boots', '_toggle_trail_boots',
                      'get_equipped_item("utility")'):
            self.assertIn(token, demo)

    def test_v16_godot_regression_suites_registered(self):
        for name in ('test_attributes.gd', 'test_abilities.gd', 'test_equipment.gd',
                     'test_equipment_persistence.gd'):
            self.assertTrue((ROOT / 'tests' / name).is_file())

    def test_v17_combat_component_has_validated_team_damage_and_statuses(self):
        combat = (ROOT / 'addons/visual_quality/combat_component.gd').read_text()
        for token in ('class_name WorldCombatant3D', 'compute_damage',
                      'TEAM_PLAYER', 'TEAM_HOSTILE', 'armor', 'hit_immunity_seconds',
                      'can_receive_hit', 'receive_damage', 'apply_stun',
                      'stun_changed.emit', 'damage_taken.emit', 'defeated.emit',
                      'restore_health', '_defeat_reported'):
            self.assertIn(token, combat)
        self.assertLess(combat.index('if not is_finite(raw_damage)'), combat.index('var actual: float = compute_damage'))

    def test_v17_hostile_sentry_attacks_and_sleeps_with_ai_lod(self):
        sentry = (ROOT / 'addons/visual_quality/hostile_sentry.gd').read_text()
        for token in ('class_name WorldHostileSentry3D', 'extends StaticBody3D',
                      'SentryCombatant', 'WorldCombatant3D.TEAM_HOSTILE',
                      'attack_interval', 'player_combatant.receive_damage',
                      'sentry_defeated.emit', 'state_changed.emit',
                      'save_sentry_state', 'load_sentry_state',
                      'combatant.set_physics_process(enabled)'):
            self.assertIn(token, sentry)
        self.assertLess(sentry.index('if not ai_enabled'), sentry.index('player_combatant.receive_damage'))

    def test_v17_combat_director_uses_bounded_loaded_cell_queries(self):
        director = (ROOT / 'addons/visual_quality/combat_controller.gd').read_text()
        for token in ('class_name WorldCombatDirector3D', 'choose_facing_target',
                      'get_active_cell(Vector2i(x, z))', 'get_hostile_sentry',
                      'strike_cooldown', 'pulse_cooldown', 'try_spend_stamina',
                      'receive_damage(melee_damage', 'receive_damage(pulse_damage',
                      'max_pulse_targets', 'clampi(ceili(radius / streamer.cell_size) + 1, 1, 3)'):
            self.assertIn(token, director)
        self.assertNotIn('get_nodes_in_group(', director)

    def test_v17_combat_is_live_and_persistent_in_game(self):
        forest = (ROOT / 'world/forest_cell.gd').read_text()
        demo = (ROOT / 'demo.gd').read_text()
        character = (ROOT / 'addons/visual_quality/character_controller.gd').read_text()
        for token in ('Sentry.new()', 'get_hostile_sentry()', 'save_sentry_state()',
                      'load_sentry_state(state)', 'set_ai_enabled(ai_enabled)',
                      'sentry_defeated.emit', 'resource_awarded.emit("forest_essence", "sentry:'):
            self.assertIn(token, forest)
        for token in ('Combatant.new()', 'CombatDirector.new()',
                      'player_combatant.defeated.connect',
                      'combat_director.streamer = streamer',
                      'KEY_M', 'KEY_N', 'KEY_BACKSPACE',
                      '_respawn_player()', 'WorldCombatFeedback'):
            self.assertIn(token, demo)
        self.assertIn('attributes.health <= 0.0', character)
        for filename in ('test_combat_component.gd', 'test_combat_selection.gd',
                         'test_hostile_sentry.gd', 'test_combat_streaming_runtime.gd', 'test_combat_visibility.gd', 'test_combat_visibility_runtime.gd'):
            self.assertTrue((ROOT / 'tests' / filename).is_file())

    def test_v18_combat_visibility_uses_godot_physics_safe_queries(self):
        source = (ROOT / "addons/visual_quality/combat_visibility.gd").read_text()
        for token in ("WorldCombatVisibility3D", "PhysicsRayQueryParameters3D.create",
                      "direct_space_state.intersect_ray", "Array[RID]",
                      "is_instance_valid(target)", "hit_is_clear", "origin.is_finite()"):
            self.assertIn(token, source)
        self.assertIn('get_rid()', source)

    def test_v18_physics_tick_input_queue_and_cover_in_game(self):
        director = (ROOT / "addons/visual_quality/combat_controller.gd").read_text()
        sentry = (ROOT / "addons/visual_quality/hostile_sentry.gd").read_text()
        demo = (ROOT / "demo.gd").read_text()
        for token in ('request_strike', 'request_shockwave', '_queued_strike',
                      '_queued_shockwave', 'max_visibility_checks', 'cover_collision_mask',
                      'Visibility.has_clear_path', 'visibility_checks_last'):
            self.assertIn(token, director)
        self.assertIn('Visibility.has_clear_path', sentry)
        self.assertIn('combat_director.request_strike()', demo)
        self.assertIn('combat_director.request_shockwave()', demo)
        self.assertLess(director.index('func _physics_process'), director.index('func request_strike'))
        self.assertNotIn('combat_director.strike()', demo)

    def test_v18_combat_visibility_test_suites_exist(self):
        for file in ('test_combat_visibility.gd', 'test_combat_visibility_runtime.gd'):
            self.assertTrue((ROOT / 'tests' / file).is_file())

    def test_headless_regression_suites_present(self):
        for filename in ('test_adaptive_resolution.gd', 'test_quality_manager.gd', 'test_atmosphere.gd', 'test_foliage.gd', 'test_exploration_quest.gd', 'test_character.gd', 'test_character_physics.gd', 'test_world_streamer.gd', 'test_world_streamer_runtime.gd', 'test_world_state_store.gd', 'test_world_state_runtime.gd', 'test_streamed_navigation.gd', 'test_streamed_navigation_runtime.gd', 'test_navigation_obstacles.gd', 'test_ai_interest.gd', 'test_navigation_obstacles_runtime.gd', 'test_world_telemetry.gd', 'test_world_budget_governor.gd', 'test_streaming_planner.gd', 'test_streaming_cell_profiler.gd', 'test_predictive_streaming_runtime.gd', 'test_world_interaction.gd', 'test_world_interaction_runtime.gd', 'test_inventory_component.gd', 'test_inventory_crafting.gd', 'test_inventory_persistence.gd', 'test_inventory_gameplay.gd', 'test_attributes.gd', 'test_abilities.gd', 'test_equipment.gd', 'test_equipment_persistence.gd', 'test_combat_component.gd', 'test_combat_selection.gd', 'test_hostile_sentry.gd', 'test_combat_streaming_runtime.gd', 'test_combat_visibility.gd', 'test_combat_visibility_runtime.gd'):
            text = (ROOT / 'tests' / filename).read_text()
            self.assertIn('extends SceneTree', text)
            self.assertIn('assert(', text)
            self.assertIn('quit(0)', text)


if __name__ == '__main__':
    unittest.main()
