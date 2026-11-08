extends Control
## Draws the live cursor, yellow locked selection, and orange pending command.


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    var pointer_ready: bool = not Bridge.using_camera() or (Bridge.cursor_visible and Bridge.pointer_confidence >= 0.65)
    var t := Bridge.target_at() if pointer_ready else null
    if is_instance_valid(t):
        draw_rect(t.get_global_rect(), Color(1, 1, 1, 0.5), false, 2.0)
    if is_instance_valid(Bridge.selected_target):
        draw_rect(Bridge.selected_target.get_global_rect(), Color(1, 0.9, 0.2), false, 4.0)
    if not Bridge.pending.is_empty() and is_instance_valid(Bridge.pending.target):
        draw_rect(Bridge.pending.target.get_global_rect().grow(4), Color(1, 0.55, 0.1), false, 3.0)
    if pointer_ready:
        draw_arc(Bridge.cursor, 16.0, 0.0, TAU, 32, Color(1, 0.35, 0.3), 3.0)
        draw_circle(Bridge.cursor, 4.0, Color(1, 0.35, 0.3))
