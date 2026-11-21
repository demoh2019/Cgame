extends RefCounted
## Portable Cgame RNG substreams: one seed and numeric stream id produce an
## independent PCG stream without drawing from or changing the parent RNG.
## Cgame implements get_substream_seed()/fork() natively; official Godot
## follows exactly the same 32-bit unsigned mixing using 64-bit GDScript ints.

const WORD_MASK := 0xffffffff
const FNV_PRIME := 16777619
const AVALANCHE := 0x045d9f3b


## The native seed mixer hashes all 64 bits of both the parent seed and the
## substream tag. Mask after each product to emulate uint32_t arithmetic.
static func _word(seed: int, stream_id: int, salt: int) -> int:
	var h: int = (2166136261 ^ salt) & WORD_MASK
	for shift in [0, 16, 32, 48]:
		h = ((h ^ ((seed >> shift) & 0xffff)) * FNV_PRIME) & WORD_MASK
	for shift in [0, 16, 32, 48]:
		h = ((h ^ ((stream_id >> shift) & 0xffff)) * FNV_PRIME) & WORD_MASK
	h = ((h ^ (h >> 16)) * AVALANCHE) & WORD_MASK
	h = ((h ^ (h >> 16)) * AVALANCHE) & WORD_MASK
	return h ^ (h >> 16)


## Returns the exact seed computed by Cgame RNG.get_substream_seed().
## Treat this mixer as a versioned serialization algorithm: changing it
## would change all resulting birds, decoration and future procedural jobs.
static func seed_for(seed: int, stream_id: int) -> int:
	var hi: int = _word(seed, stream_id, 0x9e3779b9)
	var lo: int = _word(seed, stream_id, 0x85ebca6b)
	return (hi << 32) | lo


static func fork(parent: RandomNumberGenerator, stream_id: int) -> RandomNumberGenerator:
	if parent == null:
		return null
	if parent.has_method("fork"):
		return parent.call("fork", stream_id) as RandomNumberGenerator
	var child := RandomNumberGenerator.new()
	child.seed = seed_for(parent.seed, stream_id)
	return child
