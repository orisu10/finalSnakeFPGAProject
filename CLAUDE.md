# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Intel/Altera **Quartus Prime 17.0 Lite** FPGA project targeting the **DE10‑Standard** board (Cyclone V `5CSXFC6D6F31C6`). It is a Technion Lab 1A (044157) final project: **"Slimming Snake"** — a Snake variant where the snake starts long and *shrinks* when it eats apples (cakes are a penalty that grow it). The design is being built by repurposing a provided "bouncing smiley + heart‑matrix" skeleton.

Top‑level entity: **`TOP_VGA_SNAKE`** (schematic `RTL/VGA/TOP_VGA_SNAKE.bdf`).

## Build / program

Quartus is not on PATH; prepend it first. Compile is slow (~10 min); Analysis & Elaboration (~2–3 min) is the fast way to check HDL + schematic changes before a full build.

```bash
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"

# Fast syntax/elaboration check (use this after every edit)
quartus_map --analysis_and_elaboration Lab1Demo

# Full compile -> output_files/Lab1Demo.sof
quartus_sh --flow compile Lab1Demo
```

There is no test suite. Verification is **on hardware**: program `output_files/Lab1Demo.sof` to the FPGA over **JTAG** (volatile — lost on power cycle), then look at the VGA monitor / 7‑segment displays / LEDs. The user compiles and programs from the Quartus GUI and reports what they see; iterate from that.

After a build, check results in `output_files/Lab1Demo.{map,fit,sta}.rpt` (search for `^Error`, `^Critical Warning`). Note a **pre‑existing `CLOCK_50` setup timing violation** exists in the audio/counter domain — it does **not** affect VGA (the 31.5 MHz PLL/pixel‑clock domain meets timing).

## Architecture

### Source layout
- Design is a **hybrid of `.bdf` schematics and `.sv` modules**. `.bdf` files are the wiring/top levels; leaf logic is SystemVerilog under `RTL/`.
- `RTL/VGA/` — video: VGA timing, the game board, background, object compositor. `RTL/AUDIO/` — JukeBox melody player. `RTL/KEYBOARDX/` — PS/2 keypad decode + pseudo‑random. `RTL/Seg7/` — 7‑seg. `*.mif` are ROM init files (background image, sprites).
- Quartus file list and **all pin assignments** live in `Lab1Demo.qsf`. Build artifacts (`db/`, `output_files/`, `*_sim/`) are gitignored.

### VGA rendering pipeline (the core to understand)
`VGA_Controller.sv` generates `pixelX/pixelY` (a moving raster scan), `startOfFrame` (one pulse/frame), and the packed `oVGA[28:0]` output (clock, blank, sync, HS/VS, and 24‑bit RGB to the on‑board video DAC). Mode is standard VESA **640×480 @ 72 Hz**, clocked by the **`CLK_31P5` PLL** (31.5 MHz) fed from `CLOCK_50`.

Each on‑screen object is a module that, given the current `pixelX/pixelY`, outputs a `drawingRequest` (is this pixel mine?) plus an 8‑bit `RGBout`. `objects_mux.sv` composites them by fixed priority (smiley > box > snake/hart layer > background > background‑ROM). A pixel value of **`8'hFF` means transparent** (fall through to the layer below). The composited byte goes back to `VGA_Controller` as `RGBIn`.

The whole pipeline is registered and runs on the pixel clock — keep added rendering logic in that clock domain and matched in latency.

### The game board (`RTL/VGA/HartsMatrixBitMap.sv`)
This module — still named `HartsMatrixBitMap` and instantiated via `RTL/VGA/HART_DISPLAY.bdf` — was the heart matrix and is now the **Snake board**. It is a **20×15 grid of 32×32 px tiles** (full screen). Data model:
- `snakeCol[i]/snakeRow[i]` + length — the ordered body. Movement = a **shift**: each segment takes the previous one's (x,y); the head advances one cell.
- `foodGrid` (apple/cake) kept **separate** from `snakeGrid` (head/body) so the snake gliding over food doesn't erase it; eating clears `foodGrid`. The two grids are composited at render time (snake over food over background).
- `snakeGrid` is updated incrementally each game tick (free tail cell, demote old head to body, set new head) so per‑pixel rendering is an O(1) grid lookup. A game tick is the pixel clock divided down (`TICK_DIV`).

Implementation order (see memory in `~/.claude`): 1–2 grid+render ✅, 3a auto‑movement ✅, 3b key control (8/2/4/6), then walls/self‑collision/game‑over, then eating/slimming + LFSR apple respawn, then audio‑on‑eat + 7‑seg score.

## Critical conventions and gotchas

- **`.bdf` edits are risky.** Adding/removing/renaming **ports** on a schematic symbol by hand corrupts the Block Editor (the files warn about this). **Parameter‑value‑only** edits (e.g. an `OBJECT_WIDTH_X` or a `MyConstant` value) are safe. The strong preference is to **keep SystemVerilog module port lists unchanged** so the schematic needs no rewiring — e.g. the board module kept the original heart module's exact ports. When a step genuinely needs new signals routed (e.g. keypad → board), treat the `.bdf` wiring as its own isolated, compile‑verified step.
- **VGA color byte mapping (verified on hardware):** `RED = bits[7:5], GREEN = bits[4:2], BLUE = bits[1:0]`. This is **swapped from what the `VGA_Controller.sv` comments imply** (the DE10 pin order). Known‑good: red `8'hE0`, green `8'h1C`, yellow `8'hFC`, magenta `8'hE3`, blue `8'h03`. `8'hFF` is reserved = transparent, so true white is unavailable.
- **`resetN` is KEY0 (active‑low, pin AJ4), not a power‑on reset.** Board/snake state is initialized in the `if(!resetN)` branch, and Cyclone V registers power up to 0 — so state only loads when reset is asserted. Keep init in the reset branch (mirroring the original modules).
- **Avoid module‑scope loop variables in `always_ff`** (they infer latches in Quartus). Declare loop vars locally: `for (int i = 0; ...)`.
- "Blank VGA screen" has historically been a **loose VGA cable**, not a code bug — sync/clock/pins are independent of the rendering logic. If the 7‑seg shows `0`, the FPGA is configured and the issue is downstream (cable/monitor); confirm the connection before debugging HDL.

## Git

Commit/push only when asked. The user works on `main`. The remote is `github.com/orisu10/finalSnakeFPGAProject`.
