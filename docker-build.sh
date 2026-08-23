#!/bin/sh
# docker-build.sh - build the Sunrise IDE driver ROMs using the Nextor dev
# Docker image, with no local toolchain, SDK submodule or kernel base file
# needed: the image supplies N80, mknexrom, the Nextor SDK and all twelve
# kernel base-file variants, and presets NEXTOR_BASE / NEXTOR_SDK so plain
# `make` inside it just works.
#
# Usage:
#   ./docker-build.sh [--variant <suffix>] [--image <ref>] [make args...]
#
#   ./docker-build.sh                           # all ROMs, default kernel base
#   ./docker-build.sh --variant NO_UNDOC        # build against the NO_UNDOC base
#   ./docker-build.sh --variant CTRL_INV
#   ./docker-build.sh --variant NO_UNDOC.SHIFT_INV
#   ./docker-build.sh --variant KANJI_INV
#   ./docker-build.sh --variant NO_UNDOC.CTRL_INV.KANJI_INV
#   ./docker-build.sh --variant all             # build against every base variant
#   ./docker-build.sh clean                     # pass-through make targets
#   ./docker-build.sh --variant NO_UNDOC distclean
#
# Kernel base variants (the <suffix> is the part after 'kernel_base' in the
# image's /opt/nextor/kernel_base/kernel_base<suffix>.dat files):
#   (omit --variant)    default base
#   NO_UNDOC            no undocumented Z80 opcodes (Z180-safe)
#   SHIFT_INV           inverted SHIFT-at-boot behaviour
#   CTRL_INV            inverted CTRL-at-boot behaviour
#   NO_UNDOC.SHIFT_INV  combinations of the above
#   NO_UNDOC.CTRL_INV
#   KANJI_INV           inverted "6"-at-boot behaviour (Kanji driver installed
#                       at boot unless "6" is pressed); combines with each of
#                       the above, always as the last component:
#                       NO_UNDOC.KANJI_INV, SHIFT_INV.KANJI_INV,
#                       CTRL_INV.KANJI_INV, NO_UNDOC.SHIFT_INV.KANJI_INV,
#                       NO_UNDOC.CTRL_INV.KANJI_INV
#   all                 build against every base file the image ships, in
#                       one container (runs build-all.sh inside it)
# For the *NO_UNDOC* variants the Makefile assembles the driver undoc-free to
# match (it infers NO_UNDOC_CPU_INSTRUCTIONS from the base filename).
#
# The image is pulled automatically on first use. Override it with --image or
# the NEXTOR_IMAGE environment variable. The default is pinned to the kernel
# version this driver is built for (the image's `latest` tag only tracks
# stable kernel releases, so it is not suitable while targeting a prerelease).
set -eu

# Print the leading comment block (everything from line 2 up to, but not
# including, the first non-comment line) as help text.
usage() { sed -n '2,/^[^#]/p' "$0" | sed '/^[^#]/d; s/^#\{1,\} \{0,1\}//; s/^#$//'; }

IMAGE="${NEXTOR_IMAGE:-ghcr.io/konamiman/nextor-dev:3.0.0-beta1}"
KERNEL_BASE_DIR=/opt/nextor/kernel_base
variant=
makeargs=

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)    usage; exit 0 ;;
		--variant)    shift; variant="${1:-}" ;;
		--variant=*)  variant="${1#--variant=}" ;;
		--image)      shift; IMAGE="${1:-}" ;;
		--image=*)    IMAGE="${1#--image=}" ;;
		*)            makeargs="$makeargs $1" ;;
	esac
	shift
done

# Mount the repository root (the script's own directory) at /work regardless of
# the caller's current directory, and run as the host user so the ROMs written
# to bin/ are owned by you, not root. HOME is set because Nestor80 (.NET) wants
# a writable home directory.
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

run_in_image() { # run_in_image <docker-run-args...>
	# shellcheck disable=SC2086
	exec docker run --rm \
		-v "$repo_root":/work \
		-w /work \
		--user "$(id -u):$(id -g)" \
		-e HOME=/tmp \
		"$@"
}

if [ "$variant" = all ]; then
	# Build against every base file the image ships, in a single container:
	# build-all.sh scans the image's kernel base directory and runs make once
	# per variant (see that script for the details). Any extra make args are
	# passed through to it.
	# shellcheck disable=SC2086
	run_in_image -e NEXTOR_KERNEL_BASE_DIR="$KERNEL_BASE_DIR" "$IMAGE" ./build-all.sh $makeargs
fi

# Single variant (or none). Without --variant the image's preset NEXTOR_BASE
# (the default kernel base) is used; with one, point NEXTOR_BASE at the matching
# base file.
envargs=
if [ -n "$variant" ]; then
	envargs="-e NEXTOR_BASE=$KERNEL_BASE_DIR/kernel_base.$variant.dat"
fi

# shellcheck disable=SC2086
run_in_image $envargs "$IMAGE" make $makeargs
