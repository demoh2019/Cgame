extends RefCounted

# Shared source revision and file integrity rules used by both the offline
# builder and the runtime. Changing any input invalidates old HLOD proxies.
const SCHEMA_VERSION := 1
const MANIFEST_PATH := "res://generated/hlod_manifest.json"
const PROXY_FOLDER := "res://generated"
const INPUT_FILES := PackedStringArray([
    "res://scenes/cell_detail.tscn",
    "res://scripts/cell_art.gd",
    "res://tools/bake_hlod_proxies.gd",
    "res://tools/hlod_bake_manifest.gd",
])

static func cell_key(cell: Vector2i) -> String:
    return "%d,%d" % [cell.x, cell.y]

static func proxy_path(cell: Vector2i) -> String:
    return "%s/forest_proxy_%d_%d.tscn" % [PROXY_FOLDER, cell.x, cell.y]

static func source_fingerprint(stride: int) -> String:
    if stride < 1 or stride > 64:
        return ""
    var inputs := PackedStringArray(["schema=%d" % SCHEMA_VERSION, "stride=%d" % stride])
    for path in INPUT_FILES:
        if not FileAccess.file_exists(path):
            return ""
        var digest := FileAccess.get_sha256(path)
        if digest.is_empty():
            return ""
        inputs.append("%s=%s" % [path, digest])
    return "\n".join(inputs).sha256_text()

static func read_valid_manifest(stride: int) -> Dictionary:
    if not FileAccess.file_exists(MANIFEST_PATH):
        return {}
    var text := FileAccess.get_file_as_string(MANIFEST_PATH)
    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        return {}
    var manifest: Dictionary = parsed
    if manifest.get("schema") != SCHEMA_VERSION or manifest.get("stride") != stride:
        return {}
    var fingerprint := source_fingerprint(stride)
    if fingerprint.is_empty() or manifest.get("fingerprint", "") != fingerprint:
        return {}
    if not (manifest.get("cells") is Dictionary):
        return {}
    return manifest

static func is_cached_proxy_valid(cell: Vector2i, manifest: Dictionary) -> bool:
    if manifest.is_empty():
        return false
    var cells: Dictionary = manifest.get("cells", {})
    var expected: Variant = cells.get(cell_key(cell), "")
    if not (expected is String) or String(expected).is_empty():
        return false
    var path := proxy_path(cell)
    return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == String(expected)
