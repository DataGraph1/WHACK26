# Physical camera acceptance check

Run on the exact laptop, webcam, room lighting and speakers planned for judging. This is a human test; the automated checks cannot certify it.

1. Pull `main`, run `python3.12 launch.py`, and leave keyboard mode off. On the welcome screen, complete every **CAMERA REHEARSAL** check: both hands continuously seen for two seconds, right pointer moved, and Open Palm, Victory, I-love-you and Closed Fist recognized from the left hand.
2. Start a two-module round. Use the right hand to point at a wire. Use the left Closed Fist to ask whether it is blue, release, then Victory to confirm. Hear the named answer and see it in the memory feed.
3. Queue a cut with left I-love-you. Keep pointing; wait briefly for the model's speak/quiet decision. Confirm with left Victory. Verify the game result and the narrator's response. Complete a Link Recovery contact with right pointer plus left Open Palm.
4. Repeat the check with a second person. Record each miss in the table. Do not count keyboard fallback as a camera pass.

| Trial / player | Both hands stable | Pointer moved | Four gestures | Inspection spoken | Pending decision | Confirmed action | Miss or delay |
|---|---|---|---|---|---|---|---|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |

For a confident public demo, aim for at least four clean trials out of five per player and **zero unintended cuts**. If `Hands: 2` appears but one role says missing, try `WHACK_SWAP_HANDS=1 python3.12 launch.py`. If `Hands: 1`, separate hands and improve light or camera framing. If `Left: seen / None`, the hand is detected but its pose is not a recognized command; hold it steady for 0.35 seconds. If sound fails, check the narrator API and ElevenLabs key before judging.
