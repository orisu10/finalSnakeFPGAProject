# Slimming Snake — System Design & Implementation

**Project:** Lab 1A (044157) final project, Spring 2026 — *Slimming Snake* on the DE10‑Standard FPGA.
**Variant:** the snake starts **long** and **shrinks** when it eats apples; cakes are a penalty that make it **grow**.

This document explains how the system is built, what was changed from the supplied skeleton, and — in detail — **how the snake moves**. It is written to be readable without deep FPGA knowledge.

---

## 1. The big picture

The game runs entirely in hardware on the FPGA. There is no processor and no software loop — every block below is a circuit that runs continuously. The screen is redrawn 72 times per second by scanning one pixel at a time; each circuit decides what color *its* object should be at the current pixel.

```
        ┌──────────────┐   keyPad[3:0]                    ┌────────────────────┐
 PS/2   │   KEYBOARD    │ ───────────────┐                │                    │
 keys ─▶│  (TOP_KBD)    │                │                │   VGA_Controller   │
        └──────────────┘                ▼                │                    │
                                ┌────────────────┐        │  generates the     │
        ┌──────────────┐        │  SNAKE BOARD   │        │  pixelX / pixelY   │
        │  CLOCK_50 ──▶ │  PLL   │ (HartsMatrix-  │◀───────│  scan + sync       │
        │  CLK_31P5     │ 31.5MHz│   BitMap)      │ pixelX │                    │
        └──────┬───────┘  clk   │                │ pixelY │                    │
               │                │ • snake state  │        │                    │
               │ clk            │ • movement     │        └─────────▲──────────┘
               ▼                │ • renders      │                  │ RGBIn
        (every block)          └───────┬────────┘                  │
                                        │ hartRGB / DrawingReq      │
        ┌──────────────┐                ▼                           │
        │  BACKGROUND  │──┐      ┌────────────────┐                 │
        │ (borders/img)│  └─────▶│  objects_mux   │─────────────────┘
        └──────────────┘  bgRGB  │ pick top layer │  RGBout (8‑bit)
        ┌──────────────┐         │ by priority    │
        │  SMILEY*     │────────▶│                │   *legacy block, removed
        └──────────────┘ smiley  └────────────────┘    once the snake takes over
```

**Signal flow in one sentence:** the VGA controller asks "what color is pixel (X,Y)?", every object answers, the **mux** picks the highest‑priority answer, and that color is sent to the monitor.

Top‑level schematic: `RTL/VGA/TOP_VGA_SNAKE.bdf`. The whole game board lives in one module: **`RTL/VGA/SnakeBoard.sv`**, wrapped by the sheet **`RTL/VGA/SnakeDisplay.bdf`** (these were renamed from the skeleton's `HartsMatrixBitMap.sv` / `HART_DISPLAY.bdf` to read clearly).

---

## 2. The board and its coordinate system

The screen is **640 × 480** pixels, divided into a grid of **20 columns × 15 rows** of **32 × 32‑pixel tiles** (20 × 32 = 640, 15 × 32 = 480).

```
        col 0    col 1            ...                       col 19
      ┌────────┬────────┬───── ... ───────┬────────┬────────┐
row 0 │        │        │                 │        │        │
      ├────────┼────────┼───── ... ───────┼────────┼────────┤
row 1 │        │        │                 │        │        │
      ├────────┼────────┼───── ... ───────┼────────┼────────┤
 ...  │                 each cell = 32×32 px                │
      ├────────┼────────┼───── ... ───────┼────────┼────────┤
row14 │        │        │                 │        │        │
      └────────┴────────┴───── ... ───────┴────────┴────────┘
```

To find which cell a pixel belongs to, the hardware just drops the low 5 bits of the coordinate (dividing by 32):

```
column = pixelX[9:5]      row = pixelY[8:5]
```

---

## 3. How the snake is stored (the data model)

The snake is kept in **two complementary forms** at the same time, because each is good at a different job:

### a) The body as an ordered list — used for *moving*

```
   index:   0      1      2      3      4      5      6      7
          ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐
snakeCol: │ 10 │ │  9 │ │  8 │ │  7 │ │  6 │ │  5 │ │  4 │ │  3 │
snakeRow: │  7 │ │  7 │ │  7 │ │  7 │ │  7 │ │  7 │ │  7 │ │  7 │
          └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘
            ▲                                                 ▲
           HEAD                                              TAIL
```

`snakeCol[i]` / `snakeRow[i]` hold the (x, y) of body segment *i*. Index 0 is always the **head**; the last used index is the **tail**.

### b) Two grids — used for *drawing* and *collision*

A list is awkward to draw from (you'd have to search it for every pixel). So the board also keeps two simple lookup grids, one value per cell:

- **`foodGrid`** — `EMPTY / APPLE / CAKE`. This is **static**: the snake sliding over food does not erase it. (Eating, added later, is the only thing that clears it.)
- **`snakeGrid`** — `EMPTY / HEAD / BODY`. This mirrors the body list and is updated a little bit on every step.

Keeping food and snake in **separate** grids is deliberate: it means the snake can pass over the board without destroying the apples underneath, and "eating" later becomes a single clean action (clear that one food cell).

---

## 4. How movement works ⭐

This is the heart of the system. Movement happens on a slow **game tick** (about 5 times per second), created by dividing down the fast 31.5 MHz clock with a counter. Between ticks nothing moves; the picture is just redrawn in place.

### The shift rule

On each tick, **every segment takes the position of the segment in front of it**, and the head advances one cell. That single rule makes the whole body follow the head:

```
 BEFORE the tick (head moving right ▶):

   tail                                   head
    3    4    5    6    7    8    9    10   →  (head wants col 11)
    ●────●────●────●────●────●────●────◆

 AFTER the tick:

         each segment copied the one ahead of it; head moved to 11
    4    5    6    7    8    9    10   11
    ●────●────●────●────●────●────●────◆
    ▲                                  ▲
   new tail (old col‑3 cell is now empty)   new head
```

In code this is literally a shift of the list plus one new head value:

```
for i from TAIL down to 1:        snake[i] <= snake[i-1]   // each takes the one before it
snake[0] <= next head cell                                  // head advances
```

### Keeping the picture in step

Because only the two ends change, the drawing grid is updated with just **three small writes per tick** (no need to redraw the whole snake):

```
   ┌─────────────────────────────────────────────────────────┐
   │ 1. free the OLD TAIL cell          snakeGrid[tail] = EMPTY│
   │ 2. old head becomes a body segment snakeGrid[head] = BODY │
   │ 3. mark the NEW HEAD cell           snakeGrid[next] = HEAD │
   └─────────────────────────────────────────────────────────┘
```

This is why the body appears to flow smoothly around corners: the head paints a new cell, the tail erases its oldest cell, and everything in between simply shifted.

### Steering with the keys

```
            8  (up)
             ▲
   4 ◀───────┼───────▶ 6        keyPad[3:0] = last number key pressed
  (left)     │      (right)
             ▼
            2  (down)
```

The keypad decoder outputs `keyPad[3:0]` = the **last number key pressed**, which is routed into the board (it arrives on the board's input port `dirKey`). The board decodes it into a direction and applies it on the next tick. Two safety rules:

1. **Only 8/2/4/6 change direction** — any other key is ignored, so the snake keeps going.
2. **No 180° reversal** — e.g. while moving right you cannot instantly choose left (that would fold the snake back into its own neck). The reversed request is dropped and the snake keeps its current heading.

### End of game (walls & self‑collision)

The game is a small state machine:

```
                          ┌──── hit wall / own body ───▶ ┌────────┐ (gray, ~1.5 s)
   ┌────────┐  load       │                              │  OVER  │──┐
   │  INIT  │ ──────▶ ┌────────┐                          └────────┘  │
   └────────┘         │  PLAY  │                                      │ auto-
        ▲             └────────┘                          ┌────────┐  │ restart
        │                 │     └──── slim to minimum ───▶ │  WIN   │──┤
        │                 move 1 cell / tick              └────────┘  │ (cyan, ~3 s)
        └──────────────────────────◀────────────────────────────────┘
```

- **Wall** — if the head's next step would leave the 20×15 board, that's a crash.
- **Self** — if the head's next cell is one of the snake's own body cells (`snakeGrid` lookup), that's a crash. The very **tail** cell is exempt (it vacates on the same tick).
- **OVER** — the snake **freezes and turns gray** for ~1.5 s, then the game **auto-restarts**.
- **WIN** — slimming the snake down to its **minimum length** wins: the snake turns **cyan** for ~3 s, then auto-restarts.

---

## 5. Food, eating and score ⭐ (step 5)

The "slimming" rules live here. Food sits in `foodGrid` (separate from the snake), and the head's **next** cell decides what happens:

```
   head steps onto ...     effect on the snake          other effects
   ─────────────────────   ──────────────────────────   ──────────────────────────
   APPLE  (red)            SLIMS  (one segment shorter)  score +1, and a new apple
                                                          appears at a random cell
   CAKE   (magenta)        GROWS  (one segment longer)   that cake is removed
   empty                   normal step (length same)     —
```

**One apple, always.** There is exactly one apple on the board. The instant it is eaten it is removed and a replacement is dropped on a random empty cell, so the player always has one apple to chase.

**Cakes accumulate.** The game starts with a single cake. A slow timer periodically adds another (on a random empty cell) up to a small cap, so the board gets gradually more crowded with penalties as play goes on — but never floods.

**Random cells come from an LFSR.** A *Linear-Feedback Shift Register* is a tiny circuit that produces a long pseudo-random stream of bits with almost no logic. It free-runs every clock; when a new apple/cake is needed, the current value is used as a candidate (column,row). If that cell is occupied or off-grid it is skipped and the next clock's value is tried — so food only lands on a free cell.

**Slimming vs growing — the tail trick.** Movement is still "every segment takes the place of the one before it"; only the number of freed tail cells changes:

```
   normal : head +1 , free 1 tail   → length unchanged
   apple  : head +1 , free 2 tails  → length − 1   (slims)
   cake   : head +1 , free 0 tails  → length + 1   (grows)
```

(The snake will not slim below a small minimum length.)

**Score & the on-screen number.** Each apple bumps a score counter; its value leaves the board on a new `score` output and is shown by the on-screen number, now fixed in the **top-left corner**. (It used to wander because its position was driven by a random generator; that generator is now pinned to a constant.) The bouncing smiley from the skeleton has been **removed** — the compositor simply no longer draws it.

### Getting faster (step 6)

The step interval starts at ~5 moves/second and **shrinks a little with every apple eaten**, so the snake speeds up **gradually** as you score — down to a fast floor (~21 moves/second). Cakes do not change the speed. (Each restart resets to the starting speed.)

### Two-digit score (step 6)

The score now counts **tens and ones** (00–99). Both digits leave the board on the 8-bit `score` output, and a single `NumbersBitMap` renders two digits side by side (left half = tens, right half = ones) in the top-left corner.

### Four game sounds (step 6)

The board talks to the existing **AUDIO** block with two wires:

- `soundSelect[3:0]` — *which* short tune to play (a different index per event),
- `soundTrigger` — a brief pulse meaning "start it now".

The audio's melody player picks a song from `songs.mif` by that index and plays it to the end, so each event gets a distinct sound:

```
   eat apple ─▶ melody 1        snake dies ─▶ melody 3
   eat cake  ─▶ melody 2        you win    ─▶ melody 4
```

`soundSelect` is **held** between events (so the chosen melody addresses cleanly the whole time it plays); the trigger is short and is caught by the audio when it is idle. These two wires were routed into the AUDIO block in place of the keypad, which used to make the beeps.

## 6. How a pixel becomes a color (rendering)

For the current pixel, the board looks up its cell in both grids and picks a color by priority — **snake on top of food on top of background**:

```
   is this cell a snake HEAD?  ── yes ─▶ YELLOW
   is this cell a snake BODY?  ── yes ─▶ GREEN
   is this cell an APPLE?      ── yes ─▶ RED
   is this cell a CAKE?        ── yes ─▶ MAGENTA
   otherwise                          ─▶ TRANSPARENT  (show the background)
```

A special value (`0xFF`) means **transparent**, telling the `objects_mux` to let a lower layer show through. The color byte format was measured on the real board:

```
   bit:   7  6  5 | 4  3  2 | 1  0
          └──RED──┘ └─GREEN─┘ └BLUE┘     e.g.  RED = 0xE0,  GREEN = 0x1C,  YELLOW = 0xFC
```

---

## 7. What was changed from the supplied skeleton

The starting point was a Technion demo: a bouncing "smiley" and a fixed matrix of hearts. The hearts block was already a *grid of tiles* engine — so it was the natural foundation for the snake board.

| Area | Original skeleton | Now (Slimming Snake) |
|------|-------------------|----------------------|
| `SnakeBoard.sv` (was `HartsMatrixBitMap.sv`) | 16×8 matrix of heart sprites, cleared on hit | **20×15 game board**: snake list + food/snake grids + movement + rendering |
| Board geometry | small box, offset on screen | full‑screen **20×15** board at the origin (set via schematic parameters, no rewiring) |
| Player | smiley with bouncing‑ball physics | **grid‑stepped snake** driven by the game tick |
| Control | Enter / 8 keys nudging the smiley | **8 / 2 / 4 / 6** keypad steering with anti‑reverse |
| Colors | heart palette | apple = red, cake = magenta, head = yellow, body = green (verified mapping) |
| Food | static hearts cleared on touch | **one apple** (slims + scores, LFSR respawn) + **accumulating cakes** (grow) |
| Smiley | bouncing smiley, top draw priority | **removed** from the display |
| On‑screen number | a digit at a **random** position | the **two‑digit score** (00–99), fixed **top‑left** |
| Speed | constant step rate | **gradually faster** with every apple eaten |
| Winning | (none) | **slim to the minimum length → win** (cyan screen) |
| Sound | keypad key‑press beeps | **4 distinct tunes**: apple / cake / die / win |

The **only schematic change** needed for control was routing the existing `keyPad[3..0]` net (from the keypad decoder) into the board block — done by adding one input port and connecting it by net‑name, the same way `clk` and `resetN` are wired.

---

## 8. Build status & roadmap

| Step | Description | Status |
|------|-------------|--------|
| 1–2 | 20×15 board renders snake + apples + cake | ✅ verified on board |
| 3a | Movement mechanic (auto‑crawl, body follows) | ✅ verified on board |
| 3b | Keypad control (8/2/4/6) + anti‑reverse | ✅ verified on board |
| 4 | Walls & self‑collision → game over, auto‑restart | ✅ verified on board |
| 5 | Eating (apple slims + scores, cakes grow & accumulate), LFSR respawn, score display, smiley removed | ✅ verified on board |
| **6** | **Gradual speed‑up, win screen, two‑digit score, 4 game sounds (apple/cake/die/win)** | **✅ built, compiled & flashed** |

---

### One‑paragraph summary for reviewers

The snake board is a single hardware block on a 20×15 tile grid. The snake body is stored as an ordered coordinate list; on each game tick every segment copies the position of the one ahead of it and the head advances one cell — that simple shift makes the body follow. A separate pair of lookup grids (food and snake) lets the display color each pixel by a fast cell lookup, with the snake drawn over the food over the background. The player steers with the 8/2/4/6 keys, with reversals blocked so the snake can't run into its own neck. The remaining work (collisions/game‑over, eating/slimming, sound and score) builds on this same grid‑and‑list foundation.
