class_name ElephantRig
extends RefCounted
## War elephant drawn from the design's painted action set ("ออกแบบช้างเกม Godot/Elephant
## Actions.dc.html": idle, walk, run, guard, tusk attack, trunk attack, charge, hit, victory,
## death; packed into assets/sprites/ by tools/build_elephant_sprite.py). Each frame the rig
## picks an action and frame from the fighter's state; attacks are timed so the action's impact
## frame lands when the move's hit comes out. A few springs add squash on landing and hits.
## Colours: the body is drawn with elephant_recolor.gdshader (material_for), which turns the
## painted red cloth, grey skin and gold into the ElephantDef's cloth, body and trim colours.
## Arena keeps one rig per Fighter and draws it in three passes: draw_back (shadow, auras),
## draw_body (the sprite, on its own layer with the recolour material) and draw_front (stars,
## guard). Local space faces +x, origin on the ground between the feet.

const G := GameData.GROUND
const DUST := Color(0.87, 0.77, 0.6)
const SHEETS := "res://assets/sprites/%s.png"
const PORTRAIT_PATH := "res://assets/sprites/portrait.png"
const SHADER_PATH := "res://scripts/elephant_recolor.gdshader"
const COLS := 4

## action -> [frames, frame size, pivot in the frame] (printed by tools/build_elephant_sprite.py)
const ANIMS := {
	"idle": [12, Vector2(419, 299), Vector2(213.6, 296.4)],
	"walk": [36, Vector2(418, 302), Vector2(211.2, 298.8)],
	"run": [22, Vector2(445, 307), Vector2(232.8, 302.4)],
	"guard": [12, Vector2(408, 296), Vector2(207.0, 294.0)],
	"attack_tusk": [12, Vector2(457, 299), Vector2(218.4, 297.0)],
	"attack_trunk": [16, Vector2(497, 310), Vector2(232.8, 307.2)],
	"charge": [16, Vector2(498, 310), Vector2(234.0, 307.2)],
	"hit": [12, Vector2(520, 302), Vector2(256.2, 299.4)],
	"victory": [16, Vector2(470, 324), Vector2(235.8, 307.2)],
	"death": [16, Vector2(528, 298), Vector2(264.0, 282.0)],
}
const K := 190.0 / 295.0                 ## game px per sheet pixel: the elephant stands 190 tall
const GUARD_HOLD := 5                    ## guard frame held while guarding: head down, trunk curled
## Playback speeds from the design (Elephant Actions.dc.html, frames a second of its 12- and
## 16-frame sheets). Attacks and hit reactions don't use these: they follow the move's timing.
const FPS := {"idle": 16.0, "guard": 16.0, "victory": 16.0, "death": 15.0}
const WALK_CYCLES := 18.0 / 12.0         ## walk cycles a second at full walking speed
const RUN_CYCLES := 22.0 / 12.0          ## run cycles a second while dashing

## Move -> [action, first frame, impact frame, last frame]. The frames from first to impact play
## during the wind-up, the impact frame while the hit is out, the rest during recovery.
## Impact -1: the frames simply play across the whole move; -2: they swing back and forth.
## A last frame before the impact frame plays the recovery backwards (back to that frame).
const MOVE_ANIM := {
	"light": ["attack_trunk", 8, 10, 15],
	"light2": ["attack_trunk", 5, 10, 15],
	"light3": ["attack_trunk", 3, 10, 15],
	"clow": ["attack_trunk", 8, 10, 15],
	"cmid": ["attack_trunk", 6, 10, 15],
	"uppercut": ["attack_trunk", 1, 5, 9],
	"sweep": ["attack_trunk", 5, 10, 15],
	"storm": ["attack_trunk", 4, -2, 11],
	"roar": ["victory", 0, -1, 15],
	"blessing": ["victory", 0, -1, 15],
	"mid": ["charge", 0, 3, 0],
	"gore": ["attack_tusk", 0, 3, 11],
	"hook": ["attack_tusk", 0, 3, 11],
	"headbutt": ["attack_tusk", 0, 3, 11],
	"double": ["attack_tusk", 0, 3, 11],
	"counter": ["attack_tusk", 1, 3, 11],
	"dive": ["attack_tusk", 3, 3, 3],
	"rush": ["charge", 9, 12, 15],
	"rise": ["charge", 1, 4, 0],
	"blink": ["charge", 9, 12, 15],
	"charge3": ["charge", 8, -1, 15],
	"quake": ["victory", 1, 5, 10],
}

## Footfalls for the dust puffs: [foot, gait phase offset (cycles)]. Far feet first.
const LEGS := [
	[Vector2(-70, 0), 0.0],
	[Vector2(60, 0), 0.25],
	[Vector2(-40, 0), 0.5],
	[Vector2(88, 0), 0.75],
]
const PITCH_PIVOT := Vector2(10, -90)
const NECK := Vector2(90, -120)          ## where the head is
const HEAD_TOP := Vector2(78, -186)      ## over the crown

## Spring per animated value: [frequency Hz, damping ratio]. Low damping = more overshoot.
const SPRING := {"pitch": [4.5, 0.55], "shift": [6.0, 0.6], "sq": [4.5, 0.25]}

class Puff:
	var pos: Vector2
	var vel: Vector2
	var r: float
	var life: float
	var max_life: float


static var _sheets := {}       ## action -> Texture2D
static var _shader: Shader
static var _materials := {}    ## "body/cloth/trim" colours -> ShaderMaterial
static var _portraits := {}    ## "body/cloth/trim" colours -> recoloured portrait

var _x := {}
var _v := {}
var _time := randf() * 10.0
var _phase := 0.0
var _walk := 0.0               ## walk cycle position, in cycles
var _move := 0.0
var _lifts := [0.0, 0.0, 0.0, 0.0]
var _was_air := false
var _prev_stun := 0.0
var _prev_bstun := 0.0
var _prev_balance := 100.0
var _stun_max := 1.0           ## the current stun's full length, for timing the hit action
var _dazed := false
var _mood := "normal"
var _state := ""               ## the state the current action belongs to, and time in it
var _state_t := 0.0
var _anim := "idle"            ## action and frame picked this update
var _frame := 0
var _last_x := 0.0
var _last_atk_t := 0.0
var _streak := Vector3.ZERO     ## lightning-step trail: from x, to x, time left
var _puffs: Array[Puff] = []


# ---------- animation ----------

func update(f: Fighter, duel_phase: String, dt: float) -> void:
	if dt <= 0.0:
		return
	_time += dt
	var air := f.y < G - 1.0
	var walking := not air and not f.ko and f.stun <= 0.0 and not f.blocking and not f.crouching
	if walking:
		_phase += f.vx * f.face * dt * 0.06
		_walk += dt * WALK_CYCLES * clampf(f.vx * f.face / 230.0, -1.6, 1.6)
	_move = move_toward(_move, clampf(absf(f.vx) / 200.0, 0.0, 1.0) if walking else 0.0, dt * 5.0)

	if f.stun > _prev_stun + 0.01:
		_kick("sq", 1.2)
		_stun_max = maxf(f.stun, 0.05)
	if f.bstun > _prev_bstun + 0.01:
		_kick("shift", -90.0)
	if f.balance < _prev_balance - 1.0 or (f.dazed <= 0.0 and _dazed and f.stun > 0.0):
		_kick("pitch", -40.0 if f.dazed <= 0.0 else -80.0)
	if _was_air and not air:
		_kick("sq", 2.5)
		for i in 6:
			_puff(f, randf_range(-70.0, 50.0), randf_range(-60.0, 60.0), 1.3)
	elif air and not _was_air:
		_kick("sq", -1.5)
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

	_pick(f, over, air, dt)
	var p := {"pitch": 0.0, "shift": 0.0, "sq": 0.0}
	if air and not f.ko:
		p["pitch"] = clampf(f.vy * 0.012, -8.0, 8.0)
	_step_springs(p, dt)

	var alive: Array[Puff] = []
	for pf in _puffs:
		pf.life -= dt
		if pf.life > 0.0:
			pf.pos += pf.vel * dt
			pf.vel *= 0.9
			pf.r += dt * 26.0
			alive.append(pf)
	_puffs = alive


## Which action and frame to show.
func _pick(f: Fighter, over: bool, air: bool, dt: float) -> void:
	var state: String
	if f.ko:
		state = "thrown" if air else "death"
	elif f.atk != "" and MOVE_ANIM.has(f.atk):
		state = "attack"
	elif f.stun > 0.0:
		state = "reel" if f.juggled or air else ("dizzy" if f.dazed > 0.0 else "hit")
	elif over and f.win:
		state = "victory"
	elif air:
		state = "air"
	elif f.blocking or f.crouching or f.bstun > 0.0:
		state = "guard"
	elif f.dash_t > 0.0:
		state = "dash" if f.dash_dir == f.face else "backstep"
	elif _move > 0.25:
		state = "walk"
	else:
		state = "idle"
	if state != _state:
		_state = state
		_state_t = 0.0
	else:
		_state_t += dt
	var t := _state_t
	match state:
		"death":
			_show("death", int(t * FPS["death"]))
		"thrown", "reel":
			_show("hit", 2)
		"attack":
			_attack_frame(f)
		"hit":
			_show("hit", int((1.0 - f.stun / _stun_max) * 11.0))
		"dizzy":
			_show("hit", 4 + int(pingpong(t * 7.0, 4.0)))
		"victory":
			_show("victory", int(t * FPS["victory"]) % 16)
		"air":
			_show("run", _cycle("run", 0.33 if f.vy < 0.0 else 0.67))
		"guard":
			_show("guard", mini(int(t * FPS["guard"]), GUARD_HOLD))
		"dash":
			_show("run", _cycle("run", t * RUN_CYCLES))
		"backstep":
			_show("walk", _cycle("walk", -t * RUN_CYCLES))
		"walk":
			_show("walk", _cycle("walk", _walk))
		_:
			_show("idle", int(_time * FPS["idle"]) % 12)


## Attack frames timed to the move: wind-up frames until the hit comes out, the impact frame
## while it's out, recovery frames after.
func _attack_frame(f: Fighter) -> void:
	var spec: Array = MOVE_ANIM[f.atk]
	var m := GameData.move(f.atk)
	var t := f.atk_t
	var first: int = spec[1]
	var impact: int = spec[2]
	var last: int = spec[3]
	if impact == -1:
		_show(spec[0], first + int(t / m.dur * (last - first + 1)), last)
		return
	if impact == -2:
		_show(spec[0], first + int(pingpong(t * 16.0, float(last - first))), last)
		return
	var start := m.dur * 0.4
	var stop := start
	if not m.hits.is_empty():
		start = m.hits[0].start
		stop = m.hits[0].stop
	elif m.event_at > 0.0:
		start = m.event_at
		stop = m.event_at
	var fr: int
	if t < start:
		fr = first + int(t / start * (impact - first + 1))
		fr = mini(fr, impact)
	elif t <= stop:
		fr = impact
	else:
		var k := (t - stop) / maxf(0.01, m.dur - stop)
		if last < impact:
			fr = impact - int(k * (impact - last + 1))
			fr = maxi(fr, last)
		else:
			fr = impact + int(k * (last - impact + 1))
	_show(spec[0], fr, maxi(last, impact))


## Frame of a looping action at cycle position `c` (any real number; it wraps).
func _cycle(anim: String, c: float) -> int:
	var n: int = ANIMS[anim][0]
	return mini(int(fposmod(c, 1.0) * n), n - 1)


func _show(anim: String, fr: int, last := -1) -> void:
	_anim = anim
	var n: int = ANIMS[anim][0]
	_frame = clampi(fr, 0, n - 1 if last < 0 else mini(last, n - 1))


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


## All three passes on one canvas item (the select screen's previews, which carry the material).
func draw(c: CanvasItem, f: Fighter, base: Transform2D) -> void:
	draw_back(c, f, base)
	draw_body(c, f, base)
	draw_front(c, f, base)


## Behind the elephant: its shadow, dash streaks, ultimate effects, EX aura, blessing diamonds.
func draw_back(c: CanvasItem, f: Fighter, base: Transform2D) -> void:
	var root := _root(f, base)
	c.draw_set_transform_matrix(root)
	var sw := 220.0 * (1.0 - minf(0.5, (G - f.y) / 400.0))
	DrawKit.ellipse(c, Vector2(5.0, G - f.y + 2.0), sw / 2.0, 8.0, Color(0.1, 0.05, 0.0, 0.28))
	if f.atk != "":
		var m := GameData.move(f.atk)
		if m.dash_speed > 0.0 and f.atk_t > m.dash_start and f.atk_t < m.dash_stop and absf(f.vx) > 300.0:
			for i in 4:
				c.draw_rect(Rect2(-180 - i * 18, -130 + i * 26, 70 - i * 8, 4), Color(1, 1, 1, 0.75))
		_draw_move_fx(c, f, m)
	if f.atk_ex and f.atk != "":
		# EX move: a pulsing gold aura behind the elephant
		var pulse := 0.5 + 0.5 * sin(_time * 18.0)
		DrawKit.ellipse(c, Vector2(10, -95), 150.0, 105.0, Color(GameData.GOLD_LIGHT, 0.18 + 0.12 * pulse))
		DrawKit.ellipse(c, Vector2(10, -95), 126.0, 86.0, Color(GameData.GOLD, 0.16 + 0.1 * pulse))
	if f.buff_t > 0.0:
		# blessing: gold diamonds circling the elephant while the boost lasts
		for i in 3:
			var a := _time * 2.5 + TAU * i / 3.0
			var sp := Vector2(10.0 + cos(a) * 110.0, -95.0 + sin(a) * 22.0)
			_fill(c, PackedVector2Array([sp + Vector2(0, -7), sp + Vector2(6, 0), sp + Vector2(0, 7), sp + Vector2(-6, 0)]), GameData.GOLD_LIGHT)


## The elephant itself: one frame of the picked action. `c` should carry material_for(f.def).
func draw_body(c: CanvasItem, f: Fighter, base: Transform2D) -> void:
	var spec: Array = ANIMS[_anim]
	var size: Vector2 = spec[1]
	var pivot: Vector2 = spec[2]
	c.draw_set_transform_matrix(_root(f, base) * _body_xform() * Transform2D(0.0, Vector2(K, K), 0.0, -pivot * K))
	var tint := Color.WHITE
	if f.flash > 0.0:
		tint = Color(1.0, 0.62, 0.58)
	var src := Rect2(Vector2(_frame % COLS, _frame / COLS) * size, size)
	c.draw_texture_rect_region(_sheet(_anim), Rect2(Vector2.ZERO, size), src, tint)


## In front of the elephant: dizzy stars and the guard shield.
func draw_front(c: CanvasItem, f: Fighter, base: Transform2D) -> void:
	var root := _root(f, base)
	var body := root * _body_xform()
	if _mood == "dizzy":
		c.draw_set_transform_matrix(body)
		for i in 4:
			var a := _time * 4.0 + TAU * i / 4.0
			var sp := HEAD_TOP + Vector2(cos(a) * 40.0, sin(a) * 10.0)
			_fill(c, _star(sp, 8.0 if sin(a) > 0.0 else 6.0), GameData.GOLD_LIGHT if i % 2 == 0 else Color.WHITE)
	if _dazed and _mood != "dizzy":
		# still off balance after the reel: three gold stars over the crown
		c.draw_set_transform_matrix(body)
		for i in 3:
			var a := _time * 6.0 + TAU * i / 3.0
			var sp := HEAD_TOP + Vector2(cos(a) * 24.0, -8.0 + sin(a) * 7.0)
			_fill(c, _star(sp, 7.0), GameData.GOLD_LIGHT if i != 0 else Color.WHITE)
	if f.blocking or f.bstun > 0.0:
		# guard shield: low and wide when crouching
		c.draw_set_transform_matrix(root)
		var gy := -62.0 if f.crouching else -92.0
		c.draw_arc(Vector2(120, gy), 96.0, -0.75, 0.75, 20, Color(GameData.GOLD_LIGHT, 0.85), 5.0, true)
		c.draw_arc(Vector2(120, gy), 104.0, -0.6, 0.6, 16, Color(GameData.GOLD, 0.5), 3.0, true)


## The head in its round frame for the HUD medallion and the ultimate cut-in (fits a radius of
## about 58 in `xf` space).
func draw_portrait(c: CanvasItem, f: Fighter, xf: Transform2D) -> void:
	c.draw_set_transform_matrix(xf)
	var tint := Color(1.0, 0.62, 0.58) if f.flash > 0.0 else Color.WHITE
	c.draw_texture_rect(_portrait(f.def), Rect2(-60, -64, 120, 120), false, tint)


func _root(f: Fighter, base: Transform2D) -> Transform2D:
	return base.translated_local(Vector2(f.x, f.y)).scaled_local(Vector2(f.face, 1.0))


## Springs on top of the action: squash (landing, hits), a shove back when guarding a hit, and a
## lean in the air.
func _body_xform() -> Transform2D:
	var sq := _g("sq")
	var xf := Transform2D.IDENTITY.scaled(Vector2(1.0 + sq * 0.45, 1.0 - sq))
	xf = xf * Transform2D(0.0, Vector2(_g("shift"), 0.0))
	xf = xf * _about(PITCH_PIVOT, deg_to_rad(_g("pitch")))
	return xf


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
			# gusts whirling round the head while the trunk swings
			if t > 0.15 and t < 0.95:
				var hub := _body_xform() * NECK
				for i in 3:
					var a0 := t * 14.0 + TAU * i / 3.0
					c.draw_arc(hub, 70.0 + i * 12.0, a0, a0 + 1.7, 14, Color(1, 1, 1, 0.5 - i * 0.1), 4.0, true)
					c.draw_arc(hub, 64.0 + i * 12.0, a0 + 0.3, a0 + 1.3, 10, Color(DUST, 0.45), 3.0, true)


func _about(p: Vector2, a: float) -> Transform2D:
	return Transform2D(0.0, p) * Transform2D(a, Vector2.ZERO) * Transform2D(0.0, -p)


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


# ---------- colours ----------

static func _sheet(anim: String) -> Texture2D:
	var t: Texture2D = _sheets.get(anim)
	if t == null:
		t = load(SHEETS % anim)
		_sheets[anim] = t
	return t


static func _key(d: ElephantDef) -> String:
	return "%s/%s/%s" % [d.body.to_html(), d.cloth.to_html(), d.trim.to_html()]


## The recolour material for an elephant: put it on the canvas item that draws its body.
static func material_for(d: ElephantDef) -> ShaderMaterial:
	var key := _key(d)
	var mat: ShaderMaterial = _materials.get(key)
	if mat == null:
		if _shader == null:
			_shader = load(SHADER_PATH)
		mat = ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("cloth", d.cloth)
		mat.set_shader_parameter("skin", d.body)
		mat.set_shader_parameter("trim", d.trim)
		_materials[key] = mat
	return mat


## The portrait in this elephant's colours (the painted one until its recoloured copy is ready).
static func _portrait(d: ElephantDef) -> Texture2D:
	var key := _key(d)
	var t: Texture2D = _portraits.get(key)
	if t == null:
		t = load(PORTRAIT_PATH)
		_portraits[key] = t
		_bake_portrait(key, d, t)
	return t


## Renders the portrait through the recolour shader once, in a throwaway viewport (the HUD is
## drawn without the material), and keeps the result with mipmaps.
static func _bake_portrait(key: String, d: ElephantDef, src: Texture2D) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return
	var spr := Sprite2D.new()
	spr.texture = src
	spr.centered = false
	spr.material = material_for(d)
	var vp := SubViewport.new()
	vp.size = src.get_size()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.add_child(spr)
	tree.root.add_child.call_deferred(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	var ct := CanvasTexture.new()
	ct.diffuse_texture = ImageTexture.create_from_image(img)
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portraits[key] = ct
