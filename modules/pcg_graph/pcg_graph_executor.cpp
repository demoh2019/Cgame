/**************************************************************************/
/*  pcg_graph_executor.cpp                                                */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "pcg_graph_executor.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"

uint64_t PCGGraphExecutor::node_seed(const Ref<PCGContext> &p_context, const Ref<PCGNode> &p_node) {
	const uint64_t world = p_context.is_valid() ? (uint64_t)p_context->get_seed() : 1337;
	uint64_t s = pcg_mix64(world, (uint64_t)p_node->get_node_id());
	return pcg_mix64(s, (uint64_t)p_node->get_seed_offset());
}

Dictionary PCGGraphExecutor::execute(const Ref<PCGGraph> &p_graph, const Ref<PCGContext> &p_context) {
	Dictionary result;
	if (p_graph.is_null()) {
		result["error"] = "No graph.";
		return result;
	}
	Ref<PCGContext> context = p_context;
	if (context.is_null()) {
		context.instantiate();
	}
	const PackedInt32Array order = p_graph->compute_order();
	if (order.is_empty() && p_graph->get_node_count() > 0) {
		result["error"] = "Graph has a cycle.";
		return result;
	}
	// Exposed parameter defaults under the caller's overrides.
	Ref<PCGContext> run_context = context;
	if (!p_graph->get_parameters().is_empty()) {
		run_context = Ref<PCGContext>(memnew(PCGContext));
		run_context->set_seed(context->get_seed());
		run_context->set_bounds(context->get_bounds());
		run_context->set_cell(context->get_cell());
		run_context->set_height_sampler(context->get_height_sampler());
		run_context->set_biome_sampler(context->get_biome_sampler());
		run_context->set_water_sampler(context->get_water_sampler());
		run_context->set_exclusions(context->get_exclusions());
		run_context->set_user_data(context->get_user_data());
		run_context->set_debug(context->is_debug());
		run_context->set_environment_version(context->get_environment_version());
		run_context->set_overrides(p_graph->resolve_parameters(context->get_overrides()));
	}
	const uint64_t environment_hash = run_context->compute_environment_hash();
	const bool debug = run_context->is_debug();

	HashMap<int, Ref<PCGData>> outputs;
	HashMap<int, uint64_t> output_hashes;
	Dictionary timings;
	Dictionary node_outputs;
	Dictionary point_counts;
	int hits = 0;
	int misses = 0;
	const uint64_t start = OS::get_singleton()->get_ticks_usec();

	for (int i = 0; i < order.size(); i++) {
		const int id = order[i];
		Ref<PCGNode> node = p_graph->get_node_by_id(id);
		if (node.is_null()) {
			continue;
		}
		const PackedInt32Array sources = p_graph->get_input_sources(id);
		Vector<Ref<PCGData>> inputs;
		uint64_t key = pcg_mix64(node->compute_param_hash(run_context), node_seed(run_context, node));
		for (int s = 0; s < sources.size(); s++) {
			Ref<PCGData> input;
			uint64_t input_hash = 0x9e3779b97f4a7c15ULL;
			if (sources[s] >= 0 && outputs.has(sources[s])) {
				input = outputs[sources[s]];
				input_hash = output_hashes[sources[s]];
			}
			inputs.push_back(input);
			key = pcg_mix64(key, input_hash);
		}
		if (node->uses_environment()) {
			key = pcg_mix64(key, environment_hash);
		}

		const uint64_t node_start = OS::get_singleton()->get_ticks_usec();
		Ref<PCGData> output;
		bool hit = false;
		if (cache_enabled) {
			MutexLock lock(cache_mutex);
			if (cache.has(key)) {
				output = cache[key];
				hit = true;
			}
		}
		if (!hit) {
			if (!node->is_enabled()) {
				output = inputs.is_empty() ? Ref<PCGData>(memnew(PCGPointData)) : inputs[0];
				if (output.is_null()) {
					output = Ref<PCGData>(memnew(PCGPointData));
				}
			} else {
				output = node->execute(inputs, run_context, node_seed(run_context, node));
			}
			if (output.is_null()) {
				output = Ref<PCGData>(memnew(PCGPointData));
			}
			if (cache_enabled) {
				MutexLock lock(cache_mutex);
				if (max_cache_entries > 0 && cache.size() >= (uint32_t)max_cache_entries) {
					cache.clear(); // Bounded memory: start over rather than track recency.
				}
				cache[key] = output;
			}
			misses++;
		} else {
			hits++;
		}
		outputs[id] = output;
		// The cache key fully determines the output, so it doubles as the content hash downstream.
		output_hashes[id] = key;
		timings[id] = int64_t(OS::get_singleton()->get_ticks_usec() - node_start);
		Ref<PCGPointData> points = output;
		point_counts[id] = points.is_valid() ? points->get_point_count() : -1;
		if (debug || node->is_debug_output()) {
			node_outputs[id] = output;
		}
	}

	const int output_id = p_graph->resolve_output_node_id();
	result["output"] = outputs.has(output_id) ? outputs[output_id] : Ref<PCGData>(memnew(PCGPointData));
	result["output_node_id"] = output_id;
	result["order"] = order;
	result["timings_usec"] = timings;
	result["total_usec"] = int64_t(OS::get_singleton()->get_ticks_usec() - start);
	result["cache_hits"] = hits;
	result["cache_misses"] = misses;
	result["node_outputs"] = node_outputs;
	result["point_counts"] = point_counts;
	return result;
}

void PCGGraphExecutor::_run_job(int64_t p_job_id) {
	Ref<PCGGraph> graph;
	Ref<PCGContext> context;
	{
		MutexLock lock(jobs_mutex);
		if (!jobs.has(p_job_id)) {
			return;
		}
		graph = jobs[p_job_id].graph;
		context = jobs[p_job_id].context;
	}
	Dictionary result = execute(graph, context);
	result["job_id"] = p_job_id;
	{
		MutexLock lock(jobs_mutex);
		if (jobs.has(p_job_id)) {
			jobs[p_job_id].result = result;
			jobs[p_job_id].done = true;
		}
	}
	callable_mp(this, &PCGGraphExecutor::_finish_job).call_deferred(p_job_id);
}

void PCGGraphExecutor::_finish_job(int64_t p_job_id) {
	Dictionary result;
	WorkerThreadPool::TaskID task = WorkerThreadPool::INVALID_TASK_ID;
	{
		MutexLock lock(jobs_mutex);
		if (!jobs.has(p_job_id)) {
			return; // Already collected by wait_for_job().
		}
		result = jobs[p_job_id].result;
		task = jobs[p_job_id].task_id;
		jobs.erase(p_job_id);
	}
	if (task != WorkerThreadPool::INVALID_TASK_ID) {
		WorkerThreadPool::get_singleton()->wait_for_task_completion(task);
	}
	emit_signal(SNAME("job_completed"), p_job_id, result);
}

int64_t PCGGraphExecutor::execute_async(const Ref<PCGGraph> &p_graph, const Ref<PCGContext> &p_context) {
	ERR_FAIL_COND_V(p_graph.is_null(), -1);
	int64_t id = 0;
	{
		MutexLock lock(jobs_mutex);
		id = next_job_id++;
		Job job;
		job.graph = p_graph;
		job.context = p_context;
		jobs[id] = job;
	}
	const WorkerThreadPool::TaskID task = WorkerThreadPool::get_singleton()->add_task(callable_mp(this, &PCGGraphExecutor::_run_job).bind(id), false, "PCG graph");
	{
		MutexLock lock(jobs_mutex);
		if (jobs.has(id)) {
			jobs[id].task_id = task;
		}
	}
	return id;
}

bool PCGGraphExecutor::is_job_done(int64_t p_job_id) {
	MutexLock lock(jobs_mutex);
	return !jobs.has(p_job_id) || jobs[p_job_id].done;
}

Dictionary PCGGraphExecutor::wait_for_job(int64_t p_job_id) {
	WorkerThreadPool::TaskID task = WorkerThreadPool::INVALID_TASK_ID;
	{
		MutexLock lock(jobs_mutex);
		if (!jobs.has(p_job_id)) {
			return Dictionary();
		}
		task = jobs[p_job_id].task_id;
	}
	if (task != WorkerThreadPool::INVALID_TASK_ID) {
		WorkerThreadPool::get_singleton()->wait_for_task_completion(task);
	}
	MutexLock lock(jobs_mutex);
	if (!jobs.has(p_job_id)) {
		return Dictionary();
	}
	Dictionary result = jobs[p_job_id].result;
	jobs[p_job_id].task_id = WorkerThreadPool::INVALID_TASK_ID;
	jobs.erase(p_job_id); // The deferred _finish_job will find nothing and stay silent.
	return result;
}

void PCGGraphExecutor::clear_cache() {
	MutexLock lock(cache_mutex);
	cache.clear();
}

int PCGGraphExecutor::get_cache_size() const {
	MutexLock lock(cache_mutex);
	return cache.size();
}

String PCGGraphExecutor::format_profile(const Ref<PCGGraph> &p_graph, const Dictionary &p_result) {
	Dictionary timings = p_result.get("timings_usec", Dictionary());
	Dictionary counts = p_result.get("point_counts", Dictionary());
	Array ids = timings.keys();
	// Slowest first, ties by id.
	for (int i = 0; i < ids.size(); i++) {
		for (int j = i + 1; j < ids.size(); j++) {
			const int64_t a = timings[ids[i]];
			const int64_t b = timings[ids[j]];
			if (b > a || (b == a && int(ids[j]) < int(ids[i]))) {
				const Variant swap = ids[i];
				ids[i] = ids[j];
				ids[j] = swap;
			}
		}
	}
	String text = vformat("PCG %d us total, %d cache hits, %d misses\n", int64_t(p_result.get("total_usec", 0)), int(p_result.get("cache_hits", 0)), int(p_result.get("cache_misses", 0)));
	for (int i = 0; i < ids.size(); i++) {
		String name = vformat("#%d", int(ids[i]));
		if (p_graph.is_valid()) {
			Ref<PCGNode> node = p_graph->get_node_by_id(ids[i]);
			if (node.is_valid()) {
				name = vformat("#%d %s", int(ids[i]), node->get_title());
			}
		}
		text += vformat("  %-32s %8d us  %6d pts\n", name, int64_t(timings[ids[i]]), int(counts.get(ids[i], -1)));
	}
	return text;
}

PCGGraphExecutor::~PCGGraphExecutor() {
	Vector<WorkerThreadPool::TaskID> pending;
	{
		MutexLock lock(jobs_mutex);
		for (const KeyValue<int64_t, Job> &E : jobs) {
			if (E.value.task_id != WorkerThreadPool::INVALID_TASK_ID) {
				pending.push_back(E.value.task_id);
			}
		}
	}
	for (WorkerThreadPool::TaskID task : pending) {
		WorkerThreadPool::get_singleton()->wait_for_task_completion(task);
	}
}

void PCGGraphExecutor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("execute", "graph", "context"), &PCGGraphExecutor::execute);
	ClassDB::bind_method(D_METHOD("execute_async", "graph", "context"), &PCGGraphExecutor::execute_async);
	ClassDB::bind_method(D_METHOD("is_job_done", "job_id"), &PCGGraphExecutor::is_job_done);
	ClassDB::bind_method(D_METHOD("wait_for_job", "job_id"), &PCGGraphExecutor::wait_for_job);
	ClassDB::bind_method(D_METHOD("clear_cache"), &PCGGraphExecutor::clear_cache);
	ClassDB::bind_method(D_METHOD("get_cache_size"), &PCGGraphExecutor::get_cache_size);
	ClassDB::bind_method(D_METHOD("set_max_cache_entries", "max"), &PCGGraphExecutor::set_max_cache_entries);
	ClassDB::bind_method(D_METHOD("get_max_cache_entries"), &PCGGraphExecutor::get_max_cache_entries);
	ClassDB::bind_method(D_METHOD("set_cache_enabled", "enabled"), &PCGGraphExecutor::set_cache_enabled);
	ClassDB::bind_method(D_METHOD("is_cache_enabled"), &PCGGraphExecutor::is_cache_enabled);
	ClassDB::bind_static_method("PCGGraphExecutor", D_METHOD("format_profile", "graph", "result"), &PCGGraphExecutor::format_profile);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_cache_entries"), "set_max_cache_entries", "get_max_cache_entries");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cache_enabled"), "set_cache_enabled", "is_cache_enabled");

	ADD_SIGNAL(MethodInfo("job_completed", PropertyInfo(Variant::INT, "job_id"), PropertyInfo(Variant::DICTIONARY, "result")));
}
