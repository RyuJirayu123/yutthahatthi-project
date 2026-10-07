class_name Net
extends Node
## WebSocket link to the online relay (server/relay.js). Sends and receives small JSON messages;
## the relay pairs two players and forwards everything between them.

signal opened
signal message(msg: Dictionary)
signal closed

## The relay's address. Set it in Project Settings > Online > Server Url (see README).
const SETTING := "online/server_url"
const LOCAL := "ws://localhost:8080"

var _ws: WebSocketPeer
var _was_open := false


static func server_url() -> String:
	var url := str(ProjectSettings.get_setting(SETTING, ""))
	var env := OS.get_environment("ELEPHANT_SERVER")
	if env != "":
		url = env
	return url if url != "" else LOCAL


func connect_to_server() -> void:
	close()
	_ws = WebSocketPeer.new()
	_was_open = false
	if _ws.connect_to_url(server_url()) != OK:
		_ws = null
		closed.emit.call_deferred()


## Free hosting puts the server to sleep when nobody plays; poke it over HTTP as soon as the
## online screen opens so it is awake by the time the player picks a match type.
func wake() -> void:
	var url := server_url().replace("wss://", "https://").replace("ws://", "http://")
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b) -> void: req.queue_free())
	if req.request(url) != OK:
		req.queue_free()


func is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		_ws.send_text(JSON.stringify(msg))


func close() -> void:
	if _ws:
		_ws.close()
		_ws = null
	_was_open = false


## Polled every frame (also while the game is paused) so messages never pile up.
func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				opened.emit()
			while _ws != null and _ws.get_available_packet_count() > 0:   # a handler may close us
				var data = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if data is Dictionary:
					message.emit(data)
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			_was_open = false
			closed.emit()
