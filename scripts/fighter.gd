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
var atk_new := false      ## set on the frame a move starts
var event_done := false   ## the move's one-off event (teleport, stomp, blessing) has fired
var buff_t := 0.0         ## blessing: damage boost time left
var wave_warning := false ## an enemy shockwave is about to arrive
var stun := 0.0
var bstun := 0.0
var blocking := false
var flash := 0.0
var ko := false
var buf := ""
var buf_t := 0.0
var win := false
var balance := 100.0      ## rider's balance; at 0 the rider is dazed
var balance_t := 0.0      ## time since the rider was last shaken
var dazed := 0.0          ## seconds left off balance
var rider_t := -1.0       ## time into the rider's glaive swing, < 0 when idle
var rider_hit := false
var rider_buf_t := 0.0

var ai_t := 0.5
var ai_act := "idle"
var ai_hold := 0.0
var ai_reacted := false
var ai_wave_seen := false


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
	balance_t += dt
	if dazed > 0.0:
		dazed -= dt
		if dazed <= 0.0:
			balance = 60.0
	elif balance_t > GameData.BALANCE_DELAY:
		balance = minf(100.0, balance + GameData.BALANCE_REGEN * dt)
	var grounded := y >= G
	if not ko:
		# the rider swings on his own channel, so glaive and trunk can go together
		if inp.get("rider", false):
			rider_buf_t = 0.18
		rider_buf_t -= dt
		if rider_t >= 0.0:
			rider_t += dt
			if rider_t >= GameData.move("rider").dur:
				rider_t = -1.0
		elif rider_buf_t > 0.0 and dazed <= 0.0 and stun <= 0.0 and bstun <= 0.0 and not blocking:
			rider_t = 0.0
			rider_hit = false
			rider_buf_t = 0.0
			Sfx.play("glaive")
		for a in ["special", "heavy", "light"]:
			if inp.get(a, false):
				buf = a
				buf_t = 0.18
				break
		buf_t -= dt
		if buf_t <= 0.0:
			buf = ""
		if stun > 0.0:
			stun -= dt
			blocking = false
			if grounded:
				vx *= 0.9
		elif bstun > 0.0:
			bstun -= dt
			blocking = true
			vx *= 0.85
		elif atk != "":
			atk_t += dt
			var m := GameData.move(atk)
			if m.dash_speed > 0.0 and atk_t > m.dash_start and atk_t < m.dash_stop and not (m.dash_until_hit and atk_mask != 0):
				vx = face * m.dash_speed
			elif grounded:
				vx *= 0.8
			if atk_t >= m.dur:
				atk = ""
		else:
			if not facing_locked:
				face = 1 if o.x > x else -1
			blocking = grounded and inp.get("down", false)
			if buf == "special" and meter < 100.0:
				buf = ""
			if buf != "":
				# G and H are this elephant's own signature move and ultimate
				atk = buf if buf == "light" else (def.signature if buf == "heavy" else def.ultimate)
				atk_t = 0.0
				atk_mask = 0
				atk_new = true
				event_done = false
				blocking = false
				var m := GameData.move(atk)
				if m.ultimate:
					meter = 0.0
				Sfx.play(m.start_sfx)
				buf = ""
			elif blocking:
				vx = 0.0
			elif grounded:
				var dir := (1 if inp.get("right", false) else 0) - (1 if inp.get("left", false) else 0)
				vx = dir * (230.0 if dir == face else 170.0) * def.speed
				if inp.get("up", false):
					vy = -640.0 * lerpf(1.0, def.speed, 0.4)
					vx = dir * 260.0 * def.speed
					Sfx.play("jump")
	if ko and grounded:
		vx *= 0.88
	vy += 1800.0 * dt
	y += vy * dt
	x += vx * dt
	if y >= G:
		y = G
		vy = 0.0


func think(o: Fighter, dt: float) -> Dictionary:
	var inp := {}
	var dist := absf(o.x - x)
	var tw := "right" if o.x > x else "left"
	var aw := "left" if tw == "right" else "right"
	var threat := o.atk != "" or o.rider_t >= 0.0
	if threat and dist < 300.0 and not ai_reacted:
		ai_reacted = true
		if randf() < ai.block:
			if o.atk == "":
				# guard can't stop a glaive: interrupt it with a quick whip, or back off
				ai_act = "light" if dist < 225.0 and dazed <= 0.0 else "away"
				ai_hold = 0.0 if ai_act == "light" else 0.3
			else:
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
			if o.dazed > 0.0 and dazed <= 0.0 and dist < 260.0 and r < minf(0.9, ai.rider * 2.5):
				ai_act = "rider"
			elif o.dazed > 0.0 and o.stun > 0.0 and dazed <= 0.0 and dist >= 220.0 and r < ai.aggr:
				ai_act = "toward"      # close in on a reeling opponent for the decisive strike
			elif dazed > 0.0 and dist < 300.0 and r < ai.block:
				ai_act = "away"
			elif meter >= 100.0 and _ultimate_ok(dist) and r < ai.special:
				ai_act = "special"
			elif dist < 240.0:
				if r < ai.aggr:
					var pick := randf()
					if pick < ai.rider:
						ai_act = "rider"
					else:
						ai_act = "heavy" if randf() < ai.heavy else "light"
				elif r < ai.aggr + 0.12:
					ai_act = "jump"
				else:
					ai_act = "away" if randf() < 0.5 else "block"
			elif dist < GameData.move(def.signature).ai_range and r < 0.35:
				ai_act = "heavy"
			else:
				ai_act = "jump" if r < 0.07 else ("toward" if r < 0.88 else "idle")
	match ai_act:
		"toward":
			inp[tw] = true
		"away":
			inp[aw] = true
		"block":
			inp["down"] = true
		"jump":
			inp["up"] = true
			inp[tw] = true
			ai_act = "toward"
		"light", "heavy", "special", "rider":
			inp[ai_act] = true
			# sometimes swing the glaive along with the elephant's attack
			if ai_act != "rider" and randf() < ai.rider * 0.5:
				inp["rider"] = true
			ai_act = "idle"
	return inp


func _ultimate_ok(dist: float) -> bool:
	var u := GameData.move(def.ultimate)
	if u.event == "bless":
		return hp < max_hp * 0.8 or dazed > 0.0 or balance < 50.0
	return dist < u.ai_range
