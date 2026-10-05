extends Node2D
## Draws the current Duel: painted backdrop, elephants, particles, HUD and round banners.
## Elephants are drawn by one ElephantRig per fighter. Everything is in 960×540 arena space.

const W := GameData.W
const H := GameData.H
const G := GameData.GROUND
const INK := GameData.INK
const ACC := GameData.ACC
const GOLD := GameData.GOLD
const GOLD_LIGHT := GameData.GOLD_LIGHT
const GOLD_DARK := GameData.GOLD_DARK
const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const CENTER := HORIZONTAL_ALIGNMENT_CENTER
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT
const FRAME := Color(0.1, 0.05, 0.03, 0.78)
const HP_HIGH := Color("#5fd43c")
const HP_MID := Color("#f5c518")
const HP_LOW := Color("#ef3b24")
const TRAIL := Color("#ff7a3d")
const POWER := Color("#ff9a1f")
const BALANCE := Color("#3cc6d4")

var duel: Duel
var cam_x := 0.0          ## slides the fight aside on the title screen and the result screens
var frozen := false       ## true while paused: animation holds its pose
var _pan := 0.0           ## gentle follow of the fighters during a fight (parallax)
var _rigs := {}           ## Fighter -> ElephantRig
var _backdrop: Backdrop   ## child node drawn behind the arena's own drawing
var _backdrop_duel: Duel
var _time := 0.0
var _shake := Vector2.ZERO


func _process(delta: float) -> void:
	if duel == null:
		return
	var side := duel.mode == "demo" or duel.phase == "done"
	var mid := (duel.fighters[0].x + duel.fighters[1].x) / 2.0
	var tgt := 700.0 - mid if side else 0.0
	cam_x += (tgt - cam_x) * minf(1.0, delta * (3.0 if duel.mode == "demo" else 4.0))
	var pan_tgt := 0.0 if side else (mid - W / 2.0) * 0.16
	_pan += (pan_tgt - _pan) * minf(1.0, delta * 2.5)
	if not frozen:
		_time += delta
	# animation runs on the same clock as the simulation: frozen in hitstop, slowed after a K.O.
	var adt := minf(delta, 0.05)
	if frozen or duel.hitstop > 0.0:
		adt = 0.0
	elif duel.phase == "ko" and duel.t < 0.8:
		adt *= 0.35
	_sync_rigs()
	for f in duel.fighters:
		(_rigs[f] as ElephantRig).update(f, duel.phase, adt)
	_shake = Vector2((randf() - 0.5) * duel.shake * 2.0, (randf() - 0.5) * duel.shake * 2.0)
	_sync_backdrop()
	_backdrop.update(view_x(), _time, _shake)
	queue_redraw()


## World offset of the camera: everything on the ground moves by this, far layers by less.
func view_x() -> float:
	return cam_x - _pan


func _draw() -> void:
	if duel == null:
		return
	_sync_rigs()
	_sync_backdrop()
	var world := Transform2D(0.0, _shake + Vector2(view_x(), 0.0))
	for f in duel.fighters:
		(_rigs[f] as ElephantRig).draw_dust(self, world)
	for f in duel.fighters:
		(_rigs[f] as ElephantRig).draw(self, f, world)
	draw_set_transform_matrix(world)
	for w in duel.waves:
		_draw_wave(w)
	for p in duel.parts:
		draw_rect(Rect2(p.x - p.size / 2.0, p.y - p.size / 2.0, p.size, p.size), Color(p.color, minf(1.0, p.life * 3.0)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if duel.white > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, minf(0.85, duel.white * 3.0)))
	if duel.mode != "demo":
		_draw_hud()
		_draw_callouts()
		_draw_announce()


## Fighters are recreated every round; give each new one a fresh rig.
func _sync_rigs() -> void:
	if _rigs.has(duel.fighters[0]) and _rigs.has(duel.fighters[1]):
		return
	var rigs := {}
	for f in duel.fighters:
		rigs[f] = _rigs[f] if _rigs.has(f) else ElephantRig.new()
	_rigs = rigs


## Arcade stages go morning -> sunset -> dusk for the boss; other modes pick at random.
func _sync_backdrop() -> void:
	if _backdrop and _backdrop_duel == duel:
		return
	var scene: String
	if duel.mode == "arcade":
		scene = Backdrop.SCENES[mini(duel.stage, Backdrop.SCENES.size() - 1)]
	elif _backdrop and duel.mode == "vs" and _backdrop_duel and _backdrop_duel.mode == "vs":
		scene = _backdrop.scene      # rematches keep the same field
	else:
		scene = Backdrop.SCENES[randi() % Backdrop.SCENES.size()]
	if _backdrop == null or _backdrop.scene != scene:
		if _backdrop:
			_backdrop.queue_free()
		_backdrop = Backdrop.new(scene)
		_backdrop.show_behind_parent = true
		add_child(_backdrop)
	_backdrop_duel = duel


# ---------- HUD ----------

func _draw_hud() -> void:
	for i in 2:
		var f := duel.fighters[i]
		var rev := i == 1
		var sx := -1.0 if rev else 1.0
		var px := W - 52.0 if rev else 52.0
		_bar(W - 94.0 - 336.0 if rev else 94.0, 30.0, 336.0, 24.0, f, rev)
		_portrait(Vector2(px, 50.0), f, rev)
		var nx := W - 104.0 if rev else 104.0
		var nw := _otext(f.def.display_name, nx, 79.0, 18, 800, Color.WHITE, RIGHT if rev else LEFT)
		var ew := _otext(f.def.name_en, nx + sx * (nw + 8.0), 78.0, 10, 800, GOLD_LIGHT, RIGHT if rev else LEFT, 4)
		if f.buff_t > 0.0:
			_otext("บารมี ×1.25", nx + sx * (nw + ew + 18.0), 78.0, 11, 800, GOLD, RIGHT if rev else LEFT)
		for k in duel.rounds_to_win:
			_pip(Vector2(W / 2.0 - sx * (58.0 + k * 18.0), 68.0), duel.wins[i] > k)
		_meter(W - 104.0 - 190.0 if rev else 104.0, 88.0, f, rev)
		_balance(W - 104.0 - 150.0 if rev else 104.0, 104.0, f, rev)
	_timer_badge()


## Health bar: slanted dark frame with a gold rim; green -> yellow -> red as it drains.
func _bar(x: float, y: float, w: float, h: float, f: Fighter, rev: bool) -> void:
	var sl := 10.0
	DrawKit.fill(self, _slant(x - 3, y - 3, w + 6, h + 6, sl, rev), PackedColorArray([FRAME]))
	var r := f.hp / f.max_hp
	var tr := maxf(r, f.trail / f.max_hp)
	if tr > 0.0:
		_fill_slant(x, y, w, h, sl, rev, tr, TRAIL, TRAIL.darkened(0.3))
	if r > 0.0:
		var c := HP_HIGH if r > 0.5 else (HP_MID.lerp(HP_HIGH, (r - 0.25) / 0.25) if r > 0.25 else HP_LOW.lerp(HP_MID, r / 0.25))
		if r <= 0.25 and int(Time.get_ticks_msec() / 200.0) % 2 == 0:
			c = c.lightened(0.25)
		_fill_slant(x, y, w, h, sl, rev, r, c.lightened(0.25), c.darkened(0.25))
		# gloss
		_fill_slant(x, y + 3, w, h * 0.28, sl * 0.28, rev, r, Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.12))
	var rim := _slant(x - 3, y - 3, w + 6, h + 6, sl, rev)
	rim.append(rim[0])
	draw_polyline(rim, GOLD, 2.0, true)


## Parallelogram; the slanted edge is on the side away from the portrait.
func _slant(x: float, y: float, w: float, h: float, sl: float, rev: bool) -> PackedVector2Array:
	if rev:
		return PackedVector2Array([Vector2(x + sl, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])
	return PackedVector2Array([Vector2(x, y), Vector2(x + w - sl, y), Vector2(x + w, y + h), Vector2(x, y + h)])


## Fraction `k` of a slanted bar, anchored at the portrait end, with a vertical gradient.
func _fill_slant(x: float, y: float, w: float, h: float, sl: float, rev: bool, k: float, top: Color, bot: Color) -> void:
	var fw := w * k
	var pts: PackedVector2Array
	if rev:
		var x0 := x + w - fw
		pts = PackedVector2Array([Vector2(x0 + sl * k, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x0, y + h)])
	else:
		pts = PackedVector2Array([Vector2(x, y), Vector2(x + fw - sl * k, y), Vector2(x + fw, y + h), Vector2(x, y + h)])
	DrawKit.fill(self, pts, PackedColorArray([top, top, bot, bot]))


## Round medallion with the elephant's face, ringed in gold.
func _portrait(c: Vector2, f: Fighter, rev: bool) -> void:
	var r := 38.0
	DrawKit.circle(self, c, r + 4.0, GOLD_DARK)
	var bg := f.def.cloth
	for i in 6:
		DrawKit.circle(self, c + Vector2(0, -i * 2.0), r - i * 4.0, bg.darkened(0.45 - i * 0.07))
	var face := -1.0 if rev else 1.0
	var xf := Transform2D(0.0, c + Vector2(-2.0 * face, 4.0)).scaled_local(Vector2(face * 0.64, 0.64))
	(_rigs[f] as ElephantRig).draw_portrait(self, f, xf)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_arc(c, r, 0.0, TAU, 48, GOLD, 4.0, true)
	draw_arc(c, r + 3.0, 0.0, TAU, 48, GOLD_DARK, 2.0, true)
	draw_arc(c, r - 2.5, 0.0, TAU, 48, GOLD_LIGHT, 1.2, true)
	if f.dazed > 0.0 and int(Time.get_ticks_msec() / 120.0) % 2 == 0:
		draw_arc(c, r + 1.0, 0.0, TAU, 48, ACC, 3.0, true)


func _timer_badge() -> void:
	var c := Vector2(W / 2.0, 46.0)
	DrawKit.circle(self, c, 37.0, GOLD_DARK)
	DrawKit.circle(self, c, 34.0, GOLD)
	for i in 4:
		DrawKit.circle(self, c + Vector2(0, -i * 1.5), 28.0 - i * 3.0, GameData.ACC_700.lightened(i * 0.06))
	draw_arc(c, 34.0, 0.0, TAU, 48, GOLD_LIGHT, 1.5, true)
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * 35.5
		DrawKit.fill(self, _diamond(c + d, 3.0), PackedColorArray([GOLD_LIGHT]))
	var low := duel.timer < 10 and duel.phase == "fight"
	_otext(str(ceili(duel.timer)), c.x, c.y + 12.0, 32, 800, GOLD_LIGHT if not low else Color.WHITE, CENTER, 6)
	if duel.mode == "arcade":
		_otext("SCORE " + GameData.fmt_num(duel.run_score), c.x, 128.0, 13, 800, Color.WHITE, CENTER, 4)


func _pip(c: Vector2, on: bool) -> void:
	DrawKit.fill(self, _diamond(c, 7.5), PackedColorArray([GOLD_DARK]))
	DrawKit.fill(self, _diamond(c, 5.5), PackedColorArray([GOLD_LIGHT if on else FRAME]))


func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


func _meter(x: float, y: float, f: Fighter, rev: bool) -> void:
	var mw := 190.0
	var full := f.meter >= 100.0
	DrawKit.fill(self, _slant(x - 2, y - 2, mw + 4, 13, 6.0, rev), PackedColorArray([FRAME]))
	var k := f.meter / 100.0
	if k > 0.0:
		var top := GOLD_LIGHT if full else POWER.lightened(0.3)
		var bot := GOLD if full else POWER.darkened(0.2)
		if full and int(Time.get_ticks_msec() / 140.0) % 2 == 0:
			top = Color.WHITE
		_fill_slant(x, y, mw, 9, 4.0, rev, k, top, bot)
	for i in range(1, 4):
		var tx := x + mw * i / 4.0
		draw_line(Vector2(tx, y), Vector2(tx, y + 9), Color(0, 0, 0, 0.35), 1.0)
	var label := "พลัง · POWER"
	if full:
		label = GameData.move(f.def.ultimate).name_th + " พร้อม!"
	_otext(label, x - 10.0 if rev else x + mw + 10.0, y + 10.0, 11, 800, GOLD_LIGHT if full else Color.WHITE, RIGHT if rev else LEFT, 4)


## Rider balance: drains when hit, at zero the rider is dazed and open to a decisive strike.
func _balance(x: float, y: float, f: Fighter, rev: bool) -> void:
	var mw := 150.0
	var dazed := f.dazed > 0.0
	var k := f.dazed / GameData.DAZE_TIME if dazed else f.balance / 100.0
	var on := not dazed or int(Time.get_ticks_msec() / 120.0) % 2 == 0
	DrawKit.fill(self, _slant(x - 2, y - 2, mw + 4, 9, 4.0, rev), PackedColorArray([FRAME]))
	if k > 0.0:
		var c := ACC if dazed and on else BALANCE
		_fill_slant(x, y, mw, 5, 2.0, rev, k, c.lightened(0.25), c.darkened(0.15))
	var label := ("มึน! · STUNNED" if f.stun > 0.0 else "เสียหลัก! · OFF BALANCE") if dazed else "ทรงตัว · BALANCE"
	_otext(label, x - 10.0 if rev else x + mw + 10.0, y + 7.0, 10, 800, Color("#ff6a50") if dazed else Color.WHITE, RIGHT if rev else LEFT, 4)


## Earthquake shockwave: jagged earth spikes bursting out of the ground as it travels.
func _draw_wave(w: Duel.Wave) -> void:
	var earth := _backdrop.col("ground_bot").darkened(0.2)
	for i in 4:
		var x := w.x - w.dir * i * 24.0
		var hgt := (44.0 - i * 10.0) * (0.85 + 0.15 * sin(w.traveled * 0.08 + i))
		var pts := PackedVector2Array([Vector2(x - 12, G + 4), Vector2(x - w.dir * 4.0, G - hgt), Vector2(x + 12, G + 4)])
		DrawKit.fill(self, pts, PackedColorArray([earth, _backdrop.col("ground_top"), earth]))
	draw_line(Vector2(w.x - w.dir * w.traveled, G + 3), Vector2(w.x, G + 3), Color(INK, 0.45), 2.0)


func _draw_callouts() -> void:
	for c in duel.callouts:
		if c.big:
			_band(c.t, c.th, c.en)
		else:
			var a := clampf((1.3 - c.t) * 4.0, 0.0, 1.0)
			var x := c.x + view_x()
			var y := 178.0 - minf(c.t, 0.3) * 40.0
			_otext(c.th, x, y, 28, 800, Color(GOLD_LIGHT, a), CENTER, 8, Color(GameData.ACC_700, a))
			_otext(c.en, x, y + 18, 12, 800, Color(1, 1, 1, a), CENTER, 4, Color(INK, a))


func _draw_announce() -> void:
	var t := duel.t
	if duel.phase == "intro":
		var r := duel.rounds_to_win
		var fin := r > 1 and duel.wins[0] == r - 1 and duel.wins[1] == r - 1
		if t < 1.0:
			_band(t, "ยกตัดสิน" if fin else "ยกที่ %d" % duel.round_no, "FINAL ROUND" if fin else "ROUND %d" % duel.round_no)
		else:
			_band(t - 1.0, "สู้!", "FIGHT")
	elif duel.phase == "ko" and t > 0.15:
		var ko := duel.reason == "ko"
		if t < 1.4:
			_band(t - 0.15, "น็อก!" if ko else "หมดเวลา", "K.O." if ko else "TIME UP")
		elif duel.round_winner >= 0:
			var w := duel.fighters[duel.round_winner].def
			_band(t - 1.4, w.display_name + " ชนะ", w.name_en + " WINS THE ROUND")
		else:
			_band(t - 1.4, "เสมอ", "DRAW")


## Banner across the middle: dark lacquer band with gold rules, the words in gold.
func _band(lt: float, th: String, en: String) -> void:
	var k := minf(1.0, lt * 6.0)
	var hh := 58.0 * k
	var cy := 262.0
	draw_rect(Rect2(0, cy - hh, W, hh * 2.0), Color(0.16, 0.03, 0.03, 0.82))
	draw_rect(Rect2(0, cy - hh - 4.0, W, 3.0), GOLD)
	draw_rect(Rect2(0, cy + hh + 1.0, W, 3.0), GOLD)
	if k < 1.0:
		return
	for i in 24:
		var x := 20.0 + i * 40.0
		DrawKit.fill(self, _diamond(Vector2(x, cy - hh - 2.5), 4.0), PackedColorArray([GOLD_LIGHT]))
		DrawKit.fill(self, _diamond(Vector2(x, cy + hh + 2.5), 4.0), PackedColorArray([GOLD_LIGHT]))
	var pop := 1.0 + maxf(0.0, 0.25 - (lt - 1.0 / 6.0)) * 1.2
	var size := int(62.0 * pop)
	_otext(th, W / 2.0 + 3.0, cy + 17.0 + 3.0, size, 800, Color(GameData.ACC_700, 0.9), CENTER, 0)
	_otext(th, W / 2.0, cy + 17.0, size, 800, GOLD_LIGHT, CENTER, 10, Color("#3a0d06"))
	_otext(en, W / 2.0, cy + 46.0, 18, 800, Color.WHITE, CENTER, 5, Color("#3a0d06"))


# ---------- helpers ----------

## Text on its baseline with a dark outline (readable on any part of the scene); returns its width.
func _otext(s: String, x: float, y: float, size: int, weight: int, color: Color, align := LEFT, outline := 5, outline_color := Color(0.1, 0.04, 0.02, 0.92)) -> float:
	var font := GameData.font(weight)
	var w := font.get_string_size(s, LEFT, -1, size).x
	if align == CENTER:
		x -= w / 2.0
	elif align == RIGHT:
		x -= w
	if outline > 0:
		draw_string_outline(font, Vector2(x, y), s, LEFT, -1, size, outline, outline_color)
	draw_string(font, Vector2(x, y), s, LEFT, -1, size, color)
	return w
