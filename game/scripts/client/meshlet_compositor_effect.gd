extends CompositorEffect
## Thin CompositorEffect that hands the render thread callback to a MeshletRenderer
## (scripts/client/meshlet_renderer.gd), which records the task + mesh draw. The renderer is
## assigned by MeshletRenderer.create_compositor_effect(). UNVERIFIED on mesh shader hardware.

const MeshletRenderer = preload("res://scripts/client/meshlet_renderer.gd")

var renderer: MeshletRenderer = null


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if renderer != null:
		renderer.record_draw(render_data)
