extends Node
## Runtime convolution reverb: dry samples go in, reverbed audio is rendered into an
## AudioStreamGenerator each frame through PartitionedConvolver with a wet/dry mix.
## CPU is bounded by `budget_us` microseconds of block processing per frame.

const PartitionedConvolver = preload("res://scripts/client/partitioned_convolver.gd")

@export var mix_rate: float = 24000.0
@export var block_size: int = 256
@export_range(0.0, 1.0) var wet: float = 0.35
@export var budget_us: int = 3000
@export var max_queue_samples: int = 96000

var player: AudioStreamPlayer = null
var convolver: RefCounted = PartitionedConvolver.new()
var _dry: PackedFloat32Array = PackedFloat32Array()
var _playback: AudioStreamGeneratorPlayback = null
var _has_ir: bool = false
var _tail_blocks_left: int = 0
var blocks_rendered: int = 0


func _ready() -> void:
	player = AudioStreamPlayer.new()
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = mix_rate
	gen.buffer_length = 0.2
	player.stream = gen
	add_child(player)
	player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


func set_ir(ir: PackedFloat32Array) -> void:
	convolver.setup(ir, block_size)
	_has_ir = not ir.is_empty()
	_tail_blocks_left = 0


func push_dry(samples: PackedFloat32Array) -> void:
	_dry.append_array(samples)
	if _dry.size() > max_queue_samples:
		_dry = _dry.slice(_dry.size() - max_queue_samples)
	_tail_blocks_left = int(convolver.partition_count()) + 1


func queued_samples() -> int:
	return _dry.size()


## Renders one block (wet/dry mixed). Missing dry input is treated as silence while the
## reverb tail rings out. Returns an empty array when idle (no input, no tail).
func render_block() -> PackedFloat32Array:
	var b: int = int(convolver.block_size)
	var out: PackedFloat32Array = PackedFloat32Array()
	if b == 0 or (_dry.is_empty() and _tail_blocks_left <= 0):
		return out
	var block: PackedFloat32Array = PackedFloat32Array()
	block.resize(b)
	var take: int = mini(b, _dry.size())
	for i in take:
		block[i] = _dry[i]
	if take > 0:
		_dry = _dry.slice(take)
	if take < b or _dry.is_empty():
		_tail_blocks_left -= 1
	else:
		_tail_blocks_left = int(convolver.partition_count()) + 1
	var verb: PackedFloat32Array = block if not _has_ir else convolver.process(block)
	out.resize(b)
	for i in b:
		out[i] = block[i] * (1.0 - wet) + verb[i] * wet
	blocks_rendered += 1
	return out


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var start: int = Time.get_ticks_usec()
	var b: int = int(convolver.block_size)
	while b > 0 and _playback.get_frames_available() >= b:
		if Time.get_ticks_usec() - start > budget_us:
			break
		var out: PackedFloat32Array = render_block()
		if out.is_empty():
			break
		var frames: PackedVector2Array = PackedVector2Array()
		frames.resize(out.size())
		for i in out.size():
			frames[i] = Vector2(out[i], out[i])
		_playback.push_buffer(frames)
