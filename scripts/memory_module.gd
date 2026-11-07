class_name MemoryModule
extends BombModule

const STAGES := 5

var stage := 1
var display := 1
var labels: Array = []          # number printed on each button, left to right
var history_pos: Array = []     # position (0-3) pressed in each finished stage
var history_label: Array = []   # label pressed in each finished stage
var buttons: Array = []
var button_labels: Array = []
var display_box: ColorRect
var display_label: Label
var pips: Array = []


func title() -> String:
    return "MEMORY"


func build() -> void:
    display_box = add_rect(Vector2(140, 38), Vector2(100, 60), Color(0.12, 0.12, 0.12))
    display_label = add_label("", Vector2(0, 0), Vector2(100, 60), 36, true, display_box)
    make_target(display_box, "the display")
    for i in 4:
        var b := add_rect(Vector2(20 + i * 90, 115), Vector2(80, 80), seen("blue"))
        button_labels.append(add_label("", Vector2(0, 0), Vector2(80, 80), 32, true, b))
        make_target(b, "button %d" % (i + 1))
        buttons.append(b)
    for i in STAGES:
        pips.append(add_rect(Vector2(125 + i * 28, 215), Vector2(18, 18), Color(0.25, 0.25, 0.25)))
    _deal()


func _deal() -> void:
    display = randi_range(1, 4)
    labels = [1, 2, 3, 4]
    labels.shuffle()
    display_label.text = hide_text(str(display))
    for i in 4:
        button_labels[i].text = hide_text(str(labels[i]))


## Index (0-3) of the button that must be pressed this stage.
func _expected() -> int:
    var d := display
    match stage:
        1:
            return [1, 1, 2, 3][d - 1]
        2:
            match d:
                1: return labels.find(4)
                2: return history_pos[0]
                3: return 0
                4: return history_pos[0]
        3:
            match d:
                1: return labels.find(history_label[1])
                2: return labels.find(history_label[0])
                3: return 2
                4: return labels.find(4)
        4:
            match d:
                1: return history_pos[0]
                2: return 0
                3: return history_pos[1]
                4: return history_pos[1]
        5:
            match d:
                1: return labels.find(history_label[0])
                2: return labels.find(history_label[1])
                3: return labels.find(history_label[3])
                4: return labels.find(history_label[2])
    return 0


func _reset() -> void:
    stage = 1
    history_pos.clear()
    history_label.clear()
    for p in pips:
        p.color = Color(0.25, 0.25, 0.25)
    _deal()


func handle(target: Control, kind: String, _value: String, _count: int) -> String:
    if target == display_box:
        match kind:
            "read": return str(display)
            "color": return "No"
            _: return "That is only a display."
    var i: int = buttons.find(target)
    match kind:
        "read":
            return str(labels[i])
        "color":
            return "No"
        "press":
            if solved: return "Module already disarmed."
            if i == _expected():
                history_pos.append(i)
                history_label.append(labels[i])
                pips[stage - 1].color = Color("4caf50")
                stage += 1
                if stage > STAGES:
                    solve()
                    return "Correct. Module disarmed."
                _deal()
                return "Correct."
            strike()
            _reset()
            return "Wrong. Back to stage 1."
    return ""
