extends RefCounted
## Picks the best temporal upscaler for the current GPU: DLSS on NVIDIA RTX,
## XeSS on Intel Arc, MetalFX on Apple GPUs, FSR2 everywhere else.
##
## DLSS / XeSS exist only in engine builds compiled with `dlss_sdk_path` /
## `xess_sdk_path` (see modules/dlss/README.md, modules/xess/README.md). Every
## decision is guarded twice: the enum constant must exist in this engine
## build, and the module must have registered its project settings. Anything
## unavailable resolves to FSR2 (or MetalFX on macOS) with a reason string.

enum Vendor { OTHER, NVIDIA_RTX, NVIDIA_OTHER, INTEL_ARC, INTEL_OTHER, AMD, APPLE }

const MODE_DLSS := "SCALING_3D_MODE_DLSS"
const MODE_XESS := "SCALING_3D_MODE_XESS"
const MODE_FSR2 := "SCALING_3D_MODE_FSR2"
const MODE_METALFX := "SCALING_3D_MODE_METALFX_TEMPORAL"
const MODE_BILINEAR := "SCALING_3D_MODE_BILINEAR"

## Project settings that only exist when the matching module is compiled in.
const MODULE_MARKERS := {
	"dlss": "rendering/scaling_3d/dlss/application_id",
	"xess": "rendering/scaling_3d/xess/velocity_scale",
}


## Classifies a GPU from the strings RenderingServer reports.
static func classify_adapter(vendor: String, adapter_name: String) -> int:
	var v := vendor.to_lower()
	var n := adapter_name.to_lower()
	if v.contains("nvidia") or n.contains("nvidia") or n.contains("geforce"):
		# DLSS needs Tensor cores: RTX only. GTX 16xx / 10xx do not have them.
		return Vendor.NVIDIA_RTX if n.contains("rtx") else Vendor.NVIDIA_OTHER
	if v.contains("intel") or n.contains("intel"):
		return Vendor.INTEL_ARC if n.contains(" arc") or n.contains("arc(") or n.contains("arc ") else Vendor.INTEL_OTHER
	if v.contains("apple") or n.contains("apple"):
		return Vendor.APPLE
	if v.contains("amd") or v.contains("ati") or n.contains("radeon") or n.contains("amd"):
		return Vendor.AMD
	return Vendor.OTHER


## True when this engine build has the Viewport.Scaling3DMode constant.
static func has_mode(mode_name: String) -> bool:
	return ClassDB.class_has_integer_constant("Viewport", mode_name)


static func mode_value(mode_name: String, fallback: int = 0) -> int:
	if not has_mode(mode_name):
		return fallback
	return ClassDB.class_get_integer_constant("Viewport", mode_name)


## True when the optional engine module ("dlss" / "xess") is compiled in.
static func module_compiled(module_name: String) -> bool:
	var marker: String = MODULE_MARKERS.get(module_name, "")
	return marker != "" and ProjectSettings.has_setting(marker)


## Decides the mode. `modules` = {"dlss": bool, "xess": bool}; pass
## detect_modules() for the running engine. Returns {mode, mode_name, vendor,
## reason}; `reason` explains a fallback and is empty when the native
## vendor upscaler was chosen.
static func choose(vendor: int, os_name: String, rendering_method: String, driver: String, modules: Dictionary) -> Dictionary:
	var fsr2 := mode_value(MODE_FSR2, mode_value(MODE_BILINEAR))
	var out := {"mode": fsr2, "mode_name": MODE_FSR2, "vendor": vendor, "reason": ""}

	if rendering_method != "forward_plus":
		out["mode"] = mode_value(MODE_BILINEAR)
		out["mode_name"] = MODE_BILINEAR
		out["reason"] = "temporal upscalers need the Forward+ renderer"
		return out

	if vendor == Vendor.APPLE or os_name == "macOS" or os_name == "iOS":
		if has_mode(MODE_METALFX):
			out["mode"] = mode_value(MODE_METALFX)
			out["mode_name"] = MODE_METALFX
		else:
			out["reason"] = "MetalFX temporal is not in this engine build"
		return out

	var desktop := os_name == "Windows" or os_name == "Linux"
	if vendor == Vendor.NVIDIA_RTX:
		if not desktop or driver != "vulkan":
			out["reason"] = "DLSS needs Windows/Linux with the Vulkan driver"
		elif not has_mode(MODE_DLSS):
			out["reason"] = "this engine build has no SCALING_3D_MODE_DLSS"
		elif not modules.get("dlss", false):
			out["reason"] = "engine built without dlss_sdk_path (DLSS module absent)"
		else:
			out["mode"] = mode_value(MODE_DLSS)
			out["mode_name"] = MODE_DLSS
		return out

	if vendor == Vendor.INTEL_ARC:
		if not desktop or driver != "vulkan":
			out["reason"] = "XeSS needs Windows/Linux with the Vulkan driver"
		elif not has_mode(MODE_XESS):
			out["reason"] = "this engine build has no SCALING_3D_MODE_XESS"
		elif not modules.get("xess", false):
			out["reason"] = "engine built without xess_sdk_path (XeSS module absent)"
		else:
			out["mode"] = mode_value(MODE_XESS)
			out["mode_name"] = MODE_XESS
		return out

	return out


static func detect_modules() -> Dictionary:
	return {"dlss": module_compiled("dlss"), "xess": module_compiled("xess")}


## Chooses for the machine the game is running on.
static func detect() -> Dictionary:
	var vendor := classify_adapter(RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name())
	var method := str(RenderingServer.get_current_rendering_method())
	var driver := str(RenderingServer.get_current_rendering_driver_name())
	return choose(vendor, OS.get_name(), method, driver, detect_modules())


## Applies a decision from choose()/detect() to a viewport. Returns the mode used.
static func apply(viewport: Viewport, decision: Dictionary, scale: float) -> int:
	var mode: int = decision.get("mode", mode_value(MODE_FSR2))
	viewport.scaling_3d_mode = mode as Viewport.Scaling3DMode
	viewport.scaling_3d_scale = clampf(scale, 0.33, 1.0)
	return mode
