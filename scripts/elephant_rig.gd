class_name ElephantRig
extends RefCounted
## Procedurally animated war elephant, drawn in shaded shapes with gold regalia.
## Each frame a pose is picked from the fighter's state; springs ease every joint toward it
## (so moves blend and overshoot instead of snapping) and the legs are placed with 2-bone IK.
## Arena keeps one rig per Fighter. Local space faces +x, origin on the ground between the feet.

const G := GameData.GROUND
const INK := GameData.INK
const DUST := Color(0.87, 0.77, 0.6)
const SKIN := Color("#c98d5e")
const IVORY := Color("#fffaee")
const IVORY_SHADE := Color("#d9c7a3")
const STEEL := Color("#eef3f6")
const STEEL_SHADE := Color("#8c9aa7")
const WOOD := Color("#5a3720")

const LEG_UPPER := 39.0
const LEG_LOWER := 39.0
## [hip in body space, gait phase offset (cycles), front leg]. Far legs first, near legs last.
const LEGS := [
	[Vector2(-40, -80), 0.0, false],
	[Vector2(38, -80), 0.25, true],
	[Vector2(-56, -78), 0.5, false],
	[Vector2(24, -78), 0.75, true],
]
const PITCH_PIVOT := Vector2(-10, -95)
const REAR_PIVOT := Vector2(-62, 0)
const NECK := Vector2(44, -112)
const EAR_ANCHOR := Vector2(8, -20)
const EYE := Vector2(26, -14)
const TRUNK_ROOT := Vector2(42, 10)
const TRUNK_SEG := [15.0, 15.0, 14.0, 13.0, 12.0]
const TRUNK_W := [20.0, 18.0, 15.0, 12.0, 10.0, 8.0]
const TAIL_ROOT := Vector2(-78, -108)
const RIDER_HIP := Vector2(32, -140)

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
	"head": [5.5, 0.5], "ear": [3.5, 0.3], "tail": [1.6, 0.25], "glaive": [8.5, 0.55],
	"lean": [4.0, 0.5], "sq": [4.5, 0.25],
	"tb": [6.5, 0.6], "t1": [7.0, 0.45], "t2": [6.0, 0.42], "t3": [5.0, 0.4], "t4": [4.2, 0.38],
}

class Puff:
	var pos: Vector2
	var vel: Vector2
	var r: float
	var life: float
	var max_life: float

static var BODY := PackedVector2Array()
static var BODY_RIM := PackedVector2Array()
static var HEAD := PackedVector2Array()
static var HEAD_RIM := PackedVector2Array()
static var EAR := PackedVector2Array()
static var EAR_INNER := PackedVector2Array()
static var HEADCLOTH := PackedVector2Array()
static var HEADCLOTH_HEM := PackedVector2Array()
static var NET := PackedVector2Array()
static var CLOTH := PackedVector2Array()
static var CLOTH_HEM := PackedVector2Array()
static var TASSELS := PackedVector2Array()
static var TUSK := PackedVector2Array()
static var TUSK_RINGS := []
static var BLADE := PackedVector2Array()
static var PENDANT := PackedVector2Array([Vector2(39, -5), Vector2(46, -5), Vector2(44, 6), Vector2(42.5, 10), Vector2(41, 6)])
static var CROWN := PackedVector2Array([Vector2(12, -42), Vector2(18, -60), Vector2(20, -70), Vector2(22, -60), Vector2(28, -43)])
static var HELMET := PackedVector2Array([Vector2(-6.5, -31), Vector2(-5.5, -36), Vector2(0, -38.5), Vector2(5.5, -36), Vector2(6.5, -31)])
static var CUSHION := PackedVector2Array([Vector2(-54, -143), Vector2(-52, -153), Vector2(-4, -153), Vector2(-2, -143)])
static var SHIRT := PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(6, -23), Vector2(-6, -23)])
static var TUSK_COLS := PackedColorArray()
static var TUSK_CLOSED := PackedVector2Array()
static var BLADE_COLS := PackedColorArray()
static var BLADE_CLOSED := PackedVector2Array()

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
var _shade_cache := {}          ## static shape key -> {colour: [colour, mesh, closed outline, rim colour]}


func _init() -> void:
	if BODY.is_empty():
		_build_shapes()


# ---------- animation ----------

func update(f: Fighter, duel_phase: String, dt: float) -> void:
	if dt <= 0.0:
		return
	_time += dt
	var air := f.y < G - 1.0
	var walking := not air and not f.ko and f.stun <= 0.0 and not f.blocking
	if walking:
		_phase += f.vx * f.face * dt * 0.06
	_move = move_toward(_move, clampf(absf(f.vx) / 200.0, 0.0, 1.0) if walking else 0.0, dt * 5.0)

	if f.stun > _prev_stun + 0.01:
		_kick("sq", 1.5)
		_kick("head", -260.0)
	if f.bstun > _prev_bstun + 0.01:
		_kick("shift", -90.0)
	if f.balance < _prev_balance - 1.0 or (f.dazed <= 0.0 and _dazed and f.stun > 0.0):
		_kick("lean", -320.0 if f.dazed <= 0.0 else -500.0)
	if _was_air and not air:
		_kick("sq", 2.5)
		for i in 6:
			_puff(f, randf_range(-70.0, 50.0), randf_range(-60.0, 60.0), 1.3)
	elif air and not _was_air:
		_kick("sq", -1.5)
	if _x.has("glaive") and f.atk != "storm":
		_x["glaive"] = wrapf(_x["glaive"], -270.0, 90.0)
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
		"glaive": -62.0 + sin(tm * 1.3) * 3.0,
		"lean": f.vx * f.face * 0.012,
	}
	_trunk(p, "rest")
	p["tb"] += sin(tm * 1.5) * 6.0

	if air:
		p["pitch"] = clampf(f.vy * 0.015, -10.0, 10.0)
		p["ear"] = 1.1
		_trunk(p, "air")
	if f.dash_t > 0.0 and f.atk == "" and not air:
		if f.dash_dir == f.face:
			_apply(p, {"pitch": 5.0, "head": 12.0, "shift": 8.0, "ear": 0.55, "lean": 12.0})
			_trunk(p, "tuck")
		else:
			_apply(p, {"pitch": -6.0, "head": -14.0, "shift": -8.0, "ear": 1.15, "lean": -12.0})
	if f.atk != "":
		_attack_pose(p, f)
	if f.rider_t >= 0.0:
		# rider's overhead chop, independent of the elephant: glaive wound far back, then brought down
		var rh := GameData.move("rider").hits[0]
		if f.rider_t < rh.start:
			_apply(p, {"glaive": -165.0, "lean": -18.0})
		elif f.rider_t <= rh.stop:
			_apply(p, {"glaive": 35.0, "lean": 22.0})
	if f.stun > 0.0 and not f.ko:
		_apply(p, {"pitch": -8.0, "head": -18.0, "shift": -6.0, "ear": 1.2, "glaive": -125.0, "lean": -14.0})
		_trunk(p, "hurt")
	if f.dazed > 0.0 and not f.ko:
		_apply(p, {"lean": sin(tm * 9.0) * 16.0, "glaive": 70.0 + sin(tm * 5.0) * 12.0})
		if f.stun > 0.0:
			# reeling from the balance break: head lolls, body sways, trunk hangs
			_apply(p, {"head": 16.0 + sin(tm * 5.5) * 9.0, "pitch": sin(tm * 4.0) * 4.0, "shift": sin(tm * 4.0) * 6.0, "ear": 0.7, "bob": 4.0})
			_trunk(p, "droop")
			p["tb"] += sin(tm * 5.5) * 10.0
	if f.blocking:
		_apply(p, {"bob": 7.0, "head": 12.0, "pitch": 3.0, "ear": 0.6, "glaive": -95.0, "lean": -4.0})
		_trunk(p, "guard")
	if over and f.atk == "" and not f.ko:
		if f.win:
			_apply(p, {"rear": -22.0 + sin(tm * 3.0) * 3.0, "head": -20.0, "ear": 1.1, "glaive": -90.0 + sin(tm * 7.0) * 14.0, "lean": -4.0})
			_trunk(p, "up")
		else:
			_apply(p, {"head": 14.0, "ear": 0.6, "glaive": -20.0, "lean": 10.0})
			_trunk(p, "droop")
	if f.ko:
		# thrown back while airborne, then collapse onto the belly
		if air:
			_apply(p, {"rear": -24.0, "pitch": 0.0, "head": -25.0, "ear": 1.2, "glaive": 60.0, "lean": -35.0, "bob": 0.0})
		else:
			_apply(p, {"rear": 0.0, "pitch": 5.0, "head": 24.0, "ear": 1.15, "glaive": 85.0, "lean": 35.0, "bob": 24.0})
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
				_apply(p, {"head": -8.0, "glaive": -35.0, "lean": -4.0})
				_trunk(p, "wind")
			elif act:
				_apply(p, {"head": 6.0, "shift": 6.0, "glaive": -8.0, "lean": 8.0})
				_trunk(p, "whip")
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
				_apply(p, {"rear": -20.0 * k, "head": -26.0 * k, "pitch": -4.0 * k, "ear": 1.25, "glaive": lerpf(-62.0, -140.0, k), "lean": -10.0 * k})
				_trunk(p, "upper" if k > 0.5 else "rest")
		"light2":
			# backhand: the trunk drops low, then swings up and across
			if pre:
				_apply(p, {"head": 6.0, "glaive": -40.0})
				_trunk(p, "tuck")
			elif act:
				_apply(p, {"head": -10.0, "shift": 8.0, "pitch": -2.0, "glaive": -20.0, "lean": 6.0})
				_trunk(p, "upper")
		"light3":
			# trunk raised high, then slammed down in front
			if pre:
				_apply(p, {"rear": -8.0, "head": -20.0, "ear": 1.2, "glaive": -120.0, "lean": -8.0})
				_trunk(p, "up")
			else:
				_apply(p, {"rear": 2.0 * k, "pitch": 9.0 * k, "head": 22.0 * k, "shift": 14.0 * k, "glaive": lerpf(-62.0, -10.0, k), "lean": 12.0 * k})
				_trunk(p, "slam")
		"dive":
			_apply(p, {"pitch": 14.0, "head": 26.0, "shift": 8.0, "ear": 1.25, "glaive": 10.0, "lean": 14.0})
			_trunk(p, "tuck")
		"counter":
			if pre:
				_apply(p, {"bob": 6.0, "head": 10.0, "shift": -8.0, "glaive": -95.0})
				_trunk(p, "guard")
			else:
				_apply(p, {"pitch": 6.0 * k, "head": 20.0 * k, "shift": 22.0 * k, "lean": 10.0 * k, "ear": 1.2})
				_trunk(p, "tuck")
		"gore":
			if pre:
				_apply(p, {"pitch": -6.0, "shift": -8.0, "head": -12.0, "glaive": -150.0, "lean": -12.0})
			else:
				_apply(p, {"pitch": 8.0 * k, "shift": 18.0 * k, "head": 22.0 * k, "glaive": lerpf(-62.0, 20.0, k), "lean": 14.0 * k})
			_trunk(p, "tuck")
		"hook":
			# tusk sweeps down then yanks back; the rider readies the glaive for the follow-up
			if pre:
				_apply(p, {"pitch": -4.0, "shift": -4.0, "head": -16.0, "glaive": -110.0})
			elif act:
				_apply(p, {"pitch": 6.0, "shift": 10.0, "head": 22.0, "glaive": -110.0})
			else:
				_apply(p, {"shift": -12.0 * k, "head": -8.0 * k, "pitch": -3.0 * k, "glaive": -110.0})
			_trunk(p, "tuck")
		"lunge":
			if pre:
				_apply(p, {"bob": 7.0, "pitch": 4.0, "head": 6.0, "ear": 0.6})
			else:
				_apply(p, {"pitch": 10.0 * k, "head": 22.0 * k, "shift": 14.0 * k, "lean": 10.0 * k, "ear": 1.1})
			_trunk(p, "tuck")
		"headbutt":
			# long rear-back while armored, then the head comes down hard
			if pre:
				_apply(p, {"pitch": -10.0, "rear": -5.0, "head": -26.0, "shift": -14.0, "ear": 0.6, "glaive": -100.0, "lean": -10.0})
			else:
				_apply(p, {"pitch": 12.0 * k, "head": 30.0 * k, "shift": 24.0 * k, "lean": 12.0 * k, "ear": 1.2})
			_trunk(p, "tuck")
		"sweep":
			if pre:
				_apply(p, {"head": -6.0, "lean": -4.0})
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
				_apply(p, {"pitch": 10.0 * k2, "shift": 20.0 * k2, "head": 26.0 * k2, "lean": 10.0 * k2})
			_trunk(p, "tuck")
		"charge3":
			# trumpet, ram, gore, then the rider's glaive finishes it
			var h2 := m.hits[1]
			var h3 := m.hits[2]
			if t < h.start:
				_apply(p, {"rear": -8.0, "head": -16.0, "ear": 1.2, "glaive": -75.0})
				_trunk(p, "up")
			elif t < h.stop:
				_apply(p, {"pitch": 7.0, "head": 14.0, "shift": 10.0, "ear": 1.15, "glaive": -2.0, "lean": 10.0})
				_trunk(p, "tuck")
			elif t < h2.stop + 0.04:
				_apply(p, {"pitch": 8.0, "head": 24.0, "shift": 16.0, "glaive": -165.0, "lean": -18.0})
				_trunk(p, "tuck")
			elif t < h3.start:
				_apply(p, {"pitch": 2.0, "head": 4.0, "glaive": -165.0, "lean": -18.0})
			else:
				var k3 := 1.0 if t <= h3.stop + 0.06 else maxf(0.0, 1.0 - (t - h3.stop) / (m.dur - h3.stop))
				_apply(p, {"glaive": lerpf(-62.0, 35.0, k3), "lean": 22.0 * k3, "head": 6.0 * k3})
		"storm":
			# the rider whirls the glaive overhead while the elephant trumpets
			var spin := clampf((t - 0.15) / 0.8, 0.0, 1.0)
			_apply(p, {"head": -10.0, "ear": 1.2, "glaive": -90.0 + spin * 720.0, "lean": sin(t * 18.0) * 10.0})
			_trunk(p, "up")
		"blink":
			if t < m.event_at:
				_apply(p, {"bob": 8.0, "pitch": 6.0, "head": 10.0, "ear": 0.6})
			elif pre:
				_apply(p, {"pitch": -4.0, "head": -12.0, "shift": -4.0})
			else:
				_apply(p, {"pitch": 10.0 * k, "head": 24.0 * k, "shift": 16.0 * k, "lean": 10.0 * k})
			_trunk(p, "tuck")
		"quake":
			# rear up on the hind legs, then slam the forefeet down
			if t < 0.45:
				_apply(p, {"rear": -26.0, "head": -20.0, "ear": 1.2, "glaive": -90.0, "lean": -6.0})
				_trunk(p, "up")
			elif t < 0.75:
				_apply(p, {"rear": 4.0, "pitch": 6.0, "head": 14.0, "bob": 6.0, "glaive": -40.0, "lean": 10.0})
				_trunk(p, "droop")
		"blessing":
			_apply(p, {"rear": -10.0, "head": -18.0, "ear": 1.2, "glaive": -90.0, "lean": -4.0})
			_trunk(p, "up")
		"roar":
			_apply(p, {"rear": -6.0, "head": -24.0, "ear": 1.3, "glaive": -60.0, "lean": -8.0, "shift": 4.0})
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
	var B := d.body
	var D := d.dark
	if f.flash > 0.0:
		B = B.lerp(GameData.ACC_300, 0.8)
		D = D.lerp(GameData.HURT_DARK, 0.8)
	var air := f.y < G - 1.0
	var root := base.translated_local(Vector2(f.x, f.y)).scaled_local(Vector2(f.face, 1.0))

	c.draw_set_transform_matrix(root)
	var sw := 180.0 * (1.0 - minf(0.5, (G - f.y) / 400.0))
	DrawKit.ellipse(c, Vector2(-6.0, G - f.y + 2.0), sw / 2.0, 7.0, Color(0.1, 0.05, 0.0, 0.28))
	if f.atk != "":
		var m := GameData.move(f.atk)
		if m.dash_speed > 0.0 and f.atk_t > m.dash_start and f.atk_t < m.dash_stop and absf(f.vx) > 300.0:
			for i in 4:
				c.draw_rect(Rect2(-180 - i * 18, -130 + i * 26, 70 - i * 8, 4), Color(1, 1, 1, 0.75))
		_draw_move_fx(c, f, m)
	if f.atk_ex and f.atk != "":
		# EX move: a pulsing gold aura behind the elephant
		var pulse := 0.5 + 0.5 * sin(_time * 18.0)
		DrawKit.ellipse(c, Vector2(-6, -100), 135.0, 100.0, Color(GameData.GOLD_LIGHT, 0.18 + 0.12 * pulse))
		DrawKit.ellipse(c, Vector2(-6, -100), 112.0, 82.0, Color(GameData.GOLD, 0.16 + 0.1 * pulse))
	if f.buff_t > 0.0:
		# blessing: gold diamonds circling the elephant while the boost lasts
		for i in 3:
			var a := _time * 2.5 + TAU * i / 3.0
			var sp := Vector2(-10.0 + cos(a) * 95.0, -100.0 + sin(a) * 22.0)
			_fill(c, PackedVector2Array([sp + Vector2(0, -7), sp + Vector2(6, 0), sp + Vector2(0, 7), sp + Vector2(-6, 0)]), GameData.GOLD_LIGHT)

	var bx := _body_xform()
	var legs := []
	for i in 4:
		legs.append(_solve_leg(i, bx, f, air))
	for i in 2:
		_draw_leg(c, legs[i], D, d.trim.darkened(0.3))

	var body := root * bx
	c.draw_set_transform_matrix(body)
	_draw_tail(c, D)
	_shade_s(c, &"body", BODY, B, 0.14, 0.32)
	c.draw_polyline(BODY_RIM, Color(B.lightened(0.45), 0.55), 3.0, true)
	for w in [[Vector2(36, -94), Vector2(42, -78)], [Vector2(44, -96), Vector2(48, -82)], [Vector2(-70, -86), Vector2(-62, -72)]]:
		c.draw_line(w[0], w[1], Color(B.darkened(0.4), 0.6), 1.5, true)
	_draw_girth(c, d)
	_draw_caparison(c, d)
	_draw_seat(c, d)

	c.draw_set_transform_matrix(root)
	for i in range(2, 4):
		_draw_leg(c, legs[i], B, d.trim)

	var head := body * Transform2D(deg_to_rad(_g("head")), NECK)
	c.draw_set_transform_matrix(head)
	_draw_head(c, B, D, d)

	_draw_rider(c, body, d)

	c.draw_set_transform_matrix(head * Transform2D(0.0, EAR_ANCHOR).scaled_local(Vector2(_g("ear"), 1.0)))
	_draw_ear(c, D, d)

	if f.blocking:
		c.draw_set_transform_matrix(root)
		c.draw_arc(Vector2(70, -86), 90.0, -0.75, 0.75, 20, Color(GameData.GOLD_LIGHT, 0.85), 5.0, true)
		c.draw_arc(Vector2(70, -86), 98.0, -0.6, 0.6, 16, Color(GameData.GOLD, 0.5), 3.0, true)


## Head-and-shoulders view for the HUD medallion, in the same pose as the fighter.
func draw_portrait(c: CanvasItem, f: Fighter, xf: Transform2D) -> void:
	var d := f.def
	var B := d.body.lerp(GameData.ACC_300, 0.8) if f.flash > 0.0 else d.body
	c.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(-20, 0)))
	_draw_head(c, B, d.dark, d, true)
	c.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(-20, 0) + EAR_ANCHOR))
	_draw_ear(c, d.dark, d)


## Extra shapes for ultimates, drawn in the elephant's root space before the body.
func _draw_move_fx(c: CanvasItem, f: Fighter, m: GameData.Move) -> void:
	var t := f.atk_t
	match m.id:
		"blessing":
			if t > 0.15 and t < m.dur:
				var a := clampf(minf((t - 0.15) * 5.0, (m.dur - t) * 4.0), 0.0, 1.0)
				var center := Vector2(-10, -110)
				DrawKit.circle(c, center, 120.0, Color(GameData.GOLD_LIGHT, 0.18 * a))
				for i in 12:
					var ang := TAU * i / 12.0 + t * 1.5
					var dv := Vector2.from_angle(ang)
					var n := dv.orthogonal() * 7.0
					_fill(c, PackedVector2Array([center + dv * 70.0 + n, center + dv * (150.0 + 20.0 * sin(t * 8.0 + i)), center + dv * 70.0 - n]), Color(GameData.GOLD_LIGHT, a * 0.85))
		"roar":
			if t > 0.25 and t < 0.7:
				var mouth := Vector2(130, -170)
				for i in 3:
					var r := fmod((t - 0.25) * 420.0 + i * 50.0, 150.0) + 20.0
					c.draw_arc(mouth, r, -0.9, 0.9, 18, Color(GameData.GOLD_LIGHT, 1.0 - r / 170.0), 5.0, true)
					c.draw_arc(mouth, r + 6.0, -0.8, 0.8, 18, Color(GameData.ACC, 0.6 - r / 300.0), 3.0, true)
		"storm":
			if t > 0.15 and t < 0.95:
				var hub := RIDER_HIP + Vector2(0, -20)
				var b := _body_xform()
				c.draw_arc(b * hub, 70.0, 0.0, TAU, 32, Color(1, 1, 1, 0.45), 3.0, true)
				c.draw_arc(b * hub, 76.0, 0.0, TAU, 32, Color(GameData.GOLD_LIGHT, 0.3), 2.0, true)


func _body_xform() -> Transform2D:
	var sq := _g("sq")
	var xf := Transform2D.IDENTITY.scaled(Vector2(1.0 + sq * 0.5, 1.0 - sq))
	xf = xf * Transform2D(0.0, Vector2(_g("shift"), _g("bob")))
	xf = xf * _about(REAR_PIVOT, deg_to_rad(_g("rear")))
	xf = xf * _about(PITCH_PIVOT, deg_to_rad(_g("pitch")))
	return xf


func _about(p: Vector2, a: float) -> Transform2D:
	return Transform2D(0.0, p) * Transform2D(a, Vector2.ZERO) * Transform2D(0.0, -p)


func _solve_leg(i: int, bx: Transform2D, f: Fighter, air: bool) -> Array:
	var hip_b: Vector2 = LEGS[i][0]
	var front: bool = LEGS[i][2]
	var hip := bx * hip_b
	var target: Vector2
	var ph := _phase + float(LEGS[i][1]) * TAU
	if f.ko and air:
		target = hip + Vector2(10.0 if front else -10.0, 82.0).rotated(deg_to_rad(_g("rear") + _g("pitch")))
	elif f.ko:
		target = Vector2(hip_b.x + (24.0 if front else -24.0), 0.0)
	elif air:
		target = hip + Vector2(12.0 if front else -16.0, 50.0)
	elif front and _g("rear") < -10.0:
		target = hip + Vector2(18.0, 46.0)
	else:
		var spread := (6.0 if front else -4.0) if f.blocking else 0.0
		target = Vector2(hip_b.x + spread + sin(ph) * 22.0 * _move, -maxf(0.0, cos(ph)) * 14.0 * _move)
	# 2-bone IK; the joint always points forward (elephant knees and wrists both do)
	var to := target - hip
	var dist := clampf(to.length(), 1.0, LEG_UPPER + LEG_LOWER - 0.5)
	var dir := to.normalized() if to.length() > 0.001 else Vector2.DOWN
	var cos_a := clampf((LEG_UPPER * LEG_UPPER + dist * dist - LEG_LOWER * LEG_LOWER) / (2.0 * LEG_UPPER * dist), -1.0, 1.0)
	var knee := hip + dir.rotated(-acos(cos_a)) * LEG_UPPER
	return [hip, knee, hip + dir * dist]


## Leg lit on its front edge, with skin creases, a gold anklet and toenails.
func _draw_leg(c: CanvasItem, leg: Array, col: Color, gold: Color) -> void:
	var hip: Vector2 = leg[0]
	var knee: Vector2 = leg[1]
	var foot: Vector2 = leg[2]
	var lit := col.lightened(0.1)
	var shade := col.darkened(0.25)
	DrawKit.circle(c, knee, 12.5, col)
	_quad_g(c, hip, knee, 28.0, 25.0, lit, shade)
	_quad_g(c, knee, foot + Vector2(0, -8), 25.0, 23.0, lit, shade)
	for k in [0.45, 0.62]:
		var p := knee.lerp(foot, k)
		var n := (foot - knee).normalized().orthogonal() * 9.0
		c.draw_line(p - n, p + n * 0.6, Color(col.darkened(0.4), 0.55), 1.2, true)
	var fc := PackedColorArray([col.darkened(0.12)])
	c.draw_primitive(PackedVector2Array([Vector2(foot.x - 14, foot.y), Vector2(foot.x - 13, foot.y - 9), Vector2(foot.x + 13, foot.y - 9), Vector2(foot.x + 14, foot.y)]), fc, PackedVector2Array())
	c.draw_primitive(PackedVector2Array([Vector2(foot.x - 13, foot.y - 9), Vector2(foot.x - 8, foot.y - 12), Vector2(foot.x + 8, foot.y - 12), Vector2(foot.x + 13, foot.y - 9)]), fc, PackedVector2Array())
	c.draw_rect(Rect2(foot.x - 13.0, foot.y - 17.0, 26.0, 5.0), gold)
	c.draw_rect(Rect2(foot.x - 13.0, foot.y - 17.0, 26.0, 1.5), gold.lightened(0.35))
	for k in 3:
		DrawKit.circle(c, Vector2(foot.x - 7.5 + k * 7.5, foot.y - 2.5), 2.6, IVORY_SHADE)


func _draw_tail(c: CanvasItem, col: Color) -> void:
	var a := deg_to_rad(100.0 + _g("tail"))
	var p := TAIL_ROOT
	for i in 3:
		var q := p + Vector2.from_angle(a) * 13.0
		c.draw_line(p, q, col, 5.0 - i, true)
		p = q
		a += deg_to_rad(_g("tail") * 0.5)
	var dir := Vector2.from_angle(a)
	var n := dir.orthogonal() * 4.0
	_fill(c, PackedVector2Array([p + n, p + dir * 12.0, p - n]), col.darkened(0.45))


## Belly band holding the caparison on.
func _draw_girth(c: CanvasItem, d: ElephantDef) -> void:
	c.draw_line(Vector2(10, -102), Vector2(17, -56), d.trim.darkened(0.35), 7.0, true)
	c.draw_line(Vector2(10, -102), Vector2(17, -56), d.trim, 4.0, true)
	for k in 3:
		DrawKit.circle(c, Vector2(10, -102).lerp(Vector2(17, -56), 0.25 + k * 0.25), 1.8, d.trim.lightened(0.5))


## Saddle cloth: team colour, gold border and kranok-like flames, a jewelled medallion, tassels.
func _draw_caparison(c: CanvasItem, d: ElephantDef) -> void:
	_shade_s(c, &"cloth", CLOTH, d.cloth, 0.14, 0.38)
	var gold := d.trim
	c.draw_polyline(CLOTH_HEM, gold, 3.5, true)
	c.draw_line(Vector2(-66, -109), Vector2(29, -109), gold, 3.0, true)
	c.draw_line(Vector2(-66, -106.5), Vector2(29, -106.5), Color(gold.darkened(0.4), 0.7), 1.0, true)
	for k in 8:
		var x := -58.0 + k * 11.5
		var y := -118.0 + absf(x + 18.0) * 0.06
		_fill(c, PackedVector2Array([Vector2(x - 3.5, y + 5), Vector2(x, y - 4), Vector2(x + 3.5, y + 5)]), gold)
	var m := Vector2(-18, -128)
	_fill(c, PackedVector2Array([m + Vector2(0, -10), m + Vector2(11, 0), m + Vector2(0, 10), m + Vector2(-11, 0)]), gold)
	_fill(c, PackedVector2Array([m + Vector2(0, -6), m + Vector2(6.5, 0), m + Vector2(0, 6), m + Vector2(-6.5, 0)]), gold.darkened(0.3))
	DrawKit.circle(c, m, 3.5, GameData.ACC.lightened(0.1))
	DrawKit.circle(c, m + Vector2(-1, -1), 1.2, Color(1, 1, 1, 0.8))
	for tip in TASSELS:
		var sway := sin(_time * 4.0 + tip.x * 0.3) * 2.0 - _g("lean") * 0.1
		var end: Vector2 = tip + Vector2(sway, 9.0)
		c.draw_line(tip, end, gold, 1.6, true)
		DrawKit.circle(c, end, 2.2, GameData.ACC)


## Small howdah on the back with upturned gold horns, and the war flag (or royal umbrella).
func _draw_seat(c: CanvasItem, d: ElephantDef) -> void:
	var gold := d.trim
	_shade_s(c, &"cushion", CUSHION, d.cloth.darkened(0.3), 0.1, 0.3)
	c.draw_line(Vector2(-53, -153), Vector2(-3, -153), gold, 2.5, true)
	c.draw_line(Vector2(-54, -144), Vector2(-2, -144), gold, 2.0, true)
	_fill(c, PackedVector2Array([Vector2(-52, -151), Vector2(-62, -167), Vector2(-57, -165), Vector2(-48, -153)]), gold)
	_fill(c, PackedVector2Array([Vector2(-4, -151), Vector2(6, -167), Vector2(1, -165), Vector2(-8, -153)]), gold)
	var sway := sin(_time * 1.8 + _phase) * 1.5
	if d.royal:
		c.draw_line(Vector2(-28, -153), Vector2(-28 + sway, -236), gold.darkened(0.25), 3.0, true)
		for i in 5:
			var y := -184.0 - i * 11.0
			var hw := 26.0 - i * 4.2
			var x := -28.0 + sway * (y + 153.0) / -83.0
			var tier := PackedVector2Array([Vector2(x - hw * 0.7, y - 7), Vector2(x + hw * 0.7, y - 7), Vector2(x + hw, y), Vector2(x - hw, y)])
			_shade(c, tier, Color("#fff6e2"), 0.0, 0.18)
			c.draw_line(Vector2(x - hw, y), Vector2(x + hw, y), gold, 2.0, true)
			for k in int(hw / 4.0):
				DrawKit.circle(c, Vector2(x - hw + 2.0 + k * 8.0, y + 2.5), 1.5, gold)
		var top := Vector2(-28 + sway, -236)
		_fill(c, PackedVector2Array([top + Vector2(-3, 6), top + Vector2(0, -8), top + Vector2(3, 6)]), gold)
	else:
		c.draw_line(Vector2(-28, -153), Vector2(-28, -214), gold.darkened(0.3), 3.0, true)
		_fill(c, PackedVector2Array([Vector2(-28, -222), Vector2(-24, -215), Vector2(-28, -208), Vector2(-32, -215)]), gold)
		var tip := 10.0 + sin(_time * 5.0 + _phase * 3.0) * 3.0
		var wave := sin(_time * 6.0) * 2.0
		var flag := PackedVector2Array([Vector2(-27, -210), Vector2(-8, -208 + wave), Vector2(tip, -205), Vector2(tip - 9, -198 + wave * 0.5), Vector2(tip, -190), Vector2(-8, -189 - wave), Vector2(-27, -185)])
		_shade(c, flag, d.flag, 0.15, 0.25)
		var hem := flag.duplicate()
		hem.append(flag[0])
		c.draw_polyline(hem, gold, 1.5, true)


func _draw_head(c: CanvasItem, B: Color, D: Color, d: ElephantDef, portrait := false) -> void:
	_shade_s(c, &"head", HEAD, B, 0.16, 0.3)
	c.draw_polyline(HEAD_RIM, Color(B.lightened(0.45), 0.55), 2.5, true)
	# headdress: team-colour cap with a gold net, gold hem and a jewelled pendant
	_shade_s(c, &"headcloth", HEADCLOTH, d.cloth, 0.12, 0.3)
	for p in NET:
		DrawKit.circle(c, p, 1.6, d.trim)
	c.draw_polyline(HEADCLOTH_HEM, d.trim, 3.0, true)
	DrawKit.shape(c, &"pendant", PENDANT, d.trim)
	DrawKit.circle(c, Vector2(42.5, 0), 2.4, GameData.ACC)
	if d.royal:
		DrawKit.shape(c, &"crown", CROWN, d.trim)
		DrawKit.circle(c, Vector2(20, -50), 2.5, GameData.ACC)
	_draw_eye(c)
	if _mood == "dizzy" and not portrait:
		for i in 4:
			var a := _time * 4.0 + TAU * i / 4.0
			var sp := Vector2(18, -58) + Vector2(cos(a) * 26.0, sin(a) * 7.0)
			_fill(c, _star(sp, 5.0 if sin(a) > 0.0 else 3.8), GameData.GOLD_LIGHT if i % 2 == 0 else Color.WHITE)
	if portrait:
		# a short, curled trunk keeps the medallion tidy
		var a := deg_to_rad(80.0)
		var pts: Array[Vector2] = [TRUNK_ROOT]
		for i in 2:
			pts.append(pts[i] + Vector2.from_angle(a + i * 0.5) * 13.0)
		for i in 2:
			DrawKit.circle(c, pts[i], float(TRUNK_W[i]) / 2.0, B)
			_quad_g(c, pts[i], pts[i + 1], TRUNK_W[i], TRUNK_W[i + 1], B.lightened(0.08), B.darkened(0.22))
	else:
		_draw_trunk(c, B, D)
	c.draw_mesh(DrawKit.mesh(&"tusk", TUSK, TUSK_COLS), null)
	c.draw_polyline(TUSK_CLOSED, IVORY_SHADE.darkened(0.25), 1.5, true)
	for r in TUSK_RINGS:
		c.draw_line(r[0], r[1], d.trim, 3.0, true)


func _draw_ear(c: CanvasItem, D: Color, d: ElephantDef) -> void:
	_shade_s(c, &"ear", EAR, D, 0.12, 0.3)
	DrawKit.shape(c, &"ear_inner", EAR_INNER, Color(D.lerp(Color("#d99a8e"), 0.35), 0.7))
	c.draw_polyline(PackedVector2Array([Vector2(-6, 2), Vector2(-14, 10), Vector2(-16, 22)]), Color(D.darkened(0.35), 0.6), 1.2, true)
	if d.royal:
		DrawKit.circle(c, Vector2(-12, 30), 4.0, d.trim)
		DrawKit.circle(c, Vector2(-12, 30), 1.8, GameData.ACC)


func _draw_eye(c: CanvasItem) -> void:
	match _mood:
		"ko":
			c.draw_line(EYE + Vector2(-4, -4), EYE + Vector2(4, 4), INK, 2.0, true)
			c.draw_line(EYE + Vector2(-4, 4), EYE + Vector2(4, -4), INK, 2.0, true)
		"hurt":
			c.draw_line(EYE + Vector2(-5, -2), EYE + Vector2(4, 1), INK, 2.5, true)
		"happy":
			c.draw_polyline(PackedVector2Array([EYE + Vector2(-5, 2), EYE + Vector2(0, -3), EYE + Vector2(5, 2)]), INK, 2.0, true)
		"dizzy":
			DrawKit.circle(c, EYE, 4.6, Color("#fdf8ef"))
			var a0 := _time * 9.0
			c.draw_arc(EYE, 3.2, a0, a0 + TAU * 0.8, 10, INK, 1.4, true)
			c.draw_arc(EYE, 1.4, a0 + PI, a0 + PI + TAU * 0.7, 8, INK, 1.2, true)
		_:
			if _blink > 0.0:
				c.draw_line(EYE + Vector2(-5, 0), EYE + Vector2(5, 0), INK, 2.0, true)
			else:
				DrawKit.circle(c, EYE, 4.6, Color("#fdf8ef"))
				DrawKit.circle(c, EYE + Vector2(1.2, 0.3), 2.8, Color("#5a3416"))
				DrawKit.circle(c, EYE + Vector2(1.4, 0.3), 1.5, INK)
				DrawKit.circle(c, EYE + Vector2(0.4, -0.9), 0.9, Color.WHITE)
				c.draw_polyline(PackedVector2Array([EYE + Vector2(-6, -3), EYE + Vector2(0, -6), EYE + Vector2(6, -4)]), Color(INK, 0.7), 1.5, true)


func _draw_trunk(c: CanvasItem, B: Color, D: Color) -> void:
	var a := deg_to_rad(_g("tb"))
	var pts: Array[Vector2] = [TRUNK_ROOT]
	for i in 5:
		if i > 0:
			a += deg_to_rad(_g(TRUNK_KEYS[i]))
		pts.append(pts[i] + Vector2.from_angle(a) * float(TRUNK_SEG[i]))
	for i in 6:
		DrawKit.circle(c, pts[i], float(TRUNK_W[i]) / 2.0, B)
	for i in 5:
		_quad_g(c, pts[i], pts[i + 1], TRUNK_W[i], TRUNK_W[i + 1], B.lightened(0.1), B.darkened(0.22))
	for i in range(1, 5):
		var n := (pts[i + 1] - pts[i - 1]).normalized().orthogonal() * float(TRUNK_W[i]) * 0.4
		c.draw_line(pts[i] - n, pts[i] + n, Color(D.darkened(0.2), 0.7), 1.3, true)
	DrawKit.circle(c, pts[5], float(TRUNK_W[5]) / 2.0 - 1.0, B.darkened(0.15))


## Mahout on the neck: pointed gold helmet, team-colour tunic, glaive with a steel blade.
func _draw_rider(c: CanvasItem, body: Transform2D, d: ElephantDef) -> void:
	c.draw_set_transform_matrix(body)
	var gold := d.trim
	var pants := d.cloth.darkened(0.5)
	var knee := RIDER_HIP + Vector2(12, 12)
	_quad(c, RIDER_HIP, knee, 9.0, 8.0, pants)
	DrawKit.circle(c, knee, 4.0, pants)
	_quad(c, knee, knee + Vector2(-3, 16), 6.5, 5.5, SKIN.darkened(0.08))
	c.draw_rect(Rect2(knee.x - 6.5, knee.y + 11.0, 7.0, 2.5), gold)
	var lean := deg_to_rad(_g("lean"))
	var torso := body * Transform2D(lean, RIDER_HIP)
	c.draw_set_transform_matrix(torso)
	var g := deg_to_rad(_g("glaive")) - lean
	var dir := Vector2.from_angle(g)
	var shoulder := Vector2(1, -19)
	var hand := shoulder + dir * 13.0
	# glaive shaft behind the body, gold-ringed
	var butt := hand - dir * 26.0
	var neck_b := hand + dir * 60.0
	c.draw_line(butt, neck_b, WOOD, 3.2, true)
	c.draw_line(butt, butt + dir * 4.0, gold, 4.0, true)
	c.draw_line(neck_b - dir * 5.0, neck_b, gold, 4.5, true)
	for k in 3:
		var tp := neck_b - dir * 5.0
		var hang := Vector2(sin(_time * 5.0 + k) * 1.5 + (k - 1) * 2.0, 8.0)
		c.draw_line(tp, tp + hang, GameData.ACC, 1.5, true)
	_shade_s(c, &"shirt", SHIRT, d.cloth.lightened(0.05), 0.15, 0.3)
	c.draw_rect(Rect2(-7, -7, 14, 3), gold)
	_fill(c, PackedVector2Array([Vector2(-6, -23), Vector2(6, -23), Vector2(0, -16)]), gold)
	DrawKit.circle(c, Vector2(0, -21), 4.5, gold.darkened(0.15))
	c.draw_rect(Rect2(-2, -27, 4, 5), SKIN.darkened(0.1))
	DrawKit.circle(c, Vector2(0.5, -31), 6.0, SKIN)
	DrawKit.circle(c, Vector2(4, -31.5), 1.0, INK)
	# pointed helmet with tiers (crowned and winged for royals)
	DrawKit.shape(c, &"helmet", HELMET, gold)
	c.draw_rect(Rect2(-6.5, -33, 13, 2.2), GameData.ACC)
	var spire := 58.0 if d.royal else 52.0
	_fill(c, PackedVector2Array([Vector2(-4, -37), Vector2(4, -37), Vector2(0.5, -spire)]), gold)
	for y in [-42.0, -47.0]:
		c.draw_line(Vector2(-2.6 + (y + 37) * -0.05, y), Vector2(2.6 + (y + 37) * 0.05, y), gold.darkened(0.35), 1.5, true)
	if d.royal:
		_fill(c, PackedVector2Array([Vector2(-6, -31), Vector2(-12, -42), Vector2(-8, -35)]), gold)
		_fill(c, PackedVector2Array([Vector2(6, -31), Vector2(12, -42), Vector2(8, -35)]), gold)
		DrawKit.circle(c, Vector2(0.3, -44), 1.6, GameData.ACC)
	# arm over the shaft
	c.draw_line(shoulder, hand, SKIN, 4.0, true)
	DrawKit.circle(c, hand, 2.6, SKIN.darkened(0.1))
	DrawKit.circle(c, shoulder, 3.0, d.cloth)
	if _dazed:
		# dizzy: three gold stars circling the head
		for i in 3:
			var a := _time * 6.0 + TAU * i / 3.0
			var sp := Vector2(0, -44) + Vector2(cos(a) * 14.0, sin(a) * 4.0)
			_fill(c, _star(sp, 4.0), GameData.GOLD_LIGHT if i != 0 else Color.WHITE)
	c.draw_set_transform_matrix(torso * Transform2D(g, neck_b))
	c.draw_mesh(DrawKit.mesh(&"blade", BLADE, BLADE_COLS), null)
	c.draw_polyline(BLADE_CLOSED, STEEL_SHADE.darkened(0.3), 1.2, true)


func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	return pts


# ---------- shape helpers ----------

func _quad(c: CanvasItem, a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal()
	if n == Vector2.ZERO:
		return
	c.draw_primitive(PackedVector2Array([a + n * wa / 2.0, b + n * wb / 2.0, b - n * wb / 2.0, a - n * wa / 2.0]), PackedColorArray([col]), PackedVector2Array())


## Quad shaded across its width: `lit` on one edge, `shade` on the other (round limbs).
func _quad_g(c: CanvasItem, a: Vector2, b: Vector2, wa: float, wb: float, lit: Color, shade: Color) -> void:
	var n := (b - a).normalized().orthogonal()
	if n == Vector2.ZERO:
		return
	var pts := PackedVector2Array([a + n * wa / 2.0, b + n * wb / 2.0, b - n * wb / 2.0, a - n * wa / 2.0])
	c.draw_primitive(pts, PackedColorArray([lit, lit, shade, shade]), PackedVector2Array())
	c.draw_line(pts[2], pts[3], shade, 1.0, true)
	c.draw_line(pts[0], pts[1], lit, 1.0, true)


## Polygon lit from above: lighter at its top, darker toward its bottom, with a soft dark rim.
func _shade(c: CanvasItem, pts: PackedVector2Array, col: Color, light: float, dark: float) -> void:
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var top := col.lightened(light)
	var bot := col.darkened(dark)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	var span := maxf(1.0, hi - lo)
	for i in pts.size():
		cols[i] = top.lerp(bot, smoothstep(0.1, 1.0, (pts[i].y - lo) / span))
	DrawKit.fill(c, pts, cols)
	_outline(c, pts, col.darkened(dark + 0.15), 1.3)


## `_shade` for a shape that never changes: its vertex colours are kept until the colour changes.
func _shade_s(c: CanvasItem, key: StringName, pts: PackedVector2Array, col: Color, light: float, dark: float) -> void:
	# one entry per colour: a mesh must outlive every draw command that uses it this frame,
	# and the same shape is drawn in two colours while flashing (body vs. HUD portrait)
	var by_col: Dictionary = _shade_cache.get(key, {})
	if by_col.is_empty():
		_shade_cache[key] = by_col
	var e: Array = by_col.get(col, [])
	if e.is_empty():
		var lo := INF
		var hi := -INF
		for p in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var top := col.lightened(light)
		var bot := col.darkened(dark)
		var cols := PackedColorArray()
		cols.resize(pts.size())
		var span := maxf(1.0, hi - lo)
		for i in pts.size():
			cols[i] = top.lerp(bot, smoothstep(0.1, 1.0, (pts[i].y - lo) / span))
		e = [col, DrawKit.build(pts, cols), pts + PackedVector2Array([pts[0]]), col.darkened(dark + 0.15)]
		by_col[col] = e
	c.draw_mesh(e[1], null)
	c.draw_polyline(e[2], e[3], 1.3, true)


## Flat polygon; larger ones get a 1px antialiased rim (the GL Compatibility renderer has no
## 2D MSAA). Tiny ornaments skip it: each rim is a separate draw call.
func _fill(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	DrawKit.fill(c, pts, PackedColorArray([col]))
	if pts.size() > 4:
		_outline(c, pts, col, 1.0)


func _outline(c: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	var o := pts.duplicate()
	o.append(pts[0])
	c.draw_polyline(o, col, width, true)


func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _smooth(pts: Array, segs := 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p0: Vector2 = pts[(i - 1 + n) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n]
		for s in segs:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(s) / segs))
	return out


## Points of a closed outline that lie above `y_max`, nudged inward: the rim-light line.
static func _rim(pts: PackedVector2Array, y_max: float, inset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	var start := 0
	for i in n:
		if pts[i].y >= y_max and pts[(i + 1) % n].y < y_max:
			start = (i + 1) % n
			break
	for k in n:
		var p := pts[(start + k) % n]
		if p.y >= y_max:
			break
		out.append(p + Vector2(0, inset))
	return out


static func _build_shapes() -> void:
	BODY = _smooth([
		Vector2(-80, -96), Vector2(-70, -122), Vector2(-44, -136), Vector2(-8, -142),
		Vector2(26, -138), Vector2(44, -124), Vector2(58, -100), Vector2(52, -70),
		Vector2(30, -58), Vector2(-10, -54), Vector2(-50, -58), Vector2(-74, -70),
	])
	BODY_RIM = _rim(BODY, -112.0, 3.5)
	HEAD = _smooth([
		Vector2(-14, -26), Vector2(0, -38), Vector2(14, -44), Vector2(24, -41), Vector2(34, -40),
		Vector2(44, -28), Vector2(48, -10), Vector2(46, 8), Vector2(34, 18), Vector2(16, 20),
		Vector2(-2, 22), Vector2(-16, 10),
	])
	HEAD_RIM = _rim(HEAD, -30.0, 3.0)
	EAR = _smooth([Vector2(0, -6), Vector2(-20, -10), Vector2(-30, 4), Vector2(-26, 24), Vector2(-12, 34), Vector2(0, 24)])
	EAR_INNER = _smooth([Vector2(-4, -2), Vector2(-17, -4), Vector2(-24, 6), Vector2(-21, 20), Vector2(-12, 26), Vector2(-4, 18)])
	HEADCLOTH = PackedVector2Array([
		Vector2(2, -38), Vector2(14, -45), Vector2(26, -42), Vector2(35, -41), Vector2(45, -29),
		Vector2(49, -12), Vector2(46, -2), Vector2(42, -7), Vector2(38, -20), Vector2(30, -30),
		Vector2(16, -34), Vector2(4, -30),
	])
	HEADCLOTH_HEM = PackedVector2Array([Vector2(46, -2), Vector2(42, -7), Vector2(38, -20), Vector2(30, -30), Vector2(16, -34), Vector2(4, -30), Vector2(2, -38)])
	NET = PackedVector2Array([Vector2(12, -40), Vector2(20, -40), Vector2(28, -38), Vector2(36, -36), Vector2(41, -28), Vector2(44, -19), Vector2(45, -10), Vector2(24, -36), Vector2(33, -32), Vector2(39, -22)])
	# saddle cloth: drapes over the back, scalloped hem
	var top := [Vector2(-68, -106), Vector2(-66, -118), Vector2(-58, -129), Vector2(-44, -138), Vector2(-26, -143), Vector2(-8, -145), Vector2(10, -143), Vector2(24, -137), Vector2(29, -128), Vector2(30, -102)]
	var cloth := PackedVector2Array(top)
	var hem := PackedVector2Array()
	var tips := PackedVector2Array()
	var sw := 98.0 / 8.0
	for k in 8:
		var x0 := 30.0 - k * sw
		for s in 6:
			var u := float(s) / 6.0
			var p := Vector2(x0 - u * sw, -102.0 + sin(u * PI) * 7.0)
			cloth.append(p)
			hem.append(p)
		tips.append(Vector2(x0 - sw / 2.0, -95.0))
	cloth.append(Vector2(-68, -102))
	hem.append(Vector2(-68, -102))
	CLOTH = cloth
	CLOTH_HEM = hem
	TASSELS = tips
	# curved tusk: quadratic bezier with tapering width, two gold rings near the base
	var p0 := Vector2(32, 14)
	var p1 := Vector2(60, 30)
	var p2 := Vector2(78, 10)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var rings := []
	for i in 6:
		var t := i / 6.0
		var pos := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tan := (p1 - p0).lerp(p2 - p1, t).normalized()
		var hw := 4.5 * pow(1.0 - t, 0.7)
		left.append(pos + tan.orthogonal() * hw)
		right.append(pos - tan.orthogonal() * hw)
	for t in [0.16, 0.26]:
		var pos: Vector2 = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tan: Vector2 = (p1 - p0).lerp(p2 - p1, t).normalized()
		var hw := 4.5 * pow(1.0 - t, 0.7) + 0.8
		rings.append([pos + tan.orthogonal() * hw, pos - tan.orthogonal() * hw])
	left.append(p2)
	right.reverse()
	TUSK = left + right
	TUSK_RINGS = rings
	BLADE = PackedVector2Array([Vector2(0, -3), Vector2(10, -7), Vector2(22, -7.5), Vector2(34, -2), Vector2(22, 2), Vector2(0, 3)])
	for q in TUSK:
		TUSK_COLS.append(IVORY_SHADE.lerp(IVORY, clampf((q.x - 32.0) / 40.0, 0.0, 1.0)))
	TUSK_CLOSED = TUSK + PackedVector2Array([TUSK[0]])
	for q in BLADE:
		BLADE_COLS.append(STEEL if q.y < 0.0 else STEEL_SHADE)
	BLADE_CLOSED = BLADE + PackedVector2Array([BLADE[0]])
