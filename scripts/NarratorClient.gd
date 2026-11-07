extends Node
## Event bridge to the narrator service. Registered as NarratorClient in project.godot.

signal narration_ready(text: String, audio: AudioStreamMP3, decision: Dictionary)
signal narration_skipped(decision: Dictionary)
signal narrator_error(message: String)

@export var api_url := "http://127.0.0.1:8765/v1/events"
@export var auto_play_audio := true
@export var heartbeat_interval_seconds := 1.0

var session_id := ""
var _http: HTTPRequest
var _player: AudioStreamPlayer
var _queue: Array[Dictionary] = []
var _busy := false
var _sequence := 0
var _inflight_session_id := ""
var _round_active := false
var _round_game := ""
var _round_started_ms := 0
var _last_action_ms := 0
var _heartbeat_elapsed := 0.0
var _heartbeat_retry_after_ms := 0
var _state_context: Dictionary = {}
var _state_context_updated_ms := 0
var _tracking_source: Node


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_player = AudioStreamPlayer.new()
	add_child(_player)


func _process(delta: float) -> void:
	if not _round_active or session_id.is_empty():
		return
	_heartbeat_elapsed += delta
	if _heartbeat_elapsed < heartbeat_interval_seconds:
		return
	_heartbeat_elapsed = 0.0
	var now_ms := Time.get_ticks_msec()
	if now_ms < _heartbeat_retry_after_ms:
		return
	var context := {
		"elapsed_seconds": floori(float(now_ms - _round_started_ms) / 1000.0),
		"idle_seconds": floori(float(now_ms - _last_action_ms) / 1000.0),
	}
	if now_ms - _state_context_updated_ms <= 5000:
		context.merge(_state_context, true)
	if is_instance_valid(_tracking_source) and _tracking_source.has_method("tracking_context"):
		context.merge(_tracking_source.tracking_context(), true)
	post_event({"game": _round_game, "kind": "state", "context": context})


func register_tracking_source(source: Node) -> void:
	_tracking_source = source


func unregister_tracking_source(source: Node) -> void:
	if _tracking_source == source:
		_tracking_source = null


func begin_round(round_id: String, game_name: String, context: Dictionary = {}) -> void:
	if _busy:
		_http.cancel_request()
		_busy = false
	_queue.clear()
	_player.stop()
	session_id = round_id
	_round_active = true
	_round_game = game_name
	_round_started_ms = Time.get_ticks_msec()
	_last_action_ms = _round_started_ms
	_heartbeat_elapsed = 0.0
	_state_context = {}
	_state_context_updated_ms = 0
	post_event({"game": game_name, "kind": "round_started", "context": context})


func update_round_state(game_name: String, facts: Dictionary) -> void:
	## Call from game logic as timer, lives, strikes, or current module change.
	_round_game = game_name
	_state_context.merge(facts, true)
	_state_context_updated_ms = Time.get_ticks_msec()


func send_result(game_name: String, correct: bool, action: String = "", context: Dictionary = {}) -> void:
	_last_action_ms = Time.get_ticks_msec()
	update_round_state(game_name, context)
	post_event({
		"game": game_name,
		"kind": "result",
		"result": "correct" if correct else "wrong",
		"action": action,
		"context": context,
	})


func report_uncertainty(reason: String, context: Dictionary = {}) -> void:
	if not _round_active:
		return
	var details := context.duplicate(true)
	details["uncertainty_reason"] = reason
	post_event({"game": _round_game, "kind": "uncertainty", "context": details})


func end_round(game_name: String, context: Dictionary = {}) -> void:
	if not _round_active:
		return
	post_event({"game": game_name, "kind": "game_ended", "context": context})
	_round_active = false


func post_event(event: Dictionary) -> void:
	if session_id.is_empty():
		narrator_error.emit("Call begin_round before posting narrator events")
		return
	_sequence += 1
	var payload := event.duplicate(true)
	var kind := str(payload.get("kind", ""))
	if kind != "state":
		_round_game = str(payload.get("game", _round_game))
	if kind != "state" and kind != "round_started":
		var observed_context := {}
		if Time.get_ticks_msec() - _state_context_updated_ms <= 5000:
			observed_context.merge(_state_context, true)
		if is_instance_valid(_tracking_source) and _tracking_source.has_method("tracking_context"):
			observed_context.merge(_tracking_source.tracking_context(), true)
		observed_context.merge(payload.get("context", {}), true)
		payload["context"] = observed_context
	if kind in ["result", "action", "inspection_request", "inspection_result"]:
		_last_action_ms = Time.get_ticks_msec()
	if kind == "state":
		for i in range(_queue.size() - 1, -1, -1):
			if _queue[i].get("kind") == "state":
				_queue.remove_at(i)
	elif kind in ["result", "uncertainty", "game_ended"]:
		for i in range(_queue.size() - 1, -1, -1):
			if _queue[i].get("kind") == "state":
				_queue.remove_at(i)
	payload["session_id"] = session_id
	payload["event_id"] = str(Time.get_ticks_usec()) + "-" + str(_sequence)
	if kind == "game_ended":
		_queue.clear()
		if _busy:
			_http.cancel_request()
			_busy = false
		_player.stop()
	payload["queued_at_ms"] = Time.get_ticks_msec()
	_queue.append(payload)
	_send_next()


func _send_next() -> void:
	if _busy or _queue.is_empty():
		return
	var payload: Dictionary = _queue.pop_front()
	if Time.get_ticks_msec() - int(payload.get("queued_at_ms", 0)) > 8000:
		_send_next()
		return
	payload.erase("queued_at_ms")
	_busy = true
	_inflight_session_id = str(payload.get("session_id", ""))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_busy = false
		_heartbeat_retry_after_ms = Time.get_ticks_msec() + 10000
		narrator_error.emit("Could not send event to narrator API: " + str(error))
		_send_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if _inflight_session_id != session_id:
		_send_next()
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_heartbeat_retry_after_ms = Time.get_ticks_msec() + 10000
		narrator_error.emit("Narrator HTTP request failed: " + str(result))
		_send_next()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		narrator_error.emit("Narrator sent invalid JSON")
		_send_next()
		return
	if response_code != 200:
		_heartbeat_retry_after_ms = Time.get_ticks_msec() + 10000
		narrator_error.emit("Narrator HTTP " + str(response_code) + ": " + str(parsed.get("error", "unknown error")))
		_send_next()
		return
	if parsed.get("say", false):
		var mp3_bytes := Marshalls.base64_to_raw(str(parsed.get("audio_base64", "")))
		var audio := AudioStreamMP3.load_from_buffer(mp3_bytes)
		if audio == null:
			narrator_error.emit("Narrator audio was not a valid MP3")
		else:
			narration_ready.emit(str(parsed.get("text", "")), audio, parsed)
			if auto_play_audio:
				_player.stream = audio
				_player.play()
	else:
		narration_skipped.emit(parsed)
	_send_next()
