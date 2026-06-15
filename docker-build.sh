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
#   all                 build against every one of the above, in one container
# Selecting a *.NO_UNDOC.* variant also turns on NO_UNDOC_CPU_INSTRUCTIONS so
# the driver is assembled undoc-free to match.
#
# The image is pulled automatically on first use. Override it with --image or
# the NEXTOR_IMAGE environment variable.
set -eu

# Print the leading comment block (everything from line 2 up to, but not
# including, the first non-comment line) as help text.
usage() { sed -n '2,/^[^#]/p' "$0" | sed '/^[^#]/d; s/^#\{1,\} \{0,1\}//; s/^#$//'; }

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
	# Build against every base variant the image ships, in a single container.
	# Non-undoc variants are ordered first so the driver is reassembled
	# undoc-free only once (when crossing into the NO_UNDOC group) rather than
	# for every variant. Each base/undoc pair is passed to make on the command
	# line; the build-flag stamp in the Makefile reassembles when undoc changes.
	# Any extra make args reach the loop as "$@" via the trailing `sh ...`.
	# shellcheck disable=SC2086
	run_in_image "$IMAGE" sh -c '
set -e
for v in "" SHIFT_INV CTRL_INV NO_UNDOC NO_UNDOC.SHIFT_INV NO_UNDOC.CTRL_INV; do
	if [ -z "$v" ]; then
		base=/opt/nextor/kernel_base/kernel_base.dat; undoc=
	else
		base=/opt/nextor/kernel_base/kernel_base.$v.dat
		case $v in *NO_UNDOC*) undoc=NO_UNDOC_CPU_INSTRUCTIONS=1 ;; *) undoc= ;; esac
	fi
	echo ">>> Building variant: ${v:-default}"
	make NEXTOR_BASE="$base" $undoc "$@"
done
' sh $makeargs
fi

# Single variant (or none). Without --variant the image's preset NEXTOR_BASE
# (the default kernel base) is used; with one, point NEXTOR_BASE at the matching
# base file and, for the undoc-free variants, assemble the driver undoc-free.
envargs=
if [ -n "$variant" ]; then
	envargs="-e NEXTOR_BASE=$KERNEL_BASE_DIR/kernel_base.$variant.dat"
	case "$variant" in
		*NO_UNDOC*) envargs="$envargs -e NO_UNDOC_CPU_INSTRUCTIONS=1" ;;
	esac
fi

# shellcheck disable=SC2086
run_in_image $envargs "$IMAGE" make $makeargs
