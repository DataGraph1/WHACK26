> The playable project is at the repository root. `bomb-game` is an archived camera prototype. Start root `project.godot`; see the root README and PROGRESS.md for setup and validation.

# WHACK 2026 — live narrator service

This folder is the **narrator backend only**. It contains no game UI or simulated puzzle. The game logic decides what happened; this service decides whether to speak, writes a context-aware line with a local LLM, and speaks it with ElevenLabs **Liam – Energetic, Social Media Creator**. The Godot client lives in [`scripts/NarratorClient.gd`](../scripts/NarratorClient.gd).

## How Godot connects

Godot sends a JSON event to `POST http://127.0.0.1:8765/v1/events` using `HTTPRequest`. The API replies with caption text, its decision, and base64-encoded MP3 audio. [`NarratorClient.gd`](../scripts/NarratorClient.gd) is registered as the **NarratorClient Autoload** in root `project.godot`. It queues HTTP calls, emits `narration_ready(text, audio, decision)` for the UI caption, and plays the MP3 automatically. Set `auto_play_audio` to `false` if the UI manages audio itself.

Call it from game logic **after it knows the result**. `Bridge.tracking_context()` returns the observed right-hand pointer and left-hand command for event context:

```gdscript
NarratorClient.begin_round("round-001", "bomb", {"lives": 3, "seconds_left": 180})
NarratorClient.update_round_state("bomb", {
    "seconds_left": 84, "lives": 2, "strikes": 1
})
var context := Bridge.tracking_context()
context["lives"] = 2
context["seconds_left"] = 84
NarratorClient.send_result("WIRES", false, "cut wire 2", context)
```

For another module, change the `game` name and action. You can send other live events through `post_event`, for example `kind: "focus"` or `"inspection_request"`. `end_round` sends a game-end event and stops heartbeats. Use a new `round_id` each round. The `context` dictionary should contain **observed game facts**, such as module name, hovered part, time and lives. Root [`scripts/bomb.gd`](../scripts/bomb.gd) supplies these facts during play.

### Live pacing, uncertainty, and memory

After `begin_round`, the Godot client sends a `state` heartbeat about once per second. It includes elapsed and idle time, both hands' tracking context, and recent game facts supplied through `update_round_state`. The server handles routine state updates without an LLM call. When the timer crosses 60, 30, or 10 seconds, when the player reaches the last life, or when camera tracking is uncertain, the server writes a short line directly from current verified state. When the right hand is visible and the player has been idle at least 12 seconds, the LLM may offer a pacing prompt. Pacing and uncertainty have cooldowns. Wrong and module-completion results speak; rapid intermediate correct stages can stay quiet because the game acknowledges them immediately. A closed round suppresses later events.

The agent remembers visited games, inspected targets, recent events and spoken lines, plus its wrong-answer streak and total mistakes. The LLM sees sanitized observations to avoid repetition and adapt its tone. Numeric timer and life counts are kept out of its prompt; the server adds those only from current game state. `begin_round` resets memory. The response has `trigger`, `observed_kind`, a short `reason`, and `policy_guarded` or `fallback` when applicable for the live feed.

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

The LLM sees the current event, recent events, previous lines, and round memory, with numeric counters removed. It writes short commentary for observations that merit speech. The server adds the verified correct/wrong prefix itself. Timer, life, uncertainty, start, and end lines are guarded and composed from verified state. Duplicate event IDs are ignored. The `reason` field is for the live feed; it is not spoken.

Focus lines are discarded by the Godot client if the pointer has moved to another target while Qwen and speech were running. Model lines can occasionally be rejected as `FALLBACK` if they ask a question or make an unsupported claim about the clock, lives, tracking, or an unfinished module. This keeps the live feed honest about what the model actually wrote.

**Only correct/wrong is insufficient for game-specific speech.** At minimum send `game`; send `action` and `context` for descriptions of the specific module, timer and lives. The narrator will not infer those details from a binary result.

## Run the text model and ElevenLabs voice

Text: [Ollama's chat API](https://docs.ollama.com/api/chat) with `qwen2.5:3b` by default. Speech: [ElevenLabs' text-to-speech API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert) with voice ID `TX3LPaxmHKxFdv7VOQHJ` for **Liam – Energetic, Social Media Creator**. The default speech model is `eleven_v4_turbo`. ElevenLabs is a hosted service and requires your own API key and available credits. Set `OLLAMA_MODEL` to another locally installed model if your laptop cannot run the default comfortably.

Liam is one of the account's Default voices. A speech request for Liam succeeded using the WHACK26 Free account. Voice Library voices such as Mark returned HTTP 402 `payment_required` on that account.

1. Install [Ollama](https://ollama.com/download), then run `ollama pull qwen2.5:3b`. Start Ollama if it is not running.
2. Create an ElevenLabs API key at [Developers → API Keys](https://elevenlabs.io/app/developers/api-keys). Copy `.env.example` to `.env` beside `agent_api.py` and set `ELEVENLABS_API_KEY` there. The server reads this ignored local file at startup; an existing environment variable takes precedence. Keep the key out of Godot and GitHub.
3. Run this server with Python 3.10 or newer. It uses only the Python standard library:

```bash
python3.12 agent_api.py
```

The API listens on `127.0.0.1:8765` by default. Change `NARRATOR_HOST` and `NARRATOR_PORT` if Godot runs on a different device. If Godot is exported as a browser game on a different origin, set `NARRATOR_ALLOW_ORIGIN` to that exact origin. If Godot and the API run on the same computer, the default URL works. Without Ollama, the service returns labelled factual fallback text; without ElevenLabs, it returns captions without audio.

Configuration: `OLLAMA_URL`, `OLLAMA_MODEL`, `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_VOICE_NAME`, and `ELEVENLABS_MODEL_ID` can be set in the environment or local `.env`. `GET /health` reports whether a key is configured, without exposing it. The server sends `[happy]`, `[worried]`, `[tense]`, or `[urgent]` as voice directions while keeping the displayed caption free of tags. Set `ELEVENLABS_MODEL_ID=eleven_v3` if your account does not have access to v4 Turbo.

For background on the bridge, see the official [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html) and [AudioStreamMP3](https://docs.godotengine.org/en/stable/classes/class_audiostreammp3.html) documentation. The GDScript adapter targets Godot 4.4 or later.
