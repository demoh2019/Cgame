/**************************************************************************/
/*  register_types.cpp                                                    */
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

#include "register_types.h"

#include "cgame_cpu_budget.h"
#include "cgame_hitch_correlator.h"
#include "cgame_perf_capture.h"
#include "cgame_profiled_mutex.h"
#include "cgame_shader_stall_analyzer.h"
#include "cgame_task_graph.h"
#include "cgame_trace.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"

static CgameTrace *cgame_trace = nullptr;
static Engine::FrameHook cgame_previous_frame_hook = nullptr;
static bool cgame_hook_installed = false;

// Runs once per main loop iteration on the main thread.
static void _cgame_profiling_frame_hook(uint64_t p_process_frame, uint64_t p_frame_ticks_usec) {
	if (cgame_trace) {
		cgame_trace->on_engine_frame(p_process_frame);
	}
	CgameShaderStallAnalyzer::tick_all(p_process_frame, p_frame_ticks_usec);
	if (cgame_previous_frame_hook) {
		cgame_previous_frame_hook(p_process_frame, p_frame_ticks_usec);
	}
}

void initialize_cgame_profiling_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_CORE) {
		return;
	}
	GDREGISTER_CLASS(CgameTrace);
	GDREGISTER_CLASS(CgameTaskGraph);
	GDREGISTER_CLASS(CgameCPUBudget);
	GDREGISTER_CLASS(CgameProfiledMutex);
	GDREGISTER_CLASS(CgameHitchCorrelator);
	GDREGISTER_CLASS(CgamePerfCapture);
	GDREGISTER_CLASS(CgameShaderStallAnalyzer);

	cgame_trace = memnew(CgameTrace);
	Engine::get_singleton()->add_singleton(Engine::Singleton("CgameTrace", cgame_trace));

	cgame_previous_frame_hook = Engine::get_singleton()->get_frame_hook();
	Engine::get_singleton()->set_frame_hook(_cgame_profiling_frame_hook);
	cgame_hook_installed = true;
}

void uninitialize_cgame_profiling_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_CORE) {
		return;
	}
	if (cgame_hook_installed) {
		Engine::get_singleton()->set_frame_hook(cgame_previous_frame_hook);
		cgame_previous_frame_hook = nullptr;
		cgame_hook_installed = false;
	}
	CgameTrace::shutdown_buffers();
	if (cgame_trace) {
		memdelete(cgame_trace);
		cgame_trace = nullptr;
	}
}
