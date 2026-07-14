# SQUEEPTY 2600 Demo

Video here: [https://www.youtube.com/watch?v=SjKJ531LlC0](https://www.youtube.com/watch?v=SjKJ531LlC0)

Download: [submission ZIP](downloads/SQUEEPTY_2600_Demo.zip) | [ROM only](https://github.com/squeepty/2600-demo/raw/refs/heads/main/downloads/squeepty-2600-demo.bin)

A small, deliberately first-demo-sized Atari 2600 ROM:

- color-cycling raster bars and title background
- large `SQUEEPTY` playfield title
- horizontally and vertically bouncing player sprite
- animated checker playfield
- scrolling `GREETINGS TO ALL ATARI DREAMERS...` ticker
- simple two-voice TIA melody
- fixed 262-scanline NTSC frame

## Build

Install [DASM](https://dasm-assembler.github.io/), then run:

```sh
make
make check
make release
```

The downloadable cartridge image is written to `downloads/squeepty-2600-demo.bin`.
It is a plain 4K ROM with no bank switching.

[Download the ready-to-run submission ZIP](downloads/SQUEEPTY_2600_Demo.zip) or the
[ROM on its own](downloads/squeepty-2600-demo.bin).

## Run

Open `downloads/squeepty-2600-demo.bin` in Stella. The demo is automatic and has no
controls.

On macOS with Stella installed in `/Applications`:

```sh
open -na Stella --args "$PWD/downloads/squeepty-2600-demo.bin"
```

## Layout

- `src/demo.asm`: 6502/TIA program and display kernel
- `tools/gen_assets.py`: converts small bitmap fonts into TIA playfield data
- `downloads/squeepty-2600-demo.bin`: ready-to-run Atari 2600 cartridge image
- `build/assets.inc`: generated title and scroll data
- `BEGINNER_GUIDE.md`: detailed hardware, design, timing, and code walkthrough
- `ASSEMBLY_HARDWARE_REFERENCE.md`: complete 6507 instruction, register, and TIA/RIOT address reference

The kernel favors robust, readable effects over cycle-maximal tricks. The
playfield text uses separate left and right writes on each scanline, while
the ticker animation is generated ahead of time to keep the visible kernel
comfortably inside 76 CPU cycles per scanline.
