# Practice Mode

A training script for Fightcade (FBNeo). It lets **P2 act as a dummy** that

- **replays your recordings** (you control P2 for a moment, then P2 repeats it while you play P1), or
- **performs a ready-made motion** (quarter circles, charges, holds, super jumps, 360s...), and it adds some **training tools** (infinite health and meter, damage counter, input history).

It follows the sides automatically: if you and your opponent swap places, the recording or motion swaps Left/Right for you.

---

## 1. Install (one time, 2 minutes)

1. Put `fightcade_practice_mode.lua` anywhere you like (for example next to FBNeo).
2. Start a game in Fightcade training mode.
3. In the emulator: **Game > Lua Scripting > New Lua Script Window**, click **Browse**, pick the file, and press **Run**.
4. The console prints `[PM] ...` lines. If you see `Lua Hotkeys: 1=rec 2=play 3=stop 4=menu`, it loaded.
5. **Map the 4 hotkeys:** **Input > Map Game Inputs**, double-click **Lua Hotkey 1** and press a key or button. Repeat for Lua Hotkey 2, 3 and 4.

| Lua Hotkey | What it does |
|---|---|
| **1** | Record / stop recording |
| **2** | Play |
| **3** | Stop |
| **4** | Open / close the menu |

Everything else is inside the menu.

---

## 2. Quick start

### Make P2 repeat something you record
1. Press **Hotkey 1**. Your controls now drive **P2** (P1 is frozen).
2. Do the move you want to practice against.
3. Press **Hotkey 1** again to stop. It is saved automatically.
4. Press **Hotkey 2**. P2 repeats it while you play P1. With **Loop** on, it keeps repeating.
5. Press **Hotkey 3** to stop.

### Make P2 do a ready-made motion
1. Press **Hotkey 4** to open the menu: **Recording Tools > Motions**.
2. Choose a motion with **Up/Down**. Use **Left/Right** to choose the button (if the motion needs one).
3. Press **LP** to start it. **Hotkey 2** repeats the same motion, **Hotkey 3** stops it.

### Menu controls
| Button | Does |
|---|---|
| Up / Down | Choose a row |
| Left / Right | Change the value |
| LP | Select / confirm |
| LK | Go back (closes the menu from the main page) |

Buttons you press in the menu never reach the game. A button you used to confirm or close the menu stays blocked until you let go of it, so it does not trigger an attack.

LP, MP, HP and LK, MK, HK are your six attack buttons in any game. Neo Geo: A = LP, B = LK, C = HP, D = HK.

---

## 3. The menu, row by row

**Main menu (PRACTICE MODE):** Training Tools, Recording Tools, Close menu.

### Recording Tools
| Row | What it does |
|---|---|
| **Slot** | Choose one of the 5 recording slots. Choosing a slot goes back to playing recordings (instead of a preset). |
| **Loop** | On: repeats again and again. Off: plays once. |
| **Mirror** | Swaps Left/Right of what you record. Use it if the recording comes out facing the wrong way for you. |
| **Guard while recording** | P1 holds back while you record, so it blocks P2's attacks instead of getting hit. |
| **Guard stance** | High (standing) or low (crouching) guard. |
| **Side** | AUTO (the script follows the real sides), or fixed **Left** / **Right**. |
| **Side HUD** | Shows a small line on screen: `SIDE  P1 LEFT  >  P2 forward = Left`. Handy to check the script reads the sides right. |
| **Reset Side** | Clears your Side Flip choice for this game and re-reads the sides (see Troubleshooting). |
| **Side Flip** | ON/OFF. Turns around the script's idea of left and right for this game. Saved per game. |
| **Playback delay** | Frames P2 waits before each playback (60 frames = 1 second). Left/Right = 1 frame. LP/MP/HP = +10/+20/+30. LK/MK/HK = -10/-20/-30. 0 and 300 wrap around. |
| **Random delay** | Each playback waits a random time between 0 and your delay. |
| **Random slot** | Each pass plays a random non-empty slot. |
| **Savestate reset** | On: recording stores a savestate, and every playback starts from it, so it is the same situation each time. Off: P2 repeats from wherever you are. |
| **Motions** | Opens the motion list. |

### Training Tools
Only available for games the script has a profile for (about 87 games). If a game has none, the console says so.

| Row | What it does |
|---|---|
| Infinite HP P1 / P2 | Health refills |
| Infinite Meter P1 / P2 | Super meter refills |
| Infinite Time | The round timer stops |
| Damage Counter | Shows damage dealt |
| Input History | Shows your recent inputs |
| Reset Damage | Clears the damage counter |

---

## 4. Motions (presets)

All presets follow the sides automatically. Pick the button with Left/Right.

| Category | Presets |
|---|---|
| **Holding** | Hold Down, Down-Back, Back, Up-Back, Up, Up-Forward. P2 keeps the direction held until you press Stop. |
| **Tapping** | Double Back (back dash), Double Forward, **Forward Run (66 + Hold)** |
| **Super Jumps** | Down-Up, Down-Up-Forward, Down-Up-Back |
| **Jumps** | **Hyper Jump (KOF)**. With Loop on, it restarts right after landing. |
| **Quarter / half circles** | QCF, QCB, DP, Reverse DP, HCF, HCB, QCD, Reverse QCD, Quarter Circle Up (and reverse), Half Circle Up-Forward, Up-Back, Back-Forward, Forward-Back |
| **Charge** | Back, Down, Forward, Up, Down-Back, Down-Forward |
| **Full circles** | 270, 360, Reverse 360, 720, 1080 |
| **Combined** | Double QCF, Double QCB, Double HCF, Double HCB, QCF-HCB, QCB-HCF, HCF-QCF, HCB-QCB |
| **Special** | Tiger Knee, Reverse Tiger Knee, Shokoken, Pretzel, Overkill, Negative Edge, KKZ (Triple Down) |
| **Rekka and Mash** | Rekka (QCF x3), Reverse Rekka (QCB x3), Mash |
| **Fixed sequence** | Raging Demon |

Tuning (near the top of the script, optional):
- `HYPER_JUMP_AIR_FRAMES` (default 56): how long a Hyper Jump lasts before it restarts on loop. Raise it if the next jump starts while P2 is still in the air, lower it if P2 waits on the ground.
- `CHARGE_FRAMES` (50): how long charge motions are held.
- `MASH_PRESSES` (8): how many presses "Mash" does.

---

## 5. Side detection (swapping places)

When **Side** is **AUTO**, the script knows who stands on which side:

- A recording **remembers the side it was made on.** If you are on the other side later, Left and Right are swapped for that playback.
- Motions use the real side, so "forward" always means toward you.
- With **Savestate reset** on, the saved position decides instead, so nothing is swapped.

Some games have no side information. Then the **Side** row is just **Left** / **Right**: set it to where P1 is (Left means P1 on the left).

The side is read once when a motion starts and kept until it ends. A long hold does not flip direction in the middle if the characters cross.

---

## 6. Files it creates

They are saved next to the script, one set per game. The files keep the older `record_play_` name so recordings made before the rename still load.

| File | What it is |
|---|---|
| `record_play_<game>.txt` | Your 5 recording slots |
| `record_play_<game>_settings.txt` | Your menu settings (Loop, Mirror, delay, slot, last motion, etc.) |
| `record_play_<game>_sideflip2.txt` | Your Side Flip choice for that game |

Delete a file to reset that part.

---

## 7. Troubleshooting

**A motion or run goes the wrong way (away from the opponent).**
1. Turn **Side HUD** on and check it says the right side.
2. Wrong side shown? Press **Side Flip** to turn it ON (or OFF) and try again. It is remembered for that game.
3. Still confused? Press **Reset Side**, then Side Flip if needed.
4. The game has no side detection: set the **Side** row to Left or Right yourself.

**A recording plays reversed after I swap places.**
Re-record it. Recordings made with a different Side Flip setting are corrected automatically. Older recordings (before v13) have no such note, so the script warns once and may not correct them.

**Reset Side** only removes the side marker of old recordings that carry no such note, so they play exactly as recorded without swapping.

**"No Lua Hotkeys in this emulator" / nothing happens when pressing hotkeys.**
Map the four Lua Hotkeys in **Input > Map Game Inputs**.

**Training Tools say "NO profile".**
That game has no health/meter profile. Recording and motions still work.

**Hyper Jump restarts too early or too late.**
Change `HYPER_JUMP_AIR_FRAMES` at the top of the script.

**Messages and errors.**
Everything is also printed in the Lua console with the prefix `[PM]`.

---

## 8. Good to know

- The Vampire Savior games (`vsav`, not `vsav2`) have their side flag read in reverse, so the script flips it for them automatically.
- Side detection for 3rd Strike reads positions from memory. For other games it uses each game's own facing flag.
- The script never writes to a game's memory unless a game profile exists for it and you turned a Training Tools option on.
