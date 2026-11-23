extends RefCounted
## HDR10 / EDR display output (UE5 r.HDR.EnableHDROutput, Unity HDR Output).
## Uses the engine's native DisplayServer HDR swapchain when the monitor
## reports support; SDR screens and low presets keep the 8-bit path.

const PAPER_WHITE_NITS := 200.0


static func wanted(level: int, rendering_method: String, supported: bool) -> bool:
	return supported and rendering_method != "gl_compatibility" and clampi(level, 0, 3) >= 2


static func supported() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not DisplayServer.has_method("window_is_hdr_output_supported"):
		return false
	return bool(DisplayServer.call("window_is_hdr_output_supported"))


## On macOS the display brightness setting owns the reference-white luminance.
static func can_set_reference_luminance(platform: String) -> bool:
	return platform != "macOS"


static func apply(level: int, rendering_method: String) -> bool:
	if not DisplayServer.has_method("window_request_hdr_output"):
		return false
	var on: bool = wanted(level, rendering_method, supported())
	DisplayServer.call("window_request_hdr_output", on)
	if on and can_set_reference_luminance(OS.get_name()) and DisplayServer.has_method("window_set_hdr_output_reference_luminance"):
		# UI and diffuse white stay comfortable; highlights (sun, fire, lightning) use the headroom.
		DisplayServer.call("window_set_hdr_output_reference_luminance", PAPER_WHITE_NITS)
	return on
