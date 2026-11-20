/**************************************************************************/
/*  sky_scattering_lut.cpp                                                */
/**************************************************************************/
#include "sky_scattering_lut.h"

#include "scattering_policy.h"

#include "core/object/class_db.h"

void SkyScatteringLUT::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_cloud_lighting_lut", "density"), &SkyScatteringLUT::generate_cloud_lighting_lut);
	ClassDB::bind_method(D_METHOD("generate_lut", "width", "height", "aerosol"),
			&SkyScatteringLUT::generate_lut, DEFVAL(128), DEFVAL(64), DEFVAL(2.0f));
	ClassDB::bind_method(D_METHOD("sample_scattering", "view_elevation", "sun_elevation", "aerosol"),
			&SkyScatteringLUT::sample_scattering, DEFVAL(2.0f));
}

Ref<Image> SkyScatteringLUT::generate_lut(int p_width, int p_height, float p_aerosol) const {
	ERR_FAIL_COND_V_MSG(p_width < 16 || p_width > 512 || p_height < 16 || p_height > 256,
			Ref<Image>(), "Sky scattering LUT must be between 16x16 and 512x256.");
	Ref<Image> lut = Image::create_empty(p_width, p_height, false, Image::FORMAT_RGBAH);
	ERR_FAIL_COND_V(lut.is_null(), Ref<Image>());
	for (int y = 0; y < p_height; ++y) {
		float sun_elevation = -0.15f + 1.15f * float(y) / float(p_height - 1);
		for (int x = 0; x < p_width; ++x) {
			float view_elevation = -0.08f + 1.08f * float(x) / float(p_width - 1);
			const SkyScatteringPolicy::Sample s = SkyScatteringPolicy::sample(
					view_elevation, sun_elevation, p_aerosol);
			lut->set_pixel(x, y, Color(s.r, s.g, s.b, s.transmittance));
		}
	}
	return lut;
}

Color SkyScatteringLUT::sample_scattering(float p_view_elevation, float p_sun_elevation, float p_aerosol) const {
	// Identical spectrum and optical-depth policy as generate_lut(): fog
	// receives the same sun-dependent scattering that the sky shader samples.
	const SkyScatteringPolicy::Sample sample = SkyScatteringPolicy::sample(
			p_view_elevation, p_sun_elevation, p_aerosol);
	return Color(sample.r, sample.g, sample.b, sample.transmittance);
}

Ref<Image> SkyScatteringLUT::generate_cloud_lighting_lut(const Ref<Image> &p_density) const {
	// A fixed-cost, one-time CPU bake from the same 128x128 L8 field as the
	// terrain/foliage cloud shadows; no separate noisy simulation or volume pass.
	ERR_FAIL_COND_V_MSG(p_density.is_null() || p_density->is_compressed() ||
			p_density->get_format() != Image::FORMAT_L8, Ref<Image>(),
			"Cloud lighting needs an uncompressed L8 shadow field.");
	const int width = p_density->get_width();
	const int height = p_density->get_height();
	ERR_FAIL_COND_V_MSG(width < 16 || height < 16 || width > 512 || height > 512,
			Ref<Image>(), "Cloud tile dimensions must be between 16 and 512.");
	const Vector<uint8_t> &data = p_density->get_data();
	ERR_FAIL_COND_V_MSG(data.size() < width * height, Ref<Image>(), "Cloud tile is incomplete.");
	const uint8_t *source = data.ptr();
	Vector<uint8_t> rgba;
	rgba.resize(width * height * 4);
	uint8_t *target = rgba.ptrw();
	auto sample = [&](int p_x, int p_z) -> float {
		const int x = (p_x + width) % width;
		const int z = (p_z + height) % height;
		return float(source[z * width + x]) / 255.0f;
	};
	auto pack = [](float p_value) -> uint8_t {
		return uint8_t(CLAMP(p_value, 0.0f, 1.0f) * 255.0f + 0.5f);
	};
	for (int z = 0; z < height; ++z) {
		for (int x = 0; x < width; ++x) {
			const float center = sample(x, z);
			const float left = sample(x - 1, z), right = sample(x + 1, z);
			const float top = sample(x, z - 1), bottom = sample(x, z + 1);
			// RGB packs existing cloud density and the horizontal density
			// gradient, A stores approximate local skylight occlusion.
			const float sx = (right - left) * 0.5f;
			const float sz = (bottom - top) * 0.5f;
			const float neighbour = (left + right + top + bottom) * 0.25f;
			const float ambient = CLAMP(1.0f -
					0.60f * (center * 0.65f + neighbour * 0.35f), 0.35f, 1.0f);
			const int i = (z * width + x) * 4;
			target[i] = pack(center);
			target[i + 1] = pack(0.5f + 0.75f * sx);
			target[i + 2] = pack(0.5f + 0.75f * sz);
			target[i + 3] = pack(ambient);
		}
	}
	return Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, rgba);
}
