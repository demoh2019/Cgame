/**************************************************************************/
/*  pcg_graph_executor.h                                                  */
/*                         This file is part of: GODOT ENGINE             */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

// Evaluates a PCGGraph in dependency order with a content-addressed cache:
// a node's output is keyed by its parameters (overrides applied), its seed, the
// hashes of its inputs and, for nodes that read the world, the environment.
// Editing one node therefore recomputes only that node and what is downstream
// (incremental graph recalculation); unchanged branches are cache hits.
// Results carry per-node timings (PCG profiling) and, when debugging, every
// intermediate output (PCG debugging). execute_async() runs on the
// WorkerThreadPool and reports on the main thread (async generation).

#include "pcg_graph.h"

#include "core/object/worker_thread_pool.h"
#include "core/os/mutex.h"
#include "core/templates/hash_map.h"

class PCGGraphExecutor : public RefCounted {
	GDCLASS(PCGGraphExecutor, RefCounted);

	struct Job {
		Ref<PCGGraph> graph;
		Ref<PCGContext> context;
		Dictionary result;
		WorkerThreadPool::TaskID task_id = WorkerThreadPool::INVALID_TASK_ID;
		bool done = false;
	};

	mutable Mutex cache_mutex;
	HashMap<uint64_t, Ref<PCGData>> cache;
	int max_cache_entries = 4096;
	bool cache_enabled = true;

	Mutex jobs_mutex;
	HashMap<int64_t, Job> jobs;
	int64_t next_job_id = 1;

	void _run_job(int64_t p_job_id);
	void _finish_job(int64_t p_job_id);

protected:
	static void _bind_methods();

public:
	// Per-node seed: world seed, node id and node seed offset. Never the cell, so tiling is seamless.
	static uint64_t node_seed(const Ref<PCGContext> &p_context, const Ref<PCGNode> &p_node);

	// {"output": PCGData, "order": PackedInt32Array, "timings_usec": {id: int}, "total_usec": int,
	//  "cache_hits": int, "cache_misses": int, "node_outputs": {id: PCGData} (debug only),
	//  "point_counts": {id: int}, "error": String (only on failure)}
	Dictionary execute(const Ref<PCGGraph> &p_graph, const Ref<PCGContext> &p_context);
	int64_t execute_async(const Ref<PCGGraph> &p_graph, const Ref<PCGContext> &p_context);
	bool is_job_done(int64_t p_job_id);
	// Blocks until the job finishes and returns its result (and forgets the job).
	Dictionary wait_for_job(int64_t p_job_id);

	void clear_cache();
	int get_cache_size() const;
	void set_max_cache_entries(int p_max) { max_cache_entries = MAX(0, p_max); }
	int get_max_cache_entries() const { return max_cache_entries; }
	void set_cache_enabled(bool p_enabled) { cache_enabled = p_enabled; }
	bool is_cache_enabled() const { return cache_enabled; }

	// Formats a result's timings as a sorted, human-readable profile (slowest first).
	static String format_profile(const Ref<PCGGraph> &p_graph, const Dictionary &p_result);

	~PCGGraphExecutor();
};
