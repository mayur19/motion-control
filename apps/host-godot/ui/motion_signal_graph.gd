class_name MotionSignalGraph
extends Control

const BACKGROUND := Color("111a25")
const GRID := Color("2a3a4d")
const ACCEL := Color("54d6a7")
const GYRO := Color("f6b85f")

@export var history_capacity := 120

var _acceleration: Array[float] = []
var _gyroscope: Array[float] = []


func _ready() -> void:
	custom_minimum_size = Vector2(240, 70)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push_sample(acceleration: Array, angular_velocity: Array) -> void:
	_acceleration.append(_magnitude(acceleration))
	_gyroscope.append(_magnitude(angular_velocity))
	while _acceleration.size() > history_capacity:
		_acceleration.pop_front()
	while _gyroscope.size() > history_capacity:
		_gyroscope.pop_front()
	queue_redraw()


func clear() -> void:
	_acceleration.clear()
	_gyroscope.clear()
	queue_redraw()


func history_size() -> int:
	return maxi(_acceleration.size(), _gyroscope.size())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
	for fraction in [0.25, 0.5, 0.75]:
		var y := size.y * float(fraction)
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
	_draw_series(_acceleration, 25.0, ACCEL)
	_draw_series(_gyroscope, 12.0, GYRO)


func _draw_series(values: Array[float], maximum: float, color: Color) -> void:
	if values.size() < 2:
		return
	var points := PackedVector2Array()
	for index in values.size():
		var x := float(index) / float(history_capacity - 1) * size.x
		var normalized: float = clampf(values[index] / maximum, 0.0, 1.0)
		points.append(Vector2(x, size.y - normalized * size.y))
	draw_polyline(points, color, 1.5, true)


func _magnitude(values: Array) -> float:
	if values.size() < 3:
		return 0.0
	return sqrt(
		float(values[0]) * float(values[0])
		+ float(values[1]) * float(values[1])
		+ float(values[2]) * float(values[2])
	)
