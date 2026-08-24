#!/bin/sh
# build-all.sh - build the Sunrise IDE driver ROMs against every Nextor kernel
# base-file variant found in a directory, with the local toolchain (N80,
# mknexrom, make and the SDK submodule; see README). To do the same with no
# local toolchain, use `docker-build.sh --variant all`, which runs this script
# inside the Nextor dev Docker image.
#
# Usage:
#   NEXTOR_KERNEL_BASE_DIR=<dir> ./build-all.sh [make args...]
#
#   NEXTOR_KERNEL_BASE_DIR=~/Nextor/bin/kernel-base ./build-all.sh
#   NEXTOR_KERNEL_BASE_DIR=~/Nextor/bin/kernel-base ./build-all.sh clean-bin all
#   NEXTOR_KERNEL_BASE_DIR=/opt/nextor/kernel_base ./build-all.sh   # in the image
#
# NEXTOR_KERNEL_BASE_DIR (mandatory) is the directory holding the kernel base
# files. No list of variants is needed: the directory is scanned, and every
# .dat file there named by one of the two conventions the Makefile understands
# is a variant to build against:
#
#   Nextor-<ver>.base[<suffix>].dat    as built by the Nextor repository
#   kernel_base[<suffix>].dat          as shipped in the Nextor dev image
#
# <suffix> is empty for the default base and e.g. .NO_UNDOC, .SHIFT_INV,
# .NO_UNDOC.CTRL_INV.KANJI_INV otherwise; it ends up in the ROM names, and for
# the *NO_UNDOC* bases makes the Makefile assemble the driver undoc-free to
# match, exactly as with a plain `make`.
#
# If the directory holds base files for more than one kernel version (e.g.
# leftovers from an earlier build), the ones for the version the SDK reports
# (NEXTOR_SDK/nextor-kernel-version.txt, which is the version the ROMs are
# named after) are used; if none match, the script stops and asks you to sort
# it out rather than guessing.
#
# Any arguments are passed through to make (targets, variable overrides), on
# top of the NEXTOR_BASE set for each variant. The NEXTOR_SDK, N80, MKNEXROM
# and MAKE environment variables are honoured. NEXTOR_BASE= and NEXTOR_SDK=
# assignments are rejected as arguments: the former is chosen per variant by
# this script, and the latter must come as an environment variable so that
# the variant selection (see below) uses it too.
set -eu

# Print the leading comment block (everything from line 2 up to, but not
# including, the first non-comment line) as help text.
usage() { sed -n '2,/^[^#]/p' "$0" | sed '/^[^#]/d; s/^#\{1,\} \{0,1\}//; s/^#$//'; }

die() { echo "build-all.sh: $*" >&2; exit 1; }

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# The pass-through args reach make after this script's own per-variant
# NEXTOR_BASE assignment, and in make the last command-line assignment wins:
# a forwarded NEXTOR_BASE would silently override the base for every variant,
# and a forwarded NEXTOR_SDK would steer make but not the family selection
# below. Reject the two variables this script manages; everything else
# (targets, other variable overrides) passes through untouched.
for arg do
	case $arg in
		NEXTOR_BASE=*) die "NEXTOR_BASE is chosen per variant by this script; point NEXTOR_KERNEL_BASE_DIR at the directory holding the base files instead" ;;
		NEXTOR_SDK=*)  die "pass NEXTOR_SDK as an environment variable (NEXTOR_SDK=<dir> $0 ...), not as a make argument, so that the variant selection uses it too" ;;
	esac
done

[ -n "${NEXTOR_KERNEL_BASE_DIR:-}" ] || die "NEXTOR_KERNEL_BASE_DIR is not set. Point it at the directory holding the kernel base files (run with --help for details)"
[ -d "$NEXTOR_KERNEL_BASE_DIR" ] || die "NEXTOR_KERNEL_BASE_DIR points at '$NEXTOR_KERNEL_BASE_DIR' which is not a directory"

# Make the base directory absolute, then run from the repository root (the
# script's own directory) so make finds the Makefile regardless of the
# caller's current directory.
base_dir=$(CDPATH= cd -- "$NEXTOR_KERNEL_BASE_DIR" && pwd)
cd -- "$(dirname -- "$0")"

MAKE="${MAKE:-make}"


### Scan the directory ########################################################

# Split every recognized base filename into a "family" (everything up to and
# including the 'base' token: 'Nextor-3.0.0.base' or 'kernel_base') and a
# variant suffix (what follows; 'default' stands in for the empty suffix of
# the default base so the lists below can be plain space-separated words).
families=
pairs=   # one 'family suffix' pair per line
for f in "$base_dir"/*.dat; do
	[ -e "$f" ] || break
	stem=${f##*/}; stem=${stem%.dat}
	case $stem in
		kernel_base|Nextor-*.base)     family=$stem ;;
		kernel_base.*|Nextor-*.base.*) family=${stem%%base.*}base ;;
		*)                             continue ;;
	esac
	suffix=${stem#"$family"}; suffix=${suffix#.}
	case " $families " in *" $family "*) ;; *) families="$families $family" ;; esac
	pairs="$pairs
$family ${suffix:-default}"
done

nfamilies=0
for family in $families; do nfamilies=$((nfamilies + 1)); done
[ "$nfamilies" -gt 0 ] || die "no kernel base files (kernel_base*.dat or Nextor-*.base*.dat) found in $base_dir"

# With a single family the loop above has left it in $family and we're done.
# More than one family means base files from more than one kernel version are
# mixed in the directory: use the family for the version the SDK reports (the
# Makefile names the ROMs after it), and give up if there is none.
if [ "$nfamilies" -gt 1 ]; then
	listed=$(echo $families | sed 's/ /, /g')
	# A relative NEXTOR_SDK resolves against the repository root (we cd'd there
	# above), which is also how make itself resolves it.
	sdk_version_file="${NEXTOR_SDK:-external/Nextor/sdk}/nextor-kernel-version.txt"
	sdk_version=$(cat "$sdk_version_file" 2>/dev/null || true)
	[ -n "$sdk_version" ] || die "$base_dir holds base files for several kernel versions ($listed) and the SDK's version could not be read from $sdk_version_file to pick one. Fix the SDK (see 'make setup'), or point NEXTOR_KERNEL_BASE_DIR at a directory with a single version"
	wanted="Nextor-$sdk_version.base"
	case " $families " in
		*" $wanted "*) echo "Note: $base_dir holds base files for several kernel versions ($listed); using ${wanted}[.<suffix>].dat, the SDK's version." ;;
		*) die "$base_dir holds base files for several kernel versions ($listed) and none is the SDK's ($wanted). Remove the stale ones, or point NEXTOR_KERNEL_BASE_DIR at a directory with a single version" ;;
	esac
	family=$wanted
fi


### Order the variants ########################################################

# The Makefile assembles the driver differently for the undoc-free (*NO_UNDOC*)
# bases, and its build-flag stamp reassembles it whenever that changes;
# building all the regular bases first and all the undoc-free ones last keeps
# that to a single reassembly instead of one per variant. Within each group
# the default base (if present) goes first, for readability.
regular=; undoc=
while read -r pair_family suffix; do
	[ "$pair_family" = "$family" ] || continue
	case $suffix in
		default)    regular="$suffix $regular" ;;
		*NO_UNDOC*) undoc="$undoc $suffix" ;;
		*)          regular="$regular $suffix" ;;
	esac
done <<EOF
$pairs
EOF
# shellcheck disable=SC2086
variants=$(echo $regular $undoc)  # (unquoted on purpose: normalizes the spacing)


### Build ####################################################################

n=0; for v in $variants; do n=$((n + 1)); done
echo "Building against $n kernel base variant(s) from $base_dir: $(echo "$variants" | sed 's/default/(default)/')"

for v in $variants; do
	if [ "$v" = default ]; then
		base="$base_dir/$family.dat"
	else
		base="$base_dir/$family.$v.dat"
	fi
	echo ">>> Building variant: $v"
	"$MAKE" NEXTOR_BASE="$base" "$@"
done
