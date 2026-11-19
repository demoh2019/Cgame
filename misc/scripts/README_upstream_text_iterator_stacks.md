# Text shaping: preserve stack contents when growing (upstream #125526)

Backport of [Godot PR #125526](https://github.com/godotengine/godot/pull/125526).

The advanced text server's `ScriptIterator` maintains small inline stacks for
emoji subruns and bidirectional paired brackets. When either stack exceeds its
inline capacity, the iterator previously allocated heap storage **without
copying existing entries**. Deeply nested scripts or complex emoji sequences
could therefore read uninitialized state and produce incorrect shaping.

This patch copies the original `EMOJI_STACK_DEPTH` / `PAREN_STACK_DEPTH`
inline entries to newly allocated storage. Later growth retains `memrealloc`.
All existing iteration and cleanup logic is preserved.

## Verification

Run focused checks:

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_text_iterator_stacks.py -v
```

The 23 structural regressions verify both allocation/copy branches, branch order,
copy lengths, later realloc paths, stack updates, cleanup, and paired-bracket
handling. CI runs them on Python 3.9 and 3.13 and builds/runs the Linux editor
native test target. These tests cannot independently prove absence of
out-of-bounds reads in real shaping; an ICU/HarfBuzz-enabled ASan run with long
emoji/RTL and nested bracket input is recommended before release.

No user project files are modified by this backport.
