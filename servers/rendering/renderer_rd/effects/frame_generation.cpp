/**************************************************************************/
/*  frame_generation.cpp                                                  */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "frame_generation.h"

#include "core/os/os.h"
#include "servers/rendering/renderer_rd/uniform_set_cache_rd.h"

namespace RendererRD {

void FrameGeneration::Data::register_frame(uint64_t p_now_usec) {
	if (last_frame_usec != 0 && p_now_usec > last_frame_usec) {
		double interval = double(p_now_usec - last_frame_usec);
		average_interval_usec = average_interval_usec == 0.0 ? interval : Math::lerp(average_interval_usec, interval, 0.1);
	}
	last_frame_usec = p_now_usec;
}

uint64_t FrameGeneration::Data::get_interpolated_present_delay_usec() const {
	return uint64_t(average_interval_usec * 0.5);
}

void FrameGeneration::Data::configure(RenderSceneBuffersRD *p_render_buffers) {
	// Buffers were (re)created, the history is gone.
	history_valid = false;
}

void FrameGeneration::Data::free_data() {
	history_valid = false;
}

FrameGeneration::FrameGeneration() {
	Vector<String> modes;
	modes.push_back("");

	flow_shader.initialize(modes);
	flow_version = flow_shader.version_create();
	flow_pipeline = RD::get_singleton()->compute_pipeline_create(flow_shader.version_get_shader(flow_version, 0));

	interpolate_shader.initialize(modes);
	interpolate_version = interpolate_shader.version_create();
	interpolate_pipeline = RD::get_singleton()->compute_pipeline_create(interpolate_shader.version_get_shader(interpolate_version, 0));

	history_shader.initialize(modes);
	history_version = history_shader.version_create();
	history_pipeline = RD::get_singleton()->compute_pipeline_create(history_shader.version_get_shader(history_version, 0));
}

FrameGeneration::~FrameGeneration() {
	flow_shader.version_free(flow_version);
	interpolate_shader.version_free(interpolate_version);
	history_shader.version_free(history_version);
}

bool FrameGeneration::process(Ref<RenderSceneBuffersRD> p_render_buffers, RID p_color, const Settings &p_settings) {
	ERR_FAIL_COND_V(p_render_buffers.is_null(), false);
	ERR_FAIL_COND_V(p_color.is_null(), false);

	MaterialStorage *material_storage = MaterialStorage::get_singleton();
	ERR_FAIL_NULL_V(material_storage, false);
	UniformSetCacheRD *uniform_set_cache = UniformSetCacheRD::get_singleton();
	ERR_FAIL_NULL_V(uniform_set_cache, false);

	if (p_render_buffers->get_view_count() > 1) {
		WARN_PRINT_ONCE("Frame generation does not support multiview rendering yet.");
		return false;
	}
	if (!p_render_buffers->has_velocity_buffer(false)) {
		return false;
	}

	Ref<Data> data;
	if (p_render_buffers->has_custom_data(SNAME("frame_generation"))) {
		data = p_render_buffers->get_custom_data(SNAME("frame_generation"));
	} else {
		data.instantiate();
		p_render_buffers->set_custom_data(SNAME("frame_generation"), data);
	}

	Size2i size = p_render_buffers->get_target_size();
	if (size.x < 8 || size.y < 8) {
		return false;
	}

	const StringName ctx = SNAME("frame_generation");
	const uint32_t usage = RD::TEXTURE_USAGE_SAMPLING_BIT | RD::TEXTURE_USAGE_STORAGE_BIT;

	bool had_history = p_render_buffers->has_texture(ctx, SNAME("history_color")) && data->history_valid && data->history_size == size;
	RID history_color = p_render_buffers->create_texture(ctx, SNAME("history_color"), RD::DATA_FORMAT_R16G16B16A16_SFLOAT, usage, RD::TEXTURE_SAMPLES_1, size, 1);
	RID history_depth = p_render_buffers->create_texture(ctx, SNAME("history_depth"), RD::DATA_FORMAT_R32_SFLOAT, usage, RD::TEXTURE_SAMPLES_1, size, 1);
	RID flow = p_render_buffers->create_texture(ctx, SNAME("flow"), RD::DATA_FORMAT_R16G16B16A16_SFLOAT, usage, RD::TEXTURE_SAMPLES_1, size, 1);
	RID interpolated = p_render_buffers->create_texture(ctx, SNAME("interpolated"), RD::DATA_FORMAT_R16G16B16A16_SFLOAT, usage, RD::TEXTURE_SAMPLES_1, size, 1);

	RID depth = p_render_buffers->get_depth_texture();
	RID velocity = p_render_buffers->get_velocity_buffer(false);
	if (depth.is_null() || velocity.is_null()) {
		return false;
	}

	data->register_frame(OS::get_singleton()->get_ticks_usec());

	RID linear_sampler = material_storage->sampler_rd_get_default(RSE::CANVAS_ITEM_TEXTURE_FILTER_LINEAR, RSE::CANVAS_ITEM_TEXTURE_REPEAT_DISABLED);
	RID nearest_sampler = material_storage->sampler_rd_get_default(RSE::CANVAS_ITEM_TEXTURE_FILTER_NEAREST, RSE::CANVAS_ITEM_TEXTURE_REPEAT_DISABLED);

	Vector2 fsize(size.x, size.y);
	Vector2 inv_size(1.0f / size.x, 1.0f / size.y);

	RD::get_singleton()->draw_command_begin_label("Frame Generation");

	if (had_history) {
		RID flow_sh = flow_shader.version_get_shader(flow_version, 0);
		RID interp_sh = interpolate_shader.version_get_shader(interpolate_version, 0);
		ERR_FAIL_COND_V(flow_sh.is_null() || interp_sh.is_null(), false);

		RD::get_singleton()->draw_command_begin_label("Optical Flow");
		{
			FlowPushConstant pc;
			pc.size[0] = fsize.x;
			pc.size[1] = fsize.y;
			pc.inv_size[0] = inv_size.x;
			pc.inv_size[1] = inv_size.y;
			pc.search_scale = p_settings.use_optical_flow ? 1.0f : 0.0f;
			pc.pad[0] = pc.pad[1] = pc.pad[2] = 0.0f;

			RD::Uniform u_prev(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, Vector<RID>({ linear_sampler, history_color }));
			RD::Uniform u_cur(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, Vector<RID>({ linear_sampler, p_color }));
			RD::Uniform u_vel(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, Vector<RID>({ nearest_sampler, velocity }));
			RD::Uniform u_flow(RD::UNIFORM_TYPE_IMAGE, 3, flow);
			RID set = uniform_set_cache->get_cache(flow_sh, 0, u_prev, u_cur, u_vel, u_flow);

			RD::ComputeListID cl = RD::get_singleton()->compute_list_begin();
			RD::get_singleton()->compute_list_bind_compute_pipeline(cl, flow_pipeline);
			RD::get_singleton()->compute_list_bind_uniform_set(cl, set, 0);
			RD::get_singleton()->compute_list_set_push_constant(cl, &pc, sizeof(pc));
			RD::get_singleton()->compute_list_dispatch_threads(cl, size.x, size.y, 1);
			RD::get_singleton()->compute_list_end();
		}
		RD::get_singleton()->draw_command_end_label();

		RD::get_singleton()->draw_command_begin_label("Interpolate");
		{
			InterpolatePushConstant pc;
			pc.size[0] = fsize.x;
			pc.size[1] = fsize.y;
			pc.inv_size[0] = inv_size.x;
			pc.inv_size[1] = inv_size.y;
			pc.t = CLAMP(p_settings.phase, 0.0f, 1.0f);
			pc.depth_threshold = p_settings.depth_threshold;
			pc.pad[0] = pc.pad[1] = 0.0f;

			RD::Uniform u_prev(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, Vector<RID>({ linear_sampler, history_color }));
			RD::Uniform u_cur(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, Vector<RID>({ linear_sampler, p_color }));
			RD::Uniform u_flow(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, Vector<RID>({ nearest_sampler, flow }));
			RD::Uniform u_pdepth(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, Vector<RID>({ nearest_sampler, history_depth }));
			RD::Uniform u_cdepth(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, Vector<RID>({ nearest_sampler, depth }));
			RD::Uniform u_out(RD::UNIFORM_TYPE_IMAGE, 5, interpolated);
			RID set = uniform_set_cache->get_cache(interp_sh, 0, u_prev, u_cur, u_flow, u_pdepth, u_cdepth, u_out);

			RD::ComputeListID cl = RD::get_singleton()->compute_list_begin();
			RD::get_singleton()->compute_list_bind_compute_pipeline(cl, interpolate_pipeline);
			RD::get_singleton()->compute_list_bind_uniform_set(cl, set, 0);
			RD::get_singleton()->compute_list_set_push_constant(cl, &pc, sizeof(pc));
			RD::get_singleton()->compute_list_dispatch_threads(cl, size.x, size.y, 1);
			RD::get_singleton()->compute_list_end();
		}
		RD::get_singleton()->draw_command_end_label();
		data->generated_frames++;
	}

	// Store the current frame as the history for the next one.
	RD::get_singleton()->draw_command_begin_label("Store History");
	{
		RID hist_sh = history_shader.version_get_shader(history_version, 0);
		ERR_FAIL_COND_V(hist_sh.is_null(), false);

		HistoryPushConstant pc;
		pc.size[0] = fsize.x;
		pc.size[1] = fsize.y;
		pc.inv_size[0] = inv_size.x;
		pc.inv_size[1] = inv_size.y;

		RD::Uniform u_cur(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, Vector<RID>({ linear_sampler, p_color }));
		RD::Uniform u_depth(RD::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, Vector<RID>({ nearest_sampler, depth }));
		RD::Uniform u_hc(RD::UNIFORM_TYPE_IMAGE, 2, history_color);
		RD::Uniform u_hd(RD::UNIFORM_TYPE_IMAGE, 3, history_depth);
		RID set = uniform_set_cache->get_cache(hist_sh, 0, u_cur, u_depth, u_hc, u_hd);

		RD::ComputeListID cl = RD::get_singleton()->compute_list_begin();
		RD::get_singleton()->compute_list_bind_compute_pipeline(cl, history_pipeline);
		RD::get_singleton()->compute_list_bind_uniform_set(cl, set, 0);
		RD::get_singleton()->compute_list_set_push_constant(cl, &pc, sizeof(pc));
		RD::get_singleton()->compute_list_dispatch_threads(cl, size.x, size.y, 1);
		RD::get_singleton()->compute_list_end();
	}
	RD::get_singleton()->draw_command_end_label();

	data->history_valid = true;
	data->history_size = size;

	RD::get_singleton()->draw_command_end_label();
	return had_history;
}

} // namespace RendererRD
