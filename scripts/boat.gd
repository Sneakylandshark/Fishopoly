extends Node3D
## A boat on the water. set_kind() picks its Kenney model (see MODELS); kinds with no model keep the coloured greybox.
## It sails bow-first like a real boat: it can only move the way its front points, so to change direction it turns
## in an arc (never slides sideways). It leaves a small wake (the Wake node) while moving. When it has no order it
## lies at anchor: it swings slowly about and creeps back and forth over the day instead of only bobbing.
## It can also sink.

## Sent when a sail_to() order arrives (a newer order replaces the old one, and the old one never sends this)
class Order extends RefCounted:
	signal finished

@export var hull_color := Color(0.85, 0.85, 0.8)
## How tight the boat can turn, in metres, per metre of boat length (bigger = wider arcs)
@export var turn_radius_per_length := 0.9
## Below this speed (metres a second) there is no wake
@export var wake_min_speed := 0.6
## How far an anchored boat swings to either side, in radians (main.gd sets this per mooring; docks are small)
@export var swing := 0.35
## How far an anchored boat creeps forward and back, in metres
@export var surge := 0.4

const WATER := "res://assets/kenney/watercraft-pack/"
const PIRATE := "res://assets/kenney/pirate-kit/"
# Which model each kind of boat uses, and its scale (about 3 m long for the small boats, so they fit their berths)
const MODELS := {
	"fish": [WATER + "boat-fishing-small.glb", 0.78],
	"crab": [WATER + "boat-tug-b.glb", 1.0],
	"cray": [WATER + "boat-tug-a.glb", 0.85],
	"smuggler": [WATER + "boat-speed-a.glb", 0.9],
	"barge": [WATER + "boat-tow-a.glb", 0.6],
	# Small enough to fit under the sea cave roof when hidden
	"pirate": [PIRATE + "ship-pirate-small.glb", 0.3],
	"whale": [PIRATE + "ship-medium.glb", 0.4],
	"mail": [WATER + "boat-sail-a.glb", 0.8],
	"visitor": [WATER + "ship-small.glb", 0.42],
	# The oil rig model lives with the building models (scenes/buildings/rig.tscn)
	"rig": ["res://scenes/buildings/rig.tscn", 1.0],
}

var kind := ""
var bob_phase := 0.0
var bob_strength := 0.08
var model: Node3D

# Boat length in metres (measured from the model in set_kind; the greybox hull is 2.8)
var length := 2.8
# Current forward speed in metres a second (always forward: boats never slide sideways)
var speed := 0.0
# How fast it is turning, in radians a second (used to lean into turns)
var turn_speed := 0.0

# The sailing order: where to, by when, and how fast it planned to go
var order: Order
var target := Vector3.ZERO
var deadline := 0.0
var planned_speed := 1.0

# Anchor: where it stopped, the heading it stopped on, and when (the drift fades in after stopping)
var anchored := false
var anchor_pos := Vector3.ZERO
var anchor_heading := 0.0
var anchor_time := 0.0
# The last position this script wrote, so it notices when other code moves the boat directly
var last_written := Vector3.INF
var sinking := false
# Each boat drifts a little out of step with the others
var drift_phase := 0.0


func _ready() -> void:
	bob_phase = randf() * TAU
	drift_phase = randf() * TAU
	if kind == "":
		set_color(hull_color)
	_place_wake()


func set_kind(k: String) -> void:
	# Swaps the model only when the kind changes (this is called every time the boats are placed)
	if k == kind:
		return
	kind = k
	if model:
		model.queue_free()
		model = null
	if not MODELS.has(k):
		$Hull.visible = true
		$Cabin.visible = true
		length = 2.8
		_place_wake()
		return
	model = load(MODELS[k][0]).instantiate()
	var s: float = MODELS[k][1]
	model.scale = Vector3(s, s, s)
	add_child(model)
	$Hull.visible = false
	$Cabin.visible = false
	# Measure the model so the turning circle and the wake fit the boat's real size
	var box := _model_box(model, Transform3D(Basis.from_scale(model.scale), Vector3.ZERO))
	if box.size.z > 0.1:
		length = box.size.z
	_place_wake()


func _model_box(node: Node, xform: Transform3D) -> AABB:
	# The model's size along its length, from all its meshes
	var box := AABB()
	var first := true
	for c in node.get_children():
		var t: Transform3D = xform
		if c is Node3D:
			t = xform * c.transform
		if c is MeshInstance3D and c.mesh:
			var b: AABB = t * c.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var inner := _model_box(c, t)
		if inner.size != Vector3.ZERO:
			box = inner if first else box.merge(inner)
			first = false
	return box


func _place_wake() -> void:
	# The wake starts at the stern (the back of the boat; the front points along +Z)
	if has_node("Wake"):
		$Wake.position = Vector3(0, 0.06, -length * 0.45)


func set_color(c: Color) -> void:
	# Only the greybox (kinds with no model, like oil rigs) uses a colour
	hull_color = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	$Hull.material_override = mat


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


func sail_to(to: Vector3, seconds: float) -> Order:
	# A new order replaces the old one, so two moves never fight over the boat
	order = Order.new()
	target = Vector3(to.x, position.y, to.z)
	seconds = max(seconds, 0.2)
	deadline = _now() + seconds
	anchored = false
	planned_speed = max(_path_estimate() / seconds, 0.5)
	return order


func head_out(metres: float, seconds: float) -> Order:
	# Sail a little way straight ahead (used when the boats set off each morning)
	return sail_to(position + forward() * metres, seconds)


func sink(seconds: float) -> Tween:
	sinking = true
	order = null
	speed = 0.0
	if has_node("Wake"):
		$Wake.emitting = false
	var t := create_tween()
	t.tween_property(self, "position:y", -2.0, seconds)
	t.parallel().tween_property(self, "rotation:z", 1.2, seconds)
	return t


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _turn_radius() -> float:
	return max(1.5, length * turn_radius_per_length)


func _angle_to_target() -> float:
	# How far the boat must turn to point at the target (negative = to its right)
	var to := target - position
	return wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI)


func _path_estimate() -> float:
	# Rough length of the arc-then-straight path still to sail
	var d := Vector2(target.x - position.x, target.z - position.z).length()
	var r: float = min(_turn_radius(), d * 0.5)
	return d + abs(_angle_to_target()) * r


func _process(delta: float) -> void:
	if not sinking:
		if position != last_written:
			# Other code put the boat somewhere new: it lies at anchor there from now on
			if order == null:
				_drop_anchor()
		if order != null:
			_steer(delta)
		else:
			_drift()
		last_written = position
	_bob(delta)
	if has_node("Wake"):
		$Wake.emitting = speed > wake_min_speed and visible and not sinking


func _steer(delta: float) -> void:
	var to := Vector2(target.x - position.x, target.z - position.z)
	var d := to.length()
	# Close enough: stop there and drop anchor
	if d < 0.15 + speed * delta:
		position.x = target.x
		position.z = target.z
		speed = 0.0
		turn_speed = 0.0
		var done := order
		order = null
		_drop_anchor()
		done.finished.emit()
		return
	var angle := _angle_to_target()
	# Speed: whatever gets it there on time (with a margin for slowing in the turns and at the berth), but no more than 4x the planned speed
	var time_left: float = max(deadline - _now(), 0.25)
	var want: float = clamp(_path_estimate() * 1.3 / time_left, 0.4, planned_speed * 4.0)
	# Slow down while pointing well away from the target, so it turns in a tighter arc
	want *= lerp(1.0, 0.4, clamp(abs(angle) / PI, 0.0, 1.0))
	# Ease off coming into the berth
	var accel: float = max(2.0, planned_speed * 3.0)
	want = min(want, sqrt(2.0 * accel * d) + 0.3)
	speed = move_toward(speed, want, accel * delta)
	# Turn: a boat turns only while moving, and can turn no tighter than its turning circle.
	# Close to the target the circle shrinks, so it can never loop round the berth forever.
	var r: float = min(_turn_radius(), d * 0.5)
	var max_turn: float = max(speed / r, 0.4)
	turn_speed = clamp(angle / max(delta, 0.001), -max_turn, max_turn)
	rotation.y += turn_speed * delta
	# Move only the way the bow points
	position += forward() * speed * delta


func _drop_anchor() -> void:
	anchored = true
	anchor_pos = position
	anchor_heading = rotation.y
	anchor_time = _now()


func _drift() -> void:
	# Lying at anchor: the bow swings slowly with the wind and the boat creeps forward and back on its line.
	# One full swing takes about a minute, so it looks still at a glance but has moved by the end of a day.
	if not anchored:
		_drop_anchor()
	var t := _now()
	# The drift fades in over 8 seconds after stopping, so the boat doesn't jump
	var fade: float = clamp((t - anchor_time) / 8.0, 0.0, 1.0)
	var since := t - anchor_time
	# Both waves start at 0 when the boat stops
	var swing_now := (sin(since * 0.08 + drift_phase) - sin(drift_phase)) * 0.5 + (sin(since * 0.19 + drift_phase * 2.0) - sin(drift_phase * 2.0)) * 0.25
	var surge_now := (sin(since * 0.12 + drift_phase) - sin(drift_phase)) * 0.5
	var old_heading := rotation.y
	rotation.y = anchor_heading + swing_now * swing * fade
	# The boat pivots about its bow (where the anchor line is), so the stern does the swinging
	var bow_off := length * 0.4
	var anchor_fwd := Vector3(sin(anchor_heading), 0.0, cos(anchor_heading))
	var bow := anchor_pos + anchor_fwd * bow_off
	var new_pos := bow - forward() * bow_off + forward() * surge_now * surge * fade
	var moved := Vector2(new_pos.x - position.x, new_pos.z - position.z).length()
	speed = moved / max(get_process_delta_time(), 0.001)
	turn_speed = (rotation.y - old_heading) / max(get_process_delta_time(), 0.001)
	position.x = new_pos.x
	position.z = new_pos.z


func _bob(delta: float) -> void:
	bob_phase += delta * 2.0
	var bob := sin(bob_phase) * bob_strength
	# Lean a little into turns (outwards), as a boat does under way
	var lean: float = clamp(-turn_speed * speed * 0.04, -0.15, 0.15)
	if model:
		model.position.y = bob - 0.1
		# A gentle roll, bigger in a storm
		model.rotation.z = sin(bob_phase * 0.7) * bob_strength * 0.25 + lean
	else:
		$Hull.position.y = 0.25 + bob
		$Cabin.position.y = 0.7 + bob
