extends Node
## Live path: inspected fact -> spoken fact -> model pending decision -> game result.

var bomb: Bomb
var target: Control
var inspection_audio := false
var pending_decided := false
var pending_source := ""
var pending_round_trip_ms := -1
var completed := false

func _ready() -> void:
    NarratorClient.auto_play_audio = false
    NarratorClient.narration_ready.connect(_on_narration)
    NarratorClient.narration_skipped.connect(_on_quiet)
    NarratorClient.narrator_error.connect(func(message: String) -> void: print("API error: ", message))
    NarratorClient.event_observed.connect(func(event: Dictionary) -> void:
        if event.get("kind") != "state": print("Observed: ", event.get("kind")))
    call_deferred("_start")

func _start() -> void:
    bomb = Bomb.new()
    bomb.module_count = 2
    add_child(bomb)
    await get_tree().create_timer(30.0).timeout
    if not completed:
        push_error("Live inspection and pending-action sequence did not complete")
        _finish.call_deferred(1)

func _on_narration(text: String, audio: AudioStreamMP3, decision: Dictionary) -> void:
    print("Narration: ", decision.get("trigger"), " / ", text)
    match str(decision.get("trigger", "")):
        "round_started":
            var wires: WiresModule = bomb.modules[1]
            var wrong_index: int = (wires.correct + 1) % wires.wire_hits.size()
            target = wires.wire_hits[wrong_index]
            Bridge.camera_connected = false
            Bridge.keyboard_mode = false
            Bridge.cursor = target.get_global_rect().get_center()
            Bridge._set_gesture("Closed_Fist")
            Bridge._fire("Closed_Fist")
        "target_locked":
            Bridge.cursor = target.get_global_rect().get_center()
            Bridge._set_gesture("None")
            Bridge._set_gesture("Closed_Fist")
            Bridge._fire("Closed_Fist")
            Bridge._fire("Victory")
        "inspection_result":
            inspection_audio = audio != null and decision.get("policy_guarded", false) \
                and text.contains(str(target.get_meta("desc"))) and (text.begins_with("Yes") or text.begins_with("No"))
            Bridge.cursor = target.get_global_rect().get_center()
            Bridge._fire("ILoveYou")
            Bridge.pending.time = Bridge._now() - 0.8
            Bridge._maybe_send_pending_cue()
        "pending_action":
            pending_decided = decision.get("decision_source") == "model" \
                and str(decision.get("observed_pending_id", "")) == str(Bridge.pending.get("id", "")) \
                and not decision.get("evidence", []).is_empty()
            pending_source = ("SPEAK: " + text if audio != null else "SPEAK: caption only") + \
                " / source=" + str(decision.get("decision_source", "")) + \
                " / fallback=" + str(decision.get("fallback_reason", ""))
            pending_round_trip_ms = int(decision.get("round_trip_ms", -1))
            Bridge.cursor = target.get_global_rect().get_center()
            Bridge._fire("Victory")
        "result":
            _check_result(text, audio, decision)

func _on_quiet(decision: Dictionary) -> void:
    if decision.get("trigger") == "state":
        return
    print("Quiet: ", decision.get("trigger"), " / ", decision.get("reason"))
    if decision.get("trigger") == "pending_action":
        pending_decided = decision.get("decision_source") == "model" \
            and str(decision.get("observed_pending_id", "")) == str(Bridge.pending.get("id", "")) \
            and not decision.get("evidence", []).is_empty()
        pending_source = "QUIET: " + str(decision.get("reason", ""))
        pending_round_trip_ms = int(decision.get("round_trip_ms", -1))
        Bridge.cursor = target.get_global_rect().get_center()
        Bridge._fire("Victory")

func _check_result(text: String, audio: AudioStreamMP3, decision: Dictionary) -> void:
    completed = true
    var ok := inspection_audio and pending_decided and bomb.strikes == 1 \
        and text.begins_with("Wrong choice.") and audio != null
    print(JSON.stringify({"inspection_audio": inspection_audio,
        "pending_decided": pending_decided, "pending": pending_source,
        "pending_round_trip_ms": pending_round_trip_ms,
        "result_audio": audio != null, "one_strike": bomb.strikes == 1,
        "round_trip_ms": decision.get("round_trip_ms", -1), "pass": ok}))
    if not ok:
        push_error("Live pre-confirmation path did not preserve its fact, decision and result")
    _finish.call_deferred(0 if ok else 1)

func _finish(code: int) -> void:
    NarratorClient.cancel_round()
    for child in get_children():
        child.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().quit(code)
