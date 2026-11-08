# Bot Defusal — field guide, revision 9

You are operating a remote robot through a damaged video link. Colours and lettering are obscured. Point at a component and ask the robot to inspect it; use the facts it reports to apply this guide. The narrator knows your observations and progress, but does not receive the solution.

## Mission

Disarm a two-module round within three minutes or a four-module round within eight minutes. A third mistake ends the round. Mistakes do not accelerate the clock. Press R to begin a new random round. All rules below are checked from top to bottom: use the first matching rule.

## Controls

Right index finger: move the cursor. The central part of the camera view now reaches the whole board, so small hand movements move the pointer further. Point at a target and hold a left fist for at least 0.35 seconds to **lock** it; a yellow outline remains when the pointer moves. You can lower your right hand after locking. Point at another target and fist again to change the lock. A fist on the already locked target (or with the pointer out of view) asks whether it is blue. Release between repeated gestures.

| Left hand | Keyboard equivalent | Command |
|---|---|---|
| Closed fist | 1 | Lock the pointed target; repeat on the same target to ask whether it is blue |
| Open palm | 2 | Read the target's text or number |
| Index finger pointing up | 3 | Ask whether the target is yellow |
| Thumb down | 4 | Ask whether the target is red |
| Thumb up | 5 | Ask whether the target is green |
| Victory / two fingers | 6 | Confirm the pending command |
| I-love-you sign | 7 | Queue a cut or button press |

With a target locked, inspection and press commands use that target even if the pointer moves or leaves view. Victory confirms the pending command within ten seconds; the orange outline shows what is pending. The narrator may comment while a press is queued; you may wait for the cue or confirm immediately. For multiple presses, repeat the press gesture the required number of times before confirming once. Each press refreshes the confirmation window. Fisting on a different target changes the lock and cancels any pending command. Without a lock, keep pointing at the same target until confirmation; moving away or losing the right pointer cancels the command. An uncertain left-hand gesture is ignored while you release your hand between commands. Press K to toggle mouse and keyboard controls even while the camera is connected; switching modes clears the lock. Press P to enlarge or restore the camera preview. With no camera connection, mouse and keyboard provide the same controls automatically.

The robot's response to a colour query is Yes or No. Read the serial number and indicator labels with an open palm. Count the visible battery blocks. A vowel means A, E, I, O or U. Wire and button positions in this guide start at 1.

## Link Recovery

Every round includes this robot-specific module. Its HOLD pad is a continuous control: keep the right pointer inside it and show an open left palm for 1.5 seconds of tracked contact. The fist lock does not hold this pad for you. A short tracking flicker pauses charge; a loss lasting about 0.35 seconds resets only the current contact's charge. The pointer has a small edge tolerance around the pad. With keyboard controls, keep the mouse on the pad and hold 2. No confirmation gesture is needed here. The pad moves after each completed contact; restore three contacts to disarm the module. An interrupted contact does not cost a life. The agent observes restored and interrupted contacts.

The start screen offers two or four modules. The two-module demo always has Link Recovery and Wires. The four-module round includes Link Recovery and three randomly selected modules from the four types below.

## Wires

Inspect the wires to determine their colours. Cut one correct wire. Wires run from top to bottom.

For **three wires**:
1. No red wires: cut wire 2.
2. Last wire yellow: cut wire 3.
3. More than one green wire: cut the last green wire.
4. Otherwise: cut wire 1.

For **four wires**:
1. Last wire green and no red wires: cut wire 1.
2. No yellow wires: cut wire 1.
3. More than one red wire: cut wire 4.
4. At least one green and at least one blue: cut wire 2.
5. No green wires and the serial contains a vowel: cut wire 3.
6. Otherwise: cut the first yellow wire.

## The button

Inspect its colour and read its word. Count batteries and inspect indicator labels as needed. Queue the following number of presses and confirm once:
1. Blue and labelled Abort: 2.
2. More than one battery and labelled Detonate: 3.
3. Red, exactly three batteries and an FKL indicator: 8.
4. Yellow, more than two batteries and an FRK indicator: 1.
5. Red and exactly one battery: 1.
6. Red: 3.
7. Otherwise: 4.

## Simon

The four positions are red (upper left), yellow (upper right), green (lower left), blue (lower right). The damaged image makes each flash white; use its position to identify the original colour. Wait for the flashing sequence to finish, then enter its mapped colours in order. Each press needs confirmation. Complete five stages, from one flash to five flashes. A mistake generates a new sequence starting at stage one. After five seconds without a press, the sequence replays and your input position resets.

| Serial has a vowel; strikes | Red flash | Yellow flash | Green flash | Blue flash |
|---|---|---|---|---|
| 0 | Blue | Blue | Red | Green |
| 1 | Yellow | Red | Yellow | Red |
| 2 | Green | Green | Blue | Yellow |

| Serial has no vowel; strikes | Red flash | Yellow flash | Green flash | Blue flash |
|---|---|---|---|---|
| 0 | Yellow | Blue | Blue | Green |
| 1 | Green | Red | Red | Yellow |
| 2 | Blue | Green | Yellow | Red |

## Memory

Read the display and the numbers printed on the four buttons. Positions run left to right. Record both the position and printed number of every successful press. Complete five stages. A mistake resets this module to stage one and clears its history.

| Stage | Display 1 | Display 2 | Display 3 | Display 4 |
|---|---|---|---|---|
| 1 | Position 2 | Position 2 | Position 3 | Position 4 |
| 2 | Button labelled 4 | Same position as stage 1 | Position 1 | Same position as stage 1 |
| 3 | Same label as stage 2 | Same label as stage 1 | Position 3 | Button labelled 4 |
| 4 | Same position as stage 1 | Position 1 | Same position as stage 2 | Same position as stage 2 |
| 5 | Same label as stage 1 | Same label as stage 2 | Same label as stage 4 | Same label as stage 3 |

## Inspiration

The bomb-module format and Memory puzzle are inspired by Keep Talking and Nobody Explodes. This project's contribution is remote gesture control and a live observing narrator. This guide replaces earlier v2/v6 drafts; do not mix editions.
