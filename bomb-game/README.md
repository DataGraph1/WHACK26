# bomb-game integration

This Godot 4.7 project uses the bundled GDMP plugin to show a camera preview and track both hands. Its committed main scene is `scene/camera.tscn`, with the bridge in `scripts/camera.gd`. The latest teammate commit referenced a different main scene and `ModuleSelection` Autoload, but did not include either file; those broken references were removed so this checkout opens.

## Camera bridge

`HandCamera.right_hand_position` is the right index fingertip as a normalized `Vector2` in the mirrored camera image: `(0, 0)` is the top left and `(1, 1)` is the bottom right. Check `right_hand_visible` first; when absent, the value is `(-1, -1)`. `left_hand_position` and `left_hand_visible` are also exposed. Subscribe to `right_hand_position_changed(position, visible)` and `left_hand_position_changed(position, visible)` rather than polling. The teammate's cursor follows the right hand.

`left_gesture` and `right_gesture` use the `HandCamera.Gesture` enum: `NONE`, `CLOSED_FIST`, `OPEN_PALM`, `POINTING_UP`, `THUMB_DOWN`, `THUMB_UP`, `VICTORY`, or `I_LOVE_YOU`. Subscribe to `left_gesture_changed(value, confidence)` for commands. A gesture must hold for 180 ms at confidence 0.65 or higher; a left-hand command is withheld while the right pointer is missing. `tracking_uncertain(reason, context)` reports low confidence or a missing pointer, and the camera forwards it to the narrator after a round starts. Use the exported `swap_handedness` switch if the physical camera labels the hands backwards.

For compatibility, `hand_position`, `has_hand`, and `hand_position_changed` alias the **right** hand; `gesture`, `gesture_confidence`, and `gesture_changed` alias the **left** command. `tracking_context()` returns both hands as a JSON-safe dictionary. The old signal names remain connected, but game logic should use the explicit names above.

The camera preview does not depend on the models being ready. On first run the bridge downloads the Hand Landmarker and Gesture Recognizer `.task` files into Godot's `user://GDMP` cache; it needs internet access for that first run. Keep Godot's camera permission enabled. The code tries the first available camera feed and supports RGB, YUY2 and planar YUV formats, following `GDMP-demo/project/vision/VisionTask.gd`.

## Narrator bridge

The project registers `scripts/NarratorClient.gd` as a `NarratorClient` Autoload. Start the Python service in [`../narrator`](../narrator/README.md) on the same computer. The camera registers itself as a tracking source; the client sends its latest hand state in a one-second heartbeat after `begin_round`. Game logic must supply authoritative timer/lives/strikes facts as they change:

```gdscript
var camera_bridge: HandCamera = get_tree().current_scene
NarratorClient.begin_round("round-001", "wire_cutting", {"lives": 3, "seconds_left": 180})

# From the real timer/strike logic, ideally once per second:
NarratorClient.update_round_state("wire_cutting", {
    "seconds_left": seconds_left,
    "lives": lives,
    "strikes": strikes,
})

# After the game decides whether the player's selection was correct:
var context := camera_bridge.tracking_context()
context["lives"] = lives
context["seconds_left"] = seconds_left
NarratorClient.send_result("wire_cutting", correct, selected_action, context)

# When the bomb is actually resolved:
NarratorClient.end_round("wire_cutting", {"defused": defused})
```

Use a unique round ID each round and the current mini-game name for each event. For a meaningful inspection, send `NarratorClient.post_event({"game": game_name, "kind": "inspection_request", "context": {"target": "wire 2", "observed_colour": "blue"}})` after the game has identified the target and observed fact. The narrator does not calculate puzzle answers. The one-second heartbeat may trigger a single hesitation prompt after 12 seconds of inactivity with the right hand visible, plus 60/30/10-second warnings or a last-life warning when `update_round_state` supplies fresh facts. Routine heartbeats do not call the LLM. Round memory tracks visited games, inspected targets, previous lines, and mistakes; `begin_round` clears it.

The committed project still has no puzzle result, timer, or life logic. `update_round_state` must be called by that game code for timer and life narration to be accurate. Fresh state and tracking facts are also merged into result and inspection events automatically. Avoid sending a stale countdown value: state facts expire from event context after five seconds without an update.

`NarratorClient.narration_ready(text, audio, decision)` gives the UI a caption and a decision for the live feed. `decision.trigger`, `decision.observed_kind`, and `decision.reason` explain why the agent spoke or stayed quiet. The client plays the returned MP3 automatically; set `auto_play_audio = false` if the UI owns audio playback. `NarratorClient.narrator_error(message)` reports a missing backend or failed request. The default API URL is `http://127.0.0.1:8765/v1/events`; change `api_url` if Godot and the server run on different machines.
