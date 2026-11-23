extends Node3D
## Weather you can see: sky, sun, fog, sea, cloud shadows, rain and lightning.
## main.gd calls set_weather("perfect" / "normal" / "storm") each day.
## The Rain and Flash nodes live in scenes/weather_fx.tscn, so they can be tweaked in the editor.

@export var world_env: WorldEnvironment
@export var sun: DirectionalLight3D
@export var ocean: MeshInstance3D
# Seconds to blend from one weather to the next
@export var blend_time := 2.0
# How many clouds exist (the weather shows some or all of them)
@export var cloud_total := 30

# What each weather looks like
const LOOKS := {
	"perfect": {
		"sky": Color(0.3, 0.6, 0.95), "horizon": Color(0.75, 0.85, 0.95),
		"sun": 1.3, "sun_color": Color(1.0, 0.96, 0.88), "ambient": 0.8,
		"fog": 0.0008, "fog_color": Color(0.75, 0.85, 0.95),
		"ocean": Color(0.1, 0.45, 0.7), "waves": 0.25, "wave_speed": 0.8, "chop": 0.0,
		"clouds": 5, "wind": 0.012,
		"rain": false, "lightning": false,
	},
	"normal": {
		"sky": Color(0.45, 0.58, 0.72), "horizon": Color(0.72, 0.78, 0.84),
		"sun": 0.9, "sun_color": Color(0.95, 0.95, 0.95), "ambient": 0.7,
		"fog": 0.002, "fog_color": Color(0.65, 0.72, 0.8),
		"ocean": Color(0.12, 0.36, 0.55), "waves": 0.45, "wave_speed": 1.0, "chop": 0.25,
		"clouds": 14, "wind": 0.018,
		"rain": false, "lightning": false,
	},
	"storm": {
		"sky": Color(0.18, 0.2, 0.24), "horizon": Color(0.3, 0.33, 0.37),
		"sun": 0.3, "sun_color": Color(0.7, 0.75, 0.85), "ambient": 0.45,
		"fog": 0.005, "fog_color": Color(0.28, 0.31, 0.35),
		"ocean": Color(0.08, 0.15, 0.2), "waves": 1.3, "wave_speed": 1.6, "chop": 1.0,
		"clouds": 30, "wind": 0.035,
		"rain": true, "lightning": true,
	},
}

var weather := "normal"
var wind := 0.018
var clouds: Array[Node3D] = []
var ocean_mat: ShaderMaterial
var sky_mat: ProceduralSkyMaterial
var env: Environment
var lightning_on := false
var next_strike := 0.0
# The blend in progress, stopped when the next weather starts
var blend: Tween

@onready var cloud_root: Node3D = $Clouds
@onready var rain: GPUParticles3D = $Rain
@onready var flash: DirectionalLight3D = $Flash
@onready var bolt: Node3D = $Bolt


func _ready() -> void:
	env = world_env.environment
	sky_mat = env.sky.sky_material
	ocean_mat = ocean.get_surface_override_material(0)
	_make_clouds()
	bolt.visible = false
	flash.light_energy = 0.0
	set_weather("normal", 0.0)


func _make_clouds() -> void:
	# The camera always looks down, so the clouds sit high above it and are never seen:
	# only their shadows drift over the island and the sea
	var puff := SphereMesh.new()
	puff.radial_segments = 8
	puff.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in cloud_total:
		var c := Node3D.new()
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(0.0, 110.0)
		c.position = Vector3(sin(angle) * dist, rng.randf_range(115.0, 125.0), cos(angle) * dist)
		c.rotation.y = rng.randf() * TAU
		# Each cloud is a few flattened puffs side by side
		var puffs := rng.randi_range(3, 6)
		for k in puffs:
			var m := MeshInstance3D.new()
			m.mesh = puff
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			var size := rng.randf_range(5.0, 9.0)
			m.scale = Vector3(size * 1.4, size * 0.5, size)
			m.position = Vector3((k - puffs / 2.0) * 6.0 + rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-3.0, 3.0))
			c.add_child(m)
		c.scale = Vector3.ZERO
		cloud_root.add_child(c)
		clouds.append(c)


func set_weather(w: String, seconds := -1.0) -> void:
	if not LOOKS.has(w):
		return
	weather = w
	var time: float = blend_time if seconds < 0.0 else max(seconds, 0.01)
	var look: Dictionary = LOOKS[w]
	if blend and blend.is_valid():
		blend.kill()
	blend = create_tween().set_parallel(true)
	var t := blend
	t.tween_property(sky_mat, "sky_top_color", look.sky, time)
	t.tween_property(sky_mat, "sky_horizon_color", look.horizon, time)
	t.tween_property(sky_mat, "ground_horizon_color", look.horizon, time)
	t.tween_property(sun, "light_energy", look.sun, time)
	t.tween_property(sun, "light_color", look.sun_color, time)
	t.tween_property(env, "ambient_light_energy", look.ambient, time)
	t.tween_property(env, "fog_density", look.fog, time)
	t.tween_property(env, "fog_light_color", look.fog_color, time)
	env.fog_enabled = true
	_tween_param(t, ocean_mat, "water_color", look.ocean, time)
	_tween_param(t, ocean_mat, "wave_height", look.waves, time)
	_tween_param(t, ocean_mat, "wave_speed", look.wave_speed, time)
	_tween_param(t, ocean_mat, "choppiness", look.chop, time)
	t.tween_property(self, "wind", float(look.wind), time)
	# Grow the clouds this weather needs, shrink the rest away
	for i in clouds.size():
		var target := Vector3.ONE if i < int(look.clouds) else Vector3.ZERO
		t.tween_property(clouds[i], "scale", target, time * randf_range(0.6, 1.0))
	rain.emitting = look.rain
	lightning_on = look.lightning
	next_strike = randf_range(1.5, 4.0)


func _tween_param(t: Tween, mat: ShaderMaterial, param: String, to: Variant, time: float) -> void:
	# Shader values can't be tweened by name until they have been set once
	var from: Variant = mat.get_shader_parameter(param)
	if from == null:
		mat.set_shader_parameter(param, to)
		return
	t.tween_method(func(v): mat.set_shader_parameter(param, v), from, to, time)


func _process(delta: float) -> void:
	# The cloud shadows drift round the island with the wind
	cloud_root.rotation.y += wind * delta
	if lightning_on:
		next_strike -= delta
		if next_strike <= 0.0:
			next_strike = randf_range(3.0, 9.0)
			_strike()


func _strike() -> void:
	# A jagged bolt somewhere out at sea, a double flash of light, then the sky settles
	_build_bolt()
	var t := create_tween()
	t.tween_callback(func(): bolt.visible = true)
	t.tween_property(flash, "light_energy", 2.0, 0.04)
	t.tween_property(flash, "light_energy", 0.3, 0.08)
	t.tween_property(flash, "light_energy", 1.4, 0.05)
	t.tween_callback(func(): bolt.visible = false)
	t.tween_property(flash, "light_energy", 0.0, 0.35)


func _build_bolt() -> void:
	for c in bolt.get_children():
		c.queue_free()
	# Out at sea to the left or right of the island, where the camera can see it against the water
	var cam := get_viewport().get_camera_3d()
	var ahead := Vector3(0, 0, -1)
	if cam:
		ahead = -cam.global_transform.basis.z
		ahead.y = 0.0
		ahead = ahead.normalized()
	var side := ahead.cross(Vector3.UP)
	var base := ahead * randf_range(-10.0, 15.0) + side * randf_range(38.0, 55.0) * (1.0 if randf() < 0.5 else -1.0)
	var p := Vector3(base.x, 45.0, base.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.94, 1.0)
	# Zig-zag down to the sea in short segments
	while p.y > 0.0:
		var q := p + Vector3(randf_range(-3.0, 3.0), -randf_range(4.0, 7.0), randf_range(-3.0, 3.0))
		q.y = max(q.y, 0.0)
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, p.distance_to(q))
		seg.mesh = box
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt.add_child(seg)
		seg.look_at_from_position((p + q) / 2.0, q, Vector3.RIGHT)
		p = q
