extends Control

var _feed: Label
var _welcome: Control

func _start_round(count: int = 4) -> void:
    if is_instance_valid(_welcome):
        _welcome.queue_free()
    var bomb := Bomb.new()
    bomb.module_count = count
    add_child(bomb)
    move_child(bomb, 0)

var _bot_label: Label
var _status_label: Label
var _camera_preview: TextureRect


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    Bridge.enabled = false
    call_deferred("_show_welcome")

    _make_label("BOT SCREEN", Vector2(880, 150), Vector2(360, 30), 20)
    _bot_label = _make_label("Waiting for a command...", Vector2(880, 185), Vector2(360, 200), 26)
    _bot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label = _make_label("", Vector2(880, 640), Vector2(380, 60), 16)
    _camera_preview = TextureRect.new()
    _camera_preview.position = Vector2(995, 10)
    _camera_preview.size = Vector2(240, 135)
    _camera_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _camera_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_camera_preview)
    Bridge.camera_frame_changed.connect(func(texture: Texture2D) -> void: _camera_preview.texture = texture)
    var help := _make_label(
        "Keyboard test (no camera needed):\nMouse = cursor. Hold a key ~0.35s:\n" +
        "1 blue   2 read   3 yellow\n4 red    5 green\n6 CONFIRM   7 cut/press\n" +
        "Press N I-love-you (7) taps, then 6.\nR = restart",
        Vector2(880, 400), Vector2(380, 220), 16)
    help.modulate = Color(1, 1, 1, 0.6)

    add_child(preload("res://scripts/cursor.gd").new())
    NarratorClient.narration_ready.connect(func(text: String, _audio: AudioStreamMP3, decision: Dictionary) -> void:
        _bot_label.text = text
        _feed.text = str(decision.get("trigger", "event")) + ": " + str(decision.get("reason", "")))
    NarratorClient.narrator_error.connect(func(message: String) -> void: _feed.text = "Narrator unavailable: " + message)
    _feed = _make_label("Live observer ready", Vector2(880, 590), Vector2(360, 48), 14)
    _feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    Bridge.bot_said.connect(func(t: String) -> void: _bot_label.text = t)


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
    var s := "Camera: %s | Hands: %d | Cursor: %s\nGesture: %s" % [
        camera_status, Bridge.hand_count, "yes" if Bridge.cursor_visible else "no", Bridge.gesture]
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
    guide.text = "Check the camera preview before starting.\nRight index finger moves the pointer; left hand gives commands.\nHold a gesture, release, then use Victory to confirm.\nRead docs/PLAYER_MANUAL.md revision 7.\nEvery round: three minutes, three lives.\nNo camera? Use mouse and keys 1–7."
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
