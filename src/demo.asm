; =============================================================================
; SQUEEPTY - a small NTSC Atari 2600 demo
; =============================================================================
;
; This file is assembled by DASM for the 6507 CPU inside the Atari 2600.
; The 6507 uses the same instruction set as a 6502, so DASM's "6502"
; processor mode is the right choice.
;
; The most important Atari 2600 idea is that there is no framebuffer. The
; program cannot draw a complete picture into memory and display it later.
; Instead, it changes TIA graphics registers while the television beam moves
; from left to right and top to bottom. Code that does this is called a
; display kernel, or "racing the beam."
;
; This ROM builds one 262-scanline NTSC frame approximately 60 times/second:
;
;     3 lines  VSYNC      tell the television a new frame is starting
;    37 lines  VBLANK     update animation and position the player
;   192 lines  visible    draw all demo effects
;    30 lines  overscan   blank time at the bottom of the frame
;   ---------
;   262 lines total
;
; A scanline lasts 76 CPU cycles (228 color clocks). Visible kernels must
; finish their work before the next line starts. Writing any value to WSYNC
; pauses the CPU until the beginning of the next scanline, which makes it the
; basic timing tool used throughout DrawScreen.
;
; Useful DASM/6502 syntax seen below:
;
;     #10       immediate value 10, rather than memory address 10
;     $10       hexadecimal 10 (decimal 16)
;     %00010000 binary value
;     <Label    low byte of Label's address
;     >Label    high byte of Label's address
;     Label,x   address Label plus index register X
;     (Ptr),y   16-bit address stored at Ptr, plus index register Y
;
    processor 6502

; -----------------------------------------------------------------------------
; TIA write registers
; -----------------------------------------------------------------------------
; The Television Interface Adaptor (TIA) produces video and audio. These are
; memory-mapped hardware registers: STA does not save ordinary RAM here; it
; immediately changes a piece of video or sound hardware.

VSYNC   = $00   ; bit 1 enables vertical sync
VBLANK  = $01   ; bit 1 blanks the visible output
WSYNC   = $02   ; any write waits for the next scanline
NUSIZ0  = $04   ; player 0 copy/size mode; $05 selects double width
COLUP0  = $06   ; player 0 color
COLUPF  = $08   ; playfield color
COLUBK  = $09   ; background color
CTRLPF  = $0A   ; playfield control; bit 0 selects reflected right half
PF0     = $0D   ; first 4 playfield bits
PF1     = $0E   ; next 8 playfield bits
PF2     = $0F   ; final 8 playfield bits
RESP0   = $10   ; strobe: set player 0's coarse horizontal position
AUDC0   = $15   ; audio channel 0 waveform/control
AUDC1   = $16   ; audio channel 1 waveform/control
AUDF0   = $17   ; audio channel 0 frequency divider
AUDF1   = $18   ; audio channel 1 frequency divider
AUDV0   = $19   ; audio channel 0 volume, 0-15
AUDV1   = $1A   ; audio channel 1 volume, 0-15
GRP0    = $1B   ; 8 graphics bits for player 0
HMP0    = $20   ; player 0 fine horizontal motion
HMOVE   = $2A   ; strobe: apply all horizontal-motion registers

; -----------------------------------------------------------------------------
; RIOT timer registers
; -----------------------------------------------------------------------------
; The RIOT chip supplies the console's 128 bytes of RAM, I/O ports, and timer.
; TIM64T starts a countdown where one timer tick is 64 CPU cycles. INTIM reads
; the current count. Timers let the CPU do useful work during blanked regions
; without manually counting every scanline.

INTIM   = $0284 ; current RIOT timer value
TIM64T  = $0296 ; write here to start a 64-cycle-interval countdown

; -----------------------------------------------------------------------------
; RAM layout
; -----------------------------------------------------------------------------
; The Atari 2600 has only 128 bytes of RAM at $80-$FF. This demo uses $80-$A8,
; or 41 bytes. ScrollBuffer is deliberately in RAM because the visible ticker
; kernel needs fast, simple indexed reads; its source animation lives in ROM.
;
; "ds N" reserves N bytes. SEG.U means an uninitialized segment: these labels
; describe RAM addresses but do not put bytes into the cartridge image.

    SEG.U RAM
    ORG $80

FrameCounter    ds 1    ; $80: increments once/frame and wraps after 255
Hue             ds 1    ; $81: high nibble selects the current color family
SpriteX         ds 1    ; $82: player horizontal position
SpriteDX        ds 1    ; $83: horizontal delta, either +1 or $FF (-1)
SpriteY         ds 1    ; $84: top scanline of the sprite inside its region
SpriteDY        ds 1    ; $85: vertical delta, either +1 or $FF (-1)
ScrollTick      ds 1    ; $86: divides the frame rate for slower scrolling
ScrollPtr       ds 2    ; $87-$88: little-endian pointer to one ROM frame
MusicStep       ds 1    ; $89: index into the two 16-byte note tables
CheckerState    ds 1    ; $8A: selects one of two checker patterns
ScrollBuffer    ds 30   ; $8B-$A8: current 5-row asymmetric ticker frame

; -----------------------------------------------------------------------------
; Cartridge ROM
; -----------------------------------------------------------------------------
; A plain 4K cartridge occupies CPU addresses $F000-$FFFF. There is no bank
; switching: all code and data are always visible. The final four bytes hold
; the reset and IRQ/BRK vectors expected by the processor.

    SEG CODE
    ORG $F000

; =============================================================================
; Reset - establish a known machine state
; =============================================================================
; Execution starts here after the CPU reads the reset vector at $FFFC.
; No subroutine called Reset ever returns; it falls into the permanent frame
; loop after initialization.

Reset
    sei                     ; ignore maskable interrupts (the 6507 has no IRQ pin)
    cld                     ; make ADC/SBC use ordinary binary arithmetic
    ldx #$FF
    txs                     ; initialize the stack pointer at the top of the stack

; Clear addresses $00-$FF. On the 2600 this both resets TIA write registers and
; clears the physical RAM at $80-$FF. X wraps from $FF to $00, which makes BNE
; end the loop after exactly 256 writes. A remains zero throughout.
    lda #0
    ldx #0
.clear
    sta $00,x
    inx
    bne .clear

; Give the sprite a visible starting point and positive movement in both axes.
; A delta of $FF represents -1 in 8-bit two's-complement arithmetic.
    lda #28
    sta SpriteX
    lda #1
    sta SpriteDX
    lda #7
    sta SpriteY
    lda #1
    sta SpriteDY

; ScrollPtr is a 16-bit little-endian pointer. "<" extracts the low address
; byte and ">" extracts the high byte.
    lda #<ScrollFrames
    sta ScrollPtr
    lda #>ScrollFrames
    sta ScrollPtr+1

; Configure the one hardware player and the TIA's two sound channels.
; NUSIZ0=$05 makes the 8-bit player twice its normal width.
    lda #$05
    sta NUSIZ0
    lda #$04
    sta AUDC0
    lda #$06
    sta AUDC1
    lda #4
    sta AUDV0
    lda #2
    sta AUDV1

; =============================================================================
; Frame - permanent 262-scanline main loop
; =============================================================================
; The program never waits for input. It repeatedly emits one complete NTSC
; frame, updates animation once, and jumps back here.

Frame
; --- 3 lines of vertical sync -------------------------------------------------
; Bit 1 is the active bit for both VSYNC and VBLANK, hence the value 2.
; WSYNC ignores the stored value; each write consumes the rest of one line.
    lda #2
    sta VBLANK
    sta VSYNC
    sta WSYNC
    sta WSYNC
    sta WSYNC
    lda #0
    sta VSYNC

; --- 37 lines of vertical blank ----------------------------------------------
; 43 timer ticks * 64 cycles = 2752 cycles, about 36.2 scanlines. The final
; WSYNC rounds that up to 37. Animation and horizontal positioning happen
; while VBLANK hides their intermediate register changes.
    lda #43
    sta TIM64T
    jsr UpdateState
    jsr PositionPlayer

.waitVBlank
    lda INTIM
    bne .waitVBlank
    sta WSYNC               ; INTIM was zero; the stored value does not matter
    lda #0
    sta VBLANK              ; turn the beam on at a scanline boundary

; --- 192 visible lines --------------------------------------------------------
    jsr DrawScreen

; --- 30 lines of overscan -----------------------------------------------------
; Blank the beam immediately after the visible kernel. 35 * 64 = 2240 cycles,
; about 29.5 scanlines, and the closing WSYNC rounds the region to 30.
    lda #2
    sta VBLANK
    lda #35
    sta TIM64T
.waitOverscan
    lda INTIM
    bne .waitOverscan
    sta WSYNC
    jmp Frame

; =============================================================================
; UpdateState - advance all slow, once-per-frame state
; =============================================================================
; This routine runs during VBLANK, where its execution time cannot disturb the
; visible display. It updates colors, sprite motion, ticker data, and music.

UpdateState
    inc FrameCounter         ; 8-bit increment naturally wraps $FF -> $00

; Change the base hue once every 8 frames. Because 8 is a power of two,
; FrameCounter AND 7 is zero exactly when the low three bits are all zero.
; TIA NTSC colors put the hue mainly in the high nibble, so adding $10 walks
; around the color wheel. AND $F0 discards any low luminance bits.
    lda FrameCounter
    and #7
    bne .keepHue
    lda Hue
    clc
    adc #$10
    and #$F0
    sta Hue
.keepHue

; --- Horizontal bounce -------------------------------------------------------
; Add either +1 or $FF (-1) to SpriteX. CLC is essential: ADC always includes
; the carry flag, so clearing it makes this a plain X = X + DX operation.
    lda SpriteX
    clc
    adc SpriteDX
    sta SpriteX

; At the right edge, select -1 for future frames. At the left edge, select +1.
; The current position is retained, so the visible range includes the boundary.
    cmp #146
    bcc .checkLeft
    lda #$FF
    sta SpriteDX
.checkLeft
    lda SpriteX
    cmp #14
    bcs .moveVertical
    lda #1
    sta SpriteDX

; --- Vertical bounce ---------------------------------------------------------
; SpriteY is measured in scanlines relative to the 40-line sprite region.
; An 8-line bitmap can start at 32 and end exactly on region line 39.
.moveVertical
    lda SpriteY
    clc
    adc SpriteDY
    sta SpriteY
    cmp #32
    bcc .checkTop
    lda #$FF
    sta SpriteDY
.checkTop
    lda SpriteY
    cmp #1
    bcs .scroll
    lda #1
    sta SpriteDY

; --- Scrolling ticker --------------------------------------------------------
; The asset generator precomputes a complete 40-bit playfield image for each
; animation step. Each image moves the message by two logical playfield pixels
; and occupies 30 bytes: 5 text rows * 6 playfield-register values.
;
; Advance to the next image every 8 video frames. AND 7 is a compact modulo-8
; test. At roughly 60 Hz, this is 7.5 animation frames/second, or 15 logical
; playfield pixels/second because each animation frame moves by two pixels.
.scroll
    inc ScrollTick
    lda ScrollTick
    and #7
    bne .copyScrollFrame

; ScrollPtr += 30. The low-byte addition may set carry, and ADC #0 propagates
; that carry into the high byte. This is standard 16-bit addition on a 6502.
    clc
    lda ScrollPtr
    adc #30
    sta ScrollPtr
    lda ScrollPtr+1
    adc #0
    sta ScrollPtr+1

; If the pointer reached the byte immediately after the last generated frame,
; wrap it back to the first frame. Comparing high byte first is a quick reject.
; Equality is sufficient because every advance is exactly one 30-byte frame.
    cmp #>ScrollFramesEnd
    bne .copyScrollFrame
    lda ScrollPtr
    cmp #<ScrollFramesEnd
    bne .copyScrollFrame
    lda #<ScrollFrames
    sta ScrollPtr
    lda #>ScrollFrames
    sta ScrollPtr+1

; Copy the selected ROM frame into RAM every video frame, even when ScrollPtr
; did not advance. This keeps the visible kernel simple and deterministic.
;
; Y counts backward from 29 to 0. After DEY changes 0 into $FF, the negative
; flag becomes set and BPL ("branch if plus") stops the loop.
.copyScrollFrame
    ldy #29
.copyByte
    lda (ScrollPtr),y
    sta ScrollBuffer,y
    dey
    bpl .copyByte

; --- Two-channel music -------------------------------------------------------
; Update the pitch dividers once every 16 video frames (about 3.75 times per
; second). Both tables contain 16 entries, so AND 15 wraps MusicStep cheaply.
; AUDC0/AUDC1 and both volumes were configured once during Reset.
    lda FrameCounter
    and #15
    bne .audioDone
    inc MusicStep
    lda MusicStep
    and #15
    tax
    lda Melody,x
    sta AUDF0
    lda Bass,x
    sta AUDF1
.audioDone
    rts

; =============================================================================
; PositionPlayer - convert SpriteX into TIA coarse and fine positioning
; =============================================================================
; TIA has no register where software can simply store an X coordinate.
; Horizontal position is based on *when* RESP0 is written during a scanline:
;
;   1. Repeatedly subtract 15 to spend time in 15-color-clock chunks.
;   2. Write RESP0 for the coarse position.
;   3. Convert the leftover amount into HMP0 fine motion.
;   4. Strobe HMOVE on the next line to apply that fine adjustment.
;
; This is a standard Atari 2600 positioning routine. It consumes two WSYNC
; boundaries, both safely inside the VBLANK timer budget.

PositionPlayer
    lda SpriteX             ; requested horizontal coordinate
    sec                     ; first SBC must not borrow
    sta WSYNC               ; begin coarse positioning on a fresh scanline
.divide
    sbc #15                 ; each taken loop delays the RESP0 strobe
    bcs .divide             ; continue while the subtraction did not underflow

; A now contains an underflowed remainder. EOR #7 and four shifts transform it
; into the signed 4-bit fine-motion value expected in HMP0's high nibble.
    eor #7
    asl
    asl
    asl
    asl
    sta HMP0
    sta RESP0               ; value is irrelevant; write timing sets coarse X
    sta WSYNC               ; HMOVE is safest at the start of a scanline
    sta HMOVE               ; apply HMP0
    rts

; =============================================================================
; DrawScreen - 192-scanline visible display kernel
; =============================================================================
; Scanline accounting:
;
;     1  initial partial/setup line before the first top bar
;    15  top rainbow bars
;    42  title: 7 bitmap rows * 6 scanlines
;     6  title gap
;    40  bouncing-sprite region
;    32  checker region
;    12  middle rainbow bars
;    25  ticker: 5 bitmap rows * 5 scanlines
;    19  bottom rainbow bars
;   ---
;   192
;
; The first WSYNC below closes the setup line. Each later WSYNC closes the
; effect line produced after the previous WSYNC. The final WSYNC closes the
; last bottom bar before RTS returns to overscan.

DrawScreen
; Begin with an empty, non-reflected playfield. CTRLPF=0 is needed for the
; asymmetric title/ticker technique used later.
    lda #0
    sta PF0
    sta PF1
    sta PF2
    sta CTRLPF

; -----------------------------------------------------------------------------
; Top raster bars - 15 scanlines
; -----------------------------------------------------------------------------
; The table index is (line + FrameCounter) modulo 32. AND 31 performs modulo
; because the table has a power-of-two length. Advancing FrameCounter shifts
; the palette by one entry each video frame and creates flowing color.
    ldx #14
.topBars
    sta WSYNC
    txa
    clc
    adc FrameCounter
    and #31
    tay
    lda Rainbow,y
    sta COLUBK
    dex
    bpl .topBars

; -----------------------------------------------------------------------------
; Large SQUEEPTY title - 7 bitmap rows * 6 scanlines = 42 scanlines
; -----------------------------------------------------------------------------
; Hue contains only a hue nibble. ORA supplies luminance bits; EOR offsets the
; title hue from its background so they remain visually distinct.
    lda Hue
    ora #$02
    sta COLUBK
    lda Hue
    eor #$80
    ora #$0C
    sta COLUPF
    ldy #0
.titleRow
    ldx #6                 ; repeat each source row vertically six times
.titleLine
    sta WSYNC

; A playfield is 20 bits wide and normally repeats or mirrors to make 40 bits.
; To draw a unique 40-bit title, write PF0/PF1/PF2 for the left half early in
; the line, wait for the beam to approach the center, then replace all three
; registers with right-half values. The TIA has already displayed the left
; values by the time they are replaced.
    lda TitlePF0L,y
    sta PF0
    lda TitlePF1L,y
    sta PF1
    lda TitlePF2L,y
    sta PF2

; Six NOPs consume 12 CPU cycles. They are timing, not wasted work: removing or
; adding one moves the right-half update horizontally and can damage the text.
    nop
    nop
    nop
    nop
    nop
    nop
    lda TitlePF0R,y
    sta PF0
    lda TitlePF1R,y
    sta PF1
    lda TitlePF2R,y
    sta PF2

; The common repeated-line path is about 59 cycles after WSYNC, comfortably
; under the 76-cycle scanline limit. X controls vertical enlargement; Y chooses
; one of the seven source bitmap rows.
    dex
    bne .titleLine
    iny
    cpy #7
    bne .titleRow

; -----------------------------------------------------------------------------
; Empty title gap - 6 scanlines
; -----------------------------------------------------------------------------
; Clear both the playfield and background. The same clearing writes are made
; on every line for straightforward, stable timing.
    ldx #6
.titleGap
    sta WSYNC
    lda #0
    sta PF0
    sta PF1
    sta PF2
    sta COLUBK
    dex
    bne .titleGap

; -----------------------------------------------------------------------------
; Bouncing player - 40 scanlines
; -----------------------------------------------------------------------------
; Horizontal position was already programmed by PositionPlayer during VBLANK.
; This kernel supplies vertical position in software because TIA has no player
; Y register. X is the current line number from 0 through 39.
    lda Hue
    eor #$40
    ora #$06
    sta COLUP0
    ldx #0
.spriteLine
    sta WSYNC

; Always erase GRP0 first so the sprite cannot leak from its previous row.
    lda #0
    sta GRP0

; Calculate line - SpriteY with unsigned arithmetic:
;
;   result $00-$07  -> this is one of the 8 sprite bitmap rows
;   result $08-$FF  -> before or after the sprite, so draw nothing
;
; If line is less than SpriteY, SBC underflows to a large value, which is also
; rejected by CMP #8. This single comparison handles both outside cases.
    txa
    sec
    sbc SpriteY
    cmp #8
    bcs .noSprite
    tay
    lda SpriteBitmap,y
    sta GRP0
.noSprite
    inx
    cpx #40
    bne .spriteLine

; Explicitly turn the player off before entering the next display region.
    lda #0
    sta GRP0

; -----------------------------------------------------------------------------
; Animated checker playfield - 32 scanlines
; -----------------------------------------------------------------------------
; FrameCounter / 4, masked to one bit, chooses which checker phase starts at
; the top. The starting phase changes every four video frames.
    lda FrameCounter
    lsr
    lsr
    and #1
    sta CheckerState
    tay
    lda Hue
    eor #$B0
    ora #$0A
    sta COLUPF
    lda Hue
    ora #$02
    sta COLUBK

; CTRLPF bit 0 reflects the 20-bit left playfield onto the right half. Unlike
; the title and ticker, the checker is symmetrical and needs only one set of
; PF0/PF1/PF2 writes per scanline.
    lda #1
    sta CTRLPF
    ldx #0
.checkerLine
    sta WSYNC
    lda CheckerPF0,y
    sta PF0
    lda CheckerPF1,y
    sta PF1
    lda CheckerPF2,y
    sta PF2

; Swap between the two complementary patterns every four scanlines. This makes
; each visible checker cell four scanlines tall.
    inx
    txa
    and #3
    bne .checkerKeep
    lda CheckerState
    eor #1
    sta CheckerState
    tay
.checkerKeep
    cpx #32
    bne .checkerLine

; -----------------------------------------------------------------------------
; Middle raster bars - 12 scanlines
; -----------------------------------------------------------------------------
; Clear the checker and return to non-reflected mode before drawing the bars.
; ASL doubles X, so adjacent lines sample every other palette entry and produce
; a steeper color gradient than the top bars.
    lda #0
    sta PF0
    sta PF1
    sta PF2
    sta CTRLPF
    ldx #11
.middleBars
    sta WSYNC
    txa
    asl
    clc
    adc FrameCounter
    and #31
    tay
    lda Rainbow,y
    sta COLUBK
    dex
    bpl .middleBars

; -----------------------------------------------------------------------------
; Scrolling ticker - 5 bitmap rows * 5 scanlines = 25 scanlines
; -----------------------------------------------------------------------------
; ScrollBuffer contains one complete precomputed 40-bit ticker image. Its
; 30-byte register-major layout is:
;
;      0.. 4  left PF0, one byte for each of 5 text rows
;      5.. 9  left PF1
;     10..14  left PF2
;     15..19  right PF0
;     20..24  right PF1
;     25..29  right PF2
;
; With Y as the text-row index, adding 5 selects the next register block.
    lda #0
    sta COLUBK
    lda Hue
    eor #$60
    ora #$0E
    sta COLUPF
    ldy #0
.tickerRow
    ldx #5                 ; repeat each source row vertically five times
.tickerLine
    sta WSYNC

; Like the title, the ticker rewrites the playfield around the middle of the
; scanline to obtain 40 independent bits. This repeated path also takes about
; 59 cycles after WSYNC.
    lda ScrollBuffer,y
    sta PF0
    lda ScrollBuffer+5,y
    sta PF1
    lda ScrollBuffer+10,y
    sta PF2

; Keep this six-NOP delay synchronized with the corresponding title delay.
    nop
    nop
    nop
    nop
    nop
    nop
    lda ScrollBuffer+15,y
    sta PF0
    lda ScrollBuffer+20,y
    sta PF1
    lda ScrollBuffer+25,y
    sta PF2
    dex
    bne .tickerLine
    iny
    cpy #5
    bne .tickerRow

; -----------------------------------------------------------------------------
; Bottom raster bars - 19 scanlines
; -----------------------------------------------------------------------------
; RainbowReverse gives the lower border a complementary direction. The extra
; WSYNC after the loop closes the nineteenth bar exactly at a scanline edge;
; Frame then enables VBLANK for overscan.
    lda #0
    sta PF0
    sta PF1
    sta PF2
    ldx #18
.bottomBars
    sta WSYNC
    txa
    clc
    adc FrameCounter
    and #31
    tay
    lda RainbowReverse,y
    sta COLUBK
    dex
    bpl .bottomBars
    sta WSYNC
    rts

; =============================================================================
; Read-only tables
; =============================================================================
; ALIGN 256 moves the next byte to a page boundary ($F300 here). This keeps the
; frequently indexed Rainbow tables away from a page crossing, where a 6502
; absolute-indexed load can take an extra cycle. Predictable timing is valuable
; inside a display kernel.

    ALIGN 256

; TIA NTSC color bytes combine hue in the upper nibble with luminance in the
; lower bits. These hand-picked sequences travel through several hues and then
; return toward the starting color, producing smooth animated raster bands.
Rainbow
    byte $22,$24,$26,$28,$2A,$2C,$2E,$3C
    byte $4A,$58,$66,$74,$82,$90,$A2,$B4
    byte $C6,$D8,$EA,$DC,$CE,$BC,$AA,$98
    byte $86,$74,$62,$50,$42,$34,$26,$22
RainbowReverse
    byte $B4,$A2,$90,$82,$74,$66,$58,$4A
    byte $3C,$2E,$2C,$2A,$28,$26,$24,$22
    byte $22,$26,$34,$42,$50,$62,$74,$86
    byte $98,$AA,$BC,$CE,$DC,$EA,$D8,$C6

; Player graphics are eight rows of eight bits. A 1 turns on a player pixel and
; a 0 leaves the background visible. NUSIZ0 doubles each bit horizontally, but
; the software still supplies exactly one byte per scanline.
SpriteBitmap
    byte %00011000
    byte %00111100
    byte %01111110
    byte %11011011
    byte %11111111
    byte %01100110
    byte %00111100
    byte %00011000

; Two complementary 20-bit playfield patterns. CheckerState/Y selects entry 0
; or 1 from each table. CTRLPF reflection expands the 20 bits across the screen.
; PF0 uses only its upper four bits; PF1 and PF2 use all eight bits.
CheckerPF0
    byte %10100000,%01010000
CheckerPF1
    byte %10101010,%01010101
CheckerPF2
    byte %01010101,%10101010

; TIA audio "frequency" values are divider settings, not musical note numbers:
; smaller values generally produce higher pitches. UpdateState walks both
; 16-entry tables together, giving channel 0 a lead line and channel 1 a bass.
Melody
    byte 15,12,10,8,10,12,15,18,15,12,10,8,6,8,10,12
Bass
    byte 28,28,24,24,26,26,22,22,28,28,24,24,20,20,22,22

; The Python asset tool creates:
;
;   - six 7-byte title tables (left/right PF0, PF1, PF2)
;   - all 30-byte animation frames for the scrolling ticker
;
; It is generated during the build so build/assets.inc should not be edited by
; hand. Change tools/gen_assets.py instead.
    include "build/assets.inc"

; =============================================================================
; CPU vectors
; =============================================================================
; A 6502-family reset reads a 16-bit little-endian address from $FFFC-$FFFD.
; BRK/IRQ uses $FFFE-$FFFF. Point both at Reset so an accidental BRK restarts
; cleanly. The 6507 lacks the external interrupt pins used by a full 6502.

    ORG $FFFC
    word Reset              ; reset vector
    word Reset              ; IRQ/BRK vector
