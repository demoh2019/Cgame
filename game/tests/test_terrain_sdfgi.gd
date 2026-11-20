extends RefCounted
## The custom RID-backed terrain must contribute static geometry to Ultra GI.
## The game remains compatible with non-GI graphics tiers and fallbacks.

const Indirect = preload("res://scripts/client/graphics_indirect_lighting.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")

func run(t) -> void:
	t.current = "streamed terrain contributes to Ultra SDFGI"
	var terrain := ChunkedTerrain3D.new()
	t.check(not terrain.contribute_to_gi,
		"new native terrain preserves non-GI default")
	terrain.contribute_to_gi = true
	t.check(terrain.is_contributing_to_gi(),
		"native terrain can opt into static GI without shadow-map changes")
	terrain.contribute_to_gi = false
	t.check(not terrain.is_contributing_to_gi(),
		"runtime quality changes can disable GI participation")
	var source: String = (ChunkView as Script).source_code
	t.check(source.contains("_terrain.contribute_to_gi = true"),
		"the actual game turns on GI contribution for its streamed heightfields")
	t.check(Indirect.settings(3, "forward_plus")["sdfgi_enabled"],
		"Ultra can receive heightfield-bounced light")
	t.check(not Indirect.settings(2, "forward_plus")["sdfgi_enabled"],
		"High never allocates SDFGI")
	t.check(not Indirect.settings(3, "gl_compatibility")["sdfgi_enabled"],
		"Compatibility never allocates SDFGI")
	var config: String = FileAccess.get_file_as_string("res://project.godot")
	t.check(config.contains("global_illumination/gi/use_half_resolution=true"),
		"GI buffers run at half resolution to contain GPU bandwidth")
