class_name ClockSynchronizer
extends RefCounted

const MAX_SAMPLES := 32
const SMOOTHING_ALPHA := 0.2
const LARGE_STEP_NS := 5_000_000.0
const MIN_DRIFT_BASELINE_NS := 1_000_000_000.0

var _samples: Array[Dictionary] = []
var _offset_ns := 0.0
var _rtt_ns := 0.0
var _drift_ppm := 0.0
var _initialized := false
var _previous_selected_offset_ns := 0.0
var _previous_selected_host_ns := 0.0
var _last_converted_host_ns := -1
var _backward_corrections := 0


func record_exchange(t1_host_ns: int, t2_controller_ns: int, t3_controller_ns: int, t4_host_ns: int) -> bool:
	if t1_host_ns <= 0 or t2_controller_ns <= 0 or t3_controller_ns < t2_controller_ns or t4_host_ns < t1_host_ns:
		return false
	var rtt_ns := float(t4_host_ns - t1_host_ns) - float(t3_controller_ns - t2_controller_ns)
	if rtt_ns < 0.0:
		return false
	# Positive offset means the controller clock is ahead of the host clock.
	var offset_ns := (
		float(t2_controller_ns - t1_host_ns) + float(t3_controller_ns - t4_host_ns)
	) / 2.0
	var host_midpoint_ns := (float(t1_host_ns) + float(t4_host_ns)) / 2.0
	_samples.append({"rtt_ns": rtt_ns, "offset_ns": offset_ns, "host_ns": host_midpoint_ns})
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
	_recompute()
	return true


func controller_to_host(controller_ns: int) -> int:
	var converted := controller_ns - int(round(_offset_ns))
	if _last_converted_host_ns >= 0 and converted <= _last_converted_host_ns:
		converted = _last_converted_host_ns + 1
		_backward_corrections += 1
	_last_converted_host_ns = converted
	return converted


func snapshot() -> Dictionary:
	return {
		"initialized": _initialized,
		"samples": _samples.size(),
		"rtt_ms": _rtt_ns / 1_000_000.0,
		"offset_ms": _offset_ns / 1_000_000.0,
		"drift_ppm": _drift_ppm,
		"backward_corrections": _backward_corrections,
	}


func _recompute() -> void:
	var ranked := _samples.duplicate(true)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.rtt_ns) < float(right.rtt_ns)
	)
	var preferred_count := maxi(1, int(ceil(ranked.size() / 4.0)))
	var preferred := ranked.slice(0, preferred_count)
	preferred.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.offset_ns) < float(right.offset_ns)
	)
	var selected: Dictionary = preferred[preferred.size() / 2]
	var selected_offset := float(selected.offset_ns)
	var selected_host := float(selected.host_ns)
	if not _initialized:
		_offset_ns = selected_offset
		_initialized = true
	elif absf(selected_offset - _offset_ns) > LARGE_STEP_NS:
		# A discontinuity is surfaced immediately rather than hidden by smoothing.
		_offset_ns = selected_offset
	else:
		_offset_ns = lerpf(_offset_ns, selected_offset, SMOOTHING_ALPHA)
	_rtt_ns = float(selected.rtt_ns)
	if _previous_selected_host_ns == 0.0:
		_previous_selected_offset_ns = selected_offset
		_previous_selected_host_ns = selected_host
	elif selected_host - _previous_selected_host_ns >= MIN_DRIFT_BASELINE_NS:
		_drift_ppm = (
			(selected_offset - _previous_selected_offset_ns)
			/ (selected_host - _previous_selected_host_ns)
			* 1_000_000.0
		)
		_previous_selected_offset_ns = selected_offset
		_previous_selected_host_ns = selected_host
