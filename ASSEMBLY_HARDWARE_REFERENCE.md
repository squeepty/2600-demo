# SQUEEPTY Assembly and Hardware Reference

This is the lookup reference for [`src/demo.asm`](src/demo.asm). It covers the
official 6502 instruction vocabulary, every mnemonic and DASM directive used by
this ROM, CPU/RAM registers, and the TIA/RIOT hardware addresses that produce
its video and sound.

Scope:

- The instruction table lists every documented, official 6502 mnemonic. The
  6507 in an Atari 2600 executes the same instruction set.
- The **Used** column identifies every CPU mnemonic that actually occurs in
  `src/demo.asm`.
- TIA read and write maps are complete. The project-specific tables identify
  what SQUEEPTY uses. Undocumented CPU opcodes are intentionally excluded.

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
| `X` index | 8 | Clear-loop index, scanline/repetition counter, and music-table index. |
| `Y` index | 8 | Title/sprite/checker row index and indirect ticker-pointer offset. |
| `SP` stack pointer | 8 | Points into the hardware stack; initialized to `$FF` by `TXS`. The stack grows downward. |
| `PC` program counter | 16 | Address of next instruction; loaded at reset from `$FFFC-$FFFD`. |
| `P` processor status | flags | Arithmetic, branch, decimal, and interrupt state. |

| Flag | Meaning | Use in SQUEEPTY |
| --- | --- | --- |
| `C` carry | Unsigned carry/no-borrow; receives shifted-out bits. | `CLC` before ordinary `ADC`; `SEC` before `SBC`; `BCC`/ `BCS` compare coordinates and run the position loop. |
| `Z` zero | Set when result is zero. | `BNE` controls most loops and timer polling. |
| `I` interrupt disable | Masks IRQ on a full 6502. | `SEI` gives reset a known state. The 6507 lacks an external IRQ pin, but `BRK` remains valid. |
| `D` decimal | Enables BCD behavior for `ADC`/`SBC`. | `CLD` forces normal binary coordinate and pointer arithmetic. |
| `B` break | Status representation pushed by `BRK`/`PHP`; not an ordinary latch. | IRQ/BRK vector points to `Reset`. |
| `V` overflow | Signed two's-complement overflow. | Not tested by this ROM. |
| `N` negative | Copy of result bit 7. | `BPL` stops the ticker copy after `DEY` turns zero into `$FF`. |

Bit 5 of a pushed status byte is conventionally set; it is not an independently
controlled CPU flag.

## 3. Addressing modes and DASM syntax

| Form | Mode | Meaning / example |
| --- | --- | --- |
| `#value` | Immediate | Literal byte: `lda #28`. |
| `label`, `$nn` | Zero page or absolute | Read/write address: `sta SpriteX`, `lda INTIM`. DASM picks zero-page encoding when possible. |
| `label,x` | X-indexed | Base plus `X`: `lda Melody,x`, `sta $00,x`. |
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
| `BEQ` | Branch if Z is set | tests Z | No |
| `BIT` | Test A against memory; copy memory bit 7/6 to N/V | N Z V | Yes |
| `BMI` | Branch if N is set | tests N | No |
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
| `DEC` | Decrement memory | N Z | No |
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
| `PHA` | Push A | — | No |
| `PHP` | Push status | — | No |
| `PLA` | Pull stack byte into A | N Z | No |
| `PLP` | Pull status | all restored | No |
| `ROL` | Rotate A/memory left through C | N Z C | No |
| `ROR` | Rotate A/memory right through C | N Z C | No |
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
| Arithmetic/bit shaping | `ADC SBC INC ASL LSR AND ORA EOR BIT` | Sprite motion, pointer advance, palette modulo, color construction, fine-motion encoding, and an exact three-cycle title delay. |
| Comparisons/control | `CMP CPX CPY BCC BCS BNE BPL JMP JSR RTS` | Sprite bounds, loops, polling, and routine calls. |
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
| `ALIGN 256` | Advance to the next page boundary; helps indexed palette loads avoid variable page-cross timing. |
| `byte ...` | Emit one or more data bytes. |
| `word label` | Emit a 16-bit little-endian address; used for CPU vectors. |
| `include "build/assets.inc"` | Insert generated title/ticker tables at assembly time. |
| `Label` | Name current address, e.g. `Reset`, `Frame`, `DrawScreen`. |
| `.local` | Local label associated with the surrounding major label, e.g. `.titleLine`. |

## 6. Memory map

| Address/range | Device | Role |
| --- | --- | --- |
| `$0000-$003F` | TIA | Read/write register window. Read and write meanings differ at the same address; the window is mirrored. |
| `$0080-$00FF` | RIOT RAM | Console's 128 physical RAM bytes. This program uses `$80-$A8`; stack occupies upper RAM. |
| `$0280-$0297` | RIOT I/O/timer | Controller/console ports and interval timer. |
| `$F000-$FFFF` | 4 KiB ROM | Code, tables, generated assets, and vectors. |
| `$FFFC-$FFFD` | Reset vector | Little-endian entry address, set to `Reset`. |
| `$FFFE-$FFFF` | IRQ/BRK vector | Also set to `Reset`. |

The reset loop writes `STA $00,x` as X counts through all 256 byte values.
That clears TIA writable registers and their mirrors, then RIOT RAM at
`$80-$FF`.

## 7. TIA write map — video, positioning, and audio

TIA writes usually act on hardware immediately rather than storing ordinary
memory. **Used** means this ROM writes the address.

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
| `$15` | `AUDC0` | Channel 0 control/distortion waveform (low 4 bits). Reset value `$04`. | Yes |
| `$16` | `AUDC1` | Channel 1 control/distortion waveform. Reset value `$06`. | Yes |
| `$17` | `AUDF0` | Channel 0 frequency-divider value (effectively 5 bits). Lower values generally give higher pitch for a fixed control mode. | Yes |
| `$18` | `AUDF1` | Channel 1 frequency-divider value. | Yes |
| `$19` | `AUDV0` | Channel 0 volume, low 4 bits: 0 silent through 15 loudest. Reset value 4. | Yes |
| `$1A` | `AUDV1` | Channel 1 volume. Reset value 2. | Yes |

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

SQUEEPTY reads no controller or collision register because it is an automatic
demo.

## 9. How this ROM uses the video registers

### Frame timing

One NTSC frame is 262 lines, at 76 CPU cycles (228 color clocks) per line.

| Region | Lines | Relevant actions |
| --- | ---: | --- |
| VSYNC | 3 | `VBLANK=$02`, `VSYNC=$02`, then three `WSYNC` writes; clear `VSYNC`. |
| VBLANK | 37 | Start `TIM64T=44`, update state and position P0 while blanked, poll `INTIM`, clear `VBLANK` at a line boundary. |
| Visible | 192 | `DrawScreen` races the beam, changing color/playfield/player registers. |
| Overscan | 30 | Set `VBLANK`, start `TIM64T=36`, poll, `WSYNC`, restart frame. |

`WSYNC` is the scanline metronome. It stores nothing useful: it simply holds
the CPU until the next line begins, so code immediately after it runs near the
left edge of a scanline.

### Color roles

An NTSC TIA color byte is approximately `HHHH LLLx`: high nibble hue, useful
lower bits luminance. This demo keeps `Hue` with its lower bits clear, then
uses `ORA` for brightness and `EOR` to make related hues.

| Register | SQUEEPTY role |
| --- | --- |
| `COLUBK` | Per-line top/middle/bottom raster bars; checker background; blank title/ticker space. |
| `COLUPF` | Title, checker, and ticker playfield color. |
| `COLUP0` | Bouncing Player 0 sprite color. |

### Playfield roles

TIA has 20 playfield bits per half. Each bit is four color clocks wide.

| Register | Display bit order |
| --- | --- |
| `PF0` | 4, 5, 6, 7 — only upper nibble visible |
| `PF1` | 7, 6, 5, 4, 3, 2, 1, 0 |
| `PF2` | 0, 1, 2, 3, 4, 5, 6, 7 |

With `CTRLPF` bit 0 clear, that left 20-bit pattern repeats on the right.
With it set, it mirrors. The checker uses `CTRLPF=$01`; title and ticker need
40 independent bits, so use `CTRLPF=$00` and rewrite `PF0-PF2` near the
center of each line. The ticker uses six `NOP`s for its horizontal delay. The
title uses `BIT` plus three `NOP`s because its horizontal-blank background
write already consumes three cycles.

### Player 0 roles

The TIA has no ordinary X/Y coordinate registers.

- `RESP0` establishes coarse X from *when* it is written.
- `HMP0` stores a fine adjustment in its high nibble; `HMOVE` commits it.
- `GRP0` supplies the eight pixels for the current line. Software creates Y
  by writing one bitmap row only on the desired eight scanlines.
- `NUSIZ0=$05` doubles Player 0 pixel width.

`PositionPlayer` repeatedly subtracts 15 from `SpriteX` to move the
`RESP0` strobe in coarse chunks, converts the remainder for `HMP0`, and
strobes `HMOVE` on the next scanline. `SEC` follows `WSYNC` so its two cycles
keep the low-coordinate `RESP0` write out of the TIA's special HBLANK case;
this makes the left bounce continuous. The routine runs during VBLANK, so
intermediate timing is invisible.

## 10. Audio behavior

| Voice | Reset setup | Per-update action |
| --- | --- | --- |
| 0 | `AUDC0=$04`, `AUDV0=4` | Load `AUDF0` from `Melody,x`. |
| 1 | `AUDC1=$06`, `AUDV1=2` | Load `AUDF1` from `Bass,x`. |

Every 16 frames, `MusicStep` increments and `AND #15` keeps it in the
16-entry note tables. At about 60 Hz, this is roughly 3.75 divider changes per
second. Control and volume stay fixed after reset; only the frequency dividers
move.

## 11. RIOT RAM, I/O, and timer

### Project RAM allocation

| Address | Symbol | Bytes | Role |
| ---: | --- | ---: | --- |
| `$80` | `FrameCounter` | 1 | Increments per frame; drives palette and periodic events. |
| `$81` | `Hue` | 1 | Base hue, advanced by `$10` every eight frames. |
| `$82` | `SpriteX` | 1 | Requested Player 0 horizontal coordinate. |
| `$83` | `SpriteDX` | 1 | Horizontal delta: 1 or `$FF` (-1). |
| `$84` | `SpriteY` | 1 | Sprite top inside 40-line sprite region. |
| `$85` | `SpriteDY` | 1 | Vertical delta. |
| `$86` | `ScrollTick` | 1 | Ten-frame ticker-speed divider. |
| `$87-$88` | `ScrollPtr` | 2 | Little-endian pointer to selected 30-byte ticker frame in ROM. |
| `$89` | `MusicStep` | 1 | Current 0-15 note-table index. |
| `$8A` | `CheckerState` / `TitleBackground` | 1 | Holds cached title background, then one of two checker patterns. |
| `$8B-$A8` | `ScrollBuffer` | 30 | Current 5-row, six-register ticker image. |

### RIOT register map

| Addr. | Register | Role | Used |
| ---: | --- | --- | --- |
| `$0280` | `SWCHA` | Joystick port A data: directions for both controller ports. | No |
| `$0281` | `SWACNT` | Data-direction register for `SWCHA`. | No |
| `$0282` | `SWCHB` | Console switches: reset/select/color-difficulty. | No |
| `$0283` | `SWBCNT` | Data-direction register for `SWCHB`. | No |
| `$0284` | `INTIM` | Current interval timer count; polled in VBLANK and overscan. | Yes, read |
| `$0285` | `TIMINT` | Timer underflow/interrupt status. | No |
| `$0294` | `TIM1T` | Start timer: 1 CPU cycle per decrement. | No |
| `$0295` | `TIM8T` | Start timer: 8 CPU cycles per decrement. | No |
| `$0296` | `TIM64T` | Start timer: 64 CPU cycles per decrement. Written as 44 (VBLANK) and 36 (overscan). | Yes, write |
| `$0297` | `T1024T` | Start timer: 1024 CPU cycles per decrement. | No |

The RIOT performs its first decrement immediately after the load, so values 44
and 36 leave 43 and 35 complete 64-cycle intervals. The code polls only until
`INTIM` first reaches zero, then writes `WSYNC` to round the blank region up to
a clean scanline boundary.

## 12. Reading map for the source

| Section | Refer back to |
| --- | --- |
| `Reset` | CPU flags/stack, the `$00,x` clear loop, `NUSIZ0`, and audio setup. |
| `Frame` | `VSYNC`, `VBLANK`, `WSYNC`, `TIM64T`, and `INTIM`. |
| `UpdateState` | Carry-aware arithmetic, branches, `ScrollPtr` indirect indexing, `AUDF0/1`. |
| `PositionPlayer` | Timing-strobe behavior of `RESP0`, `HMP0`, and `HMOVE`. |
| `DrawScreen` | 76-cycle scanlines, TIA colors, playfield registers, and `GRP0`. |
| Tables/vectors | `byte`, `ALIGN`, `include`, `word`, and little-endian data. |

For a narrative walkthrough of the current effects and frame construction, see
[`BEGINNER_GUIDE.md`](BEGINNER_GUIDE.md). This file is intended as the
complete instruction/register/address lookup while editing the assembly.
