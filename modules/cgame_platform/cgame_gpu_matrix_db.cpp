/**************************************************************************/
/*  cgame_gpu_matrix_db.cpp                                               */
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

#include "cgame_gpu_matrix_db.h"

#include "cgame_gpu_settings_db.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/templates/sort_array.h"

namespace {

const int POPCOUNT[16] = { 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4 };

int64_t _to_int(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::BOOL:
		case Variant::STRING:
			return (int64_t)p_value;
		default:
			return 0;
	}
}

bool _is_number(const Variant &p_value) {
	return p_value.get_type() == Variant::INT || p_value.get_type() == Variant::FLOAT;
}

int _hex_value(char32_t p_c) {
	if (p_c >= '0' && p_c <= '9') {
		return (int)(p_c - '0');
	}
	if (p_c >= 'a' && p_c <= 'f') {
		return (int)(p_c - 'a') + 10;
	}
	if (p_c >= 'A' && p_c <= 'F') {
		return (int)(p_c - 'A') + 10;
	}
	return -1;
}

struct ClusterOrder {
	bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		const double ra = p_a["ratio"];
		const double rb = p_b["ratio"];
		if (ra != rb) {
			return ra > rb;
		}
		const String da = p_a["driver"];
		const String db = p_b["driver"];
		if (da != db) {
			return da < db;
		}
		const String va = p_a["vendor"];
		const String vb = p_b["vendor"];
		if (va != vb) {
			return va < vb;
		}
		return String(p_a["renderer"]) < String(p_b["renderer"]);
	}
};

PackedStringArray _reason_list(const Dictionary &p_reasons) {
	PackedStringArray rs;
	for (const Variant &k : p_reasons.keys()) {
		rs.push_back(vformat("%s x%d", String(k), (int)p_reasons[k]));
	}
	return rs;
}

} // namespace

// ------------------------------------------------------------------ schema

bool CgameGPUMatrixDB::_is_hex16(const String &p_hash) {
	if (p_hash.length() != HASH_HEX_LEN) {
		return false;
	}
	for (int i = 0; i < p_hash.length(); i++) {
		if (_hex_value(p_hash[i]) < 0) {
			return false;
		}
	}
	return true;
}

PackedStringArray CgameGPUMatrixDB::validate_report(const Variant &p_report) {
	PackedStringArray errs;
	if (p_report.get_type() != Variant::DICTIONARY) {
		errs.push_back("report is not an object");
		return errs;
	}
	const Dictionary d = p_report;
	if (_to_int(d.get("schema", 0)) != SCHEMA_VERSION) {
		errs.push_back(vformat("unsupported schema %s", d.has("schema") ? String(d["schema"]) : String("missing")));
	}
	const Variant sys_v = d.get("system", Variant());
	if (sys_v.get_type() != Variant::DICTIONARY) {
		errs.push_back("missing system");
	} else {
		const Dictionary sys = sys_v;
		static const char *keys[5] = { "adapter", "vendor", "driver", "os", "renderer" };
		for (int i = 0; i < 5; i++) {
			const Variant v = sys.get(keys[i], Variant());
			if (v.get_type() != Variant::STRING || String(v).strip_edges().is_empty()) {
				errs.push_back(vformat("system.%s missing", keys[i]));
			}
		}
	}
	const Variant runs_v = d.get("runs", Variant());
	if (runs_v.get_type() != Variant::ARRAY || Array(runs_v).is_empty()) {
		errs.push_back("runs missing or empty");
		return errs;
	}
	const Array runs = runs_v;
	for (int i = 0; i < runs.size(); i++) {
		const Variant r_v = runs[i];
		if (r_v.get_type() != Variant::DICTIONARY) {
			errs.push_back(vformat("runs[%d] is not an object", i));
			continue;
		}
		const Dictionary r = r_v;
		const int64_t lv = _to_int(r.get("level", -1));
		if (lv < 0 || lv > CgameGPUSettingsDB::MAX_LEVEL) {
			errs.push_back(vformat("runs[%d].level out of range", i));
		}
		const Variant fm_v = r.get("frame_ms", Variant());
		if (fm_v.get_type() != Variant::DICTIONARY) {
			errs.push_back(vformat("runs[%d].frame_ms missing", i));
		} else {
			const Dictionary fm = fm_v;
			static const char *pk[3] = { "p50", "p95", "p99" };
			for (int k = 0; k < 3; k++) {
				const Variant v = fm.get(pk[k], Variant());
				if (!_is_number(v) || (double)v < 0.0) {
					errs.push_back(vformat("runs[%d].frame_ms.%s invalid", i, pk[k]));
				}
			}
		}
		if (_to_int(r.get("errors", 0)) < 0) {
			errs.push_back(vformat("runs[%d].errors negative", i));
		}
		const Variant cs_v = r.get("checksums", Array());
		if (cs_v.get_type() != Variant::ARRAY) {
			errs.push_back(vformat("runs[%d].checksums not an array", i));
		} else {
			const Array cs = cs_v;
			for (int c = 0; c < cs.size(); c++) {
				const Variant cv = cs[c];
				if (cv.get_type() != Variant::STRING || !_is_hex16(cv)) {
					errs.push_back(vformat("runs[%d] bad checksum", i));
					break;
				}
			}
		}
	}
	return errs;
}

// ------------------------------------------------------------------ perceptual hash

String CgameGPUMatrixDB::dhash(const Ref<Image> &p_image) {
	if (p_image.is_null() || p_image->is_empty()) {
		return "";
	}
	Ref<Image> g;
	g.instantiate();
	g->copy_from(p_image);
	if (g->is_compressed()) {
		g->decompress();
	}
	g->convert(Image::FORMAT_L8);
	g->resize(9, 8, Image::INTERPOLATE_LANCZOS);
	static const char *digits = "0123456789abcdef";
	String out;
	int nibble = 0;
	int bits = 0;
	for (int y = 0; y < 8; y++) {
		for (int x = 0; x < 8; x++) {
			const float l = g->get_pixel(x, y).r;
			const float r = g->get_pixel(x + 1, y).r;
			nibble = (nibble << 1) | (l > r ? 1 : 0);
			bits++;
			if (bits % 4 == 0) {
				out += String::chr(digits[nibble]);
				nibble = 0;
			}
		}
	}
	return out;
}

int CgameGPUMatrixDB::hash_distance(const String &p_a, const String &p_b) {
	if (!_is_hex16(p_a) || !_is_hex16(p_b)) {
		return -1;
	}
	int dist = 0;
	for (int i = 0; i < HASH_HEX_LEN; i++) {
		dist += POPCOUNT[_hex_value(p_a[i]) ^ _hex_value(p_b[i])];
	}
	return dist;
}

// ------------------------------------------------------------------ ingest

bool CgameGPUMatrixDB::add_report(const Variant &p_report, const String &p_source) {
	const PackedStringArray errs = validate_report(p_report);
	if (!errs.is_empty()) {
		rejected.push_back(vformat("%s: %s", p_source.is_empty() ? String("report") : p_source, String("; ").join(errs)));
		return false;
	}
	const Dictionary d = p_report;
	reports.push_back(d);
	built = false;
	return true;
}

bool CgameGPUMatrixDB::ingest_file(const String &p_path) {
	if (!FileAccess::exists(p_path)) {
		rejected.push_back(p_path + ": not found");
		return false;
	}
	const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(p_path));
	if (parsed.get_type() == Variant::NIL) {
		rejected.push_back(p_path + ": invalid JSON");
		return false;
	}
	return add_report(parsed, p_path);
}

int CgameGPUMatrixDB::ingest_dir(const String &p_dir_path) {
	int count = 0;
	Ref<DirAccess> dir = DirAccess::open(p_dir_path);
	if (dir.is_null()) {
		rejected.push_back(p_dir_path + ": cannot open directory");
		return 0;
	}
	for (const String &f : dir->get_files()) {
		if (f.begins_with("gpu_report_") && f.ends_with(".json")) {
			if (ingest_file(p_dir_path.path_join(f))) {
				count++;
			}
		}
	}
	return count;
}

String CgameGPUMatrixDB::_ref_key(const String &p_renderer, int p_level, int p_index) {
	return vformat("%s|%d|%d", p_renderer.to_lower(), p_level, p_index);
}

void CgameGPUMatrixDB::set_reference(const String &p_renderer, int p_level, int p_index, const String &p_checksum) {
	manual_refs[_ref_key(p_renderer, p_level, p_index)] = p_checksum;
	built = false;
}

void CgameGPUMatrixDB::clear() {
	reports.clear();
	rejected.clear();
	manual_refs.clear();
	references.clear();
	evals.clear();
	built = false;
}

// ------------------------------------------------------------------ analysis

void CgameGPUMatrixDB::build() {
	references.clear();
	evals.clear();
	Dictionary groups;
	for (int i = 0; i < reports.size(); i++) {
		const Dictionary rep = reports[i];
		const Dictionary sys = rep["system"];
		const String renderer = String(sys["renderer"]).to_lower();
		const Array runs = rep["runs"];
		for (int j = 0; j < runs.size(); j++) {
			const Dictionary r = runs[j];
			const Array cs = r.get("checksums", Array());
			for (int k = 0; k < cs.size(); k++) {
				const String key = _ref_key(renderer, (int)_to_int(r["level"]), k);
				if (!groups.has(key)) {
					groups[key] = Array();
				}
				Array g = groups[key];
				g.push_back(String(cs[k]));
			}
		}
	}
	for (const Variant &key : groups.keys()) {
		references[key] = _medoid(groups[key]);
	}
	for (const Variant &key : manual_refs.keys()) {
		references[key] = manual_refs[key];
	}
	for (int i = 0; i < reports.size(); i++) {
		evals.push_back(_evaluate(reports[i]));
	}
	built = true;
}

String CgameGPUMatrixDB::_medoid(const Array &p_hashes) {
	String best;
	int best_sum = 1 << 30;
	for (int i = 0; i < p_hashes.size(); i++) {
		int total = 0;
		for (int j = 0; j < p_hashes.size(); j++) {
			total += MAX(hash_distance(String(p_hashes[i]), String(p_hashes[j])), 0);
		}
		if (total < best_sum) {
			best_sum = total;
			best = String(p_hashes[i]);
		}
	}
	return best;
}

Dictionary CgameGPUMatrixDB::_evaluate(const Dictionary &p_report) const {
	const Dictionary sys = p_report["system"];
	const String adapter = sys["adapter"];
	const String vendor = String(sys["vendor"]).to_lower();
	const String renderer = String(sys["renderer"]).to_lower();
	const String family = CgameGPUSettingsDB::match_adapter(adapter, vendor)["family"];
	Array reasons;
	Array regs;
	int worst = 0;
	Dictionary level_p50;
	Dictionary level_p95;
	Dictionary blocked;
	if (p_report.has("completed") && !bool(p_report["completed"])) {
		reasons.push_back("crash");
	}
	const Array runs = p_report["runs"];
	for (int i = 0; i < runs.size(); i++) {
		const Dictionary r = runs[i];
		const int lv = (int)_to_int(r["level"]);
		const Dictionary fm = r["frame_ms"];
		level_p50[lv] = (double)fm["p50"];
		level_p95[lv] = (double)fm["p95"];
		if (_to_int(r.get("errors", 0)) > 0) {
			reasons.push_back(vformat("errors:L%d", lv));
		}
		const Array cs = r.get("checksums", Array());
		for (int k = 0; k < cs.size(); k++) {
			const String ref = references.get(_ref_key(renderer, lv, k), "");
			const int dist = hash_distance(String(cs[k]), ref);
			if (dist > tolerance) {
				Dictionary g;
				g["level"] = lv;
				g["index"] = k;
				g["distance"] = dist;
				regs.push_back(g);
				blocked[lv] = true;
				worst = MAX(worst, dist);
			}
		}
		if (blocked.has(lv)) {
			reasons.push_back(vformat("regression:L%d", lv));
		}
	}
	Dictionary out;
	out["adapter"] = adapter;
	out["vendor"] = vendor;
	out["family"] = family;
	out["driver"] = String(sys["driver"]);
	out["renderer"] = renderer;
	out["status"] = reasons.is_empty() ? "pass" : "fail";
	out["reasons"] = reasons;
	out["regressions"] = regs;
	out["worst_distance"] = worst;
	out["level_p50"] = level_p50;
	out["level_p95"] = level_p95;
	out["blocked"] = blocked;
	return out;
}

Array CgameGPUMatrixDB::evaluations() {
	if (!built) {
		build();
	}
	return evals;
}

double CgameGPUMatrixDB::_median(const Array &p_values) {
	if (p_values.is_empty()) {
		return 0.0;
	}
	Vector<double> a;
	for (int i = 0; i < p_values.size(); i++) {
		a.push_back((double)p_values[i]);
	}
	a.sort();
	const int n = a.size();
	if (n % 2 == 1) {
		return a[n >> 1];
	}
	return (a[(n >> 1) - 1] + a[n >> 1]) * 0.5;
}

Array CgameGPUMatrixDB::cells() {
	Dictionary map;
	const Array evs = evaluations();
	for (int i = 0; i < evs.size(); i++) {
		const Dictionary ev = evs[i];
		const String key = vformat("%s|%s|%s|%s", String(ev["vendor"]), String(ev["family"]), String(ev["driver"]), String(ev["renderer"]));
		if (!map.has(key)) {
			Dictionary c;
			c["vendor"] = ev["vendor"];
			c["family"] = ev["family"];
			c["driver"] = ev["driver"];
			c["renderer"] = ev["renderer"];
			c["reports"] = 0;
			c["pass"] = 0;
			c["fail"] = 0;
			c["_samples"] = Dictionary();
			c["reasons"] = Dictionary();
			map[key] = c;
		}
		Dictionary c = map[key];
		c["reports"] = (int)c["reports"] + 1;
		const String bucket = String(ev["status"]) == "pass" ? "pass" : "fail";
		c[bucket] = (int)c[bucket] + 1;
		Dictionary samples = c["_samples"];
		const Dictionary lp = ev["level_p50"];
		for (const Variant &lv : lp.keys()) {
			if (!samples.has(lv)) {
				samples[lv] = Array();
			}
			Array sa = samples[lv];
			sa.push_back((double)lp[lv]);
		}
		Dictionary rs = c["reasons"];
		const Array evr = ev["reasons"];
		for (int k = 0; k < evr.size(); k++) {
			const Variant reason = evr[k];
			rs[reason] = (int)rs.get(reason, 0) + 1;
		}
	}
	Array out;
	Array keys = map.keys();
	keys.sort();
	for (const Variant &key : keys) {
		Dictionary c = map[key];
		Dictionary samples = c["_samples"];
		Dictionary p50;
		int best60 = -1;
		Array lvls = samples.keys();
		lvls.sort();
		for (const Variant &lv : lvls) {
			const double med = _median(samples[lv]);
			p50[lv] = med;
			if (med <= target_ms) {
				best60 = MAX(best60, (int)lv);
			}
		}
		c.erase("_samples");
		c["level_p50"] = p50;
		c["max_level_60fps"] = best60;
		c["status"] = (int)c["fail"] > 0 ? "fail" : "pass";
		c["perf"] = best60 >= 0 ? "ok" : "slow";
		out.push_back(c);
	}
	return out;
}

Array CgameGPUMatrixDB::driver_failures() {
	Dictionary map;
	const Array evs = evaluations();
	for (int i = 0; i < evs.size(); i++) {
		const Dictionary ev = evs[i];
		const String key = vformat("%s|%s|%s", String(ev["vendor"]), String(ev["driver"]), String(ev["renderer"]));
		if (!map.has(key)) {
			Dictionary c;
			c["vendor"] = ev["vendor"];
			c["driver"] = ev["driver"];
			c["renderer"] = ev["renderer"];
			c["total"] = 0;
			c["fails"] = 0;
			c["families"] = Array();
			c["reasons"] = Dictionary();
			map[key] = c;
		}
		Dictionary c = map[key];
		c["total"] = (int)c["total"] + 1;
		if (String(ev["status"]) == "fail") {
			c["fails"] = (int)c["fails"] + 1;
			Array fams = c["families"];
			if (!fams.has(ev["family"])) {
				fams.push_back(ev["family"]);
			}
			Dictionary rs = c["reasons"];
			const Array evr = ev["reasons"];
			for (int k = 0; k < evr.size(); k++) {
				const Variant reason = evr[k];
				rs[reason] = (int)rs.get(reason, 0) + 1;
			}
		}
	}
	Vector<Dictionary> clusters;
	const Array map_keys = map.keys();
	for (int i = 0; i < map_keys.size(); i++) {
		Dictionary c = map[map_keys[i]];
		const double ratio = (double)(int)c["fails"] / (double)(int)c["total"];
		c["ratio"] = ratio;
		bool others_ok = false;
		for (int j = 0; j < map_keys.size(); j++) {
			if (j == i) {
				continue;
			}
			const Dictionary o = map[map_keys[j]];
			if (o["vendor"] == c["vendor"] && o["renderer"] == c["renderer"] && o["driver"] != c["driver"]) {
				if ((double)(int)o["fails"] / (double)(int)o["total"] < 0.5) {
					others_ok = true;
				}
			}
		}
		c["driver_specific"] = ratio >= 0.5 && others_ok;
		if ((int)c["fails"] > 0) {
			clusters.push_back(c);
		}
	}
	if (clusters.size() > 1) {
		SortArray<Dictionary, ClusterOrder> sorter;
		sorter.sort(clusters.ptrw(), clusters.size());
	}
	Array out;
	for (int i = 0; i < clusters.size(); i++) {
		out.push_back(clusters[i]);
	}
	return out;
}

Array CgameGPUMatrixDB::regressions() {
	Array out;
	const Array evs = evaluations();
	for (int i = 0; i < evs.size(); i++) {
		const Dictionary ev = evs[i];
		const Array regs = ev["regressions"];
		for (int k = 0; k < regs.size(); k++) {
			const Dictionary g = regs[k];
			Dictionary d;
			d["adapter"] = ev["adapter"];
			d["driver"] = ev["driver"];
			d["renderer"] = ev["renderer"];
			d["level"] = g["level"];
			d["index"] = g["index"];
			d["distance"] = g["distance"];
			out.push_back(d);
		}
	}
	return out;
}

// ------------------------------------------------------------------ recommendations

Dictionary CgameGPUMatrixDB::learned_data() {
	Dictionary data;
	const Array evs = evaluations();
	for (int i = 0; i < evs.size(); i++) {
		const Dictionary ev = evs[i];
		const String key = String(ev["adapter"]).strip_edges().to_lower();
		Dictionary entry = data.get(key, Dictionary());
		const Dictionary lp = ev["level_p50"];
		const Dictionary blocked = ev["blocked"];
		for (const Variant &lv : lp.keys()) {
			const String lk = itos((int)lv);
			Array samples = entry.get(lk, Array());
			const double ms = blocked.has(lv) ? BLOCKED_LEVEL_MS : (double)lp[lv];
			samples.push_back(ms);
			while (samples.size() > MAX_LEARNED_SAMPLES) {
				samples.pop_front();
			}
			entry[lk] = samples;
		}
		data[key] = entry;
	}
	return data;
}

bool CgameGPUMatrixDB::write_learned(const String &p_path) {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_string(JSON::stringify(learned_data()));
	return true;
}

// ------------------------------------------------------------------ export

String CgameGPUMatrixDB::csv_escape(const String &p_text) {
	if (p_text.contains(",") || p_text.contains("\"") || p_text.contains("\n")) {
		return "\"" + p_text.replace("\"", "\"\"") + "\"";
	}
	return p_text;
}

String CgameGPUMatrixDB::_md(const String &p_text) {
	return p_text.replace("|", "\\|");
}

String CgameGPUMatrixDB::to_csv() {
	PackedStringArray lines;
	lines.push_back("vendor,family,driver,renderer,reports,pass,fail,status,perf,max_level_60fps,p50_L0,p50_L1,p50_L2,p50_L3,reasons");
	const Array cs = cells();
	for (int i = 0; i < cs.size(); i++) {
		const Dictionary c = cs[i];
		const Dictionary p50 = c["level_p50"];
		PackedStringArray cols;
		cols.push_back(csv_escape(c["vendor"]));
		cols.push_back(csv_escape(c["family"]));
		cols.push_back(csv_escape(c["driver"]));
		cols.push_back(csv_escape(c["renderer"]));
		cols.push_back(String::num_int64((int)c["reports"]));
		cols.push_back(String::num_int64((int)c["pass"]));
		cols.push_back(String::num_int64((int)c["fail"]));
		cols.push_back(String(c["status"]));
		cols.push_back(String(c["perf"]));
		cols.push_back(String::num_int64((int)c["max_level_60fps"]));
		for (int lv = 0; lv < 4; lv++) {
			cols.push_back(p50.has(lv) ? vformat("%.2f", (double)p50[lv]) : String());
		}
		cols.push_back(csv_escape(String(" ").join(_reason_list(c["reasons"]))));
		lines.push_back(String(",").join(cols));
	}
	return String("\n").join(lines) + "\n";
}

String CgameGPUMatrixDB::to_markdown() {
	PackedStringArray out;
	out.push_back("# GPU compatibility matrix");
	out.push_back("");
	out.push_back(vformat("Reports: %d accepted, %d rejected. Visual tolerance: %d/64 bits.", reports.size(), rejected.size(), tolerance));
	out.push_back("");
	out.push_back("| Vendor | Family | Driver | Renderer | Reports | Pass | Fail | Perf | 60fps level | p50 L0 | L1 | L2 | L3 |");
	out.push_back("|---|---|---|---|---|---|---|---|---|---|---|---|---|");
	const Array cs = cells();
	for (int i = 0; i < cs.size(); i++) {
		const Dictionary c = cs[i];
		const Dictionary p50 = c["level_p50"];
		PackedStringArray row;
		row.push_back(_md(c["vendor"]));
		row.push_back(_md(c["family"]));
		row.push_back(_md(c["driver"]));
		row.push_back(_md(c["renderer"]));
		row.push_back(String::num_int64((int)c["reports"]));
		row.push_back(String::num_int64((int)c["pass"]));
		row.push_back(String::num_int64((int)c["fail"]));
		row.push_back(String(c["perf"]));
		row.push_back(String::num_int64((int)c["max_level_60fps"]));
		for (int lv = 0; lv < 4; lv++) {
			row.push_back(p50.has(lv) ? vformat("%.1f", (double)p50[lv]) : String("-"));
		}
		out.push_back("| " + String(" | ").join(row) + " |");
	}
	const Array drv = driver_failures();
	out.push_back("");
	out.push_back("## Driver failures");
	out.push_back("");
	if (drv.is_empty()) {
		out.push_back("None.");
	}
	for (int i = 0; i < drv.size(); i++) {
		const Dictionary d = drv[i];
		out.push_back(vformat("- %s driver %s (%s): %d/%d failed%s - %s", String(d["vendor"]), String(d["driver"]), String(d["renderer"]),
				(int)d["fails"], (int)d["total"], bool(d["driver_specific"]) ? String(" (driver-specific)") : String(),
				String(", ").join(_reason_list(d["reasons"]))));
	}
	out.push_back("");
	out.push_back("## Rendering regressions");
	out.push_back("");
	const Array regs = regressions();
	if (regs.is_empty()) {
		out.push_back("None.");
	}
	for (int i = 0; i < regs.size(); i++) {
		const Dictionary g = regs[i];
		out.push_back(vformat("- %s / %s / %s: level %d frame %d, distance %d", String(g["adapter"]), String(g["driver"]),
				String(g["renderer"]), (int)g["level"], (int)g["index"], (int)g["distance"]));
	}
	if (!rejected.is_empty()) {
		out.push_back("");
		out.push_back("## Rejected reports");
		out.push_back("");
		for (const String &r : rejected) {
			out.push_back("- " + _md(r));
		}
	}
	return String("\n").join(out) + "\n";
}

void CgameGPUMatrixDB::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tolerance", "tolerance"), &CgameGPUMatrixDB::set_tolerance);
	ClassDB::bind_method(D_METHOD("get_tolerance"), &CgameGPUMatrixDB::get_tolerance);
	ClassDB::bind_method(D_METHOD("set_target_ms", "target_ms"), &CgameGPUMatrixDB::set_target_ms);
	ClassDB::bind_method(D_METHOD("get_target_ms"), &CgameGPUMatrixDB::get_target_ms);
	ClassDB::bind_method(D_METHOD("get_reports"), &CgameGPUMatrixDB::get_reports);
	ClassDB::bind_method(D_METHOD("get_rejected"), &CgameGPUMatrixDB::get_rejected);

	ClassDB::bind_static_method("CgameGPUMatrixDB", D_METHOD("validate_report", "report"), &CgameGPUMatrixDB::validate_report);
	ClassDB::bind_static_method("CgameGPUMatrixDB", D_METHOD("dhash", "image"), &CgameGPUMatrixDB::dhash);
	ClassDB::bind_static_method("CgameGPUMatrixDB", D_METHOD("hash_distance", "a", "b"), &CgameGPUMatrixDB::hash_distance);
	ClassDB::bind_static_method("CgameGPUMatrixDB", D_METHOD("csv_escape", "text"), &CgameGPUMatrixDB::csv_escape);

	ClassDB::bind_method(D_METHOD("add_report", "report", "source"), &CgameGPUMatrixDB::add_report, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("ingest_file", "path"), &CgameGPUMatrixDB::ingest_file);
	ClassDB::bind_method(D_METHOD("ingest_dir", "dir_path"), &CgameGPUMatrixDB::ingest_dir);
	ClassDB::bind_method(D_METHOD("set_reference", "renderer", "level", "index", "checksum"), &CgameGPUMatrixDB::set_reference);
	ClassDB::bind_method(D_METHOD("build"), &CgameGPUMatrixDB::build);
	ClassDB::bind_method(D_METHOD("evaluations"), &CgameGPUMatrixDB::evaluations);
	ClassDB::bind_method(D_METHOD("cells"), &CgameGPUMatrixDB::cells);
	ClassDB::bind_method(D_METHOD("driver_failures"), &CgameGPUMatrixDB::driver_failures);
	ClassDB::bind_method(D_METHOD("regressions"), &CgameGPUMatrixDB::regressions);
	ClassDB::bind_method(D_METHOD("learned_data"), &CgameGPUMatrixDB::learned_data);
	ClassDB::bind_method(D_METHOD("write_learned", "path"), &CgameGPUMatrixDB::write_learned, DEFVAL("user://gpu_learned.json"));
	ClassDB::bind_method(D_METHOD("to_csv"), &CgameGPUMatrixDB::to_csv);
	ClassDB::bind_method(D_METHOD("to_markdown"), &CgameGPUMatrixDB::to_markdown);
	ClassDB::bind_method(D_METHOD("clear"), &CgameGPUMatrixDB::clear);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "tolerance", PROPERTY_HINT_RANGE, "0,64,1"), "set_tolerance", "get_tolerance");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "target_ms", PROPERTY_HINT_RANGE, "1,1000,0.1,or_greater,suffix:ms"), "set_target_ms", "get_target_ms");

	BIND_CONSTANT(SCHEMA_VERSION);
	BIND_CONSTANT(HASH_HEX_LEN);
	BIND_CONSTANT(DEFAULT_TOLERANCE);
	BIND_CONSTANT(MAX_LEARNED_SAMPLES);
}
