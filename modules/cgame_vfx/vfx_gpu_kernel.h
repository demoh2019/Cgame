/**************************************************************************/
/*  vfx_gpu_kernel.h                                                      */
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

#include "vfx_simulation.h"

class RenderingDevice;

// GPU update kernel of the VFX graph. Compiles an emitter's update/post modules into a GLSL
// compute shader (SSBO particle buffer plus an atomic-append event buffer for collision routing)
// and runs it on a shared local RenderingDevice. When no device exists (headless/dummy
// renderer, compatibility renderer) or compilation fails, step() returns false and the emitter
// falls back to the CPU reference kernel, which implements the identical algorithm.
//
// Spawn stages always run on the CPU. Death events are routed on the CPU after the kernel; only
// collision events travel through the event buffer.
class VFXGpuKernel {
public:
	static constexpr int LOCAL_SIZE = 64;
	static constexpr int FLOATS_PER_PARTICLE = 20;
	static constexpr int BYTES_PER_PARTICLE = 80;
	static constexpr int EVENT_HEADER_BYTES = 16;
	static constexpr int EVENT_BYTES = 32;

private:
	static RenderingDevice *shared_device;
	static int shared_users;

	RenderingDevice *rd = nullptr;
	bool opened = false;
	String last_path = "none";
	String last_error;

	bool _build(VFXSim::Emitter &r_emitter);
	void _free_emitter(VFXSim::Emitter &r_emitter);

public:
	// Template shared with the GDScript reference (particles_update.glsl.template).
	static const char *get_template_source();
	// Assigns GPU event slots (1..n) to collide_plane modules that route events.
	static void plan_slots(VFXSim::Emitter &r_emitter);
	// Generates the full compute shader source ("#[compute]" header included).
	static String generate_compute_source(VFXSim::Emitter &r_emitter, bool p_route_death = false);
	// Every update-stage module is supported; reported for API symmetry and future extension.
	static bool supports(const VFXSim::Emitter &p_emitter);

	// Opens the shared local device. Returns true when a compute capable device is available.
	bool open();
	void close();
	bool is_available() const { return rd != nullptr; }
	String get_last_path() const { return last_path; }
	String get_last_error() const { return last_error; }

	// Runs the update, integrate and post stages on the device. Returns false on any failure.
	bool step(VFXSim::Emitter &r_emitter, double p_dt);
	void release(VFXSim::System &r_system);

	~VFXGpuKernel() { close(); }
};
