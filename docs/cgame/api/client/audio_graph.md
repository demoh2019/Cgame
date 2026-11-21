# audio_graph.gd

> MetaSounds-style procedural audio graph: node-based DSP rendered block-wise into sample buffers / AudioStreamWAV.

`res://scripts/client/audio_graph.gd`

## Overview

```text
MetaSounds-style procedural audio graph: node-based DSP rendered block-wise into
sample buffers / AudioStreamWAV.

Graph asset:
  {"nodes": {id: {"type": ..., param: value, ...}},
   "connections": [[from_id, to_id, input_name], ...],
   "output": id}
A connection to input "X" replaces the constant param X with the source signal;
a connection to "X_mod" is added to it (e.g. envelope -> "cutoff_mod").
Several connections to the same input are summed.

Node types and params (defaults in DEFAULTS):
  sine saw square triangle : freq amp phase pw          (saw/square use polyBLEP)
  noise_white noise_pink noise_brown : amp
  const : value
  adsr : start gate attack decay sustain release         (linear segments)
  ar   : start attack release
  lowpass highpass bandpass : in cutoff q                (RBJ biquad)
  smooth : in time                                       (one-pole)
  delay : in time feedback                               (wet signal; may close a loop)
  gain : in gain      mixer : in (sum) gain      multiply : a b (ring / AM)
  clip : in drive     (tanh soft clip; alias "distortion")
  random_pitch : min max rate   (log-uniform sample&hold in Hz, new value each 1/rate s)
  random_trigger : rate decay min_amp   (Poisson triggers, exponentially decaying bursts)

Cycles are rejected unless they pass through a delay node (delay time is clamped to at
least one processing block, so a delay output never depends on the current block).

Ported / referenced sources (all algorithms re-implemented here, no code copied):
 - Biquad coefficients: "Audio EQ Cookbook" by Robert Bristow-Johnson,
   https://www.w3.org/TR/audio-eq-cookbook/ (published freely; W3C Note, public use of formulas).
 - polyBLEP band-limited step correction: Valimaki & Huovilainen, "Antialiasing Oscillators
   in Subtractive Synthesis", IEEE Signal Processing Magazine 2007 (published technique, formula only).
 - Pink noise: Voss-McCartney multi-row algorithm (Gardner 1978 / musicdsp.org description), own implementation.
 - Block-based dataflow evaluation, topological order and per-node profiling follow the
   general design of Unreal Engine MetaSounds (concept only; no Unreal code used).
No GPL/LGPL code and no Apache-2.0 code is included.
```

## Constants

- `const BLOCK := 64`
- `const MAX_NODE_COUNT := 256`
- `const DEFAULTS := {`

## Classes

- `class _N extends RefCounted:`

## Documented variables

- `static var last_profile: Dictionary = {}` - Filled by every render: node id -> {"type", "usec", "calls", "pct"}; see profile_report().

## Functions

### `validate`

```gdscript
static func validate(graph: Dictionary) -> Array[String]
```

Returns a list of human readable problems; empty means the graph can be rendered.

### `render`

```gdscript
static func render(graph: Dictionary, seconds: float, sample_rate: int = 22050, seed: int = 0) -> PackedFloat32Array
```

Renders `seconds` of audio; returns an empty array and fills last_errors when invalid.

### `profile_report`

```gdscript
static func profile_report() -> Array[Dictionary]
```

Profiler view: rows sorted by cost, most expensive first.

### `to_wav`

```gdscript
static func to_wav(samples: PackedFloat32Array, sample_rate: int = 22050) -> AudioStreamWAV
```

_11 private function(s) starting with `_` are not listed._
