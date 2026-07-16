# The Teeny-tiny Atari 2600 demo: Assembly and Hardware Reference

This is the lookup reference for [`src/demo.asm`](src/demo.asm), the soundtrack
events in [`src/take_on_me_tia_data.inc`](src/take_on_me_tia_data.inc), and the
generated tables produced by [`tools/gen_assets.py`](tools/gen_assets.py). It
covers the official 6502 instruction vocabulary, every mnemonic and DASM
directive used by this ROM, CPU/RAM registers, TIA/RIOT hardware addresses,
frame construction, show sequencing, audio, effects, and the current ROM layout.

Production release date: Thursday, July 16, 2026.

Scope:

- The instruction table lists every documented, official 6502 mnemonic. The
  6507 in an Atari 2600 executes the same instruction set.
- The **Used** column identifies every CPU mnemonic that actually occurs in
  `src/demo.asm`.
- TIA read and write maps are complete. The project-specific tables identify
  what the demo uses. Undocumented CPU opcodes are intentionally excluded.

## 1. Machine model

| Component | Role | Addresses relevant here |
| --- | --- | --- |
| MOS 6507 | 8-bit CPU; 6502 instruction set with a 13-bit address bus | Runs this 4 KiB cartridge at `$F000-$FFFF` |
| TIA | Television timing, colors, playfield, players, motion, collisions, and two audio voices | Low address register window `$00-$3F` (mirrored) |
| RIOT | 128 bytes RAM, console/controller I/O, and interval timer | RAM `$80-$FF`; timer/I/O around `$0280-$0297` |
| Cartridge | Program, data, generated assets, CPU vectors | `$F000-$FFFF`; no bank switching |

There is no framebuffer. A write such as `STA COLUBK`, `STA PF0`, or
`STA GRP0` changes TIA hardware while the beam is moving. In the visible
kernel, the time of a write is as meaningful as its value.

## 2. CPU registers and status flags

| Register | Width | Role in this ROM |
| --- | ---: | --- |
| `A` accumulator | 8 | Main value register: colors, timer values, graphics, table values, and TIA/RIOT writes. |
| `X` index | 8 | Clear-loop index and scanline/repetition counter. |
| `Y` index | 8 | Title/sprite/checker row index and indirect event/ticker-pointer offset. |
| `SP` stack pointer | 8 | Points into the hardware stack; initialized to `$FF` by `TXS`. The stack grows downward. |
| `PC` program counter | 16 | Address of next instruction; loaded at reset from `$FFFC-$FFFD`. |
| `P` processor status | flags | Arithmetic, branch, decimal, and interrupt state. |

| Flag | Meaning | Use in the demo |
| --- | --- | --- |
| `C` carry | Unsigned carry/no-borrow; receives shifted-out bits. | `CLC` before ordinary `ADC`; `SEC` before `SBC`; `BCC`/`BCS` compare coordinates; `ROL`/`ROR` carry ticker pixels between bytes. |
| `Z` zero | Set when result is zero. | `BEQ` and `BNE` select stages, control loops, and poll the timer. |
| `I` interrupt disable | Masks IRQ on a full 6502. | `SEI` gives reset a known state. The 6507 lacks an external IRQ pin, but `BRK` remains valid. |
| `D` decimal | Enables BCD behavior for `ADC`/`SBC`. | `CLD` forces normal binary coordinate and pointer arithmetic. |
| `B` break | Status representation pushed by `BRK`/`PHP`; not an ordinary latch. | IRQ/BRK vector points to `Reset`. |
| `V` overflow | Signed two's-complement overflow. | Not tested by this ROM. |
| `N` negative | Copy of result bit 7. | `BPL`/`BMI` terminate descending loops when an index crosses from zero to `$FF`. |

Bit 5 of a pushed status byte is conventionally set; it is not an independently
controlled CPU flag.

## 3. Addressing modes and DASM syntax

| Form | Mode | Meaning / example |
| --- | --- | --- |
| `#value` | Immediate | Literal byte: `lda #28`. |
| `label`, `$nn` | Zero page or absolute | Read/write address: `sta SpriteX`, `lda INTIM`. DASM picks zero-page encoding when possible. |
| `label,x` | X-indexed | Base plus `X`: `lda SpriteBitmaps,x`, `sta $00,x`. |
| `label,y` | Y-indexed | Base plus `Y`: `lda Rainbow,y`. |
| `(zp),y` | Indirect indexed | Read a little-endian zero-page pointer, add `Y`: `lda (ScrollPtr),y`. |
| `(zp,x)` | Indexed indirect | Add `X` to a zero-page pointer location, then dereference. Legal, not used here. |
| `(address)` | Absolute indirect | Dereference a 16-bit address. Legal only with `JMP`; not used here. |
| branch label | Relative | Signed `-128..+127` offset from next instruction: `bne .clear`. |
| `A` / no operand | Accumulator / implied | Acts on `A`, or has inherent operands: `asl`, `clc`, `rts`. |

- `$10` is hexadecimal; `%00010000` is binary; bare numbers such as `28`
  are decimal.
- `<Label` and `>Label` are the low and high byte of an address. The
  `ScrollPtr` setup uses both because 6502 pointers are little-endian.
- Original 6502 `JMP (address)` has a page-end wrap quirk when the pointer
  ends in `$FF`; this code does not use that addressing mode.

## 4. Official 6502/6507 mnemonics

Flag letters mean the instruction changes that flag. Branches test, but do not
change, their named flag. **Used** is based on `src/demo.asm`.

| Mnemonic | Plain-language operation | Flags | Used |
| --- | --- | --- | --- |
| `ADC` | `A = A + operand + C` | N Z C V | Yes |
| `AND` | `A = A AND operand` | N Z | Yes |
| `ASL` | Shift A/memory left; old bit 7 becomes C | N Z C | Yes |
| `BCC` | Branch if C is clear | tests C | Yes |
| `BCS` | Branch if C is set | tests C | Yes |
| `BEQ` | Branch if Z is set | tests Z | Yes |
| `BIT` | Test A against memory; copy memory bit 7/6 to N/V | N Z V | Yes |
| `BMI` | Branch if N is set | tests N | Yes |
| `BNE` | Branch if Z is clear | tests Z | Yes |
| `BPL` | Branch if N is clear | tests N | Yes |
| `BRK` | Software interrupt; push state, load IRQ vector | sets I | No |
| `BVC` | Branch if V is clear | tests V | No |
| `BVS` | Branch if V is set | tests V | No |
| `CLC` | Clear carry | C | Yes |
| `CLD` | Clear decimal mode | D | Yes |
| `CLI` | Clear interrupt disable | I | No |
| `CLV` | Clear overflow | V | No |
| `CMP` | Compare A with operand (subtract, discard result) | N Z C | Yes |
| `CPX` | Compare X with operand | N Z C | Yes |
| `CPY` | Compare Y with operand | N Z C | Yes |
| `DEC` | Decrement memory | N Z | Yes |
| `DEX` | `X = X - 1` | N Z | Yes |
| `DEY` | `Y = Y - 1` | N Z | Yes |
| `EOR` | `A = A XOR operand` | N Z | Yes |
| `INC` | Increment memory | N Z | Yes |
| `INX` | `X = X + 1` | N Z | Yes |
| `INY` | `Y = Y + 1` | N Z | Yes |
| `JMP` | Unconditional jump | — | Yes |
| `JSR` | Push return address and jump to a subroutine | — | Yes |
| `LDA` | Load operand into A | N Z | Yes |
| `LDX` | Load operand into X | N Z | Yes |
| `LDY` | Load operand into Y | N Z | Yes |
| `LSR` | Shift A/memory right; old bit 0 becomes C | N Z C | Yes |
| `NOP` | Consume cycles without changing state | — | Yes |
| `ORA` | `A = A OR operand` | N Z | Yes |
| `PHA` | Push A | — | Yes |
| `PHP` | Push status | — | No |
| `PLA` | Pull stack byte into A | N Z | Yes |
| `PLP` | Pull status | all restored | No |
| `ROL` | Rotate A/memory left through C | N Z C | Yes |
| `ROR` | Rotate A/memory right through C | N Z C | Yes |
| `RTI` | Return from interrupt; restore status and PC | all restored | No |
| `RTS` | Return from subroutine | — | Yes |
| `SBC` | `A = A - operand - (1-C)` | N Z C V | Yes |
| `SEC` | Set carry | C | Yes |
| `SED` | Set decimal mode | D | No |
| `SEI` | Set interrupt disable | I | Yes |
| `STA` | Store A to memory or hardware | — | Yes |
| `STX` | Store X | — | No |
| `STY` | Store Y | — | Yes |
| `TAX` | Copy A to X | N Z | Yes |
| `TAY` | Copy A to Y | N Z | Yes |
| `TSX` | Copy SP to X | N Z | No |
| `TXA` | Copy X to A | N Z | Yes |
| `TXS` | Copy X to SP | — | Yes |
| `TYA` | Copy Y to A | N Z | No |

### Used mnemonic groups

| Group | Mnemonics | Role in the source |
| --- | --- | --- |
| Transfer | `LDA LDX LDY STA STY TAX TAY TXA TXS` | Move state, data, and table indexes between CPU, RAM, TIA, and RIOT. |
| Stack data | `PHA PLA` | Preserve the packed control/volume byte while decoding each music event. |
| Arithmetic/bit shaping | `ADC SBC INC DEC INX INY DEX DEY ASL LSR ROL ROR AND ORA EOR BIT` | Motion, counters, pointer advance, palette modulo, color construction, ticker rotation, fine-motion encoding, and an exact three-cycle title delay. |
| Comparisons/control | `CMP CPX CPY BCC BCS BEQ BMI BNE BPL JMP JSR RTS` | Stage selection, sprite bounds, signed loop termination, polling, and routine calls. |
| Flag setup | `CLC SEC CLD SEI` | Establish add/subtract semantics and a known reset state. |
| Display timing | `NOP` | Completes the title's 9-cycle and ticker's 12-cycle right-half delays. |

The two most important carry idioms are:

```asm
clc
adc SpriteDX        ; A + SpriteDX, without a leftover carry

sec
sbc #15             ; A - 15, with no initial borrow
```

## 5. DASM directives and labels used here

These describe the assembled image; they are not CPU instructions.

| Form | Role |
| --- | --- |
| `processor 6502` | Selects the correct 6502-compatible instruction set for a 6507. |
| `NAME = value` | Assembly-time numeric constant, e.g. `COLUBK = $09`; emits no byte. |
| `SEG.U RAM` | Uninitialized segment: labels assign RAM addresses, not cartridge bytes. |
| `SEG CODE` | ROM code/data segment. |
| `ORG address` | Set current assembly address, e.g. `$80`, `$F000`, `$FFFC`. |
| `ds count` | Reserve bytes in an uninitialized segment. |
| `ALIGN 256` | Advance to the next page boundary; keeps timing-sensitive indexed palette/title loads from gaining a page-cross cycle. |
| `byte ...` | Emit one or more data bytes. |
| `word label` | Emit a 16-bit little-endian address; used for CPU vectors. |
| `include "src/take_on_me_tia_data.inc"` | Insert compact soundtrack events. |
| `include "build/assets.inc"` | Insert generated title/ticker tables at assembly time. |
| `Label` | Name current address, e.g. `Reset`, `Frame`, `DrawScreen`. |
| `.local` | Local label associated with the surrounding major label, e.g. `.titleLine`. |

## 6. Memory map

| Address/range | Device | Role |
| --- | --- | --- |
| `$0000-$003F` | TIA | Read/write register window. Read and write meanings differ at the same address; the window is mirrored. |
| `$0080-$00FF` | RIOT RAM | Console's 128 physical RAM bytes. Program variables use `$80-$CB`; music decoding can touch stack bytes `$F9-$FF`. |
| `$0280-$0297` | RIOT I/O/timer | Controller/console ports and interval timer. |
| `$F000-$FFFF` | 4 KiB ROM | Code, tables, generated assets, and vectors. |
| `$FFFC-$FFFD` | Reset vector | Little-endian entry address, set to `Reset`. |
| `$FFFE-$FFFF` | IRQ/BRK vector | Also set to `Reset`. |

The reset loop writes `STA $00,x` as X counts through all 256 byte values.
That clears TIA writable registers and their mirrors, then RIOT RAM at
`$80-$FF`.

## 7. TIA write map — video, positioning, and audio

TIA writes usually act on hardware immediately rather than storing ordinary
memory. **Used** means the ROM intentionally accesses the register after its
reset sweep. `Reset` also writes zero through every TIA write address while
clearing `$00-$7F`; a **No** entry therefore means "cleared only," not that the
physical address is never touched.

### Timing and global video

| Addr. | Register | Role | Used |
| ---: | --- | --- | --- |
| `$00` | `VSYNC` | Bit 1 enables vertical sync. This ROM holds it on for three WSYNC lines. | Yes |
| `$01` | `VBLANK` | Bit 1 blanks video. Bit 6 controls trigger-input latching; bit 7 dumps paddle capacitors. Uses `$02` to blank and `$00` to show. | Yes |
| `$02` | `WSYNC` | Write strobe: holds CPU until next scanline. Written byte is irrelevant. | Yes |
| `$03` | `RSYNC` | Horizontal-sync reset strobe for specialized timing. | No |

### Object configuration, colors, and playfield

| Addr. | Register | Role | Used |
| ---: | --- | --- | --- |
| `$04` | `NUSIZ0` | Player 0 copy/size and Missile 0 size. `$05` gives this demo a double-width Player 0. | Yes |
| `$05` | `NUSIZ1` | Player 1 copy/size and Missile 1 size. | No |
| `$06` | `COLUP0` | Player 0/Missile 0 color-luminance. | Yes |
| `$07` | `COLUP1` | Player 1/Missile 1 color-luminance. | No |
| `$08` | `COLUPF` | Playfield/Ball color-luminance, except score-color selection. | Yes |
| `$09` | `COLUBK` | Background color-luminance; raster bars write it per scanline. | Yes |
| `$0A` | `CTRLPF` | Bit 0 reflect right playfield; bit 1 score colors; bit 2 PF/ball priority; bits 4-5 ball size. | Yes |
| `$0B` | `REFP0` | Bit 3 reflects Player 0. | No |
| `$0C` | `REFP1` | Bit 3 reflects Player 1. | No |
| `$0D` | `PF0` | First 4 visible playfield bits (only bits 4-7). | Yes |
| `$0E` | `PF1` | Middle 8 playfield bits. | Yes |
| `$0F` | `PF2` | Final 8 playfield bits. | Yes |

### Coarse-position reset strobes

The byte written to these strobes does not matter; the color clock at which the
write occurs determines an object's coarse horizontal position.

| Addr. | Register | Object | Used |
| ---: | --- | --- | --- |
| `$10` | `RESP0` | Player 0 | Yes |
| `$11` | `RESP1` | Player 1 | No |
| `$12` | `RESM0` | Missile 0 | No |
| `$13` | `RESM1` | Missile 1 | No |
| `$14` | `RESBL` | Ball | No |

### Audio — two independent TIA voices

| Addr. | Register | Role | Used |
| ---: | --- | --- | --- |
| `$15` | `AUDC0` | Channel 0 control/distortion waveform (low 4 bits), loaded from each melody event's packed high nibble. | Yes |
| `$16` | `AUDC1` | Channel 1 control/distortion waveform, loaded from each bass event's packed high nibble. | Yes |
| `$17` | `AUDF0` | Channel 0 frequency-divider value (effectively 5 bits). Lower values generally give higher pitch for a fixed control mode. | Yes |
| `$18` | `AUDF1` | Channel 1 bass frequency-divider value. | Yes |
| `$19` | `AUDV0` | Channel 0 volume, low 4 bits: 0 silent through 15 loudest. Initialized to 0, then loaded from melody events. | Yes |
| `$1A` | `AUDV1` | Channel 1 bass volume. Initialized to 0, then loaded from bass events, including zero-volume rests. | Yes |

`AUDC` chooses divider/noise patterns, not sampled audio. An `AUDF` value's
audible pitch relationship depends on the channel's control mode.

### Graphics enable and motion

| Addr. | Register | Role | Used |
| ---: | --- | --- | --- |
| `$1B` | `GRP0` | Eight Player 0 graphic bits; 1 is visible player pixel, 0 transparent. | Yes |
| `$1C` | `GRP1` | Eight Player 1 graphic bits. | No |
| `$1D` | `ENAM0` | Missile 0 enable, bit 1. | No |
| `$1E` | `ENAM1` | Missile 1 enable, bit 1. | No |
| `$1F` | `ENABL` | Ball enable, bit 1. | No |
| `$20` | `HMP0` | Player 0 fine horizontal-motion value in bits 7-4. | Yes |
| `$21` | `HMP1` | Player 1 fine horizontal motion. | No |
| `$22` | `HMM0` | Missile 0 fine horizontal motion. | No |
| `$23` | `HMM1` | Missile 1 fine horizontal motion. | No |
| `$24` | `HMBL` | Ball fine horizontal motion. | No |
| `$25` | `VDELP0` | Delay Player 0 graphics one scanline. | No |
| `$26` | `VDELP1` | Delay Player 1 graphics one scanline. | No |
| `$27` | `VDELBL` | Delay ball enable one scanline. | No |
| `$28` | `RESMP0` | Lock/reset Missile 0 position relative to Player 0, bit 1. | No |
| `$29` | `RESMP1` | Lock/reset Missile 1 position relative to Player 1, bit 1. | No |
| `$2A` | `HMOVE` | Strobe applying all fine-motion registers. Written byte is irrelevant. | Yes |
| `$2B` | `HMCLR` | Strobe clearing all horizontal-motion registers. | No |
| `$2C` | `CXCLR` | Strobe clearing collision latches. | No |

## 8. TIA read map — collisions and inputs

The TIA uses separate read/write paths. Thus `LDA $00` reads a collision
latch, while `STA $00` writes `VSYNC`. Collision bits remain latched until
a write to `CXCLR`.

| Addr. | Read register | Role |
| ---: | --- | --- |
| `$00` | `CXM0P` | Missile 0 hit Player 1 (bit 7) / Player 0 (bit 6). |
| `$01` | `CXM1P` | Missile 1 hit Player 0 (bit 7) / Player 1 (bit 6). |
| `$02` | `CXP0FB` | Player 0 hit playfield (bit 7) / ball (bit 6). |
| `$03` | `CXP1FB` | Player 1 hit playfield (bit 7) / ball (bit 6). |
| `$04` | `CXM0FB` | Missile 0 hit playfield (bit 7) / ball (bit 6). |
| `$05` | `CXM1FB` | Missile 1 hit playfield (bit 7) / ball (bit 6). |
| `$06` | `CXBLPF` | Ball hit playfield (bit 7). |
| `$07` | `CXPPMM` | Player 0 hit Player 1 (bit 7) / Missile 0 hit Missile 1 (bit 6). |
| `$08` | `INPT0` | Controller input 0, normally paddle 0. |
| `$09` | `INPT1` | Controller input 1, normally paddle 1. |
| `$0A` | `INPT2` | Controller input 2, normally paddle 2. |
| `$0B` | `INPT3` | Controller input 3, normally paddle 3. |
| `$0C` | `INPT4` | Controller input 4, normally left fire button. |
| `$0D` | `INPT5` | Controller input 5, normally right fire button. |

The demo reads no controller or collision register because it is an automatic
demo.

## 9. Frame construction and display kernel

### Complete NTSC frame

One frame is 262 scanlines. Each line lasts 76 CPU cycles, or 228 TIA color
clocks.

| Region | Lines | Current implementation |
| --- | ---: | --- |
| VSYNC | 3 | Set `VBLANK=$02` and `VSYNC=$02`, issue three `WSYNC` strobes, then clear `VSYNC`. |
| VBLANK | 37 | Load `TIM64T=44`; run `UpdateState` and `PositionPlayer`; poll `INTIM`; use a final `WSYNC`; clear `VBLANK` on the boundary. |
| Visible | 192 | Call `DrawScreen`, which changes TIA registers in step with the beam. |
| Overscan | 30 | Set `VBLANK=$02`, load `TIM64T=36`, poll `INTIM`, issue one aligning `WSYNC`, and jump to `Frame`. |

`WSYNC` stores no useful byte. It halts the 6507 until the next scanline, so
instructions after it execute at a predictable horizontal location. The RIOT
timer continues independently while state updates and the two player-position
`WSYNC` boundaries execute during VBLANK.

### Visible-line accounting

| Visible block | Lines | Notes |
| --- | ---: | --- |
| Setup/partial line | 1 | Clears playfield, reflection, and `GRP0`; the first top-bar `WSYNC` closes it. |
| Top raster | `TopBarsLast + 1` | 15 lines. |
| Title | 42 | Seven source rows, each repeated six times. |
| Title gap | `TitleGapCount` | 6 lines. |
| Player/starfield | 40 | Software-positioned eight-row Player 0 over a scene-remapped star field. |
| Checker/grid | 32 | Two reflected patterns alternate in four-line-high cells. |
| Middle raster | 12 | Samples every other palette entry. |
| Ticker | 25 | Five source rows, each repeated five times. |
| Bottom raster | 19 | Background and playfield receive the same color. |

The top-raster count and title-gap count sum to 21. Vertical wave animates precomputed
letter rows inside the same fixed title box, so it does not alter region
heights. Intro-hidden regions still execute the same number of `WSYNC` lines.

### Color generation and aligned rasters

An NTSC TIA color byte is approximately `HHHH LLLx`: the upper nibble selects
hue, bits 3-1 select luminance, and bit 0 is not a useful luminance bit. `Hue`
is kept on a `$10` boundary and advances by `$10` every eighth frame. Effects
XOR its high nibble for related hues, OR in luminance, and finally AND every
nonblack display color with `TransitionMask`.

| Register | Demo role |
| --- | --- |
| `COLUBK` | Top, middle, and bottom raster colors; title background; checker background; black first ticker line. |
| `COLUPF` | Title, starfield, checker, ticker, and the bottom raster's playfield-matching color. |
| `COLUP0` | Current stage's bouncing Player 0 graphic. |

Top and middle raster colors are calculated before their `WSYNC`, then written
to `COLUBK` just after the new line begins. On the middle raster, the checker
playfield and reflection are cleared immediately afterward, still in the new
line's horizontal blank; this preserves the complete final checker scanline.
The first bottom color—palette index `(FrameCounter + 18) & 31`—is cached before
the ticker. Each later bottom color is calculated on the preceding line, so
both `COLUBK` and `COLUPF` change inside horizontal blank with no colored strip
at the left edge. Making the two colors equal also hides the ticker bits that
remain latched in `PF0-PF2`.

### Playfield order and 40-bit rewriting

TIA exposes 20 playfield bits per screen half. Each playfield bit is four color
clocks wide.

| Register | Left-to-right visible bit order |
| --- | --- |
| `PF0` | 4, 5, 6, 7; bits 0-3 are ignored by video |
| `PF1` | 7, 6, 5, 4, 3, 2, 1, 0 |
| `PF2` | 0, 1, 2, 3, 4, 5, 6, 7 |

With `CTRLPF` bit 0 clear, the 20-bit value repeats on the right. With it set,
the right half is reflected. The symmetric starfield and checker use
`CTRLPF=$01`. The title and ticker need 40 independent bits, so they use
`CTRLPF=$00`, write the left `PF0/PF1/PF2` values early, then replace all three
near the center after the left half has already appeared.

The normal ticker path uses six `NOP`s; its right-half stores land at cycles
40, 47, and 54. Its first scanline is specialized: left PF0 is loaded before
`WSYNC`, `STY COLUBK` makes the background black at cycle 3, and five `NOP`s
plus a `JMP` rejoin the common right-half path. The title writes its cached
background at cycle 3 and uses `BIT TitleBackground` plus three `NOP`s for a
nine-cycle delay before the right-half loads. These delays are part of the
kernel's horizontal layout.

### Player positioning, sprites, and starfield

The TIA has no ordinary X/Y coordinate registers:

- `RESP0` establishes coarse X from the cycle on which it is strobed.
- `HMP0` holds fine adjustment in bits 7-4; `HMOVE` applies it.
- `GRP0` supplies eight graphics bits for the current scanline.
- `NUSIZ0=$05` doubles each player bit horizontally to a 16-color-clock sprite.

`PositionPlayer` starts on `WSYNC`, repeatedly subtracts 15 from `SpriteX`,
converts the underflowed remainder with `EOR #7` and four `ASL`s, stores HMP0,
strobes RESP0, then applies HMOVE at the next scanline. The `SEC` immediately
after `WSYNC` is both the no-borrow setup and a two-cycle delay that avoids the
special low-coordinate HBLANK case.

Software supplies Y by clearing `GRP0` on each of the 40 region lines and
writing `SpriteBuffer[line - SpriteY]` only when the unsigned result is 0-7.
The requested X coordinate bounces from 13 through 130; Y bounces from 0 through
32, allowing an eight-line bitmap at 32 to end on region line 39. Position and
animation continue during intro phases where the sprite is not yet visible.

After the time-critical `GRP0` write, the kernel indexes three 32-row sparse
playfield planes through `StarPtr0-2`. The row index is `(line + offset) & 31`;
reflection makes the 20-bit left pattern span the screen. Stage selection
permutes the planes and chooses slow, medium, fast, or reverse drift.

## 10. Show sequencer, intro, stages, and transitions

### Counters and stage windows

`UpdateState` increments the 8-bit `FrameCounter` and 16-bit `DemoFrame` before
selecting effects. In normal operation, `DemoFrame` covers `$0000-$0FFF` and
wraps at `$1000`, giving four 1,024-frame stages. At nominal 60 Hz, one stage is
about 17.1 seconds and a complete steady-state loop is about 68.3 seconds.

The first pass after reset is special. `IntroActive=1` keeps the static title,
static sprite/star/checker assets, and full luminance mask while major
components are exposed one 256-frame stage at a time. The soundtrack continues
on its independent per-channel timers:

| `DemoFrame` interval | `IntroStage` | Visible major components |
| --- | ---: | --- |
| `$0000-$00FF` | 0 | Title; raster bands remain present. |
| `$0100-$01FF` | 1 | Add checker/grid. |
| `$0200-$02FF` | 2 | Add spaceship and its starfield. |
| `$0300-$03FF` | 3 | Add ticker. |

When the increment reaches `$0400`, `UpdateIntro` clears `IntroActive`, sets
`IntroStage=4`, leaves `DemoFrame` at `$0400`, and hands off directly to the
type-on/off second scene. There is no additional 1,024-frame hold on the static
first scene and no fade at this first handoff. Audio playback is unaffected by
the handoff.

`DemoFrame` is zero during reset initialization; because `UpdateState`
increments it before drawing, the first visible intro frame observes value 1.
The first pass then continues through type, ripple, and vertical wave before
wrapping to the ordinary static scene; every later loop runs static, type,
ripple, and vertical wave
in that order.

On later loops, the ordinary static stage occupies `$0000-$03FF`. The current
steady-state mappings are:

| `DemoFrame` | Stage / `ScenePattern` | Title | Sprite and checker | Star planes `(PF0, PF1, PF2)` / drift |
| --- | --- | --- | --- | --- |
| `$0000-$03FF` | Static / 0 | Complete generated reveal phase at row 84 | Alien/diamond; classic checker pair 0/1 | `(StarPF0, StarPF1, StarPF2)` / `FrameCounter >> 2` |
| `$0400-$07FF` | Type / 64 | 16-phase type-on/type-off cycle | Digital robot; block pair 2/3 | `(StarPF1, StarPF2, StarPF0)` / `FrameCounter >> 1` |
| `$0800-$0BFF` | Ripple / 128 | Eight horizontal ripple phases | UFO; narrow-band pair 4/5 | `(StarPF2, StarPF0, StarPF1)` / `FrameCounter` |
| `$0C00-$0FFF` | Vertical wave / 192 | Four independent vertical letter-wave phases | Space jellyfish; chunky pair 6/7 | `(StarPF0, StarPF2, StarPF1)` / unsigned `(-FrameCounter) >> 1` |

The type stage uses `(FrameCounter >> 4) & 15` to select a 16-entry sequence
built from five generated states containing 0, 2, 4, 6, or 8 letters. Each
selector entry lasts 16 frames. Ripple uses `(FrameCounter >> 3) & 7`, so each
phase lasts eight frames. Vertical wave uses `(FrameCounter >> 4) & 3` to hold each of
four independent vertical letter-wave phases for 16 frames.

For the checker, `ScenePattern >> 5` selects pair bases 0, 2, 4, or 6.
`(FrameCounter >> 2) & 1` selects the first phase, and the kernel toggles that
phase every four scanlines across the 32-line region. X counts down from 32;
the zero exit skips the unused final toggle and gives the first middle-raster
color enough time to be calculated before the boundary `WSYNC`.

### Progressive luminance transition

Normal stage changes use a 256-frame transition centered on the boundary. A
countdown begins 128 frames beforehand at `$0380`, `$0780`, `$0B80`, or `$0F80`.
The `$0380` start is suppressed during the one-time intro; the other three and
all starts on later loops operate normally. The final transition crosses the
`$1000 -> $0000` sequencer wrap.

`TransitionStepHi:TransitionStep` represents 256 initially, then counts down to
zero. Values 1-255 select `TransitionMasks[(step - 1) >> 1]`; the high-byte case
selects entry 127. Thus every one of the 128 table entries lasts two frames.

| Frames relative to boundary | Mask | Visible result |
| ---: | ---: | --- |
| -128 through -97 | `$FE` | All meaningful TIA luminance bits preserved. |
| -96 through -65 | `$FC` | Remove luminance bit 1. |
| -64 through -33 | `$F8` | Preserve only the top luminance bit. |
| -32 through +31 | `$F0` | Preserve hue only; the effect changes in this dark center. |
| +32 through +63 | `$F8` | Begin restoring luminance. |
| +64 through +95 | `$FC` | Restore the middle luminance bit. |
| +96 through +127 | `$FE` | Full useful luminance restored. |

With no active transition, and throughout the intro, the mask is `$FE`. It is
applied to raster bars, title foreground/background, player, starfield,
checker, and ticker colors; it changes luminance without altering playfield or
sprite bitmap data.

## 11. Scrolling ticker

The ticker is a 40-bit asymmetric playfield held in the 30-byte
`ScrollBuffer`. Its register-major layout is six groups of five row bytes:

| RAM offsets | Meaning |
| --- | --- |
| 0-4 | left PF0, rows 0-4 |
| 5-9 | left PF1 |
| 10-14 | left PF2 |
| 15-19 | right PF0 |
| 20-24 | right PF1 |
| 25-29 | right PF2 |

`SCROLL_DELAY=10` and the reset-only `SCROLL_INITIAL_DELAY=11`. Since
`UpdateState` runs before each visible frame, the seed image is shown for ten
complete frames before the first shift. On every later ten-frame event,
`UpdateState` calls its local `.shiftScrollOne` routine twice, advancing two
logical playfield pixels. At nominal 60 Hz that is 12 logical pixels per second.

Each compact ROM source byte holds one vertical column in bits 4-0 for text
rows 0-4. The routine fetches through `(ScrollPtr),Y`, advances the 16-bit
pointer with carry, and wraps from `ScrollColumnsEnd` to `ScrollColumns`.
`LSR`, `ROR`, and `ROL` then carry the new bit across the six differently
ordered PF register bytes for each row. `ScrollPtr` initially targets
`ScrollNextColumn`, because generated columns 0-39 already seed the visible
window. The circular stream contains 167 columns.

## 12. Frame-driven soundtrack

The 66.75-second soundtrack is a two-channel TIA adaptation of `Take On Me`.
Its musical source is derived from **Jukebox by Lloyd Russell**, published as a
type-in in **Your Sinclair issue 21, September 1987**, for the **ZX Spectrum
128K**. The recovered AY arrangement was reduced to the selected lead voice on
TIA channel 0 and the bass voice on channel 1.

The player is deliberately independent of `DemoFrame`, `ScenePattern`, and
all visual transitions. `UpdateState` calls `TakeOnMe_Update` exactly once per
NTSC frame. Each channel owns a 16-bit stream pointer and an 8-bit countdown, so
different note lengths and rests can proceed independently.

Each event is a compact three-byte record:

| Byte | Meaning |
| ---: | --- |
| 0 | Duration in 60 Hz video frames. Zero is the end marker. |
| 1 | Five-bit TIA `AUDF` frequency-divider value. |
| 2 | Packed `(AUDC << 4) | AUDV`: waveform/control in the high nibble and volume in the low nibble. |

`TakeOnMe_Init` points both readers at their stream starts, sets each timer to
one, and silences both TIA volumes. Therefore the first frame update immediately
loads intentional sound registers rather than exposing the reset-time frequency
value. `TakeOnMe_Update` decrements both timers and invokes a decoder only when
that channel reaches zero.

Each decoder performs the same steps:

1. Read the duration through the channel's zero-page indirect pointer.
2. If it is zero, restore that channel's start address and read again.
3. Store duration, `AUDF`, low-nibble volume, and high-nibble `AUDC`.
4. Advance the 16-bit pointer by three, including carry into the high byte.

The melody stream contains 168 events in 507 bytes; the bass stream contains
175 events in 528 bytes. Both total 4,005 frames (66.75 seconds at 60 Hz) before
their zero end markers and then loop. Event timing was rounded cumulatively
during conversion, preventing long-term tempo drift.

`AUDC` selects one of the TIA's divider/polynomial modes rather than a sampled
waveform, and `AUDF` is a divider rather than a MIDI note number. Consequently,
the exact timbre and tuning should be judged in Stella or on real NTSC hardware.
The ROM preview and source conversion may approximate the analog result, but the
shipped event bytes are the definitive playback data.

## 13. RIOT RAM, stack, I/O, and timer

### Project RAM allocation

| Address | Symbol | Bytes | Current role |
| ---: | --- | ---: | --- |
| `$80` | `FrameCounter` | 1 | Increments every frame; drives hue cadence, title phases, checker phase, stars, and rasters. |
| `$81` | `Hue` | 1 | Base hue, advanced by `$10` every eight frames and masked to `$F0`. |
| `$82` | `SpriteX` | 1 | Requested Player 0 horizontal coordinate. |
| `$83` | `SpriteDX` | 1 | Horizontal delta, 1 or `$FF` (-1). |
| `$84` | `SpriteY` | 1 | Sprite top within the 40-line player region. |
| `$85` | `SpriteDY` | 1 | Vertical delta, 1 or `$FF` (-1). |
| `$86` | `ScrollTick` | 1 | Ten-frame ticker countdown. |
| `$87-$88` | `ScrollPtr` | 2 | Little-endian pointer to the next compact ticker source column in ROM. |
| `$89` | `CheckerForeground` | 1 | Checker foreground cached before the first checker `WSYNC`. |
| `$8A` | `CheckerState` / `TitleBackground` / `ScrollBits` / `BottomBarColor` | 1 | Time-shared scratch: title background, star/checker phase, cached first bottom color, and VBLANK ticker-column bits. |
| `$8B-$A8` | `ScrollBuffer` | 30 | Current five-row, six-register asymmetric ticker image. |
| `$A9-$AA` | `DemoFrame` | 2 | Little-endian 0-4095 show counter; also supplies intro milestones and stage boundaries. |
| `$AB` | `TopBarsLast` | 1 | Inclusive descending top-raster index; currently 14. |
| `$AC` | `TitleGapCount` | 1 | Compensating gap count; currently 6. |
| `$AD` | `TitleFrame` | 1 | First row of the selected seven-row generated title phase. |
| `$AE` | `TitleFrameEnd` | 1 | One-past-last selected title row. |
| `$AF` | `ScenePattern` | 1 | Visual-table offset 0, 64, 128, or 192; also encodes scene identity. |
| `$B0-$B7` | `SpriteBuffer` | 8 | Active stage sprite copied from ROM during VBLANK. |
| `$B8` | `TransitionStep` | 1 | Low byte of the 256-to-0 transition countdown. |
| `$B9` | `TransitionMask` | 1 | `$FE/$FC/$F8/$F0` luminance mask used by every colored effect. |
| `$BA` | `TransitionStepHi` | 1 | High byte, equal to 1 only while the countdown represents 256. |
| `$BB-$BC` | `StarPtr0` | 2 | Little-endian pointer for the PF0 star plane. |
| `$BD-$BE` | `StarPtr1` | 2 | Little-endian pointer for the PF1 star plane. |
| `$BF-$C0` | `StarPtr2` | 2 | Little-endian pointer for the PF2 star plane. |
| `$C1` | `StarMode` | 1 | Stage number 0-3, selecting star speed/direction. |
| `$C2` | `IntroActive` | 1 | Nonzero only during the reset-time component reveal. |
| `$C3` | `IntroStage` | 1 | 0 title, 1 grid, 2 sprite/starfield, 3 ticker, 4 complete. |
| `$C4-$C5` | `MusicPtr0` | 2 | Little-endian pointer to the current melody event. |
| `$C6-$C7` | `MusicPtr1` | 2 | Little-endian pointer to the current bass event. |
| `$C8` | `MusicTimer0` | 1 | Melody frames remaining before the next event. |
| `$C9` | `MusicTimer1` | 1 | Bass frames remaining before the next event. |
| `$CA` | `CheckerBackground` | 1 | Checker background cached before the first checker `WSYNC`. |
| `$CB` | `CheckerHue` | 1 | Grid hue derived from `DemoFrame >> 1`; changes every 32 frames. |

Variables occupy 76 bytes, `$80-$CB`. `$CC-$F8` is available to ordinary state
without overlapping the deepest current stack use.
The 6507 stack uses the RIOT RAM mirror at the top of the page: SP starts at
`$FF`, each `JSR` pushes two bytes, and the deepest normal call path is three
levels (`Frame -> UpdateState -> TakeOnMe_Update -> decoder`). A decoder also
uses one `PHA`, so playback can touch `$F9-$FF`. There is no interrupt handler
or recursive call.

### RIOT register map

| Addr. | Register | Role | Used |
| ---: | --- | --- | --- |
| `$0280` | `SWCHA` | Joystick port A data: directions for both controller ports. | No |
| `$0281` | `SWACNT` | Data-direction register for `SWCHA`. | No |
| `$0282` | `SWCHB` | Console switches: reset/select/color-difficulty. | No |
| `$0283` | `SWBCNT` | Data-direction register for `SWCHB`. | No |
| `$0284` | `INTIM` | Current interval timer count; polled in VBLANK and overscan. | Yes, read |
| `$0285` | `TIMINT` | Timer underflow/interrupt status. | No |
| `$0294` | `TIM1T` | Start timer at one CPU cycle per decrement. | No |
| `$0295` | `TIM8T` | Start timer at eight CPU cycles per decrement. | No |
| `$0296` | `TIM64T` | Start timer at 64 CPU cycles per decrement; loaded with 44 in VBLANK and 36 in overscan. | Yes, write |
| `$0297` | `T1024T` | Start timer at 1,024 CPU cycles per decrement. | No |

The RIOT performs its first decrement immediately after the load, so 44 and 36
leave 43 and 35 full 64-cycle intervals: 2,752 cycles (about 36.2 lines) and
2,240 cycles (about 29.5 lines). Polling stops when `INTIM` reaches zero, and a
final `WSYNC` rounds each blank region to its documented scanline count.

## 14. Routine map

Addresses below are from the current `build/squeepty.sym`. All routines may
clobber A, X, Y, and flags unless their caller relies on a specific live value.

| Address | Routine | Responsibility |
| ---: | --- | --- |
| `$F000` | `Reset` | Set flags and SP, clear `$00-$FF`, initialize motion/intro/ticker/audio, seed `ScrollBuffer`, then fall through to `Frame`. |
| `$F03E` | `Frame` | Emit VSYNC/VBLANK/visible/overscan regions forever. |
| `$F07A` | `UpdateState` | Increment counters; select intro, transition, scene, stars, and sprite; update hue, bounce, ticker, and both audio channels. |
| `$F0FC` | `.shiftScrollOne` | Local `UpdateState` subroutine that consumes one compact column and rotates all five ticker rows by one bit. |
| `$F13B` | `UpdateIntro` | Advance reveal milestones and perform the direct `$0400` handoff to scene two. |
| `$F16D` | `UpdateTransition` | Start/age the 256-frame transition and select its luminance mask. |
| `$F1C3` | `UpdateTitleEffect` | Set title phase and `ScenePattern` for static, type, ripple, or vertical wave. |
| `$F246` | `LoadSpriteFrame` | Convert the scene offset to 0/8/16/24 and copy eight ROM bitmap bytes to RAM. |
| `$F25A` | `LoadStarPattern` | Select scene plane pointers and store `StarMode`. |
| `$F27D` | `PositionPlayer` | Convert logical X to RESP0 coarse timing and HMP0/HMOVE fine positioning over two WSYNC boundaries. |
| `$F295` | `DrawScreen` | Run the complete 192-line visible kernel; returns at `$F4DF`. |
| `$F5E4` | `TakeOnMe_Init` | Initialize the two event pointers/timers and silence both channels. |
| `$F601` | `TakeOnMe_Update` | Decrement both independent timers and dispatch expired events. |
| `$F610` | `TakeOnMe_Load0` | Decode one melody event, write channel 0, and advance its pointer. |
| `$F643` | `TakeOnMe_Load1` | Decode one bass event, write channel 1, and advance its pointer. |

Main program/display code is contiguous from `$F000-$F4DF` (1,248 bytes).
`$F4E0-$F4FF` is alignment padding before the read-only tables; the compact
music player resides at `$F5E4-$F675` immediately before its event streams.

## 15. ROM tables and generated assets

### Hand-authored tables

| Address range | Label | Bytes | Contents |
| ---: | --- | ---: | --- |
| `$F500-$F51F` | `Rainbow` | 32 | Forward raster palette. |
| `$F520-$F53F` | `RainbowReverse` | 32 | Reverse/complementary bottom palette. |
| `$F540-$F55F` | `SpriteBitmaps` | 32 | Four eight-row stage sprites. |
| `$F560-$F567` | `CheckerPF0` | 8 | Four complementary PF0 pattern pairs. |
| `$F568-$F56F` | `CheckerPF1` | 8 | Four complementary PF1 pattern pairs. |
| `$F570-$F577` | `CheckerPF2` | 8 | Four complementary PF2 pattern pairs. |
| `$F578-$F597` | `StarPF0` | 32 | Sparse star plane 0. |
| `$F598-$F5B7` | `StarPF1` | 32 | Sparse star plane 1. |
| `$F5B8-$F5D7` | `StarPF2` | 32 | Sparse star plane 2. |
| `$F5D8-$F5DB` | `StarPlane0Low` | 4 | Per-stage low pointer bytes for PF0. |
| `$F5DC-$F5DF` | `StarPlane1Low` | 4 | Per-stage low pointer bytes for PF1. |
| `$F5E0-$F5E3` | `StarPlane2Low` | 4 | Per-stage low pointer bytes for PF2. |
| `$F5E4-$F600` | `TakeOnMe_Init` | 29 | Event-pointer/timer initialization and startup mute. |
| `$F601-$F60F` | `TakeOnMe_Update` | 15 | Per-frame independent timer update. |
| `$F610-$F642` | `TakeOnMe_Load0` | 51 | Melody event decoder. |
| `$F643-$F675` | `TakeOnMe_Load1` | 51 | Bass event decoder. |
| `$F676-$F870` | `TakeOnMeMelody` | 507 | 168 melody events plus a three-byte loop marker. |
| `$F871-$FA80` | `TakeOnMeBass` | 528 | 175 bass events plus a three-byte loop marker. |
| `$FA81-$FA88` | `RippleFrameOffsets` | 8 | Generated-title row bases 0, 7, ..., 49. |
| `$FA89-$FA98` | `RevealFrameOffsets` | 16 | Row bases for the forward/backward type cycle. |
| `$FA99-$FA9C` | `VerticalFrameOffsets` | 4 | Row bases for the four vertical-wave phases. |
| `$FA9D-$FA9F` | `IntroMilestoneLow` | 3 | Low bytes for frames 256, 512, and 768; all zero. |
| `$FAA0-$FAA2` | `IntroMilestoneHigh` | 3 | High bytes 1, 2, and 3. |
| `$FAA3-$FAA6` | `TransitionStartLow` | 4 | Low bytes `$80` for each pre-boundary start. |
| `$FAA7-$FAAA` | `TransitionStartHigh` | 4 | High bytes 3, 7, 11, and 15. |
| `$FAAB-$FB2A` | `TransitionMasks` | 128 | Two-frames-per-entry luminance curve. |

`$FB2B-$FBFF` is alignment padding before the generated title data.

### Asset generator and emitted tables

`tools/gen_assets.py` owns `build/assets.inc`; the generated include must not be
edited by hand. Its `encode_half` routine converts left-to-right pixels to the
TIA's PF0/PF1/PF2 bit orders, and `encode_row` pads or clips each result to 40
logical pixels before encoding independent left and right halves.

The 4x7 title font renders `SQUEEPTY` with one-column character spacing. The 17
precomputed phases comprise eight horizontal ripples, five reveal states with
zero/two/four/six/eight letters, and four independent vertical waves. At seven
rows each, they occupy 119 bytes in each of six register-specific tables. The
generator aligns pairs so any Y index from 0 through 118 stays on the same ROM
page and cannot add a page-cross cycle to the title kernel.

| Address range | Generated label | Bytes | Contents |
| ---: | --- | ---: | --- |
| `$FC00-$FC76` | `TitlePF0L` | 119 | Left PF0 for all 17 title phases. |
| `$FC77-$FCED` | `TitlePF1L` | 119 | Left PF1; followed by 18 alignment bytes. |
| `$FD00-$FD76` | `TitlePF2L` | 119 | Left PF2. |
| `$FD77-$FDED` | `TitlePF0R` | 119 | Right PF0; followed by 18 alignment bytes. |
| `$FE00-$FE76` | `TitlePF1R` | 119 | Right PF1. |
| `$FE77-$FEED` | `TitlePF2R` | 119 | Right PF2. |
| `$FEEE-$FF0B` | `ScrollInitial` | 30 | Register-major encoding of ticker columns 0-39. |
| `$FF0C-$FF33` | `ScrollColumns` | 40 | First 40 columns retained as the circular-wrap prefix. |
| `$FF34-$FFB2` | `ScrollNextColumn` | 127 | Columns 40-166, the reset-time pointer target. |

The ticker uses a 3x5 font with one column of spacing and the message
`"    GREETINGS TO ALL ATARI DREAMERS...    "`. The generator packs each of
its 167 vertical columns into bits 4-0, emits `ScrollColumnsEnd` as the
non-data end label at `$FFB3`, and defines `SCROLL_COLUMN_COUNT=$A7` (167).

`$FFB3-$FFFB` is currently unassigned cartridge space (73 bytes). The final
four bytes are fixed vectors: `$FFFC-$FFFD` contains little-endian `$F000` for
reset, and `$FFFE-$FFFF` contains the same address for IRQ/BRK. The assembled
image is exactly 4,096 bytes and uses no bank switching.

For a narrative walkthrough, see [`BEGINNER_GUIDE.md`](BEGINNER_GUIDE.md).
When code or table sizes change, rebuild before relying on the symbol-derived
ROM addresses in sections 14 and 15.
