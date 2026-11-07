extends Node
## Autoload "Bridge".
## 1) Reads hand input: UDP packets from gesture_bridge.py, or (if no packets are
##    arriving) mouse = cursor and held keys 1-7 = left-hand gestures.
## 2) Runs the confirm / press-queue rules from the manual.

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
            _last_packet = _now()
            camera_index = int(data.get("camera_index", -1))
            hand_count = int(data.get("hands", 0))
            cursor_visible = bool(data.get("has_cursor", false))
            if data.get("has_cursor", false):
                var size := get_viewport().get_visible_rect().size
                cursor = Vector2(float(data.get("x", 0.5)), float(data.get("y", 0.5))) * size
            _set_gesture(str(data.get("gesture", "None")))
            if data.has("frame_jpeg"):
                _update_camera_preview(str(data["frame_jpeg"]))
    var was_connected := camera_connected
    camera_connected = _now() - _last_packet <= UDP_TIMEOUT
    if camera_connected != was_connected:
        print("Camera bridge connected" if camera_connected else "Camera bridge disconnected")
    if not camera_connected:
        camera_index = -1
        hand_count = 0
        cursor_visible = false
        cursor = get_viewport().get_mouse_position()
        _set_gesture(_kb_gesture)

    if enabled and gesture != "None" and not _fired and _now() - _held_since >= HOLD_TIME:
        _fired = true
        _fire(gesture)

    if not pending.is_empty() and _now() - pending.time > CONFIRM_WINDOW:
        pending = {}
        bot_said.emit("Cancelled.")


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
    var reply: String = p.target.get_meta("module").handle(p.target, p.kind, p.value, p.count)
    if reply != "":
        bot_said.emit(reply)
