extends Node
## Optional live check with an actual camera bridge already running.


func _ready() -> void:
    call_deferred("_check")


func _check() -> void:
    for attempt in 50:
        await get_tree().create_timer(0.1).timeout
        if Bridge.camera_preview_texture != null:
            var size := Bridge.camera_preview_texture.get_size()
            print("Camera preview: %d×%d" % [int(size.x), int(size.y)])
            get_tree().quit(0 if size.x >= 1280 and size.y >= 720 else 1)
            return
    push_error("Full-size preview did not reach Godot within five seconds")
    get_tree().quit(1)
