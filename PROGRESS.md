# WHACK26 implementation handover

This file records progress for the user's request to implement the ten review priorities. Credit balance is not exposed, so commits are made as checkpoints. Current playable project: repository root `project.godot`; nested `bomb-game` and `GDMP-demo` are older prototypes.

## Done

- Root playable game posts real round, focus, inspection, queued action before confirmation, result, uncertainty, state and end events to the narrator API. Captions, observed facts, speak/quiet decisions, reasons and measured round-trip time appear in the game. ElevenLabs Liam audio plays from returned MP3.
- MediaPipe camera bridge reports both hand roles separately, pointer and gesture confidence, and preview. Recognition uses the unmirrored image so anatomical hand labels stay correct; only the preview and cursor X are mirrored. Earlier code flipped frames before recognition, reversing the current MediaPipe hand-task labels. A `WHACK_SWAP_HANDS=1` override supports cameras whose drivers already mirror frames. The right pointer must be reliable for commands. Left gesture release keeps a queued command; low-confidence gestures are ignored; losing the pointer cancels pending actions. K toggles mouse/keyboard control.
- A live startup log showed macOS refusing OpenCV camera access while Godot was running; the older bridge exited before a person could approve the popup. The bridge now retries for about 20 seconds, sends waiting/blocked status into Godot, and the launcher says explicitly that `--check` does not verify camera permission. A person must still grant access in macOS and rerun the game to confirm a real preview.
- Restarting or leaving a round cancels its outstanding narration and disables old input. The two-module demo always selects Link Recovery and Wires.
- Countdown and lives consistently use 180 seconds and three strikes. Start screen has a camera rehearsal checklist before choosing a two- or four-module round. Physical completion by a person still needs to be observed.
- Added original Link Recovery module using a continuous stable hand hold, interruption and recovery events. Four established modules remain available.
- Revision 7 manual precisely documents current rules, controls and Memory; old copied manual prose was rewritten. Self-contained printable HTML is generated from Markdown.
- Backend uses round memory, pacing and warning decisions, guarded critical-state and inspection phrasing, latency metrics and explicit caption fallbacks. Inspections speak the target and observed answer. The model can decide whether a pending cut needs a grounded cue; if the player confirms before its response, the client discards the stale cue. Numeric clock/life claims come only from current game state. A wrong result cannot tell the player to abandon an unfinished module, reuse a cut wire or blame tracking for a confirmed puzzle mistake. Rapid intermediate correct stages stay quiet. Client bounds request time, coalesces heartbeat state, gives terminal events priority and discards focus narration after the pointer moves.
- `launch.py` checks and starts the local demo stack. README and demo guide document setup and pitch.

## Evidence

- Godot 4.7.2 import and headless startup succeeded.
- `tests/game_integration.tscn` passes for real wire result, confidence gating, left-hand gesture release, pointer loss, Link Recovery, three-strike failure and outgoing narrator events.
- Twenty Python narrator tests and four hand-role tests pass under Python 3.12. `launch.py --check` passes with local Godot, camera environment, Qwen 3B and configured Liam key. Godot integration exercises left-hand command packets, both-hand gating, and a queued action before a real wire result.
- Live Godot `tests/narrator_live.tscn` performed a real wrong wire cut, observed one strike, received a Qwen 3B generated caption, and decoded Liam MP3. Recent event-to-audio round trips ranged from 2.7 to 5.3 seconds. The test disables playback so Godot can free MP3 resources cleanly at exit. Earlier visual checks showed camera preview, the two-module game and the event feed working.
- Live Godot `tests/preconfirm_live.tscn` spoke a named inspection fact, gave the model a pending cut with that memory, received a model-written pre-confirmation cue, then confirmed a real wrong cut and decoded result audio. This proves the data path, though model latency can still consume much of the ten-second confirmation window.
- Human novice playtesting, a complete physical hand-controlled round, verification of both hands on the teammate's camera, and speaker listening in the venue have not been completed; these need real participants and the demo environment. Model-written focus/result lines can still occasionally be awkward or need a labelled fallback. This remains a demo-quality local agent, not a reliability guarantee.

## Before the live demonstration

- Run the full checks after any edits and visually inspect the current scene once more.
- Print the revision 7 manual; do not hand out the older v2 ODT.
- Perform a complete physical-camera round and test speaker volume/latency in the venue.
- Ask two new players to follow the manual, record confusion points, adjust timer or module count if needed.
- Do not commit `narrator/.env`, local model weights, `.venv` or `.runtime` logs.

The repository history records the implementation checkpoints. Keep this file updated as the team completes physical playtesting.
