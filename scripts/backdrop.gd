class_name Backdrop
extends Node2D
## Painted battlefield behind (and a little in front of) the elephants: sky, hills with
## temple ruins, sugar palms, big trees, banana plants, rice paddies and the dirt arena.
## Shapes are built once from a fixed seed; each layer slides with the camera by its own
## parallax factor so the far hills barely move and the foreground grass moves most.
## Each layer is its own canvas item drawn once (Godot keeps the draw list); per frame only
## the layers move, a few plants sway and a small live layer redraws birds and fireflies.
## The heavy layers are baked into textures once, so a frame costs a few dozen quads.
## Three palettes give the arcade stages a time of day: morning, sunset and dusk.

const W := GameData.W
const H := GameData.H
const G := GameData.GROUND
const SPAN := Vector2(-520.0, 1480.0)   ## world x range every layer covers
const HORIZON := 318.0
const PADDY_TOP := 352.0
const EDGE := 408.0                     ## top of the dirt arena

const BAKE := 2.0                      ## baked layers keep this many texels per arena unit (crisp at 1080p)
const VIEW_MAX := 420.0                ## farthest the camera travels either way (title-screen slide)
const SCENES := ["day", "sunset", "dusk"]
const PALETTES := {
	"day": {
		"sky_top": "3d9ee0", "sky_mid": "8fcdf0", "sky_bot": "e6f4ee", "sun": "fff8dc", "glow": "fff1a8",
		"cloud": "ffffff", "cloud_shade": "cfe2ee", "mtn_far": "a3c3d8", "mtn_mid": "7aa5bc", "temple": "8193a3",
		"tree_far": "5a9670", "tree_dark": "235f38", "tree_mid": "3d8b42", "tree_light": "76bb4c", "trunk": "5e4331",
		"palm": "2f6a3a", "paddy_a": "86c64c", "paddy_b": "67b03e", "water": "b5dfe4", "dike": "9aa456",
		"ground_top": "d2ad72", "ground_bot": "a87f4a", "ground_dark": "9a7240", "grass": "62aa3a", "grass_dark": "3d7b2a",
		"stone": "967855", "bird": "2d3a4a",
	},
	"sunset": {
		"sky_top": "2c7a9a", "sky_mid": "e7a36a", "sky_bot": "f8d690", "sun": "fff1c4", "glow": "ffb067",
		"cloud": "f7b88c", "cloud_shade": "c9786a", "mtn_far": "bd8f8a", "mtn_mid": "8e6c7a", "temple": "6c4b5b",
		"tree_far": "52704e", "tree_dark": "1f4a2a", "tree_mid": "3a7a36", "tree_light": "93b44c", "trunk": "4c3021",
		"palm": "2a502f", "paddy_a": "93bb47", "paddy_b": "71a238", "water": "f3c58d", "dike": "857f3c",
		"ground_top": "cf9f61", "ground_bot": "9a6d3d", "ground_dark": "8d6034", "grass": "6c9c35", "grass_dark": "3b6625",
		"stone": "7d5c3b", "bird": "3a2630",
	},
	"dusk": {
		"sky_top": "171c45", "sky_mid": "573878", "sky_bot": "e28558", "sun": "fff0d0", "glow": "ff9a66",
		"cloud": "6e4c7d", "cloud_shade": "3b2b5b", "mtn_far": "4d3c6d", "mtn_mid": "342951", "temple": "251c3c",
		"tree_far": "253150", "tree_dark": "121c2a", "tree_mid": "1f3b35", "tree_light": "3d5d3c", "trunk": "2b1b1b",
		"palm": "17271f", "paddy_a": "3d5d3d", "paddy_b": "304c34", "water": "a87496", "dike": "3d4331",
		"ground_top": "917052", "ground_bot": "5c4232", "ground_dark": "54392a", "grass": "3d5d30", "grass_dark": "243a20",
		"stone": "5c4636", "bird": "120e1e",
	},
}
## Sun (or moon) position and radius per scene; dusk adds stars and fireflies.
const SUNS := {"day": Vector3(745, 172, 42), "sunset": Vector3(690, 268, 72), "dusk": Vector3(300, 178, 26)}

var scene := "day"
var _pal := {}
var _rng := RandomNumberGenerator.new()
var _clouds := []        ## [x, y, scale, speed, circles: Array[Vector3]]
var _mtn_far := PackedVector2Array()
var _mtn_mid := PackedVector2Array()
var _temples: Array[PackedVector2Array] = []
var _treeline: Array[Vector3] = []      ## Vector3 circles
var _palms := []         ## [x, base_y, height, lean, frond count]
var _trees := []         ## [x, base_y, size]
var _bananas := []       ## [x, base_y, size]
var _paddy_rows := []    ## [y0, y1, color key]
         ## Vector3 (x, y, size)
var _stones: Array[Vector3] = []        ## Vector3
var _patches: Array[Vector3] = []       ## Vector3 worn dirt
var _fringe: Array[Vector3] = []        ## Vector3 grass blades along the arena edge
var _front := []         ## [x, size] foreground grass clumps
var _stars: Array[Vector3] = []
var _birds := []         ## [x, y, speed, phase]
var _row_tufts := []     ## per paddy row: Array[Vector3]
var _layers: Array[Layer] = []
var _clouds_n := []      ## [node, x, y, speed]
var _swayers := []       ## [node, phase, amount, base angle, speed, skew?]
var _live: Layer
var _view := 0.0
var _t := 0.0


## One parallax plane (or a single swaying plant inside one).
class Layer extends Node2D:
	var factor := 1.0
	var paint: Callable

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)


func _init(scene_name := "day") -> void:
	scene = scene_name if PALETTES.has(scene_name) else "day"
	for k in PALETTES[scene]:
		_pal[k] = Color("#" + PALETTES[scene][k])
	_rng.seed = 7
	_build()


func col(key: String) -> Color:
	return _pal[key]


# ---------- build ----------

func _build() -> void:
	for i in 7:
		var circles := []
		var n := _rng.randi_range(4, 7)
		for k in n:
			var cx := (k - n / 2.0) * 22.0 + _rng.randf_range(-6.0, 6.0)
			var r := _rng.randf_range(14.0, 26.0) * (1.0 - absf(k - n / 2.0) / n * 0.8)
			circles.append(Vector3(cx, -r * 0.5, r))
		_clouds.append([_rng.randf_range(SPAN.x, SPAN.y), _rng.randf_range(40.0, 190.0), _rng.randf_range(0.7, 1.3), _rng.randf_range(3.0, 9.0), circles])

	_mtn_far = _ridge(HORIZON - 70.0, 55.0, 0.006, 0.017, HORIZON + 4.0)
	_mtn_mid = _ridge(HORIZON - 30.0, 38.0, 0.009, 0.023, HORIZON + 8.0)
	# temple ruins on the near hills: three corn-cob prangs and a bell chedi
	_temples.append(_prang(560.0, HORIZON - 8.0, 98.0, 34.0))
	_temples.append(_prang(512.0, HORIZON - 4.0, 66.0, 24.0))
	_temples.append(_prang(608.0, HORIZON - 4.0, 66.0, 24.0))
	_temples.append(_chedi(-130.0, HORIZON - 2.0, 74.0, 40.0))
	_temples.append(_chedi(1150.0, HORIZON - 2.0, 60.0, 32.0))

	var x := SPAN.x
	while x < SPAN.y:
		_treeline.append(Vector3(x, HORIZON + 14.0 + _rng.randf_range(-10.0, 6.0), _rng.randf_range(12.0, 22.0)))
		x += _rng.randf_range(12.0, 20.0)

	for px in [-360.0, -150.0, 60.0, 250.0, 420.0, 700.0, 880.0, 1080.0, 1300.0]:
		_palms.append([px + _rng.randf_range(-30.0, 30.0), PADDY_TOP + _rng.randf_range(4.0, 14.0), _rng.randf_range(120.0, 175.0), _rng.randf_range(-0.12, 0.12), _rng.randi_range(13, 17)])
	for tx in [-260.0, 170.0, 980.0, 1240.0]:
		_trees.append([tx + _rng.randf_range(-40.0, 40.0), PADDY_TOP + 22.0, _rng.randf_range(0.85, 1.15)])
	for bx in [-420.0, -40.0, 330.0, 620.0, 820.0, 1150.0, 1400.0]:
		_bananas.append([bx + _rng.randf_range(-30.0, 30.0), EDGE + 2.0, _rng.randf_range(0.8, 1.15)])

	# paddies get taller toward the viewer
	var y := PADDY_TOP
	var row := 0
	while y < EDGE:
		var h := 6.0 + row * 2.6
		_paddy_rows.append([y, minf(EDGE, y + h), "water" if row == 2 or row == 5 else ("paddy_a" if row % 2 == 0 else "paddy_b")])
		y += h
		row += 1
	for r in _paddy_rows:
		var bucket: Array[Vector3] = []
		_row_tufts.append(bucket)
	for i in 420:
		var ty := _rng.randf_range(PADDY_TOP + 4.0, EDGE)
		var depth := (ty - PADDY_TOP) / (EDGE - PADDY_TOP)
		var tuft := Vector3(_rng.randf_range(SPAN.x, SPAN.y), ty, 1.5 + depth * 4.0)
		for k in _paddy_rows.size():
			if ty >= float(_paddy_rows[k][0]) and ty <= float(_paddy_rows[k][1]):
				(_row_tufts[k] as Array).append(tuft)
				break

	for i in 40:
		_stones.append(Vector3(_rng.randf_range(-200.0, 1160.0), _rng.randf_range(EDGE + 14.0, H), _rng.randf_range(2.0, 5.0)))
	for i in 9:
		_patches.append(Vector3(_rng.randf_range(-200.0, 1160.0), _rng.randf_range(EDGE + 30.0, H - 10.0), _rng.randf_range(40.0, 110.0)))
	x = -300.0
	while x < 1260.0:
		_fringe.append(Vector3(x, EDGE + _rng.randf_range(-1.0, 3.0), _rng.randf_range(5.0, 12.0)))
		x += _rng.randf_range(3.0, 7.0)
	for fx in [-60.0, 20.0, 960.0, 1030.0, 470.0]:
		_front.append([fx + _rng.randf_range(-20.0, 20.0), _rng.randf_range(0.8, 1.3)])
	for i in 70:
		_stars.append(Vector3(_rng.randf_range(0.0, W), _rng.randf_range(0.0, 220.0), _rng.randf_range(0.6, 1.8)))
	for i in 4:
		_birds.append([_rng.randf_range(0.0, W), _rng.randf_range(60.0, 170.0), _rng.randf_range(16.0, 28.0), _rng.randf() * TAU])


func _ridge(base: float, amp: float, f1: float, f2: float, bottom: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ph1 := _rng.randf() * TAU
	var ph2 := _rng.randf() * TAU
	var x := SPAN.x
	while x <= SPAN.y:
		var y := base - amp * (0.55 * sin(x * f1 + ph1) + 0.3 * sin(x * f2 + ph2) + 0.15 * sin(x * 0.05 + ph1))
		pts.append(Vector2(x, y))
		x += 16.0
	pts.append(Vector2(SPAN.y, bottom))
	pts.append(Vector2(SPAN.x, bottom))
	return pts


## Khmer-style prang: stepped base, tall rounded tower with notched tiers, thin spire.
func _prang(cx: float, by: float, h: float, w: float) -> PackedVector2Array:
	var right: Array[Vector2] = []
	var tiers := 9
	right.append(Vector2(w * 0.62, 0))
	right.append(Vector2(w * 0.62, -h * 0.08))
	right.append(Vector2(w * 0.52, -h * 0.08))
	right.append(Vector2(w * 0.52, -h * 0.2))
	for i in tiers:
		var k0 := float(i) / tiers
		var k1 := float(i + 1) / tiers
		var y0 := -h * (0.2 + 0.65 * k0)
		var y1 := -h * (0.2 + 0.65 * k1)
		var hw0 := w * 0.46 * sqrt(maxf(0.0, 1.0 - k0 * k0 * 0.92))
		var hw1 := w * 0.46 * sqrt(maxf(0.0, 1.0 - k1 * k1 * 0.92))
		right.append(Vector2(hw0, y0))
		right.append(Vector2(hw1 + w * 0.04, lerpf(y0, y1, 0.5)))
		right.append(Vector2(hw1, y1))
	right.append(Vector2(w * 0.04, -h))
	right.append(Vector2(0, -h * 1.08))
	var pts := PackedVector2Array()
	for p in right:
		pts.append(Vector2(cx + p.x, by + p.y))
	for i in range(right.size() - 2, -1, -1):
		pts.append(Vector2(cx - right[i].x, by + right[i].y))
	return pts


## Bell-shaped chedi: square base, round bell, ringed cone and a needle spire.
func _chedi(cx: float, by: float, h: float, w: float) -> PackedVector2Array:
	var right: Array[Vector2] = [Vector2(w * 0.5, 0), Vector2(w * 0.5, -h * 0.07), Vector2(w * 0.42, -h * 0.07), Vector2(w * 0.42, -h * 0.13)]
	for i in 7:
		var a := PI * 0.5 * float(i) / 6.0
		right.append(Vector2(w * 0.38 * cos(a) + w * 0.02, -h * 0.13 - h * 0.3 * sin(a)))
	right.append(Vector2(w * 0.12, -h * 0.45))
	right.append(Vector2(w * 0.12, -h * 0.5))
	for i in 5:
		var k := float(i) / 5.0
		right.append(Vector2(w * 0.1 * (1.0 - k) + w * 0.02, -h * (0.5 + 0.3 * k)))
		right.append(Vector2(w * 0.08 * (1.0 - k) + w * 0.01, -h * (0.53 + 0.3 * k)))
	right.append(Vector2(w * 0.01, -h))
	right.append(Vector2(0, -h * 1.04))
	var pts := PackedVector2Array()
	for p in right:
		pts.append(Vector2(cx + p.x, by + p.y))
	for i in range(right.size() - 2, -1, -1):
		pts.append(Vector2(cx - right[i].x, by + right[i].y))
	return pts


# ---------- layers ----------

func _ready() -> void:
	_baked(0.0, 0.0, PADDY_TOP + 2.0, _paint_sky)
	for cl in _clouds:
		var n := Layer.new()
		var tex := _bake(Rect2(-110, -70, 220, 110), func(c: CanvasItem) -> void: _paint_cloud(c, cl))
		n.paint = func(c: CanvasItem) -> void: c.draw_texture_rect(tex, Rect2(-110, -70, 220, 110), false)
		add_child(n)
		_clouds_n.append([n, cl[0], cl[1], cl[3]])
	_baked(0.08, 180.0, HORIZON + 10.0, func(c: CanvasItem) -> void: _poly_fade(c, _mtn_far, col("mtn_far"), col("mtn_far").lerp(col("sky_bot"), 0.55), HORIZON - 120.0, HORIZON))
	_baked(0.14, 190.0, HORIZON + 12.0, _paint_hills)
	_baked(0.22, HORIZON - 10.0, PADDY_TOP + 2.0, _paint_treeline)
	_baked(0.32, 120.0, PADDY_TOP + 20.0, _paint_palms)
	_baked(0.45, 150.0, PADDY_TOP + 26.0, _paint_trees)
	for k in _paddy_rows.size():
		var r: Array = _paddy_rows[k]
		var f := lerpf(0.5, 0.95, (float(r[0]) - PADDY_TOP) / (EDGE - PADDY_TOP))
		_baked(f, float(r[0]) - 14.0, float(r[1]) + 1.0, func(c: CanvasItem) -> void: _paint_paddy_row(c, k))
	_baked(0.62, 320.0, EDGE + 4.0, _paint_bananas)
	_baked(1.0, EDGE - 14.0, H + 4.0, _paint_ground)
	_live = _add(0.0, _paint_live)
	var front := _add(1.25, Callable())
	front.z_index = 1
	for fr in _front:
		var n := Layer.new()
		n.position = Vector2(fr[0], H + 2.0)
		n.paint = func(c: CanvasItem) -> void: _paint_clump(c, fr[1])
		front.add_child(n)
		_swayers.append([n, float(fr[0]) * 0.01, 0.08, 0.0, 1.6, true])


func _add(factor: float, paint: Callable) -> Layer:
	var n := Layer.new()
	n.factor = factor
	n.paint = paint
	add_child(n)
	_layers.append(n)
	return n


## A layer whose shapes are rendered once into a texture: per frame it is one textured quad.
## It is made wide enough for the camera's whole travel at this layer's parallax factor.
func _baked(factor: float, y0: float, y1: float, painter: Callable) -> Layer:
	var shift := VIEW_MAX * factor + 24.0
	var rect := Rect2(-shift, y0, W + shift * 2.0, y1 - y0)
	var tex := _bake(rect, painter)
	return _add(factor, func(c: CanvasItem) -> void: c.draw_texture_rect(tex, rect, false))


## Renders `painter` (in arena coordinates) for the area `rect` into a texture, once.
func _bake(rect: Rect2, painter: Callable) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(ceili(rect.size.x * BAKE), ceili(rect.size.y * BAKE))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var n := Layer.new()
	n.paint = painter
	n.transform = Transform2D(0.0, Vector2(BAKE, BAKE), 0.0, -rect.position * BAKE)
	vp.add_child(n)
	add_child(vp)
	return vp.get_texture()


## Slides every layer for camera offset `view` (the ground moves by it 1:1) plus screen shake.
func update(view: float, t: float, shake: Vector2) -> void:
	view = clampf(view, -VIEW_MAX, VIEW_MAX)
	_view = view
	_t = t
	for l in _layers:
		l.position = Vector2(view * l.factor, 0.0) + shake
	for cn in _clouds_n:
		(cn[0] as Node2D).position = Vector2(wrapf(float(cn[1]) + t * float(cn[3]) + view * 0.05, -200.0, W + 200.0), cn[2]) + shake
	for sw in _swayers:
		var n: Node2D = sw[0]
		var v: float = sin(t * float(sw[4]) + float(sw[1])) * float(sw[2]) + float(sw[3])
		if sw[5]:
			n.skew = v
		else:
			n.rotation = v
	_live.queue_redraw()


# ---------- painters (called once per layer, in that layer's space) ----------

func _paint_sky(c: CanvasItem) -> void:
	var top := col("sky_top")
	var mid := col("sky_mid")
	var bot := col("sky_bot")
	c.draw_polygon(PackedVector2Array([Vector2(-40, -40), Vector2(W + 40, -40), Vector2(W + 40, 190), Vector2(-40, 190)]), PackedColorArray([top, top, mid, mid]))
	c.draw_polygon(PackedVector2Array([Vector2(-40, 190), Vector2(W + 40, 190), Vector2(W + 40, PADDY_TOP), Vector2(-40, PADDY_TOP)]), PackedColorArray([mid, mid, bot, bot]))
	if scene == "dusk":
		for s in _stars:
			c.draw_circle(Vector2(s.x, s.y), s.z, Color(1, 1, 1, 0.75))
	var sun: Vector3 = SUNS[scene]
	var sp := Vector2(sun.x, sun.y)
	for i in 5:
		c.draw_circle(sp, sun.z * (2.6 - i * 0.35), Color(col("glow"), 0.07 + i * 0.02))
	c.draw_circle(sp, sun.z, col("sun"))
	if scene == "dusk":
		c.draw_circle(sp + Vector2(sun.z * 0.35, -sun.z * 0.2), sun.z * 0.82, Color(col("sky_top").lerp(col("sky_mid"), 0.3), 0.92))


func _paint_cloud(c: CanvasItem, cl: Array) -> void:
	var s: float = cl[2]
	for ci in cl[4]:
		c.draw_circle(Vector2(ci.x * s, ci.y * s + 5.0 * s), ci.z * s, col("cloud_shade"))
	for ci in cl[4]:
		c.draw_circle(Vector2(ci.x * s, ci.y * s), ci.z * s * 0.94, col("cloud"))


func _paint_hills(c: CanvasItem) -> void:
	_poly_fade(c, _mtn_mid, col("mtn_mid"), col("mtn_mid").lerp(col("sky_bot"), 0.4), HORIZON - 70.0, HORIZON + 8.0)
	for tp in _temples:
		c.draw_colored_polygon(tp, col("temple"))


func _paint_treeline(c: CanvasItem) -> void:
	var tf := col("tree_far").lerp(col("sky_bot"), 0.25)
	c.draw_rect(Rect2(SPAN.x, HORIZON + 10.0, SPAN.y - SPAN.x, PADDY_TOP - HORIZON), tf)
	for cl in _treeline:
		c.draw_circle(Vector2(cl.x, cl.y), cl.z, tf)


func _paint_palms(c: CanvasItem) -> void:
	for p in _palms:
		c.draw_set_transform(Vector2(p[0], p[1]), p[3])
		_paint_palm(c, p)
	c.draw_set_transform(Vector2.ZERO)


func _paint_bananas(c: CanvasItem) -> void:
	for b in _bananas:
		c.draw_set_transform(Vector2(b[0], b[1]))
		_paint_banana(c, b)
	c.draw_set_transform(Vector2.ZERO)


func _paint_trees(c: CanvasItem) -> void:
	for tr in _trees:
		_draw_tree(c, tr)


## Polygon whose colour fades from `a` at y0 to `b` at y1 (atmospheric haze).
func _poly_fade(c: CanvasItem, pts: PackedVector2Array, a: Color, b: Color, y0: float, y1: float) -> void:
	var cols := PackedColorArray()
	for p in pts:
		cols.append(a.lerp(b, clampf((p.y - y0) / (y1 - y0), 0.0, 1.0)))
	c.draw_polygon(pts, cols)


## Sugar palm (ตาลโตนด), base at the origin: thin trunk, round crown of spiky fan leaves.
func _paint_palm(c: CanvasItem, p: Array) -> void:
	var h: float = p[2]
	var top := Vector2(0, -h)
	var colr := col("palm").lerp(col("sky_bot"), 0.18)
	var trunk := col("trunk")
	c.draw_polygon(PackedVector2Array([Vector2(-3.5, 0), Vector2(3.5, 0), top + Vector2(2, 0), top - Vector2(2, 0)]), PackedColorArray([trunk, trunk, trunk.darkened(0.2), trunk.darkened(0.2)]))
	var n: int = p[4]
	for i in n:
		var a := -PI * 0.5 + (float(i) / (n - 1) - 0.5) * PI * 1.55
		var d := Vector2.from_angle(a)
		var tip := top + d * 30.0 + Vector2(0, absf(d.x) * 8.0)
		var nrm := d.orthogonal() * 6.0
		c.draw_colored_polygon(PackedVector2Array([top + nrm * 0.4, top + d * 16.0 + nrm, tip, top + d * 16.0 - nrm, top - nrm * 0.4]), colr if i % 2 == 0 else colr.lightened(0.12))
	c.draw_circle(top, 6.0, colr.darkened(0.25))


## Big rain tree: trunk and branches under a broad canopy lit from the top-left.
func _draw_tree(c: CanvasItem, tr: Array) -> void:
	var x: float = tr[0]
	var by: float = tr[1]
	var s: float = tr[2]
	c.draw_colored_polygon(PackedVector2Array([Vector2(x - 9 * s, by), Vector2(x + 9 * s, by), Vector2(x + 5 * s, by - 70 * s), Vector2(x + 34 * s, by - 112 * s), Vector2(x + 26 * s, by - 116 * s), Vector2(x, by - 86 * s), Vector2(x - 28 * s, by - 114 * s), Vector2(x - 34 * s, by - 108 * s), Vector2(x - 5 * s, by - 70 * s)]), col("trunk"))
	var blobs := [Vector3(-58, -118, 34), Vector3(-22, -138, 40), Vector3(22, -136, 40), Vector3(60, -116, 32), Vector3(0, -110, 36), Vector3(-38, -100, 26), Vector3(40, -98, 26)]
	for b in blobs:
		c.draw_circle(Vector2(x + b.x * s, by + (b.y + 8) * s), b.z * s, col("tree_dark"))
	for b in blobs:
		c.draw_circle(Vector2(x + b.x * s, by + b.y * s), b.z * s * 0.9, col("tree_mid"))
	for b in blobs:
		c.draw_circle(Vector2(x + (b.x - b.z * 0.25) * s, by + (b.y - b.z * 0.3) * s), b.z * s * 0.5, col("tree_light"))


## Banana plant, base at the origin.
func _paint_banana(c: CanvasItem, b: Array) -> void:
	var s: float = b[2]
	c.draw_colored_polygon(PackedVector2Array([Vector2(-6 * s, 0), Vector2(6 * s, 0), Vector2(4 * s, -52 * s), Vector2(-4 * s, -52 * s)]), col("tree_mid").darkened(0.15))
	var top := Vector2(0, -50 * s)
	for i in 6:
		var d := Vector2.from_angle(deg_to_rad(-160.0 + i * 28.0))
		var droop := Vector2(0, 24.0 * s * absf(d.x))
		var tip := top + d * 62.0 * s + droop
		var mid := top + d * 34.0 * s + droop * 0.3
		var nrm := (tip - top).normalized().orthogonal() * 11.0 * s
		var leaf := col("tree_light") if i % 2 == 0 else col("tree_mid")
		c.draw_colored_polygon(PackedVector2Array([top, mid + nrm, tip, mid - nrm * 0.8]), leaf)
		c.draw_line(top, tip, leaf.darkened(0.25), 1.5)


## One band of paddy with its share of the converging dikes and rice tufts.
func _paint_paddy_row(c: CanvasItem, k: int) -> void:
	var r: Array = _paddy_rows[k]
	var y0: float = r[0]
	var y1: float = r[1]
	c.draw_rect(Rect2(SPAN.x, y0, SPAN.y - SPAN.x, y1 - y0), col(r[2]))
	if r[2] == "water":
		c.draw_rect(Rect2(SPAN.x, y0 + 1.5, SPAN.y - SPAN.x, 1.5), Color(1, 1, 1, 0.35))
	var k0 := (y0 - PADDY_TOP) / (EDGE - PADDY_TOP)
	var k1 := (y1 - PADDY_TOP) / (EDGE - PADDY_TOP)
	var x := -900.0
	while x < 1900.0:
		var top := 480.0 + (x - 480.0) * 0.35
		c.draw_line(Vector2(lerpf(top, x, k0), y0), Vector2(lerpf(top, x, k1), y1), col("dike"), 2.0)
		x += 150.0
	c.draw_rect(Rect2(SPAN.x, y0, SPAN.y - SPAN.x, 1.5), col("dike"))
	for tf: Vector3 in _row_tufts[k]:
		var d := (tf.y - PADDY_TOP) / (EDGE - PADDY_TOP)
		var g := col("grass_dark") if int(tf.x) % 3 == 0 else col("paddy_a").darkened(0.1)
		c.draw_line(Vector2(tf.x, tf.y), Vector2(tf.x - tf.z * 0.4, tf.y - tf.z * 2.0), g, 1.0 + d)
		c.draw_line(Vector2(tf.x, tf.y), Vector2(tf.x + tf.z * 0.4, tf.y - tf.z * 1.8), g, 1.0 + d)


func _paint_ground(c: CanvasItem) -> void:
	var a := col("ground_top")
	var b := col("ground_bot")
	c.draw_polygon(PackedVector2Array([Vector2(-600, EDGE), Vector2(1560, EDGE), Vector2(1560, H + 20), Vector2(-600, H + 20)]), PackedColorArray([a, a, b, b]))
	for p in _patches:
		_ellipse(c, Vector2(p.x, p.y), p.z, p.z * 0.16, Color(col("ground_dark"), 0.35))
	# the trampled strip the elephants fight on
	_ellipse(c, Vector2(480, G + 6), 620, 26, Color(col("ground_dark"), 0.22))
	for s in _stones:
		_ellipse(c, Vector2(s.x, s.y + 1.0), s.z, s.z * 0.55, col("ground_dark"))
		_ellipse(c, Vector2(s.x, s.y), s.z, s.z * 0.5, col("stone"))
	c.draw_rect(Rect2(-600, EDGE - 2.0, 2160, 5), col("grass_dark"))
	for f in _fringe:
		var g := col("grass") if int(f.x) % 2 == 0 else col("grass_dark")
		c.draw_colored_polygon(PackedVector2Array([Vector2(f.x - 2.5, f.y + 2.0), Vector2(f.x + 0.5, f.y - f.z), Vector2(f.x + 2.5, f.y + 2.0)]), g)


## Foreground grass clump, base at the origin (it sways by skewing).
func _paint_clump(c: CanvasItem, s: float) -> void:
	for i in 9:
		var bx := (i - 4) * 9.0 * s
		var hgt := (34.0 + 22.0 * sin(i * 1.7 + s * 10.0)) * s
		var c0 := col("grass_dark") if i % 2 == 0 else col("grass")
		c.draw_colored_polygon(PackedVector2Array([Vector2(bx - 5.0 * s, 0), Vector2(bx + (i - 4) * 2.0, -hgt), Vector2(bx + 5.0 * s, 0)]), c0.darkened(0.15))


## Redrawn every frame, but small: birds, fireflies and temple lamps (cheap primitives only).
func _paint_live(c: CanvasItem) -> void:
	var t := _t
	for b in _birds:
		var x := wrapf(float(b[0]) + t * float(b[2]), -40.0, W + 40.0)
		var y := float(b[1]) + sin(t * 0.7 + float(b[3])) * 6.0
		var flap := sin(t * 7.0 + float(b[3])) * 4.0
		c.draw_polyline(PackedVector2Array([Vector2(x - 7, y - flap), Vector2(x, y), Vector2(x + 7, y - flap)]), col("bird"), 1.6, true)
	if scene == "dusk":
		for lx in [548.0, 572.0, 512.0, 608.0]:
			c.draw_rect(Rect2(lx + _view * 0.14 - 1.5, HORIZON - 15.5, 3.0, 3.0), Color(col("glow"), 0.85 + 0.15 * sin(t * 3.0 + lx)))
		for i in 14:
			var fx := fposmod(i * 97.0 + sin(t * 0.3 + i) * 40.0, W)
			var fy := 360.0 + sin(t * 0.8 + i * 2.1) * 30.0 + (i % 3) * 14.0
			var a := 0.5 + 0.5 * sin(t * 3.0 + i * 1.7)
			var p := Vector2(fx, fy)
			c.draw_primitive(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), PackedColorArray([Color(1.0, 0.85, 0.4, 0.18 * a)]), PackedVector2Array())
			c.draw_rect(Rect2(fx - 1.2, fy - 1.2, 2.4, 2.4), Color(1.0, 0.92, 0.55, a))


func _ellipse(c: CanvasItem, center: Vector2, rx: float, ry: float, colr: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, colr)
