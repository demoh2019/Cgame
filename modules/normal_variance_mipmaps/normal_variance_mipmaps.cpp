/**************************************************************************/
/*  normal_variance_mipmaps.cpp                                           */
/**************************************************************************/
#include "normal_variance_mipmaps.h"

#include "normal_variance_policy.h"
#include "core/object/class_db.h"

void NormalVarianceMipmaps::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_image", "normal_map"), &NormalVarianceMipmaps::build_image);
}

Ref<Image> NormalVarianceMipmaps::build_image(const Ref<Image> &p_normal_map) const {
	ERR_FAIL_COND_V_MSG(p_normal_map.is_null(), Ref<Image>(), "Normal map is null.");
	ERR_FAIL_COND_V_MSG(p_normal_map->is_compressed() || p_normal_map->get_format() != Image::FORMAT_RGB8,
			Ref<Image>(), "Normal variance mipmaps require an uncompressed RGB8 source.");
	const int width = p_normal_map->get_width();
	const int height = p_normal_map->get_height();
	ERR_FAIL_COND_V_MSG(width < 2 || height < 2 || width > 1024 || height > 1024,
			Ref<Image>(), "Normal variance mipmaps must be 2..1024 pixels per axis.");

	const uint8_t *src = p_normal_map->get_data().ptr();
	Vector<NormalVariancePolicy::Mean> current;
	current.resize(width * height);
	NormalVariancePolicy::Mean *means = current.ptrw();
	for (int i = 0; i < width * height; ++i) {
		means[i] = NormalVariancePolicy::normal_from_rgb(src[i * 3], src[i * 3 + 1], src[i * 3 + 2]);
	}

	Ref<Image> layout = Image::create_empty(width, height, true, Image::FORMAT_RGBA8);
	ERR_FAIL_COND_V(layout.is_null(), Ref<Image>());
	Vector<uint8_t> bytes;
	bytes.resize(layout->get_data().size());
	uint8_t *out = bytes.ptrw();
	int current_width = width;
	int current_height = height;
	const int total_levels = layout->get_mipmap_count() + 1;
	for (int mip = 0; mip < total_levels; ++mip) {
		int64_t offset;
		int64_t size;
		int mip_width;
		int mip_height;
		layout->get_mipmap_offset_size_and_dimensions(mip, offset, size, mip_width, mip_height);
		ERR_FAIL_COND_V(mip_width != current_width || mip_height != current_height ||
				offset < 0 || size < int64_t(current_width) * current_height * 4 ||
				offset + size > bytes.size(), Ref<Image>());
		const NormalVariancePolicy::Mean *level_means = current.ptr();
		for (int i = 0; i < current_width * current_height; ++i) {
			const NormalVariancePolicy::Mean m = level_means[i];
			const float c = NormalVariancePolicy::coherence(m);
			const float inv = c > 1e-6f ? 1.0f / c : 0.0f;
			const int64_t at = offset + int64_t(i) * 4;
			out[at] = NormalVariancePolicy::encode((m.x * inv) * 0.5f + 0.5f);
			out[at + 1] = NormalVariancePolicy::encode((m.y * inv) * 0.5f + 0.5f);
			out[at + 2] = NormalVariancePolicy::encode((c > 1e-6f ? m.z * inv : 1.0f) * 0.5f + 0.5f);
			out[at + 3] = NormalVariancePolicy::encode(c);
		}
		if (mip + 1 >= total_levels) {
			break;
		}
		const int next_width = MAX(1, current_width / 2);
		const int next_height = MAX(1, current_height / 2);
		Vector<NormalVariancePolicy::Mean> next;
		next.resize(next_width * next_height);
		NormalVariancePolicy::Mean *next_means = next.ptrw();
		for (int y = 0; y < next_height; ++y) {
			for (int x = 0; x < next_width; ++x) {
				const int x0 = x * 2, x1 = MIN(x0 + 1, current_width - 1);
				const int y0 = y * 2, y1 = MIN(y0 + 1, current_height - 1);
				next_means[y * next_width + x] = NormalVariancePolicy::average4(
						level_means[y0 * current_width + x0],
						level_means[y0 * current_width + x1],
						level_means[y1 * current_width + x0],
						level_means[y1 * current_width + x1]);
			}
		}
		current = next;
		current_width = next_width;
		current_height = next_height;
	}
	return Image::create_from_data(width, height, true, Image::FORMAT_RGBA8, bytes);
}
