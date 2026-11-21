# hud.gd

> All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

`res://scripts/client/hud.gd`

## Overview

All of the interface, built in code: vitals, zone, inventory, crafting and a message log.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const ReturnRate = preload("res://scripts/shared/return_rate.gd")`
- `const Factions = preload("res://scripts/shared/factions.gd")`
- `const Farming = preload("res://scripts/shared/farming.gd")`
- `const MarketBoard = preload("res://scripts/shared/market_board.gd")`
- `const Combat = preload("res://scripts/shared/combat.gd")`
- `const RaidCone = preload("res://scripts/shared/raid_cone.gd")`
- `const Party = preload("res://scripts/shared/party.gd")`
- `const PartyAid = preload("res://scripts/shared/party_aid.gd")`
- `const StormLightning = preload("res://scripts/shared/storm_lightning.gd")`
- `const Weather = preload("res://scripts/shared/weather.gd")`
- `const CorpseScent = preload("res://scripts/shared/corpse_scent.gd")`
- `const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")`
- `const TrailRation = preload("res://scripts/shared/trail_ration.gd")`
- `const CombatStress = preload("res://scripts/shared/combat_stress.gd")`
- `const QuickCooking = preload("res://scripts/shared/quick_cooking.gd")`
- `const FishingDisplay = preload("res://scripts/shared/fishing_display.gd")`
- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const Crafting = preload("res://scripts/shared/crafting.gd")`
- `const CraftingCatalog = preload("res://scripts/shared/crafting_catalog.gd")`
- `const ExpeditionLoadout = preload("res://scripts/shared/expedition_loadout.gd")`
- `const Vendor = preload("res://scripts/shared/vendor.gd")`
- `const FirstSteps = preload("res://scripts/client/first_steps.gd")`
- `const Contracts = preload("res://scripts/shared/contracts.gd")`
- `const CampRest = preload("res://scripts/shared/camp_rest.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")`
- `const Reputation = preload("res://scripts/shared/reputation.gd")`
- `const SurvivalRadar = preload("res://scripts/client/survival_radar.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`
- `const PartyFrames = preload("res://scripts/client/party_frames.gd")`
- `const HudSkin = preload("res://scripts/client/hud_skin.gd")`
- `const UiTheme = preload("res://scripts/client/ui_theme.gd")`
- `const ItemIcons = preload("res://scripts/client/item_icons.gd")`
- `const EquipmentPresets = preload("res://scripts/shared/equipment_presets.gd")`
- `const ITEM_CATEGORIES := [["weapons", "Weapons", "machete"], ["gear", "Armor and clothes", "jacket"],`
- `const EFFECTS := [`
- `const QUALITY_COLORS := [Color.WHITE, Color.WHITE, Color(0.75, 0.85, 1.0), Color(0.55, 0.9, 0.55), Color(0.8, 0.55, 1.0), Color(1.0, 0.8, 0.3)]`
- `const TIER_COLORS := [Color(0.62, 0.64, 0.68), Color(0.62, 0.64, 0.68), Color(0.36, 0.82, 0.42), Color(0.36, 0.62, 1.0), Color(0.78, 0.42, 1.0),`
- `const DOLL_SLOTS := [["bag", "Bag", "trail_backpack"], ["head", "Head", "hood_1"], ["cape", "Cape", "cloak_1"],`

## Functions

### `setup`

```gdscript
func setup(p_client) -> void
```

### `set_details_visible`

```gdscript
func set_details_visible(shown: bool) -> void
```

F3: the full text readout (every number and timer) instead of the drawn interface.

### `quick_cook`

```gdscript
func quick_cook(stew: bool = false) -> void
```

Invoked from the online '0' key and inventory button.

### `quick_smoke`

```gdscript
func quick_smoke() -> void
```

### `eat_smoked`

```gdscript
func eat_smoked() -> void
```

### `toggle_inventory`

```gdscript
func toggle_inventory() -> void
```

### `button_shadow`

```gdscript
static func button_shadow(style: StyleBoxFlat) -> void
```

### `toggle_social`

```gdscript
func toggle_social() -> void
```

### `toggle_crafting`

```gdscript
func toggle_crafting() -> void
```

### `is_menu_open`

```gdscript
func is_menu_open() -> bool
```

### `set_prompt`

```gdscript
func set_prompt(text: String) -> void
```

### `banner`

```gdscript
func banner(text: String, color: Color = Color(0.95, 0.78, 0.35)) -> void
```

A big announcement in the middle of the screen (level ups, places you enter).

### `say`

```gdscript
func say(text: String) -> void
```

_51 private function(s) starting with `_` are not listed._
