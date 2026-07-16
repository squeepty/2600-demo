The Teeny-tiny Atari 2600 demo
==============================

A compact, automatic Atari 2600 demo for NTSC systems.

Release date: Thursday, July 16, 2026
Production: The Teeny-tiny Atari 2600 demo
Platform: Atari 2600 / Atari VCS (NTSC)
Type: demo
Group: Squeepty

FILES
-----

SQUEEPTY.BIN    4096-byte, plain 4K Atari 2600 cartridge ROM
SQUEEPTY.NFO    Release information and credits
FILE_ID.DIZ     Short archive description

RUNNING
-------

Open SQUEEPTY.BIN in an Atari 2600 emulator such as Stella, or use a
suitable 4K-compatible flash cartridge on NTSC Atari 2600 hardware.

The demo runs automatically and reads no controls.

SHOW FLOW
---------

The one-time introduction reveals one major layer every 256 frames:

1. SQUEEPTY title
2. checker/grid
3. bouncing spaceship and moving starfield
4. scrolling ticker

Scene 2 begins as soon as the fourth reveal stage ends. The fully revealed
first scene is not held for another 1,024-frame scene interval.

The continuing show has four timed visual scenes:

1. static title, alien/diamond sprite, classic checks and slow stars
2. type-on/type-off title, robot sprite, digital blocks and medium stars
3. horizontal title ripple, UFO sprite, narrow bands and fast stars
4. vertical-wave title, space-jellyfish sprite, chunky blocks and
   reverse-drifting stars

All player shapes bounce horizontally and vertically. Regular scene changes
use a 256-frame luminance fade centered on the effect switch.

SOUND
-----

The 66.75-second soundtrack is a two-channel TIA adaptation of Take On Me. Its
musical source is derived from Jukebox by Lloyd Russell, published as a type-in
in Your Sinclair issue 21, September 1987, for the ZX Spectrum 128K. Channel 0
carries the selected AY lead voice and channel 1 carries the bass. Compact
event streams update duration, pitch, waveform and volume once per NTSC frame,
run independently of the visual scene counter, and loop at the end.

OTHER FEATURES
--------------

* Flowing top, middle and bottom raster bars
* Color-cycling background behind the 40-bit SQUEEPTY title
* Scene-specific sparse starfields, checker patterns and player sprites
* Compact five-row GREETINGS TO ALL ATARI DREAMERS... ticker
* Fixed 262-scanline NTSC frame

TECHNICAL
---------

The frame contains 3 VSYNC, 37 VBLANK, 192 visible and 30 overscan lines.
The ticker is shifted from compact five-bit source columns into a 30-byte
RAM screen buffer during VBLANK. The ROM uses no bank switching and is
exactly 4,096 bytes.

SHA-256 (SQUEEPTY.BIN)
cc1ba8e23eeacf973e8ce27116f8d0fbff9d59bcdfd367cde2ffec40b00c2430

SOURCE / VIDEO
--------------

Source: https://github.com/squeepty/2600-demo
Video:  https://www.youtube.com/watch?v=SjKJ531LlC0

Enjoy!
