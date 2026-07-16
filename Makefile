# The Teeny-tiny Atari 2600 demo build pipeline. Override DASM or PYTHON when
# tools are not on PATH, for example: make DASM=/opt/dasm/bin/dasm.
DASM ?= dasm
PYTHON ?= python3

# Public artifacts and assembler diagnostics.
ROM := downloads/squeepty-2600-demo.bin
RELEASE_ZIP := downloads/SQUEEPTY_2600_Demo.zip
LIST := build/squeepty.lst
SYMBOLS := build/squeepty.sym
ASSETS := build/assets.inc

# Release staging preserves the uppercase DOS-era filenames used in the ZIP.
RELEASE_STAGE := build/release/SQUEEPTY_2600_Demo
RELEASE_FILES := release/README.txt release/SQUEEPTY.NFO release/FILE_ID.DIZ

.PHONY: all clean check release

all: $(ROM)

build:
	mkdir -p build

downloads:
	mkdir -p downloads

# Generate cycle-friendly title/ticker tables from readable Python bitmaps.
$(ASSETS): tools/gen_assets.py | build
	$(PYTHON) tools/gen_assets.py > $(ASSETS)

# -f3 selects a raw binary image. The size assertion guards against accidental
# overflow or underfill of the fixed 4 KiB cartridge address space.
$(ROM): src/demo.asm src/take_on_me_tia_data.inc $(ASSETS) | downloads
	$(DASM) src/demo.asm -f3 -o$(ROM) -l$(LIST) -s$(SYMBOLS)
	@test "$$(wc -c < $(ROM) | tr -d ' ')" = "4096"

# Print a reproducible identity for the current binary after building it.
check: $(ROM)
	@printf "ROM: %s bytes\n" "$$(wc -c < $(ROM) | tr -d ' ')"
	@shasum -a 256 $(ROM)

release: $(RELEASE_ZIP)

# Package the ROM and emulator-facing text files in a clean staging directory.
$(RELEASE_ZIP): $(ROM) $(RELEASE_FILES) | downloads
	rm -rf $(RELEASE_STAGE)
	rm -f $(RELEASE_ZIP)
	mkdir -p $(RELEASE_STAGE)
	cp $(ROM) $(RELEASE_STAGE)/SQUEEPTY.BIN
	cp $(RELEASE_FILES) $(RELEASE_STAGE)/
	cd build/release && zip -X -q -r ../../$(RELEASE_ZIP) SQUEEPTY_2600_Demo
	@printf "Release archive: %s\n" "$(RELEASE_ZIP)"
	@unzip -t $(RELEASE_ZIP)

clean:
	rm -rf build
