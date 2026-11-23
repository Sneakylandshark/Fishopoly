extends Node3D
## Screenshot check (not part of the game): photographs scenes on a plain ground from two sides.
## Run: Godot_v4.7.2-stable_win64.exe --path "<project>" res://tests/shot_model.tscn -- <scene.tscn> [<scene.tscn> ...]
## Saves user://shot_model.png (one row per scene: front-left and back-right), then quits.

const TILE := Vector2i(480, 360)
var scenes: Array = []
var i := 0
var side := 0
var wait := 3
var sheet: Image
var current: Node3D


func _ready() -> void:
	scenes = Array(OS.get_cmdline_user_args())
	sheet = Image.create(TILE.x * 2, TILE.y * max(1, scenes.size()), false, Image.FORMAT_RGB8)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.75, 0.55)
	ground.material_override = mat
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.75, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)
	add_child(Camera3D.new())
	_load()


func _load() -> void:
	if current:
		current.queue_free()
	current = load(scenes[i]).instantiate()
	add_child(current)


func _top() -> float:
	var top := 1.0
	for v in current.find_children("*", "VisualInstance3D", true, false):
		top = max(top, (current.global_transform.affine_inverse() * v.global_transform * v.get_aabb()).end.y)
	return top


func _process(_d: float) -> void:
	var cam: Camera3D = find_children("*", "Camera3D", false, false)[0]
	var top := _top()
	var dirs := [Vector3(-0.7, 0.55, 1.0), Vector3(0.8, 0.5, -0.9)]
	cam.global_position = Vector3(0, top * 0.4, 0) + dirs[side].normalized() * (top * 1.2 + 2.0)
	cam.look_at(Vector3(0, top * 0.4, 0), Vector3.UP)
	wait -= 1
	if wait > 0:
		return
	var shot := get_viewport().get_texture().get_image()
	shot.convert(Image.FORMAT_RGB8)
	shot.resize(TILE.x, TILE.y)
	sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, TILE), Vector2i(side * TILE.x, i * TILE.y))
	wait = 3
	side += 1
	if side > 1:
		side = 0
		i += 1
		if i >= scenes.size():
			sheet.save_png("user://shot_model.png")
			get_tree().quit()
			return
		_load()
