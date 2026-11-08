class_name LinkModule
extends BombModule
## Original live-control challenge: restore three relay contacts using a steady pointer and an open palm.

const REQUIRED_HOLD := 1.5
var stage := 0
var charge := 0.0
var pad: ColorRect
var status_label: Label
var positions := [Vector2(35, 55), Vector2(250, 55), Vector2(140, 145)]
var was_charging := false

func title() -> String:
    return "LINK RECOVERY"

func build() -> void:
    positions.shuffle()
    pad = add_rect(positions[0], Vector2(80, 70), Color("397e88"))
    pad.add_to_group("continuous_input")
    add_label("HOLD", Vector2.ZERO, Vector2(80, 70), 18, true, pad)
    status_label = add_label("Point here + hold an open palm", Vector2(12, 220), Vector2(340, 26), 16)

func _process(delta: float) -> void:
    if solved or bomb.over or not Bridge.enabled:
        return
    var tracked := not Bridge.using_camera() or (Bridge.left_detected and Bridge.right_detected and Bridge.cursor_visible and Bridge.pointer_confidence >= 0.65 and Bridge.gesture_confidence >= 0.65)
    var holding := tracked and pad.get_global_rect().has_point(Bridge.cursor) and Bridge.gesture == "Open_Palm"
    if holding:
        charge += delta
        status_label.text = "Contact %d / 3 — %d%%" % [stage + 1, mini(100, int(charge / REQUIRED_HOLD * 100))]
        if not was_charging:
            NarratorClient.post_event({"game": title(), "kind": "link_stabilizing", "context": {"contact": stage + 1, "instruction": "Keep the pointer on the pad and hold an open palm"}})
        if charge >= REQUIRED_HOLD:
            charge = 0.0
            stage += 1
            if stage >= 3:
                solve()
                status_label.text = "Robot link restored"
                if not bomb.over:
                    NarratorClient.send_result(title(), true, "restored robot link", {"lives": 3 - bomb.strikes, "seconds_left": bomb.time_left})
            else:
                pad.position = positions[stage]
                NarratorClient.post_event({"game": title(), "kind": "link_contact", "context": {"contacts_restored": stage, "instruction": "Move to the next pad"}})
    else:
        if was_charging and charge > 0.0:
            NarratorClient.report_uncertainty("link_contact_lost", {"instruction": "Return the pointer to the pad and hold an open palm"})
        charge = 0.0
    was_charging = holding
