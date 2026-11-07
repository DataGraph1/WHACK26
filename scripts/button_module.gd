class_name ButtonModule
extends BombModule

const WORDS := ["Abort", "Detonate", "Press", "Hold"]

var color_name := "red"
var word := "Press"
var required := 4
var btn: ColorRect


func title() -> String:
    return "THE BUTTON"


func build() -> void:
    color_name = ["red", "blue", "yellow", "green"].pick_random()
    word = WORDS.pick_random()
    required = _solve()
    btn = add_rect(Vector2(110, 45), Vector2(160, 180), seen(color_name))
    add_label(hide_text(word), Vector2(0, 70), Vector2(160, 40), 26, true, btn)
    make_target(btn, "the button", "Press", true)


## Rules in order; first one that applies wins.
func _solve() -> int:
    var b: int = bomb.batteries
    if color_name == "blue" and word == "Abort": return 2
    if b > 1 and word == "Detonate": return 3
    if color_name == "red" and b == 3 and bomb.has_indicator("FKL"): return 8
    if b > 2 and color_name == "yellow" and bomb.has_indicator("FRK"): return 1
    if color_name == "red" and b == 1: return 1
    if color_name == "red": return 3
    return 4


func handle(_target: Control, kind: String, value: String, count: int) -> String:
    match kind:
        "color":
            return "Yes" if color_name == value else "No"
        "read":
            return word
        "press":
            if solved: return "Module already disarmed."
            if count == required:
                solve()
            else:
                strike()
            return "Pressed %d time%s." % [count, "" if count == 1 else "s"]
    return ""
