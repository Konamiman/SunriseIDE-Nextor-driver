# Adapt the build to Nextor 3.0.0 beta 1 final

Nextor 3.0.0 beta 1 is finished: the kernel now ships **twelve** base-file variants (the previous six, each with and without the new `KANJI_INV` boot key inversion), the final [`nextor-dev`](https://github.com/Konamiman/Nextor/pkgs/container/nextor-dev) Docker image and SDK are published, and the Nextor repository's `master` branch has been recreated from `v3.0`. This PR brings the driver build in line with all of that, and takes the opportunity to remove a piece of manual bookkeeping (the undoc flag) that the build can now handle by itself.

## Changes

### `docker-build.sh`: KANJI_INV variants and a pinned image tag

- `--variant all` builds against every base file the image ships: 12 variants × 4 ROMs = **48 ROMs** (was 24). The single-variant form accepts the new suffixes (`KANJI_INV`, `NO_UNDOC.CTRL_INV.KANJI_INV`, ...).
- The default image is now **`ghcr.io/konamiman/nextor-dev:3.0.0-beta1`** instead of `:latest`. The image's `latest` tag only tracks *stable* kernel releases (per the image's tag scheme), so it is never right while the driver targets a prerelease; in fact the `latest` currently on ghcr.io is an older build with only six base variants and older tools. Pinning to the kernel version also matches how the SDK submodule is pinned: bumping the kernel version is a deliberate change, done in one place (`NEXTOR_IMAGE` in the script and the CI workflow) together with the submodule pin. `--image` / `NEXTOR_IMAGE` still override it.

### New `build-all.sh`: every variant, with the local toolchain

The local counterpart of `docker-build.sh --variant all`:

```sh
NEXTOR_KERNEL_BASE_DIR=/path/to/Nextor/bin/kernel-base ./build-all.sh [make args...]
```

- **No list of variants to maintain.** The script scans `NEXTOR_KERNEL_BASE_DIR` and builds against every `.dat` file named by either convention the Makefile already understands (`Nextor-<ver>.base[<suffix>].dat` as built by the Nextor repository, `kernel_base[<suffix>].dat` as shipped in the image), running `make` once per base file. Whatever variants the kernel ships, it picks up.
- **Mixed kernel versions are handled.** A base directory can accumulate files from several versions (leftovers from earlier builds); in that case the script uses the family matching the version the SDK reports (`nextor-kernel-version.txt`, which is also what the ROMs are named after), and stops with a clear message if none matches, rather than silently building against stale files.
- **Builds are ordered** so all the regular bases go first and all the `*NO_UNDOC*` ones last: the Makefile's build-flag stamp reassembles the driver whenever the undoc setting changes, so this keeps it to a single reassembly instead of one per variant.
- `docker-build.sh --variant all` now simply runs this script inside the container (the image presets `NEXTOR_KERNEL_BASE_DIR`), so the variant-discovery logic lives in one place.

### Makefile: `NO_UNDOC_CPU_INSTRUCTIONS` is inferred from the base filename

Previously the user (and both scripts) had to set `NO_UNDOC_CPU_INSTRUCTIONS=1` whenever `NEXTOR_BASE` pointed at a `NO_UNDOC` base, and the README warned that the Makefile would not check the two were consistent. The Makefile now infers the flag from the `NEXTOR_BASE` variant suffix: set when it contains `NO_UNDOC`, unset otherwise, so the driver always matches the kernel it is combined with.

- An explicit value still wins in both directions: `NO_UNDOC_CPU_INSTRUCTIONS=1` forces an undoc-free driver on a regular base, and a deliberately empty `NO_UNDOC_CPU_INSTRUCTIONS= make` disables it on a `NO_UNDOC` base. This uses `$(origin ...)` rather than `?=` so that an empty explicit value counts as set.
- A base file with a non-standard name yields no variant suffix and hence no inference; the flag has to be set by hand in that case (documented).
- Both scripts lost their own `*NO_UNDOC*` special-casing as a result.

### CI: one `--variant all` build

The default/`NO_UNDOC` matrix is replaced by a single job that runs `docker-build.sh --variant all` and then checks that each of the 48 expected ROMs (12 base suffixes × 4 ROM kinds) exists and is non-empty, plus a total-count guard against strays. This exercises `build-all.sh` itself on every push. The uploaded artifact is now a single `sunrise-ide-roms` (the previous ones were `sunride-roms-<variant>`, typo included).

### Nextor `v3.0` → `master`

- `.gitmodules`: the submodule's tracked branch is now `master`.
- The `external/Nextor` pin is bumped to the current `master` tip. The SDK changes since the previous pin are additive (new `STR_*`, `DRIVER_EXTRA_AREA*` and `KBUF` constants, none clashing with the driver's symbols) plus the removal of the `.z80`/`name`/`title` headers from the include files.
- The README's Nextor license link pointed at the `v3.0` branch.

### README

Documents `build-all.sh`, the `KANJI_INV` variants (and the three axes the twelve suffixes combine), the image tag pinning, and the undoc inference. Two outdated statements are also fixed: the ROM version comes from the SDK's `nextor-kernel-version.txt`, not from the base filename (that changed with the Docker build support), and the ROMs are written to `bin/`, not the current directory.

## Notes

- `build-all.sh` is driver-agnostic apart from the name in its comments, and the Makefile inference is a self-contained block, so both should drop into the other Nextor driver repositories as-is.
