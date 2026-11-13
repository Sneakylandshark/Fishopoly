extends Control
## Draws line graphs of the run's history. main.gd fills "lines" and calls queue_redraw().
## Hover the mouse over the graph to read every line's value on that day.

# [{"name": String, "values": Array of floats, "color": Color}]
var lines: Array = []
# The first day (or week) number shown on the left edge
var first_x := 1
# "Day" or "Week"
var x_name := "Day"
var hover := -1

const PAD_L := 90.0
const PAD_R := 16.0
const PAD_T := 16.0
const PAD_B := 34.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var n := _count()
		if n == 0:
			return
		var w: float = size.x - PAD_L - PAD_R
		var t: float = clamp((event.position.x - PAD_L) / max(w, 1.0), 0.0, 1.0)
		var i: int = int(round(t * max(n - 1, 1)))
		if i != hover:
			hover = i
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = -1
		queue_redraw()


func _count() -> int:
	var n := 0
	for l in lines:
		n = max(n, l.values.size())
	return n


func _range() -> Vector2:
	var lo := 0.0
	var hi := 0.0
	for l in lines:
		for v in l.values:
			lo = min(lo, float(v))
			hi = max(hi, float(v))
	if hi - lo < 0.0001:
		hi = lo + 1.0
	return Vector2(lo, hi)


func _short(x: float) -> String:
	# $1.2M style labels for the left axis
	var a: float = abs(x)
	var s := ""
	if a >= 1e9:
		s = "%.1fB" % (a / 1e9)
	elif a >= 1e6:
		s = "%.1fM" % (a / 1e6)
	elif a >= 1e3:
		s = "%.1fk" % (a / 1e3)
	else:
		s = "%.0f" % a
	return ("-" if x < 0 else "") + s


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 14
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.13))
	var n := _count()
	if n == 0:
		draw_string(font, Vector2(PAD_L, size.y / 2), "Tick some lines on the left. Graphs fill in as days pass.", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
		return
	var r := _range()
	var w: float = size.x - PAD_L - PAD_R
	var h: float = size.y - PAD_T - PAD_B
	var to_px := func(i: int, v: float) -> Vector2:
		var x: float = PAD_L + (w * i / float(max(n - 1, 1)))
		var y: float = PAD_T + h * (1.0 - (v - r.x) / (r.y - r.x))
		return Vector2(x, y)
	# Grid lines and left-axis values
	for k in 5:
		var v: float = r.x + (r.y - r.x) * k / 4.0
		var p: Vector2 = to_px.call(0, v)
		draw_line(Vector2(PAD_L, p.y), Vector2(size.x - PAD_R, p.y), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(4, p.y + 5), _short(v), HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 10, fs, Color(0.75, 0.75, 0.75))
	# Zero line, brighter
	if r.x < 0.0:
		var z: Vector2 = to_px.call(0, 0.0)
		draw_line(Vector2(PAD_L, z.y), Vector2(size.x - PAD_R, z.y), Color(1, 1, 1, 0.3))
	# Bottom-axis day numbers
	var step: int = max(1, int(ceil(n / 8.0)))
	for i in range(0, n, step):
		var p: Vector2 = to_px.call(i, r.x)
		draw_string(font, Vector2(p.x - 20, size.y - 10), "%s %d" % [x_name, first_x + i], HORIZONTAL_ALIGNMENT_CENTER, 40, fs - 2, Color(0.7, 0.7, 0.7))
	# The lines
	for l in lines:
		var pts := PackedVector2Array()
		for i in l.values.size():
			pts.append(to_px.call(i, float(l.values[i])))
		if pts.size() == 1:
			draw_circle(pts[0], 3.0, l.color)
		elif pts.size() > 1:
			draw_polyline(pts, l.color, 2.0, true)
	# Hover: a line down the graph and each value on that day
	if hover >= 0 and hover < n:
		var hp: Vector2 = to_px.call(hover, r.x)
		draw_line(Vector2(hp.x, PAD_T), Vector2(hp.x, PAD_T + h), Color(1, 1, 1, 0.4))
		var rows := ["%s %d" % [x_name, first_x + hover]]
		var cols := [Color.WHITE]
		for l in lines:
			if hover < l.values.size():
				rows.append("%s: %s" % [l.name, _short(float(l.values[hover]))])
				cols.append(l.color)
		var bw := 260.0
		var bx: float = hp.x + 12 if hp.x + 12 + bw < size.x else hp.x - 12 - bw
		draw_rect(Rect2(bx, PAD_T, bw, 8 + rows.size() * 19), Color(0, 0, 0, 0.8))
		for k in rows.size():
			draw_string(font, Vector2(bx + 8, PAD_T + 20 + k * 19), rows[k], HORIZONTAL_ALIGNMENT_LEFT, bw - 12, fs, cols[k])
