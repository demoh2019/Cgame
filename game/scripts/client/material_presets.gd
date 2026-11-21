extends RefCounted
## Layer stacks for the game's surfaces, consumed by material_layers.gd (build_material / instance).
## Colour-only layers with procedural normals so they work without imported textures; swap an
## "albedo" for a texture path (and add "normal") to upgrade a preset without touching the shader logic.

const MaterialLayers = preload("res://scripts/client/material_layers.gd")


static func wet_mud_road() -> Dictionary:
	return {"layers": [
		{"name": "gravel", "albedo": Color(0.36, 0.32, 0.27), "roughness": 0.92, "normal_strength": 1.2,
			"uv_scale": 0.8, "height": 0.6},
		{"name": "mud", "albedo": Color(0.18, 0.13, 0.09), "roughness": 0.3, "normal_strength": 0.5,
			"uv_scale": 0.4, "height": 0.35,
			"blend": {"mode": "noise", "scale": 0.35, "threshold": 0.5, "softness": 0.2, "contrast": 3.0}},
		{"name": "puddle", "albedo": Color(0.07, 0.08, 0.09), "roughness": 0.04, "metallic": 0.0,
			"normal_strength": 0.1, "height": 0.1,
			"blend": {"mode": "noise", "scale": 0.15, "threshold": 0.72, "softness": 0.05, "contrast": 8.0}},
	]}


static func mossy_ruin_stone() -> Dictionary:
	return {"layers": [
		{"name": "stone", "albedo": Color(0.45, 0.44, 0.42), "roughness": 0.85, "normal_strength": 1.6,
			"uv_scale": 0.6, "triplanar": true, "height": 0.55},
		{"name": "moss", "albedo": Color(0.16, 0.30, 0.10), "roughness": 0.95, "normal_strength": 0.8,
			"uv_scale": 1.5, "height": 0.7, "triplanar": true,
			"blend": {"mode": "slope", "min": 0.05, "max": 0.45, "invert": true, "contrast": 4.0}},
		{"name": "grime", "albedo": Color(0.12, 0.12, 0.10), "roughness": 0.9, "height": 0.3,
			"blend": {"mode": "noise", "scale": 0.5, "threshold": 0.6, "softness": 0.15, "amount": 0.7}},
	]}


static func rusty_metal() -> Dictionary:
	return {"normal_blend": "udn", "layers": [
		{"name": "steel", "albedo": Color(0.55, 0.57, 0.6), "roughness": 0.35, "metallic": 1.0,
			"normal_strength": 0.4, "uv_scale": 1.0, "height": 0.8},
		{"name": "rust", "albedo": Color(0.45, 0.2, 0.08), "roughness": 0.88, "metallic": 0.15,
			"normal_strength": 1.8, "uv_scale": 2.0, "height": 0.3,
			"blend": {"mode": "noise", "scale": 1.2, "threshold": 0.55, "softness": 0.12, "contrast": 6.0}},
		{"name": "paint_chips", "albedo": Color(0.2, 0.28, 0.2), "roughness": 0.6, "metallic": 0.0,
			"height": 0.9, "blend": {"mode": "vertex_color", "channel": "g", "contrast": 5.0}},
	]}


static func snowy_cliff() -> Dictionary:
	return {"layers": [
		{"name": "rock", "albedo": Color(0.33, 0.31, 0.3), "roughness": 0.9, "normal_strength": 2.0,
			"uv_scale": 0.5, "triplanar": true, "triplanar_sharpness": 6.0, "height": 0.6},
		{"name": "snow", "albedo": Color(0.93, 0.95, 1.0), "roughness": 0.55, "normal_strength": 0.4,
			"uv_scale": 1.2, "height": 0.5,
			"blend": {"mode": "slope", "min": 0.1, "max": 0.35, "invert": true, "contrast": 5.0}},
		{"name": "ice", "albedo": Color(0.7, 0.85, 0.95), "roughness": 0.15, "height": 0.2,
			"blend": {"mode": "noise", "scale": 0.3, "threshold": 0.7, "softness": 0.06, "contrast": 6.0}},
	]}


static func blood_soaked_ground() -> Dictionary:
	return {"layers": [
		{"name": "dirt", "albedo": Color(0.3, 0.24, 0.18), "roughness": 0.95, "normal_strength": 1.0,
			"uv_scale": 0.7, "height": 0.6},
		{"name": "blood", "albedo": Color(0.32, 0.02, 0.02), "roughness": 0.18, "normal_strength": 0.2,
			"uv_scale": 0.5, "height": 0.2,
			"blend": {"mode": "vertex_color", "channel": "r", "contrast": 6.0}},
		{"name": "clot", "albedo": Color(0.12, 0.01, 0.01), "roughness": 0.4, "normal_strength": 0.9,
			"uv_scale": 1.4, "height": 0.4,
			"blend": {"mode": "noise", "scale": 0.9, "threshold": 0.62, "softness": 0.08, "amount": 0.9}},
	]}


static func all() -> Dictionary:
	return {
		"wet_mud_road": wet_mud_road(),
		"mossy_ruin_stone": mossy_ruin_stone(),
		"rusty_metal": rusty_metal(),
		"snowy_cliff": snowy_cliff(),
		"blood_soaked_ground": blood_soaked_ground(),
	}
