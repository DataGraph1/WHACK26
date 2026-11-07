class_name BombModule
extends Panel
## Base class for every module. Subclasses override title(), build() and handle().

signal disarmed
signal struck

const COLORS := {
    "red": Color("e0453a"), "yellow": Color("e8c53a"),
    "green": Color("4caf50"), "blue": Color("3f7fe0"),
}
## The bot's camera is too poor to see colors or read text, so the player has to
## use the gestures. Set to false while testing to see everything.
const LOW_QUALITY := true

var bomb
var solved := false
var _led: ColorRect


func _init() -> void:
    custom_minimum_size = Vector2(380, 250)
    size = Vector2(380, 250)


func title() -> String:
    return "MODULE"


func build() -> void:
    pass


## kind: "press" | "color" | "read". Returns what the bot shows on screen.
func handle(_target: Control, _kind: String, _value: String, _count: int) -> String:
    return ""


func setup(b) -> void:
    bomb = b
    add_label(title(), Vector2(12, 6), Vector2(300, 26), 18)
    _led = add_rect(Vector2(350, 10), Vector2(18, 18), Color("7a2222"))
    build()


func solve() -> void:
    if solved:
        return
    solved = true
    _led.color = Color("4caf50")
    disarmed.emit()


func strike() -> void:
    struck.emit()


func seen(color_name: String) -> Color:
    if LOW_QUALITY:
        return Color(0.55, 0.55, 0.55)
    return COLORS[color_name]


static func hide_text(s: String) -> String:
    if not LOW_QUALITY:
        return s
    return "?".repeat(maxi(s.length(), 1))


func make_target(c: Control, desc: String, verb := "Press", multi := false) -> void:
    c.add_to_group("targetable")
    c.set_meta("module", self)
    c.set_meta("desc", desc)
    c.set_meta("verb", verb)
    c.set_meta("multi", multi)


func add_rect(pos: Vector2, sz: Vector2, color: Color, parent: Node = null) -> ColorRect:
    var r := ColorRect.new()
    r.position = pos
    r.size = sz
    r.color = color
    (parent if parent != null else self).add_child(r)
    return r


func add_label(text: String, pos: Vector2, sz: Vector2, font_size := 18, center := false, parent: Node = null) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.size = sz
    l.add_theme_font_size_override("font_size", font_size)
    if center:
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    (parent if parent != null else self).add_child(l)
    return l
