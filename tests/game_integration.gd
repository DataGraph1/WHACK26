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
    var demo := Bomb.new()
    demo.module_count = 2
    get_tree().root.add_child(demo)
    check(demo.modules[0] is LinkModule and demo.modules[1] is WiresModule,
        "Two-module demo must include predictable Link Recovery and Wires")
    demo.queue_free()
    await get_tree().process_frame
    check(narrator.session_id.is_empty() and not bridge.enabled,
        "Leaving a round must stop old narration and input")
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
    check(narrator._focus_is_current(str(target.get_meta("desc")), "WIRES"),
        "Current focus target must remain valid while its narration is pending")
    check(not narrator._focus_is_current("other target", "WIRES")
        and not narrator._focus_is_current(str(target.get_meta("desc")), "MEMORY"),
        "Moved focus must reject a stale narration")
    bridge.camera_connected = true
    bridge.left_detected = true
    bridge.right_detected = true
    bridge.cursor_visible = false
    bridge.pointer_confidence = 0.99
    bridge.gesture_confidence = 0.99
    check(not narrator._focus_is_current(str(target.get_meta("desc")), "WIRES"),
        "Lost camera pointer must invalidate a pending focus line")
    bridge._fire("ILoveYou")
    check(bridge.pending.is_empty(), "Missing pointer must not arm a cut")
    bridge.cursor_visible = true
    bridge.left_detected = false
    bridge._fire("ILoveYou")
    check(bridge.pending.is_empty(), "Missing left hand must not arm a cut")
    bridge.left_detected = true
    bridge.gesture_confidence = 0.2
    bridge._fire("ILoveYou")
    check(bridge.pending.is_empty(), "Uncertain gesture must not arm a cut")
    bridge.gesture_confidence = 0.99
    bridge.pointer_confidence = 0.2
    check(not narrator._focus_is_current(str(target.get_meta("desc")), "WIRES"),
        "Uncertain camera pointer must invalidate a pending focus line")
    bridge._fire("ILoveYou")
    check(bridge.pending.is_empty(), "Uncertain pointer must not arm a cut")
    bridge.pointer_confidence = 0.99
    bridge._fire("ILoveYou")
    check(not bridge.pending.is_empty(), "Stable hands must arm a cut")
    bridge.pending.time = bridge._now() - 0.8
    bridge._maybe_send_pending_cue()
    check(events[-1].kind == "pending_action" and narrator._pending_is_current(str(events[-1].context.pending_id)),
        "Pending cut must reach narrator before confirmation")
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    var center: Vector2 = target.get_global_rect().get_center()
    var released_command := {"has_cursor": true, "x": center.x / viewport_size.x,
        "y": center.y / viewport_size.y, "pointer_confidence": 0.99,
        "gesture": "None", "confidence": 0.0, "hands": 2,
        "left_detected": true, "right_detected": true}
    bridge._ingest_camera_packet(released_command)
    check(not bridge.pending.is_empty(), "Releasing left gesture must preserve queued command")
    bridge._ingest_camera_packet({"has_cursor": false, "pointer_confidence": 0.0,
        "gesture": "Victory", "confidence": 0.99, "hands": 1,
        "left_detected": true, "right_detected": false})
    check(bridge.pending.is_empty(), "Losing right pointer must cancel queued command")
    bridge._ingest_camera_packet({"has_cursor": true, "x": center.x / viewport_size.x,
        "y": center.y / viewport_size.y, "pointer_confidence": 0.99,
        "gesture": "None", "confidence": 0.0, "hands": 2,
        "left_detected": true, "right_detected": true})
    bridge.gesture_confidence = 0.99
    bridge._fire("ILoveYou")
    var other_index: int = (wires.correct + 1) % wires.wire_hits.size()
    bridge._cancel_pending_if_target_changed(wires.wire_hits[other_index])
    check(bridge.pending.is_empty(), "Moving to another target must cancel pending command")
    var command_packet := released_command.duplicate()
    command_packet["gesture"] = "ILoveYou"
    command_packet["confidence"] = 0.99
    bridge._ingest_camera_packet(command_packet)
    bridge._fire(bridge.gesture)
    check(not bridge.pending.is_empty(), "Left-hand packet must queue the cut")
    var queued_id: String = str(bridge.pending.id)
    bridge._ingest_camera_packet(released_command)
    command_packet["gesture"] = "Victory"
    bridge._ingest_camera_packet(command_packet)
    bridge._fire(bridge.gesture)
    check(wires.solved, "Confirmed correct wire must solve module")
    check(not narrator._pending_is_current(queued_id),
        "Confirmed action must invalidate its earlier pre-confirmation cue")
    check(events[-1].kind == "result" and events[-1].result == "correct", "Actual wire result must reach narrator")
    check(events[-1].action.begins_with("cut wire") and events[-1].context.module_solved,
        "Narrator must receive the actual command and solved state")
    check(events[-1].context.target_reusable == false,
        "Cut wire must be marked unavailable for further attempts")
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
