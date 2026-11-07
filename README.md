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
Create a Python environment in this project folder, then install the camera dependencies:

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements-camera.txt
```

On Windows, use `py -3.12 -m venv .venv` and `.venv\Scripts\python -m pip install -r requirements-camera.txt`.
Press F5 in Godot. The game starts `gesture_bridge.py` automatically if `.venv` is present.
The webcam preview appears inside the game. The status shows whether the camera is connected,
how many hands are visible, and whether the right-hand cursor was found.
The bridge tries the first three camera devices and skips a device that returns only black frames.
To force a device, start `.venv/bin/python gesture_bridge.py --no-preview --camera-index 1`
before starting Godot; the game will use that bridge instead of launching another one.
Mouse and keyboard controls return if the camera bridge stops.

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
