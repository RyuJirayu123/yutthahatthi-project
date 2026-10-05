extends Node
## Autoload "Sfx": synthesised sound effects, rendered once at startup.
## Same recipes as the WebAudio tones of the original HTML version — no audio files needed.

const RATE := 22050
const MASTER := 0.5

var muted := false
var quiet := false        ## true while the title-screen demo plays

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["select"] = _render([_tone(660, 880, 0.06, "square", 0.06)])
	_streams["whoosh"] = _render([_noise(0.1, 0.25, 1800)])
	_streams["hit"] = _render([_noise(0.14, 0.7, 700), _tone(160, 60, 0.14, "square", 0.16)])
	_streams["heavy"] = _render([_noise(0.24, 0.9, 420), _tone(120, 40, 0.26, "sawtooth", 0.22)])
	_streams["block"] = _render([_tone(1100, 900, 0.07, "square", 0.07), _noise(0.06, 0.4, 3200)])
	_streams["jump"] = _render([_tone(200, 420, 0.12, "triangle", 0.14)])
	_streams["trumpet"] = _render([_trumpet(260)])
	_streams["bell"] = _render([_tone(1046, 1040, 0.6, "sine", 0.22), _tone(1568, 1560, 0.45, "sine", 0.1)])
	_streams["ko"] = _render([_trumpet(220), _noise(0.6, 0.6, 180)])
	_streams["glaive"] = _render([_noise(0.16, 0.3, 1200), _tone(500, 900, 0.12, "triangle", 0.05)])
	_streams["clang"] = _render([_tone(1800, 1700, 0.18, "square", 0.05), _tone(2400, 2300, 0.14, "sine", 0.08), _noise(0.08, 0.5, 2500), _noise(0.14, 0.5, 600)])
	_streams["daze"] = _render([_tone(880, 620, 0.16, "triangle", 0.12), _tone(700, 480, 0.16, "triangle", 0.12, 0.14), _tone(560, 360, 0.22, "triangle", 0.12, 0.28)])
	_streams["roar"] = _render([_trumpet(150), _trumpet(190, 0.05), _noise(0.8, 0.5, 220), _tone(70, 50, 0.8, "sawtooth", 0.12)])
	_streams["quake"] = _render([_noise(0.6, 1.0, 120), _tone(70, 25, 0.6, "sawtooth", 0.3), _noise(0.3, 0.5, 600)])
	_streams["bless"] = _render([_tone(784, 784, 0.4, "sine", 0.1), _tone(988, 988, 0.4, "sine", 0.1, 0.08), _tone(1175, 1175, 0.45, "sine", 0.1, 0.16), _tone(1568, 1568, 0.6, "sine", 0.1, 0.24)])
	_streams["blink"] = _render([_noise(0.18, 0.5, 3000), _tone(300, 1800, 0.12, "sawtooth", 0.05)])
	_streams["finisher"] =_render([_noise(0.45, 0.9, 300), _tone(90, 30, 0.5, "sawtooth", 0.25), _tone(2000, 1900, 0.3, "square", 0.05), _tone(1046, 1040, 0.9, "sine", 0.22, 0.05), _trumpet(300, 0.1)])
	var win := []
	for i in 4:
		var f: float = [523, 659, 784, 1046][i]
		win.append(_tone(f, f, 0.18, "square", 0.07, i * 0.11))
	_streams["win"] = _render(win)
	var lose := []
	for i in 3:
		var f: float = [392, 330, 262][i]
		lose.append(_tone(f, f * 0.98, 0.25, "triangle", 0.12, i * 0.18))
	_streams["lose"] = _render(lose)


## `force` plays even during the demo (menu clicks).
func play(n: String, force := false) -> void:
	if muted or (quiet and not force) or not _streams.has(n):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[n]
	p.play()


# Each voice returns [start_sample, PackedFloat32Array].

func _tone(f0: float, f1: float, dur: float, wave: String, vol: float, delay := 0.0) -> Array:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var fr := maxf(20.0, f1) / f0
	var gr := 0.0001 / vol
	var ph := 0.0
	for i in n:
		var k := minf(1.0, float(i) / RATE / dur)
		ph = fmod(ph + f0 * pow(fr, k) / RATE, 1.0)
		var s: float
		match wave:
			"square": s = 1.0 if ph < 0.5 else -1.0
			"sawtooth": s = 2.0 * ph - 1.0
			"triangle": s = 4.0 * absf(ph - 0.5) - 1.0
			_: s = sin(TAU * ph)
		out[i] = s * vol * pow(gr, k)
	return [int(delay * RATE), out]


func _noise(dur: float, vol: float, freq: float, delay := 0.0) -> Array:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# RBJ band-pass, Q 0.8 (WebAudio "bandpass")
	var w0 := TAU * freq / RATE
	var alpha := sin(w0) / (2.0 * 0.8)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var gr := 0.0001 / vol
	for i in n:
		var x := randf() * 2.0 - 1.0
		var y := b0 * x - b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y * vol * pow(gr, minf(1.0, float(i) / RATE / dur))
	return [int(delay * RATE), out]


## Elephant trumpet: rising sawtooth with vibrato through a low-pass.
func _trumpet(base: float, delay := 0.0) -> Array:
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var w0 := TAU * 2200.0 / RATE
	var alpha := sin(w0) / (2.0 * 0.7071)
	var a0 := 1.0 + alpha
	var b0 := (1.0 - cos(w0)) / 2.0 / a0
	var b1 := (1.0 - cos(w0)) / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float
		if t < 0.12:
			f = lerpf(base, base * 1.9, t / 0.12)
		elif t < 0.75:
			f = lerpf(base * 1.9, base * 1.55, (t - 0.12) / 0.63)
		else:
			f = base * 1.55
		f += sin(TAU * 9.0 * t) * 14.0
		var g: float
		if t < 0.04:
			g = lerpf(0.0001, 0.2, t / 0.04)
		elif t < 0.5:
			g = lerpf(0.2, 0.16, (t - 0.04) / 0.46)
		else:
			g = 0.16 * pow(0.0001 / 0.16, minf(1.0, (t - 0.5) / 0.35))
		ph = fmod(ph + f / RATE, 1.0)
		var x := 2.0 * ph - 1.0
		var y := b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y * g
	return [int(delay * RATE), out]


func _render(voices: Array) -> AudioStreamWAV:
	var total := 0
	for v in voices:
		total = maxi(total, int(v[0]) + (v[1] as PackedFloat32Array).size())
	var mix := PackedFloat32Array()
	mix.resize(total)
	for v in voices:
		var start: int = v[0]
		var data: PackedFloat32Array = v[1]
		for i in data.size():
			mix[start + i] += data[i]
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(mix[i] * MASTER, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
