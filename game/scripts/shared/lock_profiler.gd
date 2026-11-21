extends RefCounted
## Lock contention profiler: ProfiledMutex wraps Mutex and records acquisition count, contended
## acquisitions, wait time (try_lock spin + timing), hold time and last owner thread id. A global
## registry feeds report() (sorted by total wait). sync_point() times arbitrary blocking calls
## (e.g. RenderingServer.force_sync, readbacks) and flags long CPU/GPU sync stalls.
##
## Concepts only (original GDScript): lock contention sampling as in Tracy / Unreal Insights lock
## traces and the standard try-lock-then-block instrumentation pattern.

## Spin pause between try_lock attempts (microseconds).
const SPIN_USEC := 20

class ProfiledMutex:
	var name: String = ""
	var _mutex: Mutex = Mutex.new()
	var _depth: int = 0
	var _hold_start_us: int = 0
	var owner_thread_id: int = 0
	var acquisitions: int = 0
	var contended: int = 0
	var total_wait_us: int = 0
	var max_wait_us: int = 0
	var total_hold_us: int = 0
	var max_hold_us: int = 0

	func lock() -> void:
		var t0 := Time.get_ticks_usec()
		var was_contended := false
		while not _mutex.try_lock():
			was_contended = true
			OS.delay_usec(SPIN_USEC)
		var waited := Time.get_ticks_usec() - t0
		# Statistics are only touched while the mutex is held, so they need no extra lock.
		if _depth == 0:
			_hold_start_us = Time.get_ticks_usec()
			owner_thread_id = OS.get_thread_caller_id()
			acquisitions += 1
			if was_contended:
				contended += 1
				total_wait_us += waited
				max_wait_us = maxi(max_wait_us, waited)
		_depth += 1

	func try_lock() -> bool:
		if not _mutex.try_lock():
			return false
		if _depth == 0:
			_hold_start_us = Time.get_ticks_usec()
			owner_thread_id = OS.get_thread_caller_id()
			acquisitions += 1
		_depth += 1
		return true

	func unlock() -> void:
		_depth -= 1
		if _depth == 0:
			var held := Time.get_ticks_usec() - _hold_start_us
			total_hold_us += held
			max_hold_us = maxi(max_hold_us, held)
		_mutex.unlock()

	func stats() -> Dictionary:
		return {"name": name, "acquisitions": acquisitions, "contended": contended,
			"total_wait_ms": total_wait_us / 1000.0, "max_wait_ms": max_wait_us / 1000.0,
			"total_hold_ms": total_hold_us / 1000.0, "max_hold_ms": max_hold_us / 1000.0,
			"owner_thread_id": owner_thread_id}

	func reset() -> void:
		acquisitions = 0
		contended = 0
		total_wait_us = 0
		max_wait_us = 0
		total_hold_us = 0
		max_hold_us = 0


static var _registry: Array[ProfiledMutex] = []
static var _registry_lock: Mutex = Mutex.new()
static var _syncs: Dictionary = {}
static var _sync_lock: Mutex = Mutex.new()
## Sync points slower than this are reported by long_syncs().
static var long_sync_threshold_ms: float = 2.0


static func create(mutex_name: String) -> ProfiledMutex:
	var m := ProfiledMutex.new()
	m.name = mutex_name
	_registry_lock.lock()
	_registry.append(m)
	_registry_lock.unlock()
	return m


static func clear() -> void:
	_registry_lock.lock()
	_registry.clear()
	_registry_lock.unlock()
	_sync_lock.lock()
	_syncs.clear()
	_sync_lock.unlock()


## Mutex stats sorted by total wait time (most contended first).
static func report() -> Array:
	var rows: Array = []
	_registry_lock.lock()
	for m in _registry:
		rows.append(m.stats())
	_registry_lock.unlock()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["total_wait_ms"] == b["total_wait_ms"]:
			return a["total_hold_ms"] > b["total_hold_ms"]
		return a["total_wait_ms"] > b["total_wait_ms"])
	return rows


## Runs `callable`, timing it as a CPU/GPU sync point. Returns the callable's result.
static func sync_point(point_name: String, callable: Callable) -> Variant:
	var t0 := Time.get_ticks_usec()
	var r: Variant = callable.call()
	var us := Time.get_ticks_usec() - t0
	_sync_lock.lock()
	var s: Dictionary = _syncs.get(point_name, {"name": point_name, "count": 0, "total_ms": 0.0, "max_ms": 0.0, "long_count": 0})
	s["count"] = int(s["count"]) + 1
	s["total_ms"] = float(s["total_ms"]) + us / 1000.0
	s["max_ms"] = maxf(float(s["max_ms"]), us / 1000.0)
	if us / 1000.0 >= long_sync_threshold_ms:
		s["long_count"] = int(s["long_count"]) + 1
	_syncs[point_name] = s
	_sync_lock.unlock()
	return r


static func sync_report() -> Array:
	var rows: Array = []
	_sync_lock.lock()
	for k in _syncs:
		rows.append((_syncs[k] as Dictionary).duplicate())
	_sync_lock.unlock()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total_ms"] > b["total_ms"])
	return rows


## Names of sync points that exceeded the long-sync threshold at least once.
static func long_syncs() -> PackedStringArray:
	var out := PackedStringArray()
	for r in sync_report():
		if int(r["long_count"]) > 0:
			out.append(str(r["name"]))
	return out
