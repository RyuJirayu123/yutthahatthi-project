class_name Training
extends RefCounted
## Training mode: a dummy to practise on, step-by-step lessons that check what the player did,
## combo damage readout and an input log. Main drives it, Arena draws it.

const DUMMIES := ["stand", "crouch", "guard", "jump", "cpu"]
const DUMMY_NAMES := {
	"stand": "ยืนเฉยๆ · STAND", "crouch": "ย่อ · CROUCH", "guard": "ป้องกันทุกท่า · GUARD ALL",
	"jump": "กระโดด · JUMP", "cpu": "สู้กลับ · CPU",
}

## [title, how (Thai), how (English), keys, dummy, start gap, P1 power, goal, times needed]
const LESSONS := [
	["เดินและพุ่งตัว", "แตะไปข้างหน้า 2 ครั้งเร็วๆ เพื่อพุ่งตัว (ทำ 2 ครั้ง)", "Double-tap forward to dash.", "D  D", "stand", 440.0, 0.0, "dash", 2],
	["ย่อป้องกัน", "กด S ค้างไว้ ย่อกันท่าที่หุ่นตี 3 ครั้ง", "Hold down to guard three attacks.", "S ค้าง", "attack", 230.0, 0.0, "guard", 3],
	["กันท่าต่ำ", "หุ่นจะย่อตีต่ำ ย่อกัน (S ค้าง) ได้เหมือนกัน 3 ครั้ง", "It attacks low: hold down to guard it too.", "S ค้าง", "attack_low", 230.0, 0.0, "guard_low", 3],
	["ตีระยะกลาง", "F ตีได้แค่ใกล้ๆ จากตรงนี้ต้องใช้ R แทงงา (โดน 2 ครั้ง)", "Only R reaches from here: land two tusk pokes.", "R", "stand", 250.0, 0.0, "mid_hit", 2],
	["คอมโบงวง", "กด F รัวๆ ให้ได้ 3 ฮิตติดกัน", "Mash F for a 3-hit string.", "F  F  F", "stand", 205.0, 0.0, "string3", 1],
	["สั้น › กลาง › กวาด", "F แล้ว R แล้ว S + R กวาดขาให้ล้ม", "F, then R, then down + R to sweep.", "F › R › S+R", "stand", 205.0, 0.0, "smsweep", 1],
	["ยกเลิกท่า", "F โดนแล้วกด G ทันที ตัดเข้าท่าประจำตัว", "Cancel a connecting F into your signature with G.", "F › G", "stand", 205.0, 0.0, "cancel", 1],
	["งวงพ่นน้ำ", "กด ↓ ↘ → (S, S+D, D) แล้วกด F พ่นน้ำใส่หุ่น", "Quarter-circle forward + F.", "↓ ↘ → + F", "stand", 460.0, 0.0, "spout", 1],
	["งวงเสย", "หุ่นจะกระโดดเข้ามา กด → ↓ ↘ แล้ว F เสยกลางอากาศ", "Forward, down, down-forward + F to swat the jump-in.", "→ ↓ ↘ + F", "jumpin", 440.0, 0.0, "uppercut", 1],
	["กระโดดข้ามหัว", "ยืนใกล้ๆ แล้วกระโดดเข้าหา ลงข้างหลังหุ่น", "Jump forward from close to land behind it.", "W + D", "stand", 200.0, 0.0, "jumpover", 1],
	["ท่า EX", "กด G + H พร้อมกัน ใช้พลังครึ่งหลอด ท่าประจำตัวแรงขึ้น", "Press G and H together for an EX signature.", "G + H", "stand", 210.0, 100.0, "ex", 1],
	["ปัดสวน", "ย่อกันท่าของหุ่นได้แล้วกด G ผลักสวนกลับ", "Guard a hit, then press G to shove back.", "S ค้าง › G", "attack", 230.0, 100.0, "gcounter", 1],
	["กระแทกปิดฉาก", "ตีจนหลอดทรงตัวหุ่นหมด (หุ่นเซ) แล้วกด G ท่าประจำตัวใส่", "Empty its balance bar, then land your signature move (G).", "ตี… › G", "stand", 210.0, 0.0, "finisher", 1],
	["อัลติ", "พลังเต็มแล้ว กด H ปล่อยท่าไม้ตาย", "Full power: press H.", "H", "stand", 240.0, 100.0, "ult", 1],
]

var duel: Duel
var lesson := 0           ## index into LESSONS, -1 = free practice
var count := 0            ## times the lesson's goal was met
var done_t := -1.0        ## time since the lesson was passed, < 0 while still working on it
var finished_all := false
var dummy := "stand"      ## free-practice dummy behaviour
var infinite_meter := true
var combo_dmg := 0.0      ## damage of the player's current / last combo
var combo_hits := 0
var best_dmg := 0.0
var inputs: Array[String] = []   ## newest last
var _last_input := ""
var _act_t := 0.0
var _dove := false
var _idle := [0.0, 0.0]
var _was_dash := false
var _jump_side := 0
var _was_air := false
var _dt := 1.0 / 60.0


func _init(p_duel: Duel) -> void:
	duel = p_duel
	duel.dummy_input = _dummy_input
	start_lesson(0)


func behaviour() -> String:
	return dummy if lesson < 0 else LESSONS[lesson][4]


func start_lesson(i: int) -> void:
	lesson = i
	count = 0
	done_t = -1.0
	_reset_positions(LESSONS[i][5] if i >= 0 else 220.0)
	if i >= 0:
		duel.fighters[0].meter = LESSONS[i][6]
		if LESSONS[i][7] == "finisher":
			duel.fighters[1].balance = 25.0


func next_lesson() -> void:
	if lesson >= 0 and lesson < LESSONS.size() - 1:
		start_lesson(lesson + 1)
	else:
		free_practice()


func prev_lesson() -> void:
	start_lesson(maxi(0, (lesson if lesson >= 0 else LESSONS.size()) - 1))


func free_practice() -> void:
	lesson = -1
	done_t = -1.0
	_reset_positions(220.0)


func cycle_dummy() -> void:
	dummy = DUMMIES[(DUMMIES.find(dummy) + 1) % DUMMIES.size()]
	if lesson >= 0:
		free_practice()


func _reset_positions(gap: float) -> void:
	duel.phase = "fight"
	duel.t = 0.0
	duel.spouts.clear()
	duel.waves.clear()
	for k in 2:
		var f := duel.fighters[k]
		f.x = 340.0 + k * gap
		f.y = GameData.GROUND
		f.vx = 0.0
		f.vy = 0.0
		f.face = 1 if k == 0 else -1
		f.hp = f.max_hp
		f.trail = f.max_hp
		f.balance = 100.0
		f.dazed = 0.0
		f.stun = 0.0
		f.bstun = 0.0
		f.atk = ""
		f.juggled = false
		f.combo = 0
		f.combo_t = 0.0
	duel.fighters[1].meter = 0.0
	_act_t = 0.6


## Called by Main once per frame after the duel has been updated.
func update(dt: float) -> void:
	_dt = dt
	_act_t -= dt * GameData.GAME_SPEED
	duel.phase = "fight"
	duel.timer = 99.0
	var p := duel.fighters[0]
	var d := duel.fighters[1]
	if infinite_meter and lesson < 0:
		p.meter = 100.0
	# both elephants heal once they have been left alone for a moment
	for k in 2:
		var f := duel.fighters[k]
		var busy := f.stun > 0.0 or f.juggled or f.bstun > 0.0 or f.dazed > 0.0 or duel.fighters[1 - k].combo_t > 0.0
		_idle[k] = 0.0 if busy else _idle[k] + dt
		if _idle[k] > 0.8 and f.hp < f.max_hp:
			f.hp = f.max_hp
	_log_input(duel.last_p1)
	for ev in duel.events:
		if ev.by == 0 and not ev.blocked:
			if ev.combo <= 1:
				combo_dmg = 0.0
			combo_dmg += ev.dmg
			combo_hits = ev.combo
			best_dmg = maxf(best_dmg, combo_dmg)
		if lesson >= 0 and done_t < 0.0 and _goal_met(ev):
			_progress()
	duel.events.clear()
	if lesson >= 0 and done_t < 0.0:
		_poll_goals(p, d)
	if done_t >= 0.0:
		done_t += dt
		if done_t > 1.8:
			if lesson == LESSONS.size() - 1:
				finished_all = true
			next_lesson()


func _progress() -> void:
	count += 1
	Sfx.play("select", true)
	if count >= int(LESSONS[lesson][8]):
		done_t = 0.0
		Sfx.play("win", true)


func _goal_met(ev: Dictionary) -> bool:
	var goal: String = LESSONS[lesson][7]
	var mine: bool = ev.by == 0
	match goal:
		"guard":
			return not mine and ev.blocked
		"guard_low":
			return not mine and ev.blocked and ev.low and ev.crouch
		"mid_hit":
			return mine and not ev.blocked and ev.move == "mid"
		"string3":
			return mine and not ev.blocked and ev.move == "light3" and ev.combo >= 3
		"smsweep":
			return mine and not ev.blocked and ev.move == "cmid" and ev.combo >= 3
		"cancel":
			return mine and not ev.blocked and ev.move == duel.fighters[0].def.signature and ev.combo >= 2
		"spout":
			return mine and not ev.blocked and ev.move == "spout"
		"uppercut":
			return mine and not ev.blocked and ev.move == "uppercut"
		"ex":
			return mine and not ev.blocked and ev.ex
		"gcounter":
			return mine and ev.move == "counter"
		"finisher":
			return mine and ev.finisher
		"ult":
			return mine and ev.move == duel.fighters[0].def.ultimate
	return false


## Goals that are about movement rather than hits.
func _poll_goals(p: Fighter, d: Fighter) -> void:
	match LESSONS[lesson][7]:
		"dash":
			var dashing := p.dash_t > 0.0 and p.dash_dir == p.face
			if dashing and not _was_dash:
				_progress()
			_was_dash = dashing
			# walked into the dummy: put it back so there is room to dash again
			if absf(d.x - p.x) < 230.0 and p.dash_t <= 0.0 and done_t < 0.0:
				_reset_positions(LESSONS[lesson][5])
		"jumpover":
			var air := p.y < GameData.GROUND - 1.0
			if air and not _was_air:
				_jump_side = int(signf(d.x - p.x))
			elif not air and _was_air and int(signf(d.x - p.x)) != _jump_side:
				_progress()
			elif not air and absf(d.x - p.x) > 320.0:
				_reset_positions(LESSONS[lesson][5])
			_was_air = air


## What the dummy presses this frame.
func _dummy_input(f: Fighter, o: Fighter) -> Dictionary:
	var inp := {}
	var dist := absf(o.x - f.x)
	var tw := "right" if o.x > f.x else "left"
	var aw := "left" if tw == "right" else "right"
	match behaviour():
		"crouch":
			inp["down"] = true
		"guard":
			inp["down"] = true
		"jump":
			if f.y >= GameData.GROUND and _act_t <= 0.0:
				inp["up"] = true
				_act_t = 0.9
		"attack", "attack_low":
			# walks in to whip range (the player's guard makes them back off), then attacks
			if dist > 205.0:
				inp[tw] = true
			elif _act_t <= 0.0 and f.atk == "" and f.stun <= 0.0:
				inp["light"] = true
				inp["down"] = behaviour() == "attack_low"
				_act_t = 1.3
			elif behaviour() == "attack_low" and f.atk == "":
				inp["down"] = true
		"jumpin":
			if f.y >= GameData.GROUND:
				_dove = false
				if dist < 360.0:
					inp[aw] = true       # back off to make room for the next jump
				elif _act_t <= 0.0:
					inp["up"] = true
					inp[tw] = true
					_act_t = 1.6
			elif not _dove and f.vy > 0.0 and dist < 300.0:
				_dove = true
				inp["light"] = true
		"cpu":
			return f.think(o, _dt * GameData.GAME_SPEED)
	return inp


## Input log: arrows for the stick (relative to facing), then the buttons pressed.
func _log_input(inp: Dictionary) -> void:
	if inp.is_empty():
		return
	var f := duel.fighters[0]
	var dir := (1 if inp.get("right", false) else 0) - (1 if inp.get("left", false) else 0)
	var fwd := dir * f.face
	var down: bool = inp.get("down", false)
	var up: bool = inp.get("up", false)
	var arrow := ""
	if up:
		arrow = "↗" if fwd > 0 else ("↖" if fwd < 0 else "↑")
	elif down:
		arrow = "↘" if fwd > 0 else ("↙" if fwd < 0 else "↓")
	elif fwd != 0:
		arrow = "→" if fwd > 0 else "←"
	var buttons := ""
	for b in [["light", "F"], ["medium", "R"], ["heavy", "G"], ["special", "H"]]:
		if inp.get(b[0], false):
			buttons += b[1]
	if buttons != "":
		inputs.append((arrow + " + " if arrow != "" else "") + buttons)
	elif arrow != _last_input and arrow != "":
		inputs.append(arrow)
	_last_input = arrow
	while inputs.size() > 9:
		inputs.pop_front()
