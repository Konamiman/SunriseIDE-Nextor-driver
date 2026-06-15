#!/bin/sh
# docker-build.sh - build the Sunrise IDE driver ROMs using the Nextor dev
# Docker image, with no local toolchain, SDK submodule or kernel base file
# needed: the image supplies N80, mknexrom, the Nextor SDK and all six kernel
# base-file variants, and presets NEXTOR_BASE / NEXTOR_SDK so plain `make`
# inside it just works.
#
# Usage:
#   ./docker-build.sh [--variant <suffix>] [--image <ref>] [make args...]
#
#   ./docker-build.sh                           # all ROMs, default kernel base
#   ./docker-build.sh --variant NO_UNDOC        # build against the NO_UNDOC base
#   ./docker-build.sh --variant CTRL_INV
#   ./docker-build.sh --variant NO_UNDOC.SHIFT_INV
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
# Selecting a *.NO_UNDOC.* variant also turns on NO_UNDOC_CPU_INSTRUCTIONS so
# the driver is assembled undoc-free to match.
#
# The image is pulled automatically on first use. Override it with --image or
# the NEXTOR_IMAGE environment variable.
set -eu

usage() { sed -n '2,30p' "$0" | sed 's/^#\{1,\} \{0,1\}//; s/^#$//'; }

IMAGE="${NEXTOR_IMAGE:-ghcr.io/konamiman/nextor-dev:latest}"
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

# Without --variant the image's preset NEXTOR_BASE (the default kernel base) is
# used. With one, point NEXTOR_BASE at the matching base file in the image and,
# for the undoc-free variants, assemble the driver undoc-free to match.
envargs=
if [ -n "$variant" ]; then
	envargs="-e NEXTOR_BASE=$KERNEL_BASE_DIR/kernel_base.$variant.dat"
	case "$variant" in
		*NO_UNDOC*) envargs="$envargs -e NO_UNDOC_CPU_INSTRUCTIONS=1" ;;
	esac
fi

# Mount the repository root (the script's own directory) at /work regardless of
# the caller's current directory, and run as the host user so the ROMs written
# to bin/ are owned by you, not root. HOME is set because Nestor80 (.NET) wants
# a writable home directory.
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# shellcheck disable=SC2086
exec docker run --rm \
	-v "$repo_root":/work \
	-w /work \
	--user "$(id -u):$(id -g)" \
	-e HOME=/tmp \
	$envargs \
	"$IMAGE" \
	make $makeargs
