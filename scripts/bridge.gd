extends Node
## Autoload "Bridge".
## 1) Reads hand input: UDP packets from gesture_bridge.py, or (if no packets are
##    arriving) mouse = cursor and held keys 1-7 = left-hand gestures.
## 2) Runs the confirm / press-queue rules from the manual.

signal observed(event: Dictionary)

var keyboard_mode := false

func using_camera() -> bool:
    return camera_connected and not keyboard_mode

var gesture_confidence := 0.0
var pointer_confidence := 0.0
var _focus_target: Control
var _focus_since := 0.0
var _focus_sent := false
var _last_focus_event := -20.0

func tracking_context() -> Dictionary:
    return {"right_hand_visible": cursor_visible if using_camera() else true,
        "gesture_confidence": gesture_confidence, "pointer_confidence": pointer_confidence,
        "camera_connected": camera_connected, "control_mode": "camera" if using_camera() else "keyboard"}

signal bot_said(text: String)
signal camera_frame_changed(texture: Texture2D)

const PORT := 4242
const HOLD_TIME := 0.35        # a gesture must be held this long to register
const CONFIRM_WINDOW := 3.0    # seconds to confirm before the command is cancelled
const UDP_TIMEOUT := 1.0       # no packets for this long -> keyboard/mouse fallback
const CAMERA_START_DELAY := 1.25

# Keys 1-7 match the gesture numbers in the manual (MediaPipe gesture ids).
const KEY_GESTURES := {
    KEY_1: "Closed_Fist",   # blue
    KEY_2: "Open_Palm",     # read the symbol
    KEY_3: "Pointing_Up",   # yellow
    KEY_4: "Thumb_Down",    # red
    KEY_5: "Thumb_Up",      # green
    KEY_6: "Victory",       # confirm
    KEY_7: "ILoveYou",      # cut / press
}

var cursor := Vector2.ZERO
var gesture := "None"
var pending := {}      # {kind, value, count, target, time}
var enabled := true
var camera_connected := false
var camera_index := -1
var hand_count := 0
var cursor_visible := false
var camera_preview_texture: ImageTexture

var _udp := PacketPeerUDP.new()
var _camera_bridge_pid := -1
var _last_packet := -100.0
var _held_since := 0.0
var _fired := false
var _kb_gesture := "None"


func _ready() -> void:
    var err := _udp.bind(PORT)
    if err != OK:
        push_warning("Bridge: could not bind UDP port %d (error %d). Keyboard/mouse only." % [PORT, err])
        return
    _start_camera_bridge_after_delay()


func _exit_tree() -> void:
    if _camera_bridge_pid > 0:
        OS.kill(_camera_bridge_pid)
    _udp.close()


func _start_camera_bridge_after_delay() -> void:
    if DisplayServer.get_name() == "headless":
        return
    await get_tree().create_timer(CAMERA_START_DELAY).timeout
    if not is_inside_tree() or camera_connected:
        return
    var project_dir := ProjectSettings.globalize_path("res://")
    var python_relative := ".venv/Scripts/python.exe" if OS.get_name() == "Windows" else ".venv/bin/python"
    var python_path := project_dir.path_join(python_relative)
    var script_path := project_dir.path_join("gesture_bridge.py")
    if not FileAccess.file_exists(python_path) or not FileAccess.file_exists(script_path):
        push_warning("Camera bridge unavailable. Install its Python dependencies in .venv to enable hand input.")
        return
    _camera_bridge_pid = OS.create_process(python_path, PackedStringArray([script_path, "--no-preview"]))
    if _camera_bridge_pid < 0:
        push_warning("Camera bridge could not start. Keyboard and mouse still work.")


func _now() -> float:
    return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
    var k := event as InputEventKey
    if k != null and k.pressed and not k.echo and k.keycode == KEY_K:
        keyboard_mode = not keyboard_mode
        pending = {}
        _set_gesture("None")
        bot_said.emit("Mouse and keyboard mode" if keyboard_mode else "Camera control mode")
        return
    if k == null or k.echo or not KEY_GESTURES.has(k.keycode):
        return
    var g: String = KEY_GESTURES[k.keycode]
    if k.pressed:
        _kb_gesture = g
    elif _kb_gesture == g:
        _kb_gesture = "None"


func _process(_delta: float) -> void:
    while _udp.get_available_packet_count() > 0:
        var data = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
        if data is Dictionary:
            _ingest_camera_packet(data)
    var was_connected := camera_connected
    camera_connected = _now() - _last_packet <= UDP_TIMEOUT
    if camera_connected != was_connected:
        pending = {}
        _set_gesture("None")
        print("Camera bridge connected" if camera_connected else "Camera bridge disconnected")
    if not camera_connected:
        camera_index = -1
        hand_count = 0
        cursor_visible = false
        cursor = get_viewport().get_mouse_position()
        _set_gesture(_kb_gesture)

    if keyboard_mode:
        cursor = get_viewport().get_mouse_position()
        _set_gesture(_kb_gesture)

    if enabled:
        var focused := target_at() if (not using_camera() or (cursor_visible and pointer_confidence >= 0.65)) else null
        if is_instance_valid(focused):
            _cancel_pending_if_target_changed(focused)
        if focused != _focus_target:
            _focus_target = focused
            _focus_since = _now()
            _focus_sent = false
        if is_instance_valid(focused) and not _focus_sent and _now() - _focus_since >= 1.25 and _now() - _last_focus_event >= 8.0:
            _focus_sent = true
            _last_focus_event = _now()
            var module = focused.get_meta("module")
            NarratorClient.post_event({"game": module.title() if module is BombModule else "bomb", "kind": "focus", "context": {"target": str(focused.get_meta("desc")), "dwell_seconds": _now() - _focus_since}})

    if enabled and gesture != "None" and not _fired and _now() - _held_since >= HOLD_TIME:
        _fired = true
        _fire(gesture)

    if not pending.is_empty() and _now() - pending.time > CONFIRM_WINDOW:
        pending = {}
        bot_said.emit("Cancelled.")


func _cancel_pending_if_target_changed(current: Control) -> void:
    if not pending.is_empty() and current != pending.target:
        pending = {}
        bot_said.emit("Target changed. Command cancelled.")


func _ingest_camera_packet(data: Dictionary) -> void:
    _last_packet = _now()
    camera_index = int(data.get("camera_index", -1))
    hand_count = int(data.get("hands", 0))
    cursor_visible = bool(data.get("has_cursor", false))
    if cursor_visible:
        var size := get_viewport().get_visible_rect().size
        cursor = Vector2(float(data.get("x", 0.5)), float(data.get("y", 0.5))) * size
    gesture_confidence = float(data.get("confidence", 0.0))
    pointer_confidence = float(data.get("pointer_confidence", 0.0))
    if not keyboard_mode and (not cursor_visible or pointer_confidence < 0.65):
        if not pending.is_empty():
            pending = {}
            bot_said.emit("Right pointer lost. Command cancelled.")
            NarratorClient.report_uncertainty("right_pointer_missing_or_low_confidence")
        _set_gesture("None")
    else:
        var candidate := str(data.get("gesture", "None"))
        _set_gesture(candidate if keyboard_mode or candidate == "None" or gesture_confidence >= 0.65 else "None")
    if data.has("frame_jpeg"):
        _update_camera_preview(str(data["frame_jpeg"]))


func _update_camera_preview(encoded_jpeg: String) -> void:
    var image := Image.new()
    if image.load_jpg_from_buffer(Marshalls.base64_to_raw(encoded_jpeg)) != OK:
        return
    image.convert(Image.FORMAT_RGBA8)
    if camera_preview_texture == null:
        camera_preview_texture = ImageTexture.create_from_image(image)
    else:
        camera_preview_texture.update(image)
    camera_frame_changed.emit(camera_preview_texture)


func _set_gesture(g: String) -> void:
    if g != gesture:
        gesture = g
        _held_since = _now()
        _fired = false


func _fire(g: String) -> void:
    if using_camera() and (not cursor_visible or pointer_confidence < 0.65 or gesture_confidence < 0.65):
        return
    if g == "Open_Palm":
        for pad in get_tree().get_nodes_in_group("continuous_input"):
            if pad.get_global_rect().has_point(cursor):
                return
    match g:
        "ILoveYou": _queue_press()
        "Victory": _confirm()
        "Closed_Fist": _arm("color", "blue")
        "Thumb_Up": _arm("color", "green")
        "Thumb_Down": _arm("color", "red")
        "Pointing_Up": _arm("color", "yellow")
        "Open_Palm": _arm("read", "")


## Smallest targetable control under the cursor.
func target_at() -> Control:
    var best: Control = null
    var best_area := INF
    for n in get_tree().get_nodes_in_group("targetable"):
        var c: Control = n as Control
        if c == null or not c.is_visible_in_tree():
            continue
        var r := c.get_global_rect()
        if r.has_point(cursor) and r.get_area() < best_area:
            best = c
            best_area = r.get_area()
    return best


func _arm(kind: String, value: String) -> void:
    var t := target_at()
    if t == null:
        bot_said.emit("Nothing under the cursor.")
        return
    pending = {"kind": kind, "value": value, "count": 0, "target": t, "time": _now()}
    if kind == "read":
        bot_said.emit("Read %s?" % t.get_meta("desc"))
    else:
        bot_said.emit("Is %s %s?" % [t.get_meta("desc"), value])


## Each I-love-you adds one press to the queue. Nothing happens until Victory.
func _queue_press() -> void:
    var t := target_at()
    if t == null:
        bot_said.emit("Nothing under the cursor.")
        return
    var count := 1
    if not pending.is_empty() and pending.kind == "press" and pending.target == t:
        count = pending.count + 1
    var multi: bool = t.get_meta("multi", false)
    if count > 1 and not multi:
        pending = {}
        bot_said.emit("That only takes one press. Cancelled.")
        return
    pending = {"kind": "press", "value": "", "count": count, "target": t, "time": _now()}
    if multi:
        bot_said.emit("Presses queued: %d" % count)
    else:
        bot_said.emit("%s %s?" % [t.get_meta("verb", "Press"), t.get_meta("desc")])


func _confirm() -> void:
    if pending.is_empty():
        bot_said.emit("Nothing to confirm.")
        return
    var p := pending
    pending = {}
    var t := target_at()
    if not is_instance_valid(p.target) or t != p.target:
        bot_said.emit("Cursor moved. Cancelled.")
        return
    var module = p.target.get_meta("module")
    var bomb = module.bomb if module is BombModule else module
    var before_strikes: int = bomb.strikes
    var was_solved: bool = module.solved if module is BombModule else false
    var reply: String = module.handle(p.target, p.kind, p.value, p.count)
    var game_name: String = module.title() if module is BombModule else "bomb"
    var context := {"target": str(p.target.get_meta("desc")), "observation": reply, "seconds_left": bomb.time_left, "lives": maxi(0, 3 - bomb.strikes)}
    if not bomb.over:
        if p.kind == "press" and module is BombModule and not was_solved and (bomb.strikes > before_strikes or reply.begins_with("Correct") or module.solved):
            context["module_solved"] = module.solved
            context["command_count"] = p.count
            if module is WiresModule:
                context["target_reusable"] = false
            var action: String = str(p.target.get_meta("verb", "Press")).to_lower() + " " + str(p.target.get_meta("desc"))
            NarratorClient.send_result(game_name, bomb.strikes == before_strikes, action, context)
        elif p.kind != "press":
            context["query"] = str(p.value) if p.kind == "color" else "read"
            NarratorClient.post_event({"game": game_name, "kind": "inspection_result", "context": context})
    if reply != "":
        bot_said.emit(reply)
