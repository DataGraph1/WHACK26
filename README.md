# Bot Defusal

A solo bomb puzzle played through a remote robot. The webcam tracks the right hand's pointer and the left hand's command gesture. A local Qwen narrator watches structured game events and chooses when to speak; ElevenLabs Liam voices its lines. The game decides puzzle results. The narrator does not receive hidden solutions or raw video frames.

Open **this repository's root** `project.godot` in Godot 4.7. The nested `bomb-game` and `GDMP-demo` projects are older prototypes.

## One-command demo on this laptop

```sh
python3.12 launch.py --check
python3.12 launch.py
```

The launcher checks Godot, the camera environment, the local model and the voice key, warms Qwen, starts the API if needed, and opens the game. It writes process logs to ignored `.runtime/`. Press Ctrl-C to stop processes it started. If the narrator or voice is unavailable, the game reports that in its event feed and keeps local command feedback; a running narrator API returns labelled caption fallbacks.

## Setup on another laptop

1. Install Godot 4.7, Python 3.12 and [Ollama](https://ollama.com/download). Run `ollama pull qwen2.5:3b`.
2. In this directory, run `python3.12 -m venv .venv` and `.venv/bin/python -m pip install -r requirements-camera.txt`. On Windows, use `py -3.12 -m venv .venv` and `.venv\Scripts\python -m pip install -r requirements-camera.txt`.
3. Copy `narrator/.env.example` to `narrator/.env` and set your ElevenLabs API key. That ignored file must stay off GitHub. Liam is configured as the voice.
4. Run `python3.12 launch.py`. If Godot is not on PATH, set `GODOT_BIN` to its executable. On a different computer or port, update the API URL in `scripts/NarratorClient.gd`.

The camera bridge starts from `.venv` automatically. On first launch it downloads the gesture model. It tries camera indices 0–2 and skips black feeds. You can force a device by starting `.venv/bin/python gesture_bridge.py --no-preview --camera-index 1` first. The game uses the existing bridge. Camera preview appears on the welcome screen before the timer starts.

If the game shows **CAMERA WAITING FOR PERMISSION**, approve the macOS camera popup; the bridge retries for about 20 seconds. If it changes to **CAMERA ACCESS BLOCKED**, quit the game, open **System Settings → Privacy & Security → Camera**, enable whichever app macOS lists for this run (Terminal, Python or Godot), then run `python3.12 launch.py` again. `launch.py --check` verifies installed camera packages, not macOS permission; the actual camera is checked when the game opens. The detailed OpenCV message is in `.runtime/game.log`.

The status panel separately shows whether the left command hand and right pointer hand are detected. "Left: seen / None" means the hand is visible but its current pose is not a recognized command. Keep both hands apart, fully in frame and well lit. The welcome screen has a camera rehearsal: hold both hands in view, move the right pointer, and show Open Palm, Victory, I-love-you, and Closed Fist with the left. It records which checks passed; a full human round is still needed. The camera image is mirrored **only for display**; MediaPipe receives the original image so it assigns the correct hand roles. If a camera driver already supplies mirrored frames and the roles still appear reversed, start with `WHACK_SWAP_HANDS=1 python3.12 launch.py` (or pass `--swap-hands` to `gesture_bridge.py`).

## Play

Print [revision 7 of the field guide](docs/PLAYER_MANUAL_print.html), or read its [Markdown source](docs/PLAYER_MANUAL.md). Older v2/v6 rules are incompatible. Choose two modules for a short demo or four for a full round. Every round has 180 seconds and three lives. Link Recovery always appears; the other modules are selected randomly.

Right index finger points. Left hand gestures query colour, read text, queue a press, or confirm. Hold a gesture for about 0.35 seconds. Release between repeated presses. The right pointer must stay visible and stable until confirmation. An uncertain left gesture is ignored; losing the right pointer cancels pending commands. Press K to use the mouse and keys 1–7 even if a camera is connected. R restarts.

The live feed shows observed events, remembered inspection facts, speak/quiet decisions, reasons and response time. `GUARD` marks lines composed from verified state for inspections, timer, life, tracking and round boundaries; `MODEL` marks model-written commentary; `FALLBACK` marks a model failure. The narrator receives the active module, observed target, queued press before confirmation, question/result, round timer, lives and tracking state. It can react to focus, hesitation, pending choices, uncertain tracking, mistakes and warnings. Inspection facts are spoken with their target names. The game remains authoritative over correct and wrong outcomes; a pending cue is discarded if the player confirms or moves away first.

See [the judge demo guide](docs/DEMO.md) for a short presentation sequence and honest account of how the camera and narrator communicate.

## Checks

```sh
python3.12 narrator/test_agent.py
python3.12 -m unittest discover -s tests -p 'test_*.py'
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/game_integration.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/narrator_live.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/preconfirm_live.tscn
```

The two live checks require the local narrator API, Qwen and ElevenLabs key. Replace the macOS Godot path on other systems. The first checks cover agent state and real game actions; the live checks verify a result and a pre-confirmation decision with decoded Liam MP3 in Godot. They disable speaker playback during automated testing; listen to the voice in the running game before presenting. Run `python3.12 tools/build_manual.py` after changing the Markdown field guide, then commit the updated printable HTML.
