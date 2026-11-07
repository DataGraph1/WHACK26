# bomb-game integration

This Godot 4.7 project now uses the bundled GDMP plugin to show a camera preview and read the first visible hand. Its main scene is `scene/camera.tscn`, with the bridge in `scripts/camera.gd`.

## Camera bridge

`HandCamera.hand_position` is the index fingertip as a normalized `Vector2` in the mirrored camera image: `(0, 0)` is the top left and `(1, 1)` is the bottom right. Check `has_hand` first; when no hand is detected, the value is `(-1, -1)`. Subscribe to `hand_position_changed(position, has_hand)` rather than polling every frame.

`HandCamera.gesture` is a `HandCamera.Gesture` enum: `NONE`, `CLOSED_FIST`, `OPEN_PALM`, `POINTING_UP`, `THUMB_DOWN`, `THUMB_UP`, `VICTORY`, or `I_LOVE_YOU`. `gesture_confidence` is the recognizer score. Subscribe to `gesture_changed(value, confidence)` for changes. `tracking_context()` converts these values into a JSON-safe dictionary for the narrator.

The camera preview does not depend on the models being ready. On first run the bridge downloads the Hand Landmarker and Gesture Recognizer `.task` files into Godot's `user://GDMP` cache; it needs internet access for that first run. Keep Godot's camera permission enabled. The code tries the first available camera feed and supports RGB, YUY2 and planar YUV formats, following `GDMP-demo/project/vision/VisionTask.gd`.

## Narrator bridge

The project registers `scripts/NarratorClient.gd` as a `NarratorClient` Autoload. Start the Python service in [`../narrator`](../narrator/README.md) on the same computer, then call it from **actual game logic** after the result is known:

```gdscript
var camera_bridge: HandCamera = get_tree().current_scene
NarratorClient.begin_round("round-001", "wire_cutting", {"lives": 3, "seconds_left": 180})

# After the game decides whether the player's selection was correct:
var context := camera_bridge.tracking_context()
context["lives"] = lives
context["seconds_left"] = seconds_left
NarratorClient.send_result("wire_cutting", correct, selected_action, context)
```

Use a unique round ID each round and the current mini-game name for each event. For a hover or timer event, use `NarratorClient.post_event({"game": game_name, "kind": "focus", "context": {...}})` after `begin_round`. The game decides whether a hovered region, selection, timer threshold, or last life has happened. The client sends these observations to the agent; the agent chooses a line from supplied facts. No puzzle result, timer, or life logic exists in the uploaded project yet.

`NarratorClient.narration_ready(text, audio, decision)` gives the UI a caption and a decision for the live feed. The client plays the returned MP3 automatically; set `auto_play_audio = false` if the UI owns audio playback. `NarratorClient.narrator_error(message)` reports a missing backend or failed request. The default API URL is `http://127.0.0.1:8765/v1/events`; change `api_url` if Godot and the server run on different machines.
