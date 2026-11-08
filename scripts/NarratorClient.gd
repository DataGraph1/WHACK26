extends Node
## Event bridge to the narrator service. Registered as NarratorClient in project.godot.

signal event_observed(event: Dictionary)

signal narration_ready(text: String, audio: AudioStreamMP3, decision: Dictionary)
signal narration_skipped(decision: Dictionary)
signal narrator_error(message: String)

@export var api_url := "http://127.0.0.1:8765/v1/events"
@export var auto_play_audio := true
@export var heartbeat_interval_seconds := 1.0
const EXPECTED_API_VERSION := 4

var session_id := ""
var _http: HTTPRequest
var _health_http: HTTPRequest
var _player: AudioStreamPlayer
var _queue: Array[Dictionary] = []
var _busy := false
var _api_ready := false
var _voice_key_present := false
var _model_ready := false
var _health_busy := false
var _health_elapsed := 0.0
var _health_failures := 0
var _start_attempted := false
var _owned_api_pid := -1
var _inflight_payload: Dictionary = {}
var _inflight_started_ms := 0
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
	_http.timeout = 70.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_health_http = HTTPRequest.new()
	_health_http.timeout = 1.5
	add_child(_health_http)
	_health_http.request_completed.connect(_on_health_completed)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	call_deferred("_check_api_health")


func _exit_tree() -> void:
	if _owned_api_pid > 0:
		OS.kill(_owned_api_pid)


func is_api_ready() -> bool:
	return _api_ready


func is_voice_key_present() -> bool:
	return _voice_key_present


func is_model_ready() -> bool:
	return _model_ready


func _check_api_health() -> void:
	if _health_busy:
		return
	_health_busy = _health_http.request(api_url.replace("/v1/events", "/health")) == OK


func _on_health_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_health_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var health = JSON.parse_string(body.get_string_from_utf8())
		if typeof(health) != TYPE_DICTIONARY or int(health.get("api_version", -1)) != EXPECTED_API_VERSION:
			_api_ready = false
			_voice_key_present = false
			_model_ready = false
			if _health_failures != 5:
				_health_failures = 5
				narrator_error.emit("Old narrator service on port 8765. Stop it, then run launch.py.")
			return
		_api_ready = true
		_voice_key_present = bool(health.get("elevenlabs_key_present", false))
		_model_ready = bool(health.get("text_model_ready", false))
		_health_failures = 0
		_send_next()
		return
	_health_failures += 1
	_api_ready = false
	_voice_key_present = false
	_model_ready = false
	if not _start_attempted and DisplayServer.get_name() != "headless" and \
			(api_url.begins_with("http://127.0.0.1:") or api_url.begins_with("http://localhost:")):
		_start_attempted = true
		var project_dir := ProjectSettings.globalize_path("res://")
		var python_relative := ".venv/Scripts/python.exe" if OS.get_name() == "Windows" else ".venv/bin/python"
		var python_path := project_dir.path_join(python_relative)
		var script_path := project_dir.path_join("narrator/agent_api.py")
		if FileAccess.file_exists(python_path) and FileAccess.file_exists(script_path):
			_owned_api_pid = OS.create_process(python_path, PackedStringArray([script_path]))
			narrator_error.emit("Starting local narrator service...")
		else:
			narrator_error.emit("Narrator setup missing. Install .venv, then run launch.py.")
	elif _health_failures == 5:
		narrator_error.emit("Narrator API unavailable. Start Ollama and run launch.py.")


func _process(delta: float) -> void:
	_health_elapsed += delta
	if _health_elapsed >= (10.0 if _api_ready else 1.0):
		_health_elapsed = 0.0
		_check_api_health()
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
	_player.stream = null
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
	if game_name != "bomb":
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


func cancel_round() -> void:
	## A restart abandons this round without narrating a stale outcome.
	_round_active = false
	session_id = ""
	_queue.clear()
	if _busy:
		_http.cancel_request()
		_busy = false
	_player.stop()
	_player.stream = null


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
	if kind in ["result", "action", "pending_action", "inspection_request", "inspection_result"]:
		_last_action_ms = Time.get_ticks_msec()
	if kind == "state":
		for i in range(_queue.size() - 1, -1, -1):
			if _queue[i].get("kind") == "state":
				_queue.remove_at(i)
	elif kind in ["result", "uncertainty", "game_ended", "pending_action", "target_locked", "link_contact"]:
		for i in range(_queue.size() - 1, -1, -1):
			var queued_kind := str(_queue[i].get("kind", ""))
			if queued_kind == "state" or (kind in ["result", "pending_action", "target_locked"] and queued_kind in ["focus", "pending_action", "target_locked"]) or (kind == "link_contact" and queued_kind == "link_stabilizing"):
				_queue.remove_at(i)
	event_observed.emit(payload.duplicate(true))
	payload["session_id"] = session_id
	payload["event_id"] = str(Time.get_ticks_usec()) + "-" + str(_sequence)
	if kind == "game_ended":
		_queue.clear()
		if _busy:
			_http.cancel_request()
			_busy = false
		_player.stop()
		_player.stream = null
	payload["queued_at_ms"] = Time.get_ticks_msec()
	_queue.append(payload)
	_send_next()


func _send_next() -> void:
	if _busy or not _api_ready or _queue.is_empty():
		return
	var payload: Dictionary = _queue.pop_front()
	if Time.get_ticks_msec() - int(payload.get("queued_at_ms", 0)) > 12000:
		narration_skipped.emit({"trigger": payload.get("kind", "event"),
			"decision_source": "expired", "reason": "Queued event expired before API processing",
			"round_trip_ms": Time.get_ticks_msec() - int(payload.get("queued_at_ms", 0))})
		_send_next()
		return
	payload.erase("queued_at_ms")
	_inflight_payload = payload.duplicate(true)
	_busy = true
	_inflight_started_ms = Time.get_ticks_msec()
	_inflight_session_id = str(payload.get("session_id", ""))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_busy = false
		_api_ready = false
		_voice_key_present = false
		_model_ready = false
		payload["queued_at_ms"] = Time.get_ticks_msec()
		_queue.push_front(payload)
		narrator_error.emit("Narrator connection failed; reconnecting (" + str(error) + ")")
		_check_api_health()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if _inflight_session_id != session_id:
		_send_next()
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_api_ready = false
		_voice_key_present = false
		_model_ready = false
		var retry := _inflight_payload.duplicate(true)
		retry["queued_at_ms"] = Time.get_ticks_msec()
		_queue.push_front(retry)
		narrator_error.emit("Narrator HTTP connection lost; reconnecting (" + str(result) + ")")
		_check_api_health()
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
	parsed["round_trip_ms"] = Time.get_ticks_msec() - _inflight_started_ms
	if parsed.get("trigger") == "focus" and not _focus_is_current(
			str(parsed.get("observed_target", "")), str(parsed.get("game", ""))):
		parsed["reason"] = "Player moved off the observed target before narration returned"
		parsed["decision_source"] = "stale"
		narration_skipped.emit(parsed)
		_send_next()
		return
	if parsed.get("trigger") == "pending_action" and not _pending_is_current(str(parsed.get("observed_pending_id", ""))):
		parsed["reason"] = "Queued action changed or was confirmed before narration returned"
		parsed["decision_source"] = "stale"
		narration_skipped.emit(parsed)
		_send_next()
		return
	if parsed.get("trigger") == "target_locked" and (not is_instance_valid(Bridge.selected_target)
			or Bridge.selected_target.get_instance_id() != int(parsed.get("observed_target_id", 0))):
		parsed["reason"] = "Target lock changed before narration returned"
		parsed["decision_source"] = "stale"
		narration_skipped.emit(parsed)
		_send_next()
		return
	if parsed.get("say", false):
		var audio: AudioStreamMP3 = null
		var encoded := str(parsed.get("audio_base64", ""))
		if not encoded.is_empty():
			audio = AudioStreamMP3.load_from_buffer(Marshalls.base64_to_raw(encoded))
		narration_ready.emit(str(parsed.get("text", "")), audio, parsed)
		if auto_play_audio and audio != null:
			_player.stream = audio
			_player.play()
	else:
		narration_skipped.emit(parsed)
	_send_next()


func _focus_is_current(target_name: String, game_name: String) -> bool:
	if target_name.is_empty() or not is_instance_valid(_tracking_source):
		return false
	if not _tracking_source.has_method("target_at"):
		return false
	if _tracking_source == Bridge and Bridge.using_camera() and (
			not Bridge.cursor_visible or Bridge.pointer_confidence < 0.65):
		return false
	var current = _tracking_source.target_at()
	if not is_instance_valid(current) or str(current.get_meta("desc", "")) != target_name:
		return false
	var module = current.get_meta("module", null)
	var current_game: String = module.title() if module is BombModule else "bomb"
	return current_game == game_name


func _pending_is_current(pending_id: String) -> bool:
	return not pending_id.is_empty() and not Bridge.pending.is_empty() and str(Bridge.pending.get("id", "")) == pending_id
