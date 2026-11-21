/**************************************************************************/
/*  frame_generation.h                                                    */
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

#pragma once

#include "servers/rendering/renderer_rd/shaders/effects/frame_generation_flow.glsl.gen.h"
#include "servers/rendering/renderer_rd/shaders/effects/frame_generation_history.glsl.gen.h"
#include "servers/rendering/renderer_rd/shaders/effects/frame_generation_interpolate.glsl.gen.h"
#include "servers/rendering/renderer_rd/storage_rd/render_buffer_custom_data_rd.h"
#include "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h"

namespace RendererRD {

// Motion-vector based frame interpolation, inspired by the FSR 3 frame generation design
// (optical flow + interpolation passes). It operates on the final 3D image of a viewport,
// before 2D canvas items (UI) are drawn, so the UI is never interpolated.
//
// The generated in-between frame is stored in the render buffers as the named texture
// context "frame_generation", name "interpolated" (RGBA16F, target size).
class FrameGeneration {
public:
	// Per-viewport state: history validity and presentation pacing statistics.
	class Data : public RenderBufferCustomDataRD {
		GDCLASS(Data, RenderBufferCustomDataRD);

	public:
		bool history_valid = false;
		Size2i history_size;
		uint64_t last_frame_usec = 0;
		double average_interval_usec = 0.0;
		uint64_t generated_frames = 0;

		// Registers a new real frame and updates the smoothed frame interval.
		void register_frame(uint64_t p_now_usec);
		// Delay after a real frame at which the interpolated frame should be presented.
		uint64_t get_interpolated_present_delay_usec() const;

		virtual void configure(RenderSceneBuffersRD *p_render_buffers) override;
		virtual void free_data() override;
	};

	struct Settings {
		// Maximum relative depth difference before the previous frame is considered disoccluded.
		float depth_threshold = 0.1f;
		// Refine game motion vectors with a block-matching search (optical flow lite).
		bool use_optical_flow = true;
		// Interpolation phase between the previous (0) and current (1) frame.
		float phase = 0.5f;
	};

private:
	struct FlowPushConstant {
		float size[2];
		float inv_size[2];
		float search_scale;
		float pad[3];
	};

	struct InterpolatePushConstant {
		float size[2];
		float inv_size[2];
		float t;
		float depth_threshold;
		float pad[2];
	};

	struct HistoryPushConstant {
		float size[2];
		float inv_size[2];
	};

	FrameGenerationFlowShaderRD flow_shader;
	FrameGenerationInterpolateShaderRD interpolate_shader;
	FrameGenerationHistoryShaderRD history_shader;
	RID flow_version;
	RID interpolate_version;
	RID history_version;
	RID flow_pipeline;
	RID interpolate_pipeline;
	RID history_pipeline;

public:
	FrameGeneration();
	~FrameGeneration();

	// p_color: final 3D color (render target texture, target size) before 2D is drawn.
	// Returns true if an interpolated frame was produced for this real frame.
	bool process(Ref<RenderSceneBuffersRD> p_render_buffers, RID p_color, const Settings &p_settings);
};

} // namespace RendererRD
