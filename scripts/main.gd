extends Control

var _feed_lines: Array[String] = []
var _command_label: Label
var _feed: Label
var _welcome: Control
var _rehearsal_label: Label
var _both_hand_seconds := 0.0
var _pointer_start := Vector2.ZERO
var _pointer_moved := false
var _seen_gestures := {}
var _rehearsal_announced := false

func _start_round(count: int = 4) -> void:
    if is_instance_valid(_welcome):
        _welcome.queue_free()
    var bomb := Bomb.new()
    bomb.module_count = count
    add_child(bomb)
    move_child(bomb, 1)

var _bot_label: Label
var _status_label: Label
var _narrator_status_label: Label
var _camera_preview: TextureRect
var _preview_expanded := false


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var background := ColorRect.new()
    background.color = Color("101a2a")
    background.set_anchors_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    Bridge.enabled = false
    call_deferred("_show_welcome")

    _make_label("BOT SCREEN", Vector2(880, 200), Vector2(360, 30), 20)
    _bot_label = _make_label("Waiting for a command...", Vector2(880, 235), Vector2(360, 90), 21)
    _bot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label = _make_label("", Vector2(880, 640), Vector2(380, 60), 14)
    _narrator_status_label = _make_label("Agent: connecting...", Vector2(880, 365), Vector2(380, 24), 12)
    _camera_preview = TextureRect.new()
    _camera_preview.position = Vector2(900, 10)
    _camera_preview.size = Vector2(320, 180)
    _camera_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _camera_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_camera_preview)
    Bridge.camera_frame_changed.connect(func(texture: Texture2D) -> void: _camera_preview.texture = texture)
    var help := _make_label(
        "Keys: 1 lock / 1 again blue / 2 read / 3 yellow / 4 red / 5 green\n6 confirm / 7 cut or press (release between presses)\nK keyboard / P camera zoom / R restart / F11 fullscreen",
        Vector2(880, 565), Vector2(380, 80), 12)
    help.modulate = Color(1, 1, 1, 0.6)

    add_child(preload("res://scripts/cursor.gd").new())
    NarratorClient.narration_ready.connect(_on_narration_ready)
    NarratorClient.narrator_error.connect(_on_narrator_error)
    _feed = _make_label("Checking live observer...", Vector2(880, 390), Vector2(360, 165), 12)
    _feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _command_label = _make_label("Point, inspect, confirm.", Vector2(880, 330), Vector2(360, 55), 17)
    _command_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    Bridge.bot_said.connect(func(t: String) -> void: _command_label.text = t)
    NarratorClient.event_observed.connect(_on_event_observed)
    NarratorClient.narration_skipped.connect(_on_narration_skipped)


func _on_narration_ready(text: String, audio: AudioStreamMP3, decision: Dictionary) -> void:
    _bot_label.text = text
    _log_evidence(decision)
    var explanation := str(decision.get("fallback_reason", decision.get("reason", "")))
    _log("%s [%s] %d ms · %s" % ["SPEAK" if audio != null else "CAPTION",
        str(decision.get("decision_source", "model")).to_upper(),
        int(decision.get("round_trip_ms", 0)), explanation])
    if audio == null and decision.has("audio_error"):
        _log("VOICE OFF · " + str(decision.audio_error))


func _on_narrator_error(message: String) -> void:
    _log("OFFLINE · " + message)


func _on_event_observed(event: Dictionary) -> void:
    if event.get("kind") == "state":
        return
    var context: Dictionary = event.get("context", {})
    _log("OBSERVED %s · %s · %s" % [str(event.get("game", "")),
        str(event.get("kind", "")), str(context.get("target", event.get("action", "")))])


func _on_narration_skipped(decision: Dictionary) -> void:
    if decision.get("trigger") == "state":
        return
    _log_evidence(decision)
    var explanation := str(decision.get("fallback_reason", decision.get("reason", "")))
    _log("QUIET [%s] %d ms · %s" % [str(decision.get("decision_source", "rule")).to_upper(),
        int(decision.get("round_trip_ms", 0)), explanation])


func _make_label(text: String, pos: Vector2, sz: Vector2, font_size: int) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.size = sz
    l.add_theme_font_size_override("font_size", font_size)
    add_child(l)
    return l


func _process(delta: float) -> void:
    _narrator_status_label.text = ("Agent: on | Qwen: %s | Liam key: %s" % [
        "ready" if NarratorClient.is_model_ready() else "missing",
        "yes" if NarratorClient.is_voice_key_present() else "no"]) if NarratorClient.is_api_ready() else "Agent: connecting or offline"
    var camera_status := "connected (%d)" % Bridge.camera_index if Bridge.camera_connected else "off"
    var s := "Control: %s | Cam: %s | Hands: %d\nLeft: %s / %s | Right: %s" % [
        "keyboard" if Bridge.keyboard_mode or not Bridge.camera_connected else "hands",
        camera_status, Bridge.hand_count, "seen" if Bridge.left_detected else "missing",
        Bridge.gesture, "ready" if Bridge.right_detected and Bridge.cursor_visible and Bridge.pointer_confidence >= 0.65 else "missing/uncertain"]
    if not Bridge.pending.is_empty():
        s += "   |   pending: %s" % Bridge.pending.kind
    if is_instance_valid(Bridge.selected_target):
        s += "   |   locked: %s" % Bridge.selected_target.get_meta("desc")
    if not Bridge.camera_error.is_empty():
        s += "\nCAMERA ACCESS BLOCKED"
    elif not Bridge.camera_notice.is_empty():
        s += "\nCAMERA WAITING FOR PERMISSION"
    elif not Bridge.camera_preview_error.is_empty():
        s += "\n" + Bridge.camera_preview_error
    _status_label.text = s
    _update_rehearsal(delta)


func _unhandled_input(event: InputEvent) -> void:
    var k := event as InputEventKey
    if k == null or not k.pressed or k.echo:
        return
    if k.keycode == KEY_R:
        get_tree().reload_current_scene()
    elif k.keycode == KEY_F11:
        var window := get_window()
        window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
    elif k.keycode == KEY_P:
        _preview_expanded = not _preview_expanded
        _camera_preview.position = Vector2(40, 155) if _preview_expanded else Vector2(900, 10)
        _camera_preview.size = Vector2(800, 450) if _preview_expanded else Vector2(320, 180)
        if _preview_expanded:
            move_child(_camera_preview, get_child_count() - 1)


func _show_welcome() -> void:
    _welcome = Control.new()
    add_child(_welcome)
    var title_label := Label.new()
    title_label.text = "BOT DEFUSAL\nRestore the link. Trust your observations."
    title_label.position = Vector2(55, 80)
    title_label.add_theme_font_size_override("font_size", 28)
    _welcome.add_child(title_label)
    var guide := Label.new()
    guide.text = "Check the camera preview before starting.\nRight index finger moves the pointer; left fist locks a target.\nMove freely after locking; fist on another target changes the lock.\nHold, release, then use Victory to confirm.\nRead the printed revision 9 field guide.\nTwo modules: three minutes. Four modules: eight minutes. Three lives."
    guide.position = Vector2(55, 210)
    guide.add_theme_font_size_override("font_size", 20)
    _welcome.add_child(guide)
    for count in [2, 4]:
        var button := Button.new()
        button.text = "Start — %d modules" % count
        button.position = Vector2(55 + (count - 2) * 160, 430)
        button.size = Vector2(270, 60)
        button.pressed.connect(_start_round.bind(count))
        _welcome.add_child(button)
    _rehearsal_label = _make_label("", Vector2(55, 510), Vector2(780, 150), 16)
    remove_child(_rehearsal_label)
    _welcome.add_child(_rehearsal_label)


func _update_rehearsal(delta: float) -> void:
    if not is_instance_valid(_rehearsal_label):
        return
    if not Bridge.camera_error.is_empty():
        _rehearsal_label.text = Bridge.camera_error
        return
    if not Bridge.camera_notice.is_empty():
        _rehearsal_label.text = Bridge.camera_notice
        return
    var both_ready: bool = Bridge.using_camera() and Bridge.left_detected and Bridge.right_detected \
        and Bridge.cursor_visible and Bridge.pointer_confidence >= 0.65
    _both_hand_seconds = _both_hand_seconds + delta if both_ready else 0.0
    if both_ready:
        if _pointer_start == Vector2.ZERO:
            _pointer_start = Bridge.cursor
        if Bridge.cursor.distance_to(_pointer_start) >= 80.0:
            _pointer_moved = true
        if Bridge.gesture_confidence >= 0.65 and Bridge.gesture in ["Open_Palm", "Victory", "ILoveYou", "Closed_Fist"]:
            _seen_gestures[Bridge.gesture] = true
    var stable := _both_hand_seconds >= 2.0
    var line := "CAMERA REHEARSAL  Both hands 2s: %s  |  Right pointer moves: %s\n" % [
        "PASS" if stable else "WAIT", "PASS" if _pointer_moved else "WAIT"]
    line += "Left gestures: Open palm %s  Victory %s  I-love-you %s  Fist %s\n" % [
        _check_gesture("Open_Palm"), _check_gesture("Victory"),
        _check_gesture("ILoveYou"), _check_gesture("Closed_Fist")]
    var all_pass := stable and _pointer_moved and _seen_gestures.size() >= 4
    line += "READY FOR PHYSICAL ROUND" if all_pass else "Show both hands, move your right pointer, then try each left gesture."
    _rehearsal_label.text = line
    if all_pass and not _rehearsal_announced:
        _rehearsal_announced = true
        print("Camera rehearsal passed: both hands, right pointer, four left gestures")


func _check_gesture(name: String) -> String:
    return "PASS" if _seen_gestures.has(name) else "WAIT"


func _log(line: String) -> void:
    _feed_lines.append(line.left(90))
    while _feed_lines.size() > 5:
        _feed_lines.pop_front()
    _feed.text = "\n".join(_feed_lines)


func _log_evidence(decision: Dictionary) -> void:
    var facts: Array = decision.get("evidence", [])
    if not facts.is_empty():
        _log("MEMORY · " + str(facts[-1]))
