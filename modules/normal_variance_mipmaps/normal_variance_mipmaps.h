/**************************************************************************/
/*  normal_variance_mipmaps.h                                             */
/**************************************************************************/
#pragma once

#include "core/io/image.h"
#include "core/object/ref_counted.h"

// Bake normal-map mipmaps with Toksvig coherence in alpha. RGB is the
// normalized mean direction, so unchanged materials may use the same texture.
class NormalVarianceMipmaps : public RefCounted {
	GDCLASS(NormalVarianceMipmaps, RefCounted);

protected:
	static void _bind_methods();

public:
	// Requires an uncompressed RGB8 tangent-space normal map; no mutation.
	Ref<Image> build_image(const Ref<Image> &p_normal_map) const;
};
