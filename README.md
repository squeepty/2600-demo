# SQUEEPTY 2600 Demo

Video here: (https://www.youtube.com/watch?v=SjKJ531LlC0)[https://www.youtube.com/watch?v=SjKJ531LlC0]

A small, deliberately first-demo-sized Atari 2600 ROM:

- color-cycling raster bars and title background
- large `SQUEEPTY` playfield title
- horizontally and vertically bouncing player sprite
- animated checker playfield
- short scrolling `HELLO FROM SQUEEPTY / 2600 DEMO` ticker
- simple two-voice TIA melody
- fixed 262-scanline NTSC frame

## Build

Install [DASM](https://dasm-assembler.github.io/), then run:

```sh
make
make check
```

The cartridge image is written to `build/squeepty.bin`. It is a plain 4K
ROM with no bank switching.

## Run

Open `build/squeepty.bin` in Stella. The demo is automatic and has no
controls.

On macOS with Stella installed in `/Applications`:

```sh
open -na Stella --args "$PWD/build/squeepty.bin"
```

## Layout

- `src/demo.asm`: 6502/TIA program and display kernel
- `tools/gen_assets.py`: converts small bitmap fonts into TIA playfield data
- `build/assets.inc`: generated title and scroll data
- `BEGINNER_GUIDE.md`: detailed hardware, design, timing, and code walkthrough

The kernel favors robust, readable effects over cycle-maximal tricks. The
playfield text uses separate left and right writes on each scanline, while
the ticker animation is generated ahead of time to keep the visible kernel
comfortably inside 76 CPU cycles per scanline.
