-- PRACTICE MODE for Fightcade (FBNeo Lua)  -  record, playback, motion presets and training tools
-- Record: your P1 controls drive P2. Play: P2 repeats it while you play P1.
--
-- Hotkeys: the emulator's own Lua Hotkeys (no keyboard keys or button chords are used any more).
--   Lua Hotkey 1  record / stop recording
--   Lua Hotkey 2  play
--   Lua Hotkey 3  stop
--   Lua Hotkey 4  open / close the MENU (everything else is in there)
-- Map them once in the emulator: Input > Map Game Inputs > double-click "Lua Hotkey 1" and press a
-- key or button (then 2, 3 and 4). Which number does what is set in LUA_HOTKEYS below.
-- Menu: Up/Down choose, LP select; LK goes back (and closes at the main menu).
-- Playback delay row (works like a slider): Left/Right = -1/+1 frame (hold to keep going, 0 wraps
-- to 300 and 300 wraps to 0); LP/MP/HP = +10/+20/+30; LK/MK/HK = -10/-20/-30.
-- LP/MP/HP and LK/MK/HK are your six attack buttons in any game (Neo Geo: A = LP, B = LK, C = HP, D = HK).
-- Messages are also logged to the Lua console with the prefix [PM].

---------------------------------------------------------------- settings
local NUM_SLOTS = 5               -- how many recordings you can keep
local AUTO_SAVE_TO_FILE = true    -- save slots to a file after each recording, load on start
local USE_SAVESTATE = false       -- start with savestate reset on/off (toggle it in the menu)
local STATE_SLOT_BASE = 5         -- recording slot 1 uses emulator state slot 5, slot 2 uses 6, ...
local BLOCK_P1_WHILE_RECORDING = true  -- freeze P1 while you control P2
local MIRROR_AT_RECORD_START = false   -- mirror forced when recording starts (false/true/nil)
-- While recording, P1 holds back so it guards P2's attacks.
local GUARD_ON_RECORD = true
local GUARD_DIRECTION = "Left"    -- P1's back direction: "Left" if P1 is on the left, "Right" if on the right

-- Automatic side detection. The script reads each player's X position from the game's memory to see
-- which side P1 is on. Then (menu row "Side" = AUTO):
--   * a recording remembers the side it was made on, and playback swaps Left/Right if you are on the
--     other side now (with "savestate reset" on, the saved position decides instead)
--   * the guard direction and the motions follow the real side by themselves
-- Built-in for Street Fighter III 3rd Strike (all sfiii3 versions). The addresses come from community
-- scripts and are NOT yet checked against your game: watch the "Side" row in the menu, it must say
-- the right side when you swap places. For another game, fill in SIDE_SETTINGS.addresses:
--   SIDE_SETTINGS.addresses = { p1 = 0x........, p2 = 0x........, size = 2, signed = true }
-- (p1 / p2 = the address of each player's X position, size = 1, 2 or 4 bytes).
local SIDE_SETTINGS = {
  -- Games whose own "facing" flag means the opposite of what the script expects. Their detected side is
  -- flipped (a rom name that starts with one of these, except the ones in flip_except).
  -- Vampire Savior: the presets (and the guard) ran in reverse while recordings played back fine.
  flip_prefixes = { "vsav" },
  flip_except = { "vsav2" },
  addresses = nil,            -- your own addresses (see above)
  reversed = false,           -- set true if the menu shows the wrong side (X grows to the left)
  games = {                   -- built in, by rom name (the start of the name is enough)
    sfiii3 = { p1 = 0x02068C6C + 0x64, p2 = 0x02069104 + 0x64, size = 2, signed = true },
  },
}
local GUARD_CROUCH = false        -- starting guard: false = standing (high), true = crouching (low)
local PRINT_BUTTONS = false       -- true = print pressed controller button names to the console

-- Playback delay: P2 waits this many frames (60 frames = 1 second) before each playback.
-- Change it in the menu: Left/Right = 1 frame, attack buttons = see DELAY_BUTTONS.
local DELAY_START = 0         -- delay when the script starts
local DELAY_MAX = 300         -- longest delay (300 frames = 5 seconds)
local DELAY_STEP = 10         -- only for the optional delay_up / delay_down hotkeys
-- On the delay row each press of one of these buttons adds (+) or removes (-) that many frames.
-- LP/MP/HP are the punches and LK/MK/HK the kicks. A 4-button game has no MP/MK
-- (Neo Geo: A = LP, B = LK, C = HP, D = HK). Left/Right always change it by 1 frame.
local DELAY_BUTTONS = { { "LP", 10 }, { "MP", 20 }, { "HP", 30 }, { "LK", -10 }, { "MK", -20 }, { "HK", -30 } }
-- When a preset move loops, P2 rests at least this many frames between repeats, so the end of
-- one try can't blend into the start of the next (the 6 of one QCF + the 2 3 of the next = DP).
local LOOP_MIN_GAP = 20
-- Holding Up/Down in the menu: frames before it starts repeating, then frames between repeats.
local REPEAT_FIRST, REPEAT_RATE = 18, 4
-- On the delay row Left/Right also repeat while held, and go one frame per frame after this long.
local REPEAT_FAST_AFTER = 60

-- Motions sub menu (Menu > Motions): common motions that P2 can perform on demand, using the
-- button you choose. A chosen motion stays loaded like a recording: Play repeats it.
-- Notation: numpad directions relative to P2 (6 = forward, 4 = back, 2 = down, 8 = up), so
-- 236 is a quarter-circle forward. The chosen button is added to the last direction.
-- "[4]6" = hold back to charge, then forward. "236~" = hold the button during the motion and
-- release it on the last direction (negative edge). "2." = this step has no button.
-- "w14" waits 14 frames and spaces separate steps ("236 w14 236"). "mash" presses the button
-- repeatedly. A motion with fixed = true ignores the chosen button: it uses the buttons written
-- in its input ("LP LP 6. LK HP" = LP, LP, forward, LK, HP).
-- Every motion can be done with a Punch (P) or a Kick (K); HP / HK are the heavy versions.
-- The script finds each game's button names by itself (Neo Geo "Button A-D", Street Fighter
-- style "Weak Punch" ... "Strong Kick" or "Button 1-6"). If a game is not detected correctly,
-- write the names here (see the [PM] lines in the console), for example:
--   BUTTON_MAP = { LP = "Weak Punch", MP = "Medium Punch", HP = "Strong Punch",
--                  LK = "Weak Kick",  MK = "Medium Kick",  HK = "Strong Kick" }
local BUTTON_MAP = {}
-- Names tried for each button, in order (without the "P1 " in front).
local BUTTON_NAMES = {
  LP = { "Weak Punch", "Button A", "Button 1" },
  MP = { "Medium Punch", "Button 2" },
  HP = { "Strong Punch", "Button C", "Button 3" },
  LK = { "Weak Kick", "Button B", "Button 4" },
  MK = { "Medium Kick", "Button 5" },
  HK = { "Strong Kick", "Button D", "Button 6" },
}
-- "2P" and "2K" press two buttons at once: the first pair this game has is used.
local TWO_PUNCH = { { "LP", "MP" }, { "LP", "HP" } }
local TWO_KICK = { { "LK", "MK" }, { "LK", "HK" } }
-- The buttons the Motions menu offers (Left/Right). Entries the game cannot press are skipped.
local BUTTON_OPTIONS = {
  { label = "LP", sets = { { "LP" } } }, { label = "MP", sets = { { "MP" } } },
  { label = "HP", sets = { { "HP" } } }, { label = "2P", sets = TWO_PUNCH },
  { label = "LK", sets = { { "LK" } } }, { label = "MK", sets = { { "MK" } } },
  { label = "HK", sets = { { "HK" } } }, { label = "2K", sets = TWO_KICK },
}
local DIR_FRAMES = 3      -- frames each direction of a motion is held
local BUTTON_FRAMES = 3   -- frames the button is held on the last direction
local STEP_GAP = 2        -- idle frames after each step
local CHARGE_FRAMES = 50  -- frames a charge direction is held
local REKKA_GAP = 14      -- frames between the parts of a rekka string
local MASH_PRESSES = 8    -- how many times "mash" presses the button
-- Hyper Jump (KOF): frames the jump lasts after the input. When the move loops, the next Hyper Jump starts
-- right after this time (= when the character lands), with no extra rest. If it restarts too early (still
-- in the air) raise it, if it waits on the ground lower it.
local HYPER_JUMP_AIR_FRAMES = 56

local MOTIONS = {
  { cat = "HOLDING", name = "Hold Down", shown = "DOWN", input = "[2]2.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "HOLDING", name = "Hold Down-Back", shown = "DOWN-BACK", input = "[1]1.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "HOLDING", name = "Hold Back", shown = "BACK", input = "[4]4.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "HOLDING", name = "Hold Up-Back", shown = "UP-BACK", input = "[7]7.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "HOLDING", name = "Hold Up", shown = "UP", input = "[8]8.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "HOLDING", name = "Hold Up-Forward", shown = "UP-FORWARD", input = "[9]9.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "TAPPING", name = "Double Back (Back Dash)", shown = "4 4", input = "4 4", fixed = true, side_aware = true },
  { cat = "TAPPING", name = "Double Forward", shown = "6 6", input = "6 6", fixed = true, side_aware = true },
  { cat = "TAPPING", name = "Forward Run (66 + Hold)", shown = "6 [6]6.", input = "6 [6]6.", fixed = true, hold_indefinitely = true, side_aware = true },
  { cat = "SUPER JUMPS", name = "Super Jump Down-Up", shown = "2 8", input = "2. 8.", fixed = true, side_aware = true },
  { cat = "SUPER JUMPS", name = "Super Jump Down-Up-Fwd", shown = "2 9", input = "2. 9.", fixed = true, side_aware = true },
  { cat = "SUPER JUMPS", name = "Super Jump Down-Up-Back", shown = "2 7", input = "2. 7.", fixed = true, side_aware = true },
  { cat = "JUMPS", name = "Hyper Jump (KOF)", shown = "2 9", input = "29.", fixed = true, final_direction_frames = 6, side_aware = true,
    air_frames = HYPER_JUMP_AIR_FRAMES, no_loop_gap = true },
  -- quarter and half circles
  { cat = "QUARTER AND HALF CIRCLES", name = "QCF", input = "236" },
  { cat = "QUARTER AND HALF CIRCLES", name = "QCB", input = "214" },
  { cat = "QUARTER AND HALF CIRCLES", name = "DP", input = "623" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Reverse DP", input = "421" },
  { cat = "QUARTER AND HALF CIRCLES", name = "HCF", input = "41236" },
  { cat = "QUARTER AND HALF CIRCLES", name = "HCB", input = "63214" },
  { cat = "QUARTER AND HALF CIRCLES", name = "QCD", input = "632" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Reverse QCD", input = "412" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Quarter Circle Up", input = "698" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Reverse Quarter Circle Up", input = "478" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Half Circle Up-Forward", input = "47896" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Half Circle Up-Back", input = "69874" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Half Circle Back-Forward", input = "632146" },
  { cat = "QUARTER AND HALF CIRCLES", name = "Half Circle Forward-Back", input = "412364" },
  -- charge motions
  { cat = "CHARGE", name = "Back Charge", input = "[4]6" },
  { cat = "CHARGE", name = "Down Charge", input = "[2]8" },
  { cat = "CHARGE", name = "Forward Charge", input = "[6]4" },
  { cat = "CHARGE", name = "Up Charge", input = "[8]2" },
  { cat = "CHARGE", name = "Down-Back Charge", input = "[1]6" },
  { cat = "CHARGE", name = "Down-Forward Charge", input = "[3]4" },
  -- full circles (Reverse 360 is the mirror image of 360, and 1080 is 720 plus one more rotation)
  { cat = "FULL CIRCLES", name = "270", input = "4123698" },
  { cat = "FULL CIRCLES", name = "360", input = "632147896" },
  { cat = "FULL CIRCLES", name = "Reverse 360", input = "412369874" },
  { cat = "FULL CIRCLES", name = "720", input = "63214789632147896" },
  { cat = "FULL CIRCLES", name = "1080", input = "6321478963214789632147896" },
  -- combined motions
  { cat = "COMBINED MOTIONS", name = "Double QCF", input = "236236" },
  { cat = "COMBINED MOTIONS", name = "Double QCB", input = "214214" },
  { cat = "COMBINED MOTIONS", name = "Double HCF", input = "4123641236" },
  { cat = "COMBINED MOTIONS", name = "Double HCB", input = "6321463214" },
  { cat = "COMBINED MOTIONS", name = "QCF-HCB", input = "2363214" },
  { cat = "COMBINED MOTIONS", name = "QCB-HCF", input = "2141236" },
  { cat = "COMBINED MOTIONS", name = "HCF-QCF", input = "41236236" },
  { cat = "COMBINED MOTIONS", name = "HCB-QCB", input = "63214214" },
  -- special
  { cat = "SPECIAL", name = "Tiger Knee", input = "2369" },
  { cat = "SPECIAL", name = "Reverse Tiger Knee", input = "2147" },
  { cat = "SPECIAL", name = "Shokoken", input = "641236" },
  { cat = "SPECIAL", name = "Pretzel", input = "1632143" },
  { cat = "SPECIAL", name = "Overkill", input = "1236982" },
  { cat = "SPECIAL", name = "Negative Edge", input = "236~" },
  { cat = "SPECIAL", name = "KKZ (Triple Down)", shown = "222", input = "2. 2. 2" },
  -- rekka and mash
  { cat = "REKKA AND MASH", name = "Rekka (QCF x3)", shown = "236 X3",
    input = "236 w" .. REKKA_GAP .. " 236 w" .. REKKA_GAP .. " 236" },
  { cat = "REKKA AND MASH", name = "Reverse Rekka (QCB x3)", shown = "214 X3",
    input = "214 w" .. REKKA_GAP .. " 214 w" .. REKKA_GAP .. " 214" },
  { cat = "REKKA AND MASH", name = "Mash", shown = "MASH", input = "mash" },
  -- fixed sequence: always LP, LP, forward, LK, HP (the button choice does not change it)
  { cat = "FIXED SEQUENCE", name = "Raging Demon", shown = "LP LP 6 LK HP", fixed = true,
    input = "LP LP 6. LK HP" },
}

-- On-screen text: a colored REC / PLAY line while recording or playing, plus the
-- settings and slot list.
local SHOW_TEXT = true            -- false = hide all on-screen text
local ALWAYS_SHOW_DETAILS = true  -- true = settings always visible; false = only for a few seconds after a change
local TEXT_X, TEXT_Y = 3, 3        -- top-left corner of the info text
local INFO_BIG_FONT = true          -- info text in the larger pixel font (false = small emulator text)
local TEXT_COLORS = true          -- colored text on a dark backdrop (set false if it looks wrong)
local MENU_BIG_FONT = true        -- draw the menu in large pixel letters (false = normal emulator text)
local MENU_X, MENU_Y = 12, 16     -- top-left corner of the menu
local INFO_SECONDS = 3            -- when ALWAYS_SHOW_DETAILS is false: how long the details stay after a change

-- The emulator's own "Lua Hotkey 1-9" (Input > Map Game Inputs). Each number triggers one action
-- when you press the key or button you mapped to it there. Actions: rec (record / stop recording),
-- play, stop, menu, and the optional extras: loop, mirror, guard, side, guard_toggle, random,
-- random_delay, delay_up, delay_down, state, slot_next, slot_prev.
-- Remove a number (or set it to nil) to leave that Lua Hotkey alone.
local LUA_HOTKEYS = {
  [1] = "rec", [2] = "play", [3] = "stop", [4] = "menu",
  -- [5] = "slot_next", [6] = "slot_prev", [7] = "loop", [8] = "mirror", [9] = "random",
}
-- Some systems repeat a held key. A Lua Hotkey that fires again within this many frames is treated
-- as the same press (no human presses the same key twice in 4 frames).
local HOTKEY_REPEAT_FRAMES = 4

-- "Lua Hotkey 3" for an action, used in on-screen messages
local function hotkey_of(action)
  for n = 1, 9 do
    if LUA_HOTKEYS[n] == action then return "Lua Hotkey " .. n end
  end
  return action
end

-- "Lua Hotkeys: 1 record  2 play  3 stop  4 menu" (follows LUA_HOTKEYS)
local function hotkey_hint()
  local parts = {}
  for _, a in ipairs({ "rec", "play", "stop", "menu" }) do
    for n = 1, 9 do
      if LUA_HOTKEYS[n] == a then parts[#parts + 1] = n .. " " .. (a == "rec" and "record" or a) end
    end
  end
  return "Lua Hotkeys: " .. table.concat(parts, "  ")
end

-- Menu controls: these use your normal game controls (so they work the same on a
-- keyboard and a fightstick). Select is your LP button (A on Neo Geo), Back is your LK button (B).
local MENU_NAV = { up = "P1 Up", down = "P1 Down", left = "P1 Left", right = "P1 Right",
                   select = "@LP", back = "@LK" }

-- System buttons that are never recorded or copied to P2
local IGNORE = { "Coin", "Start", "Select", "Service", "Test", "Reset",
                 "Diagnostic", "Dip", "Region", "Fake" }

---------------------------------------------------------------- state
local IDLE, REC, PLAY, MOVE = 0, 1, 2, 3
local mode = IDLE
local pos = 0
local loop, mirror = true, false
local guard_dir = GUARD_DIRECTION
local guard_low = GUARD_CROUCH
local guard_on = GUARD_ON_RECORD  -- current: does P1 guard while recording?
local use_state = USE_SAVESTATE
local delay_frames = math.max(0, math.min(DELAY_MAX, DELAY_START))   -- playback delay in frames
local delay_random = false      -- true = each playback waits a random 0 to delay_frames
local delay_prev = {}          -- delay row: which delay buttons were held last frame (one press = one step)
local lr_repeat = false         -- true while Left/Right should repeat when held (delay row)
local random_slot = false   -- true = each playback pass picks a random non-empty slot
local menu_open = false
local MENU_UI = { main_idx = 1, recording_idx = 1, carry = {} }
local SIDE = { auto = false, p1_left = nil, warned = false, hud_on = true, warned_slots = {}, settings_tick = nil }
local nav_count, nav_held = {}, {}   -- how long each menu button has been held, and if it is held now
local wait = 0              -- frames left before P2 starts the current pass
local play_slot = 1         -- slot currently being played
local menu_page = "main"    -- "main", "motions" or "training"
local motion_i, motion_btn, motion_top = 1, 1, 1   -- sub menu: selected motion, button option, first visible row
local MOTION_ROWS = 9       -- how many motions the sub menu shows at once
local move_frames, move_pos = {}, 0
local move_fwd = nil     -- P2 forward direction, locked on the first frame of a move
local preset = nil          -- chosen preset move { i = motion index, opt = button option }; Play repeats it
pcall(function() math.randomseed(os.time()) end)
local logged = 0
local last_print = ""
local pad_now = {}      -- joypad.get() for the current frame (always a table, never nil)
local known = {}        -- every P1 input name seen so far (without the "P1 ")
local announced = false
local pending = {}      -- joypad overrides collected this frame, applied once at the end
local hk_pending = {}   -- actions requested by an emulator Lua Hotkey, handled on the next frame
local hk_last = {}      -- frame each Lua Hotkey action last fired (to ignore key repeat)

local slots = {}
for i = 1, NUM_SLOTS do slots[i] = { frames = {}, has_state = false } end
local cur = 1

local function log(...) print("[PM]", ...) end

---------------------------------------------------------------- finding the game's buttons
-- Games name their buttons differently, so nothing here assumes a name: every P1 input the
-- emulator reports is remembered, and the six attack buttons are matched against that list.
local DIRECTIONS = { Up = true, Down = true, Left = true, Right = true }

local function learn_inputs()
  for name in pairs(pad_now) do
    local n = tostring(name):match("^P1 (.+)$")
    if n then known[n] = true end
  end
end

-- last resort for a game with unfamiliar names: sort its buttons and use them in order
local function sorted_buttons()
  local list = {}
  for n in pairs(known) do
    local skip = DIRECTIONS[n] or false
    for _, word in ipairs(IGNORE) do if n:find(word) then skip = true end end
    if not skip then list[#list + 1] = n end
  end
  table.sort(list, function(a, b)
    local a2, b2 = a:gsub("%d+", function(d) return string.format("%05d", tonumber(d)) end),
                   b:gsub("%d+", function(d) return string.format("%05d", tonumber(d)) end)
    return a2 < b2
  end)
  return list
end
local FALLBACK_SIX = { LP = 1, MP = 2, HP = 3, LK = 4, MK = 5, HK = 6 }
local FALLBACK_FOUR = { LP = 1, LK = 2, HP = 3, HK = 4 }

-- the game's name for LP, MP, HP, LK, MK or HK (without "P1 "), or nil if it has no such button
local function game_button(logical)
  if BUTTON_MAP[logical] then return BUTTON_MAP[logical] end
  for _, n in ipairs(BUTTON_NAMES[logical] or {}) do
    if known[n] then return n end
  end
  local list = sorted_buttons()
  if #list >= 6 then return list[FALLBACK_SIX[logical]] end
  if #list >= 4 then
    local i = FALLBACK_FOUR[logical]
    return i and list[i] or nil
  end
  return nil
end

-- "@LP" -> "P1 Weak Punch" (or whatever this game calls it); other names stay as they are;
-- nil when the game has no such button
local function resolve(token)
  local logical = token:match("^@(%u%u)$")
  if logical then
    local n = game_button(logical)
    return n and ("P1 " .. n) or nil
  end
  return token
end

-- the game buttons for a Motions menu option (one or two names), or nil if it can't be pressed
local function option_buttons(opt)
  for _, set in ipairs(opt.sets) do
    local names = {}
    for _, logical in ipairs(set) do
      local n = game_button(logical)
      if not n then names = nil break end
      names[#names + 1] = n
    end
    if names then return names end
  end
  return nil
end

local function available_options()
  local list = {}
  for _, opt in ipairs(BUTTON_OPTIONS) do
    if option_buttons(opt) then list[#list + 1] = opt end
  end
  return list
end

local frame_count = 0
local info_until = 10 * 60  -- show the details (with a hint) for the first 10 seconds
local hint_until = 10 * 60
local function flash() info_until = frame_count + INFO_SECONDS * 60 end

-- short message shown on screen (and in the console)
local notice, notice_until = "", 0
local function say(msg)
  log(msg)
  notice, notice_until = msg, frame_count + 4 * 60
end

---------------------------------------------------------------- file saving
local function rom_name()
  local ok, n = pcall(function() return emu.romname() end)
  if ok and type(n) == "string" and n ~= "" then return (n:gsub("[^%w_%-]", "_")) end
  return "game"
end

local SAVE_FILE = "record_play_" .. rom_name() .. ".txt"

---------------------------------------------------------------- universal training tools
-- Works in every game of the FBNeo Training Mode archive (87 games, see UT.games), not just 3rd Strike.
-- Everything it needs is INSIDE this file: the archive's per-game files (health, meter, facing, infinite time) are
-- embedded in UT.sources, so there is no folder to install or find. Anything a game does not support shows N/A in
-- the Training Tools menu, and the script never writes to memory for a game it has no profile for.
-- (all settings live in one table, "UT": Lua 5.1 allows only 200 local variables in a script)
local UT = {
  -- rom names that are not in the game list yet, e.g. { sfiii3n = "sfiii3" } (name -> a name that is)
  aliases = {},
  -- a game file's Run() (infinite time) is only used when it is this many lines or shorter
  run_max_lines = 12,
  -- game files bigger than this (bytes) are never re-run to refresh their max values
  max_reload_bytes = 40000,
  -- match-state words: reset the damage counter each round
  match_state = { sfiii = 0x02012C54, sfiii2 = 0x02014298, sfiii3 = 0x020154A6 },
  -- rom name -> game folder in the archive
  games = {
    aliencha = { roms = { "aliencha" } },
    aof = { roms = { "aof" } },
    aof2 = { roms = { "aof2" } },
    aof3 = { roms = { "aof3" } },
    asurabld = { roms = { "asurabld" } },
    asurabus = { roms = { "asurabus" } },
    avengrgs = { roms = { "avengrgs" } },
    breakrev = { roms = { "breakrev", "brkrevext" } },
    cyberbots = { roms = { "cybots", "cybotsam" } },
    dankuga = { roms = { "dankuga" } },
    daraku = { roms = { "daraku" } },
    dinorex = { roms = { "dinorex" } },
    dbz2 = { roms = { "dbz2" } },
    doubledr = { roms = { "doubledr" } },
    fatfury1 = { roms = { "fatfury1" } },
    fatfury2 = { roms = { "fatfury2" } },
    fatfury3 = { roms = { "fatfury3" } },
    fatfursp = { roms = { "fatfursp" } },
    galaxyfg = { roms = { "galaxyfg" } },
    garou = { roms = { "garou" } },
    gundamex = { roms = { "gundamex" } },
    gowcaizr = { roms = { "gowcaizr" } },
    hsf2 = { roms = { "hsf2" } },
    jchan2 = { roms = { "jchan2" } },
    jojos = { roms = { "jojoba", "jojoban", "jojobanr1" } },
    jojov = { roms = { "jojo", "jojon" } },
    kabukikl = { roms = { "kabukikl" } },
    karnovr = { roms = { "karnovr" } },
    kizuna = { roms = { "kizuna" } },
    kof94 = { roms = { "kof94" } },
    kof95 = { roms = { "kof95", "kof95sp" } },
    kof96 = { roms = { "kof96" } },
    kof97 = { roms = { "kof97" } },
    kof98 = { roms = { "kof98", "kof98cb" } },
    kof99 = { roms = { "kof99", "kof99ae" } },
    kof2000 = { roms = { "kof2000" } },
    kof2001 = { roms = { "kof2001" } },
    kof2002 = { roms = { "kof2002" } },
    kof2003 = { roms = { "kof2003" } },
    kf2k5uni = { roms = { "kf2k5uni" } },
    lastblad = { roms = { "lastblad" } },
    lb2 = { roms = { "lastbld2" } },
    matrim = { roms = { "matrim" } },
    martmast = { roms = { "martmast" } },
    msh = { roms = { "msh" } },
    mshvsf = { roms = { "mshvsf" } },
    mvc = { roms = { "mvc", "mvsc" } },
    mwarr = { roms = { "mwarr" } },
    ninjamas = { roms = { "ninjamas" } },
    rabbit = { roms = { "rabbit" } },
    ragnagrd = { roms = { "ragnagrd" } },
    rbff1 = { roms = { "rbff1" } },
    rbff2 = { roms = { "rbff2", "rbff2h" } },
    rbffspec = { roms = { "rbffspec" } },
    redearth = { roms = { "redearth" } },
    ringdest = { roms = { "ringdest" } },
    rotd = { roms = { "rotd" } },
    samsho = { roms = { "samsho" } },
    samsho2 = { roms = { "samsho2" } },
    samsho3 = { roms = { "samsho3" } },
    samsho4 = { roms = { "samsho4" } },
    samsho5 = { roms = { "samsho5" } },
    samsho5sp = { roms = { "samsh5sp" } },
    slammast = { roms = { "slammast" } },
    sf = { roms = { "sf" } },
    sf2 = { roms = { "sf2" } },
    sf2ce = { roms = { "sf2ce", "sf2hf", "sf2rb" } },
    sfa = { roms = { "sfa" } },
    sfa2 = { roms = { "sfa2", "sfa2u" } },
    sfa3 = { roms = { "sfa3" } },
    sfiii = { roms = { "sfiii" } },
    sfiii2 = { roms = { "sfiii2" } },
    sfiii3 = { roms = { "sfiii3", "sfiii3nr1" } },
    sgemf = { roms = { "sgemf" } },
    ssf2xjr1 = { roms = { "ssf2xjr1", "ssf2tnl" } },
    svc = { roms = { "svc", "svcsplus" } },
    tkdensho = { roms = { "tkdensho" } },
    umk3 = { roms = { "umk3" } },
    vamp = { roms = { "vamp", "vampjr1" } },
    vhunt2 = { roms = { "vhunt2" } },
    vhuntjr2 = { roms = { "nwarr", "vhuntjr2" } },
    vsav = { roms = { "vsav", "vsavj", "vsavae" } },
    vsav2 = { roms = { "vsav2" } },
    wakuwak7 = { roms = { "wakuwak7", "wakuwak7bh" } },
    whp = { roms = { "whp" } },
    xmvsf = { roms = { "xmvsf" } },
    xmcota = { roms = { "xmcota", "xmcotabh" } },
  },
}
-- Street Fighter II family: Fightcade / FBNeo has many more rom names than the archive lists (sf2ua, sf2ceua,
-- sf2hfu, ssf2t, ssf2u, hsf2j ...). A rom name that is not listed is matched by its beginning, first match wins.
UT.prefix_aliases = {
  { "hsf2", "hsf2" }, { "ssf2", "ssf2xjr1" },
  { "sf2ce", "sf2ce" }, { "sf2hf", "sf2ce" }, { "sf2rb", "sf2ce" }, { "sf2t", "sf2ce" }, { "sf2yyc", "sf2ce" },
  { "sf2", "sf2" },
}
-- Games where refilling health on the very frame of a hit cancels the hit reaction (the character stays idle):
-- health is refilled only once it has stopped dropping for refill_delay frames (the combo is over), and at once
-- if it falls under refill_floor of the maximum so nobody gets KO'd mid-combo.
UT.delayed_refill = { sf2 = true, sf2ce = true, hsf2 = true, ssf2xjr1 = true }
UT.refill_delay = 24
UT.refill_floor = 0.12
-- Games whose health / meter functions only work while the file's Run() is also being called every frame
-- (Ragnagard keeps a "round started" counter there). Run is then called while any Infinite option is on.
UT.needs_run = { ragnagrd = true }
-- Hyper Street Fighter II: the archive only refills health in certain move states that its own Run() tracks, so
-- health is simply set here (same addresses as the archive's hsf2 file); infinite time = its timer rule.
UT.overrides = {
  hsf2 = function(env)
    local A = { { 0xFF8366, 0xFF8368, 0xFF84F8 }, { 0xFF8766, 0xFF8768, 0xFF88F8 } }
    for p = 1, 2 do
      local who = p == 1 and "PlayerOne" or "PlayerTwo"
      env["write" .. who .. "Health"] = function(v) env.ww(A[p][1], v) env.ww(A[p][2], v) env.ww(A[p][3], v) end
    end
    env.Run = function()
      if env.rb(0xFF8BFC) < 0x98 then env.ww(0xFF8BFC, 0x9928) end
    end
  end,
}
-- Compact built-in profiles for the games whose archive files are too entangled with the original main script
-- to embed. Each gets the loading environment and returns a refresh function (called now and then).
UT.builtin = {
  -- 3rd Strike: HP, meter (max meter depends on the super art), facing, timer
  sfiii3 = function(env)
    local rb, wb = env.rb, env.wb
    env.p1maxhealth, env.p2maxhealth = 0xA0, 0xA0
    local function refresh() env.p1maxmeter, env.p2maxmeter = rb(0x20286AD), rb(0x20286E1) end
    refresh()
    env.readPlayerOneHealth = function() return rb(0x2068D0B) end
    env.writePlayerOneHealth = function(v) wb(0x2068D0B, v) end
    env.readPlayerTwoHealth = function() return rb(0x20691A3) end
    env.writePlayerTwoHealth = function(v) wb(0x20691A3, v) end
    env.readPlayerOneMeter = function() return rb(0x20695BE) end
    env.writePlayerOneMeter = function(v) wb(0x20695BE, v) end
    env.readPlayerTwoMeter = function() return rb(0x20695EB) end
    env.writePlayerTwoMeter = function(v) wb(0x20695EB, v) end
    env.playerOneFacingLeft = function() return rb(0x2068C76) == 0 end
    env.Run = function() wb(0x2011377, 0x63) end
    return refresh
  end,
  -- Street Fighter Alpha 3 (addresses from the archive's sfa3 file)
  sfa3 = function(env)
    local rb, rw, wb, ww = env.rb, env.rw, env.wb, env.ww
    env.p1maxhealth, env.p2maxhealth, env.p1maxmeter, env.p2maxmeter = 144, 144, 0x90, 0x90
    env.readPlayerOneHealth = function() return rw(0xFF8450) end
    env.writePlayerOneHealth = function(v) ww(0xFF8450, v) ww(0xFF8452, v) end
    env.readPlayerTwoHealth = function() return rw(0xFF8850) end
    env.writePlayerTwoHealth = function(v) ww(0xFF8850, v) ww(0xFF8852, v) end
    env.readPlayerOneMeter = function() return rb(0xFF851F) end
    env.writePlayerOneMeter = function(v) wb(0xFF851F, v) end
    env.readPlayerTwoMeter = function() return rb(0xFF891F) end
    env.writePlayerTwoMeter = function(v) wb(0xFF891F, v) end
    env.playerOneFacingLeft = function() return rb(0xFF840B) == 0 end
    env.playerTwoFacingLeft = function() return rb(0xFF880B) == 0 end
    env.Run = function() wb(0xFF8109, 99) end
    return function() end
  end,
  -- Super Street Fighter II Turbo (addresses from the archive's ssf2xjr1 memory_addresses file)
  ssf2xjr1 = function(env)
    local rb, rw, rws, wb, ww = env.rb, env.rw, env.rws, env.wb, env.ww
    local BASE = { 0xFF844E, 0xFF884E }
    local MATCH_STATE, ROUND_TIMER = 0xFF847F, 0xFF8DCE
    env.p1maxhealth, env.p2maxhealth, env.p1maxmeter, env.p2maxmeter = 144, 144, 0x30, 0x30
    local function in_match() return rw(MATCH_STATE) ~= 0 end
    for p = 1, 2 do
      local b, who = BASE[p], p == 1 and "PlayerOne" or "PlayerTwo"
      env["read" .. who .. "Health"] = function() return rw(b + 0x2A) end
      env["write" .. who .. "Health"] = function(v) ww(b + 0x2A, v) ww(b + 0x2C, v) ww(b + 0x1BC, v) end
      env["read" .. who .. "Meter"] = function()
        if in_match() then return rb(b + 0x2B4) end
        return 0x30
      end
      env["write" .. who .. "Meter"] = function(v) if in_match() then wb(b + 0x2B4, v) end end
    end
    -- P1 faces left when it stands to the right of P2
    env.playerOneFacingLeft = function() return rws(BASE[1] + 0x06) >= rws(BASE[2] + 0x06) end
    env.playerTwoFacingLeft = function() return rws(BASE[1] + 0x06) < rws(BASE[2] + 0x06) end
    env.Run = function() if rb(ROUND_TIMER) < 0x98 then ww(ROUND_TIMER, 0x9928) end end
    return function() end
  end,
}
-- The archive's own per-game files (minified: comments and indentation removed, nothing else changed).
UT.sources = {}
UT.sources["aliencha"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x80
p2maxhealth = 0x80
local p1health = 0x200fc5
local p2health = 0x2010a7
local p1direction = 0x200f7a
local p2direction = 0x20105C
function gamemsg()
print "Known issues with aliencha:"
print "No hitstun detector"
print "Health display doesn't update"
print "Note that aliencha has no meter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Button 5"] = 9,
["Button 6"] = 10,
["Coin"] = 11,
["Start"] = 12,
["Select"] = 13,
}
gamedefaultconfig = {
hud = {
p1healthx=50,
p1healthy=21,
p1healthenabled=true,
p2healthx=387,
p2healthy=21,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p2direction)==1
end
function _playerOneInHitstun()
end
function _playerTwoInHitstun()
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
ww(0x200f31, 0x6200)
end
function Run()
infiniteTime()
end
]==]
UT.sources["aof"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x80
p2maxhealth = 0x80
p1maxmeter = 0x8000
p2maxmeter = 0x8000
local p1health = 0x1092cd
local p2health = 0x1093cd
local p1meter = 0x1094a4
local p2meter = 0x1095a4
function gamemsg()
print "Known issues with aof:"
print "Hitstun detector can be inconsistent"
print "No sideswap on replays"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=35,
comboenabled=true,
p1healthx=10,
p1healthy=16,
p1healthenabled=true,
p2healthx=282,
p2healthy=16,
p2healthenabled=true,
p1meterx=10,
p1metery=25,
p1meterenabled=true,
p2meterx=275,
p2metery=25,
p2meterenabled=true,
},
}
function _playerOneFacingLeft()
end
function _playerTwoFacingLeft()
end
function playerOneInHitstun()
return rb(0x1093C0)==0x02 or rb(0x1093C0)==0x04
end
function playerTwoInHitstun()
return rb(0x1093C0)==0x40
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
function infiniteTime()
ww(0x108406, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["aof2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x80
p2maxhealth = 0x80
p1maxmeter = 0x8000
p2maxmeter = 0x8000
local p1health = 0x1092ed
local p2health = 0x1093ed
local p1meter = 0x1094a4
local p2meter = 0x1095a4
local p1direction = 0x1080bd
local p2direction = 0x10847d
function gamemsg()
print "Known issues with aof2:"
print "Hitstun detector can be inconsistent"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=35,
comboenabled=true,
p1healthx=10,
p1healthy=16,
p1healthenabled=true,
p2healthx=282,
p2healthy=16,
p2healthenabled=true,
p1meterx=10,
p1metery=25,
p1meterenabled=true,
p2meterx=275,
p2metery=25,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function _playerOneInHitstun()
end
function playerTwoInHitstun()
return rb(0x1093C0)==0x06 or rb(0x1093C0)==0x07
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
function infiniteTime()
ww(0x108406, 0x5000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["aof3"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x1000
p2maxhealth = 0x1000
p1maxmeter = 0x1000
p2maxmeter = 0x1000
local p1health = 0x100468
local p2health = 0x100568
local p1meter = 0x10046A
local p2meter = 0x10056A
local p1direction = 0x10048c
local p2direction = 0x10058c
function gamemsg()
print "Known issues with aof3:"
print "Hitstun detector can update a few frames after actually losing health for inconsistent combos"
print "No hitboxes"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=40,
comboenabled=true,
p1healthx=10,
p1healthy=16,
p1healthenabled=true,
p2healthx=282,
p2healthy=16,
p2healthenabled=true,
p1meterx=10,
p1metery=25,
p1meterenabled=true,
p2meterx=282,
p2metery=25,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return false
end
function playerTwoInHitstun()
return rb(0x1005c3)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
function infiniteTime()
wb(0x10DF0F, 0x63)
end
function Run()
infiniteTime()
end
]==]
UT.sources["asurabld"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xEF
p2maxhealth = 0xEF
p1maxmeter = 0x51
p2maxmeter = 0x36
local p1health1 = 0x403911
local p1health2 = 0x40390F
local p2health1 = 0x4046C3
local p2health2 = 0x4046C5
local p1combocounter = 0x4041E7
local p2combocounter = 0x40470B
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Coin"] = 8,
["Start"] = 9,
}
gamedefaultconfig = {
hud = {
combotextx=140,
combotexty=42,
comboenabled=true,
p1healthx=24,
p1healthy=16,
p1healthenabled=true,
p2healthx=285,
p2healthy=16,
p2healthenabled=true,
p1meterx=112,
p1metery=226,
p1meterenabled=true,
p2meterx=202,
p2metery=226,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x4037F9) == 0
end
function playerTwoFacingLeft()
return rb(0x4045AD) == 0
end
function playerOneInHitstun()
return rb(p2combocounter) ~= 0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health1)
end
function writePlayerOneHealth(health)
wb(p1health1, health)
wb(p1health2, health)
end
function readPlayerTwoHealth()
return rb(p2health1)
end
function writePlayerTwoHealth(health)
wb(p2health1, health)
wb(p2health2, health)
end
function readPlayerOneMeter()
return rb(0x403913)
end
function writePlayerOneMeter(meter)
wb(0x403913, meter)
end
function readPlayerTwoMeter()
return rb(0x4046C7)
end
function writePlayerTwoMeter(meter)
wb(0x4046C7, meter)
end
function infiniteTime()
wb(0x40000A,0x99)
end
function maxCredits()
wb(0x40655D, 0x09)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["asurabus"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xEF
p2maxhealth = 0xEF
p1maxmeter = 0x40
p2maxmeter = 0x40
local p1direction = 0x4033DB
local p2direction = 0x404091
local p1combocounter = 0x403DBD
local p2combocounter = 0x404A7D
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Coin"] = 8,
["Start"] = 9,
}
gamedefaultconfig = {
hud = {
combotextx=146,
combotexty=42,
comboenabled=true,
p1healthx=22,
p1healthy=16,
p1healthenabled=true,
p2healthx=288,
p2healthy=16,
p2healthenabled=true,
p1meterx=22,
p1metery=223,
p1meterenabled=true,
p2meterx=288,
p2metery=223,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(0x4034EB)
end
function writePlayerOneHealth(health)
wb(0x4034EB, health)
end
function readPlayerTwoHealth()
return rb(0x4041A5)
end
function writePlayerTwoHealth(health)
wb(0x4041A5, health)
end
function readPlayerOneMeter()
return rb(0x4034EF)
end
function writePlayerOneMeter(meter)
wb(0x4034EF, meter)
wb(0x4034F3, meter)
end
function readPlayerTwoMeter()
return rb(0x4041A9)
end
function writePlayerTwoMeter(meter)
wb(0x4041AD, meter)
wb(0x4041A9, meter)
end
function infiniteTime()
wb(0x40000A, 0x99)
end
function secretCharacters()
wb(0x408837, 0x01)
wb(0x408839, 0x01)
end
function Run()
infiniteTime()
secretCharacters()
end
]==]
UT.sources["avengrgs"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xFF
p2maxhealth = 0xFF
p1maxmeter = 0x02
p2maxmeter = 0x02
local p1health = 0x00108DCD
local p2health = 0x00108F7D
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
p1healthx=28,
p1healthy=11,
p1healthenabled=true,
p2healthx=283,
p2healthy=11,
p2healthenabled=true,
p1meterx=44,
p1metery=18,
p1meterenabled=true,
p2meterx=290,
p2metery=18,
p2meterenabled=true,
},
}
function playerOneFacingleft()
return rb(0x00108D38) == 0x0A
end
function playerTwoFacingLeft()
return rb(0x00108ee8) == 0x0A
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth(health)
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(0x00108DD0)
end
function writePlayerOneMeter(meter)
wb(0x00108DD0, meter)
end
function readPlayerTwoMeter()
return rb(0x00108F80)
end
function writePlayerTwoMeter(meter)
wb(0x00108F80, meter)
end
function infiniteTime()
wb(0x001084C9,0x63)
end
function maxCredits()
wb(0x001088A1, 0x09)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["breakrev"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x1E00
p2maxhealth = 0x1E00
p1maxmeter = 0x3
p2maxmeter = 0x3
function gamemsg()
print "In breakrev, changes to the hitboxes will only take effect if they're set at character select"
end
local p1health = 0x10734E
local p2health = 0x1078AE
local p1meter = 0x107361
local p2meter = 0x1078C1
local p1direction = 0x107364
local p2direction = 0x107365
local p1combocounter = 0x107943
local p2combocounter = 0x1073E3
local debugaddress = 0x10007D
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=140,
combotexty=42,
comboenabled=true,
p1healthx=16,
p1healthy=18,
p1healthenabled=true,
p2healthx=288,
p2healthy=18,
p2healthenabled=true,
p1meterx=40,
p1metery=202,
p1meterenabled=true,
p2meterx=278,
p2metery=202,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0xFF
end
function playerTwoFacingLeft()
return rb(p2direction)==0xFF
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x107C27, 0x63)
end
function Run()
infiniteTime()
if (hitboxes.enabled) then wb(debugaddress, 0xC) else wb(debugaddress, 0) end
end
]==]
UT.sources["cyberbots"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 152
p2maxhealth = 152
p1maxmeter = 63
p2maxmeter = 63
function gamemsg()
print "Known issues with cybots:"
print "Inconsistent combo counter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Low Attack"] = 5,
["High Attack"] = 6,
["Boost"] = 7,
["Weapon"] = 8,
["Coin"] = 9,
["Start"] = 10,
}
gamedefaultconfig = {
hud = {
combotextx=176,
combotexty=49,
comboenabled=true,
p1healthx=33,
p1healthy=27,
p1healthenabled=true,
p2healthx=340,
p2healthy=27,
p2healthenabled=true,
p1meterx=66,
p1metery=215,
p1meterenabled=true,
p2meterx=311,
p2metery=215,
p2meterenabled=true,
},
}
local p2InHitstun = 0xffe9f7
local p2HealthAddr = 0xFF85E5
local timer = 0xFFEBA0
local p2Health = rb(p2HealthAddr)
local previousP2Health = p2Health
function playerOneFacingLeft()
return rb(0xFF85A9)==1
end
function playerTwoFacingLeft()
return rb(0xFF85A9)==0
end
function _playerOneInHitstun()
end
function playerTwoInHitstun()
return rb(p2InHitstun) ~= 0
end
function readPlayerOneHealth()
return rb(0xFF81E5)
end
function writePlayerOneHealth(health)
return wb(0xFF81E5,health)
end
function readPlayerTwoHealth()
previousP2Health = p2Health
p2Health = rb(p2HealthAddr)
return previousP2Health
end
function writePlayerTwoHealth(health)
wb(p2HealthAddr, health)
end
function readPlayerOneMeter()
return rb(0xFF8534)
end
function writePlayerOneMeter(meter)
wb(0xFF8534, meter)
end
function readPlayerTwoMeter()
return rb(0xFF8934)
end
function writePlayerTwoMeter(meter)
wb(0xFF8934, meter)
end
function infiniteTime()
wb(timer,0x9999)
end
function Run()
infiniteTime()
wb(0xff470c, 48)
wb(0xff870c, 48)
end
]==]
UT.sources["dankuga"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with dankuga:"
print "Combos are inconsistent"
end
p1maxhealth = 0x64
p2maxhealth = 0x64
p1maxmeter = 0xc8
p2maxmeter = 0xc8
local p1health = 0x412B35
local p2health = 0x412D35
local p1meter = 0x412BC1
local p2meter = 0x412DC1
local p1combocounter = 0x40cb1f
local p2combocounter = 0x40C91F
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=147,
combotexty=42,
comboenabled=true,
p1healthx=35,
p1healthy=18,
p1healthenabled=true,
p2healthx=274,
p2healthy=18,
p2healthenabled=true,
p1meterx=29,
p1metery=47,
p1meterenabled=true,
p2meterx=278,
p2metery=47,
p2meterenabled=true,
},
}
function Hitboxes()
wb(0x412B4A,0x3B)
wb(0x412B4B,0xE4)
end
function playerOneFacingLeft()
return rb(0x412AE0) == 2
end
function playerTwoFacingLeft()
return rb(0x412CE0) == 2
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function playerOneInHitstun()
return rb(p2combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x409737,0x09)
wb(0x409733,0x09)
end
function maxCredits()
wb(0x40E175, 0x09)
end
function Run()
infiniteTime()
maxCredits()
Hitboxes()
end
]==]
UT.sources["daraku"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x61
p2maxhealth = 0x61
p1maxmeter = 0x2C
p2maxmeter = 0x2C
local p1health = 0x602DF1B
local p2health = 0x602E11B
local p1meter = 0x602DF21
local p2meter = 0x602E121
local p1direction = 0x602de52
local p2direction = 0x602e052
local p1combocounter = 0x602E154
local p2combocounter = 0x602DF54
local p1character = 0x602DE81
local p2character = 0x602E081
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
}
gamedefaultconfig = {
hud = {
combotextx=145,
combotexty=42,
comboenabled=true,
p1healthx=41,
p1healthy=17,
p1healthenabled=true,
p2healthx=272,
p2healthy=17,
p2healthenabled=true,
p1meterx=98,
p1metery=29,
p1meterenabled=true,
p2meterx=215,
p2metery=29,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==8
end
function playerTwoFacingLeft()
return rb(p2direction)==8
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
if (meter==p1maxmeter) then
wb(p1meter+1, 1)
end
end
function readPlayerTwoMeter()
return rb(p1meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
if (meter==p2maxmeter) then
wb(p2meter+1, 1)
end
end
function infiniteTime()
ww(rdw(0x60004b4)-0x52A, 0x1530)
end
function Run()
infiniteTime()
end
]==]
UT.sources["dbz2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x78
p2maxhealth = 0x78
p1maxmeter = 0x40
p2maxmeter = 0x40
local p1health = 0x4862a9
local p2health = 0x4864a9
local p1prevhealth = rb(p1health)
local p2prevhealth = rb(p2health)
local p1meter = 0x48633b
local p2meter = 0x48653b
local p1combocounter = 0x486577
local p2combocounter = 0x486377
local p1direction = 0x484203
local p2direction = 0x484219
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
}
gamedefaultconfig = {
hud = {
combotextx=178,
combotexty=54,
comboenabled=true,
p1healthx=49,
p1healthy=36,
p1healthenabled=true,
p2healthx=324,
p2healthy=36,
p2healthenabled=true,
p1meterx=33,
p1metery=225,
p1meterenabled=true,
p2meterx=344,
p2metery=225,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p2direction)==1
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
local ret = p1prevhealth
p1prevhealth = rb(p1health)
return ret
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
local ret = p2prevhealth
p2prevhealth = rb(p2health)
return ret
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x48752d, 0x63)
end
function Run()
infiniteTime()
end
]==]
UT.sources["dinorex"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 104
p2maxhealth = 104
p1maxmeter = 0x60
p2maxmeter = 0x60
function gamemsg()
print "Known issues with dinorex:"
print "Infinite meter breaks the game"
print "No combo counter"
print "Game is VERY prone to throwing errors"
end
local p1health = 0x605124
local p2health = 0x605190
local p1meter = 0x605123
local p2meter = 0x60518f
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"coin",
"start",
["Left"] = 3,
["Right"] = 4,
["Up"] = 5,
["Down"] = 6,
["Fire 1"] = 7,
["Fire 2"] = 8,
["Fire 3"] = 8,
["Coin"] = 9,
["Start"] = 10,
}
gamedefaultconfig = {
combogui = {
combotextx=180,
combotexty=42,
},
}
function _playerOneFacingLeft()
end
function _playerTwoFacingLeft()
end
function _playerOneInHitstun()
end
function _playerTwoInHitstun()
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
return wb(p1health,health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x60826F,0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["doubledr"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x6800
p2maxhealth = 0x6800
p1maxmeter = 0x6800 - rw(0x100450)
p2maxmeter = 0x6800 - rw(0x100550)
local p1health = 0x100450
local p2health = 0x100550
local p1meter = 0x100510
local p2meter = 0x100610
local p1combocounter = 0x10061f
local p2combocounter = 0x10051f
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=142,
combotexty=50,
comboenabled=true,
p1healthx=43,
p1healthy=24,
p1healthenabled=true,
p2healthx=258,
p2healthy=24,
p2healthenabled=true,
p1meterx=120,
p1metery=35,
p1meterenabled=true,
p2meterx=193,
p2metery=35,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x10042B)==0x00 or rb(0x10042B)==0x04 or rb(0x10042B)==0x81 or rb(0x10042B)==0x89
end
function playerTwoFacingLeft()
return rb(0x10052B)==0x00 or rb(0x10052B)==0x04 or rb(0x10052B)==0x81 or rb(0x10052B)==0x89
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return p1maxhealth-rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, p1maxhealth-health)
end
function readPlayerTwoHealth()
return p2maxhealth-rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, p1maxhealth-health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
function infiniteTime()
wb(0x102242, 0x9a)
end
function Run()
infiniteTime()
wb(0x108E84,1)
end
]==]
UT.sources["fatfursp"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x60
p2maxhealth = 0x60
local p1health = 0x10049a
local p2health = 0x10059a
local p1direction = 0x100469
local p2direction = 0x100569
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=35,
comboenabled=true,
p1healthx=49,
p1healthy=17,
p1healthenabled=true,
p2healthx=264,
p2healthy=17,
p2healthenabled=true,
p1meterx=22,
p1metery=223,
p1meterenabled=true,
p2meterx=288,
p2metery=223,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x1004a4)~=0
end
function playerTwoInHitstun()
return rb(0x1005a4)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
ww(0x10092a, 0x6030)
end
function Run()
infiniteTime()
end
]==]
UT.sources["fatfury1"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x60
p2maxhealth = 0x60
local p1health = 0x1003B8
local p1redhealth = 0x1003B9
local p2health = 0x100589
local p2redhealth = 0x100589
local p1direction = 0x100445
local p2direction = 0x100345
function gamemsg()
print "Note that fatfury1 has no meter"
print "Known issue:"
print "Hitstun not set up"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=42,
comboenabled=true,
p1healthx=25,
p1healthy=21,
p1healthenabled=true,
p2healthx=284,
p2healthy=21,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p2direction)==1
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1redhealth, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2redhealth, health)
end
function infiniteTime()
wb(0x1042F3, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["fatfury2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x60
p2maxhealth = 0x60
local p1health = 0x1003CB
local p2health = 0x1004CB
local p1direction = 0x100367
local p2direction = 0x100467
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=42,
comboenabled=true,
p1healthx=49,
p1healthy=17,
p1healthenabled=true,
p2healthx=264,
p2healthy=17,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x1003A9)~=0
end
function playerTwoInHitstun()
return rb(0x1004A9)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
ww(0x10092A, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["fatfury3"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x78
p2maxhealth = 0x78
local p1health = 0x100489
local p2health = 0x100589
local p1direction = 0x100471
local p2direction = 0x100571
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=42,
comboenabled=true,
p1healthx=25,
p1healthy=21,
p1healthenabled=true,
p2healthx=284,
p2healthy=21,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x1004CC)~=0 or rb(0x1004CD)==8
end
function playerTwoInHitstun()
return rb(0x1005CC)~=0 or rb(0x1005CD)==8
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
ww(0x105680, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["galaxyfg"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xff
p2maxhealth = 0xff
local p1health = 0x10103C
local p2health = 0x101152
local p1combocounter = 0x10126A
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
p1healthx=18,
p1healthy=16,
p1healthenabled=true,
p2healthx=275,
p2healthy=16,
p2healthenabled=true,
comboenabled=true,
combotextx=136,
combotexty=42,
},
}
function playerOneFacingLeft()
return rb(0x10100D) == 0
end
function playerTwoFacingLeft()
return rb(0x101285) == 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth(health)
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function infiniteTime()
wb(0x101252,0xFE)
end
function maxCredits()
wb(0xD00034, 0x990)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["garou"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x78
p2maxhealth = 0x78
p1maxmeter = 0x80
p2maxmeter = 0x80
local p1direction = 0x100458
local p2direction = 0x100558
function gamemsg()
print "Known issues with garou:"
print "hitboxes don't currently work"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=145,
combotexty=40,
comboenabled=true,
p1healthx=6,
p1healthy=16,
p1healthenabled=true,
p2healthx=303,
p2healthy=16,
p2healthenabled=true,
p1meterx=90,
p1metery=208,
p1meterenabled=true,
p2meterx=222,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x10a39D)~=0
end
function playerTwoInHitstun()
return rb(0x10a39C)~=0
end
function readPlayerOneHealth()
return rb(0x10048E)
end
function writePlayerOneHealth(health)
wb(0x10048E, health)
end
function readPlayerTwoHealth()
return rb(0x10058E)
end
function writePlayerTwoHealth(health)
wb(0x10058E, health)
end
function readPlayerOneMeter()
return rb(0x1004BE)
end
function writePlayerOneMeter(meter)
wb(0x1004BE, meter)
end
function readPlayerTwoMeter()
return rb(0x1005BE)
end
function writePlayerTwoMeter(meter)
wb(0x1005BE, meter)
end
function infiniteTime()
wb(0x107490,0x99)
end
function maxCredits()
wb(0x10E008, 0x09)
wb(0x10E009, 0x09)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["gowcaizr"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x64
p2maxhealth = 0x64
local p1health = 0x102D09
local p2health = 0x1035Bf
local p1direction = 0x100186
local p2direction = 0x100187
function gamemsg()
print "Known issues with gowcaizr:"
print "Inconsistent combos"
print "Note that gowcaizr has no meter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=42,
comboenabled=true,
p1healthx=35,
p1healthy=17,
p1healthenabled=true,
p2healthx=258,
p2healthy=17,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0x80
end
function playerTwoFacingLeft()
return rb(p2direction)==0x80
end
function playerOneInHitstun()
return rb(0x10328c)==0x80 or rb(0x103b42)==0x80
end
function playerTwoInHitstun()
return rb(0x103a90)==0x80 or rb(0x103a1b)==0x80
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
wb(0x1062E1, 0x3C)
end
function Run()
infiniteTime()
end
]==]
UT.sources["gundamex"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x93
p2maxhealth = 0x93
local p1health = 0x204569
local p2health = 0x2045BF
local p1combocounter = 0x2035E7
local p2combocounter = 0x2035E9
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
}
gamedefaultconfig = {
hud = {
combotextx=180,
combotexty=42,
comboenabled=true,
p1healthx=32,
p1healthy=16,
p1healthenabled=true,
p2healthx=342,
p2healthy=16,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x203926) == 0
end
function playerTwoFacingLeft()
return rb(0x203F3A) == 0
end
function playerOneInHitstun()
return rb(p2combocounter) ~= 0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth(health)
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
wb(0x2035A3,0x9B)
wb(0x2035A2,0x0B)
end
function maxCredits()
wb(0x2034EF, 0xFF)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["hsf2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 0x30
p2maxmeter = 0x30
local p1_need_health_refill = false
local p2_need_health_refill = false
local p1health = 0xFF8366
local p1redhealth = 0xFF8368
local p1disphealth = 0xFF84F8
local p2health = 0xFF8766
local p2redhealth = 0xFF8768
local p2disphealth = 0xFF88F8
local p1meter = 0xFF85F0
local p2meter = 0xFF89F0
local p1action = 0
local p2action = 0
local p2inputs = 0
local p1inputs = 0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=178,
combotexty=49,
comboenabled=true,
p1healthx=34,
p1healthy=23,
p1healthenabled=true,
p2healthx=339,
p2healthy=23,
p2healthenabled=true,
p1meterx=82,
p1metery=207,
p1meterenabled=true,
p2meterx=294,
p2metery=207,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rw(0xFF8342) >= rw(0xFF8742)
end
function playerTwoFacingLeft()
return rw(0xFF8342) < rw(0xFF8742)
end
function playerOneInHitstun()
if rb(0xFF852C) > 0 then
return false
end
if rb(0xFF833F) == 14 then
return true
end
return false
end
function playerTwoInHitstun()
if rb(0xFF892C) > 0 then
return false
end
if rb(0xFF873F) == 14 then
return true
end
return false
end
function readPlayerOneHealth()
return rw(p1redhealth)
end
function writePlayerOneHealth(health)
local refill = false
if readPlayerOneHealth() < 33 then
refill = true
elseif ((p1action ~= 0x14 and p1action ~=0xe and p1action ~= 8) and (p2action==2 or p2action==0)) then
refill = true
elseif (p1action ~= 8) and readPlayerOneHealth() < 50 then
refill = true
end
if refill then
ww(p1health, health)
ww(p1redhealth, health)
ww(p1disphealth, health)
p1_need_health_refill=false
end
end
function readPlayerTwoHealth()
return rw(p2redhealth)
end
function writePlayerTwoHealth(health)
local refill = false
if readPlayerTwoHealth() < 33 then
refill = true
elseif ((p2action ~= 0x14 and p2action ~=0xe and p2action ~= 8) and (p1action==2 or p1action==0)) then
refill = true
elseif (p2action ~= 8) and readPlayerTwoHealth() < 50 then
refill = true
end
if refill then
ww(p2health, health)
ww(p2redhealth, health)
ww(p2disphealth, health)
p2_need_health_refill=false
end
end
function readPlayerOneMeter()
if rw(0xFF8008) == 0x2 then
return rb(p1meter)
else
return p1maxmeter
end
end
function writePlayerOneMeter(meter)
if rw(0xFF8008) == 0x2 then
wb(p1meter, meter)
end
end
function readPlayerTwoMeter()
if rw(0xFF8008) == 0x2 then
return rb(p2meter)
else
return p2maxmeter
end
end
function writePlayerTwoMeter(meter)
if rw(0xFF8008) == 0x2 then
wb(p2meter, meter)
end
end
local infiniteTime = function()
timer = rb(0xff8bfc)
if (timer < 0x98) then
ww(0xff8bfc,0x9928)
end
end
local neverEnd = function()
if p2_need_health_refill then
writePlayerTwoHealth(p2maxhealth)
end
if p1_need_health_refill then
writePlayerOneHealth(p1maxhealth)
end
if rb(0xff8741) == 10 or rb(0xff88bd) == 255 then
p2_need_health_refill=true
writePlayerTwoHealth(p2maxhealth)
end
if rb(0xff8341) == 10 or rb(0xff84bd) == 255 then
p1_need_health_refill=true
writePlayerOneHealth(p1maxhealth)
end
if readPlayerTwoHealth() < 33 then
p2_need_health_refill=true
writePlayerTwoHealth(p2maxhealth)
end
if readPlayerOneHealth() < 33 then
p1_need_health_refill=true
writePlayerOneHealth(p1maxhealth)
end
end
stage_selector = -1
local stageSelect = function()
if stage_selector == -1 then
return
end
if (rb(0xff8004) == 0x04 or rb(0xff8004) == 0x0e) then
wb(0xff8c4f,stage_selector)
end
wb(0x003fb7,0)
ww(0xFF8B64,stage_selector)
ww(0xFFBDF2,stage_selector)
ww(0xFFBEB2,stage_selector)
ww(0xFFD0B2,stage_selector)
ww(0xFFD295,stage_selector)
end
local player1Crouching = function()
if p1action == 2 then
return true
end
if p1action == 4 or p1action == 6 then
return false
end
if (p1action == 10 or p1action == 12) then
local ypos = rw(0xFF8346)
if (ypos <= 40) then
return bit.band(p1inputs, 0x4) == 0x4
end
end
return false
end
local getDistanceBetweenPlayers = function()
if playerOneFacingLeft() then
distance = rw(0xFF8342) - rw(0xFF8742)
else
distance = rw(0xFF8742) - rw(0xFF8342)
end
return distance
end
autoblock_selector = -1
local forceblock = false
local prev_p1action = 0
local inputs_at_jumpstart = 0
local autoblock_skip_counter = 60
local canblock = false
local autoBlock = function()
if autoblock_selector == -1 then
return
end
local DEBUG=false
if (p1action == 0 or p1action == 2 or p1action==6) then
setDirection(2,5)
forceblock = false
if autoblock_selector == 2 and canblock == true then
canblock = false
end
return
end
local distance = getDistanceBetweenPlayers()
if (p1action == 10 or p1action == 12) and distance < 265 then
if autoblock_selector == 2 and canblock == false then
if p2action == 14 then
setDirection(2,5)
canblock = true
end
return
end
if autoblock_selector == 3 then
autoblock_skip_counter = autoblock_skip_counter -1
if autoblock_skip_counter == 0 then
autoblock_skip_counter = 60
end
if autoblock_skip_counter > 40 then
return
end
end
local p1crouching = player1Crouching()
if playerOneFacingLeft() and p1crouching then
setDirection(2,1)
end
if playerTwoFacingLeft() and p1crouching then
setDirection(2,3)
end
if playerOneFacingLeft() and not p1crouching then
setDirection(2,4)
end
if playerTwoFacingLeft() and not p1crouching then
setDirection(2,6)
end
if DEBUG then print("ground block @ p1action=" .. p1action .. " | inputs=" .. p1inputs .. " | distance=" .. distance) end
return
end
local p1attacking = false
if autoblock_selector ~= 1 and autoblock_selector ~= 2 and p1action == 4 and distance < 265 then
if autoblock_selector == 3 then
autoblock_skip_counter = autoblock_skip_counter -1
if autoblock_skip_counter == 0 then
autoblock_skip_counter = 60
end
if autoblock_skip_counter > 30 then
return
end
end
local p1buttons = bit.band(p1inputs, 0x000F)
if prev_p1action ~= 4 then
inputs_at_jumpstart = p1inputs-p1buttons
p1attacking = false
end
if p1inputs-p1buttons ~= inputs_at_jumpstart and p1inputs-p1buttons > 10 then
p1attacking = true
forceblock = true
end
if (p2action ~= 6 and p2action ~= 8 and p2action ~= 14) then
forceblock = false
end
if (p1attacking or forceblock) then
if playerOneFacingLeft() then
setDirection(2,4)
else
setDirection(2,6)
end
if DEBUG then print("block high @ p1action=" .. p1action .. " | p2action=" .. p2action .. " | inputs=" .. p1inputs .. "/" .. p1buttons .. " | distance=" .. distance .. " | p1attacking=" .. tostring(p1attacking) .. " | forceblock=" .. tostring(forceblock)) end
return
end
setDirection(2,5)
if DEBUG then print("neutral @ p1action=" .. p1action .. " | p2action=" .. p2action .. " | inputs=" .. p1inputs .. "/" .. p1buttons .. " | distance=" .. distance .. " | p1attacking=" .. tostring(p1attacking) .. " | forceblock=" .. tostring(forceblock)) end
forceblock = false
return
end
if (distance >= 265 or p1action == 2) then
setDirection(2,5)
if DEBUG then print("neutral-4 @ p1action=" .. p1action .. " | inputs=" .. p1inputs .. " | distance=" .. distance) end
forceblock = false
return
end
if DEBUG then print("FINAL @ p1action=" .. p1action .. " | inputs=" .. p1inputs .. " | distance=" .. distance) end
end
dizzy_selector = -1
local p2DizzyControl = function()
local dizzy = 0
if dizzy_selector == -1 then
return
end
if dizzy_selector == 1 then
dizzy = 0x40
end
ww(0xFF8798, dizzy)
ww(0xFF879A, dizzy)
end
function Run()
p1action = rb(0xff833f)
p2action = rb(0xff873f)
p1inputs = rw(0xFF8076)
infiniteTime()
autoBlock()
neverEnd()
stageSelect()
p2DizzyControl()
prev_p1action = p1action
end
]==]
UT.sources["jchan2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x7FFF
p2maxhealth = 0x7FFF
p1maxmeter = 0x4000
p2maxmeter = 0x4000
local p1health = 0x201116
local p2health = 0x2013A2
local p1meter = 0x201200
local p2meter = 0x20148C
local p1combocounter = 0x20143b
local p2combocounter = 0x2011af
local p1prevhealth = rb(p1health)
local p2prevhealth = rb(p2health)
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=145,
combotexty=42,
comboenabled=true,
p1healthx=13,
p1healthy=20,
p1healthenabled=true,
p2healthx=289,
p2healthy=20,
p2healthenabled=true,
p1meterx=74,
p1metery=222,
p1meterenabled=true,
p2meterx=227,
p2metery=222,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return bit.band(bit.bxor(rb(0x200F86), rb(0x200F90)),0x2)==2
end
function playerTwoFacingLeft()
return bit.band(bit.bxor(rb(0x201212), rb(0x20121C)),0x2)==2
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
local ret = p1prevhealth
p1prevhealth = rws(p1health)
return ret
end
function writePlayerOneHealth(health)
ww(p1health, health)
end
function readPlayerTwoHealth()
local ret = p2prevhealth
p2prevhealth = rws(p2health)
return ret
end
function writePlayerTwoHealth(health)
ww(p2health, health)
end
function readPlayerOneMeter()
return rws(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rws(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
local infiniteTime = function()
wb(0x200109, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["jojos"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 10
p2maxmeter = 10
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Attack"] = 5,
["Medium Attack"] = 6,
["Strong Attack"] = 7,
["Stand"] = 8,
["Not in use 1"] = 9,
["Not in use 2"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=176,
combotexty=35,
comboenabled=true,
p1healthx=17,
p1healthy=15,
p1healthenabled=true,
p2healthx=356,
p2healthy=15,
p2healthenabled=true,
p1meterx=132,
p1metery=216,
p1meterenabled=true,
p2meterx=242,
p2metery=216,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x2034899)==0
end
function playerTwoFacingLeft()
return rb(0x2034CB9)==0
end
function playerOneInHitstun()
return rb(0x205BB39)~=0
end
function playerTwoInHitstun()
return rb(0x02034D91)~=0
end
function readPlayerOneHealth()
return rb(0x205BB28)
end
function writePlayerOneHealth(health)
wb(0x20349CD, health)
end
function readPlayerTwoHealth()
return rb(0x205BB29)
end
function writePlayerTwoHealth(health)
wb(0x2034DED, health)
end
function readPlayerOneMeter()
return rb(0x2034863)
end
function writePlayerOneMeter(meter)
wb(0x2034863, meter)
end
function readPlayerTwoMeter()
return rb(0x2034887)
end
function writePlayerTwoMeter(meter)
wb(0x2034887, meter)
end
local infiniteTime = function()
wb(0x20314B4, 0x63)
end
local infiniteCredit = function()
wb(0x20713A8, 0x09)
end
function Run()
infiniteTime()
infiniteCredit()
end
]==]
UT.sources["jojov"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 10
p2maxmeter = 10
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Attack"] = 5,
["Medium Attack"] = 6,
["Strong Attack"] = 7,
["Stand"] = 8,
["Not in use 1"] = 9,
["Not in use 2"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=176,
combotexty=34,
comboenabled=true,
p1healthx=18,
p1healthy=14,
p1healthenabled=true,
p2healthx=352,
p2healthy=14,
p2healthenabled=true,
p1meterx=134,
p1metery=216,
p1meterenabled=true,
p2meterx=242,
p2metery=216,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x2030479)==0
end
function playerTwoFacingLeft()
return rb(0x2030881)==0
end
function playerOneInHitstun()
return rb(0x2030551)~=0
end
function playerTwoInHitstun()
return rb(0x2030959)~=0
end
function readPlayerOneHealth()
return rb(0x20305AD)
end
function writePlayerOneHealth(health)
wb(0x20305AD, health)
end
function readPlayerTwoHealth()
return rb(0x20309B5)
end
function writePlayerTwoHealth(health)
wb(0x20309B5, health)
end
function readPlayerOneMeter()
return rb(0x2030443)
end
function writePlayerOneMeter(meter)
wb(0x2030443, meter)
end
function readPlayerTwoMeter()
return rb(0x2030467)
end
function writePlayerTwoMeter(meter)
wb(0x2030467, meter)
end
function Run()
wb(0x202CEBD, 0x1)
wb(0x202D0B0, 0x63)
wb(0x206B850, 0x09)
end
]==]
UT.sources["kabukikl"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x64
p2maxhealth = 0x64
p1maxmeter = 0x3C
p2maxmeter = 0x3C
local p1health = 0x100e56
local p2health = 0x100f56
local p1meter = 0x100e6e
local p2meter = 0x100f6e
local p1direction = 0x100eb9
local p2direction = 0x100fb9
local p1combocounter = 0x100f5c
local p2combocounter = 0x100e5c
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=140,
combotexty=42,
comboenabled=true,
p1healthx=42,
p1healthy=17,
p1healthenabled=true,
p2healthx=267,
p2healthy=17,
p2healthenabled=true,
p1meterx=119,
p1metery=209,
p1meterenabled=true,
p2meterx=194,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==2
end
function playerTwoFacingLeft()
return rb(p2direction)==2
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p1meter)
end
function writePlayerTwoMeter(meter)
wb(p1meter, meter)
end
function infiniteTime()
ww(0x103a16, 0x9900)
end
function Run()
infiniteTime()
end
]==]
UT.sources["karnovr"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xFF
p2maxhealth = 0xFF
p1maxmeter = 0x3C
p2maxmeter = 0x3C
local p1health = 0x1037B7
local p1redhealth = 0x1037B9
local p2health = 0x1039B7
local p2redhealth = 0x1039B9
function gamemsg()
print "Known issues with karnovr:"
print "Note karnovr has no meter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=139,
combotexty=42,
comboenabled=true,
p1healthx=18,
p1healthy=21,
p1healthenabled=true,
p2healthx=275,
p2healthy=21,
p2healthenabled=true,
}
}
function playerOneFacingLeft()
return rb(0x103691)==0 or rb(0x103691)==0x40
end
function playerTwoFacingLeft()
return rb(0x103891)==0 or rb(0x103891)==0x40
end
function playerOneInHitstun()
return rb(0x10372C)~=0
end
function playerTwoInHitstun()
return rb(0x10392C)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
ww(0x103A70, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kf2k5uni"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x67
p2maxhealth = 0x67
p1maxmeter = 0x5
p2maxmeter = 0x5
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1082E3
local p2meter = 0x1084E3
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084B0
local p2combocounter = 0x1082B0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=38,
comboenabled=true,
p1healthx=36,
p1healthy=20,
p1healthenabled=true,
p2healthx=257,
p2healthy=20,
p2healthenabled=true,
p1meterx=98,
p1metery=209,
p1meterenabled=true,
p2meterx=203,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x10A7D2, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kizuna"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xC0
p2maxhealth = 0xC0
local p1health = 0x108313
local p2health = 0x108513
local p1combocounter = 0x108554
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=42,
comboenabled=true,
p1healthx=34,
p1healthy=19,
p1healthenabled=true,
p2healthx=259,
p2healthy=19,
p2healthenabled=true,
},
}
function playerTwoFacingLeft()
return rb(0x10840F) == 0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth(health)
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
wb(0x10892A,0x99)
end
function maxCredits()
wb(0xD00034, 0x09)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["kof2000"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x67
p2maxhealth = 0x67
p1maxmeter = 0x90
p2maxmeter = 0x90
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1081e8
local p2meter = 0x1083e8
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084b0
local p2combocounter = 0x1082b0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=38,
comboenabled=true,
p1healthx=33,
p1healthy=18,
p1healthenabled=true,
p2healthx=260,
p2healthy=18,
p2healthenabled=true,
p1meterx=76,
p1metery=41,
p1meterenabled=true,
p2meterx=217,
p2metery=41,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x10A7e6, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof2001"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x67
p2maxhealth = 0x67
p1maxmeter = 0x90
p2maxmeter = 0x90
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1081e8
local p2meter = 0x1083e8
local p1metertoggle = p1meter+0x1e3
local p2metertoggle = p2meter+0x1e3
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084b0
local p2combocounter = 0x1082b0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=45,
comboenabled=true,
p1healthx=36,
p1healthy=21,
p1healthenabled=true,
p2healthx=257,
p2healthy=21,
p2healthenabled=true,
p1meterx=114,
p1metery=207,
p1meterenabled=true,
p2meterx=179,
p2metery=207,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
if rb(p1metertoggle) then return p1maxmeter end
return rb(p1meter)
end
function writePlayerOneMeter(meter)
if (meter==p1maxmeter) then
wb(p1metertoggle, 1)
wb(p1meter, 0)
else
wb(p1meter, meter)
wb(p1metertoggle, 0)
end
end
function readPlayerTwoMeter()
if rb(p2metertoggle) then return p2maxmeter end
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
if (meter==p2maxmeter) then
wb(p2metertoggle, 1)
wb(p2meter, 0)
else
wb(p2meter, meter)
wb(p2metertoggle, 0)
end
end
function infiniteTime()
ww(0x10A7d2, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof2002"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x66
p2maxhealth = 0x66
p1maxmeter = 0x14A
p2maxmeter = 0x14A
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1082E3
local p2meter = 0x1084E3
local p1meterbar = 0x1081E8
local p2meterbar = 0x1083E8
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084B0
local p2combocounter = 0x1082B0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=42,
comboenabled=true,
p1healthx=36,
p1healthy=21,
p1healthenabled=true,
p2healthx=257,
p2healthy=21,
p2healthenabled=true,
p1meterx=98,
p1metery=209,
p1meterenabled=true,
p2meterx=195,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meterbar) + rb(p1meter)*0x42
end
function writePlayerOneMeter(meter)
wb(p1meter, meter/0x42)
wb(p1meterbar, meter%0x42)
end
function readPlayerTwoMeter()
return rb(p2meterbar) + rb(p2meter)*0x42
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter/0x42)
wb(p2meterbar, meter%0x42)
end
function infiniteTime()
ww(0x10A7D2, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof2003"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x71
p2maxhealth = 0x71
p1maxmeter = 0x168
p2maxmeter = 0x168
local p1char_a = 0x107d1a
local p2char_a = 0x107d1b
local p1char = 1
local p2char = 1
local p1health = {0x2FE91D, 0x2FEA1D, 0x2FEB1D}
local p2health = {0x2FED1D, 0x2FEE1D, 0x2FEF1D}
local p1meter = 0x2FE800
local p2meter = 0x2FEC00
local p1direction = {0x10108F, 0x10138F, 0x10168F}
local p2direction = {0x101B0F, 0x101E0F, 0x10210F}
local p1combocounter = 0x2FE80F
local p2combocounter = 0x2FEC0F
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=40,
comboenabled=true,
p1healthx=2,
p1healthy=24,
p1healthenabled=true,
p2healthx=292,
p2healthy=24,
p2healthenabled=true,
p1meterx=109,
p1metery=208,
p1meterenabled=true,
p2meterx=184,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction[p1char])==0
end
function playerTwoFacingLeft()
return rb(p2direction[p2char])==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health[p1char])
end
function writePlayerOneHealth(health)
wb(p1health[p1char], health-1)
end
function readPlayerTwoHealth()
return rb(p2health[p2char])
end
function writePlayerTwoHealth(health)
wb(p2health[p2char], health-1)
end
function readPlayerOneMeter()
return rb(p1meter) + rb(p1meter+0x4)*0x48
end
function writePlayerOneMeter(meter)
wb(p1meter+0x4, meter/0x48)
wb(p1meter, meter%0x48)
end
function readPlayerTwoMeter()
return rb(p2meter) + rb(p2meter+0x4)*0x48
end
function writePlayerTwoMeter(meter)
wb(p2meter+0x4, meter/0x48)
wb(p2meter, meter%0x48)
end
function infiniteTime()
ww(0x107D62, 0x6000)
end
function Run()
infiniteTime()
p1char = rb(p1char_a)+1
p2char = rb(p2char_a)+1
end
]==]
UT.sources["kof94"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xD0
p2maxhealth = 0xD0
p1maxmeter = 0x7F
p2maxmeter = 0x7F
local p1health = 0x108221
local p2health = 0x108421
local p1meter = 0x108219
local p2meter = 0x108419
local p1direction = 0x100731
local p2direction = 0x100b31
local p1combocounter = 0x10840e
local p2combocounter = 0x10820e
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=140,
combotexty=42,
comboenabled=true,
p1healthx=36,
p1healthy=16,
p1healthenabled=true,
p2healthx=258,
p2healthy=16,
p2healthenabled=true,
p1meterx=80,
p1metery=205,
p1meterenabled=true,
p2meterx=211,
p2metery=205,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x10882E, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof95"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with kof95:"
print "Combos aren't tracked"
end
p1maxhealth = 0xD0
p2maxhealth = 0xD0
p1maxmeter = 0x7F
p2maxmeter = 0x7F
local p1health = 0x108221
local p2health = 0x108421
local p1meter = 0x108219
local p2meter = 0x108419
local p1direction = 0x100931
local p2direction = 0x100d31
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
p1healthx=33,
p1healthy=21,
p1healthenabled=true,
p2healthx=260,
p2healthy=21,
p2healthenabled=true,
p1meterx=97,
p1metery=205,
p1meterenabled=true,
p2meterx=196,
p2metery=205,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function _playerOneInHitstun()
end
function _playerTwoInHitstun()
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x10A836, 0x6000)
end
function Run()
infiniteTime()
wb(0x10E79A, 0x1)
end
]==]
UT.sources["kof96"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with kof96:"
print "Doesn't activate MAX properly"
end
p1maxhealth = 0x68
p2maxhealth = 0x68
p1maxmeter = 0x80
p2maxmeter = 0x80
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1081e8
local p2meter = 0x1083e8
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084b0
local p2combocounter = 0x1082b0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=42,
comboenabled=true,
p1healthx=33,
p1healthy=21,
p1healthenabled=true,
p2healthx=260,
p2healthy=21,
p2healthenabled=true,
p1meterx=91,
p1metery=205,
p1meterenabled=true,
p2meterx=202,
p2metery=205,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
if meter==p1maxmeter then
ww(p1meter+4, 0x4000)
ww(p1meter+8, 0x0010)
end
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
if meter==p2maxmeter then
ww(p2meter+4, 0x4000)
ww(p2meter+8, 0x0010)
end
end
function infiniteTime()
ww(0x10A836, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof97"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with kof97:"
print "Doesn't activate MAX properly"
print "Only partial support for advance with refilling max meter"
end
p1maxhealth = 0x68
p2maxhealth = 0x68
p1maxmeter = 0x80
p2maxmeter = 0x80
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1081e8
local p2meter = 0x1083e8
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084b0
local p2combocounter = 0x1082b0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=33,
comboenabled=true,
p1healthx=33,
p1healthy=16,
p1healthenabled=true,
p2healthx=260,
p2healthy=16,
p2healthenabled=true,
p1meterx=123,
p1metery=205,
p1meterenabled=true,
p2meterx=194,
p2metery=205,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
if meter==p1maxmeter then
wb(0x1082e3, 3)
ww(p1meter+4, 0x4000)
wb(p1meter+8, 0x10)
end
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
if meter==p2maxmeter then
wb(0x1084e3, 3)
ww(p2meter+4, 0x4000)
wb(p2meter+8, 0x10)
end
end
function infiniteTime()
ww(0x10A83a, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof98"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with kof98:"
print "Doesn't activate MAX properly"
print "Only partial support for advance with refilling max meter"
end
p1maxhealth = 0x68
p2maxhealth = 0x68
p1maxmeter = 0x80
p2maxmeter = 0x80
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1081e8
local p2meter = 0x1083e8
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084b0
local p2combocounter = 0x1082b0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=38,
comboenabled=true,
p1healthx=33,
p1healthy=20,
p1healthenabled=true,
p2healthx=260,
p2healthy=20,
p2healthenabled=true,
p1meterx=107,
p1metery=204,
p1meterenabled=true,
p2meterx=186,
p2metery=204,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
if meter==p1maxmeter then
wb(0x1082e3, 3)
ww(p1meter+4, 0x4000)
wb(p1meter+8, 0x10)
end
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
if meter==p2maxmeter then
wb(0x1084e3, 3)
ww(p2meter+4, 0x4000)
wb(p2meter+8, 0x10)
end
end
function infiniteTime()
ww(0x10A83a, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["kof99"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x66
p2maxhealth = 0x66
p1maxmeter = 0x90
p2maxmeter = 0x90
local p1health = 0x108239
local p2health = 0x108439
local p1meter = 0x1081e8
local p2meter = 0x1083e8
local p1direction = 0x108131
local p2direction = 0x108331
local p1combocounter = 0x1084b0
local p2combocounter = 0x1082b0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=38,
comboenabled=true,
p1healthx=33,
p1healthy=20,
p1healthenabled=true,
p2healthx=260,
p2healthy=20,
p2healthenabled=true,
p1meterx=76,
p1metery=41,
p1meterenabled=true,
p2meterx=217,
p2metery=41,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x10A7e6, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["lastblad"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Note that you have to restart the script whenever characters are switched"
end
p1maxhealth = 0x100
p2maxhealth = 0x100
p1maxmeter = 0x40
p2maxmeter = 0x40
local p1uid = rdw(0x10AC98)
local p2uid = rdw(0x10AC9C)
local p1health = p1uid+0x180
local p2health = p2uid+0x180
local p1meter = p1uid+0x18D
local p2meter = p2uid+0x18D
local p1direction = p1uid+0xE3
local p2direction = p2uid+0xE3
local p1combocounter = 0x10E294
local p2combocounter = 0x10E295
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=147,
combotexty=48,
comboenabled=true,
p1healthx=17,
p1healthy=16,
p1healthenabled=true,
p2healthx=292,
p2healthy=16,
p2healthenabled=true,
p1meterx=105,
p1metery=209,
p1meterenabled=true,
p2meterx=210,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
wb(0x10E32B,0x61)
end
function Run()
infiniteTime()
end
]==]
UT.sources["lb2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Note that you have to restart the script whenever characters are switched"
end
p1maxhealth = 0x100
p2maxhealth = 0x100
p1maxmeter = 0x40
p2maxmeter = 0x40
local p1uid = rdw(0x10E344)
local p2uid = rdw(0x10E348)
local p1health = p1uid+0x17E
local p2health = p2uid+0x17E
local p1meter = p1uid+0x17D
local p2meter = p2uid+0x17D
local p1direction = p1uid+0x41
local p2direction = p2uid+0x41
local p1combocounter = 0x10E486
local p2combocounter = 0x10E487
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=147,
combotexty=36,
comboenabled=true,
p1healthx=17,
p1healthy=17,
p1healthenabled=true,
p2healthx=292,
p2healthy=17,
p2healthenabled=true,
p1meterx=106,
p1metery=209,
p1meterenabled=true,
p2meterx=208,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)>0
end
function playerTwoInHitstun()
return rb(p1combocounter)>0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local function infiniteTime()
wb(0x10E595, 0x60)
end
function Run()
infiniteTime()
end
]==]
UT.sources["martmast"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xD1
p2maxhealth = 0xD1
p1maxmeter = 0x68
p2maxmeter = 0x68
local p1health = 0x81C67F
local p2health = 0x81C7BB
local p1meter = 0x80DAA1
local p2meter = 0x80DC5D
local p1stocks = 0x80DA99
local p2stocks = 0x80DC55
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
p1healthx=42,
p1healthy=14,
p1healthenabled=true,
p2healthx=395,
p2healthy=14,
p2healthenabled=true,
p1meterx=160,
p1metery=212,
p1meterenabled=true,
p2meterx=272,
p2metery=212,
p2meterenabled=true,
},
}
function playerTwoFacingLeft()
return rb(0x815A0D) == 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(0x80DAA1)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
wb(p1stocks, 0x09)
end
function readPlayerTwoMeter()
return rb(0x80DC5D)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
wb(p2stocks, 0x09)
end
function infiniteTime()
wb(0x80AC19,0x64)
end
function maxCredits()
wb(0x81B5B4, 0x99)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["matrim"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x95
p2maxhealth = 0x95
p1maxmeter = 240
p2maxmeter = 240
local p1healthaddress = 0x10306B
local p1displayhealth = 0x103069
local p1redhealthaddress = 0x10306F
local p2healthaddress = 0x102E9F
local p2displayhealth = 0x102E9D
local p2redhealthaddress = 0x102EA3
local p1meteraddress = 0x10307D
local p2meteraddress = 0x102EB1
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=146,
combotexty=32,
comboenabled=true,
p1healthx=41,
p1healthy=12,
p1healthenabled=true,
p2healthx=268,
p2healthy=12,
p2healthenabled=true,
p1meterx=122,
p1metery=207,
p1meterenabled=true,
p2meterx=189,
p2metery=207,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x103041)==1
end
function playerTwoFacingLeft()
return rb(0x103041)==0
end
function playerOneInHitstun()
return rb(0x103085)~=0
end
function playerTwoInHitstun()
return rb(0x102EB9)~=0
end
function readPlayerOneHealth()
return rb(p1healthaddress)
end
function writePlayerOneHealth(health)
wb(p1healthaddress, health)
wb(p1displayhealth, health)
wb(p1redhealthaddress, health)
end
function readPlayerTwoHealth()
return rb(p2healthaddress)
end
function writePlayerTwoHealth(health)
wb(p2healthaddress, health)
wb(p2displayhealth, health)
wb(p2redhealthaddress, health)
writePlayerTwoMeter(0)
end
function readPlayerOneMeter()
return rb(p1meteraddress)
end
function writePlayerOneMeter(meter)
wb(p1meteraddress, meter)
end
function readPlayerTwoMeter()
return rb(p2meteraddress)
end
function writePlayerTwoMeter(meter)
wb(p2meteraddress, meter)
end
local infiniteTime = function()
wb(0x10b90b, 0x63)
end
function Run()
infiniteTime()
end
]==]
UT.sources["msh"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
p1maxmeter = 0x03
p2maxmeter = 0x03
function gamemsg()
print "Known issues with msh:"
print "No combo counter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
p1healthx=18,
p1healthy=16,
p1healthenabled=true,
p2healthx=355,
p2healthy=16,
p2healthenabled=true,
p1meterx=31,
p1metery=26,
p1meterenabled=true,
p2meterx=350,
p2metery=26,
p2meterenabled=true,
},
}
function readPlayerOneHealth()
return rb(0xFF4191)
end
function writePlayerOneHealth(health)
wb(0xFF4191, health)
end
function readPlayerTwoHealth()
return rb(0xFF4591)
end
function writePlayerTwoHealth(health)
wb(0xFF4591, health)
end
function readPlayerOneMeter()
return rb(0xFF4198)
end
function writePlayerOneMeter(meter)
wb(0xFF4198, meter)
end
function readPlayerTwoMeter()
return rb(0xFF4598)
end
function writePlayerTwoMeter(meter)
wb(0xFF4598, meter)
end
function infiniteTime()
wb(0xFF4808, 0x99)
end
function gemsPlayerOne()
wb(0xFF41B6, 0x00)
wb(0xFF41B7, 0x02)
wb(0xFF41B8, 0x04)
wb(0xFF41B9, 0x06)
wb(0xFF41BA, 0x08)
wb(0xFF41BB, 0x0A)
end
function Run()
infiniteTime()
for gemMem = 0xFF41B6, 0xFF41BB, 1 do
if rb(gemMem) ~= 0x00 and rb(gemMem) ~= 0x02 and rb(gemMem) ~= 0x04 and rb(gemMem) ~= 0x06 and rb(gemMem) ~= 0x08 and rb(gemMem) ~= 0x0A then
gemsPlayerOne()
end
end
end
]==]
UT.sources["mshvsf"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
p1maxmeter = 0x03
p2maxmeter = 0x03
local p1health = 0xFF3A51
local p1redhealth = 0xFF3A5B
local p1char2health = 0xFF4251
local p1char2redhealth = 0xFF425B
local p1charactive = 0xFF3A61
local p2health = 0xFF3E51
local p2redhealth = 0xFF3E5B
local p2char2health = 0xFF4651
local p2char2redhealth = 0xFF465B
local p2charactive = 0xFF3E61
local p1meter = 0xFF3A54
local p2meter = 0xFF3E54
local p1combocounter = 0xFF4110
local p2combocounter = 0xFF4510
local p1direction = 0xFF384b
local p1char2direction = 0xFF404b
local p2direction = 0xFF3C4b
local p2char2direction = 0xFF444B
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=178,
combotexty=32,
comboenabled=true,
p1healthx=32,
p1healthy=16,
p1healthenabled=true,
p2healthx=341,
p2healthy=16,
p2healthenabled=true,
p1meterx=176,
p1metery=210,
p1meterenabled=true,
p2meterx=205,
p2metery=210,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
if (rb(p1charactive)==0) then
return rb(p1direction)==0
end
return rb(p1char2direction)==0
end
function playerTwoFacingLeft()
if (rb(p2charactive)==0) then
return rb(p2direction)==0
end
return rb(p2char2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
if (rb(p1charactive)==0) then
return rb(p1health)
end
return rb(p1char2health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1redhealth, health)
wb(p1char2health, health)
wb(p1char2redhealth, health)
end
function readPlayerTwoHealth()
if (rb(p2charactive)==0) then
return rb(p2health)
end
return rb(p2char2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2redhealth, health)
wb(p2char2health, health)
wb(p2char2redhealth, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0xFF4808, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["mvc"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
p1maxmeter = 0x03
p2maxmeter = 0x03
local p1healthchar1 = 0xFF3271
local p1healthchar2 = 0xFF3A71
local p2healthchar1 = 0xFF3671
local p2healthchar2 = 0xFF3E71
local p1meter = 0xFF3274
local p2meter = 0xFF3674
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=180,
combotexty=45,
comboenabled=true,
p1healthx=32,
p1healthy=21,
p1healthenabled=true,
p2healthx=341,
p2healthy=21,
p2healthenabled=true,
p1meterx=176,
p1metery=215,
p1meterenabled=true,
p2meterx=205,
p2metery=215,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0xff344b)==1
end
function playerTwoFacingLeft()
return rb(0xff344b)==0
end
function playerOneInHitstun()
return rb(0xff3520)~=0
end
function playerTwoInHitstun()
return rb(0xff3120)~=0
end
function readPlayerOneHealth()
return rb(p1healthchar1)
end
function readPlayerTwoHealth()
return rb(p2healthchar1)
end
function writePlayerOneHealth(health)
wb(p1healthchar1, health)
wb(p1healthchar2, health)
end
function writePlayerTwoHealth(health)
wb(p2healthchar1, health)
wb(p2healthchar2, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
wb(0xFF4008, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["mwarr"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with mwarr:"
print "Messing with player inputs (recording, replaying, opening the menu) freezes the game"
print "Game unfreezes when controls are returned back to normal"
end
p1maxhealth = 0x0100
p2maxhealth = 0x0100
p1maxmeter = 0x0300
p2maxmeter = 0x0300
local p1health = 0x112fce
local p2health = 0x112fd0
local p1meter = 0x113684
local p2meter = 0x113686
local p1direction = 0x112f5e
local p2direction = 0x112f60
local p1recovery = (0x1128ff+0x8)
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Coin"] = 8,
["Start"] = 9,
}
gamedefaultconfig = {
hud = {
combotextx=170,
combotexty=45,
comboenabled=true,
p1healthx=40,
p1healthy=21,
p1healthenabled=true,
p2healthx=317,
p2healthy=21,
p2healthenabled=true,
p1meterx=155,
p1metery=225,
p1meterenabled=true,
p2meterx=203,
p2metery=225,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==2
end
function playerTwoFacingLeft()
return rb(p2direction)==2
end
function _playerOneInHitstun()
end
function playerTwoInHitstun()
return rb(p1recovery)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
return ww(p1health,health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
function infiniteTime()
wb(0x112121,0x95)
end
function Run()
infiniteTime()
end
]==]
UT.sources["ninjamas"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xD0
p2maxhealth = 0xD0
p1maxmeter = 0x60
p2maxmeter = 0x60
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=150,
combotexty=42,
comboenabled=true,
p1healthx=25,
p1healthy=19,
p1healthenabled=true,
p2healthx=284,
p2healthy=19,
p2healthenabled=true,
p1meterx=120,
p1metery=207,
p1meterenabled=true,
p2meterx=193,
p2metery=207,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x100d21)==0
end
function playerTwoFacingLeft()
return rb(0x101d21)==0
end
function playerOneInHitstun()
return rb(0x100089)~=0
end
function playerTwoInHitstun()
return rb(0x101089)~=0
end
function readPlayerOneHealth()
return rb(0x100050)
end
function writePlayerOneHealth(health)
wb(0x100050, health)
end
function readPlayerTwoHealth()
return rb(0x101050)
end
function writePlayerTwoHealth(health)
wb(0x101050, health)
end
function readPlayerOneMeter()
return rb(0x1000AE)
end
function writePlayerOneMeter(meter)
if rb(0x1000AC) == 7 then
wb(0x1000AE, 0)
else
wb(0x1000AE, meter)
end
end
function readPlayerTwoMeter()
return rb(0x1010AE)
end
function writePlayerTwoMeter(meter)
if rb(0x1010AC) == 7 then
wb(0x1010AE, 0)
else
wb(0x1010AE, meter)
end
end
function infiniteTime()
wb(0x10C021, 0x9A)
end
function Run()
infiniteTime()
end
]==]
UT.sources["rabbit"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x88
p2maxhealth = 0x88
p1maxmeter = 0x03
p2maxmeter = 0x03
local p1health = 0xFF24EF
local p2health = 0xFF2533
local p1combocounter = 0xFF2525
local p2combocounter = 0xFF2569
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=42,
comboenabled=true,
p1healthx=9,
p1healthy=12,
p1healthenabled=true,
p2healthx=300,
p2healthy=12,
p2healthenabled=true,
p1meterx=22,
p1metery=223,
p1meterenabled=true,
p2meterx=288,
p2metery=223,
p2meterenabled=true,
},
}
function playerOneFacingleft()
return rb(0xFF1C25) == 0
end
function playerTwoFacingLeft()
return rb(0xFF2025) == 0
end
function playerOneInHitstun()
return rb(p2combocounter) ~= 0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth(health)
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(0xFF24FA)
end
function writePlayerOneMeter(meter)
wb(0xFF24FA, meter)
end
function readPlayerTwoMeter()
return rb(0xFF253F)
end
function writePlayerTwoMeter(meter)
wb(0xFF253F, meter)
end
function infiniteTime()
wb(0xFF2570,0x99)
end
function maxCredits()
wb(0xFFFE48, 0x09)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["ragnagrd"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xFF
p2maxhealth = 0xFF
p1barhealth = {0x1009B7, 0x100AB7, 0x100BB7, 0x100CB7, 0x100DB7, 0x100EB7, 0x100FB7, 0x1010B7, 0x1011B7, 0x1012B7}
p2barhealth = {0x1009B9, 0x100AB9, 0x100BB9, 0x100CB9, 0x100DB9, 0x100EB9, 0x100FB9, 0x1010B9, 0x1011B9, 0x1012B9}
local p1health = 0x109089
local p1stock1 = 0x1090A9
local p1stock2 = 0x1090AA
local p1elem1 = 0x1090A0
local p1elem2 = 0x1090A1
local p2health = 0x109361
local p2stock1 = 0x109381
local p2stock2 = 0x109382
local p2elem1 = 0x109378
local p2elem2 = 0x109379
local stall = 0
local stallmax = 7
function gamemsg()
print "Known issues with ragnagrd:"
print "GUI not working"
print "Life Bar does not accurately reflect life when not set to max"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
combogui = {
combotextx=146,
combotexty=37,
comboenabled=true,
p1healthx=25,
p1healthy=21,
p1healthenabled=true,
p2healthx=50,
p2healthy=21,
p2healthenabled=true,
},
}
function roundStart()
return rb(0x109373) == 0 and rb(0x109393) == 1
end
function playerOneFacingLeft()
return rb(0x10915E)==1
end
function playerTwoFacingLeft()
return rb(0x109436)==1
end
function playerOneInHitstun()
return rb(0x109175)~=0
end
function playerTwoInHitstun()
return rb(0x10944D)~=0 or rb(0x10943A)==0x20
end
function readPlayerOneHealth()
return rb(0x109089)
end
function writePlayerOneHealth(health)
if stall >= stallmax then
wb(p1health, p1maxhealth)
wb(0x10908A, 0x00)
for i, v in ipairs(p1barhealth) do
if v>0 and roundStart() then wb(v, 0x60) end
end
end
end
function readPlayerTwoHealth()
return rb(0x109361)
end
function writePlayerTwoHealth()
if stall >= stallmax then
wb(p2health, p2maxhealth)
wb(0x109363, 0x00)
for j, w in ipairs(p2barhealth) do
if w>0 then wb(w, 0x60) end
end
end
end
function readPlayerOneMeter()
return rb(p1stock1)
end
function writePlayerOneMeter(meter)
if not playerTwoInHitstun() then
wb(p1stock1, rb(p1elem1))
wb(p1stock2, rb(p1elem2))
end
end
function readPlayerTwoMeter()
return rb(p2stock1)
end
function writePlayerTwoMeter(meter)
if not playerOneInHitstun() then
wb(p2stock1, rb(p2elem1))
wb(p2stock2, rb(p2elem2))
end
end
function infiniteTime()
ww(0x10022E, 0x0601)
end
function Run()
if roundStart() then
if stall < stallmax then stall = stall + 1 end
else stall = 0
end
if stall >= stallmax then
infiniteTime()
writePlayerOneMeter()
writePlayerTwoMeter()
end
end
]==]
UT.sources["rbff1"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xC0
p2maxhealth = 0xC0
p1maxmeter = 0x3C
p2maxmeter = 0x3C
local p1health = 0x100489
local p2health = 0x100589
local p1meter = 0x1004BA
local p2meter = 0x1005BA
local p1direction = 0x100471
local p2direction = 0x100571
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=35,
comboenabled=true,
p1healthx=49,
p1healthy=21,
p1healthenabled=true,
p2healthx=261,
p2healthy=21,
p2healthenabled=true,
p1meterx=79,
p1metery=208,
p1meterenabled=true,
p2meterx=234,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x100490)~=0
end
function playerTwoInHitstun()
return rb(0x100590)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x106AA8, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["rbff2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xC0
p2maxhealth = 0xC0
p1maxmeter = 0x3C
p2maxmeter = 0x3C
local p1health = 0x10048b
local p2health = 0x10058b
local p1meter = 0x1004BC
local p2meter = 0x1005Bc
local p1direction = 0x100471
local p2direction = 0x100571
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=40,
comboenabled=true,
p1healthx=49,
p1healthy=21,
p1healthenabled=true,
p2healthx=261,
p2healthy=21,
p2healthenabled=true,
p1meterx=79,
p1metery=208,
p1meterenabled=true,
p2meterx=234,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x100490)==0
end
function playerTwoInHitstun()
return rb(0x100590)==0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x107C28, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["rbffspec"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xC0
p2maxhealth = 0xC0
p1maxmeter = 0x3C
p2maxmeter = 0x3C
local p1health = 0x10048B
local p2health = 0x10058B
local p1meter = 0x1004BC
local p2meter = 0x1005Bc
local p1direction = 0x100471
local p2direction = 0x100571
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=40,
comboenabled=true,
p1healthx=49,
p1healthy=21,
p1healthenabled=true,
p2healthx=261,
p2healthy=21,
p2healthenabled=true,
p1meterx=79,
p1metery=208,
p1meterenabled=true,
p2meterx=234,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(0x100490)==0
end
function playerTwoInHitstun()
return rb(0x100590)==0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x106AB4, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["redearth"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 124
p2maxhealth = 124
p1maxmeter = 3
p2maxmeter = 3
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hitbox = {
enabled=true,
},
hud = {
combotextx=180,
combotexty=42,
comboenabled=true,
p1healthx=49,
p1healthy=12,
p1healthenabled=true,
p2healthx=324,
p2healthy=12,
p2healthenabled=true,
p1meterx=162,
p1metery=28,
p1meterenabled=true,
p2meterx=220,
p2metery=28,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x206aa66) == 16
end
function playerTwoFacingLeft()
return rb(0x206aa66) == 0
end
function _playerOneInHitstun()
end
function playerTwoInHitstun()
return rb(0x206AAEE)~=0
end
function readPlayerOneHealth()
return rb(0x206A843)
end
function writePlayerOneHealth(health)
return wb(0x206a841, health)
end
function readPlayerTwoHealth()
return rb(0x206A713)
end
function writePlayerTwoHealth(health)
wb(0x206AAC1, health)
end
function readPlayerOneMeter()
return rb(0x206A8D5)
end
function writePlayerOneMeter(meter)
if meter > 3 then meter = 3 end
wb(0x206A8D5, meter)
for i = 1,meter do
wb(0x0206A8CD+i, 2)
end
end
function _readPlayerTwoMeter()
end
function _writePlayerTwoMeter(meter)
end
local function infiniteTime()
wb(0x2060701,154)
end
stunMeterEnabled = true
local function stunMeter()
P2StunMeter = rb(0x206AADA)
P2StunCounter = rb(0x206AB13)
P2UnitID = memory.readbyte(0x206AB25)
if P2UnitID == 0 then P2StunResistance = 36
elseif	P2UnitID == 1 then P2StunResistance = 34
elseif	P2UnitID == 2 then P2StunResistance = 30
elseif	P2UnitID == 3 then P2StunResistance = 28
end
P2TotalSR = P2StunResistance + (P2StunCounter*5)
gui.text(184,72, "Stun: " ..P2StunMeter, "green")
gui.text(168,82, "Max Stun: " ..P2TotalSR, "green")
end
function Run()
infiniteTime()
if stunMeterEnabled then stunMeter() end
end
]==]
UT.sources["ringdest"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x0116
p2maxhealth = 0x0116
local p1health = 0xFF802C
local p1redhealth = 0xFF802E
local p2health = 0xFF842C
local p2redhealth = 0xFF842E
local p1direction = 0xFF8038
local p2direction = 0xFF8438
function gamemsg()
print "Known issues with ringdest:"
print "Doesn't track combos"
print "Note that slammast doesn't have meter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Hold"] = 5,
["Weak punch"] = 6,
["Strong punch"] = 7,
["Button 4"] = 8,
["Weak kick"] = 9,
["Strong kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
p1healthx=38,
p1healthy=25,
p1healthenabled=true,
p2healthx=335,
p2healthy=25,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
ww(p1redhealth, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
ww(p2redhealth, health)
end
local infiniteTime = function()
wb(0xFF72CA, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["rotd"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xC8
p2maxhealth = 0xC8
p1maxmeter = 0xD8
p2maxmeter = 0xD8
local p1health = 0x1024CF
local p1char2health = 0x1027BF
local p2health = 0x102357
local p2char2health = 0x102067
local p1meter = 0x1024E3
local p2meter = 0x10236B
local p1direction = 0x102427
local p2direction = 0x1022AF
local p1combocounter = 0x102351
local p2combocounter = 0x1024C9
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=146,
combotexty=37,
comboenabled=true,
p1healthx=40,
p1healthy=16,
p1healthenabled=true,
p2healthx=268,
p2healthy=16,
p2healthenabled=true,
p1meterx=94,
p1metery=206,
p1meterenabled=true,
p2meterx=216,
p2metery=206,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return bit.band(rb(p1direction), 1)
end
function playerTwoFacingLeft()
return bit.band(rb(p2direction), 1)
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1health+3, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2health+3, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local function stunMeter()
P2StunMeter = rb(0x102365)
gui.text(147,67, "Stun: " ..P2StunMeter, "green")
end
function infiniteTime()
ww(0x106B11, 0x3CFF)
end
function Run()
stunMeter()
infiniteTime()
end
]==]
UT.sources["samsho"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with samsho:"
print "Issues with reading/writing health and meter"
end
local direction = 0x100a84
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=180,
combotexty=42,
comboenabled=true,
p1healthx=22,
p1healthy=16,
p1healthenabled=true,
p2healthx=288,
p2healthy=16,
p2healthenabled=true,
p1meterx=22,
p1metery=223,
p1meterenabled=true,
p2meterx=288,
p2metery=223,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(direction)==1
end
function playerTwoFacingLeft()
return rb(direction)==0
end
function _playerOneInHitstun()
end
function _playerTwoInHitstun()
end
function _readPlayerOneHealth()
end
function _writePlayerOneHealth(health)
end
function _readPlayerTwoHealth()
return rb(p2health)
end
function _writePlayerTwoHealth(health)
wb(p2health, health)
end
function _readPlayerOneMeter()
return rb(p1meter)
end
function _writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function _readPlayerTwoMeter()
return rb(p2meter)
end
function _writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x100A09, 0x63)
end
function Run()
infiniteTime()
end
]==]
UT.sources["samsho2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x80
p2maxhealth = 0x80
p1maxmeter = 0x20
p2maxmeter = 0x20
local p1health = rdw(0x100a46) + 0xbb
local p2health = rdw(0x100a4a) + 0xbb
local p1meter = rdw(0x100a46) + 0xf0
local p2meter = rdw(0x100a4a) + 0xf0
local p1direction = 0x10105c
local p2direction = 0x100ad0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
combogui = {
combotextx=180,
combotexty=42,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function _playerOneInHitstun()
end
function _playerTwoInHitstun()
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x100Ac6, 0x98)
end
function Run()
infiniteTime()
end
]==]
UT.sources["samsho3"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x80
p2maxhealth = 0x80
p1maxmeter = 0x40
p2maxmeter = 0x40
function gamemsg()
print "Known issues with samsho3:"
print "Inconsistent combo counter"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=134,
combotexty=56,
comboenabled=true,
p1healthx=9,
p1healthy=21,
p1healthenabled=true,
p2healthx=284,
p2healthy=21,
p2healthenabled=true,
p1meterx=113,
p1metery=208,
p1meterenabled=true,
p2meterx=188,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x1085db)==2
end
function playerTwoFacingLeft()
return rb(0x1085db)==0
end
function playerOneInHitstun()
return rb(0x1085c4)~=0
end
function playerTwoInHitstun()
return rb(0x10f295)~=0 or rb(0x1086c4)~=0
end
function readPlayerOneHealth()
return rb(0x108573)
end
function writePlayerOneHealth(health)
wb(0x108573, health)
end
function readPlayerTwoHealth()
return rb(0x108673)
end
function writePlayerTwoHealth(health)
wb(0x108673, health)
end
function readPlayerOneMeter()
return rb(0x10857c)
end
function writePlayerOneMeter(meter)
wb(0x10857c, meter)
end
function readPlayerTwoMeter()
return rb(0x10867c)
end
function writePlayerTwoMeter(meter)
wb(0x10867c, meter)
end
local infiniteTime = function()
wb(0x10849e, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["samsho4"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xFC
p2maxhealth = 0xFC
p1maxmeter = 0x40
p2maxmeter = 0x40
local p1health = 0x108443
local p2health = 0x108643
local p1meter = 0x10844C
local p2meter = 0x10864C
local p1combocounter = 0x10855e
local p2combocounter = 0x10875e
local p1direction = 0x10360f
local p2direction = 0x103a0f
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=147,
combotexty=55,
comboenabled=true,
p1healthx=18,
p1healthy=20,
p1healthenabled=true,
p2healthx=291,
p2healthy=20,
p2healthenabled=true,
p1meterx=106,
p1metery=209,
p1meterenabled=true,
p2meterx=207,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==2
end
function playerTwoFacingLeft()
return rb(p2direction)==2
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
ww(0x108368, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["samsho5"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x7D
p2maxhealth = 0x7D
p1maxmeter = 0x40
p2maxmeter = 0x40
local p1health = 0x108445
local p2health = 0x108655
local p1meter = 0x10844E
local p2meter = 0x10865E
local p1combocounter = 0x108560
local p2combocounter = 0x108770
local p1direction = 0x102b0f
local p2direction = 0x102f0f
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=138,
combotexty=55,
comboenabled=true,
p1healthx=9,
p1healthy=24,
p1healthenabled=true,
p2healthx=284,
p2healthy=24,
p2healthenabled=true,
p1meterx=98,
p1metery=210,
p1meterenabled=true,
p2meterx=203,
p2metery=210,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
local ptr = rdw(0x108332)
return rb(ptr+0xF)==2
end
function playerTwoFacingLeft()
local ptr = rdw(0x108336)
return rb(ptr+0xF)==2
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0x10836B, 0x60)
end
function Run()
infiniteTime()
end
]==]
UT.sources["samsho5sp"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x7D
p2maxhealth = 0x7D
p1maxmeter = 0x40
p2maxmeter = 0x40
function gamemsg()
print "Known issues with samsh5sp:"
print "gui does not show up"
print "no hitboxes currently"
print "only way to toggle p1 health is to edit code"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
p1healthx=9,
p1healthy=24,
p1healthenabled=true,
p2healthx=284,
p2healthy=24,
p2healthenabled=true,
p1meterx=98,
p1metery=210,
p1meterenabled=true,
p2meterx=199,
p2metery=210,
p2meterenabled=true,
},
}
function readPlayerOneHealth()
return rb(0x108445)
end
function writePlayerOneHealth(health)
wb(0x108445, health)
end
function readPlayerTwoHealth()
return rb(0x108655)
end
function writePlayerTwoHealth(health)
wb(0x108655, health)
end
function readPlayerOneMeter()
return rb(0x10844E)
end
function writePlayerOneMeter(meter)
wb(0x10844E, meter)
end
function readPlayerTwoMeter()
return rb(0x10865E)
end
function writePlayerTwoMeter(meter)
wb(0x10865E, meter)
end
function infiniteTime()
wb(0x10836B, 0x3C)
end
function longSwordGague()
wb(0x108554, 0x82)
wb(0x108764, 0x82)
end
function maxSwordGuageCharge()
wb(0x1085F8, 0x78)
wb(0x108808, 0x78)
end
function maxTimeSlow()
wb(0x1085FE, 0x7C)
wb(0x10880E, 0x7C)
end
function Run()
infiniteTime()
longSwordGague()
maxSwordGuageCharge()
maxTimeSlow()
end
]==]
UT.sources["sf"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x040B
p2maxhealth = 0x040B
function gamemsg()
print "Known issues with sf:"
print "Combos not tracked"
end
local p1health = 0xFF83E9
local p2health = 0xFF86E9
local p1direction = 0xFFE437
local p2direction = 0xFFEA37
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
p1healthx=34,
p1healthy=23,
p1healthenabled=true,
p2healthx=339,
p2healthy=23,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==4
end
function playerTwoFacingLeft()
return rb(p2direction)==4
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
local infiniteTime = function()
ww(0xFF9498,0x0909)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sf2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
function gamemsg()
print "Known issues with sf2:"
print "Combos not tracked"
print "Note sf2 has no meter"
end
local p1health = 0xFF83F1
local p1redhealth = 0xFF83F3
local p2health = 0xFF86F1
local p2redhealth = 0xFF86F3
local p1direction = 0xFF83D8
local p2direction = 0xFF86D8
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
p1healthx=34,
p1healthy=23,
p1healthenabled=true,
p2healthx=339,
p2healthy=23,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1redhealth, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2redhealth, health)
end
local infiniteTime = function()
ww(0xFF8ACE,0x9900)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sf2ce"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
function gamemsg()
print "Known issues with sf2ce:"
print "Combos not tracked"
print "Note sf2ce has no meter"
end
local p1health = 0xFF83E9
local p1redhealth = 0xFF83EB
local p2health = 0xFF86E9
local p2redhealth = 0xFF86EB
local p1direction = 0xFF83D0
local p2direction = 0xFF86D0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
p1healthx=34,
p1healthy=23,
p1healthenabled=true,
p2healthx=339,
p2healthy=23,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1redhealth, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2redhealth, health)
end
local infiniteTime = function()
ww(0xFF8ABE,0x9900)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sfa"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 144
p2maxmeter = 144
local p1health = 0xFF8441
local p1redhealth = 0xFF8443
local p2health = 0xFF8841
local p2redhealth = 0xFF8843
local p1meter = 0xFF84BF
local p2meter = 0xFF88BF
local p1direction = 0xff840b
local p2direction = 0xff880b
local p1combocounter = 0xFF8857
local p2combocounter = 0xFF8457
function gamemsg()
print "Known issues with sfa:"
print "Combos can be inconsistent"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=176,
combotexty=42,
comboenabled=true,
p1healthx=33,
p1healthy=20,
p1healthenabled=true,
p2healthx=340,
p2healthy=20,
p2healthenabled=true,
p1meterx=164,
p1metery=207,
p1meterenabled=true,
p2meterx=208,
p2metery=207,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1redhealth, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2redhealth, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
ww(0xFFAE09, 0x6300)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sfa2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 144
p2maxmeter = 144
local p1health = 0xFF8450
local p1redhealth = 0xff8452
local p2health = 0xFF8850
local p2redhealth = 0xFF8852
local p1meter = 0xFF849E
local p2meter = 0xFF889E
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=180,
combotexty=42,
comboenabled=true,
p1healthx=18,
p1healthy=18,
p1healthenabled=true,
p2healthx=355,
p2healthy=18,
p2healthenabled=true,
p1meterx=176,
p1metery=210,
p1meterenabled=true,
p2meterx=205,
p2metery=210,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0xff8931)==1
end
function playerTwoFacingLeft()
return rb(0xff8931)==0
end
function playerOneInHitstun()
return rb(0xff845e)~=0
end
function playerTwoInHitstun()
return rb(0xff885e)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
ww(p1redhealth, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
ww(p2redhealth, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
local infiniteTime = function()
wb(0xff8109, 99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sfiii"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xA0
p2maxhealth = 0xA0
p1maxmeter = rb(0x200D951)
p2maxmeter = rb(0x200D971)
local p1health = 0x200D22B
local p2health = 0x200D603
local p1meter = 0x200D953
local p2meter = 0x200D973
local p1direction = 0x200D196
local p2direction = 0x200D197
local p1combocounter = 0x200DA4D
local p2combocounter = 0x200D6CD
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=176,
combotexty=42,
comboenabled=true,
p1healthx=9,
p1healthy=16,
p1healthenabled=true,
p2healthx=364,
p2healthy=16,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==1
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
wb(0x200EB33, 0x64)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sfiii2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xA0
p2maxhealth = 0xA0
p1maxmeter = rb(0x200ED3D)
p2maxmeter = rb(0x200ED69)
local p1health = 0x200E5A3
local p2health = 0x200E9AF
local p1meter = 0x200ED3F
local p2meter = 0x200ED6B
local p1direction = 0x200E50E
local p2direction = 0x200E91A
local p1combocounter = 0x200EE45
local p2combocounter = 0x200EEED
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=175,
combotexty=42,
comboenabled=true,
p1healthx=10,
p1healthy=17,
p1healthenabled=true,
p2healthx=363,
p2healthy=17,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
wb(0x2010167, 0x64)
end
function Run()
infiniteTime()
end
]==]
UT.sources["sgemf"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with sgemf:"
print "Chain combos sometimes won't update the combo counter properly on whiffed attacks."
end
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 96
p2maxmeter = 96
local p1health = 0xFF8441
local p2health = 0xFF8841
local p1meter = 0xFF8595
local p2meter = 0xFF8995
local p1combocounter = 0xFF8944
local p2combocounter = 0xFF8544
local p1direction = 0xFF840b
local p2direction = 0xFF880b
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Punch"] = 5,
["Kick"] = 6,
["Special"] = 7,
["Coin"] = 8,
["Start"] = 9,
}
gamedefaultconfig = {
hud = {
combotextx=178,
combotexty=45,
comboenabled=true,
p1healthx=18,
p1healthy=23,
p1healthenabled=true,
p2healthx=355,
p2healthy=23,
p2healthenabled=true,
p1meterx=125,
p1metery=44,
p1meterenabled=true,
p2meterx=257,
p2metery=44,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
return wb(p1health,health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0xFF8188,0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["slammast"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xFF
p2maxhealth = 0xFF
local p1health = 0xFF9157
local p2health = 0xFF9357
function gamemsg()
print "Known issues with slammast:"
print "Doesn't track combos"
print "Note that slammast doesn't have meter"
print "Only supports P1 and P2"
end
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Attack"] = 5,
["Jump"] = 6,
["Pin"] = 7,
["Coin"] = 8,
["Start"] = 9,
}
gamedefaultconfig = {
hud = {
p1healthx=50,
p1healthy=33,
p1healthenabled=true,
p2healthx=356,
p2healthy=33,
p2healthenabled=true,
},
}
function playerOneFacingLeft()
return rb(0xFF90FB)==0
end
function playerTwoFacingLeft()
return rb(0xFF92FB)==0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
local infiniteTime = function()
ww(0xFFA0C8, 0x0300)
ww(0xFFA0CA, 0)
end
function Run()
infiniteTime()
end
]==]
UT.sources["svc"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with svc:"
print "Doesn't activate MAX properly"
end
p1maxhealth = 0xE1
p2maxhealth = 0xE1
p1maxmeter = 0x6400 - 0x80
p2maxmeter = 0x6400 - 0x80
local p1health = 0x10A239
local p2health = 0x10A4B9
local p1meter = 0x10A1E8
local p2meter = 0x10A468
local p1direction = 0x10A131
local p2direction = 0x10A3B1
local p1combocounter = 0x10A530
local p2combocounter = 0x10A2B0
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=137,
combotexty=49,
comboenabled=true,
p1healthx=17,
p1healthy=23,
p1healthenabled=true,
p2healthx=276,
p2healthy=23,
p2healthenabled=true,
p1meterx=111,
p1metery=208,
p1meterenabled=true,
p2meterx=173,
p2metery=208,
p2meterenabled=true,
},
inputs = {
simpleinputxoffset = {42,205},
simpleinputyoffset = {190,190},
}
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)+1
end
function writePlayerOneHealth(health)
wb(p1health, health-1)
end
function readPlayerTwoHealth()
return rb(p2health)+1
end
function writePlayerTwoHealth(health)
wb(p2health, health-1)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
end
function infiniteTime()
ww(0x10AC14, 0x6000)
end
function Run()
infiniteTime()
end
]==]
UT.sources["tkdensho"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x7F
p2maxhealth = 0x7F
p1maxmeter = 0x0B
p2maxmeter = 0x0B
local p1health = 0x2004A4
local p2health = 0x200534
local p1combocounter = 0x2004A0
local p2combocounter = 0x200530
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button 1"] = 5,
["Button 2"] = 6,
["Button 3"] = 7,
["Button 4"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=145,
combotexty=39,
comboenabled=true,
p1healthx=18,
p1healthy=20,
p1healthenabled=true,
p2healthx=290,
p2healthy=20,
p2healthenabled=true,
p1meterx=100,
p1metery=208,
p1meterenabled=true,
p2meterx=214,
p2metery=208,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x20065E) == 0xFF
end
function playerTwoFacingLeft()
return rb(0x2004F4) == 0
end
function playerOneInHitstun()
return rb(p2combocounter) ~= 0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth(health)
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(0x2004C8)
end
function writePlayerOneMeter(meter)
wb(0x2004C8, meter)
end
function readPlayerTwoMeter()
return rb(0x200558)
end
function writePlayerTwoMeter(meter)
wb(0x200558, meter)
end
function infiniteTime()
wb(0x201C50,0x63)
end
function maxCredits()
wb(0x201C3F, 0x09)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["umk3"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "Known issues with UMK3:"
print "Coin button also triggers maintenance menu."
print "Health doesn't refill on throws."
print "Combo counter doesn't increment correctly."
end
local function getAddressFromPointer(pointeraddress)
local bytetable = memory.readbyterange(pointeraddress, 32)
local targetaddress = ""
for i=32,1,-8 do
targetaddress = targetaddress .. string.format("%02x", bytetable[i])
end
return tonumber(targetaddress, 16)
end
p1maxhealth = 0xa6
p2maxhealth = 0xa6
local p1health = 0x01060a60
local p2health = 0x01061610
local p1direction = 0x01030541
local p2direction = 0x0105fa01
local p1combocounter = getAddressFromPointer(0x010615c0) + 0x390
local p2combocounter = getAddressFromPointer(0x01060a10) + 0x390
local p1inhitstun = false
local p2inhitstun = false
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["High Punch"] = 5,
["Block"] = 6,
["High Kick"] = 7,
["Low Punch"] = 8,
["Low Kick"] = 9,
["Run"] = 10,
["Coin"] = 11,
["Start"] = 12,
["Select"] = 13,
}
gamedefaultconfig = {
hud = {
combotextx=185,
combotexty=38,
comboenabled=false,
p1healthx=8,
p1healthy=27,
p1healthenabled=true,
p2healthx=381,
p2healthy=27,
p2healthenabled=true
},
}
function playerOneFacingLeft()
return rb(p1direction)==0x82
end
function playerTwoFacingLeft()
return rb(p2direction)==0x90
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function infiniteTime()
wdw(0xff80dc60, 0x0300c0d7)
end
function Run()
infiniteTime()
end
]==]
UT.sources["vamp"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
function gamemsg()
print "It's recommended to run characters health refill option on 'Health Always Full'"
end
p1maxhealth = 0x90
p2maxhealth = 0x90
p1maxmeter = 0x50
p2maxmeter = 0x50
local p1health = 0xFF83CB
local p2health = 0xFF87CB
local p1meter = 0xFF855F
local p2meter = 0xFF895F
local p1direction = 0xFF830C
local p2direction = 0xFF830D
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=178,
combotexty=49,
comboenabled=true,
p1healthx=30,
p1healthy=20,
p1healthenabled=true,
p2healthx=342,
p2healthy=20,
p2healthenabled=true,
p1meterx=136,
p1metery=212,
p1meterenabled=true,
p2meterx=241,
p2metery=212,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction) == 0
end
function playerTwoFacingLeft()
return rb(p2direction) == 0
end
function playerOneInHitstun()
return rb(0xFF84FD)~=0
end
function playerTwoInHitstun()
return rb(0xFF88FD)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
wb(0xFF9409, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["vhunt2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x120
p2maxhealth = 0x120
p1maxmeter = 0x63
p2maxmeter = 0x63
local p1health = 0xFF8450
local p2health = 0xFF8850
local p1whitehealth = 0xFF8452
local p2whitehealth = 0xFF8852
local p1meter = 0xFF8509
local p2meter = 0xFF8909
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=176,
combotexty=42,
comboenabled=true,
p1healthx=148,
p1healthy=16,
p1healthenabled=true,
p2healthx=225,
p2healthy=16,
p2healthenabled=true,
p1meterx=8,
p1metery=206,
p1meterenabled=true,
p2meterx=209,
p2metery=206,
p2meterenabled=true,
},
p2 = {
instantrefillhealth = false,
instantrefillmeter = true,
},
}
function playerOneFacingLeft()
return rb(0xFF840B)==0
end
function playerTwoFacingLeft()
return rb(0xFF880B)==0
end
function playerOneInHitstun()
return rb(0xFF8544)~=0
end
function playerTwoInHitstun()
return rb(0xFF8944)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
ww(p1whitehealth, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
ww(p2whitehealth, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
local infiniteTime = function()
ww(0xFF8109, 0x6300)
end
function Run()
infiniteTime()
end
]==]
UT.sources["vhuntjr2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 144
p2maxhealth = 144
p1maxmeter = 0x70
p2maxmeter = 0x70
local p1health = 0xFF83CB
local p2health = 0xFF88CB
local p1meter = 0xFF855F
local p2meter = 0xFF8A5F
local p1stocks = 0xFF8565
local p2stocks = 0xFF8A65
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
p1healthx=34,
p1healthy=24,
p1healthenabled=true,
p2healthx=339,
p2healthy=24,
p2healthenabled=true,
p1meterx=164,
p1metery=34,
p1meterenabled=true,
p2meterx=208,
p2metery=34,
p2meterenabled=true,
},
}
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
ww(p1meter, meter)
wb(p1stocks, 0x0A)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
ww(p2meter, meter)
wb(p2stocks, 0x0A)
end
local infiniteTime = function()
wb(0xFF8E09, 0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["vsav"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x0120
p2maxhealth = 0x0120
p1maxmeter = 0x90
p2maxmeter = 0x90
local p1health = 0xFF8450
local p2health = 0xFF8850
local p1redhealth = 0xFF8452
local p2redhealth = 0xFF8852
local p1meter = 0xFF850A
local p2meter = 0xFF890A
local p1stocks = 0xFF8509
local p2stocks = 0xFF8909
local p1direction = 0xFF8520
local p2direction = 0xFF8920
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
p1 = {
instantrefillhealth = false,
instantrefillmeter = true,
},
p2 = {
instantrefillhealth = false,
instantrefillmeter = true,
},
hud = {
combotextx=178,
combotexty=52,
comboenabled=true,
p1healthx=18,
p1healthy=16,
p1healthenabled=true,
p2healthx=355,
p2healthy=16,
p2healthenabled=true,
p1meterx=164,
p1metery=206,
p1meterenabled=true,
p2meterx=209,
p2metery=206,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction) == 1
end
function playerTwoFacingLeft()
return rb(p2direction) == 1
end
function playerOneInHitstun()
return ((rb(0xFF8544)~=0) or (rb(0xFF8545)~=0))
end
function playerTwoInHitstun()
return ((rb(0xFF8944)~=0) or (rb(0xFF8945)~=0))
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
ww(p1redhealth, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
ww(p2redhealth, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1stocks, 0x63)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2stocks, 0x63)
end
local infiniteTime = function()
wb(0xFF8109, 0x63)
end
function Run()
infiniteTime()
end
]==]
UT.sources["vsav2"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x0120
p2maxhealth = 0x0120
p1maxmeter = 0x99
p2maxmeter = 0x99
local p1health = 0xFF8450
local p2health = 0xFF8850
local p1redhealth = 0xFF8452
local p2redhealth = 0xFF8852
local p1meter = 0xFF850A
local p2meter = 0xFF890A
local p1stocks = 0xFF8509
local p2stocks = 0xFF8909
local p1direction = 0xFF8920
local p2direction = 0xFF8520
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
p1 = {
instantrefillhealth = false,
instantrefillmeter = true,
},
p2 = {
instantrefillhealth = false,
instantrefillmeter = true,
},
hud = {
combotextx=178,
combotexty=52,
comboenabled=true,
p1healthx=18,
p1healthy=16,
p1healthenabled=true,
p2healthx=355,
p2healthy=16,
p2healthenabled=true,
p1meterx=164,
p1metery=206,
p1meterenabled=true,
p2meterx=209,
p2metery=206,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction) == 0
end
function playerTwoFacingLeft()
return rb(p2direction) == 0
end
function playerOneInHitstun()
return rb(0xFF8544)~=0
end
function playerTwoInHitstun()
return rb(0xFF8944)~=0
end
function readPlayerOneHealth()
return rw(p1health)
end
function writePlayerOneHealth(health)
ww(p1health, health)
ww(p1redhealth, health)
end
function readPlayerTwoHealth()
return rw(p2health)
end
function writePlayerTwoHealth(health)
ww(p2health, health)
ww(p2redhealth, health)
end
function readPlayerOneMeter()
return rw(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1stocks, meter)
end
function readPlayerTwoMeter()
return rw(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2stocks, meter)
end
local infiniteTime = function()
ww(0xFF8109, 0x6300)
end
function Run()
infiniteTime()
end
]==]
UT.sources["wakuwak7"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xff
p2maxhealth = 0xff
p1maxmeter = 0xff
p2maxmeter = 0xff
local p1health1 = 0x10014A
local p1health2 = 0x10014B
local p2health1 = 0x10028A
local p2health2 = 0x10028B
local p1meter1 = 0x100156
local p1meter2 = 0x100517
local p2meter1 = 0x100296
local p2meter2 = 0x100297
local p1stocks = 0x100159
local p2stocks = 0x100299
local p1combocounter = 0x10679d
local p2combocounter = 0x1067c7
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=140,
combotexty=42,
comboenabled=true,
p1healthx=27,
p1healthy=21,
p1healthenabled=true,
p2healthx=266,
p2healthy=21,
p2healthenabled=true,
p1meterx=121,
p1metery=200,
p1meterenabled=true,
p2meterx=180,
p2metery=200,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0x100119) == 0
end
function playerTwoFacingLeft()
return rb(0x100259) == 0
end
function playerOneInHitstun()
return rb(p2combocounter) ~= 0
end
function playerTwoInHitstun()
return rb(p1combocounter) ~= 0
end
function readPlayerOneHealth(health)
return rb(p1health1)
end
function writePlayerOneHealth(health)
wb(p1health1, health)
wb(p1health2, health)
end
function readPlayerTwoHealth()
return rb(p2health1)
end
function writePlayerTwoHealth(health)
wb(p2health1, health)
wb(p2health2, health)
end
function readPlayerOneMeter()
return rb(0x1004BE)
end
function writePlayerOneMeter(meter)
wb(p1meter1, meter)
wb(p1meter2, meter)
wb(p1stocks, 0x07)
end
function readPlayerTwoMeter()
return rb(0x1005BE)
end
function writePlayerTwoMeter(meter)
wb(p2meter1, meter)
wb(p2meter2, meter)
wb(p2stocks, 0x07)
end
function infiniteTime()
wb(0x100B02,0x9B)
end
function maxCredits()
wb(0xD00034, 0x99)
end
function Run()
infiniteTime()
maxCredits()
end
]==]
UT.sources["whp"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0xc0
p2maxhealth = 0xc0
p1maxmeter = 0xdf
p2maxmeter = 0xdf
local p1health = 0x10600C
local p2health = 0x10610c
local p1meter = 0x106a17
local p2meter = 0x106B17
local p1direction = 0x108295
local p1combocounter = 0x106146
local p2combocounter = 0x106046
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"coin",
"start",
"select",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Button A"] = 5,
["Button B"] = 6,
["Button C"] = 7,
["Button D"] = 8,
["Coin"] = 9,
["Start"] = 10,
["Select"] = 11,
}
gamedefaultconfig = {
hud = {
combotextx=144,
combotexty=35,
comboenabled=true,
p1healthx=50,
p1healthy=17,
p1healthenabled=true,
p2healthx=259,
p2healthy=17,
p2healthenabled=true,
p1meterx=96,
p1metery=207,
p1meterenabled=true,
p2meterx=197,
p2metery=207,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==1
end
function playerTwoFacingLeft()
return rb(p1direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1health+1, health)
wb(0x10607d, 0)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2health+1, health)
wb(0x10617d, 0)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
wb(p1meter+2, meter)
end
function readPlayerTwoMeter()
return rb(p2meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
wb(p2meter+2, meter)
end
function infiniteTime()
wb(0x10C109, 0x9a)
end
function Run()
infiniteTime()
end
]==]
UT.sources["xmcota"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
p1maxmeter = 0x8E
p2maxmeter = 0x8E
local p1health = 0xFF4191
local p2health = 0xFF4591
local p1meter = 0xFF4195
local p2meter = 0xFF4595
local p1combocounter = 0xFF4110
local p2combocounter = 0xFF4510
local p1direction = 0xFF404d
local p2direction = 0xFF444d
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=180,
combotexty=42,
comboenabled=true,
p1healthx=34,
p1healthy=20,
p1healthenabled=true,
p2healthx=338,
p2healthy=20,
p2healthenabled=true,
p1meterx=170,
p1metery=30,
p1meterenabled=true,
p2meterx=211,
p2metery=30,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(0xFF404d)==0
end
function playerTwoFacingLeft()
return rb(0xFF444d)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
return rb(p1health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
end
function readPlayerTwoHealth()
return rb(p2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
end
function readPlayerOneMeter()
return rb(p1meter, meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
end
function readPlayerTwoMeter()
return rb(p2meter, meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
end
function infiniteTime()
wb(0xFF4808,0x99)
end
function Run()
infiniteTime()
end
]==]
UT.sources["xmvsf"] = [==[
assert(rb,"Run fbneo-training-mode.lua")
p1maxhealth = 0x90
p2maxhealth = 0x90
p1maxmeter = 3
p2maxmeter = 3
local p1health = 0xff4211
local p1redhealth = 0xff421b
local p1char2health = 0xff4a11
local p1char2redhealth = 0xff4a1b
local p1charactive = 0xff4220
local p2health = 0xff4611
local p2redhealth = 0xff461b
local p2char2health = 0xff4e11
local p2char2redhealth = 0xff4e1b
local p2charactive = 0xff4620
local p1meter = 0xff4214
local p2meter = 0xff4614
local p1combocounter = 0xff4110
local p2combocounter = 0xff4510
local p1direction = 0xff404b
local p2direction = 0xff444b
translationtable = {
"left",
"right",
"up",
"down",
"button1",
"button2",
"button3",
"button4",
"button5",
"button6",
"coin",
"start",
["Left"] = 1,
["Right"] = 2,
["Up"] = 3,
["Down"] = 4,
["Weak Punch"] = 5,
["Medium Punch"] = 6,
["Strong Punch"] = 7,
["Weak Kick"] = 8,
["Medium Kick"] = 9,
["Strong Kick"] = 10,
["Coin"] = 11,
["Start"] = 12,
}
gamedefaultconfig = {
hud = {
combotextx=178,
combotexty=53,
comboenabled=true,
p1healthx=157,
p1healthy=20,
p1healthenabled=true,
p2healthx=215,
p2healthy=20,
p2healthenabled=true,
p1meterx=179,
p1metery=209,
p1meterenabled=true,
p2meterx=202,
p2metery=209,
p2meterenabled=true,
},
}
function playerOneFacingLeft()
return rb(p1direction)==0
end
function playerTwoFacingLeft()
return rb(p2direction)==0
end
function playerOneInHitstun()
return rb(p2combocounter)~=0
end
function playerTwoInHitstun()
return rb(p1combocounter)~=0
end
function readPlayerOneHealth()
if (rb(p1charactive)==0) then
return rb(p1health)
end
return rb(p1char2health)
end
function writePlayerOneHealth(health)
wb(p1health, health)
wb(p1redhealth, health)
wb(p1char2health, health)
wb(p1char2redhealth, health)
end
function readPlayerTwoHealth()
if (rb(p2charactive)==0) then
return rb(p2health)
end
return rb(p2char2health)
end
function writePlayerTwoHealth(health)
wb(p2health, health)
wb(p2redhealth, health)
wb(p2char2health, health)
wb(p2char2redhealth, health)
end
function readPlayerOneMeter()
return rb(p1meter)
end
function writePlayerOneMeter(meter)
wb(p1meter, meter)
ww(0xff4212, 0x90)
end
function readPlayerTwoMeter()
return rb(p2meter, meter)
end
function writePlayerTwoMeter(meter)
wb(p2meter, meter)
ww(0xff4612, 0x90)
end
function infiniteTime()
wb(0xff5008,0x99)
end
function Run()
infiniteTime()
end
]==]

local training = (function()
  local rom = rom_name():lower()
  local is_replay = false
  pcall(function() is_replay = (emu.isreplay and emu.isreplay()) and true or false end)

  ---------------- which game is this?
  local function find_game_key(name)
    if not name or name == "" then return nil end
    for key, g in pairs(UT.games) do
      for _, r in ipairs(g.roms) do
        if r == name then return key end
      end
    end
    return nil
  end
  local game_key = find_game_key(UT.aliases[rom] or rom)
  if not game_key then
    local parent = ""
    pcall(function() parent = tostring(emu.parentname and emu.parentname() or ""):lower() end)
    game_key = find_game_key(UT.aliases[parent] or parent)
  end
  local guessed_from_family = false
  if not game_key then
    for _, pair in ipairs(UT.prefix_aliases) do
      if rom:sub(1, #pair[1]) == pair[1] then game_key, guessed_from_family = pair[2], true break end
    end
  end

  ---------------- sandbox: the archive's files expect the main script's globals (rb, wb, ...)
  local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[deep_copy(k)] = deep_copy(v) end
    return copy
  end
  local function build_env()
    local env = setmetatable({}, { __index = _G })
    local counter = { n = 0, on = true }
    local function counted(fn)
      return function(...)
        if counter.on then counter.n = counter.n + 1 end
        return fn(...)
      end
    end
    env.rb, env.rw, env.rdw = counted(memory.readbyte), counted(memory.readword), counted(memory.readdword)
    env.rws = memory.readwordsigned
    if is_replay then
      env.wb, env.ww, env.wdw = function() end, function() end, function() end   -- never write while watching a replay
    else
      env.wb, env.ww, env.wdw = memory.writebyte, memory.writeword, memory.writedword
    end
    env.REPLAY = is_replay
    env.hitboxes = { enabled = false, prev = false }
    env.copytable = _G.copytable or deep_copy
    env.print = function() end   -- the archive files print notes while loading
    env.fexists = function() return false end
    env.dofile = function() end
    env.require = function() return true end
    -- the game files are only used for their read / write functions: whatever they register on their own
    -- (HUD drawing, hotkeys, frame hooks) is ignored so it cannot change this script's behavior
    local function ignore() end
    env.gui = setmetatable({ register = ignore }, { __index = gui })
    env.input = setmetatable({ registerhotkey = ignore }, { __index = input })
    env.emu = setmetatable({ registerbefore = ignore, registerafter = ignore, registerstart = ignore, registerexit = ignore }, { __index = emu })
    return env, counter
  end

  ---------------- the game's profile: built-in, or the archive's own file embedded in this script
  local profile = nil
  local profile_error = nil
  local function load_profile()
    if not game_key then
      profile_error = "rom '" .. rom .. "' is not in the training-mode game list"
      return
    end
    local env, counter = build_env()
    if UT.builtin[game_key] then
      local ok, refresh = pcall(UT.builtin[game_key], env)
      if not ok or type(refresh) ~= "function" then profile_error = "built-in profile failed: " .. tostring(refresh) return end
      profile = { key = game_key, source = "built-in", env = env, chunk = refresh, dynamic = true }
      return
    end
    local source = UT.sources[game_key]
    if not source then profile_error = "no embedded file for " .. game_key return end
    local chunk, err = loadstring(source, "=" .. game_key)
    if not chunk then profile_error = tostring(err) return end
    setfenv(chunk, env)
    local ok, run_err = pcall(chunk)
    counter.on = false
    if not ok then profile_error = tostring(run_err) return end
    if UT.overrides[game_key] then pcall(UT.overrides[game_key], env) end
    profile = {
      key = game_key, source = "embedded", env = env, chunk = chunk,
      -- the file read memory while loading (the max meter of some games depends on the character, for
      -- example): run it again from time to time so those values stay current
      dynamic = counter.n > 0 and #source <= UT.max_reload_bytes,
    }
  end
  pcall(load_profile)
  if profile == nil and profile_error == nil then profile_error = "profile failed to load" end

  local function pfn(name)
    local f = profile and profile.env[name]
    if type(f) == "function" then return f end
    return nil
  end
  local function pnum(name)
    local v = profile and profile.env[name]
    if type(v) == "number" then return v end
    return nil
  end
  local function call(name, ...)
    local f = pfn(name)
    if not f then return nil end
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
  end
  local HP = { { "readPlayerOneHealth", "writePlayerOneHealth", "p1maxhealth" }, { "readPlayerTwoHealth", "writePlayerTwoHealth", "p2maxhealth" } }
  local METER = { { "readPlayerOneMeter", "writePlayerOneMeter", "p1maxmeter" }, { "readPlayerTwoMeter", "writePlayerTwoMeter", "p2maxmeter" } }
  local function has_pair(def) return pfn(def[1]) ~= nil and pfn(def[2]) ~= nil and pnum(def[3]) ~= nil end
  local function has_hp(p) return has_pair(HP[p]) end
  local function has_meter(p) return has_pair(METER[p]) end
  local function has_hp_both() return has_hp(1) and has_hp(2) end

  -- infinite time = the game file's Run(), but only when it is short (long ones also run the archive's
  -- own reversal / auto-block experiments, which are not wanted here)
  local function run_is_simple()
    local f = pfn("Run")
    if not f or not (debug and debug.getinfo) then return false end
    local ok, info = pcall(debug.getinfo, f, "S")
    if not ok or type(info) ~= "table" or not info.linedefined or not info.lastlinedefined then return false end
    return (info.lastlinedefined - info.linedefined) <= UT.run_max_lines
  end
  local run_ok = run_is_simple()

  local settings = {
    p1_infinite_hp = false, p2_infinite_hp = false,
    p1_infinite_meter = false, p2_infinite_meter = false,
    infinite_time = false,
    damage_counter = true, input_history = true,
  }
  local history, last_input = {}, nil
  local prev_health = { nil, nil }
  local last_damage_frame = { -100000, -100000 }
  local combo_damage = { 0, 0 }
  local match_was_active = false
  local HISTORY_ROWS, COMBO_RESET_FRAMES = 10, 45
  local function bool_label(v) return v and "ON" or "OFF" end
  local function match_active()
    local addr = UT.match_state[game_key or ""]
    if not addr then return true end   -- no match-state word known: always treat as active
    local ok, active = pcall(function()
      return memory.readdword(addr) > 0x00010000 and memory.readword(addr) ~= 0x0009
    end)
    return ok and active or false
  end
  local function reset_damage()
    for i = 1, 2 do combo_damage[i], last_damage_frame[i] = 0, -100000 end
    log("training damage stats reset")
    flash()
  end
  local function add_damage(victim, amount, before, after)
    if amount <= 0 then return end
    log(string.format("damage: P%d lost %d (health %s -> %s) frame %d", victim, amount, tostring(before), tostring(after), frame_count))
    local attacker = victim == 1 and 2 or 1
    if frame_count - last_damage_frame[attacker] > COMBO_RESET_FRAMES then combo_damage[attacker] = 0 end
    combo_damage[attacker] = combo_damage[attacker] + amount
    last_damage_frame[attacker] = frame_count
  end
  -- games with 16-bit health bars (thousands of points) show the damage as a percentage instead
  local function damage_scale()
    local m = pnum("p1maxhealth")
    if m and m > 999 then return 100 / m, "%" end
    return 1, ""
  end
  local function why_na()
    if profile then return "this game has no support for that in the training-mode archive" end
    return "no training-mode profile: " .. tostring(profile_error)
  end
  local function option_value(key)
    local who, kind = key:match("^p([12])_infinite_(%a+)$")
    if who then
      local p = tonumber(who)
      local available = (kind == "hp" and has_hp(p)) or (kind == "meter" and has_meter(p))
      return available and bool_label(settings[key]) or "N/A"
    end
    if key == "infinite_time" then return run_ok and bool_label(settings[key]) or "N/A" end
    if key == "damage_counter" then return has_hp_both() and bool_label(settings[key]) or "N/A" end
    return bool_label(settings[key])
  end
  local function toggle_option(key)
    if option_value(key) == "N/A" then
      say("Not available here: " .. why_na())
      return
    end
    settings[key] = not settings[key]
    log(key, bool_label(settings[key]))
    flash()
  end
  -- Input history: one row per change of direction / button combination. Every row shows how many frames that exact
  -- combination (directions + buttons) was held. Letting go of everything adds no row and counts nothing.
  local function capture_inputs()
    if not settings.input_history or menu_open then return end
    local up, down = pad_now["P1 Up"], pad_now["P1 Down"]
    local left, right = pad_now["P1 Left"], pad_now["P1 Right"]
    local parts = {}
    -- one arrow for the direction (a diagonal when two are held); characters 1-8 are the arrow glyphs of the font
    if up and left and not down and not right then parts[1] = "\5"
    elseif up and right and not down and not left then parts[1] = "\6"
    elseif down and left and not up and not right then parts[1] = "\7"
    elseif down and right and not up and not left then parts[1] = "\8"
    else
      if up then parts[#parts + 1] = "\1" end
      if down then parts[#parts + 1] = "\2" end
      if left then parts[#parts + 1] = "\3" end
      if right then parts[#parts + 1] = "\4" end
    end
    local arrows = table.concat(parts)
    parts = {}
    if arrows ~= "" then parts[1] = arrows end
    for _, logical in ipairs({ "LP", "MP", "HP", "LK", "MK", "HK" }) do
      local physical = game_button(logical)
      if physical and pad_now["P1 " .. physical] then parts[#parts + 1] = logical end
    end
    local signature = #parts > 0 and table.concat(parts, " ") or "NEUTRAL"
    if signature ~= last_input then
      if signature ~= "NEUTRAL" then
        table.insert(history, 1, { text = signature, frames = 0 })
        while #history > HISTORY_ROWS do table.remove(history) end
      end
      last_input = signature
    end
    if history[1] and signature == history[1].text then history[1].frames = history[1].frames + 1 end
  end
  local refill_last, refill_drop = {}, {}
  local function refill(p, def, delayed_ok)
    -- write only when the value dropped, so games whose write function has side effects are not hammered
    local maximum = pnum(def[3])
    if not maximum or maximum <= 0 then return end
    local now = call(def[1])
    if type(now) ~= "number" then return end
    if delayed_ok and UT.delayed_refill[game_key or ""] then
      local key = def[1]
      if refill_last[key] and now < refill_last[key] then refill_drop[key] = frame_count end
      refill_last[key] = now
      local recently_hit = frame_count - (refill_drop[key] or -100000) < UT.refill_delay
      if recently_hit and now > maximum * UT.refill_floor then return end
      if now < maximum then call(def[2], maximum) refill_last[key] = maximum end
      return
    end
    if now < maximum then call(def[2], maximum) end
  end
  local function after_frame()
    if is_replay or not profile then return end
    if profile.dynamic and frame_count % 30 == 0 then pcall(profile.chunk) end
    local any_infinite = settings.p1_infinite_hp or settings.p2_infinite_hp or settings.p1_infinite_meter or settings.p2_infinite_meter
    if run_ok and (settings.infinite_time or (any_infinite and UT.needs_run[game_key or ""])) then call("Run") end
    if has_hp_both() then
      local active = match_active()
      if not active then
        prev_health[1], prev_health[2] = nil, nil
        match_was_active = false
      else
        local hp = { call(HP[1][1]), call(HP[2][1]) }
        if type(hp[1]) == "number" and type(hp[2]) == "number" then
          if not match_was_active then
            reset_damage()
            match_was_active = true
          else
            for p = 1, 2 do
              if prev_health[p] ~= nil then
                local lost = prev_health[p] - hp[p]
                local maximum = pnum(HP[p][3]) or 0
                if lost < 0 and -lost > maximum * 0.25 then reset_damage()           -- bar refilled: new round
                elseif lost > 0 and lost <= maximum then add_damage(p, lost, prev_health[p], hp[p]) end   -- ignore garbage frames
              end
            end
          end
          -- the damage counter reads the loss before the refill below, so it keeps working with infinite HP.
          -- After a refill the health is READ BACK instead of assumed to be the maximum: some games store max - 1,
          -- and in the games with a delayed refill the bar is not refilled yet; assuming the maximum would count
          -- phantom damage on the following frames.
          prev_health[1], prev_health[2] = hp[1], hp[2]
          for p = 1, 2 do
            if settings["p" .. p .. "_infinite_hp"] then
              refill(p, HP[p], true)
              prev_health[p] = call(HP[p][1])
            end
          end
        end
      end
    else
      for p = 1, 2 do
        if settings["p" .. p .. "_infinite_hp"] and has_hp(p) then refill(p, HP[p], true) end
      end
    end
    for p = 1, 2 do
      if settings["p" .. p .. "_infinite_meter"] and has_meter(p) then refill(p, METER[p]) end
    end
  end
  local menu = {
    { label = "Infinite HP P1", get = function() return option_value("p1_infinite_hp") end, change = function() toggle_option("p1_infinite_hp") end },
    { label = "Infinite HP P2", get = function() return option_value("p2_infinite_hp") end, change = function() toggle_option("p2_infinite_hp") end },
    { label = "Infinite Meter P1", get = function() return option_value("p1_infinite_meter") end, change = function() toggle_option("p1_infinite_meter") end },
    { label = "Infinite Meter P2", get = function() return option_value("p2_infinite_meter") end, change = function() toggle_option("p2_infinite_meter") end },
    { label = "Infinite Time", get = function() return option_value("infinite_time") end, change = function() toggle_option("infinite_time") end },
    { label = "Damage Counter", get = function() return option_value("damage_counter") end, change = function() toggle_option("damage_counter") end },
    { label = "Input History", get = function() return option_value("input_history") end, change = function() toggle_option("input_history") end },
    { label = "Reset Damage", get = function() return "CLEAR" end, act = function() reset_damage() end },
    { label = "Back", get = function() return "" end, act = function() return "back" end },
  }

  ---------------- side from the game's own "facing left" code (used when no X addresses are known)
  local function has_facing() return pfn("playerOneFacingLeft") ~= nil end
  local function p1_on_left()
    local f1 = call("playerOneFacingLeft")
    if f1 == nil then return nil end
    return not f1   -- P1 faces left = P2 is on its left = P1 stands on the right
  end

  local function status_lines()
    local lines = {}
    if profile then
      lines[#lines + 1] = "profile: " .. profile.key .. " (" .. profile.source .. ")"
      lines[#lines + 1] = "HP P1/P2: " .. option_value("p1_infinite_hp") .. "/" .. option_value("p2_infinite_hp")
        .. "  meter P1/P2: " .. option_value("p1_infinite_meter") .. "/" .. option_value("p2_infinite_meter")
        .. "  time: " .. option_value("infinite_time") .. "  facing: " .. (has_facing() and "yes" or "no")
    else
      lines[#lines + 1] = "no profile: " .. tostring(profile_error)
    end
    return lines
  end

  return {
    supported_rom = true,        -- the tools are always shown; each row says N/A if this game cannot do it
    game_key = game_key, has_profile = function() return profile ~= nil end,
    status_lines = status_lines, has_facing = has_facing, p1_on_left = p1_on_left,
    short_status = function()
      if profile then
        return "Training tools: " .. profile.key .. (guessed_from_family and (" (guessed from rom " .. rom .. ")") or "")
      end
      return "Training tools: NO profile for rom " .. rom
    end,
    settings = settings, history = history,
    history_rows = HISTORY_ROWS, menu = menu, index = 1,
    option_value = option_value, toggle_option = toggle_option, reset_damage = reset_damage,
    capture_inputs = capture_inputs, after_frame = after_frame,
    damage_data = function()
      local scale = damage_scale()
      return { combo_damage[1] * scale, combo_damage[2] * scale }
    end,
    damage_unit = function() local _, unit = damage_scale() return unit end,
    profile_env = function() return profile and profile.env or nil end,   -- diagnostic: the loaded game file's environment
  }
end)()

---------------------------------------------------------------- side detection
-- (SIDE is created near the top of the file; p1_left: true/false, nil = unknown)
SIDE.cfg = SIDE_SETTINGS.addresses
if not SIDE.cfg then
  local rn = ""
  pcall(function() rn = emu.romname() or "" end)
  for prefix, cfg in pairs(SIDE_SETTINGS.games) do
    if rn:sub(1, #prefix) == prefix then SIDE.cfg = cfg break end
  end
end
-- no X addresses: use the game's own "facing left" function from the training-mode archive, if it has one
SIDE.facing = (SIDE.cfg == nil) and training.has_facing() or false
SIDE.flip_facing = false
if SIDE.facing then
  local rn = ""
  pcall(function() rn = emu.romname() or "" end)
  for _, prefix in ipairs(SIDE_SETTINGS.flip_prefixes) do
    if rn:sub(1, #prefix) == prefix then SIDE.flip_facing = true end
  end
  for _, prefix in ipairs(SIDE_SETTINGS.flip_except) do
    if rn:sub(1, #prefix) == prefix then SIDE.flip_facing = false end
  end
end
SIDE.auto = SIDE.cfg ~= nil or SIDE.facing   -- menu row "Side": AUTO (true) or a fixed Left / Right (false)

-- Side flip: the games disagree on what their facing flag means, so the result can be flipped. The menu row
-- "Side Flip" changes it and the choice is remembered per game (file record_play_<rom>_sideflip2.txt).
SIDE.flip_file = "record_play_" .. rom_name() .. "_sideflip2.txt"
SIDE.flip_user = nil            -- nil = built-in default, true / false = your choice
pcall(function()
  local fh = io.open(SIDE.flip_file, "r")
  if fh then
    local t = fh:read("*l")
    fh:close()
    if t == "on" then SIDE.flip_user = true elseif t == "off" then SIDE.flip_user = false end
  end
end)
function SIDE.flip_now()
  if SIDE.flip_user ~= nil then return SIDE.flip_user end
  return SIDE.flip_facing or SIDE_SETTINGS.reversed or false
end
function SIDE.save_flip()
  pcall(function()
    local fh = io.open(SIDE.flip_file, "w")
    if fh then fh:write(SIDE.flip_user and "on" or "off", "\n") fh:close() end
  end)
end
function SIDE.toggle_flip()
  SIDE.flip_user = not SIDE.flip_now()
  SIDE.p1_left = nil           -- re-read the side with the new setting
  SIDE.save_flip()
  log("side flip", SIDE.flip_user and "ON" or "OFF")
end
-- Calibration: every game writes its side flag differently. Assuming P1 is on the LEFT right now (the
-- normal start of a training session), the flip is set so that the script's idea of "left" matches.
-- It runs by itself on the first reading when no choice is saved for this game, and from the menu row
-- "Calibrate Side" (put P1 on the left first).
function SIDE.calibrate(why)
  if SIDE.raw == nil then return false end
  SIDE.flip_user = (SIDE.raw == false)
  SIDE.p1_left = nil
  SIDE.save_flip()
  say("Side calibrated (" .. why .. "): P1 assumed on the LEFT, flip " .. (SIDE.flip_user and "ON" or "OFF"))
  return true
end

-- called every frame: who is on the left?
function SIDE.update()
  local cfg = SIDE.cfg
  if not cfg then
    if SIDE.facing then
      local left = training.p1_on_left()
      if left == nil then return end
      SIDE.raw = left
      if SIDE.flip_now() then left = not left end
      if left ~= SIDE.p1_left then
        SIDE.p1_left = left
        log("sides: P1 is on the", left and "left" or "right", "(from the game's facing flag)")
      end
    end
    return
  end
  local function read_pos(addr)
    local size = cfg.size or 2
    local fn = (size == 1 and memory.readbyte) or (size == 4 and memory.readdword) or memory.readword
    local v = fn and fn(addr)
    if type(v) == "number" and cfg.signed and v >= 2 ^ (8 * size - 1) then v = v - 2 ^ (8 * size) end
    return v
  end
  local ok, x1, x2 = pcall(function() return read_pos(cfg.p1), read_pos(cfg.p2) end)
  if not (ok and type(x1) == "number" and type(x2) == "number") then
    if not SIDE.warned then SIDE.warned = true log("side detection: cannot read the memory addresses") end
    SIDE.p1_left = nil
    return
  end
  if x1 == x2 then return end        -- same spot: keep what we knew
  local left = x1 < x2
  SIDE.raw = left
  if SIDE.flip_now() then left = not left end
  if left ~= SIDE.p1_left then
    SIDE.p1_left = left
    log("sides: P1 is on the", left and "left" or "right", "(x " .. x1 .. " / " .. x2 .. ")")
  end
end

function SIDE.on() return SIDE.auto and (SIDE.cfg ~= nil or SIDE.facing) end

-- P1's back direction (= P2's forward direction): from the real side when AUTO, else the menu setting
function SIDE.guard()
  if SIDE.on() and SIDE.p1_left ~= nil then return SIDE.p1_left and "Left" or "Right" end
  return guard_dir
end

function SIDE.hud()
  if SIDE.on() then
    if SIDE.p1_left == nil then return "SIDE  no reading yet" end
    return "SIDE  P1 " .. (SIDE.p1_left and "LEFT" or "RIGHT") .. "  >  P2 forward = " .. SIDE.guard()
      .. (SIDE.flip_now() and "  (flip)" or "")
  end
  return "SIDE  manual  >  P2 forward = " .. guard_dir
end
function SIDE.label()
  if SIDE.on() then
    if SIDE.p1_left == nil then return "AUTO (NO DATA)" end
    return "AUTO (P1 " .. (SIDE.p1_left and "LEFT" or "RIGHT") .. ")"
  end
  return guard_dir
end

function SIDE.swap(btn)
  if btn == "Left" then return "Right" end
  if btn == "Right" then return "Left" end
  return btn
end

local function frame_key(f)
  local t = {}
  for b in pairs(f) do t[#t + 1] = b end
  table.sort(t)
  if #t == 0 then return "-" end
  return table.concat(t, "|")
end

local function save_file()
  local fh, err = io.open(SAVE_FILE, "w")
  if not fh then log("save failed:", err) return end
  fh:write("FRP1\n")
  for i = 1, NUM_SLOTS do
    local frames = slots[i].frames
    if #frames > 0 then
      fh:write("SLOT ", i, "\n")
      if slots[i].p1_left ~= nil then fh:write(slots[i].p1_left and "SIDE L\n" or "SIDE R\n") end
      if slots[i].flip ~= nil then fh:write(slots[i].flip and "FLIP 1\n" or "FLIP 0\n") end
      if slots[i].has_state then fh:write("STATE\n") end
      local run_key, run_n = nil, 0
      for _, f in ipairs(frames) do
        local k = frame_key(f)
        if k == run_key then
          run_n = run_n + 1
        else
          if run_key then fh:write(run_n, " ", run_key, "\n") end
          run_key, run_n = k, 1
        end
      end
      if run_key then fh:write(run_n, " ", run_key, "\n") end
      fh:write("END\n")
    end
  end
  fh:close()
  log("saved to", SAVE_FILE)
end

local function load_file()
  local fh = io.open(SAVE_FILE, "r")
  if not fh then return end
  local slot = nil
  for line in fh:lines() do
    local idx = line:match("^SLOT (%d+)")
    if idx then
      slot = tonumber(idx)
      if slot < 1 or slot > NUM_SLOTS then slot = nil else slots[slot].frames = {} slots[slot].p1_left = nil slots[slot].flip = nil end
    elseif line:match("^END") then
      slot = nil
    elseif slot and line:match("^SIDE [LR]") then
      slots[slot].p1_left = (line:match("^SIDE (%a)") == "L")
    elseif slot and line:match("^FLIP [01]") then
      slots[slot].flip = (line:match("^FLIP (%d)") == "1")
    elseif slot and line:match("^STATE") then
      slots[slot].has_state = true
    elseif slot then
      local n, key = line:match("^(%d+) (.+)$")
      n = tonumber(n)
      if n and n <= 200000 then
        local frame = {}
        if key ~= "-" then
          for b in key:gmatch("[^|\r]+") do frame[b] = true end
        end
        local frames = slots[slot].frames
        for _ = 1, n do frames[#frames + 1] = frame end
      end
    end
  end
  fh:close()
end

local function autosave()
  if not AUTO_SAVE_TO_FILE then return end
  local ok, err = pcall(save_file)
  if not ok then log("save error:", err) end
end

---------------------------------------------------------------- savestates
local function state_slot(i) return STATE_SLOT_BASE + i - 1 end

local function do_save()
  if not use_state then return false end
  local st = savestate.create(state_slot(cur))
  savestate.save(st)
  return true
end

local function do_load(i)
  if use_state and slots[i].has_state then
    local st = savestate.create(state_slot(i))
    savestate.load(st)
  end
end

---------------------------------------------------------------- inputs / hotkeys
local function ignored(btn)
  for _, word in ipairs(IGNORE) do
    if btn:find(word) then return true end
  end
  return false
end

-- true on the frame an emulator Lua Hotkey asked for this action (see lua_hotkey_fired)
local function hot(name)
  local fired = hk_pending[name]
  hk_pending[name] = nil
  return fired and true or false
end

local function flip(btn)
  if not mirror then return btn end
  if btn == "Left" then return "Right" end
  if btn == "Right" then return "Left" end
  return btn
end

-- P1 buttons currently held (name without the "P1 " prefix)
local function read_p1()
  local held = {}
  for name, down in pairs(pad_now) do
    local btn = tostring(name):match("^P1 (.+)$")
    if btn and down and not ignored(btn) then
      held[btn] = true
    end
  end
  return held
end

local function names(t)
  local n = {}
  for k in pairs(t) do n[#n + 1] = k end
  table.sort(n)
  return table.concat(n, ",")
end

---------------------------------------------------------------- record / play
-- Recording: P1 controller drives the P2 character.
-- The stored frame is exactly what was sent to P2 (already mirrored).
local function record_frame()
  local held = read_p1()
  local out, frame = {}, {}
  for btn in pairs(held) do
    local b = flip(btn)
    out["P2 " .. b] = true
    frame[b] = true
    if BLOCK_P1_WHILE_RECORDING then out["P1 " .. btn] = false end
  end
  if guard_on then
    out["P1 " .. SIDE.guard()] = true
    if guard_low then out["P1 Down"] = true end
  end
  for k, v in pairs(out) do pending[k] = v end
  local frames = slots[cur].frames
  frames[#frames + 1] = frame
  if next(frame) and logged < 10 then
    logged = logged + 1
    log("rec frame", #frames, "P2 gets:", names(frame))
  end
end

local play_flip = false   -- this pass: swap Left/Right because the sides differ from the recording

local function play_frame(frame)
  for btn in pairs(frame) do pending["P2 " .. (play_flip and SIDE.swap(btn) or btn)] = true end
  if next(frame) and logged < 10 then
    logged = logged + 1
    log("play frame", pos, "P2 set:", names(frame))
  end
end

local function finish_recording()
  local frames = slots[cur].frames
  local n = 0
  for _, f in ipairs(frames) do if next(f) then n = n + 1 end end
  log("record stop: slot", cur, ",", #frames, "frames,", n, "with inputs")
  autosave()
  flash()
end

local function delay_label()
  if delay_random then return "random 0-" .. delay_frames .. "f" end
  return delay_frames .. "f"
end

local function pick_delay()
  if delay_random then return math.random(0, delay_frames) end
  return delay_frames
end

-- the slot to play: a random non-empty slot if random mode is on, otherwise the current one
local function choose_play_slot()
  if random_slot then
    local list = {}
    for i = 1, NUM_SLOTS do
      if #slots[i].frames > 0 then list[#list + 1] = i end
    end
    if #list > 0 then return list[math.random(#list)] end
  end
  return cur
end

-- start one pass of playback (first start or a loop restart)
local function begin_pass(idx)
  play_slot = idx or choose_play_slot()
  if idx and use_state and not slots[play_slot].has_state then
    log("note: no savestate stored for slot", play_slot, ", playing from the current position")
  end
  do_load(play_slot)
  pos, logged = 0, 0
  wait = pick_delay()
  -- sides: with a savestate reset the saved position is restored, so nothing to swap
  play_flip = false
  if SIDE.on() and not (use_state and slots[play_slot].has_state) then
    local sl = slots[play_slot]
    local rec = sl.p1_left
    if rec ~= nil and sl.flip ~= nil and sl.flip ~= SIDE.flip_now() then
      -- recorded with the other Side Flip setting: read its side the way it was read then
      rec = not rec
      if not SIDE.warned_slots[play_slot] then
        SIDE.warned_slots[play_slot] = true
        log("slot", play_slot, "was recorded with Side Flip", sl.flip and "ON" or "OFF", "- its side was corrected")
      end
    elseif not SIDE.warned_slots[play_slot] and (rec == nil or sl.flip == nil) then
      SIDE.warned_slots[play_slot] = true
      if rec == nil then
        say("Slot " .. play_slot .. " has no side stored: it plays as recorded. Re-record to make it swap.")
      else
        say("Slot " .. play_slot .. " is an older recording. If it plays reversed after a side change, re-record it.")
      end
    end
    if rec ~= nil and SIDE.p1_left ~= nil and rec ~= SIDE.p1_left then play_flip = true end
  end
  if play_flip then log("sides differ from the recording: Left and Right are swapped for this pass") end
end

local function advance_playback()
  if wait > 0 then wait = wait - 1 return end
  pos = pos + 1
  if pos > #slots[play_slot].frames then
    if loop then
      begin_pass()
      if wait > 0 then wait = wait - 1 return end
      pos = 1
    else
      mode = IDLE
      log("play finished")
      flash()
      return
    end
  end
  play_frame(slots[play_slot].frames[pos])
end

-- turn a motion into a list of frames (each frame = set of P2 button names)
local function digit_buttons(d, fwd, back, side_aware)
  local t = {}
  if d == "1" or d == "2" or d == "3" then t["Down"] = true end
  if d == "7" or d == "8" or d == "9" then t["Up"] = true end
  if d == "1" or d == "4" or d == "7" then t[side_aware and "__rp_relative_back" or back] = true end
  if d == "3" or d == "6" or d == "9" then t[side_aware and "__rp_relative_forward" or fwd] = true end
  return t
end

local ATTACK_TOKENS = { LP = true, MP = true, HP = true, LK = true, MK = true, HK = true }

-- buttons = list of game button names pressed with the motion (nil for a fixed motion)
local function compile_motion(input, buttons, fixed, hold_indefinitely, final_direction_frames, side_aware, ignore_side)
  -- P1's back direction is P2's forward direction (they face each other)
  -- ignore_side: never use the automatic detection, only the menu setting
  local fwd = ignore_side and guard_dir or SIDE.guard()
  local back = (fwd == "Left") and "Right" or "Left"
  local frames = {}
  local step_count, step_index = 0, 0
  for _ in input:gmatch("%S+") do step_count = step_count + 1 end
  local function add(t, n) for _ = 1, n do frames[#frames + 1] = t end end
  local function with_buttons(t)
    for _, b in ipairs(buttons or {}) do t[b] = true end
    return t
  end

  for step in input:gmatch("%S+") do
    step_index = step_index + 1
    local wait_n = step:match("^w(%d+)$")
    if wait_n then
      add({}, tonumber(wait_n))
    elseif ATTACK_TOKENS[step] then
      -- a fixed button press (used by fixed sequences such as Raging Demon)
      local name = game_button(step)
      if not name then return nil, "this game has no " .. step .. " button" end
      add({ [name] = true }, BUTTON_FRAMES)
      add({}, STEP_GAP)
    elseif step == "mash" then
      for _ = 1, MASH_PRESSES do
        add(with_buttons({}), 2)
        add({}, 2)
      end
    else
      local charge, dirs, flag = step:match("^%[(%d)%](%d+)([~%.]?)$")
      if not charge then dirs, flag = step:match("^(%d+)([~%.]?)$") end
      if not dirs then return nil, "cannot read step '" .. step .. "'" end
      local negative = (flag == "~")
      local plain = fixed or (flag == ".")      -- no button on this step
      if charge then add(digit_buttons(charge, fwd, back, side_aware), CHARGE_FRAMES) end
      for i = 1, #dirs do
        local f = digit_buttons(dirs:sub(i, i), fwd, back, side_aware)
        local last = (i == #dirs)
        if negative then
          if not last then with_buttons(f) end      -- held during the motion, released on the last direction
          add(f, DIR_FRAMES)
        elseif last and not plain then
          with_buttons(f)
          add(f, BUTTON_FRAMES)
        else
          add(f, (last and step_index == step_count and final_direction_frames) or DIR_FRAMES)
        end
      end
      -- For indefinite directional holds, the final direction must remain the last frame.
      if not (hold_indefinitely and step_index == step_count) then add({}, STEP_GAP) end
    end
  end
  return frames
end

-- label of the button chosen for the preset ("FIXED" for a fixed sequence)
local function preset_label()
  if MOTIONS[preset.i].fixed then return "FIXED" end
  return preset.opt and preset.opt.label or "?"
end

-- start one pass of the preset move on P2 (first start or a loop restart)
-- restart = true for a loop repeat: it rests at least LOOP_MIN_GAP frames and logs nothing
local function start_motion(restart)
  local add_air
  local m = MOTIONS[preset.i]
  local names = nil
  if not m.fixed then
    names = preset.opt and option_buttons(preset.opt)
    if not names then
      say("This game has no " .. preset_label() .. " button")
      preset = nil
      return false
    end
  end
  local frames, err = compile_motion(m.input, names, m.fixed, m.hold_indefinitely, m.final_direction_frames, m.side_aware, m.ignore_side)
  if not frames then
    say("Motion error: " .. err)
    preset = nil
    return false
  end
  if m.air_frames then add_air = m.air_frames else add_air = 0 end
  for _ = 1, add_air do frames[#frames + 1] = {} end   -- wait for the landing before a loop restarts
  move_frames, move_pos = frames, 0
  move_fwd = nil
  wait = pick_delay()
  if restart and not m.no_loop_gap and wait < LOOP_MIN_GAP then wait = LOOP_MIN_GAP end
  mode = MOVE
  if not restart then
    log("preset:", m.name, preset_label(), "(" .. #frames .. " frames, delay " .. delay_label() .. ")")
  end
  return true
end

-- choosing a move in the sub menu loads it as the preset (like a recording) and plays it once
local function perform_motion()
  flash()
  if mode ~= IDLE then say("Press Stop (" .. hotkey_of("stop") .. ") before performing a motion") return end
  local opts = available_options()
  if not MOTIONS[motion_i].fixed and #opts == 0 then
    say("No punch or kick buttons found - see BUTTON_MAP in the script")
    return
  end
  preset = { i = motion_i, opt = opts[math.max(1, math.min(motion_btn, #opts))] }
  start_motion(false)
end

local function advance_move()
  if wait > 0 then wait = wait - 1 return end
  move_pos = move_pos + 1
  if move_pos > #move_frames then
    if preset and MOTIONS[preset.i].hold_indefinitely then
      -- Keep the final direction pressed until the user explicitly stops playback.
      move_pos = #move_frames
    elseif loop and preset then
      if not start_motion(true) then return end
      if wait > 0 then wait = wait - 1 return end
      move_pos = 1
    else
      mode = IDLE
      log("move finished")
      flash()
      return
    end
  end
  -- the side is read ONCE, on the first frame of the move, and kept until the move ends (a held run or
  -- hold would otherwise flip direction whenever the detected side changed in the middle of it)
  if move_pos == 1 or not move_fwd then
    move_fwd = SIDE.guard()
    local m = preset and MOTIONS[preset.i]
    if m and not m.ignore_side then
      say("Preset forward = P2 " .. move_fwd .. "  (Side: " .. SIDE.label() .. (SIDE.flip_now() and ", flip ON" or "") .. ")")
    end
  end
  local fwd = move_fwd
  local back = (fwd == "Left") and "Right" or "Left"
  for btn in pairs(move_frames[move_pos]) do
    if btn == "__rp_relative_forward" then
      pending["P2 " .. fwd] = true
    elseif btn == "__rp_relative_back" then
      pending["P2 " .. back] = true
    else
      pending["P2 " .. btn] = true
    end
  end
end

-- text shown next to a motion in the sub menu (long inputs are left out)
local function motion_shown(m)
  local t = m.shown or m.input
  if #t > 13 then return "" end
  return t
end

---------------------------------------------------------------- actions and menu
local function onoff(v) return v and "on" or "off" end

local function toggle_loop() loop = not loop log("loop", onoff(loop)) flash() end
local function toggle_mirror() mirror = not mirror log("mirror", onoff(mirror)) flash() end
local function toggle_guard_on() guard_on = not guard_on log("guard while recording", onoff(guard_on)) flash() end
local function toggle_stance() guard_low = not guard_low log("guard", guard_low and "low (crouching)" or "high (standing)") flash() end
local function toggle_side()
  if SIDE.cfg or SIDE.facing then            -- AUTO -> Left -> Right -> AUTO
    if SIDE.auto then SIDE.auto, guard_dir = false, "Left"
    elseif guard_dir == "Left" then guard_dir = "Right"
    else SIDE.auto = true end
  else
    guard_dir = (guard_dir == "Left") and "Right" or "Left"
  end
  log("side", SIDE.label())
  flash()
end
-- change the playback delay by some frames; it always stays between 0 and DELAY_MAX
local function adjust_delay(amount)
  local old = delay_frames
  delay_frames = math.max(0, math.min(DELAY_MAX, delay_frames + amount))
  if delay_frames ~= old then log("playback delay", delay_label()) end
  flash()
end
-- Left/Right on the delay row: one frame at a time, and it wraps like a slider (0 <- 300)
local function step_delay(d)
  local old = delay_frames
  delay_frames = delay_frames + d
  if delay_frames < 0 then delay_frames = DELAY_MAX end
  if delay_frames > DELAY_MAX then delay_frames = 0 end
  if delay_frames ~= old then log("playback delay", delay_label()) end
  flash()
end
local function toggle_random_delay() delay_random = not delay_random log("random delay", onoff(delay_random)) flash() end
local function toggle_random() random_slot = not random_slot log("random slot", onoff(random_slot)) flash() end
local function toggle_state()
  use_state = not use_state
  log("savestate reset", use_state and ("ON (emulator slots " .. STATE_SLOT_BASE .. "-" .. (STATE_SLOT_BASE + NUM_SLOTS - 1) .. ")") or "OFF")
  flash()
end

local function change_slot(d)
  if mode ~= IDLE then say("Press Stop (" .. hotkey_of("stop") .. ") before changing slot") return end
  cur = ((cur - 1 + d) % NUM_SLOTS) + 1
  preset = nil   -- back to playing recordings
  log("slot", cur, "(" .. #slots[cur].frames .. " frames)")
  flash()
end

local nav_pressed, nav_sync -- forward declarations: the training submenu shares the main menu navigation handlers
local function training_menu_input()
  local pr = nav_pressed()
  local rows = training.menu
  if pr.up then training.index = (training.index - 2) % #rows + 1 end
  if pr.down then training.index = training.index % #rows + 1 end
  local row = rows[training.index]
  local result
  if pr.left or pr.right then
    if row.change then row.change(pr.left and -1 or 1) end
  elseif pr.select then
    if row.act then result = row.act() elseif row.change then row.change(1) end
  end
  if pr.back or result == "back" then
    menu_page = "main"
    nav_sync()
  end
end

-- optional extra hotkeys (give one a number in LUA_HOTKEYS to use it)
local ACTIONS = {
  loop = toggle_loop, mirror = toggle_mirror, guard = toggle_stance, side = toggle_side,
  guard_toggle = toggle_guard_on, random = toggle_random, random_delay = toggle_random_delay,
  delay_up = function() adjust_delay(DELAY_STEP) end, delay_down = function() adjust_delay(-DELAY_STEP) end,
  state = toggle_state,
  slot_next = function() change_slot(1) end, slot_prev = function() change_slot(-1) end,
}

-- the real name of a menu control in this game (nil if it does not exist)
local function nav_name(action) return resolve(MENU_NAV[action]) end

nav_sync = function()
  for action in pairs(MENU_NAV) do
    local name = nav_name(action)
    local down = (name and pad_now[name]) and true or false
    nav_held[action] = down
    nav_count[action] = down and -1 or 0   -- -1: held while the menu opened, wait for it to be released
  end
  delay_prev = {}
  for _, d in ipairs(DELAY_BUTTONS) do
    local n = game_button(d[1])
    delay_prev[d[1]] = (n and pad_now["P1 " .. n]) and true or false   -- held now: needs a new press
  end
end

-- which menu controls fire this frame: a press fires once; Up and Down also repeat while held
local REPEATING = { up = true, down = true }
nav_pressed = function()
  local pressed = {}
  for action in pairs(MENU_NAV) do
    local name = nav_name(action)
    local down = (name and pad_now[name]) and true or false
    local c = nav_count[action] or 0
    if not down then
      c = 0
    elseif c ~= -1 then
      c = c + 1
      if c == 1 then
        pressed[action] = true
      elseif (REPEATING[action] or (lr_repeat and (action == "left" or action == "right")))
             and c > REPEAT_FIRST then
        local lr = (action == "left" or action == "right")
        local rate = (lr and c > REPEAT_FAST_AFTER) and 1 or REPEAT_RATE
        if (c - REPEAT_FIRST) % rate == 0 then pressed[action] = true end
      end
    end
    nav_count[action] = c
    nav_held[action] = down
  end
  return pressed
end

-- delay buttons: the total frames added or removed by buttons newly pressed this frame
-- (0 = none). Tracked on every menu frame so a button held while moving onto the row does nothing.
local function delay_button_change()
  local total = 0
  for _, d in ipairs(DELAY_BUTTONS) do
    local n = game_button(d[1])
    local down = (n and pad_now["P1 " .. n]) and true or false
    if down and not delay_prev[d[1]] then total = total + d[2] end
    delay_prev[d[1]] = down
  end
  return total
end

local function close_menu() menu_open = false menu_page = "main" lr_repeat = false flash() end

local function open_menu()
  if mode ~= IDLE then say("Press Stop (" .. hotkey_of("stop") .. ") before opening the menu") return end
  menu_open = true
  menu_page = "main"
  nav_sync()
end

MENU_UI.show_page = function(page)
  menu_page = page
  nav_sync()
end

MENU_UI.back_to_parent = function()
  if menu_page == "motions" then
    MENU_UI.show_page("recording")
  elseif menu_page == "recording" or menu_page == "training" then
    MENU_UI.show_page("main")
  else
    close_menu()
  end
end

MENU_UI.main_menu = {
  { label = "Training Tools", get = function() return "OPEN" end,
    act = function() training.index = math.max(1, math.min(training.index, #training.menu)); MENU_UI.show_page("training") end },
  { label = "Recording Tools", get = function() return "OPEN" end,
    act = function() MENU_UI.show_page("recording") end },
  { label = "Close menu", get = function() return "" end, act = close_menu },
}

MENU_UI.recording_menu = {
  { label = "Slot",
    get = function()
      if preset then
        local label = preset_label()
        local room = 17 - 7 - 1 - #label
        return "PRESET " .. MOTIONS[preset.i].name:sub(1, room) .. " " .. label
      end
      return cur .. "/" .. NUM_SLOTS .. " (" .. #slots[cur].frames .. " frames)"
    end,
    change = change_slot },
  { label = "Loop", get = function() return onoff(loop) end, change = toggle_loop },
  { label = "Mirror", get = function() return onoff(mirror) end, change = toggle_mirror },
  { label = "Guard while recording", get = function() return onoff(guard_on) end, change = toggle_guard_on },
  { label = "Guard stance", get = function() return guard_low and "low (crouching)" or "high (standing)" end, change = toggle_stance },
  { label = "Side", get = SIDE.label, change = toggle_side },
  { label = "Side HUD", get = function() return onoff(SIDE.hud_on) end,
    change = function() SIDE.hud_on = not SIDE.hud_on flash() end },
  { label = "Reset Side", get = function() return "PRESS" end,
    change = function()
      pcall(os.remove, SIDE.flip_file)
      SIDE.flip_user = nil
      SIDE.p1_left = nil
      local cleared = 0
      for i = 1, NUM_SLOTS do
        local sl = slots[i]
        if sl.p1_left ~= nil and sl.flip == nil then sl.p1_left = nil cleared = cleared + 1 end
      end
      if cleared > 0 then autosave() end
      SIDE.warned_slots = {}
      say("Side reset: flip back to default" .. (cleared > 0 and (", " .. cleared .. " old slot(s) lost their side marker") or ""))
      log("side reset; flip default =", SIDE.flip_now() and "ON" or "OFF")
      flash()
    end },
  { label = "Side Flip", get = function() return SIDE.flip_now() and "ON" or "OFF" end,
    change = function() SIDE.toggle_flip() flash() end },
  { label = "Playback delay", get = function() return delay_frames .. " FRAMES" end,
    change = function(d) step_delay(d or 1) end, adjust = true, no_select = true },
  { label = "Random delay", get = function() return onoff(delay_random) end, change = toggle_random_delay },
  { label = "Random slot", get = function() return onoff(random_slot) end, change = toggle_random },
  { label = "Savestate reset", get = function() return onoff(use_state) end, change = toggle_state },
  { label = "Motions", get = function() return "OPEN" end,
    act = function() MENU_UI.show_page("motions") end },
  { label = "Back to Main Menu", get = function() return "" end,
    act = function() MENU_UI.show_page("main") end },
}

MENU_UI.current_menu = function()
  if menu_page == "recording" then return MENU_UI.recording_menu, MENU_UI.recording_idx end
  return MENU_UI.main_menu, MENU_UI.main_idx
end

MENU_UI.set_current_menu_index = function(i)
  if menu_page == "recording" then MENU_UI.recording_idx = i else MENU_UI.main_idx = i end
end

-- keep the selected motion inside the visible window of the sub menu
local function fix_scroll()
  if motion_i < motion_top then
    motion_top = motion_i
  elseif motion_i > motion_top + MOTION_ROWS - 1 then
    motion_top = motion_i - MOTION_ROWS + 1
  end
end

-- Context-sensitive controls stay consistent across the root and recording menus.
local function menu_hints(row)
  if row and row.adjust then
    local parts = {}
    for _, d in ipairs(DELAY_BUTTONS) do
      if game_button(d[1]) then parts[#parts + 1] = d[1] .. (d[2] > 0 and "+" or "-") .. math.abs(d[2]) end
    end
    return "LEFT/RIGHT: 1 FRAME (0 WRAPS TO 300)", table.concat(parts, " ")
  end
  if menu_page == "recording" then
    return "UP/DOWN: CHOOSE  LEFT/RIGHT: CHANGE", "LP: SELECT   LK: MAIN MENU"
  end
  return "UP/DOWN: CHOOSE", "LP: SELECT   LK: CLOSE"
end

-- text for the button choice in the sub menu
local function motion_button_label()
  if MOTIONS[motion_i].fixed then return "FIXED" end
  local o = available_options()[motion_btn]
  return o and o.label or "NONE"
end

-- sub menu: Up/Down choose a motion (hold to keep moving), Left/Right choose the button,
-- LP performs, LK goes back
local function motions_input()
  local pr = nav_pressed()
  local opts = available_options()
  if motion_btn > #opts then motion_btn = #opts end
  if motion_btn < 1 then motion_btn = 1 end
  if pr.up then motion_i = (motion_i - 2) % #MOTIONS + 1 end
  if pr.down then motion_i = motion_i % #MOTIONS + 1 end
  if pr.left and #opts > 0 then motion_btn = (motion_btn - 2) % #opts + 1 end
  if pr.right and #opts > 0 then motion_btn = motion_btn % #opts + 1 end
  fix_scroll()
  if pr.select then
    close_menu()
    perform_motion()
    return
  end
  if pr.back then MENU_UI.show_page("recording") end
end

-- Up/Down move the cursor (hold to keep moving; it wraps around). Left/Right call
-- change(-1)/change(+1); toggles ignore the direction. On the delay row Left/Right move one frame
-- (and repeat while held) and the six attack buttons add or remove frames (see DELAY_BUTTONS).
local function menu_input()
  local rows, idx = MENU_UI.current_menu()
  lr_repeat = rows[idx].adjust and true or false   -- decides repeat for this frame's presses
  local pr = nav_pressed()

  -- Back is a parent-navigation action in submenus, and closes the menu only at the root.
  -- Preserve the delay row's LK shortcut for -10 frames, as in the original menu.
  if pr.back and not rows[idx].adjust then
    MENU_UI.back_to_parent()
    return
  end

  local dd = (pr.up and -1) or (pr.down and 1) or 0
  if dd ~= 0 then
    idx = (idx - 1 + dd) % #rows + 1
    MENU_UI.set_current_menu_index(idx)
  end

  local row = rows[idx]
  local dchg = delay_button_change()   -- always read, so held buttons never carry over to the row
  if row.adjust and dchg ~= 0 and dd == 0 then adjust_delay(dchg) end
  if pr.left and row.change then row.change(-1) end
  if pr.right and row.change then row.change(1) end
  if pr.select and not row.no_select then
    if row.act then
      row.act()
    elseif row.change then
      row.change(1)
    end
  end
end

local function tick()
  frame_count = frame_count + 1
  -- these two can come back empty (or nil) in some games or builds, so never trust them
  local ok_pad, pad = pcall(joypad.get)
  pad_now = (ok_pad and type(pad) == "table") and pad or {}
  learn_inputs()
  SIDE.update()

  -- once, tell the console which buttons this game uses (helps with fixing a wrong guess)
  if not announced and next(pad_now) then
    announced = true
    local list = {}
    for n in pairs(known) do list[#list + 1] = n end
    table.sort(list)
    log("P1 inputs:", table.concat(list, ", "))
    local map = {}
    for _, l in ipairs({ "LP", "MP", "HP", "LK", "MK", "HK" }) do
      map[#map + 1] = l .. "=" .. (game_button(l) or "none")
    end
    log("attack buttons:", table.concat(map, "  "))
  end

  if PRINT_BUTTONS then
    local held = {}
    for name, down in pairs(pad_now) do
      if down and tostring(name):match("^P%d ") then held[#held + 1] = tostring(name) end
    end
    table.sort(held)
    local str = table.concat(held, ", ")
    if str ~= last_print then log("buttons:", str) last_print = str end
  end

  local r, p = hot("rec"), hot("play")
  local s = hot("stop")
  local m = hot("menu")
  for name, fn in pairs(ACTIONS) do
    if hot(name) then fn() end
  end

  if m then
    if menu_open then close_menu() else open_menu() end
  elseif menu_open and (r or p or s) then
    close_menu()  -- starting or stopping something closes the menu
  end

  if menu_open then
    -- the menu uses P1's controls, so keep them away from the game while it is open
    -- (remembered, so a button still held when the menu closes is not sent to the game either)
    MENU_UI.carry = {}
    for name, down in pairs(pad_now) do
      if down and tostring(name):match("^P1 ") then pending[name] = false MENU_UI.carry[name] = true end
    end
    if menu_page == "motions" then motions_input()
    elseif menu_page == "training" then training_menu_input()
    else menu_input() end
    return
  end

  -- the menu was just closed: a button used to confirm or close it stays blocked until it is let go
  if next(MENU_UI.carry) then
    for name in pairs(MENU_UI.carry) do
      if pad_now[name] then pending[name] = false else MENU_UI.carry[name] = nil end
    end
  end

  training.capture_inputs()

  if s then
    flash()  -- always show the details when stop is pressed
    if mode == REC then
      finish_recording()
      mode = IDLE
    elseif mode == PLAY then
      log("play stopped")
      mode = IDLE
    elseif mode == MOVE then
      log("motion stopped")
      mode = IDLE
    end
  end

  if r then
    if mode == REC then
      mode = IDLE
      finish_recording()
    else
      local sl = slots[cur]
      sl.frames = {}
      sl.has_state = do_save()
      sl.p1_left = SIDE.p1_left   -- the side this recording is made on (nil = unknown)
      sl.flip = SIDE.flip_now()   -- which Side Flip setting that side was read with
      preset = nil
      pos, logged = 0, 0
      if MIRROR_AT_RECORD_START ~= nil then mirror = MIRROR_AT_RECORD_START end
      mode = REC
      log("record start: slot", cur, "- your controls now drive P2, mirror", mirror,
          use_state and "(state saved)" or "(no savestate)",
          sl.p1_left == nil and "" or (sl.p1_left and "P1 on the left" or "P1 on the right"))
    end
  elseif p and preset then
    start_motion()
  elseif p then
    local ps = choose_play_slot()
    if #slots[ps].frames == 0 then
      say("Slot " .. ps .. " is empty - record something first")
    else
      mode = PLAY
      begin_pass(ps)
      log("play start: slot", play_slot, ",", #slots[play_slot].frames, "frames, delay", delay_label())
    end
  end

  if mode == REC then
    record_frame()
  elseif mode == PLAY then
    advance_playback()
  elseif mode == MOVE then
    advance_move()
  end
end

local function safe_tick()
  pending = {}
  local ok, err = pcall(tick)
  if not ok then log("ERROR:", err) end
  if SIDE.settings_tick then pcall(SIDE.settings_tick) end
  if next(pending) then joypad.set(pending) end
end

---------------------------------------------------------------- display
local function slot_summary()
  local t = {}
  for i = 1, NUM_SLOTS do
    local n = #slots[i].frames
    t[#t + 1] = string.format("%s%d:%s", i == cur and ">" or "", i, n > 0 and n or "-")
  end
  return table.concat(t, " ")
end

-- draw one line of text; falls back to plain text if this emulator rejects colors
local function draw_text(x, y, str, color)
  if TEXT_COLORS then
    if pcall(gui.text, x, y, str, color or "white", "#000000b0") then return end
  end
  gui.text(x, y, str)
end

---------------------------------------------------------------- big menu font
-- The emulator's own text has a fixed small size, so the menu is drawn with a 5x7 pixel
-- font made of boxes (each font pixel is one game pixel, which is large on screen).
local FONT = {
  A = {".###.","#...#","#...#","#####","#...#","#...#","#...#"},
  B = {"####.","#...#","#...#","####.","#...#","#...#","####."},
  C = {".###.","#...#","#....","#....","#....","#...#",".###."},
  D = {"####.","#...#","#...#","#...#","#...#","#...#","####."},
  E = {"#####","#....","#....","####.","#....","#....","#####"},
  F = {"#####","#....","#....","####.","#....","#....","#...."},
  G = {".###.","#...#","#....","#.###","#...#","#...#",".###."},
  H = {"#...#","#...#","#...#","#####","#...#","#...#","#...#"},
  I = {".###.","..#..","..#..","..#..","..#..","..#..",".###."},
  J = {"..###","...#.","...#.","...#.","...#.","#..#.",".##.."},
  K = {"#...#","#..#.","#.#..","##...","#.#..","#..#.","#...#"},
  L = {"#....","#....","#....","#....","#....","#....","#####"},
  M = {"#...#","##.##","#.#.#","#.#.#","#...#","#...#","#...#"},
  N = {"#...#","##..#","#.#.#","#..##","#...#","#...#","#...#"},
  O = {".###.","#...#","#...#","#...#","#...#","#...#",".###."},
  P = {"####.","#...#","#...#","####.","#....","#....","#...."},
  Q = {".###.","#...#","#...#","#...#","#.#.#","#..#.",".##.#"},
  R = {"####.","#...#","#...#","####.","#.#..","#..#.","#...#"},
  S = {".####","#....","#....",".###.","....#","....#","####."},
  T = {"#####","..#..","..#..","..#..","..#..","..#..","..#.."},
  U = {"#...#","#...#","#...#","#...#","#...#","#...#",".###."},
  V = {"#...#","#...#","#...#","#...#","#...#",".#.#.","..#.."},
  W = {"#...#","#...#","#...#","#.#.#","#.#.#","##.##","#...#"},
  X = {"#...#","#...#",".#.#.","..#..",".#.#.","#...#","#...#"},
  Y = {"#...#","#...#",".#.#.","..#..","..#..","..#..","..#.."},
  Z = {"#####","....#","...#.","..#..",".#...","#....","#####"},
  ["0"] = {".###.","#...#","#..##","#.#.#","##..#","#...#",".###."},
  ["1"] = {"..#..",".##..","..#..","..#..","..#..","..#..",".###."},
  ["2"] = {".###.","#...#","....#","...#.","..#..",".#...","#####"},
  ["3"] = {"#####","...#.","..#..","...#.","....#","#...#",".###."},
  ["4"] = {"...#.","..##.",".#.#.","#..#.","#####","...#.","...#."},
  ["5"] = {"#####","#....","####.","....#","....#","#...#",".###."},
  ["6"] = {"..##.",".#...","#....","####.","#...#","#...#",".###."},
  ["7"] = {"#####","....#","...#.","..#..",".#...",".#...",".#..."},
  ["8"] = {".###.","#...#","#...#",".###.","#...#","#...#",".###."},
  ["9"] = {".###.","#...#","#...#",".####","....#","...#.",".##.."},
  ["/"] = {"....#","....#","...#.","..#..",".#...","#....","#...."},
  ["("] = {"...#.","..#..",".#...",".#...",".#...","..#..","...#."},
  [")"] = {".#...","..#..","...#.","...#.","...#.","..#..",".#..."},
  ["+"] = {".....","..#..","..#..","#####","..#..","..#..","....."},
  ["-"] = {".....",".....",".....","#####",".....",".....","....."},
  [":"] = {".....","..#..","..#..",".....","..#..","..#..","....."},
  [">"] = {"#....",".#...","..#..","...#.","..#..",".#...","#...."},
  ["."] = {".....",".....",".....",".....",".....",".##..",".##.."},
  ["["] = {"###..","#....","#....","#....","#....","#....","###.."},
  ["]"] = {"..###","....#","....#","....#","....#","....#","..###"},
  ["~"] = {".....",".....",".##.#","#.##.",".....",".....","....."},
}
local CELL_W, ROW_H = 6, 11   -- character cell width and row height, in game pixels

-- turn each glyph into a few rectangles {first row, first column, last column, last row}
-- (horizontal runs, with identical runs in neighbouring rows joined: fewer gui.box calls)
local GLYPH_RUNS = {}
-- direction arrows for the input history (characters 1-8): up, down, left, right, up-left, up-right, down-left, down-right
FONT["\1"] = { "..#..", ".###.", "#.#.#", "..#..", "..#..", "..#..", "..#.." }
FONT["\2"] = { "..#..", "..#..", "..#..", "..#..", "#.#.#", ".###.", "..#.." }
FONT["\3"] = { ".....", "..#..", ".#...", "#####", ".#...", "..#..", "....." }
FONT["\4"] = { ".....", "..#..", "...#.", "#####", "...#.", "..#..", "....." }
FONT["\5"] = { ".....", "###..", "##...", "#.#..", "#..#.", "....#", "....." }
FONT["\6"] = { ".....", "..###", "...##", "..#.#", ".#..#", "#....", "....." }
FONT["\7"] = { ".....", "....#", "#..#.", "#.#..", "##...", "###..", "....." }
FONT["\8"] = { ".....", "#....", ".#..#", "..#.#", "...##", "..###", "....." }

local function glyph_runs(ch)
  local cached = GLYPH_RUNS[ch]
  if cached then return cached end
  local runs, g = {}, FONT[ch]
  if g then
    local open = {}   -- rectangles that continue from the row above, by their columns
    for row = 1, 7 do
      local line, c = g[row], 1
      local now = {}
      while c <= 5 do
        if line:sub(c, c) == "#" then
          local e = c
          while e < 5 and line:sub(e + 1, e + 1) == "#" do e = e + 1 end
          local key = c .. ":" .. e
          local r = open[key]
          if r then
            r[4] = row - 1
          else
            r = { row - 1, c - 1, e - 1, row - 1 }
            runs[#runs + 1] = r
          end
          now[key] = r
          c = e + 1
        else
          c = c + 1
        end
      end
      open = now
    end
  end
  GLYPH_RUNS[ch] = runs
  return runs
end

-- colors: "#rrggbb" or "#rrggbbaa"; some builds want numbers, so we detect which works
local box_format = nil   -- "string", "number" or "none"
local function hex_to_num(c)
  local r, g, b, a = c:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  if not r then return 0xFFFFFFFF end
  if a == "" then a = "ff" end
  return tonumber(r .. g .. b .. a, 16)
end

local function draw_box(x1, y1, x2, y2, color)
  if box_format == nil then
    if not gui.box then
      box_format = "none"
    elseif pcall(gui.box, 0, 0, 0, 0, "#00000000", "#00000000") then
      box_format = "string"
    elseif pcall(gui.box, 0, 0, 0, 0, 0x00000000, 0x00000000) then
      box_format = "number"
    else
      box_format = "none"
    end
  end
  if box_format == "string" then
    gui.box(x1, y1, x2, y2, color, color)
  elseif box_format == "number" then
    local n = hex_to_num(color)
    gui.box(x1, y1, x2, y2, n, n)
  end
end

local function draw_big_text(x, y, str, color)
  local cx = x
  for i = 1, #str do
    for _, r in ipairs(glyph_runs(str:sub(i, i):upper())) do
      draw_box(cx + r[2], y + r[1], cx + r[3], y + r[4], color)
    end
    cx = cx + CELL_W
  end
end

local MENU_BG, MENU_BAR = "#000000f2", "#2244cc"
local MENU_TITLE, MENU_WHITE, MENU_VALUE, MENU_SEL_VALUE, MENU_HINT =
  "#ffe14d", "#ffffff", "#7fe8ff", "#ffff66", "#c8d0ff"

local function draw_menu_big()
  local rows, selected_idx = MENU_UI.current_menu()
  local is_recording = menu_page == "recording"
  local title = is_recording and "PRACTICE MODE - RECORDING" or "PRACTICE MODE"
  local x0, y0 = MENU_X, MENU_Y
  local value_col = 25
  local width = (value_col + 17) * CELL_W
  local height = (#rows + 4) * ROW_H + 4
  if box_format == nil then draw_box(0, 0, 0, 0, "#00000000") end
  if box_format == "none" then error("no gui.box") end

  draw_box(x0 - 5, y0 - 5, x0 + width, y0 + height, MENU_BG)
  draw_big_text(x0, y0, title, MENU_TITLE)
  local y = y0 + ROW_H + 3
  for i, row in ipairs(rows) do
    local selected = (i == selected_idx)
    if selected then draw_box(x0 - 3, y - 2, x0 + width - 2, y + 8, MENU_BAR) end
    draw_big_text(x0, y, selected and ">" or " ", MENU_WHITE)
    draw_big_text(x0 + 2 * CELL_W, y, row.label, MENU_WHITE)
    local value = row.get and row.get() or ""
    if value ~= "" then
      draw_big_text(x0 + value_col * CELL_W, y, value, selected and MENU_SEL_VALUE or MENU_VALUE)
    end
    y = y + ROW_H
  end
  y = y + 3
  local hint1, hint2 = menu_hints(rows[selected_idx])
  draw_big_text(x0, y, hint1, MENU_HINT)
  draw_big_text(x0, y + ROW_H, hint2, MENU_HINT)
end

local function draw_motions_big()
  local x0, y0 = MENU_X, MENU_Y
  local value_col = 29
  local width = (value_col + 14) * CELL_W
  local height = (MOTION_ROWS + 4) * ROW_H + 12
  if box_format == nil then draw_box(0, 0, 0, 0, "#00000000") end
  if box_format == "none" then error("no gui.box") end

  draw_box(x0 - 5, y0 - 5, x0 + width, y0 + height, MENU_BG)
  draw_big_text(x0, y0, "MOTIONS", MENU_TITLE)
  draw_big_text(x0 + value_col * CELL_W, y0, "BUTTON: " .. motion_button_label(), MENU_VALUE)
  local y = y0 + ROW_H + 3
  draw_big_text(x0, y, MOTIONS[motion_i].cat, MENU_HINT)
  draw_big_text(x0 + (value_col + 7) * CELL_W, y, motion_i .. "/" .. #MOTIONS, MENU_HINT)
  y = y + ROW_H + 2
  for row = motion_top, math.min(motion_top + MOTION_ROWS - 1, #MOTIONS) do
    local item = MOTIONS[row]
    local selected = (row == motion_i)
    if selected then draw_box(x0 - 3, y - 2, x0 + width - 2, y + 8, MENU_BAR) end
    draw_big_text(x0, y, selected and ">" or " ", MENU_WHITE)
    draw_big_text(x0 + 2 * CELL_W, y, item.name, MENU_WHITE)
    local shown = motion_shown(item)
    if shown ~= "" then
      draw_big_text(x0 + value_col * CELL_W, y, shown, selected and MENU_SEL_VALUE or MENU_VALUE)
    end
    y = y + ROW_H
  end
  y = y0 + ROW_H + 3 + ROW_H + 2 + MOTION_ROWS * ROW_H + 3
  draw_big_text(x0, y, "UP/DOWN: MOVE  LEFT/RIGHT: BUTTON", MENU_HINT)
  draw_big_text(x0, y + ROW_H, "LP: LOAD AND PLAY  LK: BACK", MENU_HINT)
end

local function draw_training_big()
  local x0, y0 = MENU_X, MENU_Y
  local value_col = 25
  local width = (value_col + 17) * CELL_W
  local height = (#training.menu + 4) * ROW_H + 4
  if box_format == nil then draw_box(0, 0, 0, 0, "#00000000") end
  if box_format == "none" then error("no gui.box") end
  draw_box(x0 - 5, y0 - 5, x0 + width, y0 + height, MENU_BG)
  draw_big_text(x0, y0, "TRAINING TOOLS", MENU_TITLE)
  local y = y0 + ROW_H + 3
  for i, row in ipairs(training.menu) do
    local selected = (i == training.index)
    if selected then draw_box(x0 - 3, y - 2, x0 + width - 2, y + 8, MENU_BAR) end
    draw_big_text(x0, y, selected and ">" or " ", MENU_WHITE)
    draw_big_text(x0 + 2 * CELL_W, y, row.label, MENU_WHITE)
    local value = row.get()
    if value ~= "" then
      draw_big_text(x0 + value_col * CELL_W, y, value, selected and MENU_SEL_VALUE or MENU_VALUE)
    end
    y = y + ROW_H
  end
  y = y + 3
  draw_big_text(x0, y, "UP DOWN CHOOSE LEFT RIGHT TOGGLE", MENU_HINT)
  draw_big_text(x0, y + ROW_H, "LP SELECT LK BACK", MENU_HINT)
end

---------------------------------------------------------------- training overlay drawing
local function draw_training_damage()
  local sw = emu.screenwidth()
  local sh = emu.screenheight()
  local x, y = 4, math.max(4, sh - 25)
  local damage = training.damage_data()
  local unit = training.damage_unit()
  local line1 = string.format("P1 %03d%s", math.floor(damage[1] + 0.5), unit)
  local line2 = string.format("P2 %03d%s", math.floor(damage[2] + 0.5), unit)
  if box_format == nil then draw_box(0, 0, 0, 0, "#00000000") end
  if box_format ~= "none" then draw_box(x - 3, y - 3, x + 52, math.min(sh - 1, y + 18), "#000000d8") end
  draw_big_text(x, y, line1, "#7fe8ff")
  draw_big_text(x, y + 10, line2, "#ffe14d")
end

local function draw_training_history()
  local sw = emu.screenwidth()
  local sh = emu.screenheight()
  local rows = math.min(training.history_rows, #training.history)
  -- room for an arrow plus all six buttons (19 characters), a space and the frame count (4 characters)
  local width = 24 * CELL_W
  local x = math.max(4, sw - width - 6)
  local y = 55
  local bottom = math.min(sh - 2, y + 11 + rows * 10)
  if box_format == nil then draw_box(0, 0, 0, 0, "#00000000") end
  if box_format ~= "none" then draw_box(x - 3, y - 3, math.min(sw - 1, x + width + 1), bottom, "#000000d8") end
  draw_big_text(x, y, "P1 INPUTS", MENU_TITLE)
  for i = 1, rows do
    local entry = training.history[i]
    local line = string.format("%-20s%3dF", entry.text, math.min(999, entry.frames or 0))
    draw_big_text(x, y + 10 * i, line, i == 1 and MENU_SEL_VALUE or MENU_WHITE)
  end
end

if emu.registerafter then
  emu.registerafter(training.after_frame)
else
  log("emu.registerafter is unavailable; training health/meter tools disabled")
end

---------------------------------------------------------------- display
local big_menu_failed = false

emu.registerbefore(safe_tick)

-- emulator Lua Hotkeys: the callback only leaves a note; the action runs in the next frame's tick
local function lua_hotkey_fired(name)
  local gap = frame_count - (hk_last[name] or -1000)
  hk_last[name] = frame_count
  if gap > HOTKEY_REPEAT_FRAMES then hk_pending[name] = true end
end

local hotkeys_ok = true   -- false when this emulator has no Lua Hotkeys at all

local function register_lua_hotkeys()
  if not (input and input.registerhotkey) then
    hotkeys_ok = false
    log("this emulator has no Lua Hotkeys (input.registerhotkey), so the script cannot be controlled")
    return
  end
  local used = {}
  for n = 1, 9 do
    local name = LUA_HOTKEYS[n]
    if name then
      if not (name == "rec" or name == "play" or name == "stop" or name == "menu" or ACTIONS[name]) then
        log("Lua Hotkey", n, "has an unknown action:", name)
      else
        local ok, err = pcall(input.registerhotkey, n, function() lua_hotkey_fired(name) end)
        if ok then used[#used + 1] = n .. "=" .. name else log("Lua Hotkey", n, "failed:", err) end
      end
    end
  end
  if #used > 0 then log("Lua Hotkeys:", table.concat(used, "  "), "(map them in Input > Map Game Inputs)") end
end
local big_info_failed = false
gui.register(function()
  if not menu_open and training.settings.hitboxes then
    pcall(training.render_hitboxes)
  end
  if SHOW_TEXT then
    local y = TEXT_Y
  -- info line in the larger pixel font on a dark strip (falls back to the emulator's own text)
  local function info_line(x, y, str, color)
    if INFO_BIG_FONT and not big_info_failed then
      local ok = pcall(function()
        if box_format == nil then draw_box(0, 0, 0, 0, "#00000000") end
        if box_format == "none" then error("no gui.box") end
        if TEXT_COLORS then draw_box(x - 2, y - 2, x + #str * CELL_W - 1, y + 8, "#000000b4") end
        draw_big_text(x, y, str, color or "#ffffff")
      end)
      if ok then return end
      big_info_failed = true
    end
    draw_text(x, y, str, color)
  end

  local function line(str, color)
    info_line(TEXT_X, y, str, color)
    y = y + 10
  end

  if menu_open then
    local drawn = false
    if MENU_BIG_FONT and not big_menu_failed then
      drawn = pcall(menu_page == "motions" and draw_motions_big or menu_page == "training" and draw_training_big or draw_menu_big)
      if not drawn then big_menu_failed = true end   -- fall back to normal text from now on
    end
    if not drawn and menu_page == "motions" then
      line("MOTIONS   button: " .. motion_button_label(), "#ffe14d")
      line(MOTIONS[motion_i].cat .. "   " .. motion_i .. "/" .. #MOTIONS, "#c8d0ff")
      for row = motion_top, math.min(motion_top + MOTION_ROWS - 1, #MOTIONS) do
        local item = MOTIONS[row]
        local text = (row == motion_i and "> " or "  ") .. item.name
        local shown = motion_shown(item)
        if shown ~= "" then text = text .. "   " .. shown end
        line(text, row == motion_i and "#ffff66" or "#ffffff")
      end
      line("Up/Down choose   Left/Right button   LP load and play   LK back", "#c8d0ff")
    elseif not drawn and menu_page == "training" then
      line("TRAINING TOOLS", "#ffe14d")
      for i, row in ipairs(training.menu) do
        local text = (i == training.index and "> " or "  ") .. row.label
        local value = row.get()
        if value ~= "" then text = text .. ": " .. value end
        line(text, i == training.index and "#ffff66" or "#ffffff")
      end
      line("Up/Down choose   Left/Right change   LP select   LK back", "#c8d0ff")
    elseif not drawn then
      local rows, selected_idx = MENU_UI.current_menu()
      line(menu_page == "recording" and "PRACTICE MODE - RECORDING" or "PRACTICE MODE", "#ffe14d")
      local h1, h2 = menu_hints(rows[selected_idx])
      line(h1 .. "   " .. h2, "#ffffff")
      for i, row in ipairs(rows) do
        local text = (i == selected_idx and "> " or "  ") .. row.label
        local value = row.get and row.get() or ""
        if value ~= "" then text = text .. ":  " .. value end
        line(text, i == selected_idx and "#ffff66" or "#ffffff")
      end
    end
  else
    -- recording / playing line
    if mode == REC then
      line("REC  slot " .. cur, "#ff6666")
    elseif mode == PLAY then
      local str = "PLAY  slot " .. play_slot
      if wait > 0 then str = str .. "  wait " .. wait end
      line(str, "#66ff66")
    elseif mode == MOVE then
      local str = "PRESET  " .. MOTIONS[preset.i].name .. "  " .. preset_label()
      if wait > 0 then str = str .. "  wait " .. wait end
      line(str, "#ffdd66")
    end

    if SIDE.hud_on and (SIDE.cfg or SIDE.facing or mode == MOVE) then line(SIDE.hud(), "#9fd7ff") end

    -- settings: always (default), or briefly after a change
    if ALWAYS_SHOW_DETAILS or frame_count < info_until then
      local white = "#ffffff"
      line(string.format("loop:%s  mirror:%s  guard:%s",
        onoff(loop), onoff(mirror),
        guard_on and (guard_low and "low" or "high") .. "(" .. (SIDE.on() and "auto " or "") .. SIDE.guard() .. ")" or "off"), white)
      line(string.format("delay:%s  random slot:%s  savestate:%s",
        delay_label(), onoff(random_slot), onoff(use_state)), white)
      line("slots  " .. slot_summary(), white)
      if frame_count < hint_until then
        if hotkeys_ok then
          line(hotkey_hint(), white)
        else
          line("No Lua Hotkeys in this emulator", "#ff9966")
        end
      end
    end
  end

  if frame_count < notice_until then line(notice, "#ff9966") end
  end -- SHOW_TEXT

  if not menu_open and training.supported_rom then
    if training.supported_rom and training.settings.damage_counter then pcall(draw_training_damage) end
    if training.supported_rom and training.settings.input_history then pcall(draw_training_history) end
  end
end)

-- remembered menu settings (per game): loop, mirror, guard, savestate, delay, slot, last preset, side row
do
SIDE.settings_file = "record_play_" .. rom_name() .. "_settings.txt"
function SIDE.settings_snapshot()
  local m = MOTIONS[motion_i]
  return table.concat({
    "loop=" .. tostring(loop), "mirror=" .. tostring(mirror),
    "guard_on=" .. tostring(guard_on), "guard_low=" .. tostring(guard_low), "guard_dir=" .. tostring(guard_dir),
    "side_auto=" .. tostring(SIDE.auto), "use_state=" .. tostring(use_state),
    "delay=" .. tostring(delay_frames), "delay_random=" .. tostring(delay_random),
    "random_slot=" .. tostring(random_slot), "slot=" .. tostring(cur),
    "motion=" .. (m and m.name or ""), "motion_btn=" .. tostring(motion_btn),
    "side_hud=" .. tostring(SIDE.hud_on) }, "\n") .. "\n"
end
function SIDE.settings_load()
  local fh = io.open(SIDE.settings_file, "r")
  if not fh then return end
  for line in fh:lines() do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k then
      v = v:gsub("\r", "")
      local b = (v == "true")
      if k == "loop" then loop = b
      elseif k == "mirror" then mirror = b
      elseif k == "guard_on" then guard_on = b
      elseif k == "guard_low" then guard_low = b
      elseif k == "guard_dir" then if v == "Left" or v == "Right" then guard_dir = v end
      elseif k == "side_auto" then if SIDE.cfg or SIDE.facing then SIDE.auto = b end
      elseif k == "use_state" then use_state = b
      elseif k == "delay" then
        local n = tonumber(v)
        if n then delay_frames = math.max(0, math.min(DELAY_MAX, math.floor(n))) end
      elseif k == "delay_random" then delay_random = b
      elseif k == "random_slot" then random_slot = b
      elseif k == "slot" then
        local n = tonumber(v)
        if n and n >= 1 and n <= NUM_SLOTS then cur = math.floor(n) end
      elseif k == "motion" then
        for i, mm in ipairs(MOTIONS) do if mm.name == v then motion_i = i break end end
      elseif k == "motion_btn" then
        local n = tonumber(v)
        if n and n >= 1 then motion_btn = math.floor(n) end
      elseif k == "side_hud" then SIDE.hud_on = b
      end
    end
  end
  fh:close()
  log("settings loaded from", SIDE.settings_file)
end
pcall(SIDE.settings_load)
SIDE.settings_last = SIDE.settings_snapshot()
SIDE.settings_tick = function()
  if frame_count % 90 ~= 0 then return end
  local snap = SIDE.settings_snapshot()
  if snap == SIDE.settings_last then return end
  SIDE.settings_last = snap
  pcall(function()
    local fh = io.open(SIDE.settings_file, "w")
    if fh then fh:write(snap) fh:close() end
  end)
end
end

if AUTO_SAVE_TO_FILE then
  local ok, err = pcall(load_file)
  if not ok then log("load error:", err) end
end

pcall(register_lua_hotkeys)
if SIDE.cfg then
  log("side detection: on (P1 x at", string.format("0x%08X", SIDE.cfg.p1) .. ", P2 x at", string.format("0x%08X", SIDE.cfg.p2) .. ")")
else
  if SIDE.facing then
    log("side detection: on (from this game's own facing flag in the training-mode archive)")
  else
    log("side detection: no memory addresses for this game, the Side row stays Left / Right (see SIDE_SETTINGS)")
  end
end
log("loaded. slots:", slot_summary(), "| file:", SAVE_FILE)
say(training.short_status())
log("training tools:", table.concat(training.status_lines(), " | "))
