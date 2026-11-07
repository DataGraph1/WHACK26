# Judge demo: Bot Defusal

## Prepare

1. Print `PLAYER_MANUAL_print.html` from a browser at A4 size. This is revision 7. Do not hand out the older v2 document.
2. From the repository root run `python3.12 launch.py --check`. Ensure Godot, the camera environment, the local Qwen model, and the ElevenLabs key show ready/configured.
3. Run `python3.12 launch.py` and leave that terminal open. Check live video and both hands on the welcome screen. Put the printed guide beside the laptop.
4. Set room lighting so the right index finger and left gestures are visible. Use K to switch to mouse and keys if the venue camera setup fails.

## Two-minute presentation

- **0:00–0:20:** Explain the constraint: the remote robot has a degraded video feed, and the player can only give hand signals. Start a two-module round.
- **0:20–0:45:** Hold the cursor over a target and show the observation entering the agent feed. Ask whether a wire is a specific colour; confirm the query. The bot reports a fact, and the narrator may decide whether a spoken intervention helps.
- **0:45–1:10:** Move to Link Recovery. Steady the right pointer on HOLD while showing an open left palm. Intentionally break contact once; the pending charge resets safely and the narrator receives an uncertainty event. Complete a contact.
- **1:10–1:35:** Select a wrong wire if you can identify one from the printed guide. Show the strike and the narrator's changed tone. If a puzzle is random, never claim a scripted correct answer.
- **1:35–2:00:** Show the live feed's observed event, decision reason, caption and response time. Explain that Qwen sees only observed facts and game outcomes; Liam voices the returned line. The game alone judges puzzle correctness.

A judge may ask whether the agent sees raw camera frames. The MediaPipe model reads frames locally. The language model receives structured hand state and game events, not raw video. Be explicit about this distinction.

## What to demonstrate, and what to measure

The feed should show an autonomous reaction to a focus, hesitation, uncertainty, deadline or final-life event. Routine state updates should remain quiet. `AGENT` means the model wrote commentary; `GUARD` means a critical line used verified state; `FALLBACK` means the model failed. Record time from each event to returned caption and audio. A transcript alone does not prove that a cue arrived before its moment passed.

The game has two/four-module modes, three minutes, three lives, and one original Link Recovery challenge. The four other modules are based on established bomb puzzles; acknowledge that inspiration rather than claiming the format is wholly original.

If the narrator is unavailable, the game still gives local command feedback and the feed displays OFFLINE. If the LLM or voice service fails while the API is running, it returns an explicitly marked factual caption fallback. Do not present a fallback line as generated AI speech.
