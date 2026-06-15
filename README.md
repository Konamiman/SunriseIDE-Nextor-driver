# Sunrise IDE driver for Nextor 3

This repository contains the Sunrise IDE hardware driver for [Nextor](https://github.com/Konamiman/Nextor). It produces a Nextor ROM image that combines a Nextor kernel (v3.0 or newer) base file with this driver, ready to be flashed to the Sunrise IDE cartridge or any compatible storage controller.

Four variants are built by default:

| Output                                   | Notes                                                       |
| ---------------------------------------- | ----------------------------------------------------------- |
| `Nextor-<ver>.SunriseIDE.ROM`                    | Master + slave, real hardware.                              |
| `Nextor-<ver>.SunriseIDE.MasterOnly.ROM`         | Master only, real hardware.                                 |
| `Nextor-<ver>.SunriseIDE.blueMSX.ROM`            | Master + slave, blueMSX emulator.  |
| `Nextor-<ver>.SunriseIDE.MasterOnly.blueMSX.ROM` | Master only, blueMSX emulator.                              |

`<ver>` and any kernel-base variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are picked up automatically from the `NEXTOR_BASE` filename, see [Building](#building) below.

The regular (not blueMSX specific) variant can be used in blueMSX too, but then only the slave device will be recognized.

## Repository contents

| File                | Purpose                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `driver.asm`        | The driver for real Sunrise IDE hardware.                                                |
| `driver-bluemsx.asm`| Variant of the driver to be used for the blueMSX emulator.                               |
| `chgbnk.asm`        | Bank switching routine specific to the Sunrise IDE cartridge mapper.                     |
| `Makefile`          | Build rules; see below.                                                                  |
| `docker-build.sh`   | Wrapper that builds the ROMs in the Nextor dev Docker image (no local toolchain needed). |
| `external/Nextor`   | Git submodule pointing at the Nextor repo, sparse-checkout to the `sdk/` directory only. |

## Development environment

The quickest path needs **nothing but Docker**: see [Building with the Nextor dev Docker image](#building-with-the-nextor-dev-docker-image) below, which supplies the toolchain, the SDK and the kernel base files for you (no submodule or base file to fetch). To build with a local toolchain instead, you need:

- [**Nestor80**](https://github.com/Konamiman/Nestor80) (`N80`) on your `PATH`, or pointed at via the `N80` make variable.
- **`mknexrom`** on your `PATH`, or pointed at via the `MKNEXROM` make variable. The source lives in the Nextor repository under `buildtools/sources/mknexrom.c`.
- A POSIX **`make`** and `dd` / `cat` (for the blueMSX variants).
- A Nextor kernel base file and the Nextor SDK (the `external/Nextor` submodule, set up with `make setup`).

## Cloning the repository

This repository uses a git submodule to pull in the Nextor SDK; clone with `--recurse-submodules` and then configure the submodule for a sparse checkout of the `sdk/` directory (the only thing this driver consumes from Nextor):

```sh
git clone --recurse-submodules https://github.com/Konamiman/SunriseIDE-Nextor-driver.git [<target-dir>]
cd <target-dir>/external/Nextor
git sparse-checkout init --cone
git sparse-checkout set sdk
cd ../..
```

If you already cloned without `--recurse-submodules`, run `git submodule update --init` first.

If you have a local clone of Nextor and want the submodule to point at it (e.g. while developing the SDK locally), override the URL once:

```sh
git config submodule.external/Nextor.url /path/to/your/local/Nextor
git submodule sync
git submodule update --init
```

### If you'd rather not fetch the full Nextor repository

The sequence above clones the entire Nextor repository before the sparse-checkout limits the working tree. If you'd rather only fetch the SDK files (typically <100 KB instead of tens of MB), clone the driver *without* `--recurse-submodules` and then set up the submodule as a blobless partial clone with sparse-checkout from the start:

```sh
git clone https://github.com/Konamiman/SunriseIDE-Nextor-driver.git [<target-dir>]
cd <target-dir>
git submodule init external/Nextor
git submodule update --init --filter=blob:none external/Nextor
git -C external/Nextor sparse-checkout init --cone
git -C external/Nextor sparse-checkout set sdk
git -C external/Nextor checkout
```

...or, equivalently, just `make setup`:

```sh
git clone https://github.com/Konamiman/SunriseIDE-Nextor-driver.git [<target-dir>]
cd <target-dir>
make setup
```

## Building

There are two ways to build: with the **Nextor dev Docker image** (no local toolchain, SDK or kernel base file needed) or with a **local toolchain**.

### Building with the Nextor dev Docker image

The [`nextor-dev`](https://github.com/Konamiman/Nextor/pkgs/container/nextor-dev) image bundles `N80`, `mknexrom`, the Nextor SDK and all six kernel base-file variants, and presets `NEXTOR_BASE` / `NEXTOR_SDK`, so a build needs nothing else on your machine - not even the `external/Nextor` submodule. The `docker-build.sh` wrapper runs the build in a container, mounting this repository and writing the ROMs into `bin/` owned by you (not root):

```sh
./docker-build.sh                       # all four ROMs, default kernel base
./docker-build.sh --variant NO_UNDOC    # build against the NO_UNDOC kernel base
./docker-build.sh --variant CTRL_INV
./docker-build.sh --variant NO_UNDOC.SHIFT_INV
./docker-build.sh clean                 # any extra args are passed to make
```

`--variant <suffix>` selects one of the image's kernel base files (`kernel_base<suffix>.dat`); the available suffixes are `NO_UNDOC`, `SHIFT_INV`, `CTRL_INV`, `NO_UNDOC.SHIFT_INV` and `NO_UNDOC.CTRL_INV`. A `*NO_UNDOC*` variant also assembles the driver undoc-free automatically, and the variant suffix is reflected in the output ROM names exactly as with a local build. Run `./docker-build.sh --help` for the full list.

> **Image tag during the 3.0 beta.** The wrapper defaults to the `:latest` image tag, but while Nextor 3.0 is still in pre-release **no `latest` tag exists yet**: pass the explicit tag (or set `NEXTOR_IMAGE`) until 3.0 is released:
>
> ```sh
> ./docker-build.sh --image ghcr.io/konamiman/nextor-dev:3.0.0-beta1
> # or: export NEXTOR_IMAGE=ghcr.io/konamiman/nextor-dev:3.0.0-beta1
> ```

### Building with a local toolchain

The build needs a Nextor kernel base file, supplied via `NEXTOR_BASE`:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.dat make
```

That produces all four ROM variants in the current directory.

For an undoc-instruction-free build (compatible with Z180-based MSX machines), pair an undoc-free kernel base with the matching driver-side flag:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.NO_UNDOC.dat \
NO_UNDOC_CPU_INSTRUCTIONS=1 \
make
```

The Nextor base filename's version and variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are mirrored in the output ROM filenames. **You are responsible for keeping `NO_UNDOC_CPU_INSTRUCTIONS` consistent with the base file's variant**: the Makefile does not infer it for you.

### Building without `make`

The Makefile is the recommended way, but each ROM is produced by just three tool invocations: two `N80` calls (one for the driver, one for the bank-switching routine) and one `mknexrom` call that combines them with the kernel base. If you'd rather drive them by hand, here's the sequence for the regular `Nextor-<ver>.SunriseIDE.ROM`:

```sh
mkdir -p tmp

# Assemble the driver  ->  tmp/driver.bin
N80 driver.asm tmp/ \
    --no-string-escapes --build-type abs --output-file-extension bin \
    --include-directory external/Nextor/sdk

# Assemble the bank-switching routine  ->  tmp/chgbnk.bin
N80 chgbnk.asm tmp/ \
    --no-string-escapes --build-type abs --output-file-extension bin \
    --include-directory external/Nextor/sdk

# Combine kernel base + driver + chgbnk  ->  Nextor-<ver>.SunriseIDE.ROM
mknexrom /path/to/Nextor-<ver>.base.dat Nextor-<ver>.SunriseIDE.ROM \
    /d:tmp/driver.bin /m:tmp/chgbnk.bin
```

The other three variants are slight modifications of the same recipe:

- **MasterOnly**: add `--define-symbols MASTER_ONLY` to the `N80 driver.asm` call and direct the output to a distinct filename (e.g. `tmp/driver.masteronly.bin`). Pass that filename to `mknexrom` and pick the matching `Nextor-<ver>.SunriseIDE.MasterOnly.ROM` output name.
- **blueMSX**: assemble `driver-bluemsx.asm` instead of `driver.asm`, then prepend a 256-byte zero block to the resulting `.bin` before handing it to `mknexrom`:
  ```sh
  dd if=/dev/zero bs=1 count=256 of=tmp/256.bytes
  cat tmp/256.bytes tmp/driver-bluemsx.bin > tmp/padded.bin
  mknexrom /path/to/Nextor-<ver>.base.dat Nextor-<ver>.SunriseIDE.blueMSX.ROM \
      /d:tmp/padded.bin /m:tmp/chgbnk.bin
  ```
  Combine with `MASTER_ONLY` if you want the MasterOnly blueMSX variant.
- **NO_UNDOC**: add `--define-symbols NO_UNDOC_CPU_INSTRUCTIONS` to *every* `N80` call (regardless of which variant you're building), and use a `Nextor-<ver>.base.NO_UNDOC.dat` kernel base. The driver-side and base-side undoc settings must match.

## Make variables

| Variable                    | Purpose                                                              | Default                |
| --------------------------- | -------------------------------------------------------------------- | ---------------------- |
| `NEXTOR_BASE`               | Path to the Nextor kernel base `.dat` file (mandatory).              | _(unset; error)_       |
| `NEXTOR_SDK`                | Path to the Nextor SDK directory (the one containing `asm/`).        | `external/Nextor/sdk`  |
| `N80`                       | Path to the Nestor80 assembler.                                      | `N80` (from `PATH`)    |
| `MKNEXROM`                  | Path to the `mknexrom` tool.                                         | `mknexrom` (from `PATH`) |
| `NO_UNDOC_CPU_INSTRUCTIONS` | If set (e.g. `=1`), assemble the driver without undocumented opcodes. | _(unset)_              |

Cleanup targets:

| Target           | Effect                                                                  |
| ---------------- | ----------------------------------------------------------------------- |
| `make clean`     | Removes `tmp/` (intermediate `.bin` files and helper artifacts). `bin/` and the shippable ROMs in it are kept. |
| `make clean-bin` | Removes `bin/` (the shippable ROMs).                                    |
| `make distclean` | Removes both `tmp/` and `bin/`.                                         |

## License

MIT - see [LICENSE](LICENSE). Note that [Nextor itself has a different license](https://github.com/Konamiman/Nextor/blob/v3.0/LICENSE.md).

