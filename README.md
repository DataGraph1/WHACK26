# Bot Defusal (Godot 4)

## Run it
1. Open this folder in Godot 4.2+ (import `project.godot`). Let it finish importing once so the class names register.
2. Press F5. The `Bridge` autoload is already set in project.godot.
   Using your own project instead? Copy `scripts/`, `main.tscn`, and add the autoload
   `Bridge = res://scripts/bridge.gd`.

## Test without a camera
Mouse = cursor. Hold keys 1-7 for about 0.35s (they match the gesture numbers in the manual):
1 blue, 2 read, 3 yellow, 4 red, 5 green, 6 confirm, 7 cut/press. R restarts.
Example: hover a wire, hold 7, then hold 6 -> cut. Hover the button, tap 7 three times, then 6 -> three presses.

## Play with your hands
`pip install mediapipe opencv-python`, run `python gesture_bridge.py`, then start the game.
The game switches to camera input as soon as packets arrive, and back to mouse/keyboard if they stop.

## Files
- scripts/bridge.gd   gesture input + confirm / press-queue rules (autoload)
- scripts/bomb.gd     timer, strikes, serial number, batteries, indicators
- scripts/*_module.gd the four modules (rules copied from the v6 manual)
- scripts/main.gd, cursor.gd   bot screen, cursor drawing
- gesture_bridge.py   MediaPipe -> UDP

## Knobs
- BombModule.LOW_QUALITY (module_base.gd): true hides colors/text so the player must use gestures.
- Bridge.HOLD_TIME, CONFIRM_WINDOW (bridge.gd): gesture hold and confirm timing.
- Bomb.START_TIME, module_count (bomb.gd).
