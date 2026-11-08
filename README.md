# Bot Defusal

A solo bomb puzzle played through a remote robot. The webcam tracks the right hand's pointer and the left hand's command gesture. A local Qwen narrator watches structured game events and chooses when to speak; ElevenLabs Liam voices its lines. The game decides puzzle results. The narrator does not receive hidden solutions or raw video frames.

Open **this repository's root** `project.godot` in Godot 4.7. The nested `bomb-game` and `GDMP-demo` projects are older prototypes.

## One-command demo on this laptop

```sh
python3.12 launch.py --check
python3.12 launch.py
```

The launcher checks Godot, the camera environment, the local model and the voice key, runs a short Qwen inference, starts the API if needed, and opens the game. It writes process logs to ignored `.runtime/`. Press Ctrl-C to stop processes it started. Pressing Play in Godot now checks for the narrator and starts the local API from `.venv` if needed; Ollama and the model must still be installed. The status panel shows whether the agent is connected, Qwen is available, and a Liam key is configured. If the narrator or voice is unavailable, the game reports that in its event feed and keeps local command feedback. Press F11 to switch between windowed and fullscreen mode. The 16:9 game scales with the window.

## Setup on another laptop

1. Install Godot 4.7, Python 3.12 and [Ollama](https://ollama.com/download). Run `ollama pull qwen2.5:3b`.
2. In this directory, run `python3.12 -m venv .venv` and `.venv/bin/python -m pip install -r requirements-camera.txt`. On Windows, use `py -3.12 -m venv .venv` and `.venv\Scripts\python -m pip install -r requirements-camera.txt`.
3. Copy `narrator/.env.example` to `narrator/.env` and add an ElevenLabs API key authorized for Liam. On Windows PowerShell, use `Copy-Item narrator/.env.example narrator/.env`; on macOS, use `cp narrator/.env.example narrator/.env`. Ask the account owner for the key through a private channel. Liam's voice ID and model are already configured in the committed example. Run `py -3.12 tools/check_voice.py` on Windows or `python3.12 tools/check_voice.py` on macOS; it writes a short MP3 to ignored `.runtime/` and reports voice access or the exact API error. The key stays in each teammate's ignored local file.
4. Run `python3.12 launch.py`. On Windows, run `py -3.12 launch.py --check`, then `py -3.12 launch.py` in PowerShell. If Godot is not on PATH, set `GODOT_BIN` to its executable. On a different computer or port, update the API URL in `scripts/NarratorClient.gd`.

The camera bridge starts from `.venv` automatically. On first launch it downloads the gesture model. On macOS it identifies the built-in camera by AVFoundation device type and will not open an iPhone Continuity or USB camera, even if the built-in camera is unavailable. On Windows it opens only default camera index 0 and does not try other devices. It sends hand coordinates on UDP port 4242 and serves the captured full-resolution JPEG preview on local port 4243. The game shows a larger preview in the sidebar; press **P** to enlarge it over the board and P again to return. Hand inference uses a smaller copy of each frame to keep tracking responsive.

If the feed says **Model unavailable; factual fallback**, this refers to the local Ollama text model, not ElevenLabs speech. On Windows, run `ollama list` and confirm `qwen2.5:3b` is installed; if missing, run `ollama pull qwen2.5:3b`. Start Ollama, stop any old narrator service on port 8765, then run `py -3.12 launch.py --check` and `py -3.12 launch.py`. The live feed now shows whether Ollama is unreachable, the model is missing, or inference timed out. A slower Windows laptop can set `OLLAMA_TIMEOUT_SECONDS` in `narrator/.env`, but responses taking tens of seconds will be too late for live play.

If the game shows **CAMERA WAITING FOR PERMISSION**, approve the macOS camera popup; the bridge retries for about 20 seconds. If it changes to **CAMERA ACCESS BLOCKED**, quit the game, open **System Settings → Privacy & Security → Camera**, enable whichever app macOS lists for this run (Terminal, Python or Godot), then run `python3.12 launch.py` again. `launch.py --check` verifies installed camera packages, not macOS permission; the actual camera is checked when the game opens. The detailed OpenCV message is in `.runtime/game.log`.

The status panel separately shows whether the left command hand and right pointer hand are detected. "Left: seen / None" means the hand is visible but its current pose is not a recognized command. Keep both hands apart, fully in frame and well lit. The welcome screen has a camera rehearsal: hold both hands in view, move the right pointer, and show Open Palm, Victory, I-love-you, and Closed Fist with the left. It records which checks passed; a full human round is still needed. The camera image is mirrored **only for display**; MediaPipe receives the original image so it assigns the correct hand roles. If a camera driver already supplies mirrored frames and the roles still appear reversed, start with `WHACK_SWAP_HANDS=1 python3.12 launch.py` (or pass `--swap-hands` to `gesture_bridge.py`).

## Play

Print [revision 10 of the field guide](docs/PLAYER_MANUAL_print.html), or read its [Markdown source](docs/PLAYER_MANUAL.md). Older guides have different controls. Choose two modules for a three-minute demo or four for an eight-minute round. Every round has three lives. Link Recovery always appears; the other modules are selected randomly.

The bomb-module format and Memory puzzle are inspired by Keep Talking and Nobody Explodes. Remote gesture controls, Link Recovery and the live observing narrator are original to this project.

Right index finger points. The pointer now reaches the board edges with less arm travel. A left fist locks the hovered target (yellow outline); another fist on a different target moves the lock, while a fist on the same target asks if it is blue. With a lock, the left hand can query colour, read text, queue a press, and confirm even after the right pointer moves or leaves view. An orange outline marks a pending command. Hold a gesture for about 0.35 seconds and release between repeats. Link Recovery needs continuous right-pointer contact and an open left palm; brief tracking flickers now pause its charge before a sustained loss resets it. Press K to use the mouse and keys 1–7 even if a camera is connected. R restarts.

The live feed shows observed events, remembered inspection facts, speak/quiet decisions, reasons and response time. `GUARD` marks lines composed from verified state for inspections, timer, life, tracking and round boundaries; `MODEL` marks model-written commentary; `FALLBACK` marks a model failure. The narrator receives the active module, locked target, queued press before confirmation, question/result, round timer, lives and tracking state. It reacts to target locks, pending choices, restored link contacts, uncertain tracking, mistakes, and five-, three-, and one-minute warnings when applicable. Inspection facts are spoken with their target names. The game remains authoritative over correct and wrong outcomes; a pending cue is discarded if its command is confirmed, cancelled, or replaced before the response returns. If Liam cannot generate audio, the feed displays the actual speech-service error beside the caption.

See [the judge demo guide](docs/DEMO.md) for a short presentation sequence and honest account of how the camera and narrator communicate.

## Checks

```sh
python3.12 narrator/test_agent.py
python3.12 -m unittest discover -s tests -p 'test_*.py'
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/game_integration.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/narrator_live.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/preconfirm_live.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/camera_preview_live.tscn
```

The narrator live checks require the local narrator API, Qwen and ElevenLabs key. The camera preview check requires a running `.venv/bin/python gesture_bridge.py --no-preview` first. Replace the macOS Godot path on other systems. The first checks cover agent state and real game actions; the live checks verify a result and a pre-confirmation decision with decoded Liam MP3 in Godot. They disable speaker playback during automated testing; listen to the voice in the running game before presenting. Run `python3.12 tools/build_manual.py` after changing the Markdown field guide, then commit the updated printable HTML.
