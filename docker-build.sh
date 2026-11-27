#!/bin/sh
# docker-build.sh - build the Sunrise IDE driver ROMs using the Nextor dev
# Docker image, with no local toolchain, SDK submodule or kernel base file
# needed: the image supplies N80, mknexrom, the Nextor SDK and the kernel base
# file, and presets NEXTOR_BASE / NEXTOR_SDK so plain `make` inside it just
# works.
#
# Usage:
#   ./docker-build.sh [--image <ref>] [make args...]
#
#   ./docker-build.sh                           # all four ROMs
#   ./docker-build.sh clean                     # pass-through make targets
#   ./docker-build.sh --image <ref> distclean all
#
# The driver doesn't use undocumented Z80 instructions, and it's combined with
# a kernel base that doesn't use them either. Images built after Nextor PR
# #286 ship that as their only base file, kernel_base.dat; older images (up to
# and including 3.0.0-r2) ship it as kernel_base.NO_UNDOC.dat next to a default
# kernel_base.dat that does use them, so when the image has a .NO_UNDOC base
# file, that's the one used.
#
# The image is pulled automatically on first use. Override it with --image or
# the NEXTOR_IMAGE environment variable. The default is pinned to the kernel
# version this driver is built for (the image's `latest` tag only tracks
# stable kernel releases, so it is not suitable while targeting a prerelease).
set -eu

# Print the leading comment block (everything from line 2 up to, but not
# including, the first non-comment line) as help text.
usage() { sed -n '2,/^[^#]/p' "$0" | sed '/^[^#]/d; s/^#\{1,\} \{0,1\}//; s/^#$//'; }

IMAGE="${NEXTOR_IMAGE:-ghcr.io/konamiman/nextor-dev:3.0.0}"
makeargs=

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)    usage; exit 0 ;;
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

# Inside the container: use the .NO_UNDOC base file if the image has one (see
# above), otherwise the image's preset NEXTOR_BASE; then run make with the
# remaining arguments.
# shellcheck disable=SC2016,SC2086
exec docker run --rm \
	-v "$repo_root":/work \
	-w /work \
	--user "$(id -u):$(id -g)" \
	-e HOME=/tmp \
	"$IMAGE" \
	sh -c '
		no_undoc_base="${NEXTOR_KERNEL_BASE_DIR:-/opt/nextor/kernel_base}/kernel_base.NO_UNDOC.dat"
		if [ -e "$no_undoc_base" ]; then
			export NEXTOR_BASE="$no_undoc_base"
		fi
		exec make "$@"
	' sh $makeargs
