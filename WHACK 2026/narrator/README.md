# WHACK 2026 — live narrator service

This folder is the **narrator backend and Godot connection only**. It contains no game UI or simulated puzzle. The game AI decides what happened; this service decides whether to speak, writes a context-aware line with a local LLM, and renders it through an open-weight voice model.

## How Godot connects

Godot sends a JSON event to `POST http://127.0.0.1:8765/v1/events` using `HTTPRequest`. The API replies with caption text, the narrator's decision, and base64-encoded WAV audio. [GodotNarratorClient.gd](GodotNarratorClient.gd) queues HTTP calls and emits `narration_ready(text, audio, decision)` for your UI teammate to connect to a Label and AudioStreamPlayer. Add it as an **Autoload** named `NarratorClient` in Project Settings.

Call it from the game or gesture AI **after it knows the result**:

```gdscript
NarratorClient.begin_round("round-001", "wire_cutting")
NarratorClient.send_result("wire_cutting", false, "cut the upper cable", {
    "lives": 2, "seconds_left": 84
})
```

For another mini-game, change the `game` name and action. You can send other live events through `post_event`, for example `kind: "focus"`, `"time_warning"`, `"last_life"`, or `"game_ended"`. Use a new `round_id` each round. The `context` dictionary should contain **observed game facts**, such as module name, hovered part, time and lives. Godot's `.gd` source file does not itself contain the live game state; the running Godot project must send that state through the API.

### Event contract

```json
{
  "session_id": "round-001",
  "event_id": "unique-event-id",
  "game": "keypad",
  "kind": "result",
  "result": "correct",
  "action": "pressed the star key",
  "context": {"lives": 2, "seconds_left": 84}
}
```

`session_id`, `game`, and `kind` are required. `result` is required for `kind: "result"` and must be `correct` or `wrong`. `event_id`, `action`, and `context` are optional. A successful response looks like:

```json
{
  "say": true,
  "text": "Correct! That star key clicked into place; keep the momentum going.",
  "mood": "cheerful",
  "reason": "A confirmed result should be acknowledged",
  "voice": "af_heart",
  "audio_mime_type": "audio/wav",
  "audio_base64": "...",
  "event_id": "unique-event-id",
  "session_id": "round-001",
  "game": "keypad"
}
```

The LLM sees the current event, recent events, previous lines, and wrong-answer streak. It decides when to stay quiet on routine events and writes lines from the supplied facts. The server adds the verified correct/wrong prefix itself. Results and urgent warnings always speak. Duplicate event IDs are ignored. The `reason` field is for a live agent feed; it is not spoken.

**Only correct/wrong is insufficient for game-specific speech.** At minimum send `game`; send `action` and `context` for descriptions of the specific module, timer and lives. The narrator will not infer those details from a binary result.

## Run the two local models

Text: [Ollama's chat API](https://docs.ollama.com/api/chat) with `qwen2.5:1.5b` by default. This model is approximately 1 GB and [Apache 2.0 licensed](https://registry.ollama.com/library/qwen2.5). Speech: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) through [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx), default voice `af_heart`. These are separate local models; the voice is a quality starting point that should be auditioned with your team.

1. Install [Ollama](https://ollama.com/download), then run `ollama pull qwen2.5:1.5b`. Start Ollama if it is not running.
2. In this folder, create a Python 3.12 virtual environment and install `requirements.txt`:

```bash
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
mkdir -p models
curl -L -o models/kokoro-v1.0.int8.onnx https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.int8.onnx
curl -L -o models/voices-v1.0.bin https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin
.venv/bin/python agent_api.py
```

The API listens on `127.0.0.1:8765` by default. Change `NARRATOR_HOST` and `NARRATOR_PORT` if Godot runs on a different device. If Godot is exported as a browser game on a different origin, set `NARRATOR_ALLOW_ORIGIN` to that exact origin. If Godot and the API run on the same computer, the default URL works. The models are not bundled in Git; until installed, the API returns HTTP 503 instead of inventing output.

Configuration: `OLLAMA_URL`, `OLLAMA_MODEL`, `KOKORO_MODEL_PATH`, `KOKORO_VOICES_PATH`, and `NARRATOR_VOICE` are environment variables. `GET /health` reports whether the voice files are present.

For background on the bridge, see the official [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html) and [AudioStreamWAV](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html) documentation. The GDScript adapter targets Godot 4.4 or later.
