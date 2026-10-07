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
var training: Training    ## set in training mode: lesson card, damage and input log
var cam_x := 0.0          ## slides the fight aside on the title screen and the result screens
var frozen := false       ## true while paused: animation holds its pose
var _pan := 0.0           ## gentle follow of the fighters during a fight (parallax)
var _rigs := {}           ## Fighter -> ElephantRig
var _backdrop: Backdrop   ## child node drawn behind the arena's own drawing
var _backdrop_duel: Duel
var _time := 0.0
var _shake := Vector2.ZERO
var _zoom := 1.0          ## camera push-in for ultimates (1 = whole arena)
var _focus := Vector2(W / 2.0, H / 2.0)   ## screen point the zoom is centred on
var _cut := 0.0           ## how far the ultimate's dark overlay and cut-in are faded in


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
	var adt := minf(delta, 0.05) * GameData.GAME_SPEED
	if frozen or duel.hitstop > 0.0:
		adt = 0.0
	elif duel.phase == "ko" and duel.t < 0.8:
		adt *= 0.35
	_sync_rigs()
	for f in duel.fighters:
		# during a super freeze only the one doing the move keeps moving (into its pose)
		var still := duel.super_t > 0.0 and f != duel.super_f
		(_rigs[f] as ElephantRig).update(f, duel.phase, 0.0 if still else adt)
	_shake = Vector2((randf() - 0.5) * duel.shake * 2.0, (randf() - 0.5) * duel.shake * 2.0)
	if not frozen:
		_update_camera(minf(delta, 0.05))
	_sync_backdrop()
	_backdrop.update(view_x(), _time, _shake)
	_backdrop.transform = _cam()
	_backdrop.show_front(training == null)
	queue_redraw()


## Ultimate camera: push in hard on the elephant during the freeze, then follow the move a little
## closer than usual, and ease back out when it's over.
func _update_camera(dt: float) -> void:
	var zt := 1.0
	var ft := _focus
	var f := duel.super_f
	var ult := f != null and not duel.super_ex and duel.mode != "demo"
	if ult and duel.super_t > 0.0:
		zt = 1.55
		ft = Vector2(f.x + view_x() + f.face * 40.0, f.y - 125.0)
	elif ult and f.atk == f.def.ultimate and not f.ko:
		var mid := (duel.fighters[0].x + duel.fighters[1].x) / 2.0
		zt = 1.2
		ft = Vector2(mid + view_x(), G - 150.0)
	else:
		ft = Vector2(W / 2.0, G - 150.0)
	ft = Vector2(clampf(ft.x, W * 0.22, W * 0.78), clampf(ft.y, H * 0.3, H * 0.75))
	_zoom += (zt - _zoom) * minf(1.0, dt * (9.0 if zt > _zoom else 3.5))
	_focus += (ft - _focus) * minf(1.0, dt * 8.0)
	# the cut-in clears just before the world starts moving again
	var cut_t := 1.0 if ult and duel.super_t > 0.12 else 0.0
	_cut = move_toward(_cut, cut_t, dt * (7.0 if cut_t > _cut else 8.0))


## Screen transform of the camera zoom (the HUD is drawn without it).
func _cam() -> Transform2D:
	return Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _focus * (1.0 - _zoom))


## World offset of the camera: everything on the ground moves by this, far layers by less.
func view_x() -> float:
	return cam_x - _pan


func _draw() -> void:
	if duel == null:
		return
	_sync_rigs()
	_sync_backdrop()
	var world := _cam() * Transform2D(0.0, _shake + Vector2(view_x(), 0.0))
	if _cut > 0.0:
		_draw_super_bg()
	for f in duel.fighters:
		(_rigs[f] as ElephantRig).draw_dust(self, world)
	# the elephant doing an ultimate is drawn in front
	var order := duel.fighters.duplicate()
	if duel.super_f and duel.super_f == order[0]:
		order.reverse()
	for f in order:
		(_rigs[f] as ElephantRig).draw(self, f, world)
	draw_set_transform_matrix(world)
	for w in duel.waves:
		_draw_wave(w)
	for s in duel.spouts:
		_draw_spout(s)
	for p in duel.parts:
		draw_rect(Rect2(p.x - p.size / 2.0, p.y - p.size / 2.0, p.size, p.size), Color(p.color, minf(1.0, p.life * 3.0)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if duel.white > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, minf(0.85, duel.white * 3.0)))
	if duel.mode != "demo":
		_draw_hud()
		_draw_callouts()
		if training:
			_draw_training()
		else:
			_draw_announce()
		if duel.mode == "online" and duel.net_wait > 0.3:
			_otext("รอสัญญาณคู่ต่อสู้… · WAITING FOR OPPONENT", W / 2.0, 200.0, 16, 800, Color.WHITE, CENTER, 6)
		if _cut > 0.0 and duel.super_f:
			_draw_cut_in(duel.super_f)


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
	elif duel.mode == "online":
		scene = Backdrop.SCENES[duel.stage % Backdrop.SCENES.size()]   # both players see the same field
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
		_combo(f, rev)
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
	if f.meter >= GameData.EX_COST and not full:
		label = "พลัง · EX พร้อม"
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


## Hit counter under the bars while a combo is going; it pops on every new hit.
func _combo(f: Fighter, rev: bool) -> void:
	if f.combo < 2 or f.combo_t <= 0.0:
		return
	var a := clampf(f.combo_t * 3.0, 0.0, 1.0)
	var pop := 1.0 + maxf(0.0, f.combo_t - (GameData.COMBO_SHOW - 0.12)) * 3.0
	var align := RIGHT if rev else LEFT
	var sx := -1.0 if rev else 1.0
	var x := W - 40.0 if rev else 40.0
	var w := _otext(str(f.combo), x, 176.0, int(46.0 * pop), 800, Color(GOLD_LIGHT, a), align, 8, Color(GameData.ACC_700, a))
	_otext("HITS", x + sx * (w + 8.0), 156.0, 17, 800, Color(1, 1, 1, a), align, 4, Color(INK, a))
	_otext("คอมโบ!", x + sx * (w + 8.0), 175.0, 14, 800, Color(GOLD, a), align, 4, Color(INK, a))


## Training overlay: input log on the left, combo damage on the right, the lesson card at the bottom.
func _draw_training() -> void:
	var tr := training
	_otext("ปุ่มที่กด · INPUT", 24.0, 212.0, 11, 800, GOLD_LIGHT, LEFT, 4)
	for i in tr.inputs.size():
		var s: String = tr.inputs[tr.inputs.size() - 1 - i]
		_otext(s, 24.0, 236.0 + i * 21.0, 17 if i == 0 else 15, 800, Color(1, 1, 1, 1.0 - i * 0.09), LEFT, 4)
	var rx := W - 24.0
	_otext("ดาเมจคอมโบ · COMBO DAMAGE", rx, 212.0, 11, 800, GOLD_LIGHT, RIGHT, 4)
	var hits := "  ·  %d HITS" % tr.combo_hits if tr.combo_hits > 1 else ""
	_otext("%d%s" % [roundi(tr.combo_dmg), hits], rx, 240.0, 24, 800, Color.WHITE, RIGHT, 5)
	_otext("สูงสุด · BEST  %d" % roundi(tr.best_dmg), rx, 260.0, 11, 800, Color.WHITE, RIGHT, 4)

	var x0 := 150.0
	var x1 := W - 150.0
	var y0 := 452.0
	if tr.lesson < 0:
		var msg := "เรียนครบทุกบทแล้ว! · " if tr.finished_all else ""
		_panel(x0, y0 + 30.0, x1, H - 10.0)
		_otext("%sฝึกอิสระ · FREE PRACTICE  —  หุ่น: %s" % [msg, Training.DUMMY_NAMES[tr.dummy]], W / 2.0, y0 + 53.0, 13, 800, GOLD_LIGHT, CENTER, 0)
		_otext("ESC = เปลี่ยนท่าหุ่น · กลับไปเรียน · พลังเต็มตลอด", W / 2.0, y0 + 70.0, 10, 600, Color.WHITE, CENTER, 0)
		return
	var L: Array = Training.LESSONS[tr.lesson]
	_panel(x0, y0, x1, H - 10.0)
	_otext("บทที่ %d/%d" % [tr.lesson + 1, Training.LESSONS.size()], x0 + 14.0, y0 + 22.0, 11, 800, GOLD, LEFT, 0)
	_otext(L[0], x0 + 84.0, y0 + 23.0, 17, 800, GOLD_LIGHT, LEFT, 0)
	_otext(L[3], x1 - 14.0, y0 + 26.0, 20, 800, Color.WHITE, RIGHT, 4, Color(GameData.ACC_700, 0.9))
	_otext(L[1], x0 + 14.0, y0 + 48.0, 13, 600, Color.WHITE, LEFT, 0)
	_otext(L[2], x0 + 14.0, y0 + 66.0, 10, 600, Color(1, 1, 1, 0.7), LEFT, 0)
	var need := int(L[8])
	for i in need:
		var c := Vector2(x1 - 14.0 - (need - 1 - i) * 18.0, y0 + 46.0)
		DrawKit.fill(self, _diamond(c, 6.0), PackedColorArray([GOLD_LIGHT if i < tr.count else Color(1, 1, 1, 0.25)]))
	_otext("ESC = ข้ามบท · ฝึกอิสระ", x1 - 14.0, y0 + 67.0, 9, 600, Color(1, 1, 1, 0.6), RIGHT, 0)
	if tr.done_t >= 0.0:
		_band(tr.done_t, "ผ่าน!", "LESSON CLEAR")


func _panel(x0: float, y0: float, x1: float, y1: float) -> void:
	draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(0.18, 0.04, 0.03, 0.88))
	draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), GOLD, false, 2.0)
	draw_rect(Rect2(x0 + 4.0, y0 + 4.0, x1 - x0 - 8.0, y1 - y0 - 8.0), Color(GOLD_DARK, 0.8), false, 1.0)


## Super freeze backdrop: the scene darkens and speed lines burst from the elephant.
func _draw_super_bg() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.08, 0.02, 0.02, 0.62 * _cut))
	var c := _focus
	for i in 30:
		var a := TAU * i / 30.0 + sin(i * 7.3) * 0.08 + _time * 0.15
		var d := Vector2.from_angle(a)
		var n := d.orthogonal() * (3.0 + fposmod(i * 2.7, 4.0))
		var r0 := 120.0 + fposmod(i * 37.0, 60.0)
		var col := Color(GOLD_LIGHT if i % 3 == 0 else Color.WHITE, 0.32 * _cut)
		DrawKit.fill(self, PackedVector2Array([c + d * r0 + n, c + d * 1100.0, c + d * r0 - n]), PackedColorArray([col, Color(col, 0.0), col]))


## Ultimate cut-in: a lacquer band slides in from the elephant's side with its face and the move's name.
func _draw_cut_in(f: Fighter) -> void:
	var m := GameData.move(f.def.ultimate)
	var rev := f == duel.fighters[1]
	var sx := -1.0 if rev else 1.0
	var k := clampf(_cut * 1.6, 0.0, 1.0)
	var slide := (1.0 - k) * (1.0 - k) * W * 0.6
	var cy := 410.0
	var hh := 50.0
	var x0 := -40.0 - sx * slide
	var band := PackedVector2Array([Vector2(x0, cy - hh), Vector2(x0 + W + 80.0, cy - hh - 30.0), Vector2(x0 + W + 80.0, cy + hh - 30.0), Vector2(x0, cy + hh)])
	if rev:
		for i in band.size():
			band[i] = Vector2(W - band[i].x, band[i].y)
	var a := minf(1.0, _cut * 2.0)
	DrawKit.fill(self, band, PackedColorArray([Color(0.3, 0.03, 0.03, 0.92 * a)]))
	draw_polyline(PackedVector2Array([band[0], band[1]]), Color(GOLD, a), 4.0, true)
	draw_polyline(PackedVector2Array([band[3], band[2]]), Color(GOLD, a), 4.0, true)
	# big portrait medallion at the near end
	var pc := Vector2((150.0 if not rev else W - 150.0) - sx * slide, cy - 8.0)
	var r := 62.0
	DrawKit.circle(self, pc, r + 6.0, Color(GOLD_DARK, a))
	DrawKit.circle(self, pc, r, Color(f.def.cloth.darkened(0.3), a))
	var face := -1.0 if rev else 1.0
	(_rigs[f] as ElephantRig).draw_portrait(self, f, Transform2D(0.0, pc + Vector2(-3.0 * face, 6.0)).scaled_local(Vector2(face * 1.05, 1.05)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_arc(pc, r, 0.0, TAU, 48, Color(GOLD, a), 5.0, true)
	draw_arc(pc, r + 5.0, 0.0, TAU, 48, Color(GOLD_LIGHT, a), 2.0, true)
	var tx := pc.x + sx * (r + 26.0)
	var al := RIGHT if rev else LEFT
	_otext(f.def.display_name, tx, cy - 26.0, 16, 800, Color(1, 1, 1, a), al, 4, Color(0.1, 0.02, 0.02, a))
	_otext(m.name_th + "!", tx + sx * 3.0, cy + 24.0 + 3.0, 50, 800, Color(GameData.ACC_700, 0.9 * a), al, 0)
	_otext(m.name_th + "!", tx, cy + 24.0, 50, 800, Color(GOLD_LIGHT, a), al, 9, Color("#3a0d06", a))
	_otext(m.name_en, tx, cy + 46.0, 15, 800, Color(1, 1, 1, a), al, 4, Color("#3a0d06", a))


## Water spout: a wobbling ball of water with a spray trail.
func _draw_spout(s: Duel.Spout) -> void:
	var p := Vector2(s.x, s.y)
	var wob := sin(s.traveled * 0.08) * 2.0
	for i in 3:
		var tp := p - Vector2(s.dir * (20.0 + i * 16.0), sin(s.traveled * 0.05 + i) * 4.0)
		DrawKit.circle(self, tp, 9.0 - i * 2.5, Color(0.55, 0.85, 1.0, 0.6 - i * 0.15))
	DrawKit.ellipse(self, p, 20.0 + wob, 16.0 - wob, Color("#3fa9e8"))
	DrawKit.ellipse(self, p + Vector2(s.dir * 2.0, -1.0), 15.0 + wob, 11.0 - wob, Color("#8fd8ff"))
	DrawKit.circle(self, p + Vector2(s.dir * 5.0, -6.0), 4.5, Color(1, 1, 1, 0.9))
	draw_arc(p, 21.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 2.0, true)


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
			var x := (_cam() * Vector2(c.x + view_x(), 0.0)).x
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
