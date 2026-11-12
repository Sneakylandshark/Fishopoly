extends Node3D
## A greybox boat. Colour shows its kind. It bobs on the water and can sail to a spot.

@export var hull_color := Color(0.85, 0.85, 0.8)

var bob_phase := 0.0
var bob_strength := 0.08
var home := Vector3.ZERO


func _ready() -> void:
	bob_phase = randf() * TAU
	set_color(hull_color)


func set_color(c: Color) -> void:
	hull_color = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	$Hull.material_override = mat


func _process(delta: float) -> void:
	bob_phase += delta * 2.0
	$Hull.position.y = 0.25 + sin(bob_phase) * bob_strength
	$Cabin.position.y = 0.7 + sin(bob_phase) * bob_strength


func sail_to(target: Vector3, seconds: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "position", target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t


func sink(seconds: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "position:y", -2.0, seconds)
	t.parallel().tween_property(self, "rotation:z", 1.2, seconds)
	return t
