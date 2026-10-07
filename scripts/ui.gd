class_name GameUI
extends Control
## Menu screens over the arena: title, elephant select, how-to, pause, stage clear,
## game over, versus result.
## Every button emits `action_pressed` with its action name; Main decides what happens.

signal action_pressed(action: String)

const INK := GameData.INK
const BG := GameData.BG
const ACC := GameData.ACC
const ACC_700 := GameData.ACC_700
const MUTED_INK := GameData.NEUTRAL_700
const DIVIDER := GameData.DIVIDER
const STRIP := 12.0
## Select-screen stat bars: [Thai, English, ElephantDef property, value shown empty, value shown full]
const STAT_ROWS := [
	["พลังชีวิต", "HP", "hp", 80.0, 130.0],
	["พลังโจมตี", "POWER", "power", 0.85, 1.2],
	["ความเร็ว", "SPEED", "speed", 0.8, 1.25],
	["ทำลายสมดุล", "BREAK", "rider_skill", 0.85, 1.35],
	["ความมั่นคง", "STEADY", "steady", 0.85, 1.4],
	["ชาร์จ", "CHARGE", "charge", 0.85, 1.45],
]

var _screens := {}        ## screen name -> Control
var _first := {}          ## screen name -> Button focused when shown
var _dyn := {}            ## name -> Control whose text/visibility changes
var _sound_buttons: Array[Button] = []
var _roster: Array[ElephantDef] = []
var _locked: Array[bool] = []
var _card_row: HBoxContainer
var _cards: Array[PanelContainer] = []
var _details: Array[Dictionary] = []
var _shown_ms := 0


func _ready() -> void:
	theme = _make_theme()
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_title()
	_build_select()
	_build_howto()
	_build_combos()
	_build_online()
	_build_pause()
	_build_stage_clear()
	_build_game_over()
	_build_vs_result()
	show_screen("title")


# ---------- public ----------

## "fight" (or any unknown name) hides every panel.
func show_screen(screen: String) -> void:
	for k in _screens:
		(_screens[k] as Control).visible = k == screen
	if _first.has(screen):
		(_first[screen] as Button).grab_focus.call_deferred()
	_shown_ms = Time.get_ticks_msec()


## Menus also answer the fighting keys: F / , confirm and W / S move, not just Enter and arrows.
func _unhandled_input(event: InputEvent) -> void:
	var b := get_viewport().gui_get_focus_owner() as Button
	if b == null or not b.is_visible_in_tree():
		return
	if event.is_action_pressed("p1_confirm") or event.is_action_pressed("p2_confirm"):
		# a player still mashing attack as a result screen appears shouldn't skip it
		if Time.get_ticks_msec() - _shown_ms > 600:
			b.pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("p1_up") or event.is_action_pressed("p1_down"):
		var to := b.find_prev_valid_focus() if event.is_action_pressed("p1_up") else b.find_next_valid_focus()
		if to:
			to.grab_focus()
		get_viewport().set_input_as_handled()


func set_hiscore(n: int) -> void:
	_set_text("title_hi", GameData.fmt_num(n))


func set_muted(muted: bool) -> void:
	for b in _sound_buttons:
		b.text = "ปิดเสียง · MUTED  [M]" if muted else "เสียง · SOUND ON  [M]"


func set_rules(rounds_to_win: int, round_time: int, stages: int) -> void:
	_set_text("rule1_th", "ชนะ %d ยกก่อน ยกละ %d วินาที หมดเวลาใครเลือดมากกว่าชนะ" % [rounds_to_win, round_time])
	_set_text("rule1_en", "First to %d rounds. %d s per round; on time-out more health wins." % [rounds_to_win, round_time])
	_set_text("rule4_th", "อาร์เคด: ล้มช้างศึก %d เชือก ชนะไวและไม่เสียเลือดได้โบนัส" % stages)
	_set_text("rule4_en", "Arcade: beat %d war elephants. Fast and perfect wins earn bonus points." % stages)
	_set_text("arcade_en", "1 PLAYER · ARCADE — %d STAGES" % stages)


func show_stage_clear(stage: int, stages: int, score: int, next: ElephantDef) -> void:
	_set_text("stage_kicker", "ด่าน %d / %d · STAGE %d OF %d" % [stage + 1, stages, stage + 1, stages])
	_set_text("stage_score", GameData.fmt_num(score))
	_set_text("next_th", next.display_name)
	_set_text("next_en", next.name_en)
	show_screen("stageclear")


func show_game_over(cleared: bool, stages_cleared: int, stages: int, score: int, best: int, new_hi: bool, unlocked: bool) -> void:
	(_dyn["unlocked"] as Control).visible = unlocked
	_set_text("over_kicker", "จบเกม · GAME OVER · ผ่าน %d/%d ด่าน" % [stages_cleared, stages])
	_set_text("over_th", "แชมป์ยุทธหัตถี" if cleared else "พ่ายแพ้")
	_set_text("over_en", "CHAMPION" if cleared else "DEFEATED")
	_set_text("over_score", GameData.fmt_num(score))
	_set_text("over_best", GameData.fmt_num(best))
	(_dyn["new_hi"] as Control).visible = new_hi
	set_share_msg("")
	show_screen("gameover")


## `me` is this player's side in an online match (-1 offline).
func show_vs_result(winner: int, wins: Array[int], def: ElephantDef, me := -1) -> void:
	_set_text("vs_th", ("คุณชนะ!" if winner == me else "คุณแพ้") if me >= 0 else "ผู้เล่น %d ชนะ" % (winner + 1))
	_set_text("vs_en", ("YOU WIN" if winner == me else "YOU LOSE") if me >= 0 else "PLAYER %d WINS" % (winner + 1))
	_set_text("vs_score", "%d – %d" % [wins[0], wins[1]])
	_set_text("vs_name", def.display_name + " · " + def.name_en)
	set_share_msg("")
	show_screen("vsresult")


## Builds the select-screen cards. Call again when an elephant gets unlocked.
func setup_roster(roster: Array[ElephantDef], locked: Array[bool]) -> void:
	_roster = roster
	_locked = locked
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in roster.size():
		var card := _card(i)
		_card_row.add_child(card)
		_cards.append(card)


func update_select(mode: String, cursors: Array[int], confirmed: Array[bool]) -> void:
	var two := mode == "vs"
	var kicker := "เล่นคนเดียว · อาร์เคด · ARCADE"
	match mode:
		"vs": kicker = "สองคน · ประลอง · VERSUS"
		"training": kicker = "ฝึกซ้อม · เลือกช้างที่จะฝึก · TRAINING"
		"online": kicker = "ออนไลน์ · รอคู่ต่อสู้เลือกช้าง… · WAITING FOR OPPONENT" if confirmed[0] else "ออนไลน์ · เลือกช้างของคุณ · PICK YOUR ELEPHANT"
	_set_text("select_kicker", kicker)
	(_dyn["select_vrule"] as Control).visible = two
	for i in _cards.size():
		var on1 := cursors[0] == i
		var on2 := two and cursors[1] == i
		var sb := _flat(BG)
		sb.set_border_width_all(3 if on1 or on2 else 2)
		sb.border_color = ACC if on1 else (INK if on2 else DIVIDER)
		_cards[i].add_theme_stylebox_override("panel", sb)
		(_cards[i].get_meta("tag1") as Control).visible = on1
		(_cards[i].get_meta("tag2") as Control).visible = on2
		(_cards[i].get_meta("preview") as ElephantPreview).happy = (on1 and confirmed[0]) or (on2 and confirmed[1])
	for p in 2:
		var d := _details[p]
		(d["root"] as Control).visible = p == 0 or two
		(d["pad"] as Control).visible = p == 0 and not two
		var i := cursors[p]
		var locked := _locked[i]
		var def := _roster[i]
		var prev: ElephantPreview = d["preview"]
		if prev.get_meta("index", -1) != i:
			prev.set_meta("index", i)
			prev.def = _silhouette(def) if locked else def
		prev.face = 1 if p == 0 else -1
		prev.happy = confirmed[p]
		(d["name"] as Label).text = "???" if locked else def.display_name
		var sig := GameData.move(def.signature)
		var ult := GameData.move(def.ultimate)
		(d["name_en"] as Label).text = "LOCKED" if locked else "G %s · H %s" % [sig.name_th, ult.name_th]
		var ml: Array = d["moves"]
		for k in 2:
			var mv := sig if k == 0 else ult
			(ml[k][0] as Label).text = "???" if locked else mv.name_th + "  " + mv.name_en
			(ml[k][1] as Label).text = "" if locked else mv.desc
		(d["tagline"] as Label).text = "ชนะอาร์เคดเพื่อปลดล็อก · CLEAR ARCADE" if locked else def.tagline + " · " + def.tagline_en
		var bars: Array = d["bars"]
		for r in STAT_ROWS.size():
			var row: Array = STAT_ROWS[r]
			var v := 0.0 if locked else clampf(remap(float(def.get(row[2])), row[3], row[4], 0.12, 1.0), 0.05, 1.0)
			(bars[r] as Control).set_meta("v", v)
			(bars[r] as Control).queue_redraw()
		var status: Label = d["status"]
		if confirmed[p]:
			status.text = "พร้อม! · READY"
			status.add_theme_color_override("font_color", ACC)
		else:
			status.text = "A / D เลือก · F ยืนยัน · G กลับ" if p == 0 else "← / → เลือก · , ยืนยัน · . ยกเลิก"
			status.add_theme_color_override("font_color", MUTED_INK)


func set_share_msg(msg: String) -> void:
	for k in ["over_share", "vs_share"]:
		_set_text(k, msg)
		(_dyn[k] as Control).visible = msg != ""


# ---------- screens ----------

func _build_title() -> void:
	var v := _side_panel("title")
	v.add_child(_label("เกมต่อสู้ช้างศึก · WAR ELEPHANT FIGHTING", 11, 600, ACC_700, 1))
	v.add_child(_label("ยุทธหัตถี", 67, 800))
	v.add_child(_label("ELEPHANT DUEL", 19, 800))
	v.add_child(_spacer())
	var arcade := _button("เล่นคนเดียว · อาร์เคด", "1 PLAYER · ARCADE — 3 STAGES", "PrimaryButton", "arcade", "01")
	_dyn["arcade_en"] = arcade.get_meta("en")
	_first["title"] = arcade
	var menu := _vbox(8)
	menu.add_child(arcade)
	for row_spec in [[["สองคน · ประลอง", "2 PLAYERS", "vs", "02"], ["เล่นออนไลน์", "ONLINE", "online", "03"]],
			[["ฝึกซ้อม · สอนเล่น", "TRAINING", "training", "04"], ["วิธีเล่น", "HOW TO PLAY", "howto", "05"]]]:
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 8)
		for b in row_spec:
			var btn := _button(b[0], b[1], "SecondaryButton" if b[3] in ["02", "03"] else "GhostButton", b[2], b[3], false)
			btn.size_flags_horizontal = SIZE_EXPAND_FILL
			row_box.add_child(btn)
		menu.add_child(row_box)
	v.add_child(menu)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var hi := _vbox(0)
	hi.size_flags_horizontal = SIZE_EXPAND_FILL
	hi.add_child(_label("สถิติสูงสุด · HI", 10, 600, MUTED_INK, 1))
	var hv := _label("0", 20, 800)
	hi.add_child(hv)
	_dyn["title_hi"] = hv
	row.add_child(hi)
	var ver := _label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 10, 600, MUTED_INK, 1)
	ver.size_flags_vertical = SIZE_SHRINK_END
	row.add_child(ver)
	row.add_theme_constant_override("separation", 14)
	var sb := _sound_button()
	sb.size_flags_vertical = SIZE_SHRINK_END
	row.add_child(sb)
	v.add_child(_rule(DIVIDER))
	v.add_child(row)


func _build_select() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(BG))
	p.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(p)
	_screens["select"] = p
	var v := _vbox(0)
	p.add_child(v)

	var head := _margin(29, 12, 29, 10)
	var hrow := HBoxContainer.new()
	var titles := _vbox(2)
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	var kicker := _label("", 11, 600, ACC_700, 1)
	_dyn["select_kicker"] = kicker
	titles.add_child(kicker)
	titles.add_child(_label("เลือกช้างศึก", 30, 800))
	titles.add_child(_label("CHOOSE YOUR WAR ELEPHANT", 11, 800, INK, 1))
	hrow.add_child(titles)
	var back := _button("กลับ", "BACK · ESC", "SecondaryButton", "back", "", false)
	back.focus_mode = FOCUS_NONE
	back.custom_minimum_size.x = 134
	back.size_flags_vertical = SIZE_SHRINK_END
	hrow.add_child(back)
	head.add_child(hrow)
	v.add_child(head)
	v.add_child(_pattern_strip(false))

	var cards := _margin(24, 10, 24, 10)
	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 8)
	cards.add_child(_card_row)
	v.add_child(cards)
	v.add_child(_rule())

	var details := HBoxContainer.new()
	details.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 0)
	v.add_child(details)
	for i in 2:
		if i == 1:
			var vr := _vrule()
			_dyn["select_vrule"] = vr
			details.add_child(vr)
		details.add_child(_detail_panel(i))


func _card(i: int) -> PanelContainer:
	var def := _roster[i]
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 118
	card.mouse_filter = MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			action_pressed.emit("pick:%d" % i))
	var m := _margin(4, 4, 4, 4)
	m.mouse_filter = MOUSE_FILTER_IGNORE
	var col := _vbox(2)
	var prev := ElephantPreview.new()
	prev.size_flags_vertical = SIZE_EXPAND_FILL
	prev.def = _silhouette(def) if _locked[i] else def
	col.add_child(prev)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	var name := _label("???" if _locked[i] else def.display_name, 13, 800, MUTED_INK if _locked[i] else INK)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name)
	var tag1 := _tag("1P", ACC, 9)
	var tag2 := _tag("2P", INK, 9)
	row.add_child(tag1)
	row.add_child(tag2)
	col.add_child(row)
	m.add_child(col)
	card.add_child(m)
	card.set_meta("preview", prev)
	card.set_meta("tag1", tag1)
	card.set_meta("tag2", tag2)
	return card


func _detail_panel(p: int) -> Control:
	var root := _margin(24, 10, 24, 10)
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)
	var prev := ElephantPreview.new()
	prev.custom_minimum_size = Vector2(190, 0)
	var info := _vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_child(_label("ผู้เล่น %d · PLAYER %d" % [p + 1, p + 1], 11, 800, ACC_700 if p == 0 else INK, 1))
	var name := _label("", 24, 800)
	var name_en := _label("", 11, 800, ACC_700 if p == 0 else INK)
	name_en.clip_text = true
	var tagline := _label("", 11, 600, MUTED_INK)
	tagline.clip_text = true
	tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for l in [name, name_en, tagline]:
		info.add_child(l)
	var bars := []
	var stats := _vbox(3)
	for r in STAT_ROWS:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 6)
		var th := _label(r[0], 11, 600)
		th.custom_minimum_size.x = 68
		var en := _label(r[1], 8, 600, MUTED_INK, 1)
		en.custom_minimum_size.x = 44
		en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var bar := _stat_bar(ACC if p == 0 else INK)
		srow.add_child(th)
		srow.add_child(en)
		srow.add_child(bar)
		stats.add_child(srow)
		bars.append(bar)
	info.add_child(_pad(stats, 4, 4))
	var status := _label("", 11, 800, MUTED_INK, 1)
	info.add_child(status)
	# in 1-player mode the right half is free: it explains the elephant's two special moves
	var pad := _vbox(2)
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	var move_labels := []
	for spec in [["ท่าประจำตัว · ปุ่ม G", INK], ["อัลติ · ปุ่ม H เมื่อพลังเต็ม", ACC]]:
		pad.add_child(_label(spec[0], 10, 600, MUTED_INK, 1))
		var mname := _label("", 17, 800, spec[1])
		var mdesc := _label("", 11, 600, MUTED_INK)
		mdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mdesc.custom_minimum_size.x = 150
		pad.add_child(mname)
		pad.add_child(mdesc)
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		pad.add_child(gap)
		move_labels.append([mname, mdesc])
	if p == 0:
		row.add_child(prev)
		row.add_child(info)
		row.add_child(pad)
	else:
		row.add_child(info)
		row.add_child(prev)
	_details.append({"root": root, "preview": prev, "name": name, "name_en": name_en, "tagline": tagline, "bars": bars, "status": status, "pad": pad, "moves": move_labels})
	return root


func _stat_bar(col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	c.size_flags_horizontal = SIZE_EXPAND_FILL
	c.size_flags_vertical = SIZE_SHRINK_CENTER
	c.mouse_filter = MOUSE_FILTER_IGNORE
	c.set_meta("v", 0.0)
	c.draw.connect(func() -> void:
		var w := c.size.x
		c.draw_rect(Rect2(0, 0, w, 8), BG)
		c.draw_rect(Rect2(0, 0, w * float(c.get_meta("v")), 8), col)
		for k in range(1, 5):
			c.draw_rect(Rect2(w * k / 5.0 - 1.0, 0, 2, 8), BG)
		c.draw_rect(Rect2(0, 0, w, 8), INK, false, 2.0))
	return c


## Grey stand-in for a locked elephant.
func _silhouette(def: ElephantDef) -> ElephantDef:
	var d: ElephantDef = def.duplicate()
	d.body = Color("#cdbb9c")
	d.dark = Color("#b5a283")
	d.cloth = Color("#b5a283")
	d.trim = Color("#c4b08e")
	d.flag = Color("#b5a283")
	return d


func _build_howto() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(BG))
	p.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(p)
	_screens["howto"] = p
	var v := _vbox(0)
	p.add_child(v)

	var head := _margin(29, 14, 29, 12)
	var hrow := HBoxContainer.new()
	var titles := _vbox(2)
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	titles.add_child(_label("คู่มือ · MANUAL", 11, 600, ACC_700, 1))
	titles.add_child(_label("วิธีเล่น", 34, 800))
	titles.add_child(_label("HOW TO PLAY", 12, 800, INK, 1))
	hrow.add_child(titles)
	hrow.add_theme_constant_override("separation", 10)
	var combos := _button("ท่าคอมโบ", "COMBOS & TECHNIQUES", "PrimaryButton", "combos", "", false)
	combos.custom_minimum_size.x = 190
	combos.size_flags_vertical = SIZE_SHRINK_END
	hrow.add_child(combos)
	var back := _button("กลับ", "BACK", "SecondaryButton", "back", "", false)
	back.custom_minimum_size.x = 134
	back.size_flags_vertical = SIZE_SHRINK_END
	hrow.add_child(back)
	_first["howto"] = back
	head.add_child(hrow)
	v.add_child(head)
	v.add_child(_pattern_strip(false))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 0)
	v.add_child(cols)
	cols.add_child(_controls_column("ผู้เล่น 1", "PLAYER 1", ACC, [
		["เดิน", "MOVE", [["A"], ["D"]]],
		["กระโดด · ย่อ = ป้องกัน", "JUMP · CROUCH TO GUARD", [["W"], ["S"]]],
		["งวงฟาด · ระยะสั้น", "TRUNK WHIP · SHORT", [["F"]]],
		["แทงงา · ระยะกลาง", "TUSK POKE · MID", [["R"]]],
		["ท่าประจำตัว", "SIGNATURE MOVE", [["G"]]],
		["อัลติ · พลังเต็ม", "ULTIMATE · FULL POWER", [["H", "accent"]]],
	]))
	cols.add_child(_vrule())
	cols.add_child(_controls_column("ผู้เล่น 2", "PLAYER 2", INK, [
		["เดิน", "MOVE", [["←"], ["→"]]],
		["กระโดด · ย่อ = ป้องกัน", "JUMP · CROUCH TO GUARD", [["↑"], ["↓"]]],
		["งวงฟาด · ระยะสั้น", "TRUNK WHIP · SHORT", [[","], ["NUM 1", "alt"]]],
		["แทงงา · ระยะกลาง", "TUSK POKE · MID", [["L"], ["NUM 5", "alt"]]],
		["ท่าประจำตัว", "SIGNATURE MOVE", [["."], ["NUM 2", "alt"]]],
		["อัลติ · พลังเต็ม", "ULTIMATE · FULL POWER", [["/", "accent"], ["NUM 3", "alt"]]],
	]))
	cols.add_child(_vrule())

	var rules := _margin(24, 14, 24, 0)
	rules.size_flags_horizontal = SIZE_EXPAND_FILL
	rules.size_flags_stretch_ratio = 1.35
	var rv := _vbox(0)
	rules.add_child(rv)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 10)
	rh.add_child(_label("กติกา", 17, 800))
	var rh_en := _label("RULES", 10, 600, MUTED_INK, 1)
	rh_en.size_flags_vertical = SIZE_SHRINK_CENTER
	rh.add_child(rh_en)
	rv.add_child(_pad(rh, 0, 10))
	var items := [
		["01", "rule1", "", ""],
		["02", "", "ช้างแต่ละเชือกมีท่าประจำตัว (G) และอัลติ (H) ของตัวเอง โดนตีหรือตีโดนจะเติมหลอดพลัง", "Each elephant has its own signature (G) and ultimate (H, full power bar)."],
		["03", "", "ย่อค้างกันได้ทุกท่า ยกเว้นอัลติบางท่า กันได้แล้วรีบตีสวน", "Hold down to guard all but a few ultimates, then strike back."],
		["04", "", "หลอดทรงตัวหมด = ช้างเสียหลัก มึน 1 วิ กด G ท่าประจำตัวซ้ำ = กระแทกปิดฉาก", "Empty the balance bar to stun them, then land your signature (G) for a Decisive Strike."],
		["05", "rule4", "", ""],
		["06", "", "จอย: X = F · LB = R · Y = G · B = H · A กระโดด", "Gamepad: stick/D-pad move, hold down to guard · Start pause."],
	]
	for it in items:
		rv.add_child(_rule(DIVIDER))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var num := _label(it[0], 11, 800, ACC_700)
		num.custom_minimum_size.x = 25
		num.size_flags_vertical = SIZE_SHRINK_BEGIN
		row.add_child(num)
		var txt := _vbox(2)
		txt.size_flags_horizontal = SIZE_EXPAND_FILL
		var th := _label(it[2], 12, 600)
		var en := _label(it[3], 9, 600, MUTED_INK)
		for l in [th, en]:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 200
			l.add_theme_constant_override("line_spacing", -3)
		if it[1] != "":
			_dyn[it[1] + "_th"] = th
			_dyn[it[1] + "_en"] = en
		txt.add_child(th)
		txt.add_child(en)
		row.add_child(txt)
		rv.add_child(_pad(row, 4, 4))
	cols.add_child(rules)


## Combo techniques and special moves: what to press for each player and when it works.
func _build_combos() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(BG))
	p.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(p)
	_screens["combos"] = p
	var v := _vbox(0)
	p.add_child(v)

	var head := _margin(29, 10, 29, 10)
	var hrow := HBoxContainer.new()
	var titles := _vbox(0)
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	titles.add_child(_label("คู่มือ · MANUAL", 11, 600, ACC_700, 1))
	titles.add_child(_label("ท่าคอมโบ · ท่าพิเศษ", 30, 800))
	titles.add_child(_label("COMBOS & SPECIAL MOVES", 11, 800, INK, 1))
	hrow.add_child(titles)
	var back := _button("กลับ", "BACK", "SecondaryButton", "howto", "", false)
	back.custom_minimum_size.x = 134
	back.size_flags_vertical = SIZE_SHRINK_END
	hrow.add_child(back)
	_first["combos"] = back
	head.add_child(hrow)
	v.add_child(head)
	v.add_child(_pattern_strip(false))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 0)
	v.add_child(cols)
	cols.add_child(_combo_column("คอมโบ", "COMBOS", [
		["คอมโบงวง 3 จังหวะ", "TRUNK STRING", ["F", ">", "F", ">", "F"], [",", ">", ",", ">", ","],
			"ตีโดนแล้วกด F ต่อ (กดรัวได้) ครั้งที่ 3 ทุบงวงให้ลอย"],
		["สั้น › กลาง › กวาด", "SHORT › MID › SWEEP", ["F", ">", "R", ">", "↓R"], [",", ">", "L", ">", "↓L"],
			"งวงฟาด ต่อแทงงา แล้วย่อกวาดขาให้ล้ม"],
		["ยกเลิกท่า", "CANCEL", ["F", ">", "G", ">", "H"], [",", ">", ".", ">", "/"],
			"ท่าโดนแล้วกด G หรือท่าพิเศษตัดเข้าทันที แล้ว H ตอนพลังเต็ม"],
		["ทิ้งตัวแทงงา", "DIVING GORE", ["W", ">", "F"], ["↑", ">", ","],
			"กด F กลางอากาศ พุ่งลงแทง อีกฝ่ายต้องยืนกัน"],
		["ตีลอยฟ้า", "JUGGLE", ["F ×3", ">", "→↓↘ F"], [", ×3", ">", "→↓↘ ,"],
			"ทุบงวงให้ลอยแล้วต่องวงเสย ช้างที่ลอยอยู่โดนตีซ้ำได้ไม่เกิน 3 ครั้ง"],
		["พุ่งตัว · ถอยหลบ", "DASH · BACKSTEP", ["D D", "|", "A A"], ["→ →", "|", "← ←"],
			"แตะทิศ 2 ครั้งเร็วๆ เข้าหา = พุ่ง ถอยออก = ถอยหลบ"],
	]))
	cols.add_child(_vrule(DIVIDER))
	cols.add_child(_combo_column("ท่าพิเศษ", "SPECIALS", [
		["งวงพ่นน้ำ", "WATER SPOUT", ["↓ ↘ →", "+", "F"], ["↓ ↘ →", "+", ","],
			"พ่นลูกน้ำวิ่งไปตามพื้น (F หรือ R ก็ได้) กระโดดข้ามหรือป้องกันได้"],
		["งวงเสย", "TRUNK UPPERCUT", ["→ ↓ ↘", "+", "F"], ["→ ↓ ↘", "+", ","],
			"ตอนเริ่มท่าไม่โดนอะไร สวนคนกระโดดเข้ามา แต่ถ้าพลาดโดนสวนหนัก"],
		["ท่า EX", "EX SIGNATURE", ["G", "+", "H"], [".", "+", "/"],
			"กดพร้อมกัน ใช้พลังครึ่งหลอด ท่าประจำตัวแรงขึ้น ไม่สะดุ้งตอนง้าง"],
		["ปัดสวน", "GUARD COUNTER", ["↓", "+", "G"], ["↓", "+", "."],
			"ตอนกันการโจมตีได้ กด G ผลักสวนกลับ ใช้พลัง 1 ช่อง"],
		["สวนจังหวะ", "COUNTER HIT", [], [],
			"ตีโดนตอนอีกฝ่ายกำลังออกท่า แรงขึ้นและมึนนานขึ้น ต่อท่าได้ยาวขึ้น"],
		["ป้องกัน", "GUARD", ["↓"], ["↓"],
			"ย่อค้าง = กันได้ทุกท่า ยกเว้นอัลติบางท่า · ระหว่างย่อเดินไม่ได้"],
	]))
	var tip := _label("→ = ทิศที่หันหน้าไป (หันซ้ายก็กลับทิศ) · คอมโบยิ่งยาว แต่ละฮิตยิ่งเบาลง · จอย: X = F · Y = G · B = H", 10, 600, ACC_700)
	v.add_child(_pad(_margin_wrap(tip, 29), 0, 8))


func _margin_wrap(c: Control, side: int) -> MarginContainer:
	var m := _margin(side, 0, side, 0)
	m.add_child(c)
	return m


func _combo_column(title: String, sub: String, rows: Array) -> Control:
	var col := _margin(18, 10, 18, 0)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := _vbox(0)
	col.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_label(title, 16, 800))
	var sub_label := _label(sub, 10, 600, MUTED_INK, 1)
	sub_label.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(sub_label)
	head.add_child(_spacer_h())
	for t in ["P1", "P2"]:
		var l := _label(t, 10, 800, MUTED_INK, 1)
		l.custom_minimum_size.x = 136
		l.size_flags_vertical = SIZE_SHRINK_CENTER
		head.add_child(l)
	v.add_child(_pad(head, 0, 6))
	for r in rows:
		v.add_child(_rule(DIVIDER))
		var cell := _vbox(1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var name := _label(r[0], 13, 800)
		name.size_flags_horizontal = SIZE_EXPAND_FILL
		name.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(name)
		for k in 2:
			var keys := _combo_keys(r[2 + k])
			keys.custom_minimum_size.x = 136
			row.add_child(keys)
		cell.add_child(row)
		var how := _label(r[4] + "  · " + r[1], 10, 600, MUTED_INK)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size.x = 200
		cell.add_child(how)
		v.add_child(_pad(cell, 4, 4))
	return col


func _spacer_h() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = SIZE_EXPAND_FILL
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c


## Key caps for one input sequence; ">" is "then", "+" is "together", "|" separates alternatives.
func _combo_keys(tokens: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.size_flags_vertical = SIZE_SHRINK_CENTER
	for t in tokens:
		if t in [">", "+", "|"]:
			var l := _label({">": "›", "+": "+", "|": "/"}[t], 14, 800, MUTED_INK if t == "|" else ACC_700)
			l.size_flags_vertical = SIZE_SHRINK_CENTER
			h.add_child(l)
		else:
			h.add_child(_keycap(t, "accent" if t in ["H", "/"] else "key"))
	return h


func _build_online() -> void:
	var v := _side_panel("online")
	v.add_child(_label("ออนไลน์ · ONLINE", 11, 600, ACC_700, 1))
	v.add_child(_label("เล่นออนไลน์", 48, 800))
	v.add_child(_label("PLAY ONLINE", 17, 800))
	var status := _label("", 13, 600, INK)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(200, 40)
	_dyn["online_status"] = status
	v.add_child(_pad(status, 10, 0))
	v.add_child(_spacer())
	var quick := _button("สุ่มหาคู่", "QUICK MATCH · ANYONE ONLINE", "PrimaryButton", "o_quick")
	_first["online"] = quick
	var menu := _vbox(8)
	menu.add_child(quick)
	menu.add_child(_button("สร้างห้องเล่นกับเพื่อน", "CREATE A ROOM · GET A CODE", "SecondaryButton", "o_host", "", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var code := LineEdit.new()
	code.placeholder_text = "รหัสห้อง"
	code.max_length = 4
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.custom_minimum_size = Vector2(150, 0)
	code.add_theme_font_override("font", GameData.font(800, 4))
	code.add_theme_font_size_override("font_size", 20)
	code.add_theme_color_override("font_color", INK)
	code.add_theme_color_override("font_placeholder_color", MUTED_INK)
	code.add_theme_color_override("caret_color", ACC)
	for st in ["normal", "focus"]:
		var box := _flat(GameData.SURFACE if st == "normal" else BG)
		box.set_border_width_all(2 if st == "normal" else 3)
		box.border_color = INK if st == "normal" else ACC
		code.add_theme_stylebox_override(st, box)
	code.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			code.text = up
			code.caret_column = up.length())
	code.text_submitted.connect(func(_t: String) -> void: action_pressed.emit("o_join"))
	_dyn["room_code"] = code
	row.add_child(code)
	var join := _button("เข้าห้อง", "JOIN WITH CODE", "SecondaryButton", "o_join", "", false)
	join.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(join)
	menu.add_child(row)
	menu.add_child(_button("กลับ", "BACK", "GhostButton", "back", "", false))
	v.add_child(menu)


func set_online_status(text: String) -> void:
	_set_text("online_status", text)


func room_code() -> String:
	return (_dyn["room_code"] as LineEdit).text.strip_edges().to_upper()


func _build_pause() -> void:
	var v := _side_panel("pause")
	v.add_child(_label("ESC · P · START", 11, 600, ACC_700, 1))
	var title := _vbox(0)
	title.add_child(_label("หยุดชั่วคราว", 48, 800))
	title.add_child(_label("PAUSED", 17, 800))
	_dyn["pause_title"] = title
	v.add_child(title)
	v.add_child(_spacer())
	var resume := _button("เล่นต่อ", "RESUME", "PrimaryButton", "resume")
	_first["pause"] = resume
	v.add_child(resume)
	# training options (only shown in training mode)
	var tb := GridContainer.new()
	tb.columns = 2
	tb.add_theme_constant_override("h_separation", 6)
	tb.add_theme_constant_override("v_separation", 6)
	for b in [["บทเรียนถัดไป", "NEXT LESSON", "t_next"], ["บทก่อนหน้า", "PREVIOUS LESSON", "t_prev"],
			["ฝึกอิสระ", "FREE PRACTICE", "t_free"], ["หุ่น", "DUMMY", "t_dummy"], ["พลังเต็มตลอด", "INFINITE POWER", "t_meter"]]:
		var btn := _button(b[0], b[1], "SecondaryButton", b[2], "", false)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		_dyn[b[2]] = btn
		tb.add_child(btn)
	_dyn["train_box"] = tb
	tb.visible = false
	v.add_child(tb)
	v.add_child(_button("เมนูหลัก", "MAIN MENU", "SecondaryButton", "menu"))
	var sb := _sound_button()
	sb.size_flags_horizontal = SIZE_SHRINK_BEGIN
	v.add_child(sb)


## Shows or hides the training options in the pause menu and updates their labels.
func set_training_menu(on: bool, dummy_name: String, meter_on: bool, in_lesson: bool) -> void:
	(_dyn["train_box"] as Control).visible = on
	(_dyn["pause_title"] as Control).visible = not on
	if not on:
		return
	_button_text(_dyn["t_free"], "ฝึกอิสระ" if in_lesson else "กลับไปเรียนบทแรก", "FREE PRACTICE" if in_lesson else "BACK TO LESSON 1")
	_button_text(_dyn["t_dummy"], "หุ่น: " + dummy_name.get_slice(" · ", 0), "DUMMY: " + dummy_name.get_slice(" · ", 1))
	_button_text(_dyn["t_meter"], "พลังเต็มตลอด: " + ("เปิด" if meter_on else "ปิด"), "INFINITE POWER: " + ("ON" if meter_on else "OFF"))


func _button_text(b: Button, th: String, en: String) -> void:
	var en_label := b.get_meta("en") as Label
	en_label.text = en
	var col := en_label.get_parent()
	(col.get_child(0) as Label).text = th


func _build_stage_clear() -> void:
	var v := _side_panel("stageclear")
	var kicker := _label("", 11, 600, ACC_700, 1)
	_dyn["stage_kicker"] = kicker
	v.add_child(kicker)
	v.add_child(_label("ชนะ!", 58, 800))
	v.add_child(_label("STAGE CLEAR", 17, 800))
	var score := _label("0", 38, 800)
	_dyn["stage_score"] = score
	v.add_child(_block(INK, [_label("คะแนนสะสม · SCORE", 10, 600, MUTED_INK, 1), score]))
	var nth := _label("", 21, 800)
	var nen := _label("", 10, 600, INK, 1)
	_dyn["next_th"] = nth
	_dyn["next_en"] = nen
	v.add_child(_block(DIVIDER, [_label("คู่ต่อสู้ถัดไป · NEXT OPPONENT", 10, 600, MUTED_INK, 1), nth, nen]))
	v.add_child(_spacer())
	var next := _button("ด่านต่อไป", "NEXT STAGE", "PrimaryButton", "next")
	_first["stageclear"] = next
	v.add_child(next)


func _build_game_over() -> void:
	var v := _side_panel("gameover")
	for spec in [["over_kicker", 11, 600, ACC_700, 1], ["over_th", 48, 800, INK, 0], ["over_en", 17, 800, INK, 0]]:
		var l := _label("", spec[1], spec[2], spec[3], spec[4])
		_dyn[spec[0]] = l
		v.add_child(l)
	var scores := HBoxContainer.new()
	scores.add_theme_constant_override("separation", 12)
	var sc := _label("0", 35, 800)
	var best := _label("0", 35, 800)
	_dyn["over_score"] = sc
	_dyn["over_best"] = best
	var left := _vbox(2)
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_child(_label("คะแนน · SCORE", 10, 600, MUTED_INK, 1))
	left.add_child(sc)
	var right := _vbox(2)
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_child(_label("สถิติสูงสุด · BEST", 10, 600, MUTED_INK, 1))
	right.add_child(best)
	scores.add_child(left)
	scores.add_child(_vrule(DIVIDER))
	scores.add_child(right)
	v.add_child(_block(INK, [scores]))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	var hi_tag := _tag("สถิติใหม่! · NEW RECORD", ACC, 11)
	var unlock_tag := _tag("ปลดล็อกช้างใหม่! · NEW ELEPHANT", INK, 11)
	_dyn["new_hi"] = hi_tag
	_dyn["unlocked"] = unlock_tag
	tags.add_child(hi_tag)
	tags.add_child(unlock_tag)
	v.add_child(tags)
	v.add_child(_spacer())
	var retry := _button("เล่นอีกครั้ง", "PLAY AGAIN", "PrimaryButton", "retry")
	_first["gameover"] = retry
	v.add_child(retry)
	v.add_child(_share_row())
	var msg := _label("", 10, 600, ACC_700)
	_dyn["over_share"] = msg
	v.add_child(msg)


func _build_vs_result() -> void:
	var v := _side_panel("vsresult")
	v.add_child(_label("ประลอง · VERSUS", 11, 600, ACC_700, 1))
	var th := _label("", 48, 800)
	var en := _label("", 17, 800)
	_dyn["vs_th"] = th
	_dyn["vs_en"] = en
	v.add_child(th)
	v.add_child(en)
	var score := _label("", 42, 800)
	var name := _label("", 10, 600, INK, 1)
	_dyn["vs_score"] = score
	_dyn["vs_name"] = name
	v.add_child(_block(INK, [_label("ผลยก · ROUNDS", 10, 600, MUTED_INK, 1), score, name]))
	v.add_child(_spacer())
	var rematch := _button("แมตช์ใหม่", "REMATCH", "PrimaryButton", "rematch")
	_first["vsresult"] = rematch
	v.add_child(rematch)
	v.add_child(_share_row())
	var msg := _label("", 10, 600, ACC_700)
	_dyn["vs_share"] = msg
	v.add_child(msg)


# ---------- pieces ----------

func _side_panel(screen: String) -> VBoxContainer:
	var root := Control.new()
	root.mouse_filter = MOUSE_FILTER_IGNORE
	root.anchor_right = 0.42
	root.anchor_bottom = 1.0
	add_child(root)
	_screens[screen] = root
	var p := PanelContainer.new()
	var sb := _flat(BG)
	sb.set_content_margin_all(29)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	p.offset_right = -STRIP
	root.add_child(p)
	var strip := _pattern_strip(true)
	strip.anchor_left = 1.0
	strip.anchor_right = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = -STRIP
	root.add_child(strip)
	var v := _vbox(10)
	p.add_child(v)
	return v


## Lai-thai border: gold flame motifs and diamonds on lacquer red, between gold rules.
func _pattern_strip(vertical: bool) -> Control:
	var c := Control.new()
	c.mouse_filter = MOUSE_FILTER_IGNORE
	if vertical:
		c.custom_minimum_size.x = STRIP
	else:
		c.custom_minimum_size.y = STRIP
	c.draw.connect(func() -> void:
		var length := c.size.y if vertical else c.size.x
		if vertical:
			c.draw_set_transform(Vector2(STRIP, 0.0), PI / 2.0)
		var gold := GameData.GOLD
		c.draw_rect(Rect2(0, 0, length, STRIP), ACC_700)
		c.draw_rect(Rect2(0, 0, length, 2), gold)
		c.draw_rect(Rect2(0, STRIP - 2, length, 2), gold)
		var mid := STRIP / 2.0
		var x := 8.0
		var k := 0
		while x < length:
			if k % 2 == 0:
				c.draw_colored_polygon(PackedVector2Array([Vector2(x, mid - 4), Vector2(x + 4, mid), Vector2(x, mid + 4), Vector2(x - 4, mid)]), GameData.GOLD_LIGHT)
			else:
				c.draw_colored_polygon(PackedVector2Array([Vector2(x - 4, mid + 3), Vector2(x - 1, mid - 4), Vector2(x + 1, mid - 4), Vector2(x + 4, mid + 3)]), gold)
			x += 10.0
			k += 1
	)
	c.resized.connect(c.queue_redraw)
	return c


func _controls_column(title: String, sub: String, swatch: Color, rows: Array) -> Control:
	var col := _margin(24, 14, 24, 0)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := _vbox(0)
	col.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var sq := ColorRect.new()
	sq.color = swatch
	sq.custom_minimum_size = Vector2(13, 13)
	sq.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(sq)
	head.add_child(_label(title, 17, 800))
	var sub_label := _label(sub, 10, 600, MUTED_INK, 1)
	sub_label.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(sub_label)
	v.add_child(_pad(head, 0, 10))
	for r in rows:
		v.add_child(_rule(DIVIDER))
		var row := HBoxContainer.new()
		var txt := _vbox(0)
		txt.size_flags_horizontal = SIZE_EXPAND_FILL
		txt.add_child(_label(r[0], 13, 600))
		txt.add_child(_label(r[1], 9, 600, MUTED_INK, 1))
		row.add_child(txt)
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 5)
		keys.size_flags_vertical = SIZE_SHRINK_CENTER
		for k in r[2]:
			keys.add_child(_keycap(k[0], k[1] if k.size() > 1 else "key"))
		row.add_child(keys)
		v.add_child(_pad(row, 3, 3))
	return col


func _keycap(text: String, kind: String) -> Control:
	var p := PanelContainer.new()
	var sb := _flat(ACC if kind == "accent" else Color.TRANSPARENT)
	sb.set_border_width_all(2)
	sb.border_color = ACC if kind == "accent" else (DIVIDER if kind == "alt" else INK)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(25, 25)
	var l := _label(text, 10 if kind == "alt" else 12, 600 if kind == "alt" else 800, Color.WHITE if kind == "accent" else INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## A flush-left button with a Thai label over a small English one.
func _button(th: String, en: String, style: String, action: String, num := "", big := true) -> Button:
	var b := Button.new()
	b.theme_type_variation = style
	b.pressed.connect(func() -> void: action_pressed.emit(action))
	var fg := Color.WHITE if style == "PrimaryButton" else INK
	var m := _margin(13, 8, 13, 8)
	m.mouse_filter = MOUSE_FILTER_IGNORE
	m.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	var th_label := _label(th, 18 if big else 15, 800, fg)
	if num != "":
		var n := _label(num, 11, 800, fg)
		n.custom_minimum_size = Vector2(33, th_label.get_minimum_size().y)
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.size_flags_vertical = SIZE_SHRINK_BEGIN
		row.add_child(n)
	var col := _vbox(0)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_child(th_label)
	var en_label := _label(en, 10 if big else 9, 600, fg, 1)
	col.add_child(en_label)
	row.add_child(col)
	m.add_child(row)
	b.add_child(m)
	b.set_meta("en", en_label)
	var fit := func() -> void: b.custom_minimum_size.y = m.get_combined_minimum_size().y
	m.minimum_size_changed.connect(fit)
	fit.call()
	return b


func _sound_button() -> Button:
	var b := Button.new()
	b.theme_type_variation = "SecondaryButton"
	b.add_theme_font_override("font", GameData.font(800, 1))
	b.add_theme_font_size_override("font_size", 11)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void: action_pressed.emit("sound"))
	_sound_buttons.append(b)
	set_muted(false)
	return b


func _share_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec in [["แชร์ผล", "SHARE", "share"], ["เลือกช้าง", "ELEPHANT", "reselect"], ["เมนูหลัก", "MENU", "menu"]]:
		var b := _button(spec[0], spec[1], "SecondaryButton", spec[2], "", false)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(b)
	return row


## Rule line on top, then the children stacked.
func _block(rule_color: Color, children: Array) -> Control:
	var v := _vbox(2)
	v.add_child(_rule(rule_color))
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	for c in children:
		v.add_child(c)
	return v


func _label(text: String, size: int, weight: int, color := INK, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", GameData.font(weight, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _set_text(key: String, text: String) -> void:
	(_dyn[key] as Label).text = text


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	return v


func _margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m


func _pad(c: Control, top: int, bottom: int) -> MarginContainer:
	var m := _margin(0, top, 0, bottom)
	m.add_child(c)
	return m


func _tag(text: String, col: Color, size: int) -> PanelContainer:
	var tag := PanelContainer.new()
	var sb := _flat(col)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	tag.add_theme_stylebox_override("panel", sb)
	tag.size_flags_horizontal = SIZE_SHRINK_BEGIN
	tag.size_flags_vertical = SIZE_SHRINK_CENTER
	tag.mouse_filter = MOUSE_FILTER_IGNORE
	tag.add_child(_label(text, size, 800, Color.WHITE))
	return tag


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = SIZE_EXPAND_FILL
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c


func _rule(color := INK) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.y = 2
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


func _vrule(color := INK) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.x = 2
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	return s


# ---------- theme ----------

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = GameData.font(600)
	th.default_font_size = 14
	_button_type(th, "PrimaryButton", ACC, ACC, GameData.ACC_600, GameData.ACC_700, true)
	_button_type(th, "SecondaryButton", Color.TRANSPARENT, INK, GameData.ACC_100, GameData.ACC_200, false)
	_button_type(th, "GhostButton", Color.TRANSPARENT, Color.TRANSPARENT, GameData.ACC_100, GameData.ACC_200, false)
	return th


func _button_type(th: Theme, type: String, fill: Color, border: Color, hover: Color, pressed: Color, border_follows: bool) -> void:
	th.set_type_variation(type, "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var c: Color = {"normal": fill, "hover": hover, "pressed": pressed, "disabled": fill}[state]
		var s := _flat(c)
		s.set_border_width_all(2)
		s.border_color = c if border_follows else border
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		th.set_stylebox(state, type, s)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = ACC
	focus.set_expand_margin_all(4)
	th.set_stylebox("focus", type, focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, type, Color.WHITE if border_follows else INK)
