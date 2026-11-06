class_name SoakTelemetry
extends Node

@export var interval_seconds := 1.0

var _ingest: MotionIngest
var _clocks: HostClockService
var _connections: ControllerConnectionManager
var _logger: SessionLogger
var _elapsed := 0.0
var _frame_times_ms: Array[float] = []
var _sample_ages: Dictionary = {}
var _sample_counts: Dictionary = {}


func attach(
	ingest: MotionIngest,
	clocks: HostClockService,
	connections: ControllerConnectionManager,
	logger: SessionLogger
) -> void:
	_ingest = ingest
	_clocks = clocks
	_connections = connections
	_logger = logger
	if not ingest.sample_received.is_connected(_on_sample_received):
		ingest.sample_received.connect(_on_sample_received)
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_frame_times_ms.append(delta * 1000.0)
	_elapsed += delta
	if _elapsed >= interval_seconds:
		_emit_interval()


func _on_sample_received(sample: Dictionary) -> void:
	var controller_id := int(sample.controller_id)
	_sample_counts[controller_id] = int(_sample_counts.get(controller_id, 0)) + 1
	var age := float(sample.get("adjusted_sample_age_ms", -1.0))
	if age >= 0.0:
		if not _sample_ages.has(controller_id):
			_sample_ages[controller_id] = []
		_sample_ages[controller_id].append(age)


func _emit_interval() -> void:
	var ingest_snapshot := _ingest.snapshot()
	var frame_summary := _summary(_frame_times_ms)
	for raw_controller_id in ingest_snapshot.controllers:
		var controller_id := int(raw_controller_id)
		var network: Dictionary = ingest_snapshot.controllers[raw_controller_id]
		var connection := _connections.state_for(controller_id)
		var clock := _clocks.metrics_for(controller_id)
		var fields := {
			"controller_id": controller_id,
			"interval_seconds": _elapsed,
			"actual_sensor_hz": int(connection.get("actual_sample_hz", 0)),
			"received_motion_hz": int(_sample_counts.get(controller_id, 0)) / _elapsed,
			"loss_packets": int(network.loss),
			"duplicate_packets": int(network.duplicates),
			"reordered_packets": int(network.reordered),
			"network_jitter_ms": float(network.jitter_ms),
			"clock_rtt_ms": float(clock.get("rtt_ms", -1.0)),
			"clock_offset_ms": float(clock.get("offset_ms", 0.0)),
			"clock_drift_ppm": float(clock.get("drift_ppm", 0.0)),
			"sample_age_ms": _summary(_sample_ages.get(controller_id, [])),
			"host_frame_ms": frame_summary,
			"host_static_memory_bytes": int(
				Performance.get_monitor(Performance.MEMORY_STATIC)
			),
			"queue_size": int(ingest_snapshot.queue_size),
			"queue_drops": int(ingest_snapshot.queue_drops),
			"connection_state": str(connection.state),
		}
		_logger.log_event("soak_metrics", fields)
	_elapsed = 0.0
	_frame_times_ms.clear()
	_sample_ages.clear()
	_sample_counts.clear()


func _summary(raw_values: Array) -> Dictionary:
	if raw_values.is_empty():
		return {"count": 0, "median": -1.0, "p95": -1.0, "p99": -1.0, "maximum": -1.0}
	var values: Array = raw_values.duplicate()
	values.sort()
	return {
		"count": values.size(),
		"median": float(values[(values.size() - 1) / 2]),
		"p95": _nearest_rank(values, 0.95),
		"p99": _nearest_rank(values, 0.99),
		"maximum": float(values[-1]),
	}


## Nearest-rank percentile of an already sorted array.
func _nearest_rank(sorted_values: Array, quantile: float) -> float:
	var index := mini(sorted_values.size() - 1, ceili(sorted_values.size() * quantile) - 1)
	return float(sorted_values[maxi(0, index)])
