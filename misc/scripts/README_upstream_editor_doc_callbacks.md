# Deferred documentation callback safety — upstream #123658

Port of [godotengine/godot#123658](https://github.com/godotengine/godot/pull/123658).

Godot's editor generates documentation and reloads caches in background threads.
It previously queued static callbacks that could still be invoked after the
editor freed its documentation data on shutdown. This backport binds the five
affected deferred calls to a lightweight `EditorHelpDocOwner` Object. It is
created before jobs start and destroyed after waiting for worker threads, but
before freeing documentation caches. Godot invalidates queued Object-bound
callables when that owner is destroyed.

Public documentation APIs and data formats remain unchanged.

## Verification

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_editor_doc_callbacks.py -v
```

The 20 source contracts protect the lifecycle, all five callback sites,
null-initialization, cache corruption recovery, and cleanup ordering. The
workflow also compiles a native Linux editor with tests and runs headless
unit tests.

**Limits:** Source checks and headless tests do not force the precise race between
worker completion, pending deferred callback dispatch, and editor shutdown.
Exercise repeated editor startup/shutdown, interrupted documentation generation
and corrupted caches in a GUI build under sanitizers before shipping.
