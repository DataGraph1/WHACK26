extends Node
## End-to-end check: a real wrong wire cut reaches the model and returns Liam audio.

var completed := false
var bomb: Bomb
var opening_audio := false

func _ready() -> void:
    NarratorClient.auto_play_audio = false
    NarratorClient.narration_ready.connect(_received)
    call_deferred("_start")

func _start() -> void:
    bomb = Bomb.new()
    bomb.module_count = 2
    add_child(bomb)
    await get_tree().create_timer(20.0).timeout
    if not completed:
        push_error("Live narrator did not return a result line within 20 seconds")
        _finish.call_deferred(1)

func _received(text: String, audio: AudioStreamMP3, decision: Dictionary) -> void:
    if decision.get("trigger") == "round_started":
        opening_audio = audio != null and decision.get("policy_guarded", false)
        var wires: WiresModule
        for module in bomb.modules:
            if module is WiresModule:
                wires = module
        var wrong_index: int = (wires.correct + 1) % wires.wires.size()
        Bridge.cursor = wires.wire_hits[wrong_index].get_global_rect().get_center()
        Bridge.camera_connected = false
        Bridge.keyboard_mode = false
        Bridge._fire("ILoveYou")
        Bridge._fire("Victory")
        return
    if decision.get("trigger") != "result":
        return
    completed = true
    var ok: bool = opening_audio and not text.is_empty() and audio != null \
        and not decision.get("fallback", false) and not decision.get("policy_guarded", false) \
        and text.begins_with("Wrong choice.") and bomb.strikes == 1
    print(JSON.stringify({"model_result": not decision.get("fallback", false),
        "fallback_reason": decision.get("fallback_reason", ""),
        "caption": text, "audio_decoded": audio != null,
        "round_trip_ms": decision.get("round_trip_ms", -1),
        "one_real_strike": bomb.strikes == 1, "pass": ok}))
    if not ok:
        push_error("A real wrong wire cut did not produce model-generated Liam audio")
    _finish.call_deferred(0 if ok else 1)

func _finish(code: int) -> void:
    NarratorClient.cancel_round()
    for child in get_children():
        child.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().quit(code)
