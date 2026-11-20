extends RefCounted
## Cheap, scene-wide spectral solar tint. The native sky model supplies a
## single transmittance RGB sample at 5 Hz; existing sun lighting, terrain,
## foliage, water and atmosphere all receive the same directional light.
const SAMPLE_INTERVAL := 0.20


static func valid(sample: Color) -> bool:
	return is_finite(sample.r) and is_finite(sample.g) and is_finite(sample.b) \
		and sample.r > 0.0 and sample.g > 0.0 and sample.b > 0.0 \
		and sample.r <= 1.0001 and sample.g <= 1.0001 and sample.b <= 1.0001


## Mix normalized optical transmittance into the current art-directed tint.
## The midday optical sample is white, so existing exposure remains stable.
static func tint(artist: Color, optical: Color, strength: float) -> Color:
	if not valid(optical) or not is_finite(strength):
		return artist
	var amount: float = clampf(strength, 0.0, 1.0)
	return Color(lerpf(artist.r, optical.r, amount),
		lerpf(artist.g, optical.g, amount),
		lerpf(artist.b, optical.b, amount), artist.a)


static func supported(strength: float, rendering_method: String) -> bool:
	return is_finite(strength) and strength > 0.001 and rendering_method == "forward_plus"
