extends Control

var _feed_lines: Array[String] = []
var _command_label: Label
var _feed: Label
var _welcome: Control

func _start_round(count: int = 4) -> void:
    if is_instance_valid(_welcome):
        _welcome.queue_free()
    var bomb := Bomb.new()
    bomb.module_count = count
    add_child(bomb)
    move_child(bomb, 1)

var _bot_label: Label
var _status_label: Label
var _camera_preview: TextureRect


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var background := ColorRect.new()
    background.color = Color("101a2a")
    background.set_anchors_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    Bridge.enabled = false
    call_deferred("_show_welcome")

    _make_label("BOT SCREEN", Vector2(880, 150), Vector2(360, 30), 20)
    _bot_label = _make_label("Waiting for a command...", Vector2(880, 185), Vector2(360, 120), 23)
    _bot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label = _make_label("", Vector2(880, 640), Vector2(380, 60), 14)
    _camera_preview = TextureRect.new()
    _camera_preview.position = Vector2(995, 10)
    _camera_preview.size = Vector2(240, 135)
    _camera_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _camera_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_camera_preview)
    Bridge.camera_frame_changed.connect(func(texture: Texture2D) -> void: _camera_preview.texture = texture)
    var help := _make_label(
        "Keys: 1 blue / 2 read / 3 yellow / 4 red / 5 green\n6 confirm / 7 cut or press (release between presses)\nK hand or keyboard mode / R restart",
        Vector2(880, 565), Vector2(380, 80), 12)
    help.modulate = Color(1, 1, 1, 0.6)

    add_child(preload("res://scripts/cursor.gd").new())
    NarratorClient.narration_ready.connect(func(text: String, _audio: AudioStreamMP3, decision: Dictionary) -> void:
        _bot_label.text = text
        var source := "FALLBACK" if decision.get("fallback", false) else "GUARD" if decision.get("policy_guarded", false) else "AGENT"
        var detail := str(decision.get("fallback_reason", decision.get("reason", "")))
        _log("%s/%s · %d ms · %s" % [source, str(decision.get("trigger", "event")),
            int(decision.get("round_trip_ms", 0)), detail]))
    NarratorClient.narrator_error.connect(func(message: String) -> void: _log("OFFLINE · " + message))
    _feed = _make_label("Live observer ready", Vector2(880, 400), Vector2(360, 155), 14)
    _feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _command_label = _make_label("Point, inspect, confirm.", Vector2(880, 320), Vector2(360, 65), 17)
    _command_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    Bridge.bot_said.connect(func(t: String) -> void: _command_label.text = t)
    NarratorClient.event_observed.connect(func(event: Dictionary) -> void:
        if event.get("kind") != "state":
            _log("OBSERVED · " + str(event.get("game", "")) + " · " + str(event.get("kind", ""))))
    NarratorClient.narration_skipped.connect(func(decision: Dictionary) -> void:
        if decision.get("trigger") != "state":
            _log("QUIET/" + str(decision.get("trigger", "event")) + " · " + str(decision.get("reason", ""))))


func _make_label(text: String, pos: Vector2, sz: Vector2, font_size: int) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.size = sz
    l.add_theme_font_size_override("font_size", font_size)
    add_child(l)
    return l


func _process(_delta: float) -> void:
    var camera_status := "connected (%d)" % Bridge.camera_index if Bridge.camera_connected else "off"
    var s := "Control: %s | Cam: %s | Hands: %d\nLeft: %s / %s | Right: %s" % [
        "keyboard" if Bridge.keyboard_mode or not Bridge.camera_connected else "hands",
        camera_status, Bridge.hand_count, "seen" if Bridge.left_detected else "missing",
        Bridge.gesture, "ready" if Bridge.right_detected and Bridge.cursor_visible and Bridge.pointer_confidence >= 0.65 else "missing/uncertain"]
    if not Bridge.pending.is_empty():
        s += "   |   pending: %s" % Bridge.pending.kind
    _status_label.text = s


func _unhandled_input(event: InputEvent) -> void:
    var k := event as InputEventKey
    if k != null and k.pressed and not k.echo and k.keycode == KEY_R:
        get_tree().reload_current_scene()


func _show_welcome() -> void:
    _welcome = Control.new()
    add_child(_welcome)
    var title_label := Label.new()
    title_label.text = "BOT DEFUSAL\nRestore the link. Trust your observations."
    title_label.position = Vector2(55, 80)
    title_label.add_theme_font_size_override("font_size", 28)
    _welcome.add_child(title_label)
    var guide := Label.new()
    guide.text = "Check the camera preview before starting.\nRight index finger moves the pointer; left hand gives commands.\nHold a gesture, release, then use Victory to confirm.\nRead the printed revision 7 field guide.\nEvery round: three minutes, three lives.\nUse K to switch to mouse and keys 1–7."
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


func _log(line: String) -> void:
    _feed_lines.append(line.left(125))
    while _feed_lines.size() > 3:
        _feed_lines.pop_front()
    _feed.text = "\n\n".join(_feed_lines)
