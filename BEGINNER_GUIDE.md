# SQUEEPTY Atari 2600 Demo: Beginner's Design and Code Guide

This document explains how the SQUEEPTY demo works from the hardware level
upward. It assumes that you may be new to the Atari 2600, 6502 assembly, or
both.

The most useful fact to keep in mind is this:

> The Atari 2600 does not store a finished screen anywhere. The program builds
> the picture one scanline at a time while the television is drawing it.

That constraint shapes almost every design decision in the ROM.

## 1. What the Demo Does

The ROM automatically displays:

- animated rainbow bars
- a large asymmetric `SQUEEPTY` playfield title
- an 8-row player sprite that bounces horizontally and vertically
- a reflected checker playfield
- a scrolling `HELLO FROM SQUEEPTY / 2600 DEMO` ticker
- a simple two-channel TIA melody

There are no controls. The cartridge enters a permanent frame loop immediately
after reset.

## 2. Suggested Reading Order

If this is your first Atari 2600 program, use this order:

1. Read sections 3 through 7 of this guide.
2. Open `src/demo.asm` and read from the top through `Reset`.
3. Read the `Frame` routine and refer to the scanline table in section 8.
4. Read `UpdateState`, then `PositionPlayer`.
5. Read one effect at a time inside `DrawScreen`.
6. Read `tools/gen_assets.py` only after the playfield explanation makes sense.

You do not need to understand every CPU flag or every cycle on the first pass.
Start by understanding what each routine contributes to one video frame.

## 3. The Four Main Pieces of Atari 2600 Hardware

### 3.1 The 6507 CPU

The console uses a MOS 6507. It is a reduced-pin version of the 6502 and runs
the same instructions used by this program.

The CPU has three general registers:

- `A`: the accumulator, used for arithmetic and most loads/stores
- `X`: an index register, often used for loops and scanline counters
- `Y`: another index register, often used to select table rows

It also has:

- a stack pointer
- a program counter
- status flags such as carry, zero, and negative

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
screen or spills into the next scanline. This is why the six `NOP` instructions
in the title and ticker are meaningful: they position the right-half writes.

### WSYNC

`WSYNC` is the central timing register. Writing any value to it pauses the CPU
until the next scanline begins.

Code commonly looks like this:

```asm
.line
    sta WSYNC
    ; Work here happens near the beginning of a fresh scanline.
```

The value in `A` does not matter for `WSYNC`; only the write matters.

## 5. Small 6502 Primer

### 5.1 Loads and Stores

```asm
lda #28         ; put the immediate value 28 in A
sta SpriteX     ; store A into the byte named SpriteX
ldx #0          ; put 0 in X
ldy #29         ; put 29 in Y
```

The `#` means "use this value." Without it, the operand normally means "read
from this memory address."

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
cmp #146
bcc .checkLeft
```

`CMP` subtracts for flag purposes but does not change `A`. `BCC` means "branch
if carry is clear." For an unsigned comparison after `CMP`, that corresponds
to "branch if A is less than the operand."

Other branches used here include:

- `BNE`: branch if the result was not zero
- `BCS`: branch if carry is set
- `BPL`: branch if the negative flag is clear

### 5.4 Bit Operations

```asm
and #7          ; retain only the bottom three bits
ora #$0C        ; force selected bits to 1
eor #$80        ; toggle selected bits
lsr             ; shift right one bit
asl             ; shift left one bit
```

Power-of-two masks are used as inexpensive modulo operations:

```text
value AND 7   -> value modulo 8
value AND 15  -> value modulo 16
value AND 31  -> value modulo 32
```

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
labels. Labels such as `Reset` and `DrawScreen` identify major routines.

## 7. Memory Map

### 7.1 RAM

The demo uses 41 of the 128 RAM bytes:

| Address | Name | Size | Purpose |
| --- | --- | ---: | --- |
| `$80` | `FrameCounter` | 1 | Global frame counter |
| `$81` | `Hue` | 1 | Base hue used by several effects |
| `$82` | `SpriteX` | 1 | Horizontal player coordinate |
| `$83` | `SpriteDX` | 1 | Horizontal velocity, `+1` or `-1` |
| `$84` | `SpriteY` | 1 | Sprite top within its 40-line region |
| `$85` | `SpriteDY` | 1 | Vertical velocity, `+1` or `-1` |
| `$86` | `ScrollTick` | 1 | Ticker speed divider |
| `$87-$88` | `ScrollPtr` | 2 | Pointer to a generated scroll frame |
| `$89` | `MusicStep` | 1 | Current music-table index |
| `$8A` | `CheckerState` | 1 | Current checker phase |
| `$8B-$A8` | `ScrollBuffer` | 30 | Current ticker image |

The stack begins at the top of its mirrored RAM area and grows downward. This
program uses very little stack space, and there is a large gap between the
variables ending at `$A8` and the stack near `$FF`.

### 7.2 ROM

Addresses from the current build are:

| Address range | Contents | Bytes |
| --- | --- | ---: |
| `$F000-$F267` | Program code | 616 |
| `$F268-$F2FF` | Alignment padding | 152 |
| `$F300-$F36D` | Colors, sprite, checker, and music | 110 |
| `$F36E-$F397` | Generated title data | 42 |
| `$F398-$FC43` | Generated ticker frames | 2220 |
| `$FC44-$FFFB` | Unused ROM space | 952 |
| `$FFFC-$FFFF` | Reset and IRQ/BRK vectors | 4 |

The addresses can move when code or data changes. `build/squeepty.sym` shows
the current symbol addresses after each build.

## 8. One Complete Video Frame

The main `Frame` routine produces exactly 262 NTSC scanlines.

| Region | Lines | What happens |
| --- | ---: | --- |
| VSYNC | 3 | Tells the display that a new frame starts |
| VBLANK | 37 | Updates state and positions player 0 |
| Visible | 192 | Runs `DrawScreen` |
| Overscan | 30 | Blanks the bottom and waits |
| Total | 262 | One NTSC frame |

### 8.1 VSYNC

The code sets bit 1 in both `VBLANK` and `VSYNC`, waits through three `WSYNC`
boundaries, then clears `VSYNC`.

The display remains blank because `VBLANK` is still enabled.

### 8.2 VBLANK Timer

Writing 43 to `TIM64T` starts a timer measured in 64-cycle units:

```text
43 * 64 = 2752 CPU cycles
2752 / 76 = about 36.2 scanlines
```

The final `WSYNC` rounds this region to 37 scanlines.

While the timer runs, the code calls:

- `UpdateState`
- `PositionPlayer`

The timer continues counting during both routines. After they finish, the CPU
polls `INTIM` until it reaches zero.

### 8.3 Visible Region

`DrawScreen` accounts for its 192 lines as follows:

| Effect | Lines |
| --- | ---: |
| Initial setup/partial line | 1 |
| Top bars | 15 |
| Title | 42 |
| Empty title gap | 6 |
| Sprite region | 40 |
| Checker region | 32 |
| Middle bars | 12 |
| Ticker | 25 |
| Bottom bars | 19 |
| Total | 192 |

The first visible line is the time between disabling `VBLANK` and the first
`WSYNC` in `DrawScreen`. Each effect then produces its listed number of lines.
The final `WSYNC` closes the last bottom bar.

### 8.4 Overscan Timer

The code enables `VBLANK`, writes 35 to `TIM64T`, and waits:

```text
35 * 64 = 2240 CPU cycles
2240 / 76 = about 29.5 scanlines
```

The final `WSYNC` rounds overscan to 30 lines. The code then jumps back to
`Frame`.

## 9. Reset Walkthrough

### 9.1 CPU Setup

```asm
sei
cld
ldx #$FF
txs
```

- `SEI` disables maskable interrupts.
- `CLD` makes arithmetic binary instead of binary-coded decimal.
- `TXS` initializes the stack pointer to `$FF`.

The 6507 does not expose the regular external interrupt pins, but this is still
the conventional and predictable startup sequence.

### 9.2 Clearing TIA and RAM

```asm
lda #0
ldx #0
.clear
    sta $00,x
    inx
    bne .clear
```

X visits every value from 0 through 255. The writes cover TIA registers and
the console RAM range, establishing a known black, silent state and zeroing all
variables.

### 9.3 Initial State

The sprite starts at:

```text
X = 28
Y = 7
DX = +1
DY = +1
```

`ScrollPtr` starts at `ScrollFrames`, the first generated ticker image.

### 9.4 Graphics and Sound Setup

`NUSIZ0=$05` selects a double-width player. The sprite still has eight source
bits, but each is displayed twice as wide.

The two audio controls are set to different TIA waveform modes:

```text
AUDC0 = $04
AUDC1 = $06
```

Volumes are intentionally modest:

```text
AUDV0 = 4
AUDV1 = 2
```

## 10. UpdateState Walkthrough

`UpdateState` runs once per video frame during VBLANK.

### 10.1 Frame Counter and Hue

`FrameCounter` increments every frame. It is an 8-bit byte, so it naturally
wraps from 255 to 0.

Every eighth frame:

```asm
lda Hue
clc
adc #$10
and #$F0
sta Hue
```

The high nibble of a TIA NTSC color selects hue. Adding `$10` advances to the
next hue family. Masking with `$F0` keeps the low luminance bits clear so each
effect can add its own brightness with `ORA`.

### 10.2 Horizontal Bounce

The update is:

```text
SpriteX = SpriteX + SpriteDX
```

At the right boundary, `SpriteDX` becomes `$FF`, which means `-1`. At the left
boundary, it becomes `+1`.

The horizontal range is selected to keep the double-width sprite on screen
while leaving some margin.

### 10.3 Vertical Bounce

The vertical update is the same idea:

```text
SpriteY = SpriteY + SpriteDY
```

The sprite region is 40 scanlines and the bitmap is 8 scanlines tall. A top
position of 32 uses lines 32 through 39, exactly reaching the bottom.

### 10.4 Ticker Speed and Pointer

The ticker advances when:

```asm
ScrollTick AND 7 = 0
```

That occurs every eight frames. Each generated frame shifts the source by two
logical playfield pixels.

At approximately 60 video frames per second:

```text
60 / 8 = 7.5 ticker frames per second
7.5 * 2 = 15 logical playfield pixels per second
```

The source row is 147 pixels wide, producing 74 generated frames. A complete
loop therefore lasts about:

```text
74 frames * 8 video frames / 60 = 9.9 seconds
```

Each ticker frame is 30 bytes. Advancing the pointer uses 16-bit addition:

```asm
clc
lda ScrollPtr
adc #30
sta ScrollPtr
lda ScrollPtr+1
adc #0
sta ScrollPtr+1
```

The carry from the low-byte addition is added into the high byte. When the
pointer equals `ScrollFramesEnd`, it wraps to `ScrollFrames`.

### 10.5 Copying the Ticker to RAM

The selected 30-byte frame is copied from ROM into `ScrollBuffer`:

```asm
ldy #29
.copyByte
    lda (ScrollPtr),y
    sta ScrollBuffer,y
    dey
    bpl .copyByte
```

`(ScrollPtr),y` is indirect-indexed addressing:

1. Read a 16-bit base address from `ScrollPtr`.
2. Add Y.
3. Load from the resulting address.

The copy happens in VBLANK, not in the visible ticker kernel. This is an
important design tradeoff: spending some blank-time work and 30 bytes of RAM
makes each visible scanline much simpler.

### 10.6 Music

The music changes every 16 video frames:

```text
60 / 16 = 3.75 note changes per second
```

`MusicStep AND 15` keeps the index in the range 0-15. The same index selects
one byte from `Melody` and one from `Bass`.

TIA frequency values are divider settings, not standard note names. In
general, lower divider values produce higher pitches, but the selected `AUDC`
waveform also affects the result.

## 11. Horizontal Player Positioning

The TIA has no ordinary `PlayerX` register. Writing to `RESP0` resets player
0's horizontal counter at the beam's current position. Therefore, the timing
of the write determines the coarse X position.

`PositionPlayer` works in two parts.

### 11.1 Coarse Position

After a `WSYNC`, the routine repeatedly subtracts 15:

```asm
.divide
    sbc #15
    bcs .divide
```

Each loop consumes time corresponding to a horizontal step. More loops delay
the `RESP0` write and place the player farther right.

### 11.2 Fine Position

The leftover value is converted to the signed fine-motion format used by
`HMP0`:

```asm
eor #7
asl
asl
asl
asl
sta HMP0
```

The useful motion nibble belongs in bits 7-4, which explains the four left
shifts.

The routine writes `RESP0` for coarse position and then strobes `HMOVE` at the
start of the next line to apply the fine correction.

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
instead of treating the three registers as one normal 20-bit integer.

### 12.1 Normal Repeat or Reflection

The same 20 bits normally create both screen halves:

- `CTRLPF` bit 0 clear: repeat the pattern on the right
- `CTRLPF` bit 0 set: reflect the pattern on the right

The checker uses reflection because symmetry is desirable and cheap.

### 12.2 Asymmetric 40-Bit Playfield

The title and ticker need 40 unique bits. They use a mid-scanline rewrite:

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
half. The six `NOP` instructions delay the second group of writes until the
correct horizontal time.

The common repeated path takes about 59 cycles after `WSYNC`, leaving margin
inside the 76-cycle scanline.

## 13. DrawScreen Effect by Effect

### 13.1 Initial Setup Line

`DrawScreen` first clears the playfield and `CTRLPF`. The first top-bar `WSYNC`
ends this setup line. It counts as one of the 192 visible lines.

### 13.2 Top Bars

For each of 15 lines:

```text
palette index = (line counter + FrameCounter) AND 31
```

The 32-byte `Rainbow` table provides the color. Adding `FrameCounter` shifts
the selected colors every frame, creating motion without moving geometry.

### 13.3 Title

The title source has seven bitmap rows. Each row is repeated for six
scanlines:

```text
7 source rows * 6 = 42 visible scanlines
```

`Y` chooses the source row. `X` counts the six vertical repetitions.

Six generated arrays hold one byte per source row:

```text
TitlePF0L  TitlePF1L  TitlePF2L
TitlePF0R  TitlePF1R  TitlePF2R
```

The title font uses 4-pixel-wide letters with a 1-pixel gap. Eight letters
occupy 39 pixels, and the generator adds one leading blank pixel for a total
of exactly 40.

### 13.4 Title Gap

Six empty lines clear the playfield and background. Besides adding visual
space, this gives the next sprite region a clean start.

### 13.5 Bouncing Player

The sprite region has a software line counter from 0 through 39. On every
line, it computes:

```text
bitmap row = current line - SpriteY
```

If the result is 0-7, that row of `SpriteBitmap` is written to `GRP0`.
Otherwise, `GRP0` remains zero.

This handles both cases outside the sprite:

- Before the sprite, subtraction underflows to a large unsigned value.
- After the sprite, the result is 8 or greater.

Both fail `CMP #8`.

### 13.6 Checker

The checker has two complementary PF0/PF1/PF2 patterns. The kernel swaps
between them every four scanlines, so each checker row is four lines tall.

The starting pattern is based on:

```text
(FrameCounter >> 2) AND 1
```

It changes every four video frames and makes the checker appear animated.

`CTRLPF=1` reflects the 20-bit pattern across the screen.

### 13.7 Middle Bars

The middle bars use:

```text
(line counter * 2 + FrameCounter) AND 31
```

Multiplying the line counter by two skips through the palette faster and makes
the gradient steeper than the top bars.

### 13.8 Ticker

The ticker has five source rows, each repeated five times:

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

When Y is a row number, `ScrollBuffer+10,y` means "PF2 for this same left-side
row." This layout avoids multiplication or pointer changes in the visible
kernel.

### 13.9 Bottom Bars

The 19 bottom lines use `RainbowReverse`. A final `WSYNC` ends the last visible
line cleanly before control returns to `Frame`, which immediately enables
`VBLANK`.

## 14. Asset Generation

`tools/gen_assets.py` converts readable bitmap fonts into the strange bit
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

Each character in a row is one logical playfield pixel:

- `"1"` means playfield on
- `"0"` means playfield off

The ticker uses smaller 3-by-5 glyphs.

### 14.2 Building Text Rows

`text_rows` concatenates glyph rows horizontally and inserts a blank pixel
between characters.

The title becomes seven rows. The ticker message becomes five long rows.

### 14.3 Encoding One 20-Bit Half

`encode_half` divides 20 pixels among PF0, PF1, and PF2. It handles each
register's display direction:

```python
pf0 = ...
pf1 = bits_to_byte(...)
pf2 = reverse_bits(bits_to_byte(...))
```

`encode_row` encodes both 20-bit halves and returns six values:

```text
left PF0, left PF1, left PF2, right PF0, right PF1, right PF2
```

### 14.4 Title Output

For the title, the generator transposes the seven encoded rows into six
register-specific tables. This matches how the title kernel indexes data:

```asm
lda TitlePF0L,y
lda TitlePF1L,y
lda TitlePF2L,y
```

### 14.5 Ticker Frames

The ticker generator:

1. Creates the complete five-row message.
2. Duplicates each row to make wraparound slicing easy.
3. Selects a 40-pixel window.
4. Advances the window by two pixels for the next frame.
5. Encodes each window into 30 bytes.
6. Emits all frames consecutively into ROM.

Precomputing the animation uses more ROM but saves precious visible-kernel CPU
time. This is a good Atari 2600 tradeoff because the demo has much more spare
ROM than spare scanline cycles.

## 15. Animation Rates

Approximate rates at 60 frames per second:

| Animation | Update interval | Approximate rate |
| --- | --- | --- |
| Raster palette offset | 1 frame | 60 updates/second |
| Sprite X/Y | 1 frame | 60 position steps/second |
| Checker starting phase | 4 frames | 15 changes/second |
| Hue | 8 frames | 7.5 changes/second |
| Ticker | 8 frames | 7.5 frames/second |
| Music | 16 frames | 3.75 note changes/second |

`FrameCounter` wraps every 256 frames, or roughly 4.27 seconds.

## 16. Color Design

An NTSC TIA color byte is organized approximately as:

```text
HHHH LLLx
```

- the high nibble selects hue
- the lower useful bits select luminance
- the lowest bit is not significant for ordinary color selection

The demo keeps a shared `Hue` and derives related colors with `EOR` and `ORA`.
For example:

```asm
lda Hue
eor #$80
ora #$0C
sta COLUPF
```

This offsets the hue and forces a bright luminance. It creates coordinated
color cycling without storing separate animated color values for every effect.

PAL and SECAM systems use different color interpretation and frame timing.
This ROM is intentionally an NTSC design.

## 17. Audio Design

TIA provides two simple audio channels. Each has:

- an `AUDC` control/waveform register
- an `AUDF` frequency divider
- an `AUDV` volume register

The demo configures control and volume once, then changes only frequency. This
keeps the music routine short.

TIA waveforms are hardware divider/noise patterns rather than general sampled
audio. Values that sound musical for one `AUDC` mode may sound different under
another mode.

## 18. Build Pipeline

Running `make` performs these steps:

```text
tools/gen_assets.py
        |
        v
build/assets.inc
        |
        +---- included by src/demo.asm
                         |
                         v
                       DASM
                         |
            +------------+-------------+
            v            v             v
build/squeepty.bin  build/squeepty.lst  build/squeepty.sym
```

Files:

- `build/squeepty.bin`: the 4096-byte cartridge image
- `build/squeepty.lst`: source mixed with addresses and machine-code bytes
- `build/squeepty.sym`: label-to-address map
- `build/assets.inc`: generated playfield bytes

Use:

```sh
make
make check
```

`make check` confirms the ROM size and prints its SHA-256 hash.

To run it on macOS:

```sh
open -na Stella --args "$PWD/build/squeepty.bin"
```

## 19. Safe Experiments

### 19.1 Change Scroll Speed

The current code advances when:

```asm
and #7
```

Useful masks are:

| Mask | Advance interval |
| ---: | ---: |
| `#1` | 2 frames |
| `#3` | 4 frames |
| `#7` | 8 frames |
| `#15` | 16 frames |

This works because each mask is one less than a power of two.

### 19.2 Change the Ticker Message

Edit:

```python
message = "   HELLO FROM SQUEEPTY / 2600 DEMO   "
```

in `tools/gen_assets.py`.

Every character must exist in `TICKER_FONT`. Add a 3-by-5 glyph if needed.
Then run `make`.

Longer messages consume more ROM. There are currently about 952 unused bytes,
which is enough for roughly 31 additional 30-byte ticker frames.

### 19.3 Change the Sprite

Edit the eight binary rows under `SpriteBitmap`.

Keep eight rows unless you also change:

- `CMP #8` in the sprite kernel
- the vertical bounce limit
- possibly the sprite-region scanline allocation

### 19.4 Change Sprite Size

Edit the value stored in `NUSIZ0`. Other values select normal, double, or
quadruple width and various multiple-copy patterns. Horizontal bounce limits
may also need adjustment.

### 19.5 Change Colors

The safest color experiments are:

- edit the `Rainbow` and `RainbowReverse` tables
- change the constants ORed into `Hue`
- change the hue offsets used by `EOR`

Keep color table lengths at 32 unless you also change the `AND #31` masks.

### 19.6 Change Music

Edit `Melody` and `Bass`. Keep both at 16 values unless you also change the
`AND #15` wrapping logic.

### 19.7 Change Effect Heights

This requires more care. The visible total must remain 192 lines. If one effect
gains lines, another must lose the same number.

Recalculate:

```text
initial + top + title + gap + sprite + checker + middle + ticker + bottom
```

and keep the result at 192.

### 19.8 Change Title or Ticker Timing

Treat the six `NOP` instructions as timing-critical. Changing their number can
move the right-half playfield rewrite and visibly split or distort text.

Use Stella's debugger or scanline visualization when modifying visible-kernel
instruction timing.

## 20. Common Failure Modes

### The Screen Rolls or Loses Sync

Likely causes:

- the frame is no longer 262 lines
- VSYNC is not exactly three lines
- an effect loop has the wrong count
- a visible-kernel path crosses a scanline unexpectedly

### Text Is Split Near the Center

Likely causes:

- the middle `NOP` delay changed
- an instruction before the right-half writes changed cycle count
- a table moved across a page boundary and introduced an extra indexed-load
  cycle

### The Sprite Leaves Trails

Likely cause:

- `GRP0` is not being cleared on non-sprite lines or after the sprite region

### The Ticker Shows Scrambled Rows

Likely causes:

- `ScrollBuffer` offsets no longer match its register-major layout
- generated frame size changed but the `+30` pointer advance did not
- the asset generator output was edited by hand

### The ROM Is Not 4096 Bytes

Likely causes:

- data extended past `$FFFF`
- the reset vectors were displaced
- the assembler output origin or format changed

The Makefile intentionally rejects a ROM whose size is not exactly 4096 bytes.

## 21. Debugging with Build Outputs

### Symbol File

Use `build/squeepty.sym` to answer questions such as:

- Where did `DrawScreen` assemble?
- How much RAM does `ScrollBuffer` occupy?
- Where do generated ticker frames begin and end?

### Listing File

Use `build/squeepty.lst` to see:

- source line
- assembled address
- machine-code bytes
- included generated data

The listing is especially useful for verifying that comments or label changes
did not alter executable bytes.

### Stella

Stella can inspect:

- current scanline and frame
- CPU registers and flags
- TIA register values
- RAM
- disassembly
- breakpoints and single stepping

For display-kernel work, scanline and cycle information are often more useful
than ordinary source-level stepping.

## 22. Design Tradeoffs in This Demo

This ROM deliberately prioritizes clarity and robust timing over extreme ROM
compression.

### Precomputed Ticker vs. Runtime Text Rendering

Chosen approach:

- precompute every ticker frame in Python
- copy one 30-byte frame to RAM
- use simple visible-kernel reads

Benefits:

- predictable scanline timing
- simple assembly
- easy font and message editing

Cost:

- 2220 bytes of ROM

### RAM Buffer vs. Direct ROM Reads

Chosen approach:

- copy the current frame to `ScrollBuffer`

Benefits:

- fixed, nearby addresses in the ticker kernel
- register-major layout optimized for Y indexing
- no visible-kernel pointer arithmetic

Cost:

- 30 of the console's 128 RAM bytes
- a copy loop during VBLANK

### Shared Hue vs. Independent Color Animations

Chosen approach:

- one shared `Hue`
- derive effect colors using bit operations

Benefits:

- low RAM usage
- coordinated visual palette
- short update code

Cost:

- effects cannot animate their hues independently

### Timer-Controlled Blanking vs. Counted WSYNC Loops

Chosen approach:

- RIOT timers for VBLANK and overscan

Benefits:

- blank time can contain useful work
- animation routines can change length without rewriting a large delay loop

Cost:

- the timer values and final rounding `WSYNC` must be understood together

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
reset hardware and variables

forever:
    emit 3 VSYNC lines

    start VBLANK timer
    update animation, scroll data, and music
    convert SpriteX into TIA timing
    wait for VBLANK timer

    draw exactly 192 scanlines:
        colors
        title
        sprite
        checker
        ticker
        colors

    start overscan timer
    wait
```

The source may initially look like many small register writes and loops. The
larger structure is simple: prepare state while the screen is blank, then run
a carefully timed sequence that constructs one frame directly in front of the
television beam.
