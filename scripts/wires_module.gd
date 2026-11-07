class_name WiresModule
extends BombModule

var wires: Array = []          # color names, top to bottom
var wire_hits: Array = []      # targetable hit boxes
var wire_visuals: Array = []
var cut: Array = []
var correct := 0


func title() -> String:
    return "WIRES"


func build() -> void:
    var n := randi_range(3, 4)
    for i in n:
        wires.append(["red", "yellow", "green", "blue"].pick_random())
    correct = _solve()
    for i in n:
        var hit := add_rect(Vector2(60, 45 + i * 48), Vector2(260, 40), Color(1, 1, 1, 0.05))
        var vis := add_rect(Vector2(0, 12), Vector2(260, 16), seen(wires[i]), hit)
        make_target(hit, "wire %d" % (i + 1), "Cut")
        wire_hits.append(hit)
        wire_visuals.append(vis)
        cut.append(false)


func _count(c: String) -> int:
    return wires.count(c)


## Returns the index (0 = top) of the wire that must be cut.
func _solve() -> int:
    var n := wires.size()
    var last: String = wires[n - 1]
    if n == 3:
        if _count("red") == 0: return 1
        if last == "yellow": return 2
        if _count("green") > 1: return wires.rfind("green")
        return 0
    if last == "green" and _count("red") == 0: return 0
    if _count("yellow") == 0: return 0
    if _count("red") > 1: return 3
    if _count("green") >= 1 and _count("blue") >= 1: return 1
    if _count("green") == 0 and bomb.serial_has_vowel: return 2
    return wires.find("yellow")


func handle(target: Control, kind: String, value: String, _count_arg: int) -> String:
    var i: int = wire_hits.find(target)
    match kind:
        "color":
            return "Yes" if wires[i] == value else "No"
        "read":
            return "Nothing to read."
        "press":
            if solved: return "Module already disarmed."
            if cut[i]: return "Already cut."
            cut[i] = true
            _show_cut(i)
            if i == correct:
                solve()
            else:
                strike()
            return "Cut."
    return ""


func _show_cut(i: int) -> void:
    var w: ColorRect = wire_visuals[i]
    w.size = Vector2(110, w.size.y)
    add_rect(Vector2(150, w.position.y), Vector2(110, w.size.y), w.color, w.get_parent())
