extends Node

var events: Array = []
var failures := 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _ready() -> void:
    call_deferred("run")

func run() -> void:
    var narrator = get_tree().root.get_node("NarratorClient")
    var bridge = get_tree().root.get_node("Bridge")
    narrator.event_observed.connect(func(event: Dictionary) -> void: events.append(event))
    var bomb := Bomb.new()
    bomb.module_count = 5
    get_tree().root.add_child(bomb)
    check(bomb.time_left == 180.0, "Round must start at 180 seconds")
    check(bomb.has_strike_indicator, "Every round must have three strikes")
    check(events[0].kind == "round_started", "Actual game must start narrator round")
    var wires: WiresModule
    for module in bomb.modules:
        if module is WiresModule:
            wires = module
    var target: Control = wires.wire_hits[wires.correct]
    bridge.cursor = target.get_global_rect().get_center()
    bridge.camera_connected = true
    bridge.cursor_visible = false
    bridge.gesture_confidence = 0.99
    bridge._fire("ILoveYou")
    check(bridge.pending.is_empty(), "Missing pointer must not arm a cut")
    bridge.cursor_visible = true
    bridge.gesture_confidence = 0.2
    bridge._fire("ILoveYou")
    check(bridge.pending.is_empty(), "Uncertain gesture must not arm a cut")
    bridge.gesture_confidence = 0.99
    bridge._fire("ILoveYou")
    check(not bridge.pending.is_empty(), "Stable hands must arm a cut")
    bridge._fire("Victory")
    check(wires.solved, "Confirmed correct wire must solve module")
    check(events[-1].kind == "result" and events[-1].result == "correct", "Actual wire result must reach narrator")
    check(not events[-1].context.has("correct"), "Hidden solution must not enter context")
    var link: LinkModule
    for module in bomb.modules:
        if module is LinkModule:
            link = module
    bridge.camera_connected = false
    bridge.gesture = "Open_Palm"
    bridge.cursor = link.pad.get_global_rect().get_center()
    link._process(0.75)
    check(link.charge > 0, "Stable pointer and open palm must charge link")
    bridge.gesture = "None"
    link._process(0.1)
    check(link.charge == 0, "Interrupted hold must reset charge")
    check(bomb.strikes == 0, "Interrupted link must not consume life")
    bridge.gesture = "Open_Palm"
    for i in 3:
        bridge.cursor = link.pad.get_global_rect().get_center()
        link._process(1.6)
    check(link.solved, "Three stable contacts must restore link")
    check(events[-1].kind == "result", "Link restoration must reach agent")
    bridge.cursor = bomb.modules[0].get_global_rect().position - Vector2(10, 10)
    bomb.add_strike()
    bomb.add_strike()
    check(not bomb.over, "Two mistakes must leave round active")
    bomb.add_strike()
    check(bomb.over, "Third mistake must end round")
    check(events[-1].kind == "game_ended" and not events[-1].context.defused, "Loss must reach narrator")
    check(not bridge.enabled, "Input must stop at round end")
    print("Godot integration checks: ", "PASS" if failures == 0 else str(failures) + " failures")
    get_tree().quit(0 if failures == 0 else 1)
