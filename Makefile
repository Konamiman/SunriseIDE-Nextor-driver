# Makefile for the Sunrise IDE driver for Nextor 3.
#
# By default builds four ROMs (combining this driver with the Nextor
# kernel base file pointed at by NEXTOR_BASE), placed in `bin/`:
#
#   * bin/Nextor-<ver>.SunriseIDE.ROM                     - master + slave
#   * bin/Nextor-<ver>.SunriseIDE.MasterOnly.ROM          - master only
#   * bin/Nextor-<ver>.SunriseIDE.blueMSX.ROM             - blueMSX emulator variant
#   * bin/Nextor-<ver>.SunriseIDE.MasterOnly.blueMSX.ROM  - master only, blueMSX
#
# Intermediate build artifacts (.bin files produced by N80, the
# 256-byte zero block, the temporary padded blueMSX driver images) go
# to `tmp/` instead and are dropped by `make clean`. The shippable
# ROMs in `bin/` survive `make clean` and are removed only by
# `make clean-bin` (or `make distclean` for both).
#
# <ver> and any variant suffix (e.g. ".NO_UNDOC.SHIFT_INV") are taken
# from the NEXTOR_BASE filename, which must follow the convention
# Nextor-<ver>.base[<suffix>].dat as produced by the Nextor kernel
# Makefile. If NEXTOR_BASE has a non-standard filename, the ROMs are
# named after that filename's stem instead.


### Configurable variables ###################################################

# NEXTOR_BASE: path to the Nextor kernel base .dat file (mandatory for
# every target except `setup` and the clean ones).
ifeq ($(strip $(NEXTOR_BASE)),)
ifeq ($(filter setup clean clean-bin distclean,$(MAKECMDGOALS)),)
$(error NEXTOR_BASE is not set. Point it at a Nextor kernel base .dat file)
endif
else
ifeq ($(wildcard $(NEXTOR_BASE)),)
$(error NEXTOR_BASE points at '$(NEXTOR_BASE)' which does not exist)
endif
endif

# NEXTOR_SDK: path to the Nextor SDK directory (the one containing 'asm/').
# Defaults to the bundled git submodule.
NEXTOR_SDK ?= external/Nextor/sdk

# Tool overrides. Default to invoking the executables from PATH.
N80      ?= N80
MKNEXROM ?= mknexrom

# NO_UNDOC_CPU_INSTRUCTIONS: when set (e.g. =1) the driver is assembled
# with undocumented Z80 opcodes (those operating on ixh/ixl/iyh/iyl)
# replaced with documented equivalents, for compatibility with
# Z180-based MSX machines. Set this whenever NEXTOR_BASE points at a
# .NO_UNDOC. variant; the driver developer is responsible for keeping
# the two consistent.
NO_UNDOC_CPU_INSTRUCTIONS ?=


### Output directories #######################################################

BIN := bin
TMP := tmp


### Filename derivation ######################################################

# Decompose NEXTOR_BASE's basename: 'Nextor-<ver>.base[.<suffix>].dat'.
_BASE_NAME    := $(notdir $(NEXTOR_BASE))
_BASE_STEM    := $(_BASE_NAME:.dat=)
_BASE_VERSION := $(firstword $(subst .base, ,$(_BASE_STEM)))
_BASE_SUFFIX  := $(patsubst $(_BASE_VERSION).base%,%,$(_BASE_STEM))

# If the filename didn't parse (no '.base' found), fall back to using
# the whole stem as the prefix and no variant suffix.
ifeq ($(_BASE_SUFFIX),$(_BASE_STEM))
_DRIVER_PREFIX := $(_BASE_STEM)
_VARIANT       :=
else
_DRIVER_PREFIX := $(_BASE_VERSION).SunriseIDE
_VARIANT       := $(_BASE_SUFFIX)
endif

ROM_REGULAR            := $(BIN)/$(_DRIVER_PREFIX)$(_VARIANT).ROM
ROM_MASTERONLY         := $(BIN)/$(_DRIVER_PREFIX).MasterOnly$(_VARIANT).ROM
ROM_BLUEMSX            := $(BIN)/$(_DRIVER_PREFIX).blueMSX$(_VARIANT).ROM
ROM_MASTERONLY_BLUEMSX := $(BIN)/$(_DRIVER_PREFIX).MasterOnly.blueMSX$(_VARIANT).ROM


### Assembly flags ###########################################################

N80_FLAGS := --no-string-escapes --no-show-banner --verbosity 0 \
             --build-type abs --output-file-extension bin \
             --output-file-case lower \
             --include-directory $(NEXTOR_SDK)

_DEFINES_NO_UNDOC := $(if $(NO_UNDOC_CPU_INSTRUCTIONS),--define-symbols NO_UNDOC_CPU_INSTRUCTIONS)


### Default target ###########################################################

.PHONY: all clean clean-bin distclean
all: $(ROM_REGULAR) $(ROM_MASTERONLY) $(ROM_BLUEMSX) $(ROM_MASTERONLY_BLUEMSX)

# Order-only prereqs for outputs that live in the build directories:
# ensure the directory exists without making its mtime affect rebuild
# decisions.
$(BIN) $(TMP):
	@mkdir -p $@


### Driver and chgbnk binaries (intermediates) ###############################

# 'driver.asm' produces the hardware driver. N80's "if the output path
# is a directory, use the default base name in it" behavior lets us
# point it at $(TMP)/ for the regular variants.

$(TMP)/driver.bin: driver.asm | $(TMP)
	$(N80) driver.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)

$(TMP)/driver.masteronly.bin: driver.asm | $(TMP)
	$(N80) driver.asm $(TMP)/driver.masteronly.bin $(N80_FLAGS) $(_DEFINES_NO_UNDOC) --define-symbols MASTER_ONLY

# 'driver-bluemsx.asm' is the variant used inside the blueMSX emulator.

$(TMP)/driver-bluemsx.bin: driver-bluemsx.asm | $(TMP)
	$(N80) driver-bluemsx.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)

$(TMP)/driver-bluemsx.masteronly.bin: driver-bluemsx.asm | $(TMP)
	$(N80) driver-bluemsx.asm $(TMP)/driver-bluemsx.masteronly.bin $(N80_FLAGS) $(_DEFINES_NO_UNDOC) --define-symbols MASTER_ONLY

$(TMP)/chgbnk.bin: chgbnk.asm | $(TMP)
	$(N80) chgbnk.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)


### ROM combination via mknexrom (final outputs) #############################

$(ROM_REGULAR): $(TMP)/driver.bin $(TMP)/chgbnk.bin | $(BIN)
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:$(TMP)/driver.bin /m:$(TMP)/chgbnk.bin

$(ROM_MASTERONLY): $(TMP)/driver.masteronly.bin $(TMP)/chgbnk.bin | $(BIN)
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:$(TMP)/driver.masteronly.bin /m:$(TMP)/chgbnk.bin

# The blueMSX-targeted ROMs need a 256-byte zero block prepended to the
# driver binary before mknexrom combines it with the kernel.

$(TMP)/256.bytes: | $(TMP)
	dd if=/dev/zero of=$@ bs=1 count=256

$(ROM_BLUEMSX): $(TMP)/driver-bluemsx.bin $(TMP)/chgbnk.bin $(TMP)/256.bytes | $(BIN)
	cat $(TMP)/256.bytes $(TMP)/driver-bluemsx.bin > $(TMP)/_driver-bluemsx.padded.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:$(TMP)/_driver-bluemsx.padded.bin /m:$(TMP)/chgbnk.bin
	rm -f $(TMP)/_driver-bluemsx.padded.bin

$(ROM_MASTERONLY_BLUEMSX): $(TMP)/driver-bluemsx.masteronly.bin $(TMP)/chgbnk.bin $(TMP)/256.bytes | $(BIN)
	cat $(TMP)/256.bytes $(TMP)/driver-bluemsx.masteronly.bin > $(TMP)/_driver-bluemsx-masteronly.padded.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:$(TMP)/_driver-bluemsx-masteronly.padded.bin /m:$(TMP)/chgbnk.bin
	rm -f $(TMP)/_driver-bluemsx-masteronly.padded.bin


### Housekeeping #############################################################

# `make clean` keeps the shippable ROMs in bin/, only wipes intermediates.
clean:
	rm -rf $(TMP)

# `make clean-bin` removes the shippable ROMs.
clean-bin:
	rm -rf $(BIN)

# `make distclean` removes both.
distclean: clean clean-bin


### One-time setup ###########################################################

# `make setup` initializes the Nextor SDK submodule as a blobless
# partial clone with sparse-checkout for the `sdk/` directory only, so
# that the full Nextor repository is never fetched. Run this once,
# right after cloning this repo, to initialize the external/Nextor directory.
.PHONY: setup
setup:
	@echo "Setting up the Nextor SDK submodule (blobless + sparse-checkout for sdk/ only)..."
	git submodule init external/Nextor
	git submodule update --init --filter=blob:none external/Nextor
	git -C external/Nextor sparse-checkout init --cone
	git -C external/Nextor sparse-checkout set sdk
	git -C external/Nextor checkout
	@echo "Done. Set NEXTOR_BASE and run 'make' to build."
