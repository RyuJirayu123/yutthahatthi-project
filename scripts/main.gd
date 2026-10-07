extends Node
## Game flow: title, elephant select, arcade ladder, scoring and the save file.
## Duel simulates a match, Arena draws it, GameUI shows the menus.

const SAVE_PATH := "user://save.cfg"
const ATTACKS := ["light", "medium", "heavy", "special", "rider"]
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
var training: Training    ## set while in training mode
var net: Net              ## link to the online relay
var online: OnlineMatch   ## set during an online match
var online_side := -1     ## 0 = left / host, 1 = right; -1 = not online
var _online_menu := false ## pause menu open during an online match (the match keeps running)
var _online_ask := {}     ## request to send once the relay connection opens
var _picks: Array[int] = [-1, -1]
var _votes: Array[bool] = [false, false]
var _rtt := 120.0         ## ms, measured while picking elephants
var _ping_t := 0.0

var select_mode := "arcade"
var cursors: Array[int] = [0, 1]
var confirmed: Array[bool] = [false, false]
var _select_go := -1.0     ## countdown to the match once everyone has picked
var _select_wait := 0.0    ## ignore the key press that opened the screen


func _ready() -> void:
	_load_save()
	net = Net.new()
	add_child(net)
	net.opened.connect(_on_net_open)
	net.message.connect(_on_net_message)
	net.closed.connect(_on_net_closed)
	ui.action_pressed.connect(_on_ui_action)
	ui.set_hiscore(hiscore)
	ui.set_rules(rounds_to_win, round_time, STAGES)
	ui.setup_roster(roster, _locked_list())
	_start_duel("demo", 0)
	ui.show_screen("title")


func _process(delta: float) -> void:
	if screen == "select":
		_select_process(delta)
		if online_side == 0:
			_ping_t -= delta
			if _ping_t <= 0.0:
				_ping_t = 0.5
				net.send({"t": "ping", "ts": Time.get_ticks_msec()})
	if duel == null:
		return
	if online and online.active:
		for a in ATTACKS:
			if Input.is_action_just_pressed("p1_" + a):
				online.press(a)
		online.update(delta)
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
	if training and screen == "fight":
		training.update(minf(0.05, delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and screen == "fight" and online:
		_set_online_menu(not _online_menu)
	elif event.is_action_pressed("pause") and screen == "fight":
		_set_paused(not paused)
	elif event.is_action_pressed("mute"):
		_toggle_sound()
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "fight" and not paused and online == null:
		_set_paused(true)


func _on_ui_action(action: String) -> void:
	if action.begins_with("pick:"):
		_pick(int(action.get_slice(":", 1)))
		return
	match action:
		"arcade", "vs", "training":
			_open_select(action)
		"reselect":
			if online_side >= 0:
				net.send({"t": "reselect"})
				_picks.assign([-1, -1])
				_open_select("online")
			else:
				_open_select(duel.mode)
		"retry":
			_begin("arcade", 0)
		"rematch":
			if online_side >= 0:
				_vote_rematch(online_side)
				net.send({"t": "rematch"})
			else:
				_begin("vs", 0)
		"online":
			_open_online("")
		"o_quick":
			_online_request({"t": "quick"}, "กำลังหาคู่ต่อสู้… · FINDING AN OPPONENT")
		"o_host":
			_online_request({"t": "host"}, "กำลังสร้างห้อง… · CREATING A ROOM")
		"o_join":
			var code := ui.room_code()
			if code.length() != 4:
				ui.set_online_status("ใส่รหัสห้อง 4 ตัวก่อน · ENTER THE 4-LETTER CODE")
			else:
				_online_request({"t": "join", "code": code}, "กำลังเข้าห้อง %s… · JOINING" % code)
		"next":
			_begin("arcade", stage + 1)
		"howto", "combos":
			Sfx.play("select", true)
			screen = action
			ui.show_screen(action)
		"back", "menu":
			_to_title()
		"resume":
			if online:
				_set_online_menu(false)
			else:
				_set_paused(false)
		"t_next", "t_prev", "t_free", "t_dummy", "t_meter":
			_training_action(action)
		"share":
			_share()
		"sound":
			_toggle_sound()


func _training_action(action: String) -> void:
	if training == null:
		return
	Sfx.play("select", true)
	match action:
		"t_next": training.next_lesson()
		"t_prev": training.prev_lesson()
		"t_free": training.free_practice() if training.lesson >= 0 else training.start_lesson(0)
		"t_dummy": training.cycle_dummy()
		"t_meter": training.infinite_meter = not training.infinite_meter
	_refresh_training_menu()
	if action in ["t_next", "t_prev", "t_free"]:
		_set_paused(false)


func _refresh_training_menu() -> void:
	if training:
		ui.set_training_menu(true, Training.DUMMY_NAMES[training.dummy], training.infinite_meter, training.lesson >= 0)
	else:
		ui.set_training_menu(false, "", false, false)


func _to_title() -> void:
	Sfx.play("select", true)
	_leave_online()
	training = null
	arena.training = null
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
	if select_mode == "online" and confirmed[0]:
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
	if select_mode == "online":
		_picks[online_side] = cursors[0]
		net.send({"t": "pick", "i": cursors[0]})
		_try_go()
	elif confirmed[0] and (select_mode != "vs" or confirmed[1]):
		_select_go = 0.9


func _start_from_select() -> void:
	player1 = roster[cursors[0]]
	if select_mode == "vs":
		player2 = roster[cursors[1]]
		if player2 == player1:
			player2 = _alt_colors(player1)
		_begin("vs", 0)
	elif select_mode == "training":
		# the practice dummy is the next regular elephant along
		var j := (cursors[0] + 1) % roster.size()
		while roster[j].locked or roster[j] == player1:
			j = (j + 1) % roster.size()
		player2 = roster[j]
		_begin("training", 0)
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
		"training":
			right = player2
			ai = stage_ai[1]
		"online":
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
	training = Training.new(duel) if mode == "training" else null
	arena.training = training


func _on_duel_finished(winner: int) -> void:
	if duel.mode == "demo":
		_start_duel("demo", 0)
		return
	paused = false
	if duel.mode == "online":
		online.active = false
		_set_online_menu(false)
		_votes.assign([false, false])
		Sfx.play("win" if winner == online_side else "lose")
		screen = "vsresult"
		var wdef := player1 if winner == 0 else player2
		share_text = "ยุทธหัตถี · Elephant Duel ออนไลน์ — %s ชนะ %d–%d" % [wdef.display_name, duel.wins[0], duel.wins[1]]
		ui.show_vs_result(winner, duel.wins, wdef, online_side)
		return
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
	if p:
		_refresh_training_menu()
	paused = p
	arena.frozen = p
	ui.show_screen("pause" if p else "fight")


# ---------- online ----------

func _open_online(status: String) -> void:
	Sfx.play("select", true)
	net.wake()
	if duel.mode != "demo":
		_start_duel("demo", 0)
	paused = false
	screen = "online"
	ui.set_online_status(status if status != "" else "กด สุ่มหาคู่ พร้อมกันกับเพื่อน หรือคนหนึ่งสร้างห้องแล้วส่งรหัสให้อีกคน (ใช้ปุ่มของผู้เล่น 1)")
	ui.show_screen("online")


func _online_request(msg: Dictionary, status: String) -> void:
	ui.set_online_status(status)
	if net.is_open():
		net.send(msg)
	else:
		_online_ask = msg
		ui.set_online_status(status + "
กำลังเชื่อมต่อเซิร์ฟเวอร์ ครั้งแรกอาจรอได้ถึง 1 นาที · CONNECTING")
		net.connect_to_server()


func _on_net_open() -> void:
	if not _online_ask.is_empty():
		net.send(_online_ask)
		_online_ask = {}


func _on_net_closed() -> void:
	if not _online_ask.is_empty():
		_online_ask = {}
		ui.set_online_status("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ รอสักครู่แล้วกดใหม่ (เซิร์ฟเวอร์ฟรีอาจกำลังตื่น) · CAN'T REACH THE SERVER, TRY AGAIN")
	elif online_side >= 0:
		_online_lost("หลุดการเชื่อมต่อ · DISCONNECTED")


func _on_net_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"waiting":
			ui.set_online_status("กำลังหาคู่ต่อสู้… ให้เพื่อนกด สุ่มหาคู่ ด้วยก็ได้ · WAITING FOR AN OPPONENT")
		"room":
			ui.set_online_status("รหัสห้อง  %s  ส่งให้เพื่อนแล้วรอเพื่อนเข้ามา · ROOM CODE" % msg.code)
		"error":
			ui.set_online_status("ไม่พบห้องนี้ · ROOM NOT FOUND" if msg.get("msg") == "no_room" else "ห้องนี้เต็มแล้ว · ROOM IS FULL")
		"start":
			online_side = int(msg.you)
			_picks.assign([-1, -1])
			_open_select("online")
		"pick":
			_picks[1 - online_side] = int(msg.i)
			_try_go()
		"go":
			_start_online(int(msg.seed), int(msg.p0), int(msg.p1), int(msg.delay))
		"ping":
			net.send({"t": "pong", "ts": msg.ts})
		"pong":
			_rtt = lerpf(_rtt, float(Time.get_ticks_msec() - int(msg.ts)), 0.5)
		"rematch":
			_vote_rematch(1 - online_side)
		"reselect":
			if screen == "vsresult":
				_picks.assign([-1, -1])
				_open_select("online")
		"left":
			_online_lost("คู่ต่อสู้ออกจากเกม · YOUR OPPONENT LEFT")
		_:
			if online:
				online.on_message(msg)


## The left player starts the match once both elephants are picked; the delay covers the round trip.
func _try_go() -> void:
	if online_side != 0 or _picks[0] < 0 or _picks[1] < 0:
		return
	var delay := clampi(ceili(_rtt / 2.0 / 16.7) + 2, 3, 12)
	var seed_v := randi() % 100000
	net.send({"t": "go", "seed": seed_v, "p0": _picks[0], "p1": _picks[1], "delay": delay})
	_start_online(seed_v, _picks[0], _picks[1], delay)


func _start_online(seed_v: int, p0: int, p1: int, delay: int) -> void:
	player1 = roster[p0]
	player2 = roster[p1]
	if player2 == player1:
		player2 = _alt_colors(player1)
	_begin("online", seed_v % Backdrop.SCENES.size())
	online = OnlineMatch.new(net, duel, online_side, delay)
	_online_menu = false


func _vote_rematch(who: int) -> void:
	_votes[who] = true
	if screen == "vsresult" and not (_votes[0] and _votes[1]):
		ui.set_share_msg("รอคู่ต่อสู้กดแมตช์ใหม่… · WAITING FOR OPPONENT" if who == online_side else "คู่ต่อสู้อยากเล่นอีกตา! · REMATCH?")
	if _votes[0] and _votes[1] and online_side == 0:
		_try_go()


func _set_online_menu(open: bool) -> void:
	_online_menu = open
	if online:
		online.muted = open
	if screen == "fight":
		ui.show_screen("pause" if open else "fight")


func _online_lost(why: String) -> void:
	online = null
	online_side = -1
	_online_menu = false
	net.close()
	_open_online(why)


func _leave_online() -> void:
	if online_side >= 0 or net.is_open():
		net.send({"t": "leave"})
		net.close()
	online = null
	online_side = -1
	_online_menu = false
	_online_ask = {}


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
