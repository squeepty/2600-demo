; =============================================================================
; The Teeny-tiny Atari 2600 demo - a 4 KiB NTSC production
; Released Thursday, July 16, 2026
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
; Visual choreography derives from DemoFrame, with title sub-effects using
; FrameCounter at 8- or 16-frame rates. On power-up, four 256-frame stages
; reveal the title, checker, sprite/starfield, and ticker one at a time. The
; fourth stage hands directly to scene 2. The visual scene sequencer completes
; scenes 2-4, wraps through scene 1, and repeats all four scenes in order. The
; independent two-channel soundtrack uses its own per-frame event timers.
;
; This is a passive demo: it reads no joystick or console-switch registers.
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

; Number of video frames for which each two-pixel ticker position is shown.
; The initial value is one larger because UpdateState decrements the counter
; before the first visible frame; both initial and later positions remain on
; screen for ten complete frames.
SCROLL_DELAY         = 10
SCROLL_INITIAL_DELAY = SCROLL_DELAY + 1

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
; The Atari 2600 has only 128 bytes of RAM at $80-$FF. This demo uses $80-$CB,
; or 76 bytes. ScrollBuffer is deliberately in RAM because the visible ticker
; kernel needs fast, simple indexed reads. VBLANK code shifts that buffer while
; the compact source columns remain in ROM.
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
ScrollTick      ds 1    ; $86: 10-frame divider for two-column scroll updates
ScrollPtr       ds 2    ; $87-$88: pointer to the next packed ticker column
CheckerForeground ds 1 ; $89: checker color cached before its first WSYNC
CheckerState    ds 1    ; $8A: scene pattern base plus current checker phase
TitleBackground = CheckerState ; shared scratch before checker setup overwrites it
ScrollBits       = CheckerState ; VBLANK-only source-column scratch byte
BottomBarColor   = CheckerState ; cached after checker use and before ticker draw
ScrollBuffer    ds 30   ; $8B-$A8: six register blocks * five ticker rows
DemoFrame       ds 2    ; $A9-$AA: 0..4095 main-scene frame counter
TopBarsLast     ds 1    ; $AB: inclusive final index for the 15 top bars
TitleGapCount   ds 1    ; $AC: six-line gap below the fixed title region
TitleFrame      ds 1    ; $AD: first row of selected 7-row generated phase
TitleFrameEnd   ds 1    ; $AE: exclusive end row for that generated phase
ScenePattern    ds 1    ; $AF: 0/64/128/192 visual-table offset and scene ID
SpriteBuffer    ds 8    ; $B0-$B7: active scene sprite copied during VBLANK
TransitionStep  ds 1    ; $B8: low byte of 256-frame fade countdown
TransitionMask  ds 1    ; $B9: AND mask applied to every visible color
TransitionStepHi ds 1   ; $BA: high byte, one only for countdown value 256
StarPtr0        ds 2    ; $BB-$BC: active 32-byte source for PF0 stars
StarPtr1        ds 2    ; $BD-$BE: active 32-byte source for PF1 stars
StarPtr2        ds 2    ; $BF-$C0: active 32-byte source for PF2 stars
StarMode        ds 1    ; $C1: scene-specific starfield speed/direction, 0..3
IntroActive     ds 1    ; $C2: nonzero only during one-time component reveal
IntroStage      ds 1    ; $C3: 0 title, 1 grid, 2 sprite/stars, 3 ticker, 4 done
MusicPtr0       ds 2    ; $C4-$C5: Take On Me melody event pointer
MusicPtr1       ds 2    ; $C6-$C7: Take On Me bass event pointer
MusicTimer0     ds 1    ; $C8: melody frames remaining
MusicTimer1     ds 1    ; $C9: bass frames remaining
CheckerBackground ds 1 ; $CA: background cached before its first checker WSYNC
CheckerHue      ds 1    ; $CB: grid hue clock, advanced at half the old rate

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
    sta IntroActive

; UpdateState runs before the first visible frame. Starting one above the
; regular delay lets the initial image, like every later two-column position,
; remain visible for ten complete frames before it shifts.
    lda #SCROLL_INITIAL_DELAY
    sta ScrollTick

; ScrollPtr is a 16-bit little-endian pointer to the first source column just
; beyond the initial 40-bit window. "<" and ">" select its address bytes.
    lda #<ScrollNextColumn
    sta ScrollPtr
    lda #>ScrollNextColumn
    sta ScrollPtr+1

; Seed the RAM image that the visible ticker kernel reads. Later updates shift
; this same encoded buffer in place, so no complete animation frames are kept
; in the cartridge.
    ldy #29
.loadScrollBuffer
    lda ScrollInitial,y
    sta ScrollBuffer,y
    dey
    bpl .loadScrollBuffer

; Configure the one hardware player and initialize the soundtrack.
; NUSIZ0=$05 makes the 8-bit player twice its normal width.
    lda #$05
    sta NUSIZ0
    jsr TakeOnMe_Init

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
; The RIOT decrements once immediately after a timer load. Loading 44 therefore
; leaves 43 full 64-cycle intervals: 2752 cycles, about 36.2 scanlines. The
; final WSYNC aligns the region to 37 lines. Animation and horizontal
; positioning happen while VBLANK hides their intermediate register changes.
    lda #44
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
; Blank the beam immediately after the visible kernel. Loading 36 leaves 35
; full 64-cycle intervals: 2240 cycles, about 29.5 scanlines. The closing WSYNC
; aligns the region to 30 lines.
    lda #2
    sta VBLANK
    lda #36
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

; The main show is a 4,096-frame ring: 1,024 frames apiece for scene 1/static,
; scene 2/type-on-off, scene 3/ripple, and scene 4/vertical wave. The intro also
; uses DemoFrame, then deliberately hands off at $0400 so scene 2 follows its
; fourth 256-frame reveal stage without replaying scene 1 for another cycle.
    inc DemoFrame
    bne .keepDemoFrameHigh
    inc DemoFrame+1
.keepDemoFrameHigh
    lda IntroActive
    beq .checkDemoLoop
    jsr UpdateIntro
    jmp .chooseTitleEffect
.checkDemoLoop
    lda DemoFrame+1
    cmp #$10
    bne .chooseTitleEffect
    lda DemoFrame
    cmp #$00
    bne .chooseTitleEffect
    lda #0
    sta DemoFrame
    sta DemoFrame+1

.chooseTitleEffect
; Derive the checker hue from bits 5-8 of DemoFrame. LSR places counter bit 8
; in carry and ROR shifts it above bits 7-1, producing the low byte of
; DemoFrame/2. Its high nibble therefore advances every 32 frames while still
; visiting all 16 TIA hue families over a complete 512-frame color cycle.
    lda DemoFrame+1
    lsr
    lda DemoFrame
    ror
    and #$F0
    sta CheckerHue

    jsr UpdateTransition
    jsr UpdateTitleEffect
    jsr LoadStarPattern
.loadStageSprite
    jsr LoadSpriteFrame

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

; At the right edge, select -1 for future frames. Player 0 is 16 color clocks
; wide in double-width mode, so X=130 leaves the same 14-clock margin between
; its right edge and the 160-clock screen boundary as X=14 leaves on the left.
; The current position is retained, so the visible range includes the boundary.
    cmp #130
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
; ScrollBuffer is a 40-bit-wide image encoded in the TIA's unusual PF0/PF1/PF2
; bit orders. Every tenth video frame, shift each of its five rows left twice
; and inject two successive five-bit source columns at the right. At roughly
; 60 Hz this advances 12 logical playfield pixels per second. Keeping the
; original two-pixel cadence avoids horizontal edge persistence in emulators
; while the compact column stream still saves cartridge space.
.scroll
    dec ScrollTick
    bne .music
    lda #SCROLL_DELAY
    sta ScrollTick

    jsr .shiftScrollOne
    jsr .shiftScrollOne
    jmp .music

; Each ROM byte supplies one vertical column: bits 4 through 0 hold ticker rows
; 0 through 4. Fetch it before advancing the pointer.
.shiftScrollOne
    ldy #0
    lda (ScrollPtr),y
    sta ScrollBits

; Increment the 16-bit pointer by one. If the low byte wraps, increment the high
; byte too, then wrap the complete pointer at the end of the circular stream.
    inc ScrollPtr
    bne .checkScrollEnd
    inc ScrollPtr+1
.checkScrollEnd
    lda ScrollPtr+1
    cmp #>ScrollColumnsEnd
    bne .shiftScroll
    lda ScrollPtr
    cmp #<ScrollColumnsEnd
    bne .shiftScroll
    lda #<ScrollColumns
    sta ScrollPtr
    lda #>ScrollColumns
    sta ScrollPtr+1

; Shift one row through the six hardware-register bytes. Their display order is
; PF0 bits 4->7, PF1 bits 7->0, and PF2 bits 0->7 on each screen half, so the
; rotate direction alternates. After right PF0 shifts, its old visible bit 4 is
; temporarily in bit 3; five ASLs move that boundary bit into carry for left
; PF2. PF0's unused low nibbles may collect discarded bits, but the TIA ignores
; them and right shifts can never move them back into the visible high nibble.
; X descends with ScrollBits: bit 0 feeds row 4 first, through bit 4 for row 0.
.shiftScroll
    ldx #4
.shiftScrollRow
    lsr ScrollBits
    ror ScrollBuffer+25,x
    rol ScrollBuffer+20,x
    ror ScrollBuffer+15,x
    lda ScrollBuffer+15,x
    asl
    asl
    asl
    asl
    asl
    ror ScrollBuffer+10,x
    rol ScrollBuffer+5,x
    ror ScrollBuffer,x
    dex
    bpl .shiftScrollRow
    rts

; --- Two-channel music -------------------------------------------------------
; The converted ZX Spectrum arrangement has independent event durations for
; both voices, so its player advances once per NTSC frame.
.music
    jsr TakeOnMe_Update
    rts

; =============================================================================
; UpdateIntro - reveal one major component per 256-frame stage
; =============================================================================
; IntroStage starts at zero, so the complete static title is visible first.
; Exact 256-frame milestones reveal the checker at $0100, the sprite/starfield
; at $0200, and the ticker at $0300. At $0400 the fourth reveal stage is
; complete: clear IntroActive, preserve the normal scene geometry, and set
; DemoFrame=$0400 to choose scene 2. The soundtrack has its own frame timers
; and is intentionally independent of these visual boundaries. Hidden
; components still consume their normal scanlines in DrawScreen, so the NTSC
; frame always remains exactly 262 lines.
UpdateIntro
    lda DemoFrame+1
    cmp #$04
    bne .checkIntroMilestones
    lda DemoFrame
    cmp #$00                ; 1,024 frames: hand off directly to scene two
    bne .checkIntroMilestones
    lda #0
    sta IntroActive
    sta DemoFrame
    lda #$04                ; skip scene one's additional 1,024-frame hold
    sta DemoFrame+1
    lda #4
    sta IntroStage
    rts
.checkIntroMilestones
    ldx #2
.introMilestoneLoop
    lda DemoFrame+1
    cmp IntroMilestoneHigh,x
    bne .nextIntroMilestone
    lda DemoFrame
    cmp IntroMilestoneLow,x
    bne .nextIntroMilestone
    inc IntroStage
    rts
.nextIntroMilestone
    dex
    bpl .introMilestoneLoop
    rts

; =============================================================================
; UpdateTransition - fade out before and fade in after each regular scene boundary
; =============================================================================
; A transition begins 128 frames before each 1,024-frame boundary and lasts 256
; frames. Four progressively stricter masks remove luminance bits; the effect
; switch occurs in the dark center, then the masks relax in reverse. Each entry
; in the 128-byte curve lasts two frames. The one-time component reveal bypasses
; this countdown and uses the full-luminance $FE mask; its $0400 handoff to
; scene 2 is intentionally immediate rather than another fade.

UpdateTransition
    lda IntroActive
    beq .updateNormalTransition
    lda #$FE
    sta TransitionMask
    rts
.updateNormalTransition
    lda TransitionStepHi
    bne .ageTransition
    lda TransitionStep
    beq .checkTransitionStart
.ageTransition
    lda TransitionStep
    bne .decrementTransitionLow
    dec TransitionStepHi
.decrementTransitionLow
    dec TransitionStep
.checkTransitionStart
    ldx #3
.transitionStartLoop
    lda DemoFrame+1
    cmp TransitionStartHigh,x
    bne .nextTransitionStart
    lda DemoFrame
    cmp TransitionStartLow,x
    bne .nextTransitionStart
    lda #0
    sta TransitionStep
    lda #1
    sta TransitionStepHi
    bne .selectTransitionMask
.nextTransitionStart
    dex
    bpl .transitionStartLoop

.selectTransitionMask
    lda TransitionStepHi
    bne .firstTransitionMask
    lda TransitionStep
    beq .fullLuminance
    sec
    sbc #1
    lsr
    tax
    lda TransitionMasks,x
    sta TransitionMask
    rts
.firstTransitionMask
    ldx #127
    lda TransitionMasks,x
    sta TransitionMask
    rts
.fullLuminance
    lda #$FE                ; TIA luminances are even; this preserves all bits
    sta TransitionMask
    rts

; =============================================================================
; UpdateTitleEffect - select the current 1,024-frame scene
; =============================================================================
; TopBarsLast+1 and TitleGapCount total 21 scanlines. All title motion is
; precomputed inside the fixed seven-row region, leaving the display kernel
; and its 192-line height unchanged.
;
;   DemoFrame $0000-$03FF: scene 1, static title, ScenePattern 0
;             $0400-$07FF: scene 2, type on/off, ScenePattern 64
;             $0800-$0BFF: scene 3, horizontal ripple, ScenePattern 128
;             $0C00-$0FFF: scene 4, vertical wave, ScenePattern 192
;
; ScenePattern is the shared visual selector used later for the sprite bitmap,
; checker pair, star-plane permutation, and scene-specific animation behavior.

UpdateTitleEffect
    lda #14
    sta TopBarsLast
    lda #6
    sta TitleGapCount
    lda #84                ; complete undistorted reveal phase
    sta TitleFrame
    lda #91
    sta TitleFrameEnd
    lda #0
    sta ScenePattern

; The progressive introduction uses the complete static title throughout.
    lda IntroActive
    beq .checkStaticStage
    rts

; DemoFrame < 1024 ($0400): leave the defaults above for a static title.
.checkStaticStage
    lda DemoFrame+1
    cmp #$04
    bcs .checkRippleStage
    rts

; DemoFrame < 2048 ($0800): reveal letters, then remove them in reverse.
.checkRippleStage
    lda DemoFrame+1
    cmp #$08
    bcc .titleType
    bne .checkVerticalStage
    lda DemoFrame
    cmp #$00
    bcc .titleType

; DemoFrame < 3072 ($0C00): select the horizontal ripple.
.checkVerticalStage
    lda DemoFrame+1
    cmp #$0C
    bcc .titleRipple
    bne .titleVertical
    lda DemoFrame
    cmp #$00
    bcc .titleRipple

; DemoFrame >= 3072: keep the title region fixed and use a separate vertical
; wave that moves only the precomputed letters (no horizontal ripple).
.titleVertical
    lda #192
    sta ScenePattern
    lda FrameCounter
    lsr
    lsr
    lsr                     ; advance the letter wave every 16 frames
    lsr
    and #3
    tay
    lda VerticalFrameOffsets,y
    sta TitleFrame
    clc
    adc #7
    sta TitleFrameEnd
    rts

.titleType
    lda #64
    sta ScenePattern
    lda FrameCounter
    lsr
    lsr
    lsr
    lsr
    and #15
    tay
    lda RevealFrameOffsets,y
    sta TitleFrame
    clc
    adc #7
    sta TitleFrameEnd
    rts

.titleRipple
    lda #128
    sta ScenePattern
    lda FrameCounter
    lsr
    lsr
    lsr
    and #7
    tay
    lda RippleFrameOffsets,y
    sta TitleFrame
    clc
    adc #7
    sta TitleFrameEnd
.titleEffectDone
    rts

; Copy the current scene's eight-byte sprite into RAM during VBLANK. Keeping
; the visible kernel's bitmap load simple is essential when the player is near
; the left edge, where GRP0 must be written before the beam reaches it.
LoadSpriteFrame
    lda ScenePattern
    lsr
    lsr
    lsr                     ; 0,64,128,192 -> bitmap offsets 0,8,16,24
    tay
    ldx #0
.copySpriteFrame
    lda SpriteBitmaps,y
    sta SpriteBuffer,x
    iny
    inx
    cpx #8
    bne .copySpriteFrame
    rts

; Remap the same three sparse star planes for each scene. All three tables live
; on one ROM page, so only their low pointer bytes vary. StarMode also gives
; each scene a different vertical speed or direction: slow, medium, fast, then
; medium-speed reverse. No 16-bit pointer addition is needed in the kernel.
LoadStarPattern
    lda ScenePattern
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    tay
    sty StarMode
    lda StarPlane0Low,y
    sta StarPtr0
    lda StarPlane1Low,y
    sta StarPtr1
    lda StarPlane2Low,y
    sta StarPtr2
    lda #>StarPF0
    sta StarPtr0+1
    sta StarPtr1+1
    sta StarPtr2+1
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
    sta WSYNC               ; begin coarse positioning on a fresh scanline
    sec                     ; first SBC must not borrow; this two-cycle delay
                            ; keeps RESP0 out of its special HBLANK timing case
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
; All four scenes use these same region heights. Intro-hidden regions execute
; counted WSYNC loops of the same height.
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
    sta GRP0

; -----------------------------------------------------------------------------
; Top raster bars - 15 scanlines
; -----------------------------------------------------------------------------
; The table index is (line + FrameCounter) modulo 32. AND 31 performs modulo
; because the table has a power-of-two length. Advancing FrameCounter shifts
; the palette by one entry each video frame and creates flowing color. Compute
; each color on the preceding scanline, then write COLUBK immediately after
; WSYNC; this prevents a stale-color strip at the visible left edge.
    ldx TopBarsLast
.topBars
    txa
    clc
    adc FrameCounter
    and #31
    tay
    lda Rainbow,y
    and TransitionMask
    sta WSYNC
    sta COLUBK
    dex
    bpl .topBars

; -----------------------------------------------------------------------------
; Large SQUEEPTY title - 7 bitmap rows * 6 scanlines = 42 scanlines
; -----------------------------------------------------------------------------
; Hue contains only a hue nibble. ORA supplies luminance bits; EOR offsets the
; title hue from its background so they remain visually distinct. Cache the
; background in CheckerState's RAM byte; the checker initializes that byte
; again before it is used. COLUPF is safe to change on the last raster line
; because PF0/PF1/PF2 are all zero there.
; Ripple and vertical-wave scenes use the same four-times-slower background
; hue cadence as the ticker. ScenePattern has bit 7 set only for those scenes.
    lda ScenePattern
    bpl .normalTitleBackgroundHue
    lda DemoFrame+1
    lsr                     ; carry receives DemoFrame bit 8
    lda DemoFrame
    ror
    lsr
    lsr
    lsr
    lsr
    asl
    asl
    asl
    asl
    jmp .haveTitleBackgroundHue
.normalTitleBackgroundHue
    lda Hue
.haveTitleBackgroundHue
    ora #$02
    and TransitionMask
    sta TitleBackground
    lda Hue
    eor #$80
    ora #$0C
    and TransitionMask
    sta COLUPF
    ldy TitleFrame
.titleRow
    ldx #6                 ; repeat each source row vertically six times
.titleLine
    lda TitleBackground
    sta WSYNC
    sta COLUBK              ; cycle 3: safely inside horizontal blank

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

; The background write shifted the left-half work by three cycles. BIT plus
; three NOPs delays nine cycles, keeping every right-half write at its original
; cycle. These instructions are timing, not wasted work.
    bit TitleBackground
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
    cpy TitleFrameEnd
    bne .titleRow

; -----------------------------------------------------------------------------
; Empty title gap - 6 scanlines
; -----------------------------------------------------------------------------
; Clear both the playfield and background. The same clearing writes are made
; on every line for straightforward, stable timing.
    ldx TitleGapCount
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
; Y register. VBLANK has already copied the current scene's bitmap into the
; fast SpriteBuffer. A sparse reflected playfield scrolls vertically behind it;
; those playfield writes happen only after the time-critical GRP0 write. X is
; the current line number from 0 through 39.
; IntroStage values below 2 replace the region with 40 timing-identical blank
; lines; IntroStage 2 reveals both the sprite and its starfield together.
    lda IntroActive
    beq .showSpriteRegion
    lda IntroStage
    cmp #2
    bcs .showSpriteRegion
    ldx #40
.hiddenSpriteLine
    sta WSYNC
    dex
    bne .hiddenSpriteLine
    jmp .checkerStart
.showSpriteRegion
    lda Hue
    eor #$40
    ora #$06
    and TransitionMask
    sta COLUP0
    lda Hue
    eor #$20
    ora #$0E
    and TransitionMask
    sta COLUPF
    lda #1
    sta CTRLPF
    lda StarMode
    beq .starsSlow
    cmp #1
    beq .starsMedium
    cmp #2
    beq .starsFast
    lda #0
    sec
    sbc FrameCounter
    lsr                     ; vertical-wave scene: medium-speed reverse drift
    bpl .storeStarOffset
.starsSlow
    lda FrameCounter
    lsr
    lsr
    bpl .storeStarOffset
.starsMedium
    lda FrameCounter
    lsr
    bpl .storeStarOffset
.starsFast
    lda FrameCounter
.storeStarOffset
    and #31
    sta CheckerState         ; safe scratch until checker setup below
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
    lda SpriteBuffer,y
    sta GRP0
.noSprite

; Animate a 32-line sparse star map through the 40-line sprite region. The
; bitmap repeats after 32 lines and reflection spreads 20 bits across the
; screen. GRP0 has already been written, preserving left-edge player timing.
    txa
    clc
    adc CheckerState
    and #31
    tay
    lda (StarPtr0),y
    sta PF0
    lda (StarPtr1),y
    sta PF1
    lda (StarPtr2),y
    sta PF2
    inx
    cpx #40
    bne .spriteLine

; -----------------------------------------------------------------------------
; Scene-specific animated checker grid - 32 scanlines
; -----------------------------------------------------------------------------
.checkerStart
; IntroStage zero reserves these 32 lines but draws black; the first milestone
; raises it to one and enables the checker without moving later components.
    lda IntroActive
    beq .showCheckerRegion
    lda IntroStage
    cmp #1
    bcs .showCheckerRegion
    ldx #32
.hiddenCheckerLine
    sta WSYNC
    dex
    bne .hiddenCheckerLine
    jmp .middleBarsStart
.showCheckerRegion
; ScenePattern is 0,64,128,192 for the four scenes. Dividing it by 32
; produces table-pair bases 0,2,4,6. FrameCounter selects one of the two phases
; in that pair, changing the starting phase every four video frames.
    lda ScenePattern
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CheckerState
    lda FrameCounter
    lsr
    lsr
    and #1
    ora CheckerState
    sta CheckerState
    tay
; CheckerHue advances once every 32 frames, half the previous grid color rate.
    lda CheckerHue
    eor #$B0
    ora #$0A
    and TransitionMask
    sta CheckerForeground
    lda CheckerHue
    ora #$02
    and TransitionMask
    sta CheckerBackground

; CTRLPF bit 0 reflects the 20-bit left playfield onto the right half. Unlike
; the title and ticker, the checker is symmetrical and needs only one set of
; PF0/PF1/PF2 writes per scanline. Write the cached colors only after WSYNC so
; they cannot recolor the right half of the preceding starfield scanline. The
; playfield registers follow early enough for their respective left-half fetch
; windows; GRP0 and reflection are then updated before the screen midpoint.
    ldx #32
.checkerLine
    sta WSYNC
    lda CheckerForeground
    sta COLUPF
    lda CheckerBackground
    sta COLUBK
    lda CheckerPF0,y
    sta PF0
    lda CheckerPF1,y
    sta PF1
    lda CheckerPF2,y
    sta PF2
    lda #0
    sta GRP0
    lda #1
    sta CTRLPF

; Count down from 32 and swap patterns whenever the remaining count is a
; multiple of four. This makes each visible checker cell four scanlines tall.
; Test for zero before an otherwise-unused final phase toggle; the short exit
; leaves enough time to prepare the first middle-raster color before its WSYNC.
    dex
    beq .middleBarsStart
    txa
    and #3
    bne .checkerKeep
    lda CheckerState
    eor #1
    sta CheckerState
    tay
.checkerKeep
    jmp .checkerLine

; -----------------------------------------------------------------------------
; Middle raster bars - 12 scanlines
; -----------------------------------------------------------------------------
.middleBarsStart
; ASL doubles X, so adjacent lines sample every other palette entry and produce
; a steeper color gradient than the top bars. Calculate each color before WSYNC
; and store it at cycle 3 to keep every row aligned. Clear the checker and its
; reflection immediately afterward, still in horizontal blank; clearing before
; WSYNC would erase the right edge of the checker's final visible scanline.
    ldx #11
.middleBars
    txa
    asl
    clc
    adc FrameCounter
    and #31
    tay
    lda Rainbow,y
    and TransitionMask
    sta WSYNC
    sta COLUBK
    lda #0
    sta PF0
    sta PF1
    sta PF2
    sta CTRLPF
    dex
    bpl .middleBars

; -----------------------------------------------------------------------------
; Scrolling ticker - 5 bitmap rows * 5 scanlines = 25 scanlines
; -----------------------------------------------------------------------------
; ScrollBuffer contains the current encoded 40-bit ticker image. Its
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
; Set the foreground while the playfield is zero on the last middle-bar line.
; The first ticker line is specialized so COLUBK changes only after WSYNC,
; inside horizontal blank, without shifting the right-half playfield writes.
; Cache the first bottom-bar color now as well. The ticker's final scanline is
; too cycle-tight to calculate it before its closing WSYNC, and calculating it
; afterward would leave a differently colored strip at the left edge.
; IntroStage values below 3 substitute 25 blank lines with identical height.
    lda FrameCounter
    clc
    adc #18
    and #31
    tay
    lda RainbowReverse,y
    and TransitionMask
    sta BottomBarColor
    lda IntroActive
    beq .showTickerRegion
    lda IntroStage
    cmp #3
    bcs .showTickerRegion
    lda #0                  ; keep the reserved scroll area black during intro
    ldx #25
.hiddenTickerLine
    sta WSYNC
    sta COLUBK
    dex
    bne .hiddenTickerLine
    jmp .bottomBarsStart
.showTickerRegion
; Derive a 16-color hue cycle from (DemoFrame >> 5), changing the ticker text
; once every 32 frames: four times slower than the main eight-frame hue cycle.
    lda DemoFrame+1
    lsr                     ; carry receives DemoFrame bit 8
    lda DemoFrame
    ror
    lsr
    lsr
    lsr
    lsr
    asl
    asl
    asl
    asl
    eor #$60
    ora #$0E
    and TransitionMask
    sta COLUPF
    ldy #0
    ldx #5
    lda ScrollBuffer,y
    sta WSYNC
    sty COLUBK              ; Y is zero: black at cycle 3
    sta PF0                 ; first left PF0 was preloaded before WSYNC
    lda ScrollBuffer+5,y
    sta PF1
    lda ScrollBuffer+10,y
    sta PF2
    nop
    nop
    nop
    nop
    nop
    jmp .tickerRight

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

; Six NOPs place the normal path's right-half writes at cycles 40/47/54.
    nop
    nop
    nop
    nop
    nop
    nop
.tickerRight
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
; RainbowReverse gives the lower border a complementary direction. The ticker
; playfield bits remain latched, but assigning the same color to COLUBK and
; COLUPF makes them invisible. The first color was cached before the ticker;
; later colors are calculated on the preceding line. This puts both color
; writes safely in horizontal blank without extending the tight ticker path.
; The extra WSYNC closes the nineteenth bar exactly at a scanline edge; Frame
; then enables VBLANK for overscan.
.bottomBarsStart
    ldx #18
    lda BottomBarColor
.bottomBars
    sta WSYNC
    sta COLUBK
    sta COLUPF
    dex
    bmi .bottomBarsDone
    txa
    clc
    adc FrameCounter
    and #31
    tay
    lda RainbowReverse,y
    and TransitionMask
    jmp .bottomBars
.bottomBarsDone
    sta WSYNC
    rts

; =============================================================================
; Read-only tables
; =============================================================================
; ALIGN 256 moves the next byte to a page boundary. This keeps the
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

; Four scene-specific player graphics, each eight rows of eight bits. NUSIZ0
; doubles each bit horizontally, but software still supplies one byte per line.
SpriteBitmaps
; Static: original alien/diamond.
    byte %00011000
    byte %00111100
    byte %01111110
    byte %11011011
    byte %11111111
    byte %01100110
    byte %00111100
    byte %00011000
; Type-on/off: square digital robot.
    byte %00111100
    byte %01000010
    byte %10100101
    byte %10000001
    byte %10111101
    byte %10000001
    byte %01000010
    byte %00111100
; Ripple: horizontally symmetric flying saucer with two landing-light rays.
; Symmetry keeps it facing naturally when the shared bounce code reverses X.
    byte %00011000
    byte %00111100
    byte %01111110
    byte %11111111
    byte %10111101
    byte %01111110
    byte %00100100
    byte %01000010
; Vertical wave: symmetric space jellyfish with a broad dome and four tentacles.
; Like the UFO, its symmetry remains natural across horizontal reversals.
    byte %00111100
    byte %01111110
    byte %11011011
    byte %11111111
    byte %11100111
    byte %00100100
    byte %01011010
    byte %10000001

; Four pairs of complementary 20-bit playfield patterns, one pair per scene:
; classic checks, digital blocks, narrow ripples, and chunky bounce
; blocks. CTRLPF reflection expands each 20-bit half across the screen. PF0
; uses only its upper four bits; PF1 and PF2 use all eight bits.
CheckerPF0
    byte %10100000,%01010000   ; static: classic checker
    byte %11110000,%00000000   ; type: digital blocks
    byte %11000000,%00110000   ; ripple: narrow travelling bands
    byte %11110000,%00000000   ; vertical wave: large chunky blocks
CheckerPF1
    byte %10101010,%01010101
    byte %11110000,%00001111
    byte %11001100,%00110011
    byte %11111111,%00000000
CheckerPF2
    byte %01010101,%10101010
    byte %00001111,%11110000
    byte %00110011,%11001100
    byte %00000000,%11111111

; Sparse 32-line star map for the sprite region. Only a few playfield bits are
; active on any line; vertical indexing makes them drift while reflection
; produces a full-width field from these three compact tables.
StarPF0
    byte $00,$00,$10,$00,$00,$00,$80,$00
    byte $00,$20,$00,$00,$00,$40,$00,$00
    byte $00,$00,$00,$80,$00,$10,$00,$00
    byte $40,$00,$00,$00,$20,$00,$00,$00
StarPF1
    byte $00,$04,$00,$00,$40,$00,$00,$01
    byte $00,$00,$10,$00,$00,$00,$80,$00
    byte $02,$00,$00,$20,$00,$00,$00,$08
    byte $00,$80,$00,$00,$04,$00,$00,$20
StarPF2
    byte $20,$00,$00,$01,$00,$00,$40,$00
    byte $00,$08,$00,$80,$00,$00,$02,$00
    byte $00,$40,$00,$00,$10,$00,$01,$00
    byte $08,$00,$00,$00,$80,$00,$00,$04

; Plane permutations make each scene's star distribution visibly distinct.
StarPlane0Low
    byte <StarPF0,<StarPF1,<StarPF2,<StarPF0
StarPlane1Low
    byte <StarPF1,<StarPF2,<StarPF0,<StarPF2
StarPlane2Low
    byte <StarPF2,<StarPF0,<StarPF1,<StarPF1

; Take On Me frame-driven TIA player
;
; The musical source is derived from Jukebox by Lloyd Russell, published as a
; type-in for the ZX Spectrum 128K in Your Sinclair issue 21 (September 1987).
; Its AY arrangement was reduced to a selected lead on TIA channel 0 and bass
; on channel 1. This player is intentionally independent of the visual scene
; counter: TakeOnMe_Update is called exactly once per 60 Hz NTSC frame.
;
; Each channel has its own pointer and countdown. Records contain three bytes:
; duration in video frames, AUDF, and (AUDC << 4) | AUDV. A zero duration is an
; end marker that resets only that channel to the beginning of its stream.
TakeOnMe_Init
; Point both readers at their first records. Timers start at one so the first
; call to TakeOnMe_Update loads intentional register values immediately.
    lda #<TakeOnMeMelody
    sta MusicPtr0
    lda #>TakeOnMeMelody
    sta MusicPtr0+1
    lda #<TakeOnMeBass
    sta MusicPtr1
    lda #>TakeOnMeBass
    sta MusicPtr1+1
    lda #1
    sta MusicTimer0
    sta MusicTimer1
    lda #0
    sta AUDV0
    sta AUDV1
    rts

TakeOnMe_Update
; Count each channel independently; a channel touches TIA registers only when
; its current event expires. Most frames therefore take the short branch path.
    dec MusicTimer0
    bne .bass
    jsr TakeOnMe_Load0
.bass
    dec MusicTimer1
    bne .done
    jsr TakeOnMe_Load1
.done
    rts

TakeOnMe_Load0
; Y selects the three fields without modifying the persistent 16-bit pointer.
    ldy #0
    lda (MusicPtr0),y
    bne .event0
    lda #<TakeOnMeMelody
    sta MusicPtr0
    lda #>TakeOnMeMelody
    sta MusicPtr0+1
    jmp TakeOnMe_Load0
.event0
    sta MusicTimer0
    iny
    lda (MusicPtr0),y
    sta AUDF0
    iny
    lda (MusicPtr0),y
    pha
; Low nibble is volume. Preserve the packed byte on the stack, then shift its
; high nibble down to obtain the waveform/control value.
    and #$0F
    sta AUDV0
    pla
    lsr
    lsr
    lsr
    lsr
    sta AUDC0
; Advance the 16-bit pointer to the following three-byte record.
    clc
    lda MusicPtr0
    adc #3
    sta MusicPtr0
    bcc .return0
    inc MusicPtr0+1
.return0
    rts

TakeOnMe_Load1
; Channel 1 mirrors the decoder above but writes the bass-side TIA registers.
    ldy #0
    lda (MusicPtr1),y
    bne .event1
    lda #<TakeOnMeBass
    sta MusicPtr1
    lda #>TakeOnMeBass
    sta MusicPtr1+1
    jmp TakeOnMe_Load1
.event1
    sta MusicTimer1
    iny
    lda (MusicPtr1),y
    sta AUDF1
    iny
    lda (MusicPtr1),y
    pha
    and #$0F
    sta AUDV1
    pla
    lsr
    lsr
    lsr
    lsr
    sta AUDC1
    clc
    lda MusicPtr1
    adc #3
    sta MusicPtr1
    bcc .return1
    inc MusicPtr1+1
.return1
    rts

    include "src/take_on_me_tia_data.inc"

; Eight purely horizontal ripple phases, seven rows each.
RippleFrameOffsets
    byte 0,7,14,21,28,35,42,49

; Five reveal phases follow, displaying 0, 2, 4, 6, or 8 letters. Repeated
; offsets preserve the type-on/type-off scene's 16-frame phase rhythm.
RevealFrameOffsets
    byte 56,56,63,63,70,70,77,77,84,84,77,77,70,70,63,63

; Four independent-letter vertical-wave phases occupy the final table rows.
VerticalFrameOffsets
    byte 91,98,105,112

; The three introduction milestones are 256 frames apart: grid at 256,
; sprite/starfield at 512, and ticker at 768. Scene 2 begins as soon as the
; fourth 256-frame reveal stage ends at visual counter $0400.
IntroMilestoneLow
    byte $00,$00,$00
IntroMilestoneHigh
    byte $01,$02,$03

; Start each 256-frame transition 128 frames before a scene boundary.
TransitionStartLow
    byte $80,$80,$80,$80    ; 896, 1920, 2944, and 3968 frames
TransitionStartHigh
    byte $03,$07,$0B,$0F

; Luminance masks for half-countdown indices 0..127. The masks progressively
; remove the TIA's three luminance bits, hold the picture dark across the scene
; switch, and restore those bits in reverse. UpdateTransition derives the same
; 0..127 range from both halves of its 256-frame countdown. Hue bits are always
; preserved, and $FE is effectively full brightness because NTSC TIA colors
; use even luminance values.
TransitionMasks
    byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
    byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
    byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
    byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
    byte $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
    byte $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
    byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
    byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
    byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
    byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
    byte $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
    byte $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
    byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
    byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
    byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
    byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE

; The Python asset tool creates:
;
;   - six 119-byte title tables (8 ripple, 5 reveal, 4 vertical-wave phases)
;   - one 30-byte initial ticker window
;   - one compact five-bit byte for each ticker source column
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
