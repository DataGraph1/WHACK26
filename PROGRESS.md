# Implementation handover

Current request: implement all ten ranked improvements from the incident.io review.

## Completed in first checkpoint
- Root playable Godot project now registers NarratorClient, sends round start/state/end and inspection/result events, and displays captions and a decision reason.
- Camera packets now carry recognition confidence. Root input cancels pending commands on pointer/confidence loss and connection transitions.
- Game now consistently uses 180 seconds and three strikes, with no accelerated clock.
- Narrator HTTP timeout, stale queued event rejection, round restart audio cancellation, and terminal-event queue priority added.
- Godot import and headless startup passed; existing three narrator unit tests passed under Python 3.12.

## Still required (do not describe task as complete)
- Meaningful integration tests covering actual Godot events, safety gates, terminal outcomes and restart.
- Full live Ollama and ElevenLabs validation; narrator was not running during review. Do not print or commit .env secrets.
- Update physical manual to exact current puzzle rules, remove copied prose, include Memory. Existing attached v2 differs; README refers to unavailable v6.
- Implement original robot-specific mechanic, richer proactive observation, useful memory, audio priority/fallback and latency measurement.
- Validate missing-pointer reacquisition and held gestures; current gate relies on confidence packets and hold time.
- User-facing setup, calibration/onboarding, playtesting and two-minute demo guide.
- Synchronize obsolete bomb-game integration documentation with root project; avoid maintaining two diverging clients.
- No changes pushed yet. User requested implementation; earlier push request preceded this work.

## Environment
Repo: /Users/kp/Documents/Codex/2026-11-07/i/work/WHACK26
Godot: /Applications/Godot.app/Contents/MacOS/Godot
Python: python3.12 (system python3 is too old).
Credit balance is not exposed; checkpoints are periodic rather than tied to 5% remaining.
