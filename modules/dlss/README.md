# DLSS module (optional, NVIDIA Streamline)

Adds NVIDIA DLSS temporal upscaling as `Viewport.SCALING_3D_MODE_DLSS`
(`RenderingServer.VIEWPORT_SCALING_3D_MODE_DLSS`, project setting
`rendering/scaling_3d/mode` = `NVIDIA DLSS`).

**This repository does not contain any NVIDIA code, headers or binaries.**
The module is compiled only when you pass `dlss_sdk_path=...` to SCons. Without
it, `can_build` returns `false`, nothing from NVIDIA is needed, and selecting
`SCALING_3D_MODE_DLSS` at runtime prints a warning and falls back to FSR 2.

## License obligations

The NVIDIA Streamline SDK and the DLSS runtime (`nvngx_dlss`) are proprietary
and are distributed under the NVIDIA RTX SDK License Agreement. You must:

- download the SDK yourself from <https://github.com/NVIDIAGameWorks/Streamline>
  and accept its license before using it;
- keep the SDK out of this repository and out of any public fork;
- follow NVIDIA's redistribution terms (including the required attribution /
  logo usage and the application id registration) when shipping a game with
  the Streamline DLLs and `nvngx_dlss` next to your executable.

You are responsible for checking that your use complies with that license.

## Supported platforms

| Platform | Renderer / driver | Status |
| --- | --- | --- |
| Windows | Forward+ on Vulkan | implemented, untested |
| Linux | Forward+ on Vulkan | implemented, untested |
| Windows | Forward+ on Direct3D 12 | not implemented (falls back to FSR 2) |
| macOS / iOS / Android / Web | any | not supported (use MetalFX / FSR 2) |

Hardware: NVIDIA RTX (Turing or newer) GPU with a current driver.
The Mobile and Compatibility renderers are not supported.

## Building

1. Download and extract the Streamline SDK. The folder you pass must contain
   `include/sl.h`, `include/sl_dlss.h`, `lib/x64/sl.interposer.lib` (Windows) or
   `bin/x64/libsl.interposer.so` (Linux).
2. Build the editor or export templates with the SDK path:

   ```
   scons platform=windows target=editor vulkan=yes dlss_sdk_path=C:/sdks/Streamline
   scons platform=linuxbsd target=template_release vulkan=yes dlss_sdk_path=/opt/Streamline
   ```

3. Copy the Streamline runtime plugins from the SDK (`bin/x64/sl.interposer`,
   `sl.common`, `sl.dlss`, and `nvngx_dlss` from the SDK's `bin/x64` folder)
   next to the Godot executable.
4. Optional: set `rendering/scaling_3d/dlss/application_id` to the id NVIDIA
   assigned to your application.

## Usage

```gdscript
get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_DLSS
get_viewport().scaling_3d_scale = 0.667   # Quality. 1.0 = DLAA, 0.33 = Ultra Performance
```

The DLSS mode is picked from the render scale (DLAA, Quality, Balanced,
Performance, Ultra Performance). 3D MSAA is disabled internally and TAA is
replaced by DLSS, like for FSR 2.

## How it works

The engine side is the generic `RendererRD::VendorUpscaler` interface in
`servers/rendering/renderer_rd/effects/vendor_upscaler.h`, used by
`RenderForwardClustered` exactly where FSR 2 / MetalFX Temporal run. This module
registers a `VendorUpscaler` that, through `RenderingDevice::driver_callback_add`,
tags color, depth, motion vectors, exposure and output with `slSetTagForFrame`,
sets `sl::Constants` and `slDLSSSetOptions`, and calls `slEvaluateFeature` on the
current Vulkan command buffer.

## Known limitations (read before relying on this)

- The code was written from the public Streamline programming guide and has
  **not been compiled or run** against the SDK or on an NVIDIA GPU. Expect
  small API adjustments depending on the SDK version.
- Streamline normally proxies the Vulkan loader. Godot loads Vulkan itself, so
  the module uses `eUseManualHooking`. The Vulkan device must be created with
  the instance/device extensions and features that `slGetFeatureRequirements`
  reports for DLSS; the Godot Vulkan driver does not request them yet. If
  `slIsFeatureSupported` fails, DLSS reports itself unsupported and the engine
  falls back to FSR 2 with a warning. Adding the extension plumbing to
  `drivers/vulkan` is the main remaining engineering task.
- Matrix conventions (row-major, reverse-Z, UV-space motion vectors with
  `mvecScale = 1`) need verification on hardware.
