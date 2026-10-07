class_name Duel
extends RefCounted
## One match between two elephants: rounds, timer, hit detection, particles.
## Pure simulation — Arena draws it, Main reacts to `finished`.

signal finished(winner: int)

## Short text that pops up during a fight ("เสียหลัก!", "ฟันปิดฉาก!").
class Callout:
	var th: String
	var en: String
	var x: float
	var t := 0.0
	var big: bool

## Earthquake shockwave running along the ground.
class Wave:
	var x: float
	var dir: int
	var owner: Fighter
	var traveled := 0.0
	var hit := false

## Ball of water sprayed by the water spout special.
class Spout:
	var x: float
	var y: float
	var dir: int
	var owner: Fighter
	var traveled := 0.0
	var done := false

class Particle:
	var x: float
	var y: float
	var vx: float
	var vy: float
	var life: float
	var size: float
	var color: Color

const INK := GameData.INK
const ACC := GameData.ACC
const MIN_GAP := 195.0
const AIR_GAP := 100.0     ## narrower while someone is airborne, so a jump can pass over
## Basic attacks: no chip damage when guarded.
const NO_CHIP := ["light", "light2", "light3", "mid", "clow", "cmid", "dive", "counter"]

var mode: String          ## "arcade", "endless", "vs", "online", "training" or "demo"
var stage: int
var defs: Array[ElephantDef]
var ctrls: Array[String]
var round_time: float
var rounds_to_win: int
var screen_shake: bool
var ai: AIProfile

var wins: Array[int] = [0, 0]
var round_no := 1
var fighters: Array[Fighter] = []
var parts: Array[Particle] = []
var phase := "intro"      ## intro, fight, ko, done
var t := 0.0
var timer := 0.0
var belled := false
var reason := ""
var round_winner := -1
var shake := 0.0
var hitstop := 0.0
var white := 0.0          ## full-screen flash on a decisive strike
var callouts: Array[Callout] = []
var waves: Array[Wave] = []
var spouts: Array[Spout] = []
var super_t := 0.0        ## world frozen for an ultimate's cut-in (or the flash of an EX move)
var super_f: Fighter      ## who is doing it
var super_ex := false     ## the freeze is an EX flash, not an ultimate
var dummy_input: Callable ## training: what the dummy (ctrl "dummy") presses
var events: Array[Dictionary] = []   ## training: every hit / guard this frame, read by Training
var last_p1 := {}         ## player 1's input this frame (training input log)
var injected := [{}, {}]  ## online: both players' inputs for the tick being simulated
var net_wait := 0.0       ## online: seconds spent waiting for the other player's input
var replaying := false    ## online rollback: re-simulating ticks already shown, so no new particles or callouts
var run_score := 0
var scored := false       ## arcade and endless keep a score for the player
var start_hp := -1.0      ## endless: the player's health carried from the last fight (-1 = full)
var start_meter := 0.0
var _presses := {}


func _init(p_mode: String, p_stage: int, left: ElephantDef, right: ElephantDef, p_ai: AIProfile, p_round_time: float, p_rounds_to_win: int, p_screen_shake: bool) -> void:
	ai = p_ai
	mode = p_mode
	stage = p_stage
	scored = mode in ["arcade", "endless"]
	defs = [left, right]
	ctrls = ["ai" if mode == "demo" else "p1", "p2" if mode == "vs" else ("dummy" if mode == "training" else "ai")]
	if mode == "online":
		ctrls = ["net", "net"]
	round_time = p_round_time
	rounds_to_win = p_rounds_to_win
	screen_shake = p_screen_shake
	Sfx.quiet = mode == "demo"
	reset_round()


## Endless mode: the player's elephant starts with the health and power it had left.
func carry_over(hp: float, meter: float) -> void:
	start_hp = hp
	start_meter = meter
	reset_round()


## Queue a just-pressed attack action ("p1_light", …) for the next simulated frame.
func press(action: String) -> void:
	_presses[action] = true


func clear_presses() -> void:
	_presses.clear()


func reset_round() -> void:
	fighters = [Fighter.new(defs[0], 300.0, 1, ctrls[0]), Fighter.new(defs[1], 660.0, -1, ctrls[1])]
	for f in fighters:
		f.ai = ai
	if start_hp > 0.0:
		fighters[0].hp = start_hp
		fighters[0].trail = start_hp
	fighters[0].meter = maxf(fighters[0].meter, start_meter)
	phase = "intro"
	t = 0.0
	timer = 99.0 if mode == "demo" else round_time
	belled = false
	parts.clear()
	waves.clear()
	spouts.clear()
	super_t = 0.0
	super_f = null


func update(dt: float) -> void:
	t += dt
	if not replaying:
		_update_fx(dt)
	if super_t > 0.0:
		super_t -= dt
		return
	if hitstop > 0.0:
		hitstop -= dt
		return
	var sdt := dt * GameData.GAME_SPEED
	if phase == "ko" and t < 0.8:
		sdt *= 0.35
	if phase == "intro":
		if t > 1.0 and not belled:
			belled = true
			_sfx("bell")
		if t > 1.7:
			phase = "fight"
			t = 0.0
	elif phase == "fight":
		if mode != "training":
			timer -= dt
		if timer <= 0.0:
			timer = 0.0
			_end_round("time")
	for i in 2:
		fighters[i].wave_warning = _wave_near(fighters[i])
	var inputs: Array[Dictionary] = []
	for i in 2:
		inputs.append(_input_for(fighters[i], fighters[1 - i], sdt) if phase == "fight" else {})
	_presses.clear()
	for i in 2:
		var f := fighters[i]
		f.step(fighters[1 - i], inputs[i], sdt, phase == "done")
		if mode != "demo":
			f.x = clampf(f.x, GameData.WALL, GameData.W - GameData.WALL)
	for i in 2:
		_move_events(fighters[i], fighters[1 - i])
	_separate()
	_update_waves(sdt)
	_update_spouts(sdt)
	if phase == "fight":
		_check_hit(fighters[0], fighters[1])
		_check_hit(fighters[1], fighters[0])
	if phase == "ko" and t > 2.8:
		_after_round()


## Particles, screen shake and callouts: visual only, so a rollback doesn't replay them.
func _update_fx(dt: float) -> void:
	var alive: Array[Particle] = []
	for p in parts:
		var pdt := dt * GameData.GAME_SPEED
		p.life -= pdt
		if p.life > 0.0:
			p.vy += 1400.0 * pdt
			p.x += p.vx * pdt
			p.y += p.vy * pdt
			alive.append(p)
	parts = alive
	shake = maxf(0.0, shake - dt * 30.0)
	white = maxf(0.0, white - dt)
	var live: Array[Callout] = []
	for c in callouts:
		c.t += dt
		if c.t < 1.3:
			live.append(c)
	callouts = live


func _input_for(f: Fighter, o: Fighter, dt: float) -> Dictionary:
	if f.ctrl == "ai":
		return f.think(o, dt)
	if f.ctrl == "dummy":
		return dummy_input.call(f, o) if dummy_input.is_valid() else {}
	if f.ctrl == "net":
		return injected[fighters.find(f)]
	var p := f.ctrl + "_"
	var inp := {
		"left": Input.is_action_pressed(p + "left"),
		"right": Input.is_action_pressed(p + "right"),
		"up": Input.is_action_pressed(p + "up"),
		"down": Input.is_action_pressed(p + "down"),
		"light": _presses.has(p + "light"),
		"medium": _presses.has(p + "medium"),
		"heavy": _presses.has(p + "heavy"),
		"special": _presses.has(p + "special"),
	}
	if f == fighters[0]:
		last_p1 = inp
	return inp


func _end_round(why: String) -> void:
	if phase != "fight":
		return
	phase = "ko"
	t = 0.0
	reason = why
	var a := fighters[0]
	var b := fighters[1]
	var ra := a.hp / a.max_hp
	var rb := b.hp / b.max_hp
	round_winner = -1 if absf(ra - rb) < 0.001 else (0 if ra > rb else 1)
	if round_winner >= 0:
		wins[round_winner] += 1
		fighters[round_winner].win = true
	if scored and round_winner == 0:
		run_score += roundi((1000 + floorf(timer) * 20 + (2000 if a.hp >= a.max_hp else 0)) * (1 + stage * 0.5))
	_sfx("ko" if why == "ko" else "bell")


func _after_round() -> void:
	var r := rounds_to_win
	if wins[0] >= r or wins[1] >= r or round_no >= r * 2 + 1:
		var w: int
		if wins[0] == wins[1]:
			w = 0 if fighters[0].hp >= fighters[1].hp else 1
		else:
			w = 0 if wins[0] > wins[1] else 1
		if mode != "demo":
			phase = "done"
			t = 0.0
			for i in 2:
				fighters[i].win = i == w
		finished.emit(w)
	else:
		round_no += 1
		reset_round()


func _separate() -> void:
	var a := fighters[0]
	var b := fighters[1]
	if a.ko or b.ko:
		return
	var d := b.x - a.x
	var air := a.y < GameData.GROUND - 1.0 or b.y < GameData.GROUND - 1.0
	var gap := AIR_GAP if air else MIN_GAP
	if absf(d) < gap and absf(a.y - b.y) < (90.0 if air else 110.0):
		var sg := 1.0 if d == 0.0 else signf(d)
		var push := (gap - absf(d)) / 2.0
		a.x -= sg * push
		b.x += sg * push
		if mode != "demo":
			var lo := GameData.WALL
			var hi := GameData.W - GameData.WALL
			a.x = clampf(a.x, lo, hi)
			b.x = clampf(b.x, lo, hi)
			if absf(b.x - a.x) < gap:
				if a.x <= lo or a.x >= hi:
					b.x = a.x + sg * gap
				else:
					a.x = b.x - sg * gap


func _check_hit(a: Fighter, b: Fighter) -> void:
	if b.ko:
		return
	if a.atk != "":
		var m := GameData.move(a.atk)
		for i in m.hits.size():
			var h := m.hits[i]
			if a.atk_mask & (1 << i) == 0 and _connects(a, b, h, a.atk_t):
				a.atk_mask |= 1 << i
				_land(a, b, m, h)
				if b.ko:
					return


func _connects(a: Fighter, b: Fighter, h: GameData.Hit, t: float) -> bool:
	if t < h.start or t > h.stop or _invulnerable(b):
		return false
	var cx := a.x + a.face * (h.offset + h.reach / 2.0)
	return absf(b.x - cx) <= h.reach / 2.0 + 55.0 and absf(a.y - b.y) <= h.vreach


func _invulnerable(f: Fighter) -> bool:
	return f.atk != "" and f.atk_t < GameData.move(f.atk).invuln


## Time into the move during which it shrugs off hits; an EX move is armored all through its wind-up.
func _armor(f: Fighter) -> float:
	var m := GameData.move(f.atk)
	if f.atk_ex and not m.hits.is_empty():
		return maxf(m.armor, m.hits[0].start + 0.02)
	return m.armor


func _land(a: Fighter, b: Fighter, m: GameData.Move, h: GameData.Hit) -> void:
	# guard: crouching with the attacker in front; unblockable ultimates go through
	var guard := (b.guarding or b.bstun > 0.0) and signf(a.x - b.x) != -b.face and b.stun <= 0.0 and b.atk == "" and not h.overhead
	var blocked := guard
	# decisive strike: the signature move (G) landing on an elephant whose balance broke
	var finisher := m.id == a.def.signature and b.dazed > 0.0 and not guard
	var armored := not finisher and b.atk != "" and b.atk_t < _armor(b)
	var skill := a.def.rider_skill if m.id == "storm" else 1.0
	var ex := a.atk_ex and m.id == a.atk
	var dmg := h.dmg * a.def.power * skill * (GameData.BUFF_POWER if a.buff_t > 0.0 else 1.0) * (GameData.EX_POWER if ex else 1.0)
	var shaken := h.balance * a.def.rider_skill / b.def.steady * (1.5 if ex else 1.0)
	var px := (a.x + b.x) / 2.0
	var py := minf(a.y, b.y) - 95.0
	if finisher:
		_finisher(a, b)
		dmg = GameData.FINISHER_DMG * a.def.power
	elif blocked:
		# guarded basic attacks do no chip damage (mashing at a guard gets nothing); specials chip a little
		dmg *= 0.3 if m.ultimate else (0.0 if m.id in NO_CHIP else 0.12)
		# the push is shared, so the guarding elephant stays close enough to hit back
		b.vx = a.face * h.knock * 0.3
		a.vx = -a.face * h.knock * 0.25
		b.bstun = 0.16
		b.meter = minf(100.0, b.meter + 4.0 * b.def.charge)
		_burst(px, py, Color.WHITE, 6, 0.6)
		_sfx("block")
		hitstop = 0.04
		_shake_balance(b, shaken * 0.3)
	elif armored:
		# super armor: takes the damage but keeps going
		b.flash = 0.12
		_burst(px, py, GameData.GOLD_LIGHT, 10, 1.0)
		_sfx("block")
		hitstop = 0.08
		_shake_balance(b, shaken * 0.5)
	else:
		a.atk_hit = a.atk == m.id
		var big := h.dmg >= 9.0 or ex
		# counter hit: caught in the middle of an attack -> harder hit, longer stun
		var counter := b.atk != "" or b.lag > 0.0
		# combo: hits landed before the target recovers; later hits do less damage
		b.hits_taken = b.hits_taken + 1 if b.stun > 0.0 or b.juggled else 1
		dmg *= GameData.combo_scale(b.hits_taken)
		if counter:
			dmg *= GameData.COUNTER_DMG
		a.combo = b.hits_taken
		a.combo_t = GameData.COMBO_SHOW
		if scored and a == fighters[0] and a.combo >= 3:
			run_score += roundi(a.combo * 40 * (1 + stage * 0.5))
		var airborne := b.y < GameData.GROUND - 1.0
		# a hit can't cut short the reel from a balance break
		var stun := h.stun * GameData.combo_stun(b.hits_taken) + (GameData.COUNTER_STUN if counter else 0.0) + (0.15 if ex else 0.0)
		b.stun = maxf(b.stun, stun) if b.dazed > 0.0 else stun
		b.vx = a.face * h.knock * (-1.0 if h.pull else 1.0)
		if airborne or h.lift != 0.0:
			# juggle: an elephant in the air is knocked back up a few times, then just falls
			b.juggle += 1
			if b.juggle <= GameData.JUGGLE_MAX:
				b.vy = h.lift if h.lift != 0.0 else minf(b.vy, -260.0)
			b.juggled = true
			b.vx *= 0.6 if airborne else 1.0
		b.atk = ""
		b.lag = 0.0
		b.flash = 0.12
		b.blocking = false
		a.meter = minf(100.0, a.meter + h.meter * a.def.charge)
		b.meter = minf(100.0, b.meter + h.meter * 0.6 * b.def.charge)
		_burst(px, py, ACC, 18 if big else 10, 1.6 if big else 1.0)
		if screen_shake:
			shake = 9.0 if big else 3.0
		hitstop = (0.11 if big else 0.05) + (0.05 if counter else 0.0)
		if counter and mode != "demo":
			_callout("สวนจังหวะ!", "COUNTER", b.x, false)
			_burst(px, py, GameData.GOLD_LIGHT, 12, 1.4)
		_sfx(h.sound)
		_shake_balance(b, shaken)
		if h.daze:
			_shake_balance(b, 1000.0)
	b.hp = maxf(1.0 if mode == "training" else 0.0, b.hp - dmg)
	if mode == "training":
		events.append({"by": fighters.find(a), "move": m.id, "blocked": blocked, "low": h.low, "crouch": b.crouching,
			"combo": b.hits_taken if not blocked else 0, "dmg": dmg, "ex": ex, "finisher": finisher})
	if scored and a == fighters[0]:
		run_score += roundi(dmg * 10 * (1 + stage * 0.5))
	if b.hp <= 0.0:
		b.ko = true
		b.vy = -420.0
		b.vx = a.face * 300.0
		_end_round("ko")


## One-off moments inside a move: the ultimate's name pops up, then teleport / stomp / blessing.
func _move_events(f: Fighter, o: Fighter) -> void:
	if f.atk == "":
		return
	var m := GameData.move(f.atk)
	if f.atk_new:
		f.atk_new = false
		if mode != "demo":
			if m.ultimate:
				# super freeze: the world stops, the camera pushes in and the move's name cuts in
				super_t = GameData.SUPER_FREEZE
				super_f = f
				super_ex = false
				white = 0.12
			elif f.atk_ex:
				super_t = GameData.EX_FREEZE
				super_f = f
				super_ex = true
				_burst(f.x, f.y - 120.0, GameData.GOLD_LIGHT, 14, 1.2)
				_callout("EX " + m.name_th + "!", "EX " + m.name_en, f.x, false)
				_sfx("bless")
			elif m.id == "counter" or m.id == "uppercut" or m.id == "spout":
				_callout(m.name_th + "!", m.name_en, f.x, false)
	if m.event == "" or f.event_done or f.atk_t < m.event_at:
		return
	f.event_done = true
	match m.event:
		"spout":
			var s := Spout.new()
			s.x = f.x + f.face * 120.0
			s.y = GameData.GROUND - GameData.SPOUT_HEIGHT
			s.dir = f.face
			s.owner = f
			spouts.append(s)
			f.spout_live = true
			_sfx("whoosh")
		"teleport":
			# lightning step: reappear behind the opponent (or in front if a wall is in the way)
			var dir := signf(o.x - f.x) if o.x != f.x else float(f.face)
			var lo := GameData.WALL if mode != "demo" else -INF
			var hi := GameData.W - GameData.WALL if mode != "demo" else INF
			var to := clampf(o.x + dir * 175.0, lo, hi)
			if absf(to - o.x) < 150.0:
				to = clampf(o.x - dir * 175.0, lo, hi)
			_burst(f.x, f.y - 60.0, INK, 8, 0.8)
			f.x = to
			f.vx = 0.0
			f.face = 1 if o.x > f.x else -1
			_burst(f.x, f.y - 60.0, INK, 8, 0.8)
			_sfx("blink")
		"wave":
			var w := Wave.new()
			w.x = f.x + f.face * 90.0
			w.dir = f.face
			w.owner = f
			waves.append(w)
			if screen_shake:
				shake = 10.0
			_sfx("quake")
		"bless":
			f.hp = minf(f.max_hp, f.hp + GameData.BLESS_HEAL)
			f.balance = 100.0
			f.dazed = 0.0
			f.buff_t = GameData.BUFF_TIME
			_sfx("bless")


func _update_waves(dt: float) -> void:
	var live: Array[Wave] = []
	for w in waves:
		var step := GameData.WAVE_SPEED * dt
		w.x += w.dir * step
		w.traveled += step
		if randf() < 0.5:
			_burst(w.x, GameData.GROUND - 6.0, INK, 1, 0.35)
		var target := fighters[1] if w.owner == fighters[0] else fighters[0]
		if phase == "fight" and not w.hit and not target.ko and target.y >= GameData.GROUND - 12.0 and absf(target.x - w.x) < 50.0:
			w.hit = true
			var m := GameData.move("quake")
			_land(w.owner, target, m, m.wave)
		if w.traveled < GameData.WAVE_RANGE and not w.hit:
			live.append(w)
	waves = live


func _update_spouts(dt: float) -> void:
	for s in spouts:
		var step := GameData.SPOUT_SPEED * dt
		s.x += s.dir * step
		s.traveled += step
		if randf() < 0.6:
			var p := Particle.new()
			p.x = s.x - s.dir * 14.0
			p.y = s.y + randf_range(-8.0, 8.0)
			p.vx = -s.dir * randf_range(20.0, 80.0)
			p.vy = randf_range(-60.0, 20.0)
			p.life = 0.3
			p.size = randf_range(3.0, 6.0)
			p.color = Color("#bfe9ff")
			parts.append(p)
		var target := fighters[1] if s.owner == fighters[0] else fighters[0]
		# jumping elephants clear it when their feet are above the water
		if phase == "fight" and not target.ko and absf(target.x - s.x) < 55.0 and target.y > s.y + 12.0 and not _invulnerable(target):
			s.done = true
			var m := GameData.move("spout")
			_land(s.owner, target, m, m.wave)
		if s.traveled > GameData.SPOUT_RANGE:
			s.done = true
	# two spouts meeting cancel out
	for a in spouts:
		for b in spouts:
			if a != b and a.owner != b.owner and not a.done and not b.done and absf(a.x - b.x) < 30.0:
				a.done = true
				b.done = true
				_burst((a.x + b.x) / 2.0, a.y, Color("#7fd3ff"), 14, 1.0)
	var live: Array[Spout] = []
	for s in spouts:
		if s.done:
			_burst(s.x, s.y, Color("#7fd3ff"), 8, 0.7)
		else:
			live.append(s)
	spouts = live
	for f in fighters:
		f.spout_live = false
	for s in spouts:
		s.owner.spout_live = true


## True when an enemy shockwave or water spout is close and heading this way (the CPU jumps it).
func _wave_near(f: Fighter) -> bool:
	for w in waves:
		if w.owner != f and signf(f.x - w.x) == w.dir and absf(f.x - w.x) < 150.0:
			return true
	for s in spouts:
		if s.owner != f and signf(f.x - s.x) == s.dir and absf(f.x - s.x) < 190.0:
			return true
	return false


func _shake_balance(f: Fighter, amount: float) -> void:
	if f.dazed > 0.0:
		return
	f.balance_t = 0.0
	f.balance = maxf(0.0, f.balance - amount)
	if f.balance <= 0.0:
		# balance break: the elephant reels, open to a decisive strike
		f.dazed = GameData.DAZE_TIME
		f.stun = maxf(f.stun, GameData.BREAK_STUN)
		# it reels on the spot rather than flying off, so the decisive strike can still reach it
		f.vx *= 0.25
		f.vy = maxf(f.vy, -200.0)
		f.atk = ""
		f.blocking = false
		f.bstun = 0.0
		_callout("เสียหลัก!", "STUNNED", f.x, false)
		_sfx("daze")


## The signature move landing on a reeling elephant — the duel's decisive blow.
func _finisher(a: Fighter, b: Fighter) -> void:
	b.dazed = 0.0
	b.balance = 50.0
	b.balance_t = 0.0
	b.stun = 0.9
	b.vx = a.face * 520.0
	b.vy = -300.0
	b.atk = ""
	b.flash = 0.2
	b.blocking = false
	_burst((a.x + b.x) / 2.0, minf(a.y, b.y) - 150.0, ACC, 30, 2.0)
	if screen_shake:
		shake = 14.0
	hitstop = 0.3
	white = 0.3
	_callout("กระแทกปิดฉาก!", "DECISIVE STRIKE", b.x, true)
	_sfx("finisher")
	if scored and a == fighters[0]:
		run_score += roundi(1500 * (1 + stage * 0.5))


func _callout(th: String, en: String, x: float, big: bool) -> void:
	if replaying:
		return
	var c := Callout.new()
	c.th = th
	c.en = en
	c.x = x
	c.big = big
	callouts.append(c)


func _burst(x: float, y: float, color: Color, n: int, sp: float) -> void:
	if replaying:
		return
	for i in n:
		var ang := randf() * TAU
		var v := (150.0 + randf() * 350.0) * sp
		var p := Particle.new()
		p.x = x
		p.y = y
		p.vx = cos(ang) * v
		p.vy = sin(ang) * v - 200.0
		p.life = 0.35 + randf() * 0.3
		p.size = 4.0 + randf() * 8.0
		p.color = GameData.GOLD_LIGHT if randf() < 0.3 else color
		parts.append(p)


func _sfx(n: String) -> void:
	if mode != "demo":
		Sfx.play(n)
