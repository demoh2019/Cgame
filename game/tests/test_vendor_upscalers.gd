extends RefCounted
## DLSS / XeSS / MetalFX / FSR2 vendor selection. No GPU or vendor SDK needed.
const Vendors = preload("res://scripts/client/graphics_vendor_upscalers.gd")

const BOTH := {"dlss": true, "xess": true}
const NONE := {"dlss": false, "xess": false}


func run(t) -> void:
	t.current = "adapter classification"
	t.eq(Vendors.classify_adapter("NVIDIA", "NVIDIA GeForce RTX 4070"), Vendors.Vendor.NVIDIA_RTX, "RTX")
	t.eq(Vendors.classify_adapter("NVIDIA", "NVIDIA GeForce GTX 1660"), Vendors.Vendor.NVIDIA_OTHER, "GTX has no tensor cores")
	t.eq(Vendors.classify_adapter("Intel", "Intel(R) Arc(TM) A770 Graphics"), Vendors.Vendor.INTEL_ARC, "Arc")
	t.eq(Vendors.classify_adapter("Intel", "Intel(R) UHD Graphics 770"), Vendors.Vendor.INTEL_OTHER, "iGPU is not Arc")
	t.eq(Vendors.classify_adapter("AMD", "AMD Radeon RX 7800 XT"), Vendors.Vendor.AMD, "AMD")
	t.eq(Vendors.classify_adapter("Apple", "Apple M3 Pro"), Vendors.Vendor.APPLE, "Apple")
	t.eq(Vendors.classify_adapter("", ""), Vendors.Vendor.OTHER, "unknown")

	var fsr2 := Vendors.mode_value(Vendors.MODE_FSR2, -1)
	t.check(fsr2 >= 0, "FSR2 exists in this engine")

	t.current = "engine build exposes the new enum values"
	t.check(Vendors.has_mode(Vendors.MODE_DLSS), "Viewport.SCALING_3D_MODE_DLSS registered")
	t.check(Vendors.has_mode(Vendors.MODE_XESS), "Viewport.SCALING_3D_MODE_XESS registered")
	t.check(Vendors.mode_value(Vendors.MODE_DLSS) != Vendors.mode_value(Vendors.MODE_XESS), "distinct values")
	t.check(Vendors.mode_value(Vendors.MODE_DLSS) != fsr2 and Vendors.mode_value(Vendors.MODE_XESS) != fsr2,
		"new values do not alias FSR2")
	t.check(Vendors.has_mode("SCALING_3D_MODE_DOES_NOT_EXIST") == false, "unknown constant is rejected")

	t.current = "NVIDIA RTX picks DLSS only when compiled in"
	var d: Dictionary = Vendors.choose(Vendors.Vendor.NVIDIA_RTX, "Windows", "forward_plus", "vulkan", BOTH)
	t.eq(d["mode"], Vendors.mode_value(Vendors.MODE_DLSS), "DLSS on RTX")
	t.eq(d["reason"], "", "no fallback reason")
	d = Vendors.choose(Vendors.Vendor.NVIDIA_RTX, "Linux", "forward_plus", "vulkan", NONE)
	t.eq(d["mode"], fsr2, "no module falls back to FSR2")
	t.check(str(d["reason"]).contains("dlss_sdk_path"), "reason names the build flag")
	d = Vendors.choose(Vendors.Vendor.NVIDIA_RTX, "Windows", "forward_plus", "d3d12", BOTH)
	t.eq(d["mode"], fsr2, "D3D12 is not supported yet")
	d = Vendors.choose(Vendors.Vendor.NVIDIA_OTHER, "Windows", "forward_plus", "vulkan", BOTH)
	t.eq(d["mode"], fsr2, "GTX uses FSR2")

	t.current = "Intel Arc picks XeSS only when compiled in"
	d = Vendors.choose(Vendors.Vendor.INTEL_ARC, "Windows", "forward_plus", "vulkan", BOTH)
	t.eq(d["mode"], Vendors.mode_value(Vendors.MODE_XESS), "XeSS on Arc")
	d = Vendors.choose(Vendors.Vendor.INTEL_ARC, "Linux", "forward_plus", "vulkan", {"dlss": true, "xess": false})
	t.eq(d["mode"], fsr2, "no XeSS module falls back to FSR2")
	t.check(str(d["reason"]).contains("xess_sdk_path"), "reason names the build flag")
	d = Vendors.choose(Vendors.Vendor.INTEL_OTHER, "Windows", "forward_plus", "vulkan", BOTH)
	t.eq(d["mode"], fsr2, "integrated Intel uses FSR2")

	t.current = "AMD, Apple and non Forward+ renderers"
	d = Vendors.choose(Vendors.Vendor.AMD, "Windows", "forward_plus", "vulkan", BOTH)
	t.eq(d["mode"], fsr2, "AMD uses FSR2")
	d = Vendors.choose(Vendors.Vendor.APPLE, "macOS", "forward_plus", "metal", NONE)
	t.eq(d["mode"], Vendors.mode_value(Vendors.MODE_METALFX), "Apple uses MetalFX temporal")
	d = Vendors.choose(Vendors.Vendor.NVIDIA_RTX, "Windows", "mobile", "vulkan", BOTH)
	t.eq(d["mode"], Vendors.mode_value(Vendors.MODE_BILINEAR), "Mobile renderer has no temporal upscalers")
	t.check(str(d["reason"]) != "", "reason given for non Forward+")

	t.current = "running engine"
	var modules: Dictionary = Vendors.detect_modules()
	t.check(modules.has("dlss") and modules.has("xess"), "module probe returns both keys")
	# The default build has no SDK modules, so the probes must be false and the fallback FSR2.
	t.eq(modules["dlss"], false, "default build has no DLSS module")
	t.eq(modules["xess"], false, "default build has no XeSS module")
