# Makefile for the Sunrise IDE driver for Nextor 3.
#
# By default builds four ROMs (combining this driver with the Nextor
# kernel base file pointed at by NEXTOR_BASE):
#
#   * Nextor-<ver>.SunriseIDE.ROM                     - master + slave
#   * Nextor-<ver>.SunriseIDE.MasterOnly.ROM          - master only
#   * Nextor-<ver>.SunriseIDE.blueMSX.ROM             - blueMSX emulator variant
#   * Nextor-<ver>.SunriseIDE.MasterOnly.blueMSX.ROM  - master only, blueMSX
#
# <ver> and any variant suffix (e.g. ".NO_UNDOC.SHIFT_INV") are taken
# from the NEXTOR_BASE filename, which must follow the convention
# Nextor-<ver>.base[<suffix>].dat as produced by the Nextor kernel
# Makefile. If NEXTOR_BASE has a non-standard filename, the ROMs are
# named after that filename's stem instead.


### Configurable variables ###################################################

# NEXTOR_BASE: path to the Nextor kernel base .dat file (mandatory for
# all targets except `clean`).
ifeq ($(strip $(NEXTOR_BASE)),)
ifneq ($(MAKECMDGOALS),clean)
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

ROM_REGULAR            := $(_DRIVER_PREFIX)$(_VARIANT).ROM
ROM_MASTERONLY         := $(_DRIVER_PREFIX).MasterOnly$(_VARIANT).ROM
ROM_BLUEMSX            := $(_DRIVER_PREFIX).blueMSX$(_VARIANT).ROM
ROM_MASTERONLY_BLUEMSX := $(_DRIVER_PREFIX).MasterOnly.blueMSX$(_VARIANT).ROM


### Assembly flags ###########################################################

N80_FLAGS := --no-string-escapes --no-show-banner --verbosity 0 \
             --build-type abs --output-file-extension bin \
             --output-file-case lower \
             --include-directory $(NEXTOR_SDK)

_DEFINES_NO_UNDOC := $(if $(NO_UNDOC_CPU_INSTRUCTIONS),--define-symbols NO_UNDOC_CPU_INSTRUCTIONS)


### Default target ###########################################################

.PHONY: all clean
all: $(ROM_REGULAR) $(ROM_MASTERONLY) $(ROM_BLUEMSX) $(ROM_MASTERONLY_BLUEMSX)


### Driver and chgbnk binaries ###############################################

# 'driver.asm' produces the hardware driver.

driver.bin: driver.asm
	$(N80) driver.asm $$ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)

driver.masteronly.bin: driver.asm
	$(N80) driver.asm $$/driver.masteronly.bin $(N80_FLAGS) $(_DEFINES_NO_UNDOC) --define-symbols MASTER_ONLY

# 'driver-bluemsx.asm' is the variant used inside the blueMSX emulator.

driver-bluemsx.bin: driver-bluemsx.asm
	$(N80) driver-bluemsx.asm $$ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)

driver-bluemsx.masteronly.bin: driver-bluemsx.asm
	$(N80) driver-bluemsx.asm $$/driver-bluemsx.masteronly.bin $(N80_FLAGS) $(_DEFINES_NO_UNDOC) --define-symbols MASTER_ONLY

chgbnk.bin: chgbnk.asm
	$(N80) chgbnk.asm $$ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)


### ROM combination via mknexrom #############################################

$(ROM_REGULAR): driver.bin chgbnk.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:driver.bin /m:chgbnk.bin

$(ROM_MASTERONLY): driver.masteronly.bin chgbnk.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:driver.masteronly.bin /m:chgbnk.bin

# The blueMSX-targeted ROMs need a 256-byte zero block prepended to the
# driver binary before mknexrom combines it with the kernel.

256.bytes:
	dd if=/dev/zero of=256.bytes bs=1 count=256

$(ROM_BLUEMSX): driver-bluemsx.bin chgbnk.bin 256.bytes
	cat 256.bytes driver-bluemsx.bin > _driver-bluemsx.padded.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:_driver-bluemsx.padded.bin /m:chgbnk.bin
	rm -f _driver-bluemsx.padded.bin

$(ROM_MASTERONLY_BLUEMSX): driver-bluemsx.masteronly.bin chgbnk.bin 256.bytes
	cat 256.bytes driver-bluemsx.masteronly.bin > _driver-bluemsx-masteronly.padded.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:_driver-bluemsx-masteronly.padded.bin /m:chgbnk.bin
	rm -f _driver-bluemsx-masteronly.padded.bin


### Housekeeping #############################################################

clean:
	rm -f *.bin *.ROM *.sym 256.bytes
