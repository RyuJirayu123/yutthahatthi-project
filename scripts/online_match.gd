class_name OnlineMatch
extends RefCounted
## Rollback netcode for one online match. Both players run the same deterministic Duel at a fixed
## 60 ticks a second; each player's input is scheduled `delay` ticks ahead (a couple of frames)
## and sent to the other. When the other player's input for a tick hasn't arrived yet, the game
## guesses it (the same directions still held, no new button) and carries on, so your own elephant
## answers at once whatever the ping. When the real input arrives and differs from the guess, the
## duel is put back to the state saved before that tick and re-simulated with the right inputs.
## Inputs only matter while a round is fought, and a knockout is always confirmed long before the
## next round starts, so a wrong guess can never end a round or the match for real.
## Every second the left player sends a hash of a confirmed state; if the right player's differs,
## the left player's state is copied over.

const TICK := 1.0 / 60.0
const HASH_EVERY := 60
const MAX_ROLLBACK := 10       ## ticks the game may run ahead of the other player's inputs
const KEEP := 300              ## ticks of input history kept
## [action suffix, bit]: held directions, then buttons pressed this tick
const BITS := [["left", 1], ["right", 2], ["up", 4], ["down", 8],
	["light", 16], ["medium", 32], ["heavy", 64], ["special", 128]]
const HELD := 15               ## the direction bits: a guess keeps them, never repeats a button
const SKIP := ["def", "ai", "ctrl"]

static var _fprops := PackedStringArray()   ## Fighter's script variables, saved for rollback

var net: Net
var duel: Duel
var side: int                  ## 0 = left elephant (host), 1 = right
var delay: int
var active := true             ## false once the match is over
var muted := false             ## local controls ignored (menu open)
var tick := 0                  ## next tick to simulate
var stalled := 0.0             ## seconds waiting for the other player's input
var resyncs := 0
var rollbacks := 0             ## ticks re-simulated after a wrong guess
var _inputs := [{}, {}]        ## side -> {tick: bits}, real inputs only
var _guess := {}               ## tick -> the other player's bits guessed when it was simulated
var _states := {}              ## tick -> state saved just before simulating it
var _confirmed := 0            ## all of the other player's inputs before this tick have arrived
var _redo_from := 1 << 30      ## earliest tick simulated with a wrong guess
var _sent := 0
var _presses := 0
var _acc := 0.0
var _hashed := 0               ## last tick whose confirmed state was hashed
var _hashes := {}              ## tick -> my hash (right player)
var _their_hashes := {}        ## tick -> left player's hash (right player)
var _asked := false
var _remote_tick := 0          ## the other player's tick when it sent its latest input
var _remote_adv := 0           ## how far ahead of us the other player sees itself
var _wait_cool := 0


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
	if _redo_from < tick:
		_rollback(_redo_from)
	_redo_from = 1 << 30
	_acc = minf(_acc + delta, TICK * 8.0)
	var blocked := false
	while _acc >= TICK:
		while _sent <= tick + delay:
			var bits := _sample()
			_inputs[side][_sent] = bits
			net.send({"t": "in", "f": _sent, "i": bits, "k": tick, "a": tick - _remote_tick})
			_sent += 1
		if not _inputs[1 - side].has(tick) and tick - _confirmed >= MAX_ROLLBACK:
			blocked = true       # too far ahead of the other player: wait for its inputs
			break
		_acc -= TICK
		if _hold_back():
			continue
		_step()
	stalled = stalled + delta if blocked else 0.0
	duel.net_wait = stalled
	_hash_confirmed()
	var oldest := mini(_confirmed, tick) - 2
	for t in _states.keys():
		if t < oldest:
			_states.erase(t)


## Running ahead of the other player makes us guess further; skip a tick now and then so the
## two clocks stay level.
func _hold_back() -> bool:
	_wait_cool -= 1
	var skew := (tick - _remote_tick - _remote_adv) / 2
	if skew >= 2 and _wait_cool <= 0:
		_wait_cool = 12
		return true
	return false


func _step() -> void:
	_states[tick] = snapshot()
	var other := 1 - side
	var theirs: int
	if _inputs[other].has(tick):
		theirs = _inputs[other][tick]
		_guess.erase(tick)
	else:
		theirs = (_inputs[other].get(_confirmed - 1, 0) as int) & HELD
		_guess[tick] = theirs
	var bits := [0, 0]
	bits[side] = _inputs[side][tick]
	bits[other] = theirs
	duel.injected = [_unpack(bits[0]), _unpack(bits[1])]
	duel.update(TICK)
	tick += 1
	_inputs[0].erase(tick - KEEP)
	_inputs[1].erase(tick - KEEP)


## Back to the state before tick `from`, then forward again to where we were, silently.
func _rollback(from: int) -> void:
	if not _states.has(from):
		return
	var target := tick
	_restore(_states[from])
	tick = from
	_resim_to(target)
	rollbacks += target - from


func _resim_to(target: int) -> void:
	var quiet := Sfx.quiet
	Sfx.quiet = true
	duel.replaying = true
	while tick < target:
		_step()
	duel.replaying = false
	Sfx.quiet = quiet


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
			var f := int(msg.f)
			var bits := int(msg.i)
			var other := 1 - side
			_inputs[other][f] = bits
			while _inputs[other].has(_confirmed):
				_confirmed += 1
			_remote_tick = maxi(_remote_tick, int(msg.get("k", 0)))
			_remote_adv = int(msg.get("a", 0))
			if _guess.has(f):
				if _guess[f] != bits:
					_redo_from = mini(_redo_from, f)
				_guess.erase(f)
		"h":
			_their_hashes[int(msg.f)] = int(msg.h)
			_check(int(msg.f))
		"resync":
			if side == 0:
				# the newest state that no guess went into (or the live one if that's gone)
				var at := mini(_confirmed, tick)
				var s: Dictionary
				if at < tick and _states.has(at):
					s = _states[at]
				else:
					at = tick
					s = snapshot()
				net.send({"t": "snap", "f": at, "s": var_to_str(s)})
		"snap":
			if side == 1:
				_apply_snapshot(int(msg.f), str_to_var(str(msg.s)))


# ---------- desync check ----------

## Hash every HASH_EVERY-th state once nothing guessed went into it.
func _hash_confirmed() -> void:
	while _hashed + HASH_EVERY < tick and _hashed + HASH_EVERY <= _confirmed:
		_hashed += HASH_EVERY
		if not _states.has(_hashed):
			continue
		var h := _hash_of(_states[_hashed])
		if side == 0:
			net.send({"t": "h", "f": _hashed, "h": h})
		else:
			_hashes[_hashed] = h
			_check(_hashed)


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


## Hash of the live duel (tests compare the two players' at the end of a match).
func state_hash() -> int:
	return _hash_of(snapshot())


static func _hash_of(s: Dictionary) -> int:
	var d: Array = s.duel
	var parts := [d[0], snappedf(d[1], 0.001), snappedf(d[2], 0.001), d[6], d[7]]
	for f: Dictionary in s.fighters:
		parts.append([snappedf(f.x, 0.01), snappedf(f.y, 0.01), snappedf(f.hp, 0.01), snappedf(f.meter, 0.01),
			snappedf(f.balance, 0.01), f.atk, snappedf(f.atk_t, 0.001), snappedf(f.stun, 0.001), f.face])
	return str(parts).hash()


# ---------- saved states ----------

func snapshot() -> Dictionary:
	if _fprops.is_empty():
		for p in duel.fighters[0].get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in SKIP:
				_fprops.append(p.name)
	var fs := []
	for f in duel.fighters:
		var d := {}
		for n in _fprops:
			var v = f.get(n)
			d[n] = v.duplicate(true) if v is Array or v is Dictionary else v
		fs.append(d)
	var waves := []
	for w in duel.waves:
		waves.append([w.x, w.dir, duel.fighters.find(w.owner), w.traveled, w.hit])
	return {"fighters": fs, "waves": waves,
		"duel": [duel.phase, duel.t, duel.timer, duel.belled, duel.reason, duel.round_winner, duel.round_no,
			duel.wins.duplicate(), duel.hitstop, duel.super_t, duel.super_ex, duel.fighters.find(duel.super_f)]}


func _restore(s: Dictionary) -> void:
	for k in 2:
		var fd: Dictionary = s.fighters[k]
		for key in fd:
			var v = fd[key]
			duel.fighters[k].set(key, v.duplicate(true) if v is Array or v is Dictionary else v)
	duel.waves.clear()
	for w in s.waves:
		var nw := Duel.Wave.new()
		nw.x = w[0]; nw.dir = w[1]; nw.owner = duel.fighters[w[2]]; nw.traveled = w[3]; nw.hit = w[4]
		duel.waves.append(nw)
	var d: Array = s.duel
	duel.phase = d[0]; duel.t = d[1]; duel.timer = d[2]; duel.belled = d[3]; duel.reason = d[4]
	duel.round_winner = d[5]; duel.round_no = d[6]; duel.wins.assign(d[7]); duel.hitstop = d[8]
	duel.super_t = d[9]; duel.super_ex = d[10]; duel.super_f = duel.fighters[d[11]] if d[11] >= 0 else null


## Right player: take the left player's confirmed state for tick `at`, then catch back up.
func _apply_snapshot(at: int, s) -> void:
	if not s is Dictionary:
		return
	var target := maxi(tick, at)
	_restore(s)
	tick = at
	_states.clear()
	_guess.clear()
	_resim_to(target)
	_sent = maxi(_sent, tick)
	resyncs += 1
	_asked = false
