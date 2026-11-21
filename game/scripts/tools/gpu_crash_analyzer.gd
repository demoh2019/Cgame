extends RefCounted
## GPU crash / error log analyzer: parses Godot logs and Vulkan/Metal error text
## into structured reports {kind, message, likely_cause, suggestions}.
## Original code (MIT-compatible); the pattern knowledge is generic public
## driver-error folklore (Vulkan spec result codes, Metal MTLCommandBufferError).

const RULES: Array[Dictionary] = [
	{
		"kind": "device_lost",
		"pattern": "VK_ERROR_DEVICE_LOST|DEVICE_LOST|device lost|VK_ERROR_SURFACE_LOST",
		"cause": "The GPU stopped responding (TDR/watchdog timeout, driver crash or an invalid GPU access).",
		"suggestions": ["Reduce per-frame GPU work (long compute/fragment shaders, huge dispatches).", "Update the GPU driver.", "Run with validation layers (--gpu-validation) to find invalid descriptors or out-of-bounds access."],
	},
	{
		"kind": "metal_error",
		"pattern": "MTLCommandBufferError|Metal.*(command buffer|error)|command buffer.*(failed|error)|kIOGPU",
		"cause": "A Metal command buffer failed: a GPU timeout, an access violation or an invalid pipeline/resource state.",
		"suggestions": ["Enable Metal API validation (MTL_DEBUG_LAYER=1).", "Split long-running GPU passes.", "Check for resources used after being freed or in the wrong state."],
	},
	{
		"kind": "out_of_memory",
		"pattern": "VK_ERROR_OUT_OF_DEVICE_MEMORY|VK_ERROR_OUT_OF_HOST_MEMORY|out of (video |device |host |gpu )?memory|OOM|Insufficient Memory|failed to allocate",
		"cause": "GPU or host memory was exhausted, usually by oversized textures, render targets or leaked resources.",
		"suggestions": ["Lower texture quality / shadow atlas / render target sizes.", "Enable VRAM compression for textures.", "Look for leaked RIDs or textures (see the GPU resource report)."],
	},
	{
		"kind": "shader_compile",
		"pattern": "shader compilation failed|failed to compile|SPIR-V|glslang|Error compiling (shader|pipeline)|Failed to create (graphics |compute )?pipeline|Parse Error.*shader|Shader.*error",
		"cause": "A shader or pipeline failed to compile or link, often due to a syntax error, an unsupported feature or driver limits.",
		"suggestions": ["Read the first shader error line for the offending source location.", "Check the feature is supported on the target GPU/renderer (Compatibility vs Forward+).", "Reduce uniform/varying counts or specialisation permutations."],
	},
	{
		"kind": "condition_true",
		"pattern": "Condition \".*\" is true",
		"cause": "An engine sanity check failed (an invalid argument or state), commonly caused by freed or null resources passed to the renderer.",
		"suggestions": ["Open the failing condition's source file named in the log line.", "Check the call stack for use of invalid RIDs, null textures or zero-sized buffers.", "Reproduce with a debug build for the full backtrace."],
	},
]

static var _regexes: Array[RegEx] = []


static func _compiled() -> Array[RegEx]:
	if _regexes.is_empty():
		for r in RULES:
			var re := RegEx.new()
			re.compile("(?i)" + str(r["pattern"]))
			_regexes.append(re)
	return _regexes


## Returns one report per distinct (kind, message) with an occurrence count.
static func parse(text: String) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var seen: Dictionary = {}
	var regexes: Array[RegEx] = _compiled()
	var lines: PackedStringArray = text.split("\n")
	for ln in lines.size():
		var line: String = lines[ln].strip_edges()
		if line.is_empty():
			continue
		for i in RULES.size():
			if regexes[i].search(line) == null:
				continue
			var rule: Dictionary = RULES[i]
			var kind: String = str(rule["kind"])
			var key: String = kind + "|" + line
			if seen.has(key):
				var existing: Dictionary = res[int(seen[key])]
				existing["count"] = int(existing["count"]) + 1
			else:
				seen[key] = res.size()
				res.append({
					"kind": kind, "message": line, "line": ln + 1, "count": 1,
					"likely_cause": str(rule["cause"]), "suggestions": rule["suggestions"].duplicate(),
				})
			break
	return res


static func parse_file(path: String) -> Array[Dictionary]:
	return parse(FileAccess.get_file_as_string(path))


## Counts per kind plus the most severe kind present.
static func summarize(reports: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for r in reports:
		var k: String = str(r["kind"])
		counts[k] = int(counts.get(k, 0)) + int(r["count"])
	var order: Array[String] = ["device_lost", "metal_error", "out_of_memory", "shader_compile", "condition_true"]
	var top: String = ""
	for k in order:
		if counts.has(k):
			top = k
			break
	return {"counts": counts, "primary_kind": top, "total": reports.size()}
