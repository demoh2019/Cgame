# XeSS module (optional, Intel XeSS SDK)

Adds Intel XeSS temporal upscaling as `Viewport.SCALING_3D_MODE_XESS`
(`RenderingServer.VIEWPORT_SCALING_3D_MODE_XESS`, project setting
`rendering/scaling_3d/mode` = `Intel XeSS`).

**This repository does not contain any Intel code, headers or binaries.**
The module is compiled only when you pass `xess_sdk_path=...` to SCons. Without
it, `can_build` returns `false`, nothing from Intel is needed, and selecting
`SCALING_3D_MODE_XESS` at runtime prints a warning and falls back to FSR 2.

## License obligations

The XeSS SDK (<https://github.com/intel/xess>) is distributed by Intel under
its own license (Intel Simplified Software License, see the `LICENSE` file in
the SDK release). You must download the SDK yourself, accept that license,
keep the SDK out of this repository, and follow Intel's redistribution terms
when shipping `libxess` with a game. You are responsible for checking that your
use complies with that license.

## Supported platforms

| Platform | Renderer / driver | Status |
| --- | --- | --- |
| Windows | Forward+ on Vulkan | implemented, untested |
| Linux | Forward+ on Vulkan | implemented, untested |
| Windows | Forward+ on Direct3D 12 | not implemented (falls back to FSR 2) |
| macOS / iOS / Android / Web | any | not supported (use MetalFX / FSR 2) |

Hardware: best on Intel Arc (XMX path). XeSS also has a DP4a fallback for other
GPUs that support it. The Mobile and Compatibility renderers are not supported.

## Building

1. Download and extract the XeSS SDK. The folder you pass must contain
   `inc/xess/xess.h`, `inc/xess/xess_vk.h` and the library in `lib/`
   (`libxess.lib` + `libxess.dll` on Windows, `libxess.so` on Linux).
2. Build:

   ```
   scons platform=windows target=editor vulkan=yes xess_sdk_path=C:/sdks/xess
   scons platform=linuxbsd target=template_release vulkan=yes xess_sdk_path=/opt/xess
   ```

3. Copy `libxess.dll` / `libxess.so` next to the Godot executable.

## Usage

```gdscript
get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_XESS
get_viewport().scaling_3d_scale = 0.59   # Balanced. 1.0 = XeSS-AA, 0.33 = Ultra Performance
```

The XeSS quality preset is picked from the render scale. 3D MSAA is disabled
internally and TAA is replaced by XeSS, like for FSR 2.

## How it works

The module registers a `RendererRD::VendorUpscaler`
(`servers/rendering/renderer_rd/effects/vendor_upscaler.h`). `create_context`
calls `xessVKCreateContext` and `xessVKInit` (reverse-Z, auto exposure);
`upscale` queues a driver callback via `RenderingDevice::driver_callback_add`
that calls `xessVKExecute` on the current Vulkan command buffer with the color,
depth, velocity and output image views.

## Known limitations (read before relying on this)

- The code was written from the public XeSS Vulkan API and has **not been
  compiled or run** against the SDK or on Intel/other hardware.
- The Vulkan device must enable the extensions XeSS requires
  (`xessGetRequiredInstanceExtensions` / `xessGetRequiredDeviceExtensions`);
  the Godot Vulkan driver does not request them yet. If the context cannot be
  created the module reports itself unsupported and the engine falls back to
  FSR 2 with a warning.
- Motion vector scale/sign is exposed as the project setting
  `rendering/scaling_3d/xess/velocity_scale` and must be confirmed on hardware.
