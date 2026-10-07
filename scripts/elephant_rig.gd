class_name ElephantRig
extends RefCounted
## Procedurally animated war elephant in the cute look from the design project
## ("ออกแบบช้างเกม Godot/Elephant.dc.html" with cute = true): big head and eyes, short stumpy
## legs and a dark outline around the whole silhouette (the design's riders are left out). Variant A is the
## ceremonial caparison, variant B (ElephantDef.armored) the scale-armour one.
## The design's SVG paths are parsed once and baked into one mesh per body part and colour set.
## Each frame a pose is picked from the fighter's state, springs ease every joint toward it (so
## moves blend and overshoot instead of snapping) and the legs are placed with 2-bone IK; then
## the parts are drawn twice: first every part's outline in ink, then the parts themselves.
## Arena keeps one rig per Fighter. Local space faces +x, origin on the ground between the feet.

const G := GameData.GROUND
const INK := Color("#231c1f")
const DUST := Color(0.87, 0.77, 0.6)
const LINE := Color("#2a2427")
const EYE_INK := Color("#2a1d17")
const JEWEL := Color("#e04848")
const JEWEL_D := Color("#8e1f1f")

## Design units -> game px; the design point SV_ORIGIN (between the feet) is the rig origin.
const SV := 0.6
const SV_ORIGIN := Vector2(215, 349)
## The head turns about this design point and is drawn 1.35x (the cute proportions).
const HEAD_PIVOT := Vector2(300, 196)
const HK := SV * 1.35
const EAR_PIVOT := Vector2(316, 166)
const TAIL_PIVOT := Vector2(104, 206)
const OUT := 2.2          ## outline thickness, game px
const FEATHER := 0.7      ## antialiased fringe on baked shapes, game px
## Portrait: design point at the medallion centre, and its scale.
const PORTRAIT_C := Vector2(352, 200)
const PK := 0.6

## Legs: [hip, gait phase offset (cycles), front leg, upper length, lower length], game px.
## Far legs first, near legs last. Lengths follow the design's stumpy legs.
const LEGS := [
	[Vector2(-31.8, -67.8), 0.0, false, 38.9, 29.1],
	[Vector2(36.6, -65.4), 0.25, true, 40.6, 25.5],
	[Vector2(-45.0, -67.8), 0.5, false, 38.9, 29.1],
	[Vector2(48.6, -66.6), 0.75, true, 40.6, 25.5],
]
const PITCH_PIVOT := Vector2(0, -80)
const REAR_PIVOT := Vector2(-45, -8)
const NECK := Vector2(51, -91.8)          ## HEAD_PIVOT in game px
## Trunk in the head's design units: root under the cheek, segment lengths and widths.
const TRUNK_ROOT := Vector2(372, 224)
const TRUNK_SEG := [17.0, 17.0, 16.0, 15.0, 14.0]
const TRUNK_W := [24.0, 21.0, 18.0, 16.0, 14.0, 12.0]

## Trunk poses: absolute base angle, then four relative bends (degrees, 0 = forward, 90 = down).
const TRUNK := {
	"rest": [88, 4, 4, 0, -28],
	"air": [55, -8, -8, -10, -10],
	"wind": [-35, -35, -35, -30, -20],
	"whip": [12, -6, -4, 0, 12],
	"tuck": [105, 30, 38, 38, 30],
	"up": [-62, -14, -14, -10, 32],
	"guard": [72, 38, 38, 30, 22],
	"hurt": [58, -18, -18, -18, -10],
	"droop": [95, 4, 2, 0, -5],
	"ko": [62, -14, -18, -18, -8],
	"sweep": [30, -12, -10, -6, 4],
	"roar": [-70, -18, -12, -6, 40],
	"upper": [-12, -26, -22, -16, 8],
	"slam": [52, -8, -8, -4, 22],
	"spray": [-6, -6, -4, -2, -16],
}
const TRUNK_KEYS := ["tb", "t1", "t2", "t3", "t4"]

## Spring per animated value: [frequency Hz, damping ratio]. Low damping = more overshoot.
const SPRING := {
	"bob": [5.0, 0.45], "pitch": [4.5, 0.55], "rear": [2.6, 0.42], "shift": [6.0, 0.6],
	"head": [5.5, 0.5], "ear": [3.5, 0.3], "tail": [1.6, 0.25],
	"sq": [4.5, 0.25],
	"tb": [6.5, 0.6], "t1": [7.0, 0.45], "t2": [6.0, 0.42], "t3": [5.0, 0.4], "t4": [4.2, 0.38],
}

class Puff:
	var pos: Vector2
	var vel: Vector2
	var r: float
	var life: float
	var max_life: float


## A piece of the elephant that moves as one: filled and stroked shapes in design units.
class Part:
	var unit := 0.6       ## game px per unit (outline and antialiasing widths)
	var ops := []         ## [points, closed, fill (palette key / Color / null), stroke, width, alpha]
	var sil := []         ## outline pieces: [points, closed, half width of an open line]


## Triangle geometry whose vertex colours are resolved later from a palette (so one shape serves
## every elephant); edges get a thin transparent fringe for antialiasing.
class Mesher:
	var v := PackedVector2Array()
	var ix := PackedInt32Array()
	var k := PackedInt32Array()      ## colour per vertex: index into `keys`
	var a := PackedFloat32Array()    ## alpha per vertex
	var t := PackedFloat32Array()    ## position in the skin gradient per vertex (-1 = flat colour)
	var keys := []                   ## palette keys and Colors

	func poly(pts: PackedVector2Array, key: Variant, alpha: float, grad: bool, fe: float) -> void:
		var n := pts.size()
		var ts := PackedFloat32Array()
		ts.resize(n)
		ts.fill(-1.0)
		if grad:
			var lo := INF
			var hi := -INF
			for p in pts:
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
			for i in n:
				ts[i] = (pts[i].y - lo) / maxf(1.0, hi - lo)
		var kid := _key(key)
		var b := v.size()
		v.append_array(pts)
		_add(kid, alpha, ts)
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			push_warning("ElephantRig: could not triangulate a shape of %d points" % n)
			for i in range(1, n - 1):
				ix.append_array([b, b + i, b + i + 1])
		else:
			for i in tri:
				ix.append(b + i)
		if fe > 0.0:
			var s := 1.0 if Mesher.area(pts) > 0.0 else -1.0
			var r := v.size()
			for i in n:
				var m := Mesher.normal(pts[(i + n - 1) % n], pts[i], pts[(i + 1) % n]) * s
				v.append_array([pts[i], pts[i] + m * fe])
				k.append_array([kid, kid])
				a.append_array([alpha, 0.0])
				t.append_array([ts[i], ts[i]])
			for i in n:
				var p := r + i * 2
				var q := r + ((i + 1) % n) * 2
				ix.append_array([p, q, p + 1, q, q + 1, p + 1])

	func strip(pts: PackedVector2Array, closed: bool, w: float, key: Variant, alpha: float, fe: float) -> void:
		var n := pts.size()
		if n < 2:
			return
		var hw := w / 2.0
		var kid := _key(key)
		var b := v.size()
		for i in n:
			var m: Vector2
			if closed:
				m = Mesher.normal(pts[(i + n - 1) % n], pts[i], pts[(i + 1) % n])
			elif i == 0:
				m = (pts[1] - pts[0]).orthogonal().normalized()
			elif i == n - 1:
				m = (pts[i] - pts[i - 1]).orthogonal().normalized()
			else:
				m = Mesher.normal(pts[i - 1], pts[i], pts[i + 1])
			v.append_array([pts[i] + m * (hw + fe), pts[i] + m * hw, pts[i] - m * hw, pts[i] - m * (hw + fe)])
			k.append_array([kid, kid, kid, kid])
			a.append_array([0.0, alpha, alpha, 0.0])
			t.append_array([-1.0, -1.0, -1.0, -1.0])
		for i in (n if closed else n - 1):
			var p := b + i * 4
			var q := b + ((i + 1) % n) * 4
			for j in 3:
				ix.append_array([p + j, q + j, p + j + 1, q + j, q + j + 1, p + j + 1])

	## Mesh in the given palette ("skin" is the design's vertical gradient: light top, darker belly).
	func build(pal: Dictionary) -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		var table := []
		for key in keys:
			table.append(key if key is Color else pal[key])
		var top: Color = pal.get("skin_top", Color.WHITE)
		var mid: Color = pal.get("skin", Color.WHITE)
		var bot: Color = pal.get("skin_bot", Color.WHITE)
		var cols := PackedColorArray()
		cols.resize(v.size())
		for i in v.size():
			var g := t[i]
			var col: Color = table[k[i]] if g < 0.0 else (top.lerp(mid, g / 0.55) if g < 0.55 else mid.lerp(bot, (g - 0.55) / 0.45))
			col.a *= a[i]
			cols[i] = col
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = ix
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	func _key(key: Variant) -> int:
		var i := keys.find(key)
		if i < 0:
			keys.append(key)
			i = keys.size() - 1
		return i

	func _add(kid: int, alpha: float, ts: PackedFloat32Array) -> void:
		for i in ts.size():
			k.append(kid)
			a.append(alpha)
		t.append_array(ts)

	## Miter normal at `p` (left of a -> p -> b), lengthened so offsets keep their width.
	static func normal(a: Vector2, p: Vector2, b: Vector2) -> Vector2:
		var n1 := (p - a).orthogonal().normalized()
		var n2 := (b - p).orthogonal().normalized()
		var m := n1 + n2
		if m.length_squared() < 0.0001:
			return n1
		m = m.normalized()
		return m / maxf(m.dot(n1), 0.5)

	static func area(pts: PackedVector2Array) -> float:
		var s := 0.0
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			s += a.x * b.y - b.x * a.y
		return s


static var _parts := {}        ## "a" / "b" -> {part name: Part}
static var _geo := {}          ## "variant/part" -> Mesher (shapes, coloured per palette)
static var _baked := {}        ## "variant/part/palette" -> ArrayMesh
static var _sil_baked := {}    ## "variant/part" -> ArrayMesh (white; drawn tinted with INK)
static var _palettes := {}     ## palette id -> {key: Color}
static var _re: RegEx
static var _cur: Part          ## part being built
static var _pre := Transform2D.IDENTITY    ## applied to points while building
static var _pre_w := 1.0                   ## ...and its scale, applied to stroke widths

var _x := {}
var _v := {}
var _time := randf() * 10.0
var _phase := 0.0
var _move := 0.0
var _lifts := [0.0, 0.0, 0.0, 0.0]
var _was_air := false
var _prev_stun := 0.0
var _prev_bstun := 0.0
var _prev_balance := 100.0
var _dazed := false
var _blink := 0.0
var _next_blink := randf_range(1.5, 4.0)
var _mood := "normal"
var _last_x := 0.0
var _last_atk_t := 0.0
var _streak := Vector3.ZERO     ## lightning-step trail: from x, to x, time left
var _puffs: Array[Puff] = []


## The first rig (the select-screen cards, built while the game loads) prepares every shape and
## outline, so only the colouring (a few ms per elephant) is left for later.
func _init() -> void:
	if _parts.is_empty():
		for v in ["a", "b"]:
			_parts[v] = _build(v)
			for name in _parts[v]:
				_geometry(v, name)
				if not (_parts[v][name] as Part).sil.is_empty():
					_sil_mesh(v, name)


# ---------- animation ----------

func update(f: Fighter, duel_phase: String, dt: float) -> void:
	if dt <= 0.0:
		return
	_time += dt
	var air := f.y < G - 1.0
	var walking := not air and not f.ko and f.stun <= 0.0 and not f.blocking and not f.crouching
	if walking:
		_phase += f.vx * f.face * dt * 0.06
	_move = move_toward(_move, clampf(absf(f.vx) / 200.0, 0.0, 1.0) if walking else 0.0, dt * 5.0)

	if f.stun > _prev_stun + 0.01:
		_kick("sq", 1.5)
		_kick("head", -260.0)
	if f.bstun > _prev_bstun + 0.01:
		_kick("shift", -90.0)
	if f.balance < _prev_balance - 1.0 or (f.dazed <= 0.0 and _dazed and f.stun > 0.0):
		_kick("pitch", -60.0 if f.dazed <= 0.0 else -110.0)
	if _was_air and not air:
		_kick("sq", 2.5)
		for i in 6:
			_puff(f, randf_range(-70.0, 50.0), randf_range(-60.0, 60.0), 1.3)
	elif air and not _was_air:
		_kick("sq", -1.5)
	if _x.has("tb") and f.atk != "storm":
		_x["tb"] = wrapf(_x["tb"], -200.0, 160.0)   # unwind after the trunk storm
	if absf(f.x - _last_x) > 80.0 and _time > 0.1:
		_streak = Vector3(_last_x, f.x, 0.3)
	_streak.z = maxf(0.0, _streak.z - dt)
	if f.atk == "quake" and _last_atk_t < 0.5 and f.atk_t >= 0.5:
		_kick("sq", 3.0)
		for i in 10:
			_puff(f, randf_range(10.0, 120.0), randf_range(40.0, 160.0), 1.6)
	if f.atk == "light3" and _last_atk_t < 0.18 and f.atk_t >= 0.18:
		# the trunk slams into the ground in front
		_kick("sq", 1.2)
		for i in 5:
			_puff(f, randf_range(120.0, 170.0), randf_range(20.0, 120.0), 1.1)
	_last_x = f.x
	_last_atk_t = f.atk_t if f.atk != "" else 0.0
	_was_air = air
	_prev_stun = f.stun
	_prev_bstun = f.bstun
	_prev_balance = f.balance
	_dazed = f.dazed > 0.0 and not f.ko

	for i in 4:
		var lift := maxf(0.0, cos(_phase + float(LEGS[i][1]) * TAU)) * _move
		if _lifts[i] > 0.15 and lift <= 0.15 and _move > 0.4:
			_puff(f, (LEGS[i][0] as Vector2).x, -f.vx * f.face * 0.1, 0.8)
		_lifts[i] = lift
	if not air and (f.atk != "" or f.dash_t > 0.0) and absf(f.vx) > 400.0 and randf() < 0.7:
		_puff(f, -60.0 if f.vx * f.face > 0.0 else 60.0, -120.0 * signf(f.vx * f.face), 1.1)
	if not air and f.stun > 0.0 and absf(f.vx) > 150.0 and randf() < 0.5:
		_puff(f, 30.0, 0.0, 1.0)

	_blink -= dt
	_next_blink -= dt
	if _next_blink <= 0.0:
		_blink = 0.12
		_next_blink = randf_range(2.0, 5.0)

	var over := duel_phase == "ko" or duel_phase == "done"
	if f.ko:
		_mood = "ko"
	elif f.stun > 0.0 and f.dazed > 0.0:
		_mood = "dizzy"
	elif f.stun > 0.0:
		_mood = "hurt"
	elif over and f.win:
		_mood = "happy"
	else:
		_mood = "normal"

	_step_springs(_targets(f, over, air), dt)

	var alive: Array[Puff] = []
	for p in _puffs:
		p.life -= dt
		if p.life > 0.0:
			p.pos += p.vel * dt
			p.vel *= 0.9
			p.r += dt * 26.0
			alive.append(p)
	_puffs = alive


func _targets(f: Fighter, over: bool, air: bool) -> Dictionary:
	var tm := _time
	var p := {
		"bob": 1.0 + sin(tm * 2.2) * 1.2 + absf(sin(_phase)) * 3.0 * _move,
		"pitch": 0.0, "rear": 0.0, "shift": 0.0, "sq": 0.0,
		"head": sin(tm * 1.7) * 2.0 + sin(_phase * 2.0) * 3.0 * _move,
		"ear": 0.82 + 0.32 * pow(maxf(0.0, sin(tm * 2.3)), 6.0),
		"tail": sin(tm * 1.9) * 10.0 + f.vx * f.face * 0.03,
		
	}
	_trunk(p, "rest")
	p["tb"] += sin(tm * 1.5) * 6.0

	if air:
		p["pitch"] = clampf(f.vy * 0.015, -10.0, 10.0)
		p["ear"] = 1.1
		_trunk(p, "air")
	if f.dash_t > 0.0 and f.atk == "" and not air:
		if f.dash_dir == f.face:
			_apply(p, {"pitch": 5.0, "head": 12.0, "shift": 8.0, "ear": 0.55})
			_trunk(p, "tuck")
		else:
			_apply(p, {"pitch": -6.0, "head": -14.0, "shift": -8.0, "ear": 1.15})
	if f.atk != "":
		_attack_pose(p, f)
	if f.stun > 0.0 and not f.ko:
		_apply(p, {"pitch": -8.0, "head": -18.0, "shift": -6.0, "ear": 1.2})
		_trunk(p, "hurt")
	if f.dazed > 0.0 and not f.ko:
		if f.stun > 0.0:
			# reeling from the balance break: head lolls, body sways, trunk hangs
			_apply(p, {"head": 16.0 + sin(tm * 5.5) * 9.0, "pitch": sin(tm * 4.0) * 4.0, "shift": sin(tm * 4.0) * 6.0, "ear": 0.7, "bob": 4.0})
			_trunk(p, "droop")
			p["tb"] += sin(tm * 5.5) * 10.0
	if f.crouching and f.atk == "" and not f.ko:
		# hunkered down: knees bent, head low
		_apply(p, {"bob": 14.0, "head": 14.0, "pitch": 2.0, "ear": 0.75})
		_trunk(p, "guard" if f.blocking else "tuck")
	elif f.blocking:
		_apply(p, {"bob": 7.0, "head": 12.0, "pitch": 3.0, "ear": 0.6})
		_trunk(p, "guard")
	if over and f.atk == "" and not f.ko:
		if f.win:
			_apply(p, {"rear": -22.0 + sin(tm * 3.0) * 3.0, "head": -20.0, "ear": 1.1})
			_trunk(p, "up")
		else:
			_apply(p, {"head": 14.0, "ear": 0.6})
			_trunk(p, "droop")
	if f.ko:
		# thrown back while airborne, then collapse onto the belly
		if air:
			_apply(p, {"rear": -24.0, "pitch": 0.0, "head": -25.0, "ear": 1.2, "bob": 0.0})
		else:
			_apply(p, {"rear": 0.0, "pitch": 5.0, "head": 24.0, "ear": 1.15, "bob": 24.0})
		_trunk(p, "ko")
	return p


## Pose for the move being performed. `t` is time into the move; most moves go
## wind-up -> strike -> ease back (k fades 1 -> 0 over the recovery).
func _attack_pose(p: Dictionary, f: Fighter) -> void:
	var m := GameData.move(f.atk)
	var t := f.atk_t
	var h: GameData.Hit = m.hits[0] if not m.hits.is_empty() else null
	var pre := h != null and t < h.start
	var act := h != null and t >= h.start and t <= h.stop
	var k := 1.0 if h == null or t <= h.stop else maxf(0.0, 1.0 - (t - h.stop) / (m.dur - h.stop))
	match f.atk:
		"light":
			if pre:
				_apply(p, {"head": -8.0})
				_trunk(p, "wind")
			elif act:
				_apply(p, {"head": 6.0, "shift": 6.0})
				_trunk(p, "whip")
		"mid":
			# rocks back, then drives both tusks straight ahead
			if pre:
				_apply(p, {"shift": -10.0, "head": -10.0, "pitch": -3.0, "ear": 1.15})
			else:
				_apply(p, {"shift": 20.0 * k, "head": 16.0 * k, "pitch": 6.0 * k, "ear": 1.1})
			_trunk(p, "tuck")
		"clow":
			# from a crouch, flicks the trunk along the ground
			_apply(p, {"bob": 18.0, "head": 20.0 if act else 10.0, "pitch": 4.0, "shift": 6.0 if act else 0.0, "ear": 0.8})
			_trunk(p, "sweep" if act else "tuck")
		"cmid":
			# low sweep at the legs
			if pre:
				_apply(p, {"bob": 16.0, "head": 8.0, "shift": -6.0, "ear": 1.2})
				_trunk(p, "wind")
			else:
				_apply(p, {"bob": 16.0 * maxf(k, 0.4), "head": 26.0 * k, "pitch": 6.0 * k, "shift": 12.0 * k, "ear": 1.1})
				_trunk(p, "sweep" if k > 0.3 else "tuck")
		"spout":
			# draws water up the trunk, then sprays it forward
			if t < m.event_at:
				_apply(p, {"head": -6.0, "pitch": -2.0, "shift": -6.0, "ear": 1.25, "bob": 4.0})
				_trunk(p, "tuck")
			else:
				var ks := maxf(0.0, 1.0 - (t - m.event_at) / (m.dur - m.event_at))
				_apply(p, {"head": -14.0 * ks, "shift": 8.0 * ks, "pitch": 3.0 * ks, "ear": 1.1})
				_trunk(p, "spray")
		"uppercut":
			# crouches, then rears up swatting the trunk skywards
			if pre:
				_apply(p, {"bob": 8.0, "head": 12.0, "pitch": 4.0, "ear": 0.6})
				_trunk(p, "tuck")
			else:
				_apply(p, {"rear": -20.0 * k, "head": -26.0 * k, "pitch": -4.0 * k, "ear": 1.25})
				_trunk(p, "upper" if k > 0.5 else "rest")
		"light2":
			# backhand: the trunk drops low, then swings up and across
			if pre:
				_apply(p, {"head": 6.0})
				_trunk(p, "tuck")
			elif act:
				_apply(p, {"head": -10.0, "shift": 8.0, "pitch": -2.0})
				_trunk(p, "upper")
		"light3":
			# trunk raised high, then slammed down in front
			if pre:
				_apply(p, {"rear": -8.0, "head": -20.0, "ear": 1.2})
				_trunk(p, "up")
			else:
				_apply(p, {"rear": 2.0 * k, "pitch": 9.0 * k, "head": 22.0 * k, "shift": 14.0 * k})
				_trunk(p, "slam")
		"dive":
			_apply(p, {"pitch": 14.0, "head": 26.0, "shift": 8.0, "ear": 1.25})
			_trunk(p, "tuck")
		"counter":
			if pre:
				_apply(p, {"bob": 6.0, "head": 10.0, "shift": -8.0})
				_trunk(p, "guard")
			else:
				_apply(p, {"pitch": 6.0 * k, "head": 20.0 * k, "shift": 22.0 * k, "ear": 1.2})
				_trunk(p, "tuck")
		"gore":
			if pre:
				_apply(p, {"pitch": -6.0, "shift": -8.0, "head": -12.0})
			else:
				_apply(p, {"pitch": 8.0 * k, "shift": 18.0 * k, "head": 22.0 * k})
			_trunk(p, "tuck")
		"hook":
			# tusk sweeps down then yanks back
			if pre:
				_apply(p, {"pitch": -4.0, "shift": -4.0, "head": -16.0})
			elif act:
				_apply(p, {"pitch": 6.0, "shift": 10.0, "head": 22.0})
			else:
				_apply(p, {"shift": -12.0 * k, "head": -8.0 * k, "pitch": -3.0 * k})
			_trunk(p, "tuck")
		"lunge":
			if pre:
				_apply(p, {"bob": 7.0, "pitch": 4.0, "head": 6.0, "ear": 0.6})
			else:
				_apply(p, {"pitch": 10.0 * k, "head": 22.0 * k, "shift": 14.0 * k, "ear": 1.1})
			_trunk(p, "tuck")
		"headbutt":
			# long rear-back while armored, then the head comes down hard
			if pre:
				_apply(p, {"pitch": -10.0, "rear": -5.0, "head": -26.0, "shift": -14.0, "ear": 0.6})
			else:
				_apply(p, {"pitch": 12.0 * k, "head": 30.0 * k, "shift": 24.0 * k, "ear": 1.2})
			_trunk(p, "tuck")
		"sweep":
			if pre:
				_apply(p, {"head": -6.0})
				_trunk(p, "wind")
			elif act:
				_apply(p, {"head": 10.0, "shift": 6.0, "pitch": 3.0})
				_trunk(p, "sweep")
		"double":
			var h2 := m.hits[1]
			if t < h.start:
				_apply(p, {"pitch": -5.0, "shift": -6.0, "head": -12.0})
			elif t <= h.stop + 0.04:
				_apply(p, {"pitch": 6.0, "shift": 12.0, "head": 18.0})
			elif t < h2.start:
				_apply(p, {"pitch": -4.0, "shift": 0.0, "head": -12.0})
			else:
				var k2 := 1.0 if t <= h2.stop else maxf(0.0, 1.0 - (t - h2.stop) / (m.dur - h2.stop))
				_apply(p, {"pitch": 10.0 * k2, "shift": 20.0 * k2, "head": 26.0 * k2})
			_trunk(p, "tuck")
		"charge3":
			# trumpet, ram, gore, then rear up and bring the head down for the last blow
			var h2 := m.hits[1]
			var h3 := m.hits[2]
			if t < h.start:
				_apply(p, {"rear": -8.0, "head": -16.0, "ear": 1.2})
				_trunk(p, "up")
			elif t < h.stop:
				_apply(p, {"pitch": 7.0, "head": 14.0, "shift": 10.0, "ear": 1.15})
				_trunk(p, "tuck")
			elif t < h2.stop + 0.04:
				_apply(p, {"pitch": 8.0, "head": 24.0, "shift": 16.0})
				_trunk(p, "tuck")
			elif t < h3.start:
				_apply(p, {"rear": -12.0, "head": -22.0, "pitch": -4.0, "ear": 1.2})
				_trunk(p, "up")
			else:
				var k3 := 1.0 if t <= h3.stop + 0.06 else maxf(0.0, 1.0 - (t - h3.stop) / (m.dur - h3.stop))
				_apply(p, {"pitch": 12.0 * k3, "head": 30.0 * k3, "shift": 20.0 * k3, "ear": 1.2})
				_trunk(p, "tuck")
		"storm":
			# trumpets, then whirls the trunk round and round
			var spin := clampf((t - 0.15) / 0.8, 0.0, 1.0)
			_apply(p, {"head": -10.0, "ear": 1.2, "bob": 4.0})
			_trunk(p, "sweep")
			p["tb"] = 30.0 + spin * 720.0
		"blink":
			if t < m.event_at:
				_apply(p, {"bob": 8.0, "pitch": 6.0, "head": 10.0, "ear": 0.6})
			elif pre:
				_apply(p, {"pitch": -4.0, "head": -12.0, "shift": -4.0})
			else:
				_apply(p, {"pitch": 10.0 * k, "head": 24.0 * k, "shift": 16.0 * k})
			_trunk(p, "tuck")
		"quake":
			# rear up on the hind legs, then slam the forefeet down
			if t < 0.45:
				_apply(p, {"rear": -26.0, "head": -20.0, "ear": 1.2})
				_trunk(p, "up")
			elif t < 0.75:
				_apply(p, {"rear": 4.0, "pitch": 6.0, "head": 14.0, "bob": 6.0})
				_trunk(p, "droop")
		"blessing":
			_apply(p, {"rear": -10.0, "head": -18.0, "ear": 1.2})
			_trunk(p, "up")
		"roar":
			_apply(p, {"rear": -6.0, "head": -24.0, "ear": 1.3, "shift": 4.0})
			_trunk(p, "roar")


func _trunk(p: Dictionary, pose: String) -> void:
	var a: Array = TRUNK[pose]
	for i in 5:
		p[TRUNK_KEYS[i]] = float(a[i])


func _apply(p: Dictionary, values: Dictionary) -> void:
	for k in values:
		p[k] = values[k]


func _kick(key: String, amount: float) -> void:
	_v[key] = float(_v.get(key, 0.0)) + amount


func _step_springs(targets: Dictionary, dt: float) -> void:
	var steps := ceili(dt * 120.0)
	var h := dt / steps
	for key in SPRING:
		var target: float = targets[key]
		var x: float = _x.get(key, target)
		var v: float = _v.get(key, 0.0)
		var w: float = TAU * float(SPRING[key][0])
		var z: float = SPRING[key][1]
		for i in steps:
			v += (w * w * (target - x) - 2.0 * z * w * v) * h
			x += v * h
		_x[key] = x
		_v[key] = v


func _g(key: String) -> float:
	return _x.get(key, 0.0)


func _puff(f: Fighter, local_x: float, speed: float, size: float) -> void:
	var p := Puff.new()
	p.pos = Vector2(f.x + local_x * f.face, G - 4.0)
	p.vel = Vector2(speed * f.face + randf_range(-30.0, 30.0), randf_range(-40.0, -10.0))
	p.r = randf_range(4.0, 7.0) * size
	p.max_life = randf_range(0.35, 0.6)
	p.life = p.max_life
	_puffs.append(p)


# ---------- drawing ----------

## Dust and the lightning-step streak are drawn in arena space, before both elephants.
func draw_dust(c: CanvasItem, base: Transform2D) -> void:
	c.draw_set_transform_matrix(base)
	if _streak.z > 0.0:
		var a := _streak.z / 0.3
		for i in 4:
			var y := G - 150.0 + i * 28.0
			c.draw_line(Vector2(_streak.x, y), Vector2(_streak.y, y), Color(GameData.GOLD_LIGHT, a * (1.0 - i * 0.18)), 4.0 - i * 0.6, true)
	for p in _puffs:
		DrawKit.circle(c, p.pos, p.r, Color(DUST, 0.7 * p.life / p.max_life))


func draw(c: CanvasItem, f: Fighter, base: Transform2D) -> void:
	var d := f.def
	var v := "b" if d.armored else "a"
	var pal := _palette(d, f.flash > 0.0)
	var air := f.y < G - 1.0
	var root := base.translated_local(Vector2(f.x, f.y)).scaled_local(Vector2(f.face, 1.0))

	c.draw_set_transform_matrix(root)
	var sw := 180.0 * (1.0 - minf(0.5, (G - f.y) / 400.0))
	DrawKit.ellipse(c, Vector2(-2.0, G - f.y + 2.0), sw / 2.0, 7.0, Color(0.1, 0.05, 0.0, 0.28))
	if f.atk != "":
		var m := GameData.move(f.atk)
		if m.dash_speed > 0.0 and f.atk_t > m.dash_start and f.atk_t < m.dash_stop and absf(f.vx) > 300.0:
			for i in 4:
				c.draw_rect(Rect2(-180 - i * 18, -130 + i * 26, 70 - i * 8, 4), Color(1, 1, 1, 0.75))
		_draw_move_fx(c, f, m)
	if f.atk_ex and f.atk != "":
		# EX move: a pulsing gold aura behind the elephant
		var pulse := 0.5 + 0.5 * sin(_time * 18.0)
		DrawKit.ellipse(c, Vector2(0, -95), 135.0, 100.0, Color(GameData.GOLD_LIGHT, 0.18 + 0.12 * pulse))
		DrawKit.ellipse(c, Vector2(0, -95), 112.0, 82.0, Color(GameData.GOLD, 0.16 + 0.1 * pulse))
	if f.buff_t > 0.0:
		# blessing: gold diamonds circling the elephant while the boost lasts
		for i in 3:
			var a := _time * 2.5 + TAU * i / 3.0
			var sp := Vector2(cos(a) * 95.0, -95.0 + sin(a) * 22.0)
			_fill(c, PackedVector2Array([sp + Vector2(0, -7), sp + Vector2(6, 0), sp + Vector2(0, 7), sp + Vector2(-6, 0)]), GameData.GOLD_LIGHT)

	var bx := _body_xform()
	var legs := []
	for i in 4:
		legs.append(_solve_leg(i, bx, f, air))
	var body := root * bx
	var bsv := body * Transform2D(0.0, Vector2(SV, SV), 0.0, -SV_ORIGIN * SV)
	var head := body * Transform2D(deg_to_rad(_g("head")), NECK) * Transform2D(0.0, Vector2(HK, HK), 0.0, -HEAD_PIVOT * HK)
	var ear := head * _ear_xform()
	var tail := bsv * _about(TAIL_PIVOT, deg_to_rad(_g("tail")))
	var trunk := _trunk_chain(false)

	for step in 2:
		var ol := step == 0
		for i in 2:
			_draw_leg(c, root, legs[i], i, v, pal, ol)
		_part(c, tail, v, "tail", pal, ol)
		_part(c, bsv, v, "torso", pal, ol)
		for i in range(2, 4):
			_draw_leg(c, root, legs[i], i, v, pal, ol)
		_part(c, bsv, v, "body", pal, ol)
		_part(c, bsv, v, "pole", pal, ol)
		if d.royal:
			_draw_umbrella(c, bsv, d, ol)
		else:
			_draw_flag(c, bsv, d, pal, ol)
		_draw_head(c, head, ear, trunk, v, d, pal, ol)

	if _mood == "dizzy":
		c.draw_set_transform_matrix(head)
		for i in 4:
			var a := _time * 4.0 + TAU * i / 4.0
			var sp := Vector2(338, 112) + Vector2(cos(a) * 34.0, sin(a) * 9.0)
			_fill(c, _star(sp, 7.0 if sin(a) > 0.0 else 5.0), GameData.GOLD_LIGHT if i % 2 == 0 else Color.WHITE)
	if _dazed and _mood != "dizzy":
		# still off balance after the reel: three gold stars over the crown
		c.draw_set_transform_matrix(head)
		for i in 3:
			var a := _time * 6.0 + TAU * i / 3.0
			var sp := Vector2(338, 100) + Vector2(cos(a) * 20.0, sin(a) * 6.0)
			_fill(c, _star(sp, 6.0), GameData.GOLD_LIGHT if i != 0 else Color.WHITE)
	if f.blocking or f.bstun > 0.0:
		# guard shield: low and wide when crouching
		c.draw_set_transform_matrix(root)
		var gy := -58.0 if f.crouching else -86.0
		c.draw_arc(Vector2(70, gy), 90.0, -0.75, 0.75, 20, Color(GameData.GOLD_LIGHT, 0.85), 5.0, true)
		c.draw_arc(Vector2(70, gy), 98.0, -0.6, 0.6, 16, Color(GameData.GOLD, 0.5), 3.0, true)


## Head-and-shoulders view for the HUD medallion, in the same pose as the fighter.
func draw_portrait(c: CanvasItem, f: Fighter, xf: Transform2D) -> void:
	var d := f.def
	var v := "b" if d.armored else "a"
	var pal := _palette(d, f.flash > 0.0)
	var head := xf * Transform2D(0.0, Vector2(PK, PK), 0.0, -PORTRAIT_C * PK)
	var trunk := _trunk_chain(true)
	for step in 2:
		_draw_head(c, head, head * _ear_xform(), trunk, v, d, pal, step == 0)


func _draw_head(c: CanvasItem, head: Transform2D, ear: Transform2D, trunk: Array, v: String, d: ElephantDef, pal: Dictionary, ol: bool) -> void:
	_part(c, head, v, "tusk_far", pal, ol)
	_draw_trunk(c, head, trunk, pal, ol)
	if _g("tb") < 0.0:
		# trunk raised: the mouth opens (trumpeting)
		_part(c, head, v, "mouth", pal, ol)
	_part(c, head, v, "head", pal, ol)
	if d.royal:
		_part(c, head, v, "crown", pal, ol)
	_part(c, ear, v, "ear", pal, ol)
	if d.royal:
		_part(c, ear, v, "earring", pal, ol)
	if not ol:
		_draw_face(c, head, v, pal)


## Ears flare out when the spring value is high (alarmed, attacking) and fold back when low.
func _ear_xform() -> Transform2D:
	var e := _g("ear")
	var sx := 1.12 * lerpf(0.88, 1.1, clampf((e - 0.55) / 0.75, 0.0, 1.0))
	return Transform2D(0.0, EAR_PIVOT) * Transform2D(deg_to_rad((e - 0.85) * -22.0), Vector2(sx, 1.12), 0.0, Vector2.ZERO) * Transform2D(0.0, -EAR_PIVOT)


## One baked part: its ink outline in the first pass, the part itself in the second.
func _part(c: CanvasItem, xf: Transform2D, v: String, name: String, pal: Dictionary, ol: bool) -> void:
	c.draw_set_transform_matrix(xf)
	if ol:
		c.draw_mesh(_sil_mesh(v, name), null, Transform2D.IDENTITY, INK)
	else:
		c.draw_mesh(_mesh(v, name, pal), null)


## Leg from the IK solution: upper leg, a knee to cover the joint, lower leg with anklet and nails.
func _draw_leg(c: CanvasItem, root: Transform2D, leg: Array, i: int, v: String, pal: Dictionary, ol: bool) -> void:
	var hip: Vector2 = leg[0]
	var knee: Vector2 = leg[1]
	var foot: Vector2 = leg[2]
	var tag: String = ("f" if LEGS[i][2] else "h") + ("n" if i >= 2 else "f")
	_part(c, root * Transform2D((knee - hip).angle() - PI / 2.0, Vector2(SV, SV), 0.0, hip), v, "up_" + tag, pal, ol)
	c.draw_set_transform_matrix(root)
	var kc: Color = INK if ol else ((pal["skin"] as Color).lerp(pal["skin_bot"], 0.6) if i >= 2 else pal["far"])
	DrawKit.circle(c, knee, 14.0 + (OUT if ol else 0.0), kc)
	_part(c, root * Transform2D((foot - knee).angle() - PI / 2.0, Vector2(SV, SV), 0.0, knee), v, "lo_" + tag, pal, ol)


## Trunk as a smoothed chain of quads, lit on its upper/front side, with creases and a nostril.
func _draw_trunk(c: CanvasItem, xf: Transform2D, tr: Array, pal: Dictionary, ol: bool) -> void:
	c.draw_set_transform_matrix(xf)
	var sm: PackedVector2Array = tr[0]
	var w: PackedFloat32Array = tr[1]
	var n := sm.size()
	var o := OUT / HK if ol else 0.0
	var lit: Color = INK if ol else (pal["skin_top"] as Color).lerp(pal["skin"], 0.35)
	var shade: Color = INK if ol else pal["skin_bot"]
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var dirs := PackedVector2Array()
	for i in n:
		var dir := (sm[mini(i + 1, n - 1)] - sm[maxi(i - 1, 0)]).normalized()
		dirs.append(dir)
		left.append(sm[i] + dir.orthogonal() * (w[i] / 2.0 + o))
		right.append(sm[i] - dir.orthogonal() * (w[i] / 2.0 + o))
	for i in n - 1:
		c.draw_primitive(PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]]),
			PackedColorArray([lit, lit, shade, shade]), PackedVector2Array())
	var tip := sm[n - 1]
	var tr_ := w[n - 1] / 2.0 + o
	var tip_col: Color = INK if ol else (pal["skin"] as Color)
	DrawKit.circle(c, tip, tr_, tip_col)
	var edge: Color = INK if ol else pal["skinD"]
	var ew := 1.2 / HK if ol else 1.6
	c.draw_polyline(left, edge, ew, true)
	c.draw_polyline(right, edge, ew, true)
	var ta := dirs[n - 1].angle()
	c.draw_arc(tip, tr_, ta - PI / 2.0, ta + PI / 2.0, 10, edge, ew, true)
	if ol:
		return
	var crease := Color(pal["skinD"], 0.55)
	for i in range(3, n - 1, 3):
		var nn := dirs[i].orthogonal() * w[i]
		c.draw_line(sm[i] + nn * 0.42, sm[i] - nn * 0.32, crease, 1.4, true)
	DrawKit.circle(c, tip + dirs[n - 1] * w[n - 1] * 0.2, w[n - 1] * 0.18, Color(pal["skinD"], 0.8))


## Trunk centre line from the springs (or a short curl for the portrait), smoothed: [points, widths].
func _trunk_chain(portrait: bool) -> Array:
	var pts: Array[Vector2] = [TRUNK_ROOT]
	if portrait:
		for i in 2:
			pts.append(pts[i] + Vector2.from_angle(deg_to_rad(80.0) + i * 0.6) * 15.0)
	else:
		var a := deg_to_rad(_g("tb"))
		for i in 5:
			if i > 0:
				a += deg_to_rad(_g(TRUNK_KEYS[i]))
			pts.append(pts[i] + Vector2.from_angle(a) * float(TRUNK_SEG[i]))
	var sm := PackedVector2Array()
	var w := PackedFloat32Array()
	var n := pts.size()
	for i in n - 1:
		for s in 3:
			var t := s / 3.0
			sm.append(pts[i].cubic_interpolate(pts[i + 1], pts[maxi(i - 1, 0)], pts[mini(i + 2, n - 1)], t))
			w.append(lerpf(TRUNK_W[i], TRUNK_W[i + 1], t))
	sm.append(pts[n - 1])
	w.append(TRUNK_W[n - 1])
	return [sm, w]


## Eyes (with the mood), blush.
func _draw_face(c: CanvasItem, xf: Transform2D, v: String, pal: Dictionary) -> void:
	c.draw_set_transform_matrix(xf)
	c.draw_mesh(_mesh(v, "blush", pal), null)
	var e := Vector2(362, 180)
	match _mood:
		"ko":
			c.draw_line(e + Vector2(-6, -6), e + Vector2(6, 6), EYE_INK, 2.4, true)
			c.draw_line(e + Vector2(-6, 6), e + Vector2(6, -6), EYE_INK, 2.4, true)
		"hurt":
			c.draw_polyline(PackedVector2Array([e + Vector2(-6, -6), e + Vector2(5, 0), e + Vector2(-6, 6)]), EYE_INK, 2.4, true)
		"happy":
			c.draw_polyline(PackedVector2Array([e + Vector2(-7, 3), e + Vector2(-3.5, -2), e + Vector2(0, -4), e + Vector2(3.5, -2), e + Vector2(7, 3)]), EYE_INK, 2.4, true)
		"dizzy":
			DrawKit.ellipse(c, e, 7.5, 8.5, Color.WHITE)
			var a0 := _time * 9.0
			c.draw_arc(e, 5.5, a0, a0 + TAU * 0.8, 12, EYE_INK, 1.6, true)
			c.draw_arc(e, 2.6, a0 + PI, a0 + PI + TAU * 0.7, 10, EYE_INK, 1.4, true)
		_:
			if _blink > 0.0:
				c.draw_polyline(PackedVector2Array([e + Vector2(-7, 1), e + Vector2(-3.5, 3.5), e + Vector2(0, 4.2), e + Vector2(3.5, 3.5), e + Vector2(7, 1)]), EYE_INK, 2.2, true)
			else:
				c.draw_mesh(_mesh(v, "eye", pal), null)


## War flag on a pole over the howdah, streaming back with a swallowtail and a gold disc.
func _draw_flag(c: CanvasItem, xf: Transform2D, d: ElephantDef, pal: Dictionary, ol: bool) -> void:
	c.draw_set_transform_matrix(xf)
	var t := _time * 6.0 + _phase * 3.0
	var flag := PackedVector2Array()
	for i in 5:
		var k := i / 4.0
		flag.append(Vector2(lerpf(231.0, 178.0, k), lerpf(-4.0, 0.0, k) + sin(t - i * 1.1) * 3.0 * k))
	flag.append(Vector2(190.0 + sin(t - 4.4) * 1.5, 13.0 + sin(t - 4.4) * 2.0))
	for i in range(4, -1, -1):
		var k := i / 4.0
		flag.append(Vector2(lerpf(231.0, 178.0, k), lerpf(24.0, 26.0, k) + sin(t - i * 1.1) * 3.0 * k))
	if ol:
		_ink_poly(c, flag, OUT / SV)
		return
	c.draw_colored_polygon(flag, d.flag)
	c.draw_polyline(flag + PackedVector2Array([flag[0]]), pal["gold"], 2.5, true)
	var disc := Vector2(212, 11.0 + sin(t - 2.2) * 1.5)
	DrawKit.circle(c, disc, 4.5, pal["goldD"])
	DrawKit.circle(c, disc, 3.6, pal["gold"])


## Royal tiered umbrella in place of the flag.
func _draw_umbrella(c: CanvasItem, xf: Transform2D, d: ElephantDef, ol: bool) -> void:
	c.draw_set_transform_matrix(xf)
	var gold := d.trim
	var sway := sin(_time * 1.8 + _phase) * 2.0
	var top := Vector2(233.0 + sway, -68.0)
	if ol:
		c.draw_line(Vector2(233, -8), top, INK, 3.5 + 2.0 * OUT / SV, true)
	else:
		c.draw_line(Vector2(233, -8), top, Color("#5b3a1f"), 3.5, true)
	for i in 5:
		var y := 4.0 - i * 13.0
		var hw := 44.0 - i * 7.5
		var x := 233.0 + sway * (i + 1) / 6.0
		var tier := PackedVector2Array([Vector2(x - hw * 0.7, y - 10), Vector2(x + hw * 0.7, y - 10), Vector2(x + hw, y), Vector2(x - hw, y)])
		if ol:
			_ink_poly(c, tier, OUT / SV)
			continue
		c.draw_primitive(tier, PackedColorArray([Color("#fff6e2"), Color("#fff6e2"), Color("#e8d8b8"), Color("#e8d8b8")]), PackedVector2Array())
		c.draw_line(Vector2(x - hw, y), Vector2(x + hw, y), gold, 3.0, true)
		for k in int(hw / 7.0):
			DrawKit.circle(c, Vector2(x - hw + 4.0 + k * 14.0, y + 3.5), 2.2, gold)
	var spire := PackedVector2Array([top + Vector2(-5, 2), top + Vector2(0, -16), top + Vector2(5, 2)])
	if ol:
		_ink_poly(c, spire, OUT / SV)
	else:
		_fill(c, spire, gold)


## Ink silhouette of a shape whose points change every frame.
func _ink_poly(c: CanvasItem, pts: PackedVector2Array, grow: float) -> void:
	for q in Geometry2D.offset_polygon(pts, grow, Geometry2D.JOIN_ROUND):
		c.draw_colored_polygon(q, INK)
		c.draw_polyline(q + PackedVector2Array([q[0]]), INK, 1.0, true)


## Extra shapes for ultimates, drawn in the elephant's root space before the body.
func _draw_move_fx(c: CanvasItem, f: Fighter, m: GameData.Move) -> void:
	var t := f.atk_t
	match m.id:
		"blessing":
			if t > 0.15 and t < m.dur:
				var a := clampf(minf((t - 0.15) * 5.0, (m.dur - t) * 4.0), 0.0, 1.0)
				var center := Vector2(0, -105)
				DrawKit.circle(c, center, 120.0, Color(GameData.GOLD_LIGHT, 0.18 * a))
				for i in 12:
					var ang := TAU * i / 12.0 + t * 1.5
					var dv := Vector2.from_angle(ang)
					var n := dv.orthogonal() * 7.0
					_fill(c, PackedVector2Array([center + dv * 70.0 + n, center + dv * (150.0 + 20.0 * sin(t * 8.0 + i)), center + dv * 70.0 - n]), Color(GameData.GOLD_LIGHT, a * 0.85))
		"roar":
			if t > 0.25 and t < 0.7:
				var mouth := Vector2(118, -150)
				for i in 3:
					var r := fmod((t - 0.25) * 420.0 + i * 50.0, 150.0) + 20.0
					c.draw_arc(mouth, r, -0.9, 0.9, 18, Color(GameData.GOLD_LIGHT, 1.0 - r / 170.0), 5.0, true)
					c.draw_arc(mouth, r + 6.0, -0.8, 0.8, 18, Color(GameData.ACC, 0.6 - r / 300.0), 3.0, true)
		"storm":
			# gusts whirling round the head while the trunk spins
			if t > 0.15 and t < 0.95:
				var hub := _body_xform() * (NECK + Vector2(40, 0))
				for i in 3:
					var a0 := t * 14.0 + TAU * i / 3.0
					c.draw_arc(hub, 70.0 + i * 12.0, a0, a0 + 1.7, 14, Color(1, 1, 1, 0.5 - i * 0.1), 4.0, true)
					c.draw_arc(hub, 64.0 + i * 12.0, a0 + 0.3, a0 + 1.3, 10, Color(DUST, 0.45), 3.0, true)


## The body sits low on its short legs, so crouches and collapses sink it a little less.
func _body_xform() -> Transform2D:
	var sq := _g("sq")
	var xf := Transform2D.IDENTITY.scaled(Vector2(1.0 + sq * 0.5, 1.0 - sq))
	xf = xf * Transform2D(0.0, Vector2(_g("shift"), _g("bob") * 0.75))
	xf = xf * _about(REAR_PIVOT, deg_to_rad(_g("rear")))
	xf = xf * _about(PITCH_PIVOT, deg_to_rad(_g("pitch")))
	return xf


func _about(p: Vector2, a: float) -> Transform2D:
	return Transform2D(0.0, p) * Transform2D(a, Vector2.ZERO) * Transform2D(0.0, -p)


func _solve_leg(i: int, bx: Transform2D, f: Fighter, air: bool) -> Array:
	var hip_b: Vector2 = LEGS[i][0]
	var front: bool = LEGS[i][2]
	var upper: float = LEGS[i][3]
	var lower: float = LEGS[i][4]
	var hip := bx * hip_b
	var target: Vector2
	var ph := _phase + float(LEGS[i][1]) * TAU
	if f.ko and air:
		target = hip + Vector2(10.0 if front else -10.0, 82.0).rotated(deg_to_rad(_g("rear") + _g("pitch")))
	elif f.ko:
		target = Vector2(hip_b.x + (24.0 if front else -24.0), 0.0)
	elif air:
		target = hip + Vector2(12.0 if front else -16.0, 44.0)
	elif front and _g("rear") < -10.0:
		target = hip + Vector2(18.0, 40.0)
	else:
		var spread := (6.0 if front else -4.0) if f.blocking else 0.0
		if f.crouching:
			spread = 10.0 if front else -8.0   # feet planted wide rather than knees jutting out
		target = Vector2(hip_b.x + spread + sin(ph) * 22.0 * _move, -maxf(0.0, cos(ph)) * 14.0 * _move)
	# 2-bone IK; the joint always points forward (elephant knees and wrists both do)
	var to := target - hip
	var dist := clampf(to.length(), 1.0, upper + lower - 0.5)
	var dir := to.normalized() if to.length() > 0.001 else Vector2.DOWN
	var cos_a := clampf((upper * upper + dist * dist - lower * lower) / (2.0 * upper * dist), -1.0, 1.0)
	var knee := hip + dir.rotated(-acos(cos_a)) * upper
	return [hip, knee, hip + dir * dist]


func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	return pts


## Flat polygon; larger ones get a 1px antialiased rim (the GL Compatibility renderer has no
## 2D MSAA). Tiny ornaments skip it: each rim is a separate draw call.
func _fill(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	DrawKit.fill(c, pts, PackedColorArray([col]))
	if pts.size() > 4:
		c.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.0, true)


# ---------- baked parts ----------

## Colours for one elephant (and its hit flash), keyed like the design's palette.
static func _palette(d: ElephantDef, flash: bool) -> Dictionary:
	var id := "%d%s" % [d.get_instance_id(), "!" if flash else ""]
	if not _palettes.has(id):
		var b := d.body
		var dk := d.dark
		if flash:
			b = b.lerp(GameData.ACC_300, 0.8)
			dk = dk.lerp(GameData.HURT_DARK, 0.8)
		var g := d.trim
		_palettes[id] = {
			"id": id,
			"skin": b, "skin_top": b.lightened(0.25), "skin_bot": b.darkened(0.25),
			"skinD": b.darkened(0.42), "skinL": b.lightened(0.45), "skinFlat": b,
			"far": dk, "farD": dk.darkened(0.33), "pink": b.lerp(Color("#e7a3a3"), 0.5),
			"cloth": d.cloth, "clothD": d.cloth.darkened(0.35), "clothL": d.cloth.lightened(0.3),
			"gold": g, "goldD": g.darkened(0.35), "goldFar": g.darkened(0.22), "goldFarD": g.darkened(0.5),
		}
	return _palettes[id]


static func _mesh(v: String, name: String, pal: Dictionary) -> ArrayMesh:
	var key := "%s/%s/%s" % [v, name, pal["id"]]
	var m: ArrayMesh = _baked.get(key)
	if m == null:
		m = _geometry(v, name).build(pal)
		_baked[key] = m
	return m


static func _geometry(v: String, name: String) -> Mesher:
	var key := v + "/" + name
	var mb: Mesher = _geo.get(key)
	if mb == null:
		var part: Part = _parts[v][name]
		mb = Mesher.new()
		var fe := FEATHER / part.unit
		for op in part.ops:
			var a: float = op[5]
			if op[2] != null:
				mb.poly(op[0], op[2], a, op[2] is String and op[2] == "skin", fe if op[3] == null else 0.0)
			if op[3] != null:
				mb.strip(op[0], op[1], op[4], op[3], a, fe)
		_geo[key] = mb
	return mb


static func _sil_mesh(v: String, name: String) -> ArrayMesh:
	var key := v + "/" + name
	var m: ArrayMesh = _sil_baked.get(key)
	if m == null:
		var part: Part = _parts[v][name]
		var mb := Mesher.new()
		var o := OUT / part.unit
		var fe := FEATHER / part.unit
		for s in part.sil:
			var polys: Array = Geometry2D.offset_polygon(s[0], o, Geometry2D.JOIN_ROUND) if s[1] \
				else Geometry2D.offset_polyline(s[0], float(s[2]) + o, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
			for q: PackedVector2Array in polys:
				mb.poly(q, Color.WHITE, 1.0, false, fe)
		m = mb.build({})
		_sil_baked[key] = m
	return m


## SVG path data (absolute M, L, C and Z, as the design file writes them) -> [[points, closed], ...],
## with curves flattened and the current pre-transform applied.
static func _path(d: String) -> Array:
	if _re == null:
		_re = RegEx.create_from_string("[MLCZ]|-?(?:\\d+\\.?\\d*|\\.\\d+)")
	var out := []
	var pts := PackedVector2Array()
	var cmd := ""
	var nums: Array[float] = []
	var cur := Vector2.ZERO
	for m in _re.search_all(d):
		var s := m.get_string()
		if s == "M" or s == "L" or s == "C" or s == "Z":
			if s == "M" or s == "Z":
				if pts.size() > 1:
					out.append([_clean(pts, s == "Z"), s == "Z"])
				pts = PackedVector2Array()
			cmd = s
			nums.clear()
			continue
		nums.append(s.to_float())
		if nums.size() < (6 if cmd == "C" else 2):
			continue
		if cmd == "C":
			var c1 := Vector2(nums[0], nums[1])
			var c2 := Vector2(nums[2], nums[3])
			var e := Vector2(nums[4], nums[5])
			var n := clampi(ceili((cur.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(e)) / 5.0), 2, 16)
			for k in range(1, n + 1):
				pts.append(_pre * cur.bezier_interpolate(c1, c2, e, float(k) / n))
			cur = e
		else:
			cur = Vector2(nums[0], nums[1])
			pts.append(_pre * cur)
			if cmd == "M":
				cmd = "L"
		nums.clear()
	if pts.size() > 1:
		out.append([_clean(pts, false), false])
	return out


static func _clean(pts: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.05:
			out.append(p)
	if closed and out.size() > 2 and out[0].distance_to(out[out.size() - 1]) <= 0.05:
		out.remove_at(out.size() - 1)
	return out


static func _begin(parts: Dictionary, name: String, unit := SV) -> void:
	_cur = Part.new()
	_cur.unit = unit
	parts[name] = _cur
	_set_pre(Transform2D.IDENTITY)


static func _set_pre(xf: Transform2D) -> void:
	_pre = xf
	_pre_w = sqrt(absf(xf.determinant()))


## Scale `s` about point `p`.
static func _sc(p: Vector2, s: Vector2) -> Transform2D:
	return Transform2D(0.0, s, 0.0, p - p * s)


## Filled path. `stroke` null = no outline; `sil` adds it to the part's ink silhouette.
static func _sh(d: String, fill: Variant, stroke: Variant = null, w := 1.6, a := 1.0, sil := false) -> void:
	for sp in _path(d):
		_poly(sp[0], fill, stroke, w, a, sil)


static func _poly(pts: PackedVector2Array, fill: Variant, stroke: Variant = null, w := 1.6, a := 1.0, sil := false) -> void:
	_cur.ops.append([pts, true, fill, stroke, w * _pre_w, a])
	if sil:
		_cur.sil.append([pts, true, 0.0])


## Stroked (unfilled) path.
static func _ln(d: String, col: Variant, w: float, a := 1.0, sil := false) -> void:
	for sp in _path(d):
		_cur.ops.append([sp[0], sp[1], null, col, w * _pre_w, a])
		if sil:
			_cur.sil.append([sp[0], sp[1], w * _pre_w / 2.0])


## Dashed stroke: `on` units drawn, `off` skipped.
static func _dash(d: String, col: Variant, w: float, on: float, off: float) -> void:
	for sp in _path(d):
		var pts: PackedVector2Array = sp[0]
		var piece := PackedVector2Array([pts[0]])
		var pos := 0.0
		var drawing := true
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var seg := a.distance_to(b)
			var walked := 0.0
			while walked < seg:
				var left := (on if drawing else off) - pos
				var step := minf(left, seg - walked)
				walked += step
				pos += step
				var p := a.lerp(b, walked / seg)
				if drawing:
					piece.append(p)
				if pos >= (on if drawing else off) - 0.001:
					if drawing and piece.size() > 1:
						_cur.ops.append([piece, false, null, col, w * _pre_w, 1.0])
					drawing = not drawing
					pos = 0.0
					piece = PackedVector2Array([p])
		if drawing and piece.size() > 1:
			_cur.ops.append([piece, false, null, col, w * _pre_w, 1.0])


static func _el(cx: float, cy: float, rx: float, ry: float, fill: Variant, stroke: Variant = null, w := 1.0, a := 1.0, sil := false) -> void:
	var pts := PackedVector2Array()
	var n := clampi(int((rx + ry) * 1.6), 10, 32)
	for i in n:
		pts.append(_pre * Vector2(cx + cos(TAU * i / n) * rx, cy + sin(TAU * i / n) * ry))
	_poly(pts, fill, stroke, w, a, sil)


static func _dot(cx: float, cy: float, r: float, fill: Variant, stroke: Variant = null, w := 1.0, a := 1.0, sil := false) -> void:
	_el(cx, cy, r, r, fill, stroke, w, a, sil)


## Scale-armour pattern (the design's 12×9 tile of arcs) clipped to the closed path `d`.
static func _scales(d: String) -> void:
	var shape: PackedVector2Array = _path(d)[0][0]
	var r := Rect2(shape[0], Vector2.ZERO)
	for p in shape:
		r = r.expand(p)
	for row in range(floori(r.position.y / 9.0) - 1, ceili(r.end.y / 9.0) + 1):
		for col in range(floori(r.position.x / 12.0) - 1, ceili(r.end.x / 12.0) + 1):
			var x0 := col * 12.0
			var y0 := row * 9.0
			for arc in [[Vector2(x0, y0 + 9), Vector2(x0, y0 + 3), Vector2(x0 + 12, y0 + 3), Vector2(x0 + 12, y0 + 9)],
					[Vector2(x0 - 6, y0 + 4.5), Vector2(x0 - 6, y0 - 1.5), Vector2(x0 + 6, y0 - 1.5), Vector2(x0 + 6, y0 + 4.5)]]:
				var pl := PackedVector2Array()
				for k in 7:
					pl.append((arc[0] as Vector2).bezier_interpolate(arc[1], arc[2], arc[3], k / 6.0))
				for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(pl, shape):
					_cur.ops.append([piece, false, null, Color.BLACK, 1.1, 0.3])


static func _bez(p: Array, t: float) -> Vector2:
	return (p[0] as Vector2).bezier_interpolate(p[1], p[2], p[3], t)


## Every part of one variant ("a" ceremonial, "b" armoured), transcribed from the design.
static func _build(v: String) -> Dictionary:
	var B := v == "b"
	var P := {}

	# legs: upper (shortened ×0.72) and lower (×0.85) for front/hind, near/far
	for front in [false, true]:
		for near in [false, true]:
			var tag: String = ("f" if front else "h") + ("n" if near else "f")
			var fill: String = "skin" if near else "far"
			var line: String = "skinD" if near else "farD"
			_begin(P, "up_" + tag)
			_set_pre(Transform2D.IDENTITY.scaled(Vector2(1.1, 0.72)))
			if front:
				_sh("M -30 -20 C -22 -44, 20 -44, 28 -20 C 32 25, 25 68, 21 96 L -21 96 C -25 68, -32 25, -30 -20 Z", fill, line, 1.6, 1.0, true)
				if near:
					_sh("M -30 -20 C -32 25, -25 68, -21 96 L -13 96 C -17 68, -22 25, -20 -20 Z", "skinD", null, 0.0, 0.28)
					_ln("M -18 60 C -8 64, 6 64, 18 58", "skinD", 1.6, 0.5)
			else:
				_sh("M -40 -30 C -30 -60, 24 -60, 30 -30 C 38 35, 32 70, 22 92 L -28 92 C -40 55, -46 15, -40 -30 Z", fill, line, 1.6, 1.0, true)
				if near:
					_sh("M -40 -30 C -46 15, -40 55, -28 92 L -18 92 C -30 55, -34 15, -28 -30 Z", "skinD", null, 0.0, 0.28)
					_ln("M 12 56 C 22 62, 30 64, 34 60", "skinD", 1.6, 0.6)
			_begin(P, "lo_" + tag)
			_set_pre(Transform2D.IDENTITY.scaled(Vector2(1.08, 0.85)))
			var gold: String = "gold" if near else "goldFar"
			var gold_d: String = "goldD" if near else "goldFarD"
			var nail: Color = Color("#ded4c4") if near else Color("#b5ab9c")
			var nail_d: Variant = Color("#a69a88") if near else null
			var nry := 3.2 if near else 3.0
			if front:
				_sh("M -21 -4 C -8 2, 8 2, 21 -4 C 21 18, 24 32, 25 43 C 26 48, 23 50, 19 50 L -17 50 C -22 50, -25 48, -25 44 C -25 32, -22 18, -21 -4 Z", fill, line, 1.6, 1.0, true)
				if near:
					_ln("M -20 8 C -8 12, 8 12, 21 7", "skinD", 1.6, 0.5)
				_sh("M -23.4 18 L 22.6 18 L 23 24 L -23.8 24 Z M -24 28 L 23.5 28 L 24.3 37 L -24.7 37 Z" if B else "M -24 28 L 23.5 28 L 24.3 36 L -24.6 36 Z", gold, gold_d)
				_el(-9, 47, 5, nry, nail, nail_d)
				_el(2, 47.5, 5, nry, nail, nail_d)
				_el(13, 47, 5, nry, nail, nail_d)
			else:
				_sh("M -26 -4 C -10 2, 8 2, 22 -4 C 21 18, 24 36, 25 49 C 26 54, 23 57, 19 57 L -19 57 C -24 57, -27 54, -27 50 C -27 40, -24 20, -26 -4 Z", fill, line, 1.6, 1.0, true)
				if near:
					_ln("M -22 12 C -10 16, 6 16, 20 12", "skinD", 1.6, 0.5)
				_sh("M -25.6 24 L 23.6 24 L 24 30 L -26 30 Z M -26.2 34 L 24.4 34 L 24.9 43 L -26.7 43 Z" if B else "M -26.2 34 L 24.4 34 L 24.8 42 L -26.6 42 Z", gold, gold_d)
				_el(-6, 54, 5, nry, nail, nail_d)
				_el(6, 54, 5, nry, nail, nail_d)
				_el(16, 53, 4.5, nry, nail, nail_d)

	_begin(P, "tail")
	_ln("M 104 206 C 93 232, 90 262, 94 296", "skinD", 7.5, 1.0, true)
	_ln("M 104 206 C 93 232, 90 262, 94 296", "skinFlat", 4.5)
	_sh("M 89 292 L 89 318 L 94 305 L 98 318 L 101 292 Z", Color("#3b3236"), LINE, 1.6, 1.0, true)

	_begin(P, "torso")
	_sh("M 292 166 C 262 146, 196 136, 152 152 C 120 164, 100 194, 100 232 C 100 266, 114 290, 140 302 C 182 316, 252 316, 292 302 C 320 292, 332 262, 328 230 C 325 202, 312 180, 292 166 Z", "skin", "skinD", 1.6, 1.0, true)
	_sh("M 118 282 C 160 302, 250 306, 312 284 C 300 298, 270 312, 220 314 C 170 314, 134 302, 118 282 Z", "skinD", null, 0.0, 0.3)
	_ln("M 312 250 C 318 262, 318 278, 310 290", "skinD", 1.6, 0.6)
	_ln("M 112 220 C 107 240, 109 262, 120 278", "skinD", 1.6, 0.6)

	# caparison, girth and howdah cushion
	_begin(P, "body")
	var girth := "M 230 288 C 231 298, 233 306, 234 314" if B else "M 228 266 C 230 284, 232 300, 234 314"
	_ln(girth, "goldD", 9.0)
	_ln(girth, "gold", 6.0)
	_ln("M 126 196 C 118 200, 110 204, 104 208", "gold", 4.0)
	var cap_body := "M 290 160 C 262 140, 196 130, 152 148 C 136 154, 124 164, 118 176 C 116 210, 120 248, 128 282 C 172 296, 248 296, 290 284 C 296 244, 296 200, 290 160 Z" if B \
		else "M 288 162 C 262 144, 198 134, 154 150 C 140 155, 130 162, 124 170 C 122 200, 126 232, 132 260 C 172 274, 244 274, 284 262 C 290 230, 292 196, 288 162 Z"
	_sh(cap_body, "cloth", "clothD", 1.6, 1.0, true)
	if B:
		_scales(cap_body)
	_sh("M 160 154 C 156 190, 158 230, 164 268 L 178 272 C 172 232, 170 192, 172 148 Z", "clothD", null, 0.0, 0.35)
	_sh("M 222 140 C 220 180, 222 230, 226 274 L 238 274 C 234 230, 232 180, 234 140 Z", "clothD", null, 0.0, 0.35)
	_sh("M 266 150 C 268 190, 270 230, 268 268 L 278 266 C 280 230, 280 190, 276 156 Z", "clothD", null, 0.0, 0.35)
	_sh("M 158 154 C 200 140, 250 142, 284 160 C 250 152, 200 150, 158 162 Z", "clothL", null, 0.0, 0.6)
	var cap_left := "M 118 176 C 116 210, 120 248, 128 282" if B else "M 124 170 C 122 200, 126 232, 132 260"
	var cap_right := "M 290 160 C 296 200, 296 244, 290 284" if B else "M 288 162 C 292 196, 290 230, 284 262"
	for edge in [cap_left, cap_right]:
		_ln(edge, "goldD", 7.0)
		_ln(edge, "gold", 4.5)
	var hb := [Vector2(128, 282), Vector2(172, 296), Vector2(248, 296), Vector2(290, 284)] if B \
		else [Vector2(132, 260), Vector2(172, 274), Vector2(244, 274), Vector2(284, 262)]
	var ht := [Vector2(126, 268), Vector2(172, 282), Vector2(248, 282), Vector2(291, 270)] if B \
		else [Vector2(130, 246), Vector2(172, 260), Vector2(244, 260), Vector2(286, 248)]
	for i in 12:
		var q := _bez(ht, (i + 0.5) / 12.0)
		_poly(PackedVector2Array([q + Vector2(-5, 1), q + Vector2(5, 1), q + Vector2(0, -8)]), "gold", "goldD", 1.0)
	_sh("M 126 268 C 172 282, 248 282, 291 270 L 290 284 C 248 296, 172 296, 128 282 Z" if B else "M 130 246 C 172 260, 244 260, 286 248 L 284 262 C 244 274, 172 274, 132 260 Z", "gold", "goldD")
	_ln("M 127 275 C 172 289, 248 289, 290.5 277" if B else "M 131 253 C 172 267, 244 267, 285 255", "goldD", 1.2)
	for i in 12:
		var p := _bez(hb, (i + 0.5) / 12.0)
		_poly(PackedVector2Array([p + Vector2(-6, -1), p + Vector2(6, -1), p + Vector2(0, 11)]), "gold", "goldD", 1.1)
		_dot(p.x, p.y + 14.0, 2.8, "clothL", "clothD", 1.0)
	_sh("M 206 184 L 224 202 L 206 220 L 188 202 Z", "gold", "goldD")
	_sh("M 206 191 L 217 202 L 206 213 L 195 202 Z", "clothD", "goldD", 1.0)
	_dot(206, 202, 3.6, JEWEL, JEWEL_D, 1.0)
	_sh("M 184 140 C 188 124, 244 122, 250 138 C 238 146, 196 148, 184 140 Z", "clothD", "gold", 2.5, 1.0, true)

	_begin(P, "pole")
	_ln("M 233 152 L 233 -8", Color("#5b3a1f"), 3.5, 1.0, true)
	_sh("M 229 -8 L 237 -8 L 233 -19 Z", "gold", "goldD", 1.6, 1.0, true)

	# head, drawn ×1.35 about HEAD_PIVOT (applied when drawing); tusks ×0.66, trunk mouth ×(0.8, 0.54)
	var tusk := "M 368 234 C 384 256, 418 264, 446 238 C 440 258, 412 270, 386 266 C 372 263, 364 254, 362 242 Z" if B \
		else "M 368 234 C 380 252, 408 258, 432 240 C 424 254, 404 264, 384 262 C 372 260, 364 252, 362 242 Z"
	var tusk_sc := _sc(Vector2(366, 238), Vector2(0.66, 0.66))
	_begin(P, "tusk_far", HK)
	_set_pre(tusk_sc * Transform2D(0.0, Vector2(-9, -3)))
	_sh(tusk, Color("#cbbfa6"), Color("#8a7c62"), 1.6, 1.0, true)

	_begin(P, "mouth", HK)
	_set_pre(_sc(Vector2(380, 215), Vector2(0.8, 0.54)))
	_sh("M 356 238 C 366 250, 382 250, 394 228 C 382 236, 368 240, 356 238 Z", Color("#a8706f"), Color("#6e4343"), 1.6, 1.0, true)

	_begin(P, "head", HK)
	_sh("M 296 174 C 298 146, 318 128, 341 128 C 351 128, 357 132, 361 134 C 372 138, 380 152, 382 170 C 384 190, 386 206, 384 218 C 380 232, 368 242, 354 244 C 336 246, 318 238, 308 226 C 298 214, 294 194, 296 174 Z", "skin", "skinD", 1.6, 1.0, true)
	_el(358, 156, 17, 11, "skinL", null, 0.0, 0.4)
	_sh("M 310 226 C 325 242, 345 246, 360 243 C 345 236, 325 232, 310 218 Z", "skinD", null, 0.0, 0.3)
	_dot(378, 214, 2.6, "pink")
	_dot(371, 222, 2.0, "pink")
	_dot(381, 204, 1.8, "pink")
	_sh("M 352 244 C 360 252, 372 252, 378 244 C 372 247, 360 247, 352 244 Z", Color("#9c7f80"), "skinD", 1.0, 1.0, true)
	var collar := "M 298 180 C 300 206, 306 230, 318 246"
	_ln(collar, "goldD", 7.0)
	_ln(collar, "gold", 5.0)
	_dash(collar, "cloth", 2.5, 3.0, 5.0)
	_sh("M 313 249 C 313 242, 327 242, 327 249 L 329 259 L 311 259 Z", "gold", "goldD", 1.6, 1.0, true)
	_dot(320, 261, 2.2, "goldD", null, 1.0, 1.0, true)
	_set_pre(tusk_sc)
	_sh(tusk, Color("#efe6d2"), Color("#9b8d72"), 1.6, 1.0, true)
	_ln("M 376 244 C 392 256, 414 258, 432 250" if B else "M 376 244 C 390 254, 406 256, 422 250", Color("#fffaf0"), 2.0)
	if B:
		_sh("M 420 262 C 432 256, 440 248, 446 238 C 442 254, 434 262, 422 268 Z", "gold", "goldD", 1.6, 1.0, true)
		_sh("M 404 260 L 411 258 L 413 268 L 406 269 Z", "gold", "goldD")
	_sh("M 361 237 L 371 231 L 377 244 L 366 250 Z", "gold", "goldD")
	_set_pre(Transform2D.IDENTITY)
	if B:
		_sh("M 344 130 C 344 120, 350 112, 356 107 C 354 116, 356 124, 361 132 Z", "gold", "goldD", 1.6, 1.0, true)
		_sh("M 326 136 C 342 124, 366 128, 378 146 C 386 160, 388 190, 387 214 C 382 220, 377 222, 372 220 C 374 196, 372 178, 364 166 C 352 156, 336 150, 326 136 Z", "clothD", "gold", 3.0, 1.0, true)
		for p in [Vector2(338, 139), Vector2(352, 140), Vector2(364, 148), Vector2(373, 162), Vector2(379, 180), Vector2(381, 198)]:
			_dot(p.x, p.y, 2.4, "gold")
	else:
		_sh("M 300 168 C 302 142, 320 126, 342 126 C 352 126, 357 129, 361 132 C 373 137, 380 150, 382 166 C 372 160, 364 158, 356 160 C 342 163, 330 160, 322 156 C 312 153, 304 160, 300 168 Z", "cloth", "clothD", 1.6, 1.0, true)
		var hem := "M 300 168 C 304 160, 312 153, 322 156 C 330 160, 342 163, 356 160 C 364 158, 372 160, 382 166"
		_ln(hem, "goldD", 6.0)
		_ln(hem, "gold", 3.6)
		for p in [Vector2(318, 140), Vector2(332, 133), Vector2(346, 131), Vector2(360, 137), Vector2(371, 147), Vector2(312, 152), Vector2(326, 146), Vector2(340, 144), Vector2(354, 147), Vector2(366, 155)]:
			_dot(p.x, p.y, 2.2, "gold")
		_sh("M 377 164 L 382 174 L 377 186 L 372 174 Z", "gold", "goldD", 1.2)
		_dot(377, 175, 2.0, JEWEL)

	_begin(P, "crown", HK)
	_sh("M 328 132 L 334 110 L 341 92 L 348 110 L 354 130 Z", "gold", "goldD", 1.6, 1.0, true)
	_ln("M 331 120 L 351 120", "goldD", 1.4)
	_dot(341, 112, 2.6, JEWEL, JEWEL_D, 1.0)

	_begin(P, "ear", HK)
	_sh("M 316 158 C 336 152, 352 166, 352 190 C 352 212, 344 228, 334 240 C 330 242, 326 238, 324 232 C 322 222, 316 216, 310 210 C 300 198, 302 168, 316 158 Z", "skin", "skinD", 1.6, 1.0, true)
	_sh("M 318 170 C 330 168, 338 178, 338 192 C 338 204, 332 214, 326 220 C 320 212, 312 204, 310 194 C 308 182, 310 174, 318 170 Z", "skinD", null, 0.0, 0.3)
	_ln("M 320 165 C 334 163, 345 176, 344 192 C 343 206, 337 218, 331 226", "skinD", 1.6, 0.55)
	_dot(347, 207, 2.6, "pink")
	_dot(342, 220, 2.0, "pink")
	_dot(350, 195, 1.8, "pink")

	_begin(P, "earring", HK)
	_dot(331, 243, 4.0, "gold", "goldD", 1.2, 1.0, true)
	_dot(331, 243, 1.8, JEWEL)

	_begin(P, "blush", HK)
	_el(366, 201, 8, 4.5, Color("#ec8f97"), null, 0.0, 0.5)

	_begin(P, "eye", HK)
	_el(362, 180, 7.5, 8.5, Color.WHITE, EYE_INK, 1.4)
	_dot(363.5, 181, 5.6, EYE_INK)
	_dot(365.6, 178.4, 2.1, Color.WHITE)
	_dot(361.4, 183.6, 1.0, Color.WHITE)
	_ln("M 355.5 173.5 C 353 172, 351.5 170, 351.5 168 M 359.5 172 C 358.5 170, 358.5 168, 359.5 166", EYE_INK, 1.4)

	return P
