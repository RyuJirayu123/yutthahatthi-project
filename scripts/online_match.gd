class_name OnlineMatch
extends RefCounted
## Lockstep netcode for one online match. Both players run the same Duel at a fixed 60 ticks
## a second; each player's input is scheduled `delay` ticks ahead and sent to the other, and a
## tick is only simulated once both inputs for it are in. Every second the left player sends a
## hash of the state; if the right player's differs, the left player's state is copied over.

const TICK := 1.0 / 60.0
const HASH_EVERY := 60
const KEEP := 300              ## ticks of input history kept for re-simulating after a resync
## [action suffix, bit]: held directions, then buttons pressed this tick
const BITS := [["left", 1], ["right", 2], ["up", 4], ["down", 8],
	["light", 16], ["medium", 32], ["heavy", 64], ["special", 128]]

var net: Net
var duel: Duel
var side: int                  ## 0 = left elephant (host), 1 = right
var delay: int
var active := true             ## false once the match is over
var muted := false             ## local controls ignored (menu open)
var tick := 0                  ## next tick to simulate
var stalled := 0.0             ## seconds waiting for the other player's input
var resyncs := 0
var _inputs := [{}, {}]        ## side -> {tick: bits}
var _sent := 0
var _presses := 0
var _acc := 0.0
var _hashes := {}              ## tick -> my hash (right player)
var _their_hashes := {}        ## tick -> left player's hash (right player)
var _asked := false


func _init(p_net: Net, p_duel: Duel, p_side: int, p_delay: int) -> void:
	net = p_net
	duel = p_duel
	side = p_side
	delay = p_delay
	for f in duel.fighters:
		f.ctrl = "net"


## A button was pressed this frame (from Main's input polling).
func press(action: String) -> void:
	for b in BITS:
		if action == b[0]:
			_presses |= b[1]


func update(delta: float) -> void:
	if not active:
		return
	_acc = minf(_acc + delta, TICK * 6.0)
	var waited := true
	while _acc >= TICK:
		while _sent <= tick + delay:
			var bits := _sample()
			_inputs[side][_sent] = bits
			net.send({"t": "in", "f": _sent, "i": bits})
			_sent += 1
		if not _inputs[1 - side].has(tick):
			break
		waited = false
		_step()
		_acc -= TICK
	stalled = 0.0 if not waited else stalled + delta
	duel.net_wait = stalled


func _step() -> void:
	duel.injected = [_unpack(_inputs[0][tick]), _unpack(_inputs[1][tick])]
	duel.update(TICK)
	tick += 1
	_inputs[0].erase(tick - KEEP)
	_inputs[1].erase(tick - KEEP)
	if tick % HASH_EVERY == 0:
		var h := state_hash()
		if side == 0:
			net.send({"t": "h", "f": tick, "h": h})
		else:
			_hashes[tick] = h
			_check(tick)


func _sample() -> int:
	var bits := 0
	if not muted:
		for i in 4:
			if Input.is_action_pressed("p1_" + BITS[i][0]):
				bits |= BITS[i][1]
		bits |= _presses
	_presses = 0
	return bits


static func _unpack(bits: int) -> Dictionary:
	var d := {}
	for b in BITS:
		d[b[0]] = bits & b[1] != 0
	return d


func on_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"in":
			_inputs[1 - side][int(msg.f)] = int(msg.i)
		"h":
			_their_hashes[int(msg.f)] = int(msg.h)
			_check(int(msg.f))
		"resync":
			if side == 0:
				net.send({"t": "snap", "f": tick, "s": var_to_str(snapshot())})
		"snap":
			if side == 1:
				_apply_snapshot(int(msg.f), str_to_var(str(msg.s)))


## Right player: compare our hash with the left player's for the same tick.
func _check(t: int) -> void:
	if side != 1 or not _hashes.has(t) or not _their_hashes.has(t):
		return
	var same: bool = _hashes[t] == _their_hashes[t]
	_hashes.erase(t)
	_their_hashes.erase(t)
	if not same and not _asked:
		_asked = true
		net.send({"t": "resync"})


func state_hash() -> int:
	var parts := [duel.phase, snappedf(duel.t, 0.001), snappedf(duel.timer, 0.001), duel.round_no, duel.wins]
	for f in duel.fighters:
		parts.append([snappedf(f.x, 0.01), snappedf(f.y, 0.01), snappedf(f.hp, 0.01), snappedf(f.meter, 0.01),
			snappedf(f.balance, 0.01), f.atk, snappedf(f.atk_t, 0.001), snappedf(f.stun, 0.001), f.face])
	return str(parts).hash()


# ---------- resync ----------

const SKIP := ["def", "ai", "ctrl"]

func snapshot() -> Dictionary:
	var fs := []
	for f in duel.fighters:
		var d := {}
		for p in f.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in SKIP:
				d[p.name] = f.get(p.name)
		fs.append(d)
	var waves := []
	for w in duel.waves:
		waves.append([w.x, w.dir, duel.fighters.find(w.owner), w.traveled, w.hit])
	var spouts := []
	for s in duel.spouts:
		spouts.append([s.x, s.y, s.dir, duel.fighters.find(s.owner), s.traveled, s.done])
	return {"fighters": fs, "waves": waves, "spouts": spouts,
		"duel": [duel.phase, duel.t, duel.timer, duel.belled, duel.reason, duel.round_winner, duel.round_no,
			duel.wins.duplicate(), duel.hitstop, duel.super_t, duel.super_ex, duel.fighters.find(duel.super_f)]}


func _apply_snapshot(at: int, s) -> void:
	if not s is Dictionary:
		return
	for k in 2:
		for key in s.fighters[k]:
			duel.fighters[k].set(key, s.fighters[k][key])
	duel.waves.clear()
	for w in s.waves:
		var nw := Duel.Wave.new()
		nw.x = w[0]; nw.dir = w[1]; nw.owner = duel.fighters[w[2]]; nw.traveled = w[3]; nw.hit = w[4]
		duel.waves.append(nw)
	duel.spouts.clear()
	for sp in s.spouts:
		var ns := Duel.Spout.new()
		ns.x = sp[0]; ns.y = sp[1]; ns.dir = sp[2]; ns.owner = duel.fighters[sp[3]]; ns.traveled = sp[4]; ns.done = sp[5]
		duel.spouts.append(ns)
	var d: Array = s.duel
	duel.phase = d[0]; duel.t = d[1]; duel.timer = d[2]; duel.belled = d[3]; duel.reason = d[4]
	duel.round_winner = d[5]; duel.round_no = d[6]; duel.wins.assign(d[7]); duel.hitstop = d[8]
	duel.super_t = d[9]; duel.super_ex = d[10]; duel.super_f = duel.fighters[d[11]] if d[11] >= 0 else null
	# catch back up to where we were with the inputs we already have
	var target := tick
	tick = at
	while tick < target and _inputs[0].has(tick) and _inputs[1].has(tick):
		_step()
	_sent = maxi(_sent, tick)
	resyncs += 1
	_asked = false
