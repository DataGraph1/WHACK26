extends Control

var _bot_label: Label
var _status_label: Label


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(Bomb.new())

    _make_label("BOT SCREEN", Vector2(880, 150), Vector2(360, 30), 20)
    _bot_label = _make_label("Waiting for a command...", Vector2(880, 185), Vector2(360, 200), 26)
    _bot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label = _make_label("", Vector2(880, 640), Vector2(380, 60), 16)
    var help := _make_label(
        "Keyboard test (no camera needed):\nMouse = cursor. Hold a key ~0.35s:\n" +
        "1 blue   2 read   3 yellow\n4 red    5 green\n6 CONFIRM   7 cut/press\n" +
        "Press N I-love-you (7) taps, then 6.\nR = restart",
        Vector2(880, 400), Vector2(380, 220), 16)
    help.modulate = Color(1, 1, 1, 0.6)

    add_child(preload("res://scripts/cursor.gd").new())
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
    var camera_status := "connected" if Bridge.camera_connected else "off"
    var s := "Camera: %s   |   Gesture: %s" % [camera_status, Bridge.gesture]
    if not Bridge.pending.is_empty():
        s += "   |   pending: %s" % Bridge.pending.kind
    _status_label.text = s


func _unhandled_input(event: InputEvent) -> void:
    var k := event as InputEventKey
    if k != null and k.pressed and not k.echo and k.keycode == KEY_R:
        get_tree().reload_current_scene()
