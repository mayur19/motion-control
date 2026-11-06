class_name DetectorPipeline
extends RefCounted

## TMB-029 detector boundary shared by live play and offline replay. It
## consumes only `MotionIngest.normalized_sample_received` samples (calibrated,
## common racket frame), so live and replay run the identical implementation
## for identical input. TMB-032 replaces the placeholder detector below.

signal event_detected(event: Dictionary)
## Each accepted normalized sample with its preprocessing output (TMB-031).
signal sample_preprocessed(sample: Dictionary, prepared: Dictionary)

const Preprocessor = preload("res://detection/motion_preprocessor.gd")
const PROBE := "angular_speed_probe"
const PROBE_VERSION := 1
const DEFAULTS := {"detector": PROBE, "threshold_rad_s": 3.5, "refractory_ms": 700}

var _config: Dictionary = DEFAULTS.duplicate(true)
var _preprocessor := Preprocessor.new()
## controller_id -> {above: bool, last_event_ns: int}
var _state: Dictionary = {}


## Validates and applies a full configuration; returns {ok, error?}.
func configure(config: Dictionary) -> Dictionary:
	var preprocessor := Preprocessor.new()
	var preprocessing: Variant = config.get("preprocessing", {})
	if typeof(preprocessing) != TYPE_DICTIONARY:
		return {"ok": false, "error": "preprocessing must be an object"}
	var preprocessed := preprocessor.configure(preprocessing)
	if not bool(preprocessed.ok):
		return {"ok": false, "error": "preprocessing: %s" % str(preprocessed.error)}
	var merged := DEFAULTS.duplicate(true)
	merged.merge(config, true)
	merged.erase("preprocessing")
	if str(merged.detector) != PROBE:
		return {"ok": false, "error": "unknown detector %s" % str(merged.detector)}
	var threshold := float(merged.threshold_rad_s)
	var refractory := int(merged.refractory_ms)
	if not is_finite(threshold) or threshold <= 0.0 or refractory < 0:
		return {"ok": false, "error": "threshold_rad_s must be > 0 and refractory_ms >= 0"}
	_config = {"detector": PROBE, "threshold_rad_s": threshold, "refractory_ms": refractory}
	_preprocessor = preprocessor
	_state = {}
	return {"ok": true}


## Everything needed to reproduce a run: detector name, version and config.
func describe() -> Dictionary:
	return {
		"detector": str(_config.detector),
		"version": PROBE_VERSION,
		"config": _config.duplicate(true),
		"preprocessing": _preprocessor.describe(),
	}


func bind_ingest(ingest: MotionIngest) -> void:
	if not ingest.normalized_sample_received.is_connected(_on_normalized_sample):
		ingest.normalized_sample_received.connect(_on_normalized_sample)


func reset() -> void:
	_state = {}
	_preprocessor.reset()


## Placeholder (not the TMB-032 detector): one event per rising crossing of
## preprocessed (TMB-031) angular speed above the threshold, outside the
## refractory window.
func process(sample: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var prepared := _preprocessor.process(sample)
	if not bool(prepared.ok):
		return events  # dropped: duplicate/out-of-order, non-finite or uncalibrated
	sample_preprocessed.emit(sample, prepared)
	var speed := float(prepared.preprocessed.angular_speed)
	var controller_id := int(sample.get("controller_id", 0))
	var sensor_ns := int(sample.get("sensor_monotonic_ns", 0))
	var state: Dictionary = _state.get(controller_id, {"above": false, "last_event_ns": -1})
	var above := speed >= float(_config.threshold_rad_s)
	var refractory_ns := int(_config.refractory_ms) * 1_000_000
	var outside_refractory := (
		int(state.last_event_ns) < 0 or sensor_ns - int(state.last_event_ns) >= refractory_ns
	)
	if above and not bool(state.above) and outside_refractory:
		events.append({
			"detector": str(_config.detector),
			"controller_id": controller_id,
			"sequence": int(sample.get("sequence", 0)),
			"sensor_monotonic_ns": sensor_ns,
			"arrival_monotonic_ns": int(sample.get("arrival_monotonic_ns", 0)),
			"angular_speed_rad_s": speed,
		})
		state.last_event_ns = sensor_ns
	state.above = above
	_state[controller_id] = state
	return events


func _on_normalized_sample(sample: Dictionary) -> void:
	for event in process(sample):
		event_detected.emit(event)
