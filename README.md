# The Teeny-tiny Atari 2600 demo

Release date: Thursday, July 16, 2026

Video: [https://www.youtube.com/watch?v=SjKJ531LlC0](https://www.youtube.com/watch?v=SjKJ531LlC0)

Download: [submission ZIP](downloads/SQUEEPTY_2600_Demo.zip) | [ROM only](https://github.com/squeepty/2600-demo/raw/refs/heads/main/downloads/squeepty-2600-demo.bin)

The Teeny-tiny Atari 2600 demo is an automatic 4 KiB NTSC production built
around four timed visual scenes and an independent two-channel soundtrack. It
includes:

- flowing top, middle, and bottom raster bars with a color-cycling title
  background
- a large, asymmetric 40-bit `SQUEEPTY` playfield title
- four title treatments: static, type-on/type-off, horizontal ripple, and
  vertical wave
- four scene-specific player bitmaps that bounce horizontally and vertically
- a sparse reflected starfield with a different plane mapping and motion in
  each scene
- four animated checker/grid styles synchronized to the scene
- a compact five-row `GREETINGS TO ALL ATARI DREAMERS...` ticker
- a 66.75-second, two-channel TIA adaptation of `Take On Me`
- luminance fades centered on regular scene changes
- a fixed 262-scanline NTSC frame

## Show flow

The first scene doubles as a one-time progressive introduction. One major
content layer appears every 256 frames (about 4.27 seconds):

1. `SQUEEPTY` title
2. checker/grid
3. bouncing spaceship and starfield
4. scrolling ticker

The demo enters scene 2 as soon as the fourth reveal stage ends; it does not
hold the fully revealed first scene for another 1,024-frame scene interval.
The continuing show cycles through these four scenes:

| Scene | Title and visual variant |
| --- | --- |
| 1 — Static | Fixed title, alien/diamond sprite, classic checks, slow stars |
| 2 — Type | Letters type on and off, robot sprite, digital blocks, medium stars |
| 3 — Ripple | Travelling horizontal title ripple, UFO sprite, narrow bands, fast stars |
| 4 — Vertical wave | Fixed title region with independently waving letters, space-jellyfish sprite, chunky blocks, reverse-drifting stars |

## Music credit

The soundtrack is derived from **Jukebox by Lloyd Russell**, published as a
type-in in **Your Sinclair issue 21, September 1987**, for the **ZX Spectrum
128K**. The recovered AY arrangement was converted into compact TIA events:
channel 0 carries the selected lead voice and channel 1 carries the bass. Both
channels update from independent duration, frequency, waveform, and volume
events once per NTSC frame and loop at the end. The music runs independently
of the visual scene counter.

Regular scene boundaries use a 256-frame luminance fade, with the visual
change at its dark midpoint.

## Build

Install [DASM](https://dasm-assembler.github.io/) and Python 3. The release
target also needs `zip` and `unzip`. Then run:

```sh
make          # generate assets and assemble the ROM
make check    # report the exact byte count and SHA-256
make release  # build the submission archive
```

The playable cartridge image is written to
`downloads/squeepty-2600-demo.bin`. It is exactly 4,096 bytes: a plain 4K ROM
with no bank switching. `make release` writes
`downloads/SQUEEPTY_2600_Demo.zip` and packages the ROM as `SQUEEPTY.BIN` with
the release README, NFO, and FILE_ID.DIZ.

## Run

Open `downloads/squeepty-2600-demo.bin` in Stella or use a suitable 4K flash
cartridge on NTSC Atari 2600 hardware. The demo is automatic and reads no
controls.

On macOS with Stella installed in `/Applications`:

```sh
open -na Stella --args "$PWD/downloads/squeepty-2600-demo.bin"
```

## Layout

- `src/demo.asm`: documented 6502/TIA program, state updates, and display
  kernel
- `src/take_on_me_tia_data.inc`: compact two-channel soundtrack event streams
- `tools/gen_assets.py`: generates title phases and compact ticker data
- `build/assets.inc`: generated playfield tables; do not edit by hand
- `downloads/squeepty-2600-demo.bin`: ready-to-run cartridge image
- `release/`: text files packaged by `make release`
- `BEGINNER_GUIDE.md`: hardware, design, timing, build, and code walkthrough
- `ASSEMBLY_HARDWARE_REFERENCE.md`: 6507, TIA, RIOT, and address reference

The frame contains 3 VSYNC, 37 VBLANK, 192 visible, and 30 overscan lines. The
kernel rewrites the playfield at mid-scanline for independent title and ticker
halves. The ticker keeps only a 30-byte screen buffer in RAM and shifts compact
five-bit source columns during VBLANK, keeping its visible path within the
Atari 2600's 76-cycle scanline budget.
