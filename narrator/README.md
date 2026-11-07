> Current integration: the playable root project now uses `scripts/NarratorClient.gd`. Start the root project, not the older `bomb-game` camera prototype. LLM and TTS requests now each have a three-second network timeout; failures produce explicitly labelled caption fallbacks. Captions remain available without audio. Tests use Python 3.12. See the root README and PROGRESS.md for current validation status.

# WHACK 2026 — live narrator service

This folder is the **narrator backend only**. It contains no game UI or simulated puzzle. The game logic decides what happened; this service decides whether to speak, writes a context-aware line with a local LLM, and speaks it with ElevenLabs **Liam – Energetic, Social Media Creator**. The Godot bridge lives in [`bomb-game/scripts/NarratorClient.gd`](../bomb-game/scripts/NarratorClient.gd).

## How Godot connects

Godot sends a JSON event to `POST http://127.0.0.1:8765/v1/events` using `HTTPRequest`. The API replies with caption text, the narrator's decision, and base64-encoded MP3 audio. [`NarratorClient.gd`](../bomb-game/scripts/NarratorClient.gd) is already registered as the **NarratorClient Autoload** in `bomb-game/project.godot`. It queues HTTP calls, emits `narration_ready(text, audio, decision)` for the UI caption, and plays the MP3 automatically. Set `auto_play_audio` to `false` if the UI manages audio itself.

Call it from the game logic **after it knows the result**. `HandCamera.tracking_context()` returns the observed right-hand pointer and left-hand command for event context:

```gdscript
var camera_bridge: HandCamera = get_tree().current_scene
NarratorClient.begin_round("round-001", "wire_cutting", {"lives": 3, "seconds_left": 180})
NarratorClient.update_round_state("wire_cutting", {
    "seconds_left": 84, "lives": 2, "strikes": 1
})
var context := camera_bridge.tracking_context()
context["lives"] = 2
context["seconds_left"] = 84
NarratorClient.send_result("wire_cutting", false, "cut the upper cable", context)
```

For another mini-game, change the `game` name and action. You can send other live events through `post_event`, for example `kind: "focus"` or `"inspection_request"`. `end_round` sends a game-end event and stops heartbeats. Use a new `round_id` each round. The `context` dictionary should contain **observed game facts**, such as module name, hovered part, time and lives. The current `bomb-game` upload has no puzzle result or timer logic yet; the running game must call `update_round_state` as those facts change. See the [bomb-game integration notes](../bomb-game/README.md).

### Live pacing, uncertainty, and memory

After `begin_round`, the Godot client sends a `state` heartbeat about once per second. It includes elapsed and idle time, both hands' tracking context, and any fresh game facts supplied through `update_round_state` within the last five seconds. Fresh state and tracking facts are merged into other events too, so a result can reflect the current pressure. The server handles routine state updates without an LLM call. It asks the LLM to speak when the timer first passes 60, 30, or 10 seconds; when the player reaches the last life; or when the right hand is visible and no game action has happened for at least 12 seconds. Hesitation prompts have a 20-second cooldown. Camera uncertainty events have an eight-second cooldown and ask for a repeat instead of guessing. Explicit result and end events still speak.

The agent remembers visited games, inspected targets, recent events and spoken lines, plus its wrong-answer streak and total mistakes. The LLM sees this memory to avoid repetition and adapt its tone. `begin_round` resets the memory. The server's response has `trigger`, `observed_kind`, and a short `reason` for the optional live feed. Timer and life facts are always provided by the game; the agent does not invent them.

### Event contract

```json
{
  "session_id": "round-001",
  "event_id": "unique-event-id",
  "game": "wires",
  "kind": "result",
  "result": "correct",
  "action": "cut wire 2",
  "context": {"lives": 2, "seconds_left": 84}
}
```

`session_id`, `game`, and `kind` are required. `result` is required for `kind: "result"` and must be `correct` or `wrong`. `event_id`, `action`, and `context` are optional. A successful response looks like:

```json
{
  "say": true,
  "text": "Correct! That module is safely behind us; keep moving.",
  "mood": "cheerful",
  "reason": "A confirmed result should be acknowledged",
  "voice": "Liam - Energetic, Social Media Creator",
  "voice_id": "TX3LPaxmHKxFdv7VOQHJ",
  "audio_mime_type": "audio/mpeg",
  "audio_base64": "...",
  "event_id": "unique-event-id",
  "session_id": "round-001",
  "game": "wires",
  "trigger": "result",
  "observed_kind": "result"
}
```

The LLM sees the current event, recent events, previous lines, and round memory. It decides when to stay quiet on routine events and writes lines from supplied facts. The server adds the verified correct/wrong prefix itself. Results and urgent warnings always speak. Duplicate event IDs are ignored. The `reason` field is for a live agent feed; it is not spoken.

**Only correct/wrong is insufficient for game-specific speech.** At minimum send `game`; send `action` and `context` for descriptions of the specific module, timer and lives. The narrator will not infer those details from a binary result.

## Run the text model and ElevenLabs voice

Text: [Ollama's chat API](https://docs.ollama.com/api/chat) with `qwen2.5:1.5b` by default. This model is approximately 1 GB and [Apache 2.0 licensed](https://registry.ollama.com/library/qwen2.5). Speech: [ElevenLabs' text-to-speech API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert) with voice ID `TX3LPaxmHKxFdv7VOQHJ` for **Liam – Energetic, Social Media Creator**. The default speech model is `eleven_v4_turbo`, which [supports audio tags for expressive, real-time delivery](https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/how-do-audio-tags-work-with-eleven-v3-and-v4). ElevenLabs is a hosted service and requires your own API key and available credits.

Liam is one of the account's Default voices. A speech request for Liam succeeded using the WHACK26 Free account. Voice Library voices such as Mark returned HTTP 402 `payment_required` on that account.

1. Install [Ollama](https://ollama.com/download), then run `ollama pull qwen2.5:1.5b`. Start Ollama if it is not running.
2. Create an ElevenLabs API key at [Developers → API Keys](https://elevenlabs.io/app/developers/api-keys). Copy `.env.example` to `.env` beside `agent_api.py` and set `ELEVENLABS_API_KEY` there. The server reads this ignored local file at startup; an existing environment variable takes precedence. Keep the key out of Godot and GitHub.
3. Run this server with Python 3.10 or newer. It uses only the Python standard library:

```bash
python3.12 agent_api.py
```

The API listens on `127.0.0.1:8765` by default. Change `NARRATOR_HOST` and `NARRATOR_PORT` if Godot runs on a different device. If Godot is exported as a browser game on a different origin, set `NARRATOR_ALLOW_ORIGIN` to that exact origin. If Godot and the API run on the same computer, the default URL works. Without Ollama, the service returns labelled factual fallback text; without ElevenLabs, it returns captions without audio.

Configuration: `OLLAMA_URL`, `OLLAMA_MODEL`, `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_VOICE_NAME`, and `ELEVENLABS_MODEL_ID` can be set in the environment or local `.env`. `GET /health` reports whether a key is configured, without exposing it. The server sends `[happy]`, `[worried]`, `[tense]`, or `[urgent]` as voice directions while keeping the displayed caption free of tags. Set `ELEVENLABS_MODEL_ID=eleven_v3` if your account does not have access to v4 Turbo.

For background on the bridge, see the official [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html) and [AudioStreamMP3](https://docs.godotengine.org/en/stable/classes/class_audiostreammp3.html) documentation. The GDScript adapter targets Godot 4.4 or later.
