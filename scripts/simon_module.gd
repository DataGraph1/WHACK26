class_name SimonModule
extends BombModule

const NAMES := ["red", "yellow", "green", "blue"]
const STAGES := 5
const IDLE_REPLAY := 5.0

# table[strikes][flash color] = color to press
const VOWEL := {
    0: {"red": "blue", "yellow": "blue", "green": "red", "blue": "green"},
    1: {"red": "yellow", "yellow": "red", "green": "yellow", "blue": "red"},
    2: {"red": "green", "yellow": "green", "green": "blue", "blue": "yellow"},
}
const NO_VOWEL := {
    0: {"red": "yellow", "yellow": "blue", "green": "blue", "blue": "green"},
    1: {"red": "green", "yellow": "red", "green": "red", "blue": "yellow"},
    2: {"red": "blue", "yellow": "green", "green": "yellow", "blue": "red"},
}

var buttons := {}        # color -> ColorRect
var sequence: Array = []
var stage := 1
var input_index := 0
var _idle := 0.0
var _playing := false
var _gen := 0


func title() -> String:
    return "SIMON SAYS"


func build() -> void:
    var layout := {
        "red": [Vector2(70, 45), "top left button"],
        "yellow": [Vector2(210, 45), "top right button"],
        "green": [Vector2(70, 150), "bottom left button"],
        "blue": [Vector2(210, 150), "bottom right button"],
    }
    for c in NAMES:
        var r := add_rect(layout[c][0], Vector2(100, 90), seen(c))
        make_target(r, layout[c][1])
        buttons[c] = r
    _new_sequence()


func _new_sequence() -> void:
    sequence.clear()
    for i in STAGES:
        sequence.append(NAMES.pick_random())
    stage = 1
    input_index = 0
    _play()


func _play() -> void:
    _gen += 1
    var my := _gen
    _playing = true
    await get_tree().create_timer(0.8).timeout
    for i in stage:
        if my != _gen or not is_inside_tree() or solved:
            return
        _flash(sequence[i], true)
        await get_tree().create_timer(0.6).timeout
        _flash(sequence[i], false)
        await get_tree().create_timer(0.3).timeout
    if my == _gen:
        _playing = false
        _idle = 0.0


func _flash(c: String, on: bool) -> void:
    if not is_inside_tree():
        return
    buttons[c].color = Color(1, 1, 1) if on else seen(c)


func _process(delta: float) -> void:
    if solved or _playing:
        return
    _idle += delta
    if _idle >= IDLE_REPLAY:
        _idle = 0.0
        input_index = 0   # replay starts from the beginning, so re-enter from the start
        _play()


func _expected(flash: String) -> String:
    var table: Dictionary = VOWEL if bomb.serial_has_vowel else NO_VOWEL
    return table[mini(bomb.strikes, 2)][flash]


func handle(target: Control, kind: String, value: String, _count: int) -> String:
    var c: String = buttons.find_key(target)
    match kind:
        "color":
            return "Yes" if c == value else "No"
        "read":
            return "Nothing to read."
        "press":
            if solved: return "Module already disarmed."
            if _playing: return "Wait for the flashes to finish."
            _idle = 0.0
            if c == _expected(sequence[input_index]):
                input_index += 1
                if input_index >= stage:
                    stage += 1
                    input_index = 0
                    if stage > STAGES:
                        solve()
                        return "Correct. Module disarmed."
                    _play()
                return "Correct."
            strike()
            _new_sequence()
            return "Wrong. New sequence."
    return ""
