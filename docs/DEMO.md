# Judge demo: Bot Defusal

## Prepare

1. Print `PLAYER_MANUAL_print.html` from a browser at A4 size. This is revision 9. Do not hand out older guides with different controls.
2. From the repository root run `python3.12 launch.py --check` and `python3.12 tools/check_voice.py`. Ensure Godot, the camera environment, local Qwen inference, and the Liam MP3 check pass.
3. Run `python3.12 launch.py` and leave that terminal open. Complete the camera rehearsal on the welcome screen: both hands steady, right pointer movement, and the four listed left gestures. Use [the physical acceptance sheet](CAMERA_REHEARSAL.md) with at least two people. Put the printed guide beside the laptop. Record any gesture that fails and fix lighting or camera placement before judging.
4. Set room lighting so the right index finger and left gestures are visible. Use K to switch to mouse and keys if the venue camera setup fails.

## Two-minute presentation

- **0:00–0:20:** Explain the constraint: the remote robot has a degraded video feed, and the player can only give hand signals. Start a two-module round.
- **0:20–0:45:** Point at a wire and fist to lock it; move the pointer away to show that the yellow outline stays. Fist again on the same wire to ask whether it is blue. The game reports a fact and Liam says the target and answer. Show the fact in the agent's memory feed.
- **0:45–1:10:** Move to Link Recovery. Steady the right pointer on HOLD while showing an open left palm. Briefly break contact; the charge pauses. Break contact for over 0.35 seconds to show a safe reset and a spoken recovery cue. Complete a contact and hear Liam react.
- **1:10–1:35:** Queue a wire cut and briefly wait before Victory. Move the pointer off the locked wire and show that the queued target stays put. Show `pending_action`, the relevant remembered fact, and the agent's speak/quiet decision before the cut. Then confirm and show the actual result. If a puzzle is random, never claim a scripted correct answer.
- **1:35–2:00:** Show the live feed's observed event, decision reason, caption and response time. Explain that Qwen sees only observed facts and game outcomes; Liam voices the returned line. The game alone judges puzzle correctness.

A judge may ask whether the agent sees raw camera frames. The MediaPipe model reads frames locally. The language model receives structured hand state and game events, not raw video. Be explicit about this distinction.

## What to demonstrate, and what to measure

The feed should show an autonomous reaction to a target lock, queued action, restored link contact, hesitation, uncertainty, deadline or final-life event. Routine state updates should remain quiet. `MODEL` means Qwen chose and wrote a line; `GUARD` means a verified game fact was spoken; `FALLBACK` means the model failed. The feed shows observed event, relevant memory, speak/quiet decision, reason and round-trip time. If a player confirms before a pending cue returns, the client discards it; demonstrate that separately if time allows. A transcript alone does not prove that a cue arrived before its moment passed.

The two-module mode lasts three minutes; the four-module mode lasts eight. Each has three lives and one original Link Recovery challenge. The four other modules are based on established bomb puzzles; acknowledge that inspiration rather than claiming the format is wholly original.

If the narrator is unavailable, the game still gives local command feedback and the feed displays OFFLINE. If the LLM or voice service fails while the API is running, it returns an explicitly marked factual caption fallback. Do not present a fallback line as generated AI speech.
