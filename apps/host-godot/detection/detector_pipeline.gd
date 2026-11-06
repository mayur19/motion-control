class_name DetectorPipeline
extends RefCounted

## Detector boundary shared by live play and offline replay (TMB-029). It
## consumes only `MotionIngest.normalized_sample_received` samples, runs
## MotionPreprocessor (TMB-031) and then the configured detector:
## `early_rise` (TMB-032, default) or the `angular_speed_probe` reference.
## Identical input and configuration give identical events.

signal event_detected(event: Dictionary)
## Each accepted normalized sample with its preprocessing output (TMB-031).
signal sample_preprocessed(sample: Dictionary, prepared: Dictionary)

const Preprocessor = preload("res://detection/motion_preprocessor.gd")
const EarlyRise = preload("res://detection/early_swing_detector.gd")
const Probe = preload("res://detection/angular_speed_probe.gd")
const DEFAULTS := {"detector": EarlyRise.NAME}

var _preprocessor := Preprocessor.new()
var _detector: RefCounted = EarlyRise.new()


## Validates and applies a full configuration: `detector` selects the
## implementation, `preprocessing` configures the filter, every other key is
## the detector's own configuration. Returns {ok, error?}.
func configure(config: Dictionary) -> Dictionary:
	var preprocessing: Variant = config.get("preprocessing", {})
	if typeof(preprocessing) != TYPE_DICTIONARY:
		return {"ok": false, "error": "preprocessing must be an object"}
	var preprocessor := Preprocessor.new()
	var preprocessed := preprocessor.configure(preprocessing)
	if not bool(preprocessed.ok):
		return {"ok": false, "error": "preprocessing: %s" % str(preprocessed.error)}
	var name := str(config.get("detector", DEFAULTS.detector))
	var detector: RefCounted
	match name:
		EarlyRise.NAME:
			detector = EarlyRise.new()
		Probe.NAME:
			detector = Probe.new()
		_:
			return {"ok": false, "error": "unknown detector %s" % name}
	var detector_config := config.duplicate(true)
	detector_config.erase("detector")
	detector_config.erase("preprocessing")
	var configured: Dictionary = detector.configure(detector_config)
	if not bool(configured.ok):
		return configured
	_preprocessor = preprocessor
	_detector = detector
	return {"ok": true}


## Everything needed to reproduce a run: detector, version, config and the
## preprocessing stage.
func describe() -> Dictionary:
	var description: Dictionary = _detector.describe()
	description["preprocessing"] = _preprocessor.describe()
	return description


func bind_ingest(ingest: MotionIngest) -> void:
	if not ingest.normalized_sample_received.is_connected(_on_normalized_sample):
		ingest.normalized_sample_received.connect(_on_normalized_sample)


func reset() -> void:
	_preprocessor.reset()
	_detector.reset()


func process(sample: Dictionary) -> Array[Dictionary]:
	var prepared := _preprocessor.process(sample)
	if not bool(prepared.ok):
		var none: Array[Dictionary] = []
		return none  # dropped: duplicate/out-of-order, non-finite or uncalibrated
	sample_preprocessed.emit(sample, prepared)
	return _detector.process(prepared)


func _on_normalized_sample(sample: Dictionary) -> void:
	for event in process(sample):
		event_detected.emit(event)
