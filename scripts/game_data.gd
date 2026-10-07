class_name GameData
extends RefCounted
## Shared constants: arena size, palette, attack moves and fonts.

const W := 960.0
const H := 540.0
const GROUND := 440.0
const WALL := 80.0
## Speed of the whole fight (moves, walking, jumps, effects); 1.0 = original pace. The round timer stays in real seconds.
const GAME_SPEED := 0.7

## Thai court palette: lacquer red, gold leaf, cream paper, dark teak.
const INK := Color("#2a170d")
const BG := Color("#fbf1dc")
const SURFACE := Color("#f3e3c3")
const GRID := Color("#e6d2a8")
const ACC := Color("#cc1f1f")
const ACC_100 := Color("#fde6d6")
const ACC_200 := Color("#f9cdb3")
const ACC_300 := Color("#f4a487")
const ACC_600 := Color("#b5181a")
const ACC_700 := Color("#8e1013")
const NEUTRAL_700 := Color("#6f5947")
const DIVIDER := Color(0.165, 0.09, 0.05, 0.3)
const HURT_DARK := Color("#ff8a70")
const GOLD := Color("#e8b33a")
const GOLD_LIGHT := Color("#ffe08a")
const GOLD_DARK := Color("#9c6a14")
const JADE := Color("#1f6b4a")


## One hit window of a move.
class Hit:
	var start: float       ## hitbox opens (s into the move)
	var stop: float        ## hitbox closes
	var reach: float
	var dmg: float
	var knock: float
	var stun: float
	var meter: float       ## power gained by the attacker
	var balance: float     ## damage to the opponent's balance
	var lift := 0.0        ## launch speed given to the target (negative = up)
	var offset := 100.0    ## hitbox starts this far in front of the attacker
	var vreach := 120.0    ## max height difference that still connects
	var overhead := false  ## can't be guarded at all
	var low := false       ## a crouching attack (training checks it)
	var high := false      ## a jump-in attack
	var pull := false      ## knocks the target toward the attacker
	var daze := false      ## breaks the target's balance at once
	var sound := "heavy"


class Move:
	var id: String
	var name_th := ""
	var name_en := ""
	var desc := ""             ## one-line Thai description for the select screen
	var dur: float             ## total length (s)
	var hits: Array[Hit] = []
	var ultimate := false      ## needs a full power bar
	var dash_start := 0.0
	var dash_stop := 0.0
	var dash_speed := 0.0
	var dash_until_hit := false
	var armor := 0.0           ## won't flinch when hit before this time
	var invuln := 0.0          ## can't be hit at all before this time
	var event := ""            ## "teleport", "wave" or "bless", fired once at event_at
	var event_at := 0.0
	var wave: Hit              ## the ground shockwave of an earthquake stomp, or the water spout projectile
	var ai_range := 240.0      ## CPU uses it when the opponent is closer than this
	var start_sfx := "whoosh"
	var links := {}            ## next attack button -> move it chains into ("light", "medium", "clight" / "cmedium" = crouching)
	var cancel_heavy := false  ## once it connects, G cuts its recovery short with the signature move
	var cancel_super := false  ## once it connects, H (full power bar) cuts it short with the ultimate


## Moves by id. The normals and specials are shared; each ElephantDef picks a signature (G)
## and an ultimate (H, full power bar).
static var MOVES := {}

static func move(id: String) -> Move:
	if MOVES.is_empty():
		_build_moves()
	return MOVES[id]


static func _hit(start: float, stop: float, reach: float, dmg: float, knock: float, stun: float, meter: float, balance: float, extra := {}) -> Hit:
	var h := Hit.new()
	h.start = start; h.stop = stop; h.reach = reach; h.dmg = dmg
	h.knock = knock; h.stun = stun; h.meter = meter; h.balance = balance
	for k in extra:
		h.set(k, extra[k])
	return h


static func _move(id: String, dur: float, hits: Array, extra := {}) -> Move:
	var m := Move.new()
	m.id = id
	m.dur = dur
	m.hits.assign(hits)
	for k in extra:
		m.set(k, extra[k])
	MOVES[id] = m
	return m


static func _build_moves() -> void:
	var unblockable := {"overhead": true, "vreach": 200.0, "sound": "clang"}
	# Normals. F = short range, R = mid range, holding down makes them low (crouch to guard).
	# Pressing the next button during a move chains along `links` once it hit (a guarded hit ends the string);
	# G / specials / H cut a move short once it connected (hit or guarded). G on a reeling elephant = decisive strike.
	var string := {"cancel_heavy": true, "cancel_super": true}
	_move("light", 0.34, [_hit(0.07, 0.17, 72, 5, 150, 0.26, 8, 3, {"sound": "hit"})],
		string.merged({"links": {"light": "light2", "medium": "mid", "clight": "clow", "cmedium": "cmid"}}))
	_move("light2", 0.38, [_hit(0.08, 0.18, 76, 6, 170, 0.30, 8, 4, {"sound": "hit"})],
		string.merged({"links": {"light": "light3", "medium": "mid", "cmedium": "cmid"}, "name_th": "ตวัดงวง", "name_en": "BACKHAND",
		"dash_stop": 0.10, "dash_speed": 300.0}))
	_move("light3", 0.50, [_hit(0.16, 0.26, 84, 9, 330, 0.50, 10, 8, {"lift": -460.0})],
		string.merged({"name_th": "ทุบงวง", "name_en": "TRUNK SLAM", "dash_stop": 0.14, "dash_speed": 320.0}))
	# R: a long tusk poke for mid range
	_move("mid", 0.50, [_hit(0.13, 0.24, 110, 7, 220, 0.36, 9, 5, {"sound": "hit"})],
		string.merged({"links": {"cmedium": "cmid"}, "name_th": "แทงงาตรง", "name_en": "TUSK POKE", "dash_stop": 0.12, "dash_speed": 200.0}))
	# down + F: quick whip at the feet
	_move("clow", 0.34, [_hit(0.06, 0.15, 76, 4, 120, 0.26, 6, 2, {"offset": 90.0, "low": true, "sound": "hit"})],
		string.merged({"links": {"light": "light2", "medium": "mid", "cmedium": "cmid"}, "name_th": "ย่อฟาดขา", "name_en": "LOW WHIP"}))
	# down + R: sweeps the legs and trips the opponent; ends a combo
	_move("cmid", 0.62, [_hit(0.15, 0.27, 120, 8, 160, 0.5, 10, 6, {"offset": 90.0, "low": true, "lift": -300.0})],
		{"name_th": "กวาดขา", "name_en": "LEG SWEEP", "dash_stop": 0.12, "dash_speed": 180.0})
	# F or R in the air: dive down tusks first (guard it standing); lands into the F string
	_move("dive", 0.90, [_hit(0.06, 0.90, 120, 7, 140, 0.45, 8, 6, {"offset": 60.0, "vreach": 170.0, "high": true})],
		{"name_th": "ทิ้งตัวแทงงา", "name_en": "DIVING GORE"})
	# G while blocking a hit (costs COUNTER_COST power): shove the attacker away
	_move("counter", 0.42, [_hit(0.05, 0.15, 96, 4, 480, 0.36, 0, 10, {"offset": 70.0})],
		{"name_th": "ปัดสวน", "name_en": "GUARD COUNTER", "armor": 0.16, "start_sfx": "block"})
	# special moves (motion + F). Like the F string they cancel into the ultimate once they connect.
	# ↓↘→ + F: a ball of water sprayed from the trunk; travels along the ground, jump or block it
	var spout := _move("spout", 0.62, [], {"name_th": "งวงพ่นน้ำ", "name_en": "WATER SPOUT", "event": "spout", "event_at": 0.22,
		"ai_range": 700.0, "start_sfx": "whoosh"})
	spout.wave = _hit(0.0, 0.0, 0, 7, 220, 0.45, 8, 6, {"sound": "hit"})
	# →↓↘ + F: rears up and swats upward. Untouchable as it starts, beats jump-ins, but wide open on a miss.
	_move("uppercut", 0.74, [_hit(0.07, 0.20, 110, 10, 140, 0.6, 12, 10, {"offset": 70.0, "vreach": 240.0, "lift": -560.0})],
		{"name_th": "งวงเสย", "name_en": "TRUNK UPPERCUT", "invuln": 0.13, "cancel_super": true, "ai_range": 200.0})

	# signature moves (G)
	_move("gore", 0.62, [_hit(0.22, 0.34, 96, 11, 340, 0.42, 12, 10, {"lift": -220.0})],
		{"cancel_super": true, "name_th": "แทงงา", "name_en": "TUSK GORE", "desc": "แทงงาหนัก กระเด็นไกล"})
	_move("hook", 0.60, [_hit(0.20, 0.32, 100, 8, 260, 0.55, 12, 8, {"pull": true})],
		{"cancel_super": true, "name_th": "งาเกี่ยว", "name_en": "TUSK HOOK", "desc": "เกี่ยวดึงเข้ามาใกล้ แล้วต่อท่าได้"})
	_move("lunge", 0.55, [_hit(0.12, 0.28, 80, 8, 260, 0.38, 10, 6)],
		{"cancel_super": true, "name_th": "พุ่งแทง", "name_en": "LUNGE", "desc": "พุ่งไปข้างหน้าเร็วพร้อมแทง ระยะไกล",
		"dash_start": 0.08, "dash_stop": 0.26, "dash_speed": 560.0, "ai_range": 330.0})
	_move("headbutt", 0.78, [_hit(0.34, 0.44, 90, 14, 520, 0.5, 12, 16, {"lift": -180.0})],
		{"cancel_super": true, "name_th": "หัวโขก", "name_en": "HEADBUTT", "desc": "ช้า แต่ตอนง้างโดนตีไม่สะดุ้ง กระเด็นไกล", "armor": 0.34})
	_move("sweep", 0.55, [_hit(0.14, 0.26, 140, 8, 200, 0.3, 22, 4, {"offset": 80.0, "sound": "hit"})],
		{"cancel_super": true, "name_th": "งวงหวด", "name_en": "TRUNK SWEEP", "desc": "ฟาดกวาดระยะยาว ได้หลอดพลังเยอะ", "ai_range": 280.0})
	_move("double", 0.80, [_hit(0.18, 0.26, 90, 6, 120, 0.45, 8, 6), _hit(0.40, 0.50, 96, 9, 380, 0.45, 10, 10, {"lift": -200.0})],
		{"cancel_super": true, "name_th": "งาคู่", "name_en": "TWIN GORE", "desc": "แทงงาสองจังหวะติดกัน"})

	# ultimates (H, full power bar)
	var u := {"ultimate": true}
	_move("charge3", 1.05, [
			_hit(0.10, 0.46, 90, 12, 150, 0.8, 0, 10),
			_hit(0.56, 0.64, 110, 8, 150, 0.6, 0, 8, {"lift": -100.0}),
			_hit(0.74, 0.82, 120, 9, 520, 0.7, 0, 12, unblockable.merged({"lift": -300.0, "sound": "heavy"})),
		], u.merged({"name_th": "พุ่งชนสามจังหวะ", "name_en": "TRIPLE CHARGE", "desc": "พุ่งชน ต่องา แล้วโขกปิดท้ายอัตโนมัติ",
		"dash_start": 0.10, "dash_stop": 0.46, "dash_speed": 640.0, "dash_until_hit": true, "ai_range": 400.0, "start_sfx": "trumpet"}))
	var spin := unblockable.merged({"offset": 70.0, "sound": "hit"})
	_move("storm", 1.10, [
			_hit(0.25, 0.33, 150, 6, 40, 0.5, 0, 16, spin),
			_hit(0.48, 0.56, 150, 6, 40, 0.5, 0, 16, spin),
			_hit(0.71, 0.80, 150, 7, 420, 0.6, 0, 18, spin.merged({"lift": -200.0})),
		], u.merged({"name_th": "งวงพายุ", "name_en": "TRUNK STORM", "desc": "สะบัดงวงหมุนฟาด 3 ครั้ง ตีหลอดทรงตัวหนัก",
		"ai_range": 300.0, "start_sfx": "trumpet"}))
	_move("blink", 0.90, [_hit(0.30, 0.40, 96, 20, 480, 0.7, 0, 18, {"lift": -260.0, "overhead": true})],
		u.merged({"name_th": "ฝีเท้าสายฟ้า", "name_en": "LIGHTNING STEP", "desc": "พุ่งทะลุไปข้างหลังแล้วแทง ป้องกันไม่ได้",
		"event": "teleport", "event_at": 0.18, "ai_range": 500.0, "start_sfx": "blink"}))
	var quake := _move("quake", 1.20, [],
		u.merged({"name_th": "กระทืบธรณี", "name_en": "EARTHQUAKE", "desc": "ยืนสองขาแล้วกระทืบ คลื่นวิ่งไปตามพื้น ต้องกระโดดหลบ",
		"armor": 0.5, "event": "wave", "event_at": 0.5, "ai_range": 650.0, "start_sfx": "trumpet"}))
	quake.wave = _hit(0.0, 0.0, 0, 18, 380, 0.8, 0, 20, {"lift": -320.0, "overhead": true})
	_move("blessing", 0.90, [_hit(0.35, 0.45, 120, 2, 380, 0.3, 0, 0, {"offset": 40.0, "overhead": true, "sound": "hit"})],
		u.merged({"name_th": "บารมีช้างเผือก", "name_en": "WHITE BLESSING", "desc": "ฟื้นเลือดและทรงตัว แล้วแรงขึ้น 6 วินาที",
		"event": "bless", "event_at": 0.35, "start_sfx": "bless"}))
	_move("roar", 1.00, [_hit(0.30, 0.55, 260, 4, 220, 0.6, 0, 0, {"offset": 60.0, "vreach": 220.0, "overhead": true, "daze": true, "sound": "hit"})],
		u.merged({"name_th": "คชสารคำราม", "name_en": "ROYAL ROAR", "desc": "คำรามให้อีกฝ่ายเสียหลักทันที",
		"ai_range": 330.0, "start_sfx": "roar"}))


## Balance: hits drain it; empty, the elephant reels (dazed) and is open to a decisive strike
const BALANCE_REGEN := 10.0     ## per second, after BALANCE_DELAY without hits
const BALANCE_DELAY := 1.2
const DAZE_TIME := 1.4          ## off-balance duration
const BREAK_STUN := 1.0         ## the elephant reels this long when its balance breaks
const FINISHER_DMG := 30.0

## Combos
const DASH_TIME := 0.24         ## double-tap forward
const DASH_SPEED := 560.0
const BACKSTEP_TIME := 0.2      ## double-tap back
const BACKSTEP_SPEED := 470.0
const DOUBLE_TAP := 0.25        ## max gap between the two taps
const COUNTER_COST := 25.0      ## power spent on a guard counter
const JUGGLE_MAX := 3           ## air hits that still knock the target back up
const COMBO_SHOW := 1.1         ## the hit counter lingers this long after the last hit
const WHIFF_LAG := 0.14         ## extra recovery after an attack that touched nothing
const F_COOLDOWN := 0.15        ## F can't start a new string this long after the trunk slam (3rd F) ends

## Street-fighter style extras
const MOTION_WINDOW := 0.4      ## a motion (↓↘→ / →↓↘) must be finished this long before the button
const EX_COST := 50.0           ## G + H together: power for an EX signature move
const EX_WINDOW := 0.06         ## G and H count as "together" when pressed this close
const EX_POWER := 1.4           ## EX damage
const COUNTER_DMG := 1.2        ## hitting an opponent in the middle of an attack
const COUNTER_STUN := 0.18      ## extra stun on a counter hit, enough to link another move
const SPOUT_SPEED := 430.0
const SPOUT_RANGE := 720.0
const SPOUT_HEIGHT := 100.0     ## above the ground; jumping elephants clear it
const SUPER_FREEZE := 0.85      ## the world stops while the ultimate's cut-in plays
const EX_FREEZE := 0.2

## Damage of the n-th hit in a combo (1-based): full for two hits, then 10% less per hit, at least 45%.
static func combo_scale(n: int) -> float:
	return clampf(1.0 - 0.1 * (n - 2), 0.45, 1.0)

## Hit stun of the n-th hit: shrinks after the 4th so loops (string -> hook -> string) run out at ~9 hits.
static func combo_stun(n: int) -> float:
	return clampf(1.0 - 0.08 * (n - 4), 0.4, 1.0)

## Ultimates
const WAVE_SPEED := 520.0       ## earthquake shockwave
const WAVE_RANGE := 640.0
const BLESS_HEAL := 21.0
const BUFF_TIME := 6.0
const BUFF_POWER := 1.25


# Archivo for Latin text with IBM Plex Sans Thai as the Thai fallback, like the web version.
static var _fonts := {}

static func font(weight: int, spacing := 0) -> Font:
	var key := weight * 100 + spacing
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Archivo-Variable.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing
	var thai: Font = load("res://assets/fonts/IBMPlexSansThai-Bold.ttf" if weight >= 700 else "res://assets/fonts/IBMPlexSansThai-SemiBold.ttf")
	fv.fallbacks = [thai]
	_fonts[key] = fv
	return fv


## 12345 -> "12,345"
static func fmt_num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
