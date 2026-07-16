#!/usr/bin/env python3
"""Generate ROM assets consumed by The Teeny-tiny Atari 2600 demo kernel.

The assembly cannot afford to translate readable bitmap rows into the TIA's
PF0/PF1/PF2 bit order while the beam is visible. This build-time tool emits:

* 17 seven-row title phases (8 horizontal-ripple, 5 type-on reveal, and 4
  vertical-letter-wave phases), split into six register-major tables; and
* a 30-byte encoded ticker seed plus a circular stream of packed 5-pixel-high
  source columns that the VBLANK code shifts into the seed two at a time.

Output is DASM source written to stdout and redirected to build/assets.inc by
the Makefile. The generated file is disposable and must not be edited by hand.
"""

# The title uses a custom 4x7 font. There is no separate space glyph because
# the fixed title text is assembled with one blank column between characters.
TITLE_FONT = {
    "S": ("1111", "1000", "1000", "1111", "0001", "0001", "1111"),
    "Q": ("1110", "1001", "1001", "1001", "1011", "1110", "0011"),
    "U": ("1001", "1001", "1001", "1001", "1001", "1001", "1111"),
    "E": ("1111", "1000", "1000", "1110", "1000", "1000", "1111"),
    "P": ("1110", "1001", "1001", "1110", "1000", "1000", "1000"),
    "T": ("1111", "0110", "0110", "0110", "0110", "0110", "0110"),
    "Y": ("1001", "1001", "1001", "0110", "0110", "0110", "0110"),
}

# The ticker uses a denser 3x5 font so a useful message fits in a small circular
# column stream. Every character used by the message must be present here.
TICKER_FONT = {
    " ": ("000", "000", "000", "000", "000"),
    "!": ("010", "010", "010", "000", "010"),
    "*": ("101", "010", "111", "010", "101"),
    ".": ("000", "000", "000", "000", "010"),
    "/": ("001", "001", "010", "100", "100"),
    "0": ("111", "101", "101", "101", "111"),
    "2": ("110", "001", "010", "100", "111"),
    "6": ("011", "100", "111", "101", "111"),
    "A": ("010", "101", "111", "101", "101"),
    "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "110", "100", "111"),
    "F": ("111", "100", "110", "100", "100"),
    "G": ("011", "100", "101", "101", "011"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"),
    "N": ("101", "111", "111", "111", "101"),
    "O": ("111", "101", "101", "101", "111"),
    "P": ("110", "101", "110", "100", "100"),
    "Q": ("111", "101", "101", "111", "001"),
    "R": ("110", "101", "110", "101", "101"),
    "S": ("011", "100", "111", "001", "110"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"),
    "W": ("101", "101", "101", "111", "010"),
    "Y": ("101", "101", "010", "010", "010"),
}


def text_rows(text, font, height, spacing=1):
    """Expand *text* into ``height`` rows of integer pixels.

    Glyph strings use ``"1"`` for a set pixel and ``"0"`` for background.
    ``spacing`` blank columns are inserted between, but never after, glyphs.
    The result is row-major because both title and ticker generation transform
    complete horizontal scan rows before rearranging them for TIA registers.
    """
    rows = [[] for _ in range(height)]
    for char_index, char in enumerate(text):
        glyph = font[char]
        for row_index, row in enumerate(glyph):
            rows[row_index].extend(int(pixel) for pixel in row)
            if spacing and char_index != len(text) - 1:
                rows[row_index].extend([0] * spacing)
    return rows


def reverse_bits(value):
    """Return an 8-bit value with bit order reversed."""
    result = 0
    for bit in range(8):
        result |= ((value >> bit) & 1) << (7 - bit)
    return result


def bits_to_byte(bits):
    """Pack an iterable of left-to-right bits into a most-significant-bit-first byte."""
    value = 0
    for bit in bits:
        value = (value << 1) | bit
    return value


def encode_half(pixels):
    """Encode exactly 20 left-to-right pixels as PF0/PF1/PF2 values.

    TIA displays PF0 bits 4->7, PF1 bits 7->0, then PF2 bits 0->7. PF0's low
    nibble is unused. Reversing the final eight source bits makes the returned
    tuple match that hardware display order when stored directly.
    """
    pf0 = sum(pixel << (4 + index) for index, pixel in enumerate(pixels[:4]))
    pf1 = bits_to_byte(pixels[4:12])
    pf2 = reverse_bits(bits_to_byte(pixels[12:20]))
    return pf0, pf1, pf2


def encode_row(pixels):
    """Pad or truncate a row to 40 pixels and encode independent screen halves."""
    padded = (pixels + [0] * 40)[:40]
    left = encode_half(padded[:20])
    right = encode_half(padded[20:40])
    return left + right


def emit_bytes(label, values, per_line=16):
    """Print one DASM byte table with hexadecimal values and a leading label."""
    print(f"{label}")
    for start in range(0, len(values), per_line):
        chunk = values[start : start + per_line]
        encoded = ",".join(f"${value:02X}" for value in chunk)
        print(f"    byte {encoded}")


def generate_title():
    """Emit six page-safe register-major tables for every title animation phase."""
    rows = text_rows("SQUEEPTY", TITLE_FONT, 7)
    # The first eight phases are a purely horizontal ripple. Successive bitmap
    # rows move sideways, while every letter keeps its original vertical row.
    ripple_offsets = (
        (1, 1, 1, 1, 1, 1, 1),
        (1, 2, 3, 3, 2, 1, 0),
        (2, 3, 3, 2, 1, 0, 0),
        (3, 3, 2, 1, 0, 0, 1),
        (3, 2, 1, 0, 0, 1, 2),
        (2, 1, 0, 0, 1, 2, 3),
        (1, 0, 0, 1, 2, 3, 3),
        (0, 0, 1, 2, 3, 3, 2),
    )
    ripple_phases = [
        [encode_row([0] * offsets[row_index] + row) for row_index, row in enumerate(rows)]
        for offsets in ripple_offsets
    ]

    # Five phases reveal the title in two-letter increments. RevealFrameOffsets
    # maps them onto a 16-entry forward/backward visual cycle; each selector
    # entry lasts 16 frames, and duplicates hold a source phase for 32 frames.
    reveal_phases = []
    for visible_letters in range(0, 9, 2):
        if visible_letters:
            reveal_rows = text_rows("SQUEEPTY"[:visible_letters], TITLE_FONT, 7)
        else:
            reveal_rows = [[] for _ in range(7)]
        reveal_phases.append([encode_row([0] + row) for row in reveal_rows])

    # The final four phases form a separate vertical wave. Their glyphs use
    # five representative source rows inside the seven-row title box, leaving
    # a blank row above and below. Letters can therefore move by one complete
    # bitmap row without being clipped or moving the background region.
    vertical_wave = (
        (0, 1, 1, 0, 0, -1, -1, 0),
        (1, 1, 0, 0, -1, -1, 0, 0),
        (0, 0, -1, -1, 0, 0, 1, 1),
        (-1, -1, 0, 0, 1, 1, 0, 0),
    )
    vertical_glyph_rows = (0, 1, 3, 5, 6)
    vertical_phases = []
    for offsets in vertical_wave:
        phase_rows = []
        for output_row in range(7):
            pixels = []
            for letter_index, char in enumerate("SQUEEPTY"):
                source_row = output_row - offsets[letter_index] - 1
                glyph_row = (
                    TITLE_FONT[char][vertical_glyph_rows[source_row]]
                    if 0 <= source_row < 5
                    else "0000"
                )
                pixels.extend(int(pixel) for pixel in glyph_row)
                if letter_index != 7:
                    pixels.append(0)
            phase_rows.append(encode_row([0] + pixels))
        vertical_phases.append(phase_rows)

    phases = ripple_phases + reveal_phases + vertical_phases
    labels = (
        "TitlePF0L",
        "TitlePF1L",
        "TitlePF2L",
        "TitlePF0R",
        "TitlePF1R",
        "TitlePF2R",
    )
    # Y indexes as far as 118 into each table. Put two 119-byte tables on each
    # page, ensuring no indexed load crosses a page and changes kernel timing.
    print("    ALIGN 256")
    for column, label in enumerate(labels):
        if column in (2, 4):
            print("    ALIGN 256")
        emit_bytes(
            label,
            [row[column] for phase in phases for row in phase],
        )


def generate_scroll():
    """Emit the encoded ticker window and its circular packed-column stream."""
    message = "    GREETINGS TO ALL ATARI DREAMERS...    "
    source_rows = text_rows(message, TICKER_FONT, 5)
    width = len(source_rows[0])
    if width <= 40:
        raise ValueError("ticker source must be wider than its 40-bit window")

    # Seed the visible kernel's register-major RAM buffer with source columns
    # 0..39. Runtime VBLANK code shifts this encoded image one bit at a time.
    initial_rows = [encode_row(source[:40]) for source in source_rows]
    initial = []
    for register in range(6):
        initial.extend(row[register] for row in initial_rows)
    emit_bytes("ScrollInitial", initial)

    # Each byte is one vertical source slice. Bits 4..0 contain text rows 0..4
    # so the assembly's descending row loop can consume them with LSR. The
    # first 40 columns are retained for circular wrap; initial playback starts
    # at ScrollNextColumn because columns 0..39 are already visible.
    columns = []
    for column in range(width):
        packed = sum(
            source_rows[row][column] << (4 - row) for row in range(5)
        )
        columns.append(packed)

    emit_bytes("ScrollColumns", columns[:40])
    emit_bytes("ScrollNextColumn", columns[40:])
    print("ScrollColumnsEnd")
    # The assembly currently wraps by address; expose the count as a generated
    # constant as well so listings and future bounds checks can verify it.
    print(f"SCROLL_COLUMN_COUNT = {len(columns)}")


def main():
    """Write the complete generated DASM include to standard output."""
    print("; Generated by tools/gen_assets.py. Do not edit by hand.")
    generate_title()
    generate_scroll()


if __name__ == "__main__":
    main()
