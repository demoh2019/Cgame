extends RefCounted
## Closed captions for important sounds with a direction relative to the camera, e.g. "[Gunshot, left, 24 m]"
## (Unity has no built-in equivalent; Unreal ships Subtitles/Closed Captions and sound-class captions).
## Pure static functions turn a server event into text; `CaptionView` shows the last few lines.

const UiLocalization = preload("res://scripts/client/ui_localization.gd")

const SECTORS := ["ahead", "ahead-right", "right", "behind-right", "behind", "behind-left", "left", "ahead-left"]
const NEARBY_M := 2.5
const MAX_RANGE_M := 120.0


## Direction word for an offset in world XZ given the camera's forward/right vectors flattened to XZ.
static func direction_word(offset: Vector2, forward: Vector2, right: Vector2) -> String:
	if offset.length() < NEARBY_M:
		return "nearby"
	var angle := atan2(offset.dot(right), offset.dot(forward)) # 0 = straight ahead, + = right.
	var sector := int(round(angle / (TAU / 8.0))) % 8
	if sector < 0:
		sector += 8
	return SECTORS[sector]


## English caption key for an event, or "" when it makes no important sound.
static func caption_key(event: Dictionary, local_peer: int) -> String:
	match str(event.get("type", "")):
		"attack":
			return "Gunshot" if bool(event.get("ranged", false)) else "Melee swing"
		"hit":
			if str(event.get("kind", "")) == "zombie":
				return "Infected shrieks"
			if int(event.get("id", -1)) == local_peer:
				return "You are hit"
			return ""
		"zombie_died":
			return "Infected collapses"
		"barricade_broken":
			return "Barricade breaks"
		"snare_triggered":
			return "Trap snaps"
		"flash_thrown":
			return "Flash burst"
		"lightning_struck":
			return "Thunder crack"
		"lightning_warning":
			return "Thunder warning"
		"knockback":
			return "Impact"
		"death":
			return "You die" if int(event.get("peer", -1)) == local_peer else ""
		"outpost_taken":
			return "Outpost captured"
		"skill_up":
			return "Skill improves" if int(event.get("peer", -1)) == local_peer else ""
		"crate":
			return "Crate opens"
	return ""


## Full caption line or "". `listener` is the player's XZ, `forward`/`right` the camera basis flattened to XZ.
static func caption_for(event: Dictionary, local_peer: int, listener: Vector2, forward: Vector2, right: Vector2,
		locale: String = "") -> String:
	var key := caption_key(event, local_peer)
	if key == "":
		return ""
	var parts := [UiLocalization.t(key, locale)]
	if event.has("x") and event.has("z"):
		var at := Vector2(float(event["x"]), float(event["z"]))
		if at.is_finite():
			var offset := at - listener
			if offset.length() > MAX_RANGE_M:
				return "" # Too far to be heard at all.
			var word := direction_word(offset, forward, right)
			parts.append(UiLocalization.t(word, locale))
			if word != "nearby":
				parts.append("%d m" % int(round(offset.length())))
	return "[" + ", ".join(parts) + "]"


## Lines kept on screen: newest last, duplicates within `window` seconds merged, at most `limit` rows.
static func push_line(lines: Array, text: String, now: float, window: float = 0.8, limit: int = 4) -> Array:
	# Cap the collection even for malformed caller input. Never mutate
	# existing caption timestamps while deciding whether to merge duplicates.
	if limit <= 0:
		return []
	var out: Array = lines.duplicate(true)
	if text.strip_edges().is_empty() or not is_finite(now):
		return out
	var merge_window: float = maxf(0.0, window) if is_finite(window) else 0.0
	for row in out:
		var elapsed: float = now - float(row["time"])
		if row["text"] == text and elapsed >= 0.0 and elapsed < merge_window:
			row["time"] = now
			return out
	out.append({"text": text, "time": now})
	while out.size() > limit:
		out.pop_front()
	return out


## A small bottom-centre caption strip (a Control, so it follows UI scale).
class CaptionView extends VBoxContainer:
	const LIFETIME := 4.0
	var lines: Array = []
	var font_size := 18
	var _clock := 0.0

	func _init() -> void:
		name = "ClosedCaptions"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		alignment = BoxContainer.ALIGNMENT_END
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		offset_top = -230.0
		offset_bottom = -150.0
		add_theme_constant_override("separation", 2)

	func add_caption(text: String) -> void:
		lines = push_line_static(lines, text, _clock)
		_rebuild()

	static func push_line_static(rows: Array, text: String, now: float) -> Array:
		var script: GDScript = load("res://scripts/client/ui_captions.gd")
		return script.push_line(rows, text, now)

	func _process(delta: float) -> void:
		_clock += delta
		var before := lines.size()
		lines = lines.filter(func(row) -> bool: return _clock - float(row["time"]) < LIFETIME)
		if lines.size() != before:
			_rebuild()

	func _rebuild() -> void:
		for child in get_children():
			child.queue_free()
		for row in lines:
			var label := Label.new()
			label.text = row["text"]
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", font_size)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 6)
			var back := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0.62)
			style.set_corner_radius_all(6)
			style.set_content_margin_all(4)
			back.add_theme_stylebox_override("panel", style)
			back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			back.add_child(label)
			add_child(back)
