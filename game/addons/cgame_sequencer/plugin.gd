@tool
extends EditorPlugin
## Adds a "Sequencer" bottom panel hosting sequencer_panel.gd.
## Note: in the editor the panel can only call the runtime sequence/player
## scripts if they are marked @tool (a warning is pushed otherwise).

const SequencerPanel = preload("res://addons/cgame_sequencer/sequencer_panel.gd")
const CinematicSequence = preload("res://scripts/client/cinematic_sequence.gd")

var _panel: Control = null


func _enter_tree() -> void:
	_panel = SequencerPanel.new()
	_panel.custom_minimum_size = Vector2(0, 260)
	add_control_to_bottom_panel(_panel, "Sequencer")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
