# Bot Defusal Field Guide Revision 10

You are operating a remote robot through a damaged video link. Colours and lettering are obscured. Point at a component and ask the robot to inspect it; use the facts it reports to apply this guide. The narrator knows your observations and progress, but does not receive the solution.

## Mission

Disarm a two-module round within three minutes or a four-module round within eight minutes. A third mistake ends the round. Mistakes do not accelerate the clock. Press R to begin a new random round. In each puzzle section, check rules from top to bottom and use the first one that applies.

## Controls

Use your **right index finger** to move the cursor. Small hand movements cover the whole board; you do not need to reach to the edge of the camera view. Hover over the wire, button, label or display you want. Hold a **left fist** for about 0.35 seconds to lock it. A **yellow outline** marks the locked target and stays there when your pointer moves. You may lower your right hand after locking. To change targets, point at a different one and fist again. Release your left hand between gestures.

A fist on the **same** locked target asks whether it is blue. The same blue query works if your right pointer is out of view after locking. A fist over empty space leaves the lock where it is. **A fist does not cut a wire or press a button.**

| Left hand | Keyboard equivalent | Command |
|---|---|---|
| Closed fist | 1 | Lock the pointed target; repeat on the same target to ask whether it is blue |
| Open palm | 2 | Read the target's text or number |
| Index finger pointing up | 3 | Ask whether the target is yellow |
| Thumb down | 4 | Ask whether the target is red |
| Thumb up | 5 | Ask whether the target is green |
| Victory / two fingers | 6 | Confirm the pending command |
| I-love-you sign | 7 | Queue a cut or button press |

With a target locked, inspection and press commands use that target even if the pointer moves or leaves view. Make an inspection or press gesture, then show **Victory** within ten seconds to confirm it. An **orange outline** marks the pending command. You can wait for the narrator's cue or confirm immediately. To press a button multiple times, show the I-love-you sign once for each press, releasing between signs, then confirm once. Each sign refreshes the ten-second window. Fisting on another target changes the lock and cancels the pending command. Without a lock, keep pointing at the same target until confirmation; moving away cancels it. If a gesture is not recognized, release your left hand and try again.

**Example — cut a wire:** point to wire 2 with your right index finger, hold a left fist until the yellow lock appears, release, show I-love-you, release, then show Victory. **Example — read a label:** lock the label, show an open palm, release, then show Victory. The robot reports the answer; the narrator may react to it but does not tell you the solution.

Press **K** to toggle mouse and keyboard controls, even while the camera is connected; switching modes clears the lock. In keyboard mode, move the mouse and use keys 1–7 for the left-hand gestures shown above. Press **P** to enlarge or restore the camera preview. With no camera connection, mouse and keyboard controls activate automatically.

The robot's response to a colour query is Yes or No. Read the serial number and indicator labels with an open palm. Count the visible battery blocks. A vowel means A, E, I, O or U. Wire and button positions in this guide start at 1.

## Link Recovery

Every round includes this robot-specific module. Its **HOLD** pad is a continuous control: keep the right pointer on the pad and show an open left palm for 1.5 seconds of tracked contact. **Do not fist-lock the pad**; the pointer must stay on it. A brief tracking flicker pauses progress; a loss lasting about 0.35 seconds resets only the current contact's charge. In keyboard mode, keep the mouse on the pad and hold **2**. No Victory confirmation is needed. The pad moves after each completed contact; restore three contacts to disarm the module. An interrupted contact does not cost a life. The narrator reacts to restored and interrupted contacts.

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
