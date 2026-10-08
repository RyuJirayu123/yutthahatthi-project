class_name Controls
extends RefCounted
## Keyboard keys the players can change on the Controls screen (วิธีเล่น → ตั้งปุ่ม).
## Changes are saved to user://controls.cfg (the browser keeps it too) and applied to the
## InputMap when the game starts; gamepad buttons are left as they are. A key that is already
## used by another action swaps over to it, so two actions never share a key.

const FILE := "user://controls.cfg"
## Rebindable actions of each player, in screen order: [suffix, Thai, English]
const ACTIONS := [
	["left", "เดินซ้าย", "LEFT"], ["right", "เดินขวา", "RIGHT"], ["up", "กระโดด", "JUMP"],
	["down", "ย่อ · ป้องกัน", "CROUCH · GUARD"], ["light", "งวงรัว · ระยะสั้น", "TRUNK FLURRY"],
	["medium", "ขาตวัด · ระยะกลาง", "FORELEG SWIPE"], ["heavy", "พุ่งชน", "CHARGE"],
	["special", "อัลติ", "ULTIMATE"],
]
## Default key letters written in help texts -> the action whose current key replaces them.
## Player 2's arrows are only keys on the controls lists (elsewhere they mean directions).
const TOKENS := {
	1: {"A": "left", "D": "right", "W": "up", "S": "down", "F": "light", "R": "medium", "G": "heavy", "H": "special"},
	2: {",": "light", "L": "medium", ".": "heavy", "/": "special"},
}
const SYMBOLS := {
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓", KEY_COMMA: ",", KEY_PERIOD: ".",
	KEY_SLASH: "/", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_MINUS: "-", KEY_EQUAL: "=", KEY_BACKSLASH: "\\", KEY_QUOTELEFT: "`", KEY_SPACE: "SPACE",
	KEY_ENTER: "ENTER", KEY_KP_ENTER: "NUM ENT", KEY_SHIFT: "SHIFT", KEY_CTRL: "CTRL", KEY_ALT: "ALT",
	KEY_TAB: "TAB", KEY_BACKSPACE: "BKSP", KEY_CAPSLOCK: "CAPS",
}

static var _defaults := {}     ## action -> its shipped key events (rebindable and confirm actions)
static var _changed := {}      ## action -> physical keycode the player chose
static var _cache := {}        ## resolved help texts
static var _loaded := false


## Read the saved keys once, at startup.
static func setup() -> void:
	if _loaded:
		return
	_loaded = true
	for p in [1, 2]:
		for a in ACTIONS:
			_defaults["p%d_%s" % [p, a[0]]] = _key_events("p%d_%s" % [p, a[0]])
		_defaults["p%d_confirm" % p] = _key_events("p%d_confirm" % p)
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return
	for action in cfg.get_section_keys("keys") if cfg.has_section("keys") else []:
		if _defaults.has(action):
			_assign(action, int(cfg.get_value("keys", action, 0)))


static func actions(player: int) -> Array[String]:
	var out: Array[String] = []
	for a in ACTIONS:
		out.append("p%d_%s" % [player, a[0]])
	return out


## Keys bound to `action`, primary first.
static func keys(action: String) -> Array[int]:
	var out: Array[int] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(_code(e))
	return out


static func key_name(action: String) -> String:
	var k := keys(action)
	return label(k[0]) if not k.is_empty() else "—"


static func label(code: int) -> String:
	if SYMBOLS.has(code):
		return SYMBOLS[code]
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return "NUM %d" % (code - KEY_KP_0)
	return OS.get_keycode_string(code).to_upper()


## Keys the game itself uses (pause, mute, fullscreen, menu confirm with Enter).
static func reserved(code: int) -> bool:
	if code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER:
		return true
	for action in ["pause", "mute", "fullscreen"]:
		if code in keys(action):
			return true
	return false


## Put `code` on `action`; whichever other action had it gets this action's old key.
static func rebind(action: String, code: int) -> void:
	setup()
	var old := keys(action)
	var old_code: int = old[0] if not old.is_empty() else 0
	if code == old_code:
		return
	for p in [1, 2]:
		for other in actions(p):
			if other != action and code in keys(other):
				_assign(other, old_code)
				_changed[other] = old_code
	_assign(action, code)
	_changed[action] = code
	_save()


static func reset() -> void:
	setup()
	for action in _defaults:
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		for e in _defaults[action]:
			InputMap.action_add_event(action, e)
	_changed.clear()
	_cache.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


## Help text with the default key letters swapped for the player's current keys.
## `arrows`: player 2's arrows are keys here (the controls list), not directions.
static func resolve(text: String, player: int, arrows := false) -> String:
	setup()
	var key := "%d%s|%s" % [player, "a" if arrows else "", text]
	if _cache.has(key):
		return _cache[key]
	var map: Dictionary = TOKENS[player].duplicate()
	if arrows and player == 2:
		map.merge({"←": "left", "→": "right", "↑": "up", "↓": "down"})
	var out := ""
	for i in text.length():
		var ch := text[i]
		var alone := (i == 0 or not _is_letter(text[i - 1])) and (i == text.length() - 1 or not _is_letter(text[i + 1]))
		out += key_name("p%d_%s" % [player, map[ch]]) if map.has(ch) and alone else ch
	_cache[key] = out
	return out


static func _is_letter(ch: String) -> bool:
	return (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z")


static func _code(e: InputEventKey) -> int:
	return e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode


static func _key_events(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(e.duplicate())
	return out


## Replace the action's keyboard keys with `code`; menu confirm follows the light attack.
static func _assign(action: String, code: int) -> void:
	var before := keys(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	if code != 0:
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event(action, ev)
	if action.ends_with("_light"):
		var confirm := action.replace("_light", "_confirm")
		for e in InputMap.action_get_events(confirm):
			if e is InputEventKey and _code(e) in before:
				InputMap.action_erase_event(confirm, e)
		if code != 0 and not code in keys(confirm):
			var ce := InputEventKey.new()
			ce.physical_keycode = code as Key
			InputMap.action_add_event(confirm, ce)
	_cache.clear()


static func _save() -> void:
	var cfg := ConfigFile.new()
	for action in _changed:
		cfg.set_value("keys", action, _changed[action])
	cfg.save(FILE)
