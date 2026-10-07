class_name Fighter
extends RefCounted
## One elephant in a duel: movement, attacks, guard and the CPU brain.

var def: ElephantDef
var ai: AIProfile         ## used when ctrl == "ai"
var ctrl: String          ## "p1", "p2" or "ai"
var x: float
var y := GameData.GROUND
var vx := 0.0
var vy := 0.0
var face: int
var hp: float
var max_hp: float
var trail: float          ## health shown by the lagging pink bar
var meter := 0.0
var atk := ""             ## current move id, "" when not attacking
var atk_t := 0.0
var atk_mask := 0         ## bit per hit window that already connected
var atk_hit := false      ## the current move hit (not guarded)
var atk_new := false      ## set on the frame a move starts
var event_done := false   ## the move's one-off event (teleport, stomp, blessing) has fired
var buff_t := 0.0         ## blessing: damage boost time left
var wave_warning := false ## an enemy shockwave is about to arrive
var stun := 0.0
var bstun := 0.0
var guarding := false     ## crouching on the ground: hits from the front are guarded (all but unblockable ultimates)
var crouching := false    ## holding down
var blocking := false     ## guarding while an attack is coming: stands still in the guard pose
var flash := 0.0
var ko := false
var buf := ""
var buf_t := 0.0
var win := false
var balance := 100.0      ## at 0 the elephant is dazed: it reels, open to a decisive strike
var balance_t := 0.0      ## time since the balance was last shaken
var dazed := 0.0          ## seconds left off balance
var combo := 0            ## hits in the combo this fighter is landing right now
var combo_t := 0.0        ## time left to show the hit counter
var hits_taken := 0       ## hits taken in a row without recovering (combo damage scaling)
var juggled := false      ## knocked into the air: stays stunned until it lands
var juggle := 0           ## air hits taken since being launched
var dash_t := 0.0         ## time left in a dash (towards the opponent) or backstep
var dash_dir := 0         ## world direction of the dash, +1 / -1
var atk_ex := false       ## the current signature move is the EX version
var lag := 0.0            ## stuck recovering from a whiffed attack (hits here count as counter hits)
var spout_live := false   ## this elephant's water spout is still flying (one at a time)
var _held_dir := 0
var _tap_dir := 0
var _tap_t := 9.0
var _clock := 0.0
var _dirs := []           ## recent stick directions as [numpad digit relative to facing, time]
var _last_num := 5
var _buf_age := 9.0

var ai_t := 0.5
var ai_act := "idle"
var ai_hold := 0.0
var ai_reacted := false
var ai_wave_seen := false
var ai_chained := false   ## already decided how to follow up the move that connected
var ai_dove := false
var ai_countered := false
var ai_aa := false        ## already decided whether to swat this jump-in
var ai_punish := false    ## already decided whether to punish this whiff
var ai_guarding := false  ## already decided whether to keep guarding this string
var ai_seen := ""         ## the opponent's attack last frame, to notice each new one
var ai_seen_t := 0.0
var ai_was_bstun := false


func _init(p_def: ElephantDef, p_x: float, p_face: int, p_ctrl: String) -> void:
	def = p_def
	x = p_x
	face = p_face
	ctrl = p_ctrl
	hp = def.hp
	max_hp = def.hp
	trail = def.hp


func step(o: Fighter, inp: Dictionary, dt: float, facing_locked: bool) -> void:
	var G := GameData.GROUND
	flash = maxf(0.0, flash - dt)
	trail += (hp - trail) * minf(1.0, dt * 2.5)
	buff_t = maxf(0.0, buff_t - dt)
	combo_t = maxf(0.0, combo_t - dt)
	dash_t = maxf(0.0, dash_t - dt)
	balance_t += dt
	if dazed > 0.0:
		dazed -= dt
		if dazed <= 0.0:
			balance = 60.0
	elif balance_t > GameData.BALANCE_DELAY:
		balance = minf(100.0, balance + GameData.BALANCE_REGEN * dt)
	var grounded := y >= G
	if not ko:
		var dir := (1 if inp.get("right", false) else 0) - (1 if inp.get("left", false) else 0)
		var num := 5 + dir * face - (3 if inp.get("down", false) else 0)
		if num != _last_num:
			_last_num = num
			_dirs.append([num, _clock])
			if _dirs.size() > 12:
				_dirs.pop_front()
		_clock += dt
		var pressed := ""
		if inp.get("special", false) and inp.get("heavy", false):
			pressed = "ex"
		else:
			for a in ["special", "heavy", "medium", "light"]:
				if inp.get(a, false):
					pressed = a
					break
		if pressed != "":
			if _buf_age < GameData.EX_WINDOW and ((pressed == "special" and buf == "heavy") or (pressed == "heavy" and buf == "special")):
				pressed = "ex"
			elif pressed == "light" or pressed == "medium":
				var mo := _motion(inp)
				if mo != "" and not (mo == "spout" and spout_live):
					pressed = mo
				elif inp.get("down", false) and y >= G:
					pressed = "c" + pressed     # crouching (low) version
			if pressed == "ex" and meter < GameData.EX_COST:
				pressed = "heavy"
			buf = pressed
			_buf_age = 0.0
			# pressed during a move: wait for its combo window (or its end)
			buf_t = maxf(0.18, GameData.move(atk).dur - atk_t) if atk != "" else 0.18
		_buf_age += dt
		buf_t -= dt
		if buf_t <= 0.0:
			buf = ""
		# double-tap a direction to dash (towards the opponent) or backstep (away)
		var dash_req: int = inp.get("dash", 0)
		if dir != 0 and dir != _held_dir:
			if dir == _tap_dir and _tap_t < GameData.DOUBLE_TAP:
				dash_req = dir
				_tap_dir = 0
			else:
				_tap_dir = dir
			_tap_t = 0.0
		_held_dir = dir
		_tap_t += dt
		if stun > 0.0:
			stun -= dt
			if juggled and not grounded and juggle <= GameData.JUGGLE_MAX:
				stun = maxf(stun, 0.05)    # no recovering in mid-air: a launched elephant is open until it lands
			blocking = false
			guarding = false
			crouching = false
			if grounded:
				vx *= 0.9
		elif bstun > 0.0:
			if (buf == "heavy" or buf == "ex") and meter >= GameData.COUNTER_COST:
				meter -= GameData.COUNTER_COST
				bstun = 0.0
				_start("counter")
			else:
				bstun -= dt
				blocking = true
				vx *= 0.85
		elif atk != "":
			atk_t += dt
			var m := GameData.move(atk)
			var next := _follow_up(m)
			if next != "":
				var cancel := not m.links.has(buf)
				_begin(next)
				var nm := GameData.move(atk)
				if cancel and o.stun > 0.0 and not o.juggled and not nm.hits.is_empty():
					# a cancel off a hit always combos: the opponent stays reeling until the new move lands
					o.stun = maxf(o.stun, nm.hits[0].start + 0.06)
			else:
				if m.dash_speed > 0.0 and atk_t > m.dash_start and atk_t < m.dash_stop and not (m.dash_until_hit and atk_mask != 0):
					vx = face * m.dash_speed
				elif grounded:
					vx *= 0.8
				if atk_t >= m.dur:
					atk = ""
					if atk_mask == 0 and not m.hits.is_empty() and not m.ultimate:
						lag = GameData.WHIFF_LAG
		elif lag > 0.0:
			lag -= dt
			guarding = false
			blocking = false
			if grounded:
				vx *= 0.8
		else:
			if not facing_locked and grounded:
				face = 1 if o.x > x else -1    # keeps facing through a jump, turns on landing
			# hold down to guard: crouching stops everything but unblockable ultimates
			var free := grounded and dash_t <= 0.0
			crouching = free and inp.get("down", false)
			guarding = crouching
			blocking = guarding and (o.atk != "" or wave_warning)
			if buf == "special" and meter < 100.0 and not _ex_pending():
				buf = ""
			if buf != "" and not _ex_pending():
				# F / R dive when airborne; G and H are this elephant's own signature move and ultimate
				var kind := buf
				if not grounded and kind in ["light", "medium", "clight", "cmedium", "spout", "uppercut"]:
					kind = "dive"
				elif kind == "spout" and spout_live:
					kind = "light"
				_begin(kind)
			elif blocking or crouching:
				vx = 0.0
			elif grounded and dash_t > 0.0:
				vx = dash_dir * (GameData.DASH_SPEED if dash_dir == face else GameData.BACKSTEP_SPEED) * sqrt(def.speed)
			elif grounded and dash_req != 0:
				dash_dir = dash_req
				dash_t = GameData.DASH_TIME if dash_req == face else GameData.BACKSTEP_TIME
				vx = dash_dir * (GameData.DASH_SPEED if dash_dir == face else GameData.BACKSTEP_SPEED) * sqrt(def.speed)
				Sfx.play("whoosh")
			elif grounded:
				vx = dir * (230.0 if dir == face else 170.0) * def.speed
				if inp.get("up", false):
					# high and long enough to clear the other elephant and land behind it
					vy = -780.0 * lerpf(1.0, def.speed, 0.25)
					vx = dir * 345.0 * lerpf(1.0, def.speed, 0.5)
					Sfx.play("jump")
	if ko and grounded:
		vx *= 0.88
	vy += 1800.0 * dt
	y += vy * dt
	x += vx * dt
	if y >= G:
		if juggled and not ko:
			stun = maxf(stun, 0.2)       # brief landing before it can act again
		juggled = false
		juggle = 0
		y = G
		vy = 0.0
		if atk == "dive" and atk_t > 0.05:
			atk = ""


## Start what the buffer asked for: a move id, or "heavy" / "ex" / "special" for this elephant's own moves.
func _begin(kind: String) -> void:
	match kind:
		"heavy": _start(def.signature)
		"ex": _start(def.signature, true)
		"special": _start(def.ultimate)
		"medium": _start("mid")
		"clight": _start("clow")
		"cmedium": _start("cmid")
		_: _start(kind)


func _start(id: String, ex := false) -> void:
	var m := GameData.move(id)
	atk_ex = ex
	if ex:
		meter -= GameData.EX_COST
	atk = id
	atk_t = 0.0
	atk_mask = 0
	atk_hit = false
	atk_new = true
	event_done = false
	blocking = false
	guarding = false
	crouching = id == "clow" or id == "cmid"
	dash_t = 0.0
	buf = ""
	if m.ultimate:
		meter = 0.0
	if id == "dive":
		vy = maxf(vy, 150.0)
		vx = face * 260.0 * def.speed
	Sfx.play(m.start_sfx)


## The move that cuts this one short once it has connected: the next link of the F string,
## the signature move (G) or the ultimate (H).
func _follow_up(m: GameData.Move) -> String:
	if buf == "" or m.hits.is_empty() or atk_t < m.hits[0].stop or _ex_pending():
		return ""
	if atk_mask == 0:
		return ""                # nothing connects off a whiff: a missed attack has to recover
	if m.links.has(buf):
		# the string only goes on if it really hit; a guarded hit ends it, so the guard can strike back
		return m.links[buf] if atk_hit else ""
	match buf:
		"heavy", "ex", "spout", "uppercut":
			return buf if m.cancel_heavy else ""
		"special":
			return buf if m.cancel_super and meter >= 100.0 else ""
	return ""


## G or H was just pressed: hold it a moment in case the other one follows (G + H = EX).
func _ex_pending() -> bool:
	return _buf_age < GameData.EX_WINDOW and (buf == "special" or (buf == "heavy" and meter >= GameData.EX_COST))


## Special move from the last directions: →↓↘ (ending on ↘) is the uppercut, ↓↘→ the water spout.
## The CPU asks for them directly with "dp" / "qcf".
func _motion(inp: Dictionary) -> String:
	if inp.get("dp", false):
		return "uppercut"
	if inp.get("qcf", false):
		return "spout"
	var seq := []
	for i in range(_dirs.size() - 1, -1, -1):
		seq.push_front(_dirs[i][0])
		if _clock - float(_dirs[i][1]) > GameData.MOTION_WINDOW:
			break      # the direction already held when the window opened still counts
	if _last_num == 3 and _subseq(seq, [6, 2, 3]):
		return "uppercut"
	if _last_num in [3, 6] and (_subseq(seq, [2, 3]) or _subseq(seq, [2, 6])):
		return "spout"
	return ""


static func _subseq(seq: Array, pat: Array) -> bool:
	var j := 0
	for v in seq:
		if j < pat.size() and v == pat[j]:
			j += 1
	return j == pat.size()


func think(o: Fighter, dt: float) -> Dictionary:
	var inp := {}
	var dist := absf(o.x - x)
	var tw := "right" if o.x > x else "left"
	var aw := "left" if tw == "right" else "right"
	# combos: follow up a move that connected, dive out of a jump, counter out of block stun
	if atk_mask == 0:
		ai_chained = false
	elif atk != "" and not ai_chained:
		ai_chained = true
		var m := GameData.move(atk)
		if m.cancel_super and meter >= 100.0 and _ultimate_ok(dist) and randf() < ai.special:
			inp["special"] = true
		elif not m.links.is_empty() and randf() < ai.combo:
			var keys: Array = m.links.keys()
			var k: String = keys[randi() % keys.size()]
			inp["medium" if k.ends_with("medium") else "light"] = true
			inp["down"] = k.begins_with("c")
		elif m.cancel_heavy and randf() < ai.combo * 0.6:
			inp["heavy"] = true
			if meter >= GameData.EX_COST and meter < 100.0 and randf() < ai.special * 0.4:
				inp["special"] = true
		elif m.cancel_heavy and randf() < ai.combo * 0.3:
			inp["light"] = true
			inp["dp" if dist < 230.0 else "qcf"] = true
		if not inp.is_empty():
			return inp
	if y >= GameData.GROUND:
		ai_dove = false
	elif atk == "" and not ai_dove and vy > 0.0 and y < GameData.GROUND - 50.0 and dist < 320.0:
		ai_dove = true
		if randf() < ai.aggr:
			return {"light": true}
	# swat a jump-in with the uppercut
	if o.y >= GameData.GROUND - 30.0:
		ai_aa = false
	elif not ai_aa and dist < 250.0 and o.vy > -200.0 and atk == "" and stun <= 0.0 and dazed <= 0.0 and y >= GameData.GROUND:
		ai_aa = true
		if randf() < ai.block * 0.8:
			return {"light": true, "dp": true}
	if bstun <= 0.0:
		ai_countered = false
	elif not ai_countered:
		ai_countered = true
		if meter >= GameData.COUNTER_COST and randf() < ai.block * 0.35:
			return {"heavy": true}
	# strike back as soon as the guard holds: a guarded attack leaves the attacker the slower one
	if bstun > 0.0:
		ai_was_bstun = true
	elif ai_was_bstun:
		ai_was_bstun = false
		if stun <= 0.0 and dist < 260.0 and randf() < 0.2 + ai.block * 0.6:
			var k := _ai_normal(dist)
			return {"medium" if k.ends_with("medium") else "light": true}
	# keep guarding a string once the first hit was guarded
	if bstun <= 0.0:
		ai_guarding = false
	elif not ai_guarding:
		ai_guarding = true
		if randf() < 0.4 + ai.block:
			ai_act = "block"
			ai_hold = 0.3
	# punish an attack that missed while it recovers
	var whiffed := o.lag > 0.0
	if o.atk != "" and o.atk_mask == 0:
		var om := GameData.move(o.atk)
		whiffed = not om.hits.is_empty() and o.atk_t > om.hits[om.hits.size() - 1].stop
	if not whiffed:
		ai_punish = false
	elif not ai_punish and atk == "" and stun <= 0.0 and dazed <= 0.0 and y >= GameData.GROUND:
		ai_punish = true
		if dist < 270.0 and randf() < 0.3 + ai.block:
			if dist > 215.0:
				return {"medium": true}
			return {"heavy": true} if randf() < ai.heavy else {"light": true}
	# every new attack is a new chance to guard it (a masher never leaves a gap between them)
	if o.atk != ai_seen or o.atk_t < ai_seen_t:
		ai_reacted = false
	ai_seen = o.atk
	ai_seen_t = o.atk_t
	var threat := o.atk != ""
	if threat and dist < 300.0 and not ai_reacted:
		ai_reacted = true
		if randf() < ai.block:
			ai_act = "block"
			ai_hold = 0.35
	if not threat:
		ai_reacted = false
	if wave_warning and not ai_wave_seen:
		ai_wave_seen = true
		if randf() < 0.3 + ai.block:
			ai_act = "jump"
			ai_hold = 0.0
	if not wave_warning:
		ai_wave_seen = false
	if ai_hold > 0.0:
		ai_hold -= dt
	else:
		ai_t -= dt
		if ai_t <= 0.0:
			ai_t = ai.tick * (0.6 + randf() * 0.8)
			var r := randf()
			if o.dazed > 0.0 and o.stun > 0.0 and dazed <= 0.0 and dist < GameData.move(def.signature).ai_range and r < minf(0.9, ai.finish * 2.5):
				ai_act = "heavy"      # decisive strike
			elif o.dazed > 0.0 and o.stun > 0.0 and dazed <= 0.0 and dist >= 220.0 and r < ai.aggr:
				ai_act = "toward"      # close in on a reeling opponent for the decisive strike
			elif dazed > 0.0 and dist < 300.0 and r < ai.block:
				ai_act = "backstep" if randf() < 0.4 else "away"
			elif meter >= 100.0 and _ultimate_ok(dist) and r < ai.special:
				ai_act = "special"
			elif dist < 270.0:
				if r < ai.aggr:
					ai_act = "heavy" if randf() < ai.heavy else _ai_normal(dist)
				elif r < ai.aggr + 0.12:
					ai_act = "jump"
				else:
					ai_act = "away" if randf() < 0.5 else "block"
			elif dist < GameData.move(def.signature).ai_range and r < 0.35:
				ai_act = "heavy"
			elif dist > 300.0 and not spout_live and randf() < ai.special * 0.35:
				ai_act = "spout"
			elif dist > 400.0 and r < ai.aggr * 0.3:
				ai_act = "dash"
			else:
				ai_act = "jump" if r < 0.07 else ("toward" if r < 0.88 else "idle")
	match ai_act:
		"toward":
			inp[tw] = true
		"away":
			inp[aw] = true
		"dash", "backstep":
			var d := 1 if o.x > x else -1
			inp["dash"] = d if ai_act == "dash" else -d
			inp[tw if ai_act == "dash" else aw] = true
			ai_act = "toward" if ai_act == "dash" else "away"
		"block":
			inp["down"] = true
		"jump":
			inp["up"] = true
			inp[tw] = true
			ai_act = "toward"
		"spout":
			inp["light"] = true
			inp["qcf"] = true
			ai_act = "idle"
		"light", "medium", "clight", "cmedium":
			inp["medium" if ai_act.ends_with("medium") else "light"] = true
			inp["down"] = ai_act.begins_with("c")
			ai_act = "idle"
		"heavy", "special":
			inp[ai_act] = true
			if ai_act == "heavy" and meter >= GameData.EX_COST and meter < 100.0 and randf() < ai.special * 0.35:
				inp["special"] = true
			ai_act = "idle"
	return inp


## Short-range whip up close, the tusk poke further out; sometimes the crouching (low) version.
func _ai_normal(dist: float) -> String:
	var kind := "medium" if dist > 215.0 or randf() < 0.25 else "light"
	return ("c" + kind) if randf() < 0.3 else kind



func _ultimate_ok(dist: float) -> bool:
	var u := GameData.move(def.ultimate)
	if u.event == "bless":
		return hp < max_hp * 0.8 or dazed > 0.0 or balance < 50.0
	return dist < u.ai_range
