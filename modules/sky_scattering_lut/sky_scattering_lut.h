/**************************************************************************/
/*  sky_scattering_lut.h                                                  */
/**************************************************************************/
#pragma once

#include "core/io/image.h"
#include "core/object/ref_counted.h"

// Runtime-agnostic small HDR LUT for sky view elevation and solar elevation.
// A game can reuse it across every Sky material; no per-frame CPU/GPU work.
class SkyScatteringLUT : public RefCounted {
	GDCLASS(SkyScatteringLUT, RefCounted);

protected:
	static void _bind_methods();

public:
	Ref<Image> generate_lut(int p_width = 128, int p_height = 64, float p_aerosol = 2.0f) const;
	// Prebake sun-shading geometry from the same L8 tile used by cloud shadows.
	Ref<Image> generate_cloud_lighting_lut(const Ref<Image> &p_density) const;
	// CPU-side match for the sky LUT's optical model. Useful to synchronize
	// the 3D world's fog/atmospheric perspective with sky radiance without
	// uploading pixels or reading GPU textures every frame.
	Color sample_scattering(float p_view_elevation, float p_sun_elevation, float p_aerosol = 2.0f) const;
};
