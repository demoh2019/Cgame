/**************************************************************************/
/*  cgame_gpu_matrix_db.h                                                 */
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

#include "core/io/image.h"
#include "core/object/ref_counted.h"

// GPU compatibility matrix and rendering-regression database.
//
// Ingests the JSON reports written by a GPU benchmark run (collected from testers), builds
// vendor x family x driver x renderer cells (pass / fail / perf), detects visual regressions by perceptual-hash
// distance against a per-renderer reference, clusters failures by driver, exports Markdown / CSV and writes a
// learned JSON that CgameGPUSettingsDB can read (same layout as user://gpu_learned.json).
//
// Concepts (not code): result-schema versioning as in public benchmark reports and the Steam hardware survey
// (adapter + driver + OS only, no personal data); the difference hash (dHash) is the public-domain "perceptual
// hash" idea (9x8 greyscale, 64 gradient bits).
class CgameGPUMatrixDB : public RefCounted {
	GDCLASS(CgameGPUMatrixDB, RefCounted);

public:
	static constexpr int SCHEMA_VERSION = 1;
	static constexpr int HASH_HEX_LEN = 16;
	static constexpr int DEFAULT_TOLERANCE = 8;
	// Frame time written into the learned JSON for a level that rendered incorrectly, so
	// CgameGPUSettingsDB.recommend() never picks it.
	static constexpr double BLOCKED_LEVEL_MS = 1000.0;
	static constexpr int MAX_LEARNED_SAMPLES = 31;

private:
	int tolerance = DEFAULT_TOLERANCE;
	double target_ms = 1000.0 / 60.0;
	Array reports;
	PackedStringArray rejected;
	Dictionary manual_refs;
	Dictionary references;
	Array evals;
	bool built = false;

	static String _ref_key(const String &p_renderer, int p_level, int p_index);
	static String _medoid(const Array &p_hashes);
	static double _median(const Array &p_values);
	static bool _is_hex16(const String &p_hash);
	static String _md(const String &p_text);
	Dictionary _evaluate(const Dictionary &p_report) const;

protected:
	static void _bind_methods();

public:
	void set_tolerance(int p_tolerance) { tolerance = p_tolerance; }
	int get_tolerance() const { return tolerance; }
	void set_target_ms(double p_target_ms) { target_ms = p_target_ms; }
	double get_target_ms() const { return target_ms; }
	Array get_reports() const { return reports; }
	PackedStringArray get_rejected() const { return rejected; }

	static PackedStringArray validate_report(const Variant &p_report);
	static String dhash(const Ref<Image> &p_image);
	static int hash_distance(const String &p_a, const String &p_b);

	bool add_report(const Variant &p_report, const String &p_source = "");
	bool ingest_file(const String &p_path);
	int ingest_dir(const String &p_dir_path);
	void set_reference(const String &p_renderer, int p_level, int p_index, const String &p_checksum);

	void build();
	Array evaluations();
	Array cells();
	Array driver_failures();
	Array regressions();
	Dictionary learned_data();
	bool write_learned(const String &p_path = "user://gpu_learned.json");

	String to_csv();
	String to_markdown();
	static String csv_escape(const String &p_text);
	void clear();
};
