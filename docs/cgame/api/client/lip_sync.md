# lip_sync.gd

> Automatic lip sync: rule-based grapheme-to-phoneme (English + Cyrillic transliteration), phoneme -> 9-shape viseme mapping, coarticulated viseme timeline and...

`res://scripts/client/lip_sync.gd`

## Overview

```text
Automatic lip sync: rule-based grapheme-to-phoneme (English + Cyrillic transliteration),
phoneme -> 9-shape viseme mapping, coarticulated viseme timeline and audio refinement.

Concepts ported (clean-room GDScript, no code copied) from:
 - Rhubarb Lip Sync by Daniel Wolf, MIT License, https://github.com/DanielSWolf/rhubarb-lip-sync
   (mouth shapes A-H + X: A closed P/B/M, B slight open K/S/T/EE, C open EH/AE, D wide AA,
   E rounded AO/ER, F puckered UW/OW/W, G F/V teeth-on-lip, H L tongue-up, X rest;
   short mouth shapes are dropped/merged, silence -> X).
 - Preston Blair phoneme set (public animation convention) and Oculus OVRLipSync viseme
   groupings (PP FF TH DD kk CH SS nn RR aa E ih oh ou), reduced here to the 9 shapes.
Pure-GDScript, deterministic, no dictionaries.
```

## Constants

- `const REST := "X"`
- `const OPEN_VISEMES := ["C", "D", "E"]`
- `const SILENCE_LEVEL := 0.1`
- `const TRANSITION := 0.07`
- `const MIN_KEY_GAP := 0.03`
- `const EN_RULES := [`
- `const EN_LETTERS := {`
- `const RU_LETTERS := {`
- `const VOWELS := ["aa", "ae", "ah", "ao", "eh", "er", "ih", "iy", "uh", "uw", "ow", "aw", "ay", "ey", "oy"]`
- `const VISEME_OF := {`

## Functions

### `phonemes_from_text`

```gdscript
static func phonemes_from_text(text: String, language := "en") -> PackedStringArray
```

### `viseme_for`

```gdscript
static func viseme_for(phoneme: String) -> String
```

### `timeline`

```gdscript
static func timeline(text: String, duration_seconds: float, language := "en") -> Array
```

### `amplitude_track`

```gdscript
static func amplitude_track(samples: PackedFloat32Array, sample_rate: int, hop_seconds := 0.02) -> PackedFloat32Array
```

### `refine_with_audio`

```gdscript
static func refine_with_audio(tl: Array, envelope: PackedFloat32Array, hop: float) -> Array
```

### `sample`

```gdscript
static func sample(tl: Array, t: float) -> Dictionary
```

_7 private function(s) starting with `_` are not listed._
