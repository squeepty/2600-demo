# The Teeny-tiny Atari 2600 demo: Beginner's Design and Code Guide

This guide explains The Teeny-tiny Atari 2600 demo from the hardware level
upward. It assumes that you may be new to the Atari 2600, 6502 assembly, or
both. Release date: Thursday, July 16, 2026.

The most useful fact to keep in mind is this:

> The Atari 2600 does not store a finished screen anywhere. The program builds
> the picture one scanline at a time while the television is drawing it.

That constraint shapes the display kernel, the generated assets, the RAM
layout, and even where apparently simple color calculations are allowed to run.

## 1. What the Demo Does

The ROM presents a timed visual show with an independent two-channel soundtrack:

- animated top, middle, and bottom raster bars
- a large asymmetric `SQUEEPTY` playfield title
- static, type-on/type-off, horizontal-ripple, and vertical-wave title scenes
- four scene-specific 8-row player sprites that bounce in both axes
- a sparse reflected starfield behind the player
- four scene-specific animated checker patterns
- a compact, continuously scrolling `GREETINGS TO ALL ATARI DREAMERS...`
  ticker
- a 66.75-second `Take On Me` adaptation on the TIA's two audio channels
- progressive luminance fades between the normal visual scenes

The one-time introduction reveals one major component every 256 frames:

| Stage | `DemoFrame` range | Newly visible component |
| ---: | --- | --- |
| 1 | `$0000-$00FF` | Complete static title; raster bars are already present |
| 2 | `$0100-$01FF` | Checker/grid |
| 3 | `$0200-$02FF` | Bouncing sprite and starfield |
| 4 | `$0300-$03FF` | Scrolling ticker |

At `$0400`, the program goes directly to scene 2, the type-on/type-off scene.
It does not hold the fully revealed static scene for another 1,024-frame
interval. The first pass therefore continues through scenes 2, 3, and 4, then
wraps to the normal static scene. Every later 4,096-frame loop shows all four
scenes.

Music is derived from **Jukebox by Lloyd Russell**, published as a type-in in
**Your Sinclair issue 21, September 1987**, for the **ZX Spectrum 128K**. The
selected AY lead and bass voices were converted into compact, independent TIA
event streams. They update once per NTSC frame but do not reset at visual scene
boundaries.

There are no controls. After reset, the cartridge enters a permanent frame
loop and drives the entire presentation automatically.

## 2. Suggested Reading Order

If this is your first Atari 2600 program, use this order:

1. Read sections 3 through 7 of this guide.
2. Open `src/demo.asm` and read from the top through `Reset` and `Frame`.
3. Refer to the scanline table in section 8 while reading `DrawScreen`.
4. Read `UpdateState` and its four selection helpers:
   `UpdateIntro`, `UpdateTransition`, `UpdateTitleEffect`, and
   `LoadStarPattern`/`LoadSpriteFrame`.
5. Read `PositionPlayer`.
6. Read one visible effect at a time inside `DrawScreen`.
7. Read the `TakeOnMe_*` routines and `src/take_on_me_tia_data.inc` for audio.
8. Read `tools/gen_assets.py` after the playfield explanation makes sense.

You do not need to understand every CPU flag or cycle on the first pass. Start
by identifying what is prepared during blanking and what must happen while the
beam is visible.

## 3. The Four Main Pieces of Atari 2600 Hardware

### 3.1 The 6507 CPU

The console uses a MOS 6507. It is a reduced-pin version of the 6502 and runs
the same instructions used by this program.

The CPU has three general registers:

- `A`: the accumulator, used for arithmetic and most loads/stores
- `X`: an index register, often used for loops and scanline counters
- `Y`: another index register, often used to select table rows

It also has a stack pointer, a program counter, and status flags such as carry,
zero, and negative.

The CPU runs at approximately 1.19 MHz on an NTSC console. One scanline gives
the program only 76 CPU cycles.

### 3.2 The TIA

The Television Interface Adaptor produces the picture and sound. It has
registers for:

- vertical sync and blanking
- background color
- playfield bits and color
- two players, two missiles, and one ball
- horizontal positioning and motion
- two audio channels

The TIA has no framebuffer and almost no concept of vertical position. If a
sprite should appear on eight particular scanlines, the program must write its
graphics on those lines and write zero on the others.

### 3.3 The RIOT

The RIOT chip provides:

- 128 bytes of RAM
- console-switch and joystick I/O
- a programmable timer

This demo uses the timer to make the vertical blank and overscan regions the
right length. It does not read any controls.

### 3.4 The Cartridge

This is a plain 4 KB cartridge with no bank switching. Its ROM appears at
`$F000-$FFFF`, so all code and data are available at once.

## 4. Racing the Beam

A television image is drawn from left to right in horizontal scanlines. After
one line, the beam returns to the left and starts the next. After the last line,
vertical synchronization starts a new frame.

Modern software usually renders into a pixel buffer. An Atari 2600 kernel
instead changes TIA registers at carefully chosen times:

```text
start scanline
    write left-side playfield data
    wait a precise number of CPU cycles
    write right-side playfield data
end scanline
```

If code takes too long, a register update happens on the wrong side of the
screen or spills into the next scanline. This is why the title and ticker have
explicit delay instructions and page-aligned tables.

Raster colors are timing-sensitive too. The current top and middle kernels
calculate the next palette entry before `WSYNC`, then write the color just
after the next line starts. The bottom kernel calculates each later color on
the preceding scanline and caches its first color before entering the ticker.
Those arrangements keep both background and playfield color changes inside
horizontal blank and prevent a differently colored strip at the left edge.

### 4.1 `WSYNC`

`WSYNC` is the central timing register. Writing any value to it pauses the CPU
until the next scanline begins.

Code commonly looks like this:

```asm
.line
    sta WSYNC
    ; Work here happens near the beginning of a fresh scanline.
```

The value in `A` does not matter for `WSYNC`; only the write matters. Code
before the write belongs to the preceding line. Code after the write begins at
the left side of the new line.

## 5. Small 6502 Primer

### 5.1 Loads and Stores

```asm
lda #28         ; put the immediate value 28 in A
sta SpriteX     ; store A into the byte named SpriteX
ldx #0          ; put 0 in X
ldy #29         ; put 29 in Y
```

The `#` means “use this value.” Without it, the operand normally means “read
from this memory address.”

### 5.2 Arithmetic

```asm
clc             ; clear carry before ordinary addition
adc SpriteDX    ; A = A + SpriteDX + carry

sec             ; set carry before subtraction
sbc #15         ; A = A - 15 - inverse carry
```

On 6502, `ADC` and `SBC` always involve the carry flag. That is why `CLC` and
`SEC` appear immediately before many arithmetic operations.

The demo represents `-1` as `$FF`. In 8-bit two's-complement arithmetic:

```text
$20 + $FF = $1F
```

so adding `$FF` moves a coordinate backward by one.

### 5.3 Comparisons and Branches

```asm
cmp #130
bcc .checkLeft
```

`CMP` subtracts for flag purposes but does not change `A`. `BCC` means “branch
if carry is clear.” For an unsigned comparison after `CMP`, that corresponds
to “branch if A is less than the operand.”

Other branches used here include:

- `BNE`: branch if the result was not zero
- `BCS`: branch if carry is set
- `BMI`: branch if the negative flag is set
- `BPL`: branch if the negative flag is clear

### 5.4 Bit Operations

```asm
and #7          ; retain only the bottom three bits
ora #$0C        ; force selected bits to 1
eor #$80        ; toggle selected bits
lsr             ; shift right one bit
asl             ; shift left one bit
ror             ; rotate right through carry
rol             ; rotate left through carry
```

Power-of-two masks are used as inexpensive modulo operations:

```text
value AND 7    -> value modulo 8
value AND 15   -> value modulo 16
value AND 31   -> value modulo 32
value AND 63   -> value modulo 64
```

The ticker also uses `ROL` and `ROR` to move pixels through six encoded
playfield-register bytes while preserving the TIA's mixed bit directions.

### 5.5 Loops

```asm
ldx #6
.line
    ; do work
    dex
    bne .line
```

This loop executes six times. `DEX` subtracts one from X, and `BNE` repeats
until X becomes zero.

A loop ending in `BPL` often includes zero as a final index. For example,
starting X at 14 and decrementing through zero produces 15 iterations.

### 5.6 Subroutines

```asm
jsr UpdateState
...
UpdateState
    ; work
    rts
```

`JSR` pushes a return address onto the stack and jumps to a routine. `RTS`
returns to the instruction after the `JSR`.

## 6. DASM Syntax Used by the Project

The source is assembled by DASM.

| Syntax | Meaning |
| --- | --- |
| `processor 6502` | Select the 6502 instruction set |
| `NAME = $10` | Define a numeric constant |
| `SEG.U RAM` | Begin an uninitialized address segment |
| `SEG CODE` | Begin the ROM code/data segment |
| `ORG $F000` | Set the assembly address |
| `ds 30` | Reserve 30 bytes in an uninitialized segment |
| `byte ...` | Emit one or more bytes into ROM |
| `word Reset` | Emit a 16-bit little-endian address |
| `ALIGN 256` | Move to the next 256-byte boundary |
| `include "..."` | Assemble another file at this location |
| `<Label` | Low byte of a label's address |
| `>Label` | High byte of a label's address |

Labels beginning with a period, such as `.clear`, are local implementation
labels. Labels such as `Reset`, `UpdateState`, and `DrawScreen` identify major
routines.

## 7. Memory Map

### 7.1 RAM

The demo uses 76 of the console's 128 RAM bytes, `$80-$CB` inclusive.

| Address | Name | Size | Purpose |
| --- | --- | ---: | --- |
| `$80` | `FrameCounter` | 1 | Animation clock; wraps every 256 frames |
| `$81` | `Hue` | 1 | Shared hue nibble used to derive effect colors |
| `$82` | `SpriteX` | 1 | Horizontal player coordinate |
| `$83` | `SpriteDX` | 1 | Horizontal delta, `+1` or `$FF` (`-1`) |
| `$84` | `SpriteY` | 1 | Sprite top within the 40-line player region |
| `$85` | `SpriteDY` | 1 | Vertical delta, `+1` or `$FF` (`-1`) |
| `$86` | `ScrollTick` | 1 | Ten-frame ticker countdown |
| `$87-$88` | `ScrollPtr` | 2 | Pointer to the next packed ticker source column |
| `$89` | `CheckerForeground` | 1 | Foreground cached before the first checker scanline |
| `$8A` | `CheckerState` and aliases | 1 | Time-shared checker/title/ticker/bottom-bar scratch |
| `$8B-$A8` | `ScrollBuffer` | 30 | Current 5-row, 40-bit asymmetric ticker image |
| `$A9-$AA` | `DemoFrame` | 2 | 16-bit visual counter, normally `0-$0FFF` |
| `$AB` | `TopBarsLast` | 1 | Last top-bar X index; currently 14 |
| `$AC` | `TitleGapCount` | 1 | Gap lines compensating for top-bar height |
| `$AD` | `TitleFrame` | 1 | First row of the selected 7-row title phase |
| `$AE` | `TitleFrameEnd` | 1 | One-past-last row of the selected title phase |
| `$AF` | `ScenePattern` | 1 | Visual-table offset 0, 64, 128, or 192 |
| `$B0-$B7` | `SpriteBuffer` | 8 | Current scene's sprite copied from ROM |
| `$B8` | `TransitionStep` | 1 | Low byte of the 256-frame transition countdown |
| `$B9` | `TransitionMask` | 1 | Luminance mask applied throughout the kernel |
| `$BA` | `TransitionStepHi` | 1 | High byte used to represent countdown value 256 |
| `$BB-$C0` | `StarPtr0-2` | 6 | Three little-endian star-plane pointers |
| `$C1` | `StarMode` | 1 | Scene-specific star speed/direction mode |
| `$C2` | `IntroActive` | 1 | Nonzero only during the one-time reveal intro |
| `$C3` | `IntroStage` | 1 | Revealed-component level, 0 through 4 |
| `$C4-$C5` | `MusicPtr0` | 2 | Current melody event pointer |
| `$C6-$C7` | `MusicPtr1` | 2 | Current bass event pointer |
| `$C8` | `MusicTimer0` | 1 | Melody frames remaining |
| `$C9` | `MusicTimer1` | 1 | Bass frames remaining |
| `$CA` | `CheckerBackground` | 1 | Background cached before the first checker scanline |
| `$CB` | `CheckerHue` | 1 | Full-range grid hue clock changing every 32 frames |

The aliases at `$8A` are safe because their lifetimes do not overlap:

- `TitleBackground` is used in the title kernel.
- `ScrollBits` is scratch only while shifting ticker rows in VBLANK.
- `CheckerState` is initialized again before the checker kernel needs it.
- The star kernel temporarily uses the same byte for its vertical offset.
- `BottomBarColor` is stored after checker drawing and remains live through
  the ticker until the bottom-raster loop begins.

The stack starts at `$FF` and grows downward. The deepest path is
`Frame -> UpdateState -> TakeOnMe_Update -> channel decoder`; the decoder's
temporary `PHA` can bring stack use down to `$F9`. Ordinary state therefore
stays safely below `$CC`.

### 7.2 ROM

Addresses from the current build are:

| Address range | Contents | Bytes |
| --- | --- | ---: |
| `$F000-$F4DF` | Reset, frame loop, update routines, and display kernel | 1,248 |
| `$F4E0-$F4FF` | Alignment padding before indexed tables | 32 |
| `$F500-$F5E3` | Color, sprite, checker, and star tables | 228 |
| `$F5E4-$F675` | Frame-driven two-channel music player | 146 |
| `$F676-$FA80` | Melody and bass event streams | 1,035 |
| `$FA81-$FB2A` | Visual offsets, milestones, and transition masks | 170 |
| `$FB2B-$FBFF` | Alignment padding before generated title data | 213 |
| `$FC00-$FEED` | Six generated 119-byte title tables plus page padding | 750 |
| `$FEEE-$FF0B` | Generated 30-byte initial ticker image | 30 |
| `$FF0C-$FFB2` | Generated 167-byte packed ticker column stream | 167 |
| `$FFB3-$FFFB` | Currently unused ROM space | 73 |
| `$FFFC-$FFFF` | Reset and IRQ/BRK vectors | 4 |

Addresses move when code or data changes. `build/squeepty.sym` is the authority
for a particular build. The 4 KB size is fixed even though the amount of unused
space changes.

## 8. One Complete Video Frame

The main `Frame` routine produces exactly 262 NTSC scanlines.

| Region | Lines | What happens |
| --- | ---: | --- |
| VSYNC | 3 | Marks the start of a new television frame |
| VBLANK | 37 | Updates state, shifts ticker data when due, and positions player 0 |
| Visible | 192 | Runs `DrawScreen` |
| Overscan | 30 | Blanks the bottom and waits |
| Total | 262 | One NTSC frame |

### 8.1 VSYNC

The code sets bit 1 in both `VBLANK` and `VSYNC`, waits through three `WSYNC`
boundaries, then clears `VSYNC`. The display remains blank because `VBLANK`
stays enabled.

### 8.2 VBLANK Timer

Writing 44 to `TIM64T` starts a timer measured in 64-cycle units. The RIOT
decrements once immediately after the load, leaving 43 complete intervals:

```text
43 * 64 = 2752 CPU cycles
2752 / 76 = about 36.2 scanlines
```

While the timer runs, the code calls `UpdateState` and `PositionPlayer`. The
timer keeps counting during both routines. The CPU then polls `INTIM`, and a
final `WSYNC` aligns the region to 37 lines.

### 8.3 Visible Region

`DrawScreen` always accounts for 192 lines:

| Effect | Lines | Notes |
| --- | ---: | --- |
| Initial setup/partial line | 1 | Closed by the first top-bar `WSYNC` |
| Top bars | 15 | `TopBarsLast + 1` |
| Title | 42 | 7 bitmap rows times 6 scanlines |
| Title gap | 6 | Fixed gap below the title region |
| Sprite/star region | 40 | Still consumes 40 hidden lines early in the intro |
| Checker region | 32 | Still consumes 32 hidden lines during intro stage 1 |
| Middle bars | 12 | Fixed |
| Ticker | 25 | Still consumes 25 hidden lines before intro stage 4 |
| Bottom bars | 19 | Fixed |
| Total | 192 | Top bars plus title gap always total 21 lines |

`TopBarsLast + 1 + TitleGapCount` is 21. The vertical-wave scene animates letters inside
the fixed title region without changing the frame's total scanline count.

### 8.4 Overscan Timer

The code enables `VBLANK`, writes 36 to `TIM64T`, and waits. After the immediate
first decrement, 35 complete intervals remain:

```text
35 * 64 = 2240 CPU cycles
2240 / 76 = about 29.5 scanlines
```

The final `WSYNC` rounds overscan to 30 lines, then execution jumps back to
`Frame`.

## 9. Reset Walkthrough

### 9.1 CPU and Memory Setup

```asm
sei
cld
ldx #$FF
txs
```

- `SEI` disables maskable interrupts.
- `CLD` selects ordinary binary arithmetic.
- `TXS` initializes the stack pointer to `$FF`.

The following loop writes zero to every address from `$00` through `$FF`:

```asm
lda #0
ldx #0
.clear
    sta $00,x
    inx
    bne .clear
```

Those writes reset TIA registers and clear physical RAM at `$80-$FF`, giving
the program a predictable black, silent starting state.

### 9.2 Initial Animation and Intro State

The sprite starts at:

```text
X = 28
Y = 7
DX = +1
DY = +1
```

`IntroActive` is set to 1. All other intro and sequencer bytes remain zero from
the clear loop. On the first frame, `UpdateState` selects the static title,
static sprite/checker/star data, and a full-luminance transition mask before
anything is displayed.

### 9.3 Initial Ticker State

The generator emits two ticker representations:

- `ScrollInitial`: the first visible 40-column window, encoded as 30 bytes
- `ScrollColumns`: the full 167-column circular source stream

Reset copies `ScrollInitial` into `ScrollBuffer` and points `ScrollPtr` at
`ScrollNextColumn`, source column 40. Columns 0 through 39 are already on
screen, so column 40 is the next one to enter from the right.

`ScrollTick` starts at `SCROLL_INITIAL_DELAY`, which is one greater than the
normal delay. Because `UpdateState` runs before the first visible frame, that
extra count lets the initial window remain visible for the same ten rendered
frames as every later two-pixel position.

### 9.4 Player and Initial Audio State

`NUSIZ0=$05` selects a double-width player. Its source is still eight bits,
but each bit occupies two color clocks.

`TakeOnMe_Init` prepares audio without assuming one fixed TIA waveform. It
points `MusicPtr0` and `MusicPtr1` at their first events, sets both countdowns
to one, and writes zero to `AUDV0` and `AUDV1`. The first
`TakeOnMe_Update` call therefore loads intentional `AUDF`, `AUDC`, and
`AUDV` values immediately. Muting first prevents a reset-pitch chirp.

## 10. `UpdateState` Walkthrough

`UpdateState` runs once per video frame during VBLANK. Its high-level order is:

```text
increment FrameCounter and DemoFrame
update the one-time intro or wrap the normal show
select transition brightness
select the title scene and shared visual-table offset
select star mapping and copy the stage sprite to RAM
update hue
bounce the sprite horizontally and vertically
shift the ticker twice when its countdown expires
advance the independent melody and bass event timers once
```

Doing this work during VBLANK keeps variable-time preparation out of the
cycle-sensitive visible kernel.

### 10.1 The 4,096-Frame Visual Sequencer

`DemoFrame` is a little-endian 16-bit counter. Under normal operation it runs
from `$0000` through `$0FFF`, then wraps to zero. Each visual scene lasts
1,024 frames, about 17.07 seconds at 60 Hz.

| Scene | `DemoFrame` range | `ScenePattern` | Title behavior |
| --- | --- | ---: | --- |
| 1: Static | `$0000-$03FF` | 0 | Complete undistorted title |
| 2: Type | `$0400-$07FF` | 64 | Reveal 0/2/4/6/8 letters, then reverse to 2 |
| 3: Ripple | `$0800-$0BFF` | 128 | Eight generated horizontal ripple phases |
| 4: Vertical wave | `$0C00-$0FFF` | 192 | Independent four-phase vertical letter wave |

The one-time introduction occupies the numeric range normally belonging to
scene 1. At the `$0400` handoff, `UpdateIntro` clears `IntroActive`, leaves
`DemoFrame` at `$0400`, and marks all four intro components as revealed.
Consequently the first pass is intro, type, ripple, vertical wave. After the
counter wraps, subsequent passes are static, type, ripple, vertical wave.

This counter does not index or restart the soundtrack. The music streams run
on their own event pointers and frame countdowns.

### 10.2 One Component per Intro Stage

`IntroMilestoneLow` and `IntroMilestoneHigh` identify `$0100`, `$0200`,
and `$0300`. At those exact values, `IntroStage` increments:

- stage 0: title only, plus the raster framework
- stage 1: checker becomes visible
- stage 2: sprite and starfield become visible
- stage 3: ticker becomes visible
- stage 4: intro complete at the `$0400` handoff

Each interval is 256 frames, or roughly 4.27 seconds at 60 Hz. Hidden components
do not remove scanlines. Their kernels execute counted `WSYNC` loops of 40,
32, or 25 lines so the NTSC frame stays exactly 262 lines.

During the intro, `UpdateTitleEffect` holds `ScenePattern=0` and displays the
complete static title. Audio continues independently.

### 10.3 Scene Transitions

Normal scene changes use a 256-frame luminance fade centered on the 1,024-frame
boundary. A transition begins 128 frames before each boundary, at:

```text
$0380, $0780, $0B80, $0F80
```

`TransitionStepHi:TransitionStep` represents a countdown starting at 256.
`TransitionMasks` contains a 128-byte curve; each entry effectively lasts two
frames as the countdown is divided by two for indexing. The masks progress
through:

```text
$FE -> $FC -> $F8 -> $F0 -> $F8 -> $FC -> $FE
```

TIA color luminances use even-valued low bits. `AND TransitionMask` gradually
removes those luminance bits while retaining the high hue nibble. The scene
switch happens in the dark middle of the curve, then brightness returns.

During the introduction, `UpdateTransition` forces `$FE` every frame. That
prevents the transition scheduled at `$0380` from hiding the final reveal
stage, and the requested `$0400` handoff to scene 2 is immediate. Later normal
boundaries, including vertical-wave-to-static across the counter wrap, use the fade.

### 10.4 Title Scene Selection

`UpdateTitleEffect` begins with safe static defaults:

```text
TopBarsLast = 14       -> 15 top bars
TitleGapCount = 6      -> 6 gap lines
TitleFrame = 84
TitleFrameEnd = 91     -> complete seven-row reveal phase
ScenePattern = 0
```

It then selects a scene from `DemoFrame` unless the intro is active.

Type scene:

- selects `ScenePattern=64`;
- uses `(FrameCounter >> 4) AND 15` as a reveal-phase index;
- holds each selector entry for 16 frames;
- walks through 0, 2, 4, 6, 8 visible letters, then 6, 4, and 2.

Ripple scene:

- selects `ScenePattern=128`;
- uses `(FrameCounter >> 3) AND 7`;
- holds each generated ripple phase for 8 frames;
- completes one ripple cycle every 64 frames.

Vertical-wave scene:

- selects `ScenePattern=192`;
- uses `(FrameCounter >> 4) AND 3` to select one of four generated vertical
  letter-wave phases, holding each for 16 frames;
- keeps the enclosing title region and its compensating gap fixed.

### 10.5 Scene Sprite, Stars, and Checker

`LoadSpriteFrame` converts `ScenePattern` values 0, 64, 128, and 192 into ROM
offsets 0, 8, 16, and 24. It copies the selected eight-byte bitmap to
`SpriteBuffer`. The visible kernel can then use a fast nearby indexed load even
when the player is close to the left edge.

The four sprites are:

- static: alien/diamond
- type: square digital robot
- ripple: symmetric flying saucer/UFO
- vertical wave: symmetric space jellyfish

`LoadStarPattern` selects three pointers into `StarPF0`, `StarPF1`, and
`StarPF2`. All tables share one ROM page, so their high address byte is common.
Each scene permutes which sparse plane feeds which playfield register:

| Scene | PF0 pointer | PF1 pointer | PF2 pointer | Vertical movement |
| --- | --- | --- | --- | --- |
| Static | `StarPF0` | `StarPF1` | `StarPF2` | Forward, 1 row per 4 frames |
| Type | `StarPF1` | `StarPF2` | `StarPF0` | Forward, 1 row per 2 frames |
| Ripple | `StarPF2` | `StarPF0` | `StarPF1` | Forward, 1 row per frame |
| Vertical wave | `StarPF0` | `StarPF2` | `StarPF1` | Reverse, about 1 row per 2 frames |

Each star plane is 32 rows. The visible 40-line region indexes
`(line + offset) AND 31`, so the map wraps for the last eight lines. `CTRLPF=1`
reflects the sparse 20-bit pattern across the full screen.

The checker also has four scene-specific pairs. `ScenePattern >> 5` produces
pair bases 0, 2, 4, and 6. `(FrameCounter >> 2) AND 1` chooses the initial
member of the pair, and the kernel toggles between the two members every four
scanlines.

### 10.6 Frame Counter, Hue, and Sprite Bounce

`FrameCounter` increments every frame and naturally wraps after 255.

Every eighth frame, the program advances `Hue` by `$10` and masks it with
`$F0`. The high nibble selects a TIA hue family; visible effects add their own
luminance and hue offsets later.

The sprite position updates every frame:

```text
SpriteX = SpriteX + SpriteDX
SpriteY = SpriteY + SpriteDY
```

The horizontal tests select `-1` at X values greater than or equal to 130 and
select `+1` when X is less than 14. Because the new coordinate is stored before
the test, the actual inclusive range is 13-130: a left-moving sprite reaches
13, changes direction, and moves back to 14 on the next frame.

The vertical tests work the same way: select `-1` at Y values greater than or
equal to 32 and `+1` below 1. The actual inclusive range is therefore 0-32. An
8-row sprite starting at 32 occupies region lines 32-39 exactly, while Y=0
places it at the top of the region.

### 10.7 Compact Runtime Ticker

The current implementation does not store every 30-byte ticker frame in ROM.
It stores:

- one 30-byte encoded starting window;
- one 167-byte circular stream, one byte per source column.

Every frame, `ScrollTick` decrements. When it reaches zero, the code reloads
10 and calls `.shiftScrollOne` twice. The display therefore advances two
logical playfield pixels every ten video frames.

Each packed source byte uses bits 4 through 0 for ticker rows 0 through 4.
`.shiftScrollOne` fetches one byte, advances the 16-bit pointer, and wraps it at
`ScrollColumnsEnd`.

For each of five rows, the shifter rotates through the buffer's six register
blocks. The directions alternate because the TIA displays PF0, PF1, and PF2 in
different bit orders. A five-`ASL` bridge extracts right PF0's old visible bit
4 and carries it into left PF2. PF0's unused low nibble may collect discarded
bits, but the TIA never displays those bits.

The message is 167 logical columns wide. Because the code advances by two and
167 is odd, it visits every possible starting column and returns to the exact
initial phase after 167 updates:

```text
167 updates * 10 video frames = 1,670 frames
1,670 / 60 = about 27.8 seconds
```

At approximately 60 Hz, its linear speed remains:

```text
2 pixels / 10 frames * 60 frames/second = 12 pixels/second
```

### 10.8 Independent Melody and Bass Update

`UpdateState` calls `TakeOnMe_Update` once per NTSC frame. It decrements
`MusicTimer0` and `MusicTimer1` separately. When one reaches zero, only that
channel loads its next three-byte event:

1. duration in frames;
2. `AUDF` frequency divider;
3. packed `(AUDC << 4) | AUDV`.

The decoder writes the low nibble to volume and shifts the high nibble down for
the control/waveform register. It then advances that channel's 16-bit pointer
by three. A zero duration is an end marker: the channel pointer returns to its
own stream start and decoding continues from the first event.

The channels can therefore change on different frames. Both streams total
4,005 frames and loop after 66.75 seconds, but neither depends on
`FrameCounter`, `DemoFrame`, or `ScenePattern`. Lower `AUDF` divider values
generally sound higher for a fixed `AUDC` mode, but TIA divider values are not
standard MIDI notes.

## 11. Horizontal Player Positioning

The TIA has no ordinary `PlayerX` register. Writing to `RESP0` resets player
0's horizontal counter at the beam's current position. The timing of that
write determines coarse X position.

`PositionPlayer` consumes two VBLANK scanlines and works in two parts.

### 11.1 Coarse Position

After a `WSYNC`, the routine sets carry and repeatedly subtracts 15:

```asm
    sta WSYNC
    sec
.divide
    sbc #15
    bcs .divide
```

Each loop spends time corresponding to a horizontal step. More loops delay the
`RESP0` strobe and place the player farther right.

`SEC` deliberately executes after `WSYNC`. Besides preparing the first `SBC`,
its two cycles keep the smallest `RESP0` strobes out of the TIA's special
horizontal-blank timing case. This prevents a jump at the coarse/fine boundary
near the left bounce.

### 11.2 Fine Position

The underflowed remainder is converted to the signed fine-motion format used
by `HMP0`:

```asm
eor #7
asl
asl
asl
asl
sta HMP0
```

The useful motion nibble belongs in bits 7-4, explaining the four left shifts.
The routine writes `RESP0` for coarse positioning, waits for another line, and
strobes `HMOVE` to apply the fine correction.

## 12. Playfield Fundamentals

The playfield has 20 programmable bits:

```text
PF0: 4 visible bits
PF1: 8 visible bits
PF2: 8 visible bits
total: 20 bits
```

Each logical playfield bit is four color clocks wide on the 160-color-clock
visible screen.

The display order is unusual:

```text
PF0 bits: 4, 5, 6, 7
PF1 bits: 7, 6, 5, 4, 3, 2, 1, 0
PF2 bits: 0, 1, 2, 3, 4, 5, 6, 7
```

This mixed direction is why `tools/gen_assets.py` has explicit encoding logic
and why the runtime ticker shifter alternates rotate directions.

### 12.1 Repeat or Reflection

The same 20 bits normally create both screen halves:

- `CTRLPF` bit 0 clear: repeat the pattern on the right
- `CTRLPF` bit 0 set: reflect the pattern on the right

The checker and starfield use reflection because symmetry is useful and cheap.

### 12.2 Asymmetric 40-Bit Playfield

The title and ticker need 40 unique bits. They rewrite the registers near the
middle of each scanline:

```text
early scanline:
    PF0 = left PF0
    PF1 = left PF1
    PF2 = left PF2

near screen center:
    PF0 = right PF0
    PF1 = right PF1
    PF2 = right PF2
```

By the time the right values are written, the TIA has already drawn the left
half.

The common ticker path uses six `NOP` instructions for a 12-cycle delay. The
title writes its cached background at cycle 3, then uses `BIT` plus three
`NOP`s for a 9-cycle delay. That three-cycle reduction compensates for the
background write and keeps the right-half writes aligned.

Both common repeated paths take about 59 cycles after `WSYNC`, within the
76-cycle scanline budget. Exact page placement still matters because some
indexed loads gain a cycle when they cross a 256-byte boundary.

## 13. `DrawScreen` Effect by Effect

### 13.1 Setup Line

`DrawScreen` first clears PF0, PF1, PF2, `CTRLPF`, and `GRP0`. The first top-bar
`WSYNC` ends this partial setup line. It is the first of 192 visible lines.

### 13.2 Top Raster Bars

For each line:

```text
palette index = (line counter + FrameCounter) AND 31
```

The 32-byte `Rainbow` table supplies the color. Advancing `FrameCounter` shifts
the palette every frame.

Crucially, the index and table load happen before `WSYNC`. `COLUBK` is written
immediately after `WSYNC`, in horizontal blank. In every scene, X runs 14
through 0 for 15 lines.

Every raster color is masked through `TransitionMask` before display.

### 13.3 Large Title

The title has seven source rows, each repeated six times:

```text
7 source rows * 6 = 42 visible scanlines
```

`TitleFrame` and `TitleFrameEnd` select one contiguous seven-row phase from the
generated tables. Six arrays provide left and right PF0/PF1/PF2 bytes:

```text
TitlePF0L  TitlePF1L  TitlePF2L
TitlePF0R  TitlePF1R  TitlePF2R
```

The foreground derives from `Hue EOR $80 OR $0C`; the background derives from
`Hue OR $02`. Both pass through `TransitionMask`. The background is cached in
`TitleBackground`, written at cycle 3 of every title line, and later reused as
checker scratch.

The left playfield values are written first. `BIT TitleBackground` and three
`NOP`s delay the right-half rewrite without changing registers needed by the
kernel.

### 13.4 Compensating Title Gap

Every gap line clears the playfield and background. The gap is six lines in
all four scenes. The vertical-wave effect uses precomputed letter phases inside
the same fixed seven-row title region, so it does not alter scanline totals.

### 13.5 Bouncing Player and Starfield

The region has a software line counter from 0 through 39. Every line begins by
clearing `GRP0`, then computes:

```text
bitmap row = current line - SpriteY
```

If the unsigned result is 0-7, that row of `SpriteBuffer` is written. A result
of 8 or greater draws no player. Subtraction underflow before the sprite also
becomes a large unsigned value, so the same comparison handles both outside
regions.

After the time-critical player write, the kernel indexes all three star
pointers and writes PF0/PF1/PF2. Reflection turns the sparse 20-bit data into a
full-width background. The player and star colors use separate hue offsets,
and both are transition-masked.

During intro stages 0 and 1, a 40-`WSYNC` hidden path replaces this drawing but
preserves the region height.

### 13.6 Scene-Specific Checker

The checker uses one of four complementary table pairs:

- static: classic alternating checks
- type: digital blocks
- ripple: narrow travelling bands
- vertical wave: chunky blocks

The selected pair alternates every four scanlines, producing eight visible
checker rows across 32 lines. Its initial member changes every four video
frames. `CTRLPF=1` reflects each 20-bit row across the screen.

X counts down from 32. After drawing the final line, the kernel branches to
the middle-raster setup before performing an unnecessary phase toggle. This
short exit leaves enough scanline time to calculate the first raster color
without modifying the checker's still-visible right edge.

Checker foreground and background colors are calculated before entering the
region but are written only after each line's `WSYNC`. This is important: an
earlier version changed `COLUPF` on the final starfield line, recoloring its
latched right-half playfield and creating a stray half-width stripe. After the
two color writes, PF0/PF1/PF2 still arrive before their left-half fetch windows;
`GRP0` is cleared and reflection enabled before the screen midpoint. During
intro stage 0, a 32-line hidden path preserves timing instead.

### 13.7 Middle Raster Bars

The 12 middle bars use:

```text
palette index = (line counter * 2 + FrameCounter) AND 31
```

Doubling the line counter samples every other palette entry for a steeper
gradient. As in the corrected top raster, calculation happens before `WSYNC`
and the masked `COLUBK` write happens just after it, avoiding partial-line
color changes. PF0/PF1/PF2 and reflection are cleared immediately after that
write, still during horizontal blank of the new raster line. Clearing them on
the preceding checker line would erase the right edge of its final row.

### 13.8 Ticker

The ticker has five source rows, each expanded to five scanlines:

```text
5 source rows * 5 = 25 visible scanlines
```

`ScrollBuffer` is register-major:

| Offsets | Values |
| --- | --- |
| `0-4` | Left PF0 for rows 0-4 |
| `5-9` | Left PF1 for rows 0-4 |
| `10-14` | Left PF2 for rows 0-4 |
| `15-19` | Right PF0 for rows 0-4 |
| `20-24` | Right PF1 for rows 0-4 |
| `25-29` | Right PF2 for rows 0-4 |

With Y as a row number, fixed offsets select all six register values without
multiplication or visible-time pointer arithmetic.

The first ticker line has a specialized entry path. It preloads left PF0,
crosses `WSYNC`, writes black to `COLUBK` at cycle 3, and uses five `NOP`s plus
a `JMP` to join the common right-side path at the correct cycle. Later lines
use the normal six-`NOP` path.

Before entering the ticker, the kernel also calculates the first bottom-bar
color and caches it in the `$8A` alias `BottomBarColor`. The ticker's final line
is too cycle-tight to calculate that color before its closing boundary. During
intro stages 0-2, a 25-line hidden path skips ticker graphics but retains this
setup and the exact frame height.

### 13.9 Bottom Raster Bars and the Alignment Fix

The bottom border contains 19 lines from `RainbowReverse`. The first color,
for X=18, was cached before the ticker. Each bottom line:

1. crosses `WSYNC`;
2. writes the same cached color to `COLUBK` and `COLUPF` in horizontal blank;
3. calculates the next line's color before the next `WSYNC`.

Making foreground and background equal hides the ticker bits that remain
latched in PF0/PF1/PF2. More importantly, calculating colors on the preceding
line ensures both color writes occur at the left edge of every raster line.
This is the timing fix that removes the former horizontal misalignment of the
lower raster bands.

An additional `WSYNC` closes the nineteenth line exactly before `Frame`
enables overscan blanking.

## 14. Asset Generation

`tools/gen_assets.py` converts readable bitmap fonts into the unusual bit
ordering required by TIA playfield registers.

### 14.1 Font Representation

A title glyph is written as strings:

```python
"S": (
    "1111",
    "1000",
    "1000",
    "1111",
    "0001",
    "0001",
    "1111",
)
```

Each character in a row is one logical playfield pixel. `"1"` means on and
`"0"` means off. The title uses 4-by-7 glyphs; the ticker uses 3-by-5 glyphs.
`text_rows` concatenates glyphs and adds one blank column between characters.

Eight four-pixel title letters plus seven one-pixel gaps occupy 39 pixels. A
leading blank column makes the undistorted phase exactly 40 pixels wide.

### 14.2 Encoding 20- and 40-Bit Rows

`encode_half` splits 20 left-to-right pixels into PF0, PF1, and PF2 while
accounting for each register's display order. `encode_row` pads or clips to 40
pixels, encodes both halves, and returns:

```text
left PF0, left PF1, left PF2, right PF0, right PF1, right PF2
```

The generator is the single source of truth for this encoding. Generated
`build/assets.inc` should never be edited by hand.

### 14.3 Generated Title Phases

`generate_title` creates 17 phases:

- 8 ripple phases, each with seven row-specific horizontal offsets
- 5 reveal phases containing zero, two, four, six, or eight complete letters
- 4 vertical-wave phases with independent per-letter row offsets

Each of the six register-specific tables therefore contains:

```text
17 phases * 7 rows = 119 bytes
```

The generator transposes phase/row data into the six arrays expected by the
kernel. It places two 119-byte tables per ROM page and aligns before the next
pair. A table beginning at page offset `$77` and indexed no farther than `$76`
ends at `$ED`, so none of the title's absolute-indexed loads crosses a page.
This preserves constant kernel timing.

### 14.4 Compact Ticker Output

`generate_scroll` builds the five complete message rows. The current 42
characters use:

```text
42 glyphs * 3 columns + 41 spaces = 167 columns
```

It emits:

- `ScrollInitial`: source columns 0-39 encoded into the 30-byte RAM layout
- `ScrollColumns`: all 167 source columns packed vertically into 167 bytes
- `ScrollNextColumn`: a label at source column 40
- `ScrollColumnsEnd`: the pointer wrap boundary
- `SCROLL_COLUMN_COUNT = 167`: generated metadata

Keeping all columns, including the first 40, makes the source circular after
the initial pass. Runtime shifting replaces the old design that stored every
30-byte animation frame, dramatically reducing ROM use.

## 15. Timing and Animation Rates

Approximate rates at 60 video frames per second:

| Animation | Update interval | Approximate behavior |
| --- | --- | --- |
| Raster palette offset | 1 frame | 60 palette shifts/second |
| Sprite X/Y | 1 frame | 60 position steps/second |
| Vertical-wave title | 16 frames | 4 phases; 64-frame cycle |
| Ripple title | 8 frames | 8 phases; 64-frame cycle |
| Hue | 8 frames | 7.5 hue changes/second |
| Ticker | 10 frames | 2 pixels/update; 12 pixels/second |
| Type title selector | 16 frames | 16-entry forward/backward cycle |
| Music event timers | 1 frame | Independent duration countdowns at 60 Hz |
| Checker initial phase | 4 frames | 15 phase changes/second |
| Checker hue | 32 frames | Half-speed color changes; 512-frame full cycle |
| Static stars | 4 frames/row | Slow forward drift |
| Type stars | 2 frames/row | Medium forward drift |
| Ripple stars | 1 frame/row | Fast forward drift |
| Vertical-wave stars | About 2 frames/row | Medium reverse drift |
| Intro component | 256 frames | One component per reveal stage, about 4.27 seconds |
| Normal scene | 1,024 frames | About 17.07 seconds |
| Soundtrack loop | 4,005 frames | 66.75 seconds, independent of scenes |
| Full normal loop | 4,096 frames | Four scenes, about 68.27 seconds |
| Scene fade | 256 frames | About 4.27 seconds, centered on boundary |

`FrameCounter` wraps every 256 frames, about 4.27 seconds. `DemoFrame` wraps
every 4,096 frames after the one-time intro logic is disabled.

## 16. Color and Fade Design

An NTSC TIA color byte is organized approximately as:

```text
HHHH LLLx
```

- the high nibble selects hue
- the lower useful bits select luminance
- the lowest bit is not significant for ordinary color selection

The demo maintains one shared `Hue` and derives related colors with `EOR` and
`ORA`. For example:

```asm
lda Hue
eor #$80
ora #$0C
and TransitionMask
sta COLUPF
```

This offsets the hue, requests a bright luminance, then applies the current
fade. Raster-table colors are masked the same way, so title, player, stars,
checker, ticker, and all three raster groups fade together.

`$FE` preserves all meaningful TIA color bits. `$FC`, `$F8`, and `$F0`
successively remove luminance while leaving hue. At `$F0`, colored objects can
retain a dark hue tint rather than becoming a mathematically all-zero byte;
the perceptual result is the intentionally dark center of the transition.

PAL and SECAM systems interpret colors and frame timing differently. This ROM
is intentionally NTSC.

## 17. Audio Design

TIA provides two audio channels. Each has:

- an `AUDC` waveform/control register
- an `AUDF` frequency divider
- an `AUDV` volume register

The soundtrack is a 66.75-second, two-channel TIA adaptation of `Take On Me`.
Music is derived from **Jukebox by Lloyd Russell**, published as a type-in in
**Your Sinclair issue 21, September 1987**, for the **ZX Spectrum 128K**. The
recovered source uses the Spectrum 128K's AY sound chip; the conversion selects
one lead voice for TIA channel 0 and one bass voice for TIA channel 1. AY
noise-only percussion is omitted because both TIA voices are reserved for pitch.

The two streams are stored in `src/take_on_me_tia_data.inc`. Every event is
three bytes:

~~~text
duration_in_60Hz_frames, AUDF, (AUDC << 4) | AUDV
~~~

Duration is a frame countdown, not a musical note index. `AUDF` selects the
pitch divider. The final byte packs the four-bit waveform/control and four-bit
volume values. A record whose duration is zero marks the end and loops that
channel to its beginning.

The melody contains 168 events plus its marker, occupying 507 bytes. The bass
contains 175 events plus its marker, occupying 528 bytes. Both add to 4,005
frames, so they loop together after 66.75 seconds even though events within the
streams can end on different frames. Conversion used cumulative duration
rounding to prevent long-term tempo drift.

`TakeOnMe_Init` establishes the pointers, gives each timer a value of one, and
mutes both channels. `TakeOnMe_Update` runs once per frame. Most calls merely
decrement two bytes; a decoder runs only when one expires. It separates the
packed register byte, writes that channel's TIA registers, advances its pointer
by three, and handles the zero-duration loop marker.

TIA tones are hardware divider and polynomial modes, not equal-tempered MIDI
notes. Smaller `AUDF` values generally mean higher pitch only when `AUDC`
stays fixed. Stella or real NTSC hardware is the final authority for timbre and
tuning because TIA's polynomial waveforms and analog output are distinctive.

## 18. Build Pipeline

Running `make` performs these steps:

```text
tools/gen_assets.py -> build/assets.inc --------+
src/take_on_me_tia_data.inc --------------------+--> src/demo.asm
                                                       |
                                                       v
                                                     DASM
                                                       |
                                        +--------------+----------+
                                        v              v          v
                                    ROM image       listing    symbol map
```

Files:

- `downloads/squeepty-2600-demo.bin`: 4,096-byte cartridge image
- `build/squeepty.lst`: source mixed with addresses and machine-code bytes
- `build/squeepty.sym`: label-to-address map
- `build/assets.inc`: generated playfield data
- `src/take_on_me_tia_data.inc`: hand-included compact music event data

Commands:

```sh
make
make check
make release
```

`make check` verifies the ROM size and prints its SHA-256 hash. `make release`
rebuilds and validates the distributable ZIP.

To launch the current ROM in a separate Stella instance on macOS:

```sh
open -na Stella --args "$PWD/downloads/squeepty-2600-demo.bin"
```

## 19. Safe Experiments

### 19.1 Change Scroll Speed

`SCROLL_DELAY` is the number of video frames between two-pixel advances:

```asm
SCROLL_DELAY         = 10
SCROLL_INITIAL_DELAY = SCROLL_DELAY + 1
```

Smaller values scroll faster. Keep the initial value defined as the regular
delay plus one because state updates happen before rendering.

| `SCROLL_DELAY` | Two-pixel advance | Speed at 60 Hz |
| ---: | ---: | ---: |
| 8 | every 8 frames | 15 pixels/second |
| 10 | every 10 frames | 12 pixels/second |
| 12 | every 12 frames | 10 pixels/second |
| 16 | every 16 frames | 7.5 pixels/second |

### 19.2 Change the Ticker Message

Edit the `message` string in `generate_scroll` inside `tools/gen_assets.py`.
Every character must exist in `TICKER_FONT`; add a 3-by-5 glyph if necessary.

Each additional 3-pixel character normally adds four packed source bytes:
three glyph columns and one inter-character gap. The 30-byte initial window
does not grow. The source must remain wider than 40 columns, as enforced by the
generator.

Run `make` after any generator change.

### 19.3 Change a Scene Sprite

Edit the corresponding eight rows under `SpriteBitmaps`:

```text
bytes 0-7    static
bytes 8-15   type
bytes 16-23  ripple UFO
bytes 24-31  vertical wave
```

Keep each bitmap at eight bytes unless you also change the copy routine, the
`CMP #8` visible test, and the vertical bounce limit.

### 19.4 Change Sprite Size

Edit the value stored in `NUSIZ0`. Other values choose normal, double, or
quadruple width and multiple-copy modes. Recalculate horizontal bounce limits
if the visible width changes.

### 19.5 Change Title Effects

For ripple shape, edit `ripple_offsets` in `generate_title`. Keep eight phases
of seven row offsets unless the runtime `RippleFrameOffsets` table and masks
change too.

For the type sequence, edit `RevealFrameOffsets` in assembly. Valid generated
reveal phases begin at row offset 56 and advance in steps of seven through 84.
The 16 selector entries reuse those five phases to build the forward/backward
cycle.

For vertical-wave motion, edit the four phase definitions in
`generate_title` or reorder their row bases in `VerticalFrameOffsets`. Each
phase must remain seven rows so `TitleFrameEnd = TitleFrame + 7` stays valid.

### 19.6 Change Colors

The safest color experiments are:

- edit the 32-byte `Rainbow` and `RainbowReverse` tables;
- change constants ORed into `Hue`;
- change hue offsets applied with `EOR`.

Keep both raster tables at 32 bytes unless all `AND #31` indexing masks change.
Keep `AND TransitionMask` in every scene-colored path if the whole image should
continue to fade together.

### 19.7 Change Music

The shipped event bytes live in `src/take_on_me_tia_data.inc`. Each channel is
a sequence of three-byte records:

~~~text
duration, AUDF, (AUDC << 4) | AUDV
~~~

Keep every duration in the range 1-255 and end each channel with
`$00,$00,$00`. Update the `TAKE_ON_ME_MELODY_BYTES` and
`TAKE_ON_ME_BASS_BYTES` constants when lengths change. The player advances
pointers by exactly three bytes and treats the first zero duration as the loop
marker, so a missing or misaligned field will make it read unrelated ROM data.

The two streams need not have matching event boundaries. If they should loop
together, make the sum of all nonzero durations equal in both. ROM capacity is
tight: only 73 bytes remain before the vectors in the current build.

For a different generated arrangement, preserve the event format or update both
decoders. Keep `TakeOnMe_Update` called once per NTSC frame unless every
duration is regenerated for another update rate.

### 19.8 Change Checker or Star Patterns

Checker tables contain two entries per scene in static/type/ripple/vertical-wave order.
Keep PF0/PF1/PF2 entries paired and keep the total at eight per table unless
the stage-base calculation changes.

Each star plane must remain 32 bytes while the kernel uses `AND #31`. All three
planes currently share one ROM page, which lets `LoadStarPattern` assign one
common high byte to all pointers.

### 19.9 Change Effect Heights

The visible total must remain 192 lines:

```text
setup + top + title + gap + sprite + checker + middle + ticker + bottom
```

If one fixed region gains lines, another must lose the same number. Preserve:

```text
(TopBarsLast + 1) + TitleGapCount = 21
```

Remember that hidden intro paths must use the same line counts as the regions
they replace.

### 19.10 Change Cycle-Critical Kernels

Treat these sequences as timing-critical:

- six `NOP`s in the common ticker path;
- five `NOP`s plus `JMP` in the first ticker line;
- `BIT` plus three `NOP`s in the title;
- palette calculation before `WSYNC` in top and middle bars;
- cached first color and preceding-line calculation in bottom bars;
- generated title page alignment;
- `GRP0` writes before star playfield work.

Use Stella's debugger or scanline visualization after changing any of them.

## 20. Common Failure Modes

### The Screen Rolls or Loses Sync

Likely causes:

- the frame is no longer 262 lines;
- VSYNC is not exactly three lines;
- an effect or hidden intro loop has the wrong count;
- a visible-kernel path crosses a scanline unexpectedly.

### Text Splits or Wobbles Near the Center

Likely causes:

- a title or ticker delay sequence changed;
- an instruction before the right-half writes changed cycle count;
- a generated table crossed a page boundary and added an indexed-load cycle;
- the first ticker line no longer rejoins `.tickerRight` at the intended time.

### A Raster Band Has a Differently Colored Left Edge

Likely causes:

- a palette lookup moved after `WSYNC` in the top or middle loop;
- the first bottom color is no longer cached before the ticker;
- bottom colors are calculated after entering their own scanline;
- `COLUBK` and `COLUPF` no longer update together in horizontal blank.

### The Sprite Leaves Trails or Disappears at the Left

Likely causes:

- `GRP0` is not cleared on every non-sprite line or at checker entry;
- starfield work moved before the time-critical `GRP0` load;
- a stage sprite is no longer exactly eight bytes;
- the coarse-positioning delay around `RESP0` changed.

### The Ticker Shows Scrambled Rows

Likely causes:

- `ScrollBuffer` offsets no longer match its register-major layout;
- rotate directions no longer match PF0/PF1/PF2 bit order;
- packed source bits are not rows 0-4 in bits 4-0;
- `ScrollPtr` no longer wraps exactly at `ScrollColumnsEnd`;
- generated output was edited by hand.

### The Soundtrack Stalls, Clicks, or Reads Past Its Stream

Music and visual scenes changing at different times is intentional. Actual
playback faults are more likely caused by:

- `TakeOnMe_Update` no longer being called exactly once per NTSC frame;
- a duration byte being zero before the intended end marker;
- a channel record not containing exactly three bytes;
- a pointer or timer RAM address overlapping other state;
- a packed control/volume byte using bits outside its two nibbles;
- an edited stream running past available ROM before its marker.

### A Transition Stays Dark

Likely causes:

- `TransitionStepHi` and `TransitionStep` are no longer decremented together;
- a transition start table contains the wrong 16-bit boundary;
- a visible color path omitted or misused `TransitionMask`;
- intro code failed to clear `IntroActive` at `$0400`.

### The ROM Is Not 4,096 Bytes

Likely causes:

- data extended past `$FFFF`;
- the vectors were displaced;
- the origin or output format changed;
- generated assets grew beyond the remaining ROM budget.

The Makefile rejects a cartridge image whose size is not exactly 4,096 bytes.

## 21. Debugging with Build Outputs

### 21.1 Symbol File

Use `build/squeepty.sym` to answer questions such as:

- Where did `DrawScreen` assemble?
- Which variables share `$8A`?
- Do all star planes still share a page?
- Where do generated title tables and ticker columns begin and end?

### 21.2 Listing File

Use `build/squeepty.lst` to see:

- source line;
- assembled address;
- machine-code bytes;
- generated include data;
- padding inserted by `ALIGN`;
- whether an instruction or table moved across a page boundary.

The listing is especially useful when auditing cycle-sensitive paths.

### 21.3 Stella

Stella can inspect:

- current scanline, cycle, and frame;
- CPU registers and flags;
- TIA register values;
- RAM and disassembly;
- breakpoints and single stepping.

For display-kernel work, scanline and cycle information is often more useful
than ordinary source-level stepping. For visual sequencing, watch `DemoFrame`,
`IntroStage`, `ScenePattern`, and `TransitionMask` around `$0100`, `$0200`,
`$0300`, and each `$0400`-aligned scene boundary. For audio, watch
`MusicPtr0`, `MusicPtr1`, `MusicTimer0`, and `MusicTimer1`; they should advance
independently and return to their stream starts at the zero-duration markers.

## 22. Design Tradeoffs in This Demo

### 22.1 Compact Columns vs. Precomputed Ticker Frames

The current ticker stores one initial 30-byte image plus 167 packed columns,
then shifts its RAM image during VBLANK.

Benefits:

- hundreds of bytes rather than thousands of bytes of ROM;
- the same simple 30-byte visible-kernel layout;
- easy message and font editing;
- smooth two-pixel cadence without edge persistence from changing whole frames.

Costs:

- more VBLANK CPU work;
- a bit-order-sensitive rotate routine;
- 30 bytes of scarce RAM.

### 22.2 Generated Title Phases vs. Visible-Time Shifting

Ripple and reveal phases are precomputed into six 119-byte tables.

Benefits:

- the title kernel always performs the same simple indexed loads;
- ripple and type effects do not add visible-time bit manipulation;
- page alignment can guarantee stable indexed-load timing.

Cost:

- 714 bytes of title data plus alignment padding.

### 22.3 Scene Tables vs. Branch-Heavy Kernels

Sprites are copied to one RAM buffer, stars are remapped through pointers, and
checker data uses scene offsets. Music has separate sequential event streams.

Benefits:

- visible kernels stay mostly stage-agnostic;
- one `ScenePattern` value selects several matching visual assets;
- adding visual identity does not duplicate entire kernels.

Costs:

- VBLANK selection/copy work;
- visual tables must retain matching scene order.

### 22.4 Shared Hue and Transition Mask

One `Hue` byte derives coordinated colors, and one `TransitionMask` controls
brightness across all effects.

Benefits:

- little RAM;
- visually coherent palette;
- scene-wide fades without separate color curves.

Cost:

- effects cannot animate hue and fade independently without more state.

### 22.5 Shared Scratch RAM

`CheckerState`, `TitleBackground`, `ScrollBits`, `BottomBarColor`, and the star
offset share one byte because they are needed at different times.

Benefit:

- saves four RAM bytes on a machine with only 128.

Cost:

- routine ordering and value lifetimes become part of correctness.

### 22.6 Timer-Controlled Blanking

RIOT timers control VBLANK and overscan rather than long counted `WSYNC` loops.

Benefits:

- blank time can contain useful work;
- most update-routine length changes do not require rebuilding delay loops.

Cost:

- all work must still finish before the timer expires, and the final rounding
  `WSYNC` remains part of the 262-line accounting.

## 23. Glossary

**6502 / 6507**
The CPU instruction family used by the Atari 2600.

**Beam**
The moving point that draws the television image one line at a time.

**Color clock**
The TIA's horizontal timing unit. There are three color clocks per CPU cycle.

**Display kernel**
Cycle-sensitive code that writes graphics registers while visible scanlines
are being drawn.

**Framebuffer**
Memory containing a complete image. The Atari 2600 does not have one.

**Horizontal blank**
The non-visible left-edge interval at the beginning of a scanline, used here
for clean color and graphics-register changes.

**Luminance**
The brightness portion of a TIA color value. Transition masks progressively
remove luminance bits.

**NTSC**
The television timing/color system targeted by this ROM, using 262 scanlines
per frame at approximately 60 frames per second.

**Overscan**
Blank scanlines after the visible image and before the next frame.

**Playfield**
The TIA's low-resolution 20-bit background graphics object.

**RIOT**
The chip providing RAM, input/output, and a timer.

**Scanline**
One horizontal line of the video frame.

**Scene / stage**
A scene is one 1,024-frame static, type, ripple, or vertical-wave section. During the
one-time introduction, “stage” instead means one 256-frame reveal interval.

**Strobe register**
A hardware register where the act of writing triggers behavior; the written
value may not matter. `WSYNC`, `RESP0`, and `HMOVE` are examples.

**TIA**
The chip producing Atari 2600 video and sound.

**VBLANK**
The blanked region used for computation before visible drawing.

**VSYNC**
The signal that marks the start of a new video frame.

**WSYNC**
The TIA register that pauses the CPU until the next scanline.

## 24. Final Mental Model

The complete program can be summarized as:

```text
reset hardware and RAM
seed ticker RAM and enable the one-time intro

forever:
    emit 3 VSYNC lines

    start the 37-line VBLANK timer
    increment the 4,096-frame visual sequencer
    reveal an intro component or select the normal scene
    update transition, title, scene sprite, stars, checker base, hue, and motion
    shift two ticker columns when its ten-frame countdown expires
    update both independent music event timers and decode expired events
    convert SpriteX into TIA coarse/fine timing
    wait for the VBLANK timer

    draw exactly 192 visible scanlines:
        top rasters
        generated title phase
        bouncing scene sprite over remapped stars
        scene checker
        middle rasters
        compact RAM-buffer ticker
        bottom rasters with colors prepared one line early

    start the 30-line overscan timer
    wait and repeat
```

The larger structure is straightforward: prepare complex state while the beam
is blank, then execute a fixed-height, carefully timed visible kernel. The
4,096-frame counter coordinates graphics and fades; the one-time intro hands
off to scene 2 as soon as its fourth reveal stage ends. Alongside it, two music
pointers and countdowns play the soundtrack on an independent 4,005-frame loop.
