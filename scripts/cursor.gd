extends Control
## Draws the bot's cursor, a faint box on whatever it is hovering over,
## and a yellow box on the target of a pending (unconfirmed) command.


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    var t := Bridge.target_at()
    if t != null:
        draw_rect(t.get_global_rect(), Color(1, 1, 1, 0.5), false, 2.0)
    if not Bridge.pending.is_empty() and is_instance_valid(Bridge.pending.target):
        draw_rect(Bridge.pending.target.get_global_rect(), Color(1, 0.9, 0.2), false, 4.0)
    draw_arc(Bridge.cursor, 16.0, 0.0, TAU, 32, Color(1, 0.35, 0.3), 3.0)
    draw_circle(Bridge.cursor, 4.0, Color(1, 0.35, 0.3))
