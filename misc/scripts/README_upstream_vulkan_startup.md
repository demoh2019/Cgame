# Upstream Godot 4.x backports: Vulkan cache and failed-display startup

These backports were reviewed against the current `develop` code and the corresponding official Godot pull requests on November 19, 2026. The upstream PRs were still open when ported, so this is a **local backport**, not a claim of upstream acceptance.

- [godotengine/godot#125598](https://github.com/godotengine/godot/pull/125598) — after `vkGetPipelineCacheData()` returns, resize the serialized cache buffer to the actual reported payload length plus the engine header. This avoids stale trailing bytes when a Vulkan driver returns less data than the original query size. `VK_INCOMPLETE` remains a supported result.
- [godotengine/godot#125620](https://github.com/godotengine/godot/pull/125620) — when every requested display backend fails during `Main::setup2`, use `finalize_display()` and finalize the 2D/3D navigation server managers **before** GDExtension/server module teardown. Retain compile-time feature guards and existing physics cleanup.

## Regression verification

```bash
python3 -m unittest discover -s misc/scripts/tests -p 'test_upstream_vulkan_startup.py' -v
```

The test suite extracts the **actual current C++ methods** from the repository, compiles them against deterministic C++ test doubles, and exercises successful, empty, shortened, incomplete and failed Vulkan cache data reads as well as display failure handling with and without navigation servers. It also checks the relative order of resource cleanup and the presence of build guards. These harnesses are narrow unit regressions, **not a complete Vulkan, editor, headless, macOS or Windows engine build**; engine CI and device-level validation are still required before a release. In CI, this standalone suite runs on Linux and macOS using system C++ compilers.

Porting is credited to the upstream contributors in the linked PRs. Preserve the upstream MIT license and review subsequent upstream changes before carrying further patches.
