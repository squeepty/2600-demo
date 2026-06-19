DASM ?= dasm
PYTHON ?= python3

ROM := build/squeepty.bin
LIST := build/squeepty.lst
SYMBOLS := build/squeepty.sym
ASSETS := build/assets.inc

.PHONY: all clean check

all: $(ROM)

build:
	mkdir -p build

$(ASSETS): tools/gen_assets.py | build
	$(PYTHON) tools/gen_assets.py > $(ASSETS)

$(ROM): src/demo.asm $(ASSETS)
	$(DASM) src/demo.asm -f3 -o$(ROM) -l$(LIST) -s$(SYMBOLS)
	@test "$$(wc -c < $(ROM) | tr -d ' ')" = "4096"

check: $(ROM)
	@printf "ROM: %s bytes\n" "$$(wc -c < $(ROM) | tr -d ' ')"
	@shasum -a 256 $(ROM)

clean:
	rm -rf build
