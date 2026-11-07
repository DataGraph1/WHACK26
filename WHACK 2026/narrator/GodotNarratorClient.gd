extends Node
## Godot 4.4+ API adapter. Add this script as an Autoload named NarratorClient.

signal narration_ready(text: String, audio: AudioStreamWAV, decision: Dictionary)
signal narration_skipped(decision: Dictionary)
signal narrator_error(message: String)

@export var api_url := "http://127.0.0.1:8765/v1/events"

var session_id := ""
var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _busy := false
var _sequence := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func begin_round(round_id: String, game_name: String, context: Dictionary = {}) -> void:
	session_id = round_id
	post_event({"game": game_name, "kind": "round_started", "context": context})


func send_result(game_name: String, correct: bool, action: String = "", context: Dictionary = {}) -> void:
	post_event({
		"game": game_name,
		"kind": "result",
		"result": "correct" if correct else "wrong",
		"action": action,
		"context": context,
	})


func post_event(event: Dictionary) -> void:
	if session_id.is_empty():
		narrator_error.emit("Call begin_round before posting narrator events")
		return
	_sequence += 1
	var payload := event.duplicate(true)
	payload["session_id"] = session_id
	payload["event_id"] = str(Time.get_ticks_usec()) + "-" + str(_sequence)
	_queue.append(payload)
	_send_next()


func _send_next() -> void:
	if _busy or _queue.is_empty():
		return
	var payload: Dictionary = _queue.pop_front()
	_busy = true
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http.request(api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_busy = false
		narrator_error.emit("Could not send event to narrator API: " + str(error))
		_send_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		narrator_error.emit("Narrator HTTP request failed: " + str(result))
		_send_next()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		narrator_error.emit("Narrator sent invalid JSON")
		_send_next()
		return
	if response_code != 200:
		narrator_error.emit("Narrator HTTP " + str(response_code) + ": " + str(parsed.get("error", "unknown error")))
		_send_next()
		return
	if parsed.get("say", false):
		var wav_bytes := Marshalls.base64_to_raw(str(parsed.get("audio_base64", "")))
		var audio := AudioStreamWAV.load_from_buffer(wav_bytes)
		if audio == null:
			narrator_error.emit("Narrator audio was not a valid WAV")
		else:
			narration_ready.emit(str(parsed.get("text", "")), audio, parsed)
	else:
		narration_skipped.emit(parsed)
	_send_next()
