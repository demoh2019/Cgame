/**************************************************************************/
/*  cgroup_cpu_quota.h                                                    */
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

#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstdlib>

// Helpers are platform-local and have no dependency on the engine. Quota is
// expressed in CPU units, rounded up to permit partial-core utilization.
namespace CgroupCPUQuota {

// Returns 0 if the cgroup-v2 cpu.max value is unlimited or unavailable.
// Uses integer division rather than floating point to avoid rounding issues.
inline int parse_cpu_max(const char *p_line) {
	if (p_line == nullptr || p_line[0] < '0' || p_line[0] > '9') {
		return 0; // e.g. "max 100000".
	}

	errno = 0;
	char *end = nullptr;
	const unsigned long long quota = std::strtoull(p_line, &end, 10);
	if (errno == ERANGE || end == p_line || (*end != ' ' && *end != '\t')) {
		return 0;
	}
	while (*end == ' ' || *end == '\t') {
		end++;
	}
	if (*end < '0' || *end > '9') {
		return 0;
	}

	errno = 0;
	char *period_end = nullptr;
	const unsigned long long period = std::strtoull(end, &period_end, 10);
	if (errno == ERANGE || period_end == end || period == 0) {
		return 0;
	}
	for (; *period_end != 0; period_end++) {
		if (*period_end != ' ' && *period_end != '\t' && *period_end != '\r' && *period_end != '\n') {
			return 0;
		}
	}
	if (quota == 0) {
		return 0;
	}
	const unsigned long long cores = quota / period + (quota % period != 0);
	return cores > static_cast<unsigned long long>(INT_MAX) ? INT_MAX : static_cast<int>(cores);
}

// Affinity and explicit positive quota are both upper bounds. Always keep at
// least one worker, even if affinity detection returned an invalid count.
inline int effective_thread_count(int p_affinity_count, int p_quota_count) {
	const int allowed = p_affinity_count > 0 ? p_affinity_count : 1;
	return p_quota_count > 0 && p_quota_count < allowed ? p_quota_count : allowed;
}

inline int read_cpu_max_file(const char *p_path = "/sys/fs/cgroup/cpu.max") {
	FILE *file = std::fopen(p_path, "r");
	if (file == nullptr) {
		return 0;
	}
	char buffer[128];
	const bool ok = std::fgets(buffer, sizeof(buffer), file) != nullptr;
	std::fclose(file);
	return ok ? parse_cpu_max(buffer) : 0;
}

} // namespace CgroupCPUQuota
