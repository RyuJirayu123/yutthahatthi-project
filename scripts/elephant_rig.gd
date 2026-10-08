class_name ElephantRig
extends RefCounted
## War elephant drawn from the design's painted walk cycle ("ออกแบบช้างเกม Godot/Elephant Walk
## Sheet.dc.html": 12 frames, packed into assets/sprites/elephant_walk.png by
## tools/build_elephant_sprite.py). Walking plays the cycle at the ground speed, standing shows
## one frame. Each frame a pose is picked from the fighter's state and springs ease toward it
## (so moves blend and overshoot instead of snapping); the pose moves the whole sprite: squash,
## lunge, lean and rearing up. Every ElephantDef gets its own colours: the sheet is rendered once
## through elephant_recolor.gdshader (cloth, skin, trim) and kept with mipmaps.
## Arena keeps one rig per Fighter. Local space faces +x, origin on the ground between the feet.

const G := GameData.GROUND
const DUST := Color(0.87, 0.77, 0.6)
const TEX_PATH := "res://assets/sprites/elephant_walk.png"
const SHADER_PATH := "res://scripts/elephant_recolor.gdshader"

## Sheet layout (printed by tools/build_elephant_sprite.py): frame size, 4 per row, and the
## portrait under the frames.
const FRAME := Vector2(522, 378)
const COLS := 4
const FRAMES := 12
const PIVOT := Vector2(222.6, 375.0)     ## between the feet, on the ground, in frame pixels
const PORTRAIT_Y := 1134.0
const PORTRAIT_PX := 256.0
const IDLE := 4                          ## frame shown standing still: all four feet planted
const WALK_FPS := 12.0                   ## at full walking speed
const K := 190.0 / 378.0                 ## game px per sheet pixel: the elephant stands 190 tall

## Footfalls for the dust puffs: [foot, gait phase offset (cycles)]. Far feet first.
const LEGS := [
	[Vector2(-70, 0), 0.0],
	[Vector2(60, 0), 0.25],
	[Vector2(-40, 0), 0.5],
	[Vector2(88, 0), 0.75],
]
const PITCH_PIVOT := Vector2(20, -90)
const REAR_PIVOT := Vector2(-60, -6)     ## hind feet
const NECK := Vector2(95, -120)          ## where the head is
const HEAD_TOP := Vector2(88, -176)      ## over the crown

## Spring per animated value: [frequency Hz, damping ratio]. Low damping = more overshoot.
const SPRING := {
	"bob": [5.0, 0.45], "pitch": [4.5, 0.55], "rear": [2.6, 0.42], "shift": [6.0, 0.6],
	"head": [5.5, 0.5], "sq": [4.5, 0.25],
}

class Puff:
	var pos: Vector2
	var vel: Vector2
	var r: float
	var life: float
	var max_life: float


static var _src: Texture2D
static var _shader: Shader
static var _tex := {}          ## "body/cloth/trim" colours -> the sheet recoloured for them

var _x := {}
var _v := {}
var _time := randf() * 10.0
var _phase := 0.0
var _walk := float(IDLE)       ## walk cycle position, in frames
var _move := 0.0
var _lifts := [0.0, 0.0, 0.0, 0.0]
var _was_air := false
var _prev_stun := 0.0
var _prev_bstun := 0.0
var _prev_balance := 100.0
var _dazed := false
var _mood := "normal"
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
		if _move < 0.25:
			_walk = float(IDLE)      # set off from the standing frame
		_walk += dt * WALK_FPS * clampf(f.vx * f.face / 230.0, -1.6, 1.6)
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
	}

	if air:
		p["pitch"] = clampf(f.vy * 0.015, -10.0, 10.0)
	if f.dash_t > 0.0 and f.atk == "" and not air:
		if f.dash_dir == f.face:
			_apply(p, {"pitch": 5.0, "head": 12.0, "shift": 8.0})
		else:
			_apply(p, {"pitch": -6.0, "head": -14.0, "shift": -8.0})
	if f.atk != "":
		_attack_pose(p, f)
	if f.stun > 0.0 and not f.ko:
		_apply(p, {"pitch": -8.0, "head": -18.0, "shift": -6.0})
	if f.dazed > 0.0 and not f.ko:
		if f.stun > 0.0:
			# reeling from the balance break: head lolls, body sways, trunk hangs
			_apply(p, {"head": 16.0 + sin(tm * 5.5) * 9.0, "pitch": sin(tm * 4.0) * 4.0, "shift": sin(tm * 4.0) * 6.0, "bob": 4.0})
	if f.crouching and f.atk == "" and not f.ko:
		# hunkered down: knees bent, head low
		_apply(p, {"bob": 14.0, "head": 14.0, "pitch": 2.0})
	elif f.blocking:
		_apply(p, {"bob": 7.0, "head": 12.0, "pitch": 3.0})
	if over and f.atk == "" and not f.ko:
		if f.win:
			_apply(p, {"rear": -22.0 + sin(tm * 3.0) * 3.0, "head": -20.0})
		else:
			_apply(p, {"head": 14.0})
	if f.ko:
		# thrown back while airborne, then collapse onto the belly
		if air:
			_apply(p, {"rear": -24.0, "pitch": 0.0, "head": -25.0, "bob": 0.0})
		else:
			_apply(p, {"rear": 0.0, "pitch": 5.0, "head": 24.0, "bob": 24.0})
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
			elif act:
				_apply(p, {"head": 6.0, "shift": 6.0})
		"mid":
			# rocks back, then drives both tusks straight ahead
			if pre:
				_apply(p, {"shift": -10.0, "head": -10.0, "pitch": -3.0})
			else:
				_apply(p, {"shift": 20.0 * k, "head": 16.0 * k, "pitch": 6.0 * k})
		"clow":
			# from a crouch, flicks the trunk along the ground
			_apply(p, {"bob": 18.0, "head": 20.0 if act else 10.0, "pitch": 4.0, "shift": 6.0 if act else 0.0})
		"cmid":
			# low sweep at the legs
			if pre:
				_apply(p, {"bob": 16.0, "head": 8.0, "shift": -6.0})
			else:
				_apply(p, {"bob": 16.0 * maxf(k, 0.4), "head": 26.0 * k, "pitch": 6.0 * k, "shift": 12.0 * k})
		"spout":
			# draws water up the trunk, then sprays it forward
			if t < m.event_at:
				_apply(p, {"head": -6.0, "pitch": -2.0, "shift": -6.0, "bob": 4.0})
			else:
				var ks := maxf(0.0, 1.0 - (t - m.event_at) / (m.dur - m.event_at))
				_apply(p, {"head": -14.0 * ks, "shift": 8.0 * ks, "pitch": 3.0 * ks})
		"uppercut":
			# crouches, then rears up swatting the trunk skywards
			if pre:
				_apply(p, {"bob": 8.0, "head": 12.0, "pitch": 4.0})
			else:
				_apply(p, {"rear": -20.0 * k, "head": -26.0 * k, "pitch": -4.0 * k})
		"light2":
			# backhand: the trunk drops low, then swings up and across
			if pre:
				_apply(p, {"head": 6.0})
			elif act:
				_apply(p, {"head": -10.0, "shift": 8.0, "pitch": -2.0})
		"light3":
			# trunk raised high, then slammed down in front
			if pre:
				_apply(p, {"rear": -8.0, "head": -20.0})
			else:
				_apply(p, {"rear": 2.0 * k, "pitch": 9.0 * k, "head": 22.0 * k, "shift": 14.0 * k})
		"dive":
			_apply(p, {"pitch": 14.0, "head": 26.0, "shift": 8.0})
		"counter":
			if pre:
				_apply(p, {"bob": 6.0, "head": 10.0, "shift": -8.0})
			else:
				_apply(p, {"pitch": 6.0 * k, "head": 20.0 * k, "shift": 22.0 * k})
		"gore":
			if pre:
				_apply(p, {"pitch": -6.0, "shift": -8.0, "head": -12.0})
			else:
				_apply(p, {"pitch": 8.0 * k, "shift": 18.0 * k, "head": 22.0 * k})
		"hook":
			# tusk sweeps down then yanks back
			if pre:
				_apply(p, {"pitch": -4.0, "shift": -4.0, "head": -16.0})
			elif act:
				_apply(p, {"pitch": 6.0, "shift": 10.0, "head": 22.0})
			else:
				_apply(p, {"shift": -12.0 * k, "head": -8.0 * k, "pitch": -3.0 * k})
		"lunge":
			if pre:
				_apply(p, {"bob": 7.0, "pitch": 4.0, "head": 6.0})
			else:
				_apply(p, {"pitch": 10.0 * k, "head": 22.0 * k, "shift": 14.0 * k})
		"headbutt":
			# long rear-back while armored, then the head comes down hard
			if pre:
				_apply(p, {"pitch": -10.0, "rear": -5.0, "head": -26.0, "shift": -14.0})
			else:
				_apply(p, {"pitch": 12.0 * k, "head": 30.0 * k, "shift": 24.0 * k})
		"sweep":
			if pre:
				_apply(p, {"head": -6.0})
			elif act:
				_apply(p, {"head": 10.0, "shift": 6.0, "pitch": 3.0})
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
		"charge3":
			# trumpet, ram, gore, then rear up and bring the head down for the last blow
			var h2 := m.hits[1]
			var h3 := m.hits[2]
			if t < h.start:
				_apply(p, {"rear": -8.0, "head": -16.0})
			elif t < h.stop:
				_apply(p, {"pitch": 7.0, "head": 14.0, "shift": 10.0})
			elif t < h2.stop + 0.04:
				_apply(p, {"pitch": 8.0, "head": 24.0, "shift": 16.0})
			elif t < h3.start:
				_apply(p, {"rear": -12.0, "head": -22.0, "pitch": -4.0})
			else:
				var k3 := 1.0 if t <= h3.stop + 0.06 else maxf(0.0, 1.0 - (t - h3.stop) / (m.dur - h3.stop))
				_apply(p, {"pitch": 12.0 * k3, "head": 30.0 * k3, "shift": 20.0 * k3})
		"storm":
			# trumpets, then whirls the trunk round and round
			var spin := clampf((t - 0.15) / 0.8, 0.0, 1.0)
			_apply(p, {"head": -10.0, "bob": 4.0})
		"blink":
			if t < m.event_at:
				_apply(p, {"bob": 8.0, "pitch": 6.0, "head": 10.0})
			elif pre:
				_apply(p, {"pitch": -4.0, "head": -12.0, "shift": -4.0})
			else:
				_apply(p, {"pitch": 10.0 * k, "head": 24.0 * k, "shift": 16.0 * k})
		"quake":
			# rear up on the hind legs, then slam the forefeet down
			if t < 0.45:
				_apply(p, {"rear": -26.0, "head": -20.0})
			elif t < 0.75:
				_apply(p, {"rear": 4.0, "pitch": 6.0, "head": 14.0, "bob": 6.0})
		"blessing":
			_apply(p, {"rear": -10.0, "head": -18.0})
		"roar":
			_apply(p, {"rear": -6.0, "head": -24.0, "shift": 4.0})


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
	var root := base.translated_local(Vector2(f.x, f.y)).scaled_local(Vector2(f.face, 1.0))

	c.draw_set_transform_matrix(root)
	var sw := 210.0 * (1.0 - minf(0.5, (G - f.y) / 400.0))
	DrawKit.ellipse(c, Vector2(10.0, G - f.y + 2.0), sw / 2.0, 8.0, Color(0.1, 0.05, 0.0, 0.28))
	if f.atk != "":
		var m := GameData.move(f.atk)
		if m.dash_speed > 0.0 and f.atk_t > m.dash_start and f.atk_t < m.dash_stop and absf(f.vx) > 300.0:
			for i in 4:
				c.draw_rect(Rect2(-180 - i * 18, -130 + i * 26, 70 - i * 8, 4), Color(1, 1, 1, 0.75))
		_draw_move_fx(c, f, m)
	if f.atk_ex and f.atk != "":
		# EX move: a pulsing gold aura behind the elephant
		var pulse := 0.5 + 0.5 * sin(_time * 18.0)
		DrawKit.ellipse(c, Vector2(20, -95), 150.0, 105.0, Color(GameData.GOLD_LIGHT, 0.18 + 0.12 * pulse))
		DrawKit.ellipse(c, Vector2(20, -95), 126.0, 86.0, Color(GameData.GOLD, 0.16 + 0.1 * pulse))
	if f.buff_t > 0.0:
		# blessing: gold diamonds circling the elephant while the boost lasts
		for i in 3:
			var a := _time * 2.5 + TAU * i / 3.0
			var sp := Vector2(20.0 + cos(a) * 110.0, -95.0 + sin(a) * 22.0)
			_fill(c, PackedVector2Array([sp + Vector2(0, -7), sp + Vector2(6, 0), sp + Vector2(0, 7), sp + Vector2(-6, 0)]), GameData.GOLD_LIGHT)

	var body := root * _body_xform()
	c.draw_set_transform_matrix(body * Transform2D(0.0, Vector2(K, K), 0.0, -PIVOT * K))
	var fr := _frame(f)
	var tint := Color.WHITE
	if f.flash > 0.0:
		tint = Color(1.0, 0.62, 0.58)
	elif f.ko:
		tint = Color(0.82, 0.8, 0.82)
	c.draw_texture_rect_region(_texture(f.def), Rect2(Vector2.ZERO, FRAME), Rect2(Vector2(fr % COLS, fr / COLS) * FRAME, FRAME), tint)

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
	c.draw_texture_rect_region(_texture(f.def), Rect2(-60, -64, 120, 120), Rect2(0, PORTRAIT_Y, PORTRAIT_PX, PORTRAIT_PX), tint)


## Walk cycle frame: steps forward or backward with the ground speed; the idle frame standing still.
func _frame(f: Fighter) -> int:
	if _move < 0.25 or f.y < G - 1.0:
		return IDLE
	return posmod(int(_walk), FRAMES)


## Whole-sprite pose from the springs: squash (bob, landing), lunge (shift), rear up on the hind
## feet, and lean (pitch, plus part of the head's nod since the head can't turn on its own).
func _body_xform() -> Transform2D:
	var sq := _g("sq") + clampf(_g("bob") - 1.0, -4.0, 30.0) * 0.011
	var xf := Transform2D.IDENTITY.scaled(Vector2(1.0 + sq * 0.45, 1.0 - sq))
	xf = xf * Transform2D(0.0, Vector2(_g("shift"), 0.0))
	xf = xf * _about(REAR_PIVOT, deg_to_rad(_g("rear")))
	xf = xf * _about(PITCH_PIVOT, deg_to_rad(_g("pitch") + _g("head") * 0.3))
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
			# gusts whirling round the head while the trunk spins
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

## The sheet in this elephant's colours (the plain sheet until its recoloured copy is ready).
static func _texture(d: ElephantDef) -> Texture2D:
	var key := "%s/%s/%s" % [d.body.to_html(), d.cloth.to_html(), d.trim.to_html()]
	var t: Texture2D = _tex.get(key)
	if t == null:
		if _src == null:
			_src = load(TEX_PATH)
		t = _src
		_tex[key] = t
		_bake(key, d)
	return t


## Renders the sheet through the recolour shader once, in a throwaway viewport, and keeps the
## result with mipmaps so small previews stay smooth.
static func _bake(key: String, d: ElephantDef) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return
	if _shader == null:
		_shader = load(SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("cloth", d.cloth)
	mat.set_shader_parameter("skin", d.body)
	mat.set_shader_parameter("trim", d.trim)
	var spr := Sprite2D.new()
	spr.texture = _src
	spr.centered = false
	spr.material = mat
	var vp := SubViewport.new()
	vp.size = _src.get_size()
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
	_tex[key] = ct
