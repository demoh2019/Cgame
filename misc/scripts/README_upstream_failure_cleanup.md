# Upstream failure-path cleanup backports (2026-11-19)

This Cgame change selectively ports two small fixes from the open upstream
[Godot pull requests](https://github.com/godotengine/godot/pulls):

- [#125620](https://github.com/godotengine/godot/pull/125620): on a failed
  `Main::setup2` DisplayServer creation, call the shared `finalize_display()`
  teardown and release the 2D/3D navigation server managers before deinitializing
  GDExtensions, module servers and physics server managers.
- [#125615](https://github.com/godotengine/godot/pull/125615): attempt all
  remaining OpenXR spatial-container teardown operations even when
  `OpenXRAPI` is already unavailable or the runtime returns a failure. Log
  the OpenXR error, clear handles and render-set state, and free the owned RID.

Both patches preserve the surrounding engine APIs, use the upstream's
compile-time feature guards, and do not introduce new user-facing settings.

## Regression checks

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_upstream_failure_cleanup.py' -v
```

The 16 source-contract tests check startup error-path ordering, conditional
navigation cleanup, preservation of existing server/physics cleanup, and XR
teardown state clearing in success and error branches. The dedicated CI
workflow runs them with Python 3.10 and 3.13 on Linux.

**Scope of verification:** these tests validate source control-flow invariants,
not actual platform startup or XR hardware. A complete Godot build,
Windows/macOS startup test and OpenXR runtime integration test remain necessary
before considering the backports fully validated on every platform. In
particular, the tests do not simulate a real failure of `xrDestroySpatialContainerEXT`
or `xrEndSpatialContainerRenderingEXT`.

The fixes are cherry-picked as code, not a bulk merge of open upstream PRs.
Engine upgrades should reconcile future changes from those upstream PRs rather
than applying them twice.
