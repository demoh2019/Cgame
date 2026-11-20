/**************************************************************************/
/*  sky_scattering_lut.cpp                                                */
/**************************************************************************/
#include "sky_scattering_lut.h"

#include "scattering_policy.h"

#include "core/object/class_db.h"

void SkyScatteringLUT::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate_lut", "width", "height", "aerosol"),
			&SkyScatteringLUT::generate_lut, DEFVAL(128), DEFVAL(64), DEFVAL(2.0f));
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
