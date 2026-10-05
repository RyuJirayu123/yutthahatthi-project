extends Node
## Game flow: title, elephant select, arcade ladder, scoring and the save file.
## Duel simulates a match, Arena draws it, GameUI shows the menus.

const SAVE_PATH := "user://save.cfg"
const ATTACKS := ["light", "heavy", "special", "rider"]
const STAGES := 3

@export_group("Roster")
## Elephants on the select screen, in order. Add an ElephantDef here to add a character.
@export var roster: Array[ElephantDef] = []
## Final arcade opponent.
@export var boss: ElephantDef

@export_group("CPU")
## One profile per arcade stage, easiest first.
@export var stage_ai: Array[AIProfile] = []
## Used by the title-screen demo.
@export var demo_ai: AIProfile

@export_group("Rules")
@export_range(10, 99) var round_time := 60
@export_range(1, 3) var rounds_to_win := 2
@export var screen_shake := true

@onready var arena: Node2D = $Arena
@onready var ui: GameUI = $UI/Root

var screen := "title"
var paused := false
var duel: Duel
var stage := 0
var run_score := 0
var hiscore := 0
var share_text := ""
var boss_unlocked := false
var player1: ElephantDef
var player2: ElephantDef
var ladder: Array[ElephantDef] = []

var select_mode := "arcade"
var cursors: Array[int] = [0, 1]
var confirmed: Array[bool] = [false, false]
var _select_go := -1.0     ## countdown to the match once everyone has picked
var _select_wait := 0.0    ## ignore the key press that opened the screen


func _ready() -> void:
	_load_save()
	ui.action_pressed.connect(_on_ui_action)
	ui.set_hiscore(hiscore)
	ui.set_rules(rounds_to_win, round_time, STAGES)
	ui.setup_roster(roster, _locked_list())
	_start_duel("demo", 0)
	ui.show_screen("title")


func _process(delta: float) -> void:
	if screen == "select":
		_select_process(delta)
	if duel == null:
		return
	if paused:
		duel.clear_presses()
		return
	if screen == "fight":
		for p in ["p1_", "p2_"]:
			for a in ATTACKS:
				if Input.is_action_just_pressed(p + a):
					duel.press(p + a)
	duel.update(minf(0.05, delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and screen == "fight":
		_set_paused(not paused)
	elif event.is_action_pressed("mute"):
		_toggle_sound()
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "fight" and not paused:
		_set_paused(true)


func _on_ui_action(action: String) -> void:
	if action.begins_with("pick:"):
		_pick(int(action.get_slice(":", 1)))
		return
	match action:
		"arcade", "vs":
			_open_select(action)
		"reselect":
			_open_select(duel.mode)
		"retry":
			_begin("arcade", 0)
		"rematch":
			_begin("vs", 0)
		"next":
			_begin("arcade", stage + 1)
		"howto", "combos":
			Sfx.play("select", true)
			screen = action
			ui.show_screen(action)
		"back", "menu":
			_to_title()
		"resume":
			_set_paused(false)
		"share":
			_share()
		"sound":
			_toggle_sound()


func _to_title() -> void:
	Sfx.play("select", true)
	_start_duel("demo", 0)
	paused = false
	screen = "title"
	ui.show_screen("title")


# ---------- elephant select ----------

func _open_select(mode: String) -> void:
	Sfx.play("select", true)
	if duel.mode != "demo":
		_start_duel("demo", 0)
	select_mode = mode
	confirmed.assign([false, false])
	_select_go = -1.0
	_select_wait = 0.15
	paused = false
	screen = "select"
	ui.update_select(select_mode, cursors, confirmed)
	ui.show_screen("select")


func _select_process(delta: float) -> void:
	if _select_wait > 0.0:
		_select_wait -= delta
		return
	if _select_go >= 0.0:
		_select_go -= delta
		if _select_go < 0.0:
			_start_from_select()
		return
	if Input.is_action_just_pressed("pause") or (not confirmed[0] and Input.is_action_just_pressed("p1_cancel")):
		_to_title()
		return
	for p in (2 if select_mode == "vs" else 1):
		var pre := "p%d_" % (p + 1)
		if confirmed[p]:
			if Input.is_action_just_pressed(pre + "cancel"):
				confirmed[p] = false
				Sfx.play("select", true)
				ui.update_select(select_mode, cursors, confirmed)
			continue
		var dir := int(Input.is_action_just_pressed(pre + "right")) - int(Input.is_action_just_pressed(pre + "left"))
		if dir != 0:
			cursors[p] = wrapi(cursors[p] + dir, 0, roster.size())
			Sfx.play("select", true)
			ui.update_select(select_mode, cursors, confirmed)
		elif Input.is_action_just_pressed(pre + "confirm"):
			_confirm(p)


## Mouse click on a card: picks for whoever hasn't chosen yet.
func _pick(i: int) -> void:
	if screen != "select" or _select_go >= 0.0:
		return
	var p := 1 if select_mode == "vs" and confirmed[0] else 0
	if confirmed[p]:
		return
	cursors[p] = i
	_confirm(p)


func _confirm(p: int) -> void:
	if _locked_list()[cursors[p]]:
		Sfx.play("block", true)
		ui.update_select(select_mode, cursors, confirmed)
		return
	confirmed[p] = true
	Sfx.play("trumpet", true)
	ui.update_select(select_mode, cursors, confirmed)
	if confirmed[0] and (select_mode != "vs" or confirmed[1]):
		_select_go = 0.9


func _start_from_select() -> void:
	player1 = roster[cursors[0]]
	if select_mode == "vs":
		player2 = roster[cursors[1]]
		if player2 == player1:
			player2 = _alt_colors(player1)
		_begin("vs", 0)
	else:
		_build_ladder()
		_begin("arcade", 0)


## Two random opponents, then the boss (or a third random one if you are the boss).
func _build_ladder() -> void:
	var pool: Array[ElephantDef] = []
	for d in roster:
		if d != player1 and d != boss:
			pool.append(d)
	pool.shuffle()
	ladder.assign([pool[0], pool[1], boss if player1 != boss else pool[2]])


## Mirror match: tint player 2's copy so the two elephants can be told apart.
func _alt_colors(def: ElephantDef) -> ElephantDef:
	var d: ElephantDef = def.duplicate()
	var light := def.body.get_luminance() > 0.3
	d.body = def.body.lerp(GameData.INK, 0.3) if light else def.body.lerp(Color.WHITE, 0.35)
	d.dark = def.dark.lerp(GameData.INK, 0.3) if light else def.dark.lerp(Color.WHITE, 0.35)
	# opposite team colour on the cloth and flag
	d.cloth = Color.from_hsv(fposmod(def.cloth.h + 0.5, 1.0), def.cloth.s, maxf(def.cloth.v, 0.55))
	d.flag = d.cloth
	return d


func _locked_list() -> Array[bool]:
	var out: Array[bool] = []
	for d in roster:
		out.append(d.locked and not boss_unlocked)
	return out


# ---------- matches ----------

func _begin(mode: String, st: int) -> void:
	Sfx.play("select", true)
	if mode == "arcade" and st == 0:
		run_score = 0
	stage = st
	_start_duel(mode, st)
	paused = false
	screen = "fight"
	ui.show_screen("fight")


func _start_duel(mode: String, st: int) -> void:
	var left := player1
	var right: ElephantDef
	var ai := demo_ai
	match mode:
		"arcade":
			right = ladder[st]
			ai = stage_ai[mini(st, stage_ai.size() - 1)]
		"vs":
			right = player2
		_:
			left = roster.pick_random()
			right = roster.pick_random()
			while right == left:
				right = roster.pick_random()
	duel = Duel.new(mode, st, left, right, ai, round_time, rounds_to_win, screen_shake)
	duel.run_score = run_score
	duel.finished.connect(_on_duel_finished)
	arena.duel = duel
	arena.frozen = false


func _on_duel_finished(winner: int) -> void:
	if duel.mode == "demo":
		_start_duel("demo", 0)
		return
	paused = false
	if duel.mode == "vs":
		var def := player1 if winner == 0 else player2
		share_text = "ยุทธหัตถี · Elephant Duel — %s (ผู้เล่น %d) ชนะ %d–%d" % [def.display_name, winner + 1, duel.wins[0], duel.wins[1]]
		Sfx.play("win")
		screen = "vsresult"
		ui.show_vs_result(winner, duel.wins, def)
		return
	run_score = duel.run_score
	if winner == 0 and stage < STAGES - 1:
		Sfx.play("win")
		screen = "stageclear"
		ui.show_stage_clear(stage, STAGES, run_score, ladder[stage + 1])
		return
	var cleared := winner == 0
	var new_hi := run_score > hiscore
	var unlocked := cleared and not boss_unlocked
	if new_hi:
		hiscore = run_score
		ui.set_hiscore(hiscore)
	if unlocked:
		boss_unlocked = true
		ui.setup_roster(roster, _locked_list())
	if new_hi or unlocked:
		_save()
	var passed := STAGES if cleared else stage
	share_text = "ยุทธหัตถี · Elephant Duel — %s · %s คะแนน · ผ่าน %d/%d ด่าน%s" % [player1.display_name, GameData.fmt_num(run_score), passed, STAGES, " · แชมป์!" if cleared else ""]
	Sfx.play("win" if cleared else "lose")
	screen = "gameover"
	ui.show_game_over(cleared, passed, STAGES, run_score, hiscore, new_hi, unlocked)


func _set_paused(p: bool) -> void:
	paused = p
	arena.frozen = p
	ui.show_screen("pause" if p else "fight")


func _toggle_sound() -> void:
	Sfx.muted = not Sfx.muted
	ui.set_muted(Sfx.muted)
	Sfx.play("select", true)


func _share() -> void:
	DisplayServer.clipboard_set(share_text)
	ui.set_share_msg("คัดลอกผลแล้ว · Copied to clipboard")


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	hiscore = int(cfg.get_value("arcade", "hiscore", 0))
	boss_unlocked = bool(cfg.get_value("unlocks", "boss", false))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("arcade", "hiscore", hiscore)
	cfg.set_value("unlocks", "boss", boss_unlocked)
	cfg.save(SAVE_PATH)
