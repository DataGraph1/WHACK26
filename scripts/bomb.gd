class_name Bomb
extends Control
## The bomb: random serial / batteries / indicators, countdown, strikes, modules.

signal finished(won: bool)

const START_TIME := 180.0
const INDICATOR_POOL := ["FKL", "FRK", "CLR", "SND", "BOB"]

@export var module_count := 4

var serial := ""
var serial_has_vowel := false
var batteries := 0
var indicators: Array = []
var has_strike_indicator := true
var strikes := 0
var time_left := START_TIME
var modules: Array = []
var over := false

var _timer_label: Label
var _strike_label: Label
var _overlay: ColorRect
var _overlay_label: Label


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    Bridge.enabled = true
    Bridge.pending = {}
    _generate()
    _build_ui()
    _build_modules()
    NarratorClient.register_tracking_source(Bridge)
    NarratorClient.begin_round(str(Time.get_ticks_usec()), "bomb", {"lives": 3, "seconds_left": time_left})


func has_indicator(label: String) -> bool:
    return indicators.has(label)


func _generate() -> void:
    serial = _make_serial()
    for ch in serial:
        if ch in "AEIOU":
            serial_has_vowel = true
    batteries = randi_range(0, 4)
    for label in INDICATOR_POOL:
        if randf() < 0.5:
            indicators.append(label)
    has_strike_indicator = true


func _make_serial() -> String:
    var pool := "BCDFGHJKLMNPQRSTVWXYZ0123456789"
    var s := ""
    for i in 6:
        s += pool[randi() % pool.length()]
    if randf() < 0.5:
        var v: String = "AEIOU"[randi() % 5]
        var p := randi() % 6
        s = s.substr(0, p) + v + s.substr(p + 1)
    return s


func _build_ui() -> void:
    var bg := ColorRect.new()
    bg.color = Color("1b1d22")
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    _timer_label = _label("03:00", Vector2(40, 10), Vector2(300, 70), 56)
    _strike_label = _label("", Vector2(360, 24), Vector2(300, 40), 32)
    _update_strikes()

    _target_box(Vector2(40, 92), Vector2(190, 44), "the serial number", serial, BombModule.hide_text(serial))
    for i in batteries:
        var b := _target_box(Vector2(260 + i * 40, 92), Vector2(32, 44), "a battery", "Battery", "")
        b.color = Color("c9a227")
    for i in indicators.size():
        _target_box(Vector2(460 + i * 110, 92), Vector2(100, 44), "indicator %d" % (i + 1),
                indicators[i], BombModule.hide_text(indicators[i]))

    _overlay = ColorRect.new()
    _overlay.color = Color(0, 0, 0, 0.75)
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.visible = false
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_overlay)
    _overlay_label = Label.new()
    _overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _overlay_label.add_theme_font_size_override("font_size", 64)
    _overlay.add_child(_overlay_label)


func _build_modules() -> void:
    var kinds := [WiresModule, ButtonModule, SimonModule, MemoryModule]
    kinds.shuffle()
    for i in mini(module_count, kinds.size()):
        var m: BombModule = kinds[i].new()
        m.position = Vector2(40 + (i % 2) * 400, 150 + floori(i / 2.0) * 270)
        add_child(m)
        m.setup(self)
        m.struck.connect(add_strike)
        m.disarmed.connect(_on_disarmed)
        modules.append(m)
    # Overlay must draw above the modules.
    move_child(_overlay, get_child_count() - 1)


func _label(text: String, pos: Vector2, sz: Vector2, font_size: int) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.size = sz
    l.add_theme_font_size_override("font_size", font_size)
    add_child(l)
    return l


func _target_box(pos: Vector2, sz: Vector2, desc: String, info: String, shown: String) -> ColorRect:
    var r := ColorRect.new()
    r.color = Color(1, 1, 1, 0.08)
    r.position = pos
    r.size = sz
    add_child(r)
    var l := Label.new()
    l.text = shown
    l.size = sz
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    r.add_child(l)
    r.add_to_group("targetable")
    r.set_meta("module", self)
    r.set_meta("desc", desc)
    r.set_meta("verb", "Press")
    r.set_meta("multi", false)
    r.set_meta("info", info)
    return r


## Bomb-level targets (serial number, batteries, indicators).
func handle(target: Control, kind: String, _value: String, _count: int) -> String:
    match kind:
        "read": return target.get_meta("info")
        "color": return "No"
    return "Nothing to press there."


func _process(delta: float) -> void:
    if over:
        return
    NarratorClient.update_round_state("bomb", {"seconds_left": time_left, "lives": maxi(0, 3 - strikes), "strikes": strikes})
    time_left -= delta   # fixed three-minute round
    if time_left <= 0.0:
        time_left = 0.0
        _end(false)
    _timer_label.text = "%02d:%02d" % [floori(time_left / 60.0), floori(fmod(time_left, 60.0))]


func add_strike() -> void:
    if over:
        return
    strikes += 1
    _update_strikes()
    if not has_strike_indicator or strikes >= 3:
        _end(false)


func _update_strikes() -> void:
    if not has_strike_indicator:
        _strike_label.text = ""
        return
    var t := ""
    for i in 3:
        t += "[X] " if i < strikes else "[ ] "
    _strike_label.text = t


func _on_disarmed() -> void:
    for m in modules:
        if not m.solved:
            return
    _end(true)


func _end(won: bool) -> void:
    if over:
        return
    over = true
    Bridge.enabled = false
    Bridge.pending = {}
    _overlay_label.text = ("BOMB DEFUSED" if won else "BOOM") + "\nPress R to restart"
    _overlay.visible = true
    NarratorClient.end_round("bomb", {"defused": won, "seconds_left": time_left, "lives": maxi(0, 3 - strikes)})
    finished.emit(won)
