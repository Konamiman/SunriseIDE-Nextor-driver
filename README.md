# Sunrise IDE driver for Nextor 3

This repository contains the Sunrise IDE hardware driver for [Nextor](https://github.com/Konamiman/Nextor) 3.x. It produces a Nextor ROM image that combines a Nextor kernel base file with this driver, ready to be flashed to the Sunrise IDE cartridge.

Four variants are built by default:

| Output                                   | Notes                                                       |
| ---------------------------------------- | ----------------------------------------------------------- |
| `Nextor-<ver>.SunriseIDE.ROM`                    | Master + slave, real hardware.                              |
| `Nextor-<ver>.SunriseIDE.MasterOnly.ROM`         | Master only, real hardware.                                 |
| `Nextor-<ver>.SunriseIDE.blueMSX.ROM`            | Master + slave, blueMSX emulator (driver image is padded).  |
| `Nextor-<ver>.SunriseIDE.MasterOnly.blueMSX.ROM` | Master only, blueMSX emulator.                              |

`<ver>` and any kernel-base variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are picked up automatically from the `NEXTOR_BASE` filename — see [Building](#building) below.

## Repository contents

| File                | Purpose                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `driver.asm`        | The driver for real Sunrise IDE hardware.                                                |
| `driver-bluemsx.asm`| Variant of the driver used inside the blueMSX emulator.                                  |
| `chgbnk.asm`        | Bank-switching routine specific to the Sunrise IDE cartridge mapper.                     |
| `Makefile`          | Build rules; see below.                                                                  |
| `external/Nextor`   | Git submodule pointing at the Nextor repo, sparse-checkout to the `sdk/` directory only. |

## Development environment

You need:

- [**Nestor80**](https://github.com/Konamiman/Nestor80) (`N80`) on your `PATH`, or pointed at via the `N80` make variable.
- **`mknexrom`** on your `PATH`, or pointed at via the `MKNEXROM` make variable. The source lives in the Nextor repository under `buildtools/sources/mknexrom.c`.
- A POSIX **`make`** and `dd` / `cat` (for the blueMSX variants).

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

The sequence above clones the entire Nextor repository before the sparse-checkout limits the working tree. If you'd rather only fetch the SDK objects (typically <100 KB instead of tens of MB), clone the driver *without* `--recurse-submodules` and then set up the submodule as a blobless partial clone with sparse-checkout from the start:

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

The Nextor base filename's version and variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are mirrored in the output ROM filenames. **You are responsible for keeping `NO_UNDOC_CPU_INSTRUCTIONS` consistent with the base file's variant** — the Makefile does not infer it for you.

## Make variables

| Variable                    | Purpose                                                              | Default                |
| --------------------------- | -------------------------------------------------------------------- | ---------------------- |
| `NEXTOR_BASE`               | Path to the Nextor kernel base `.dat` file (mandatory).              | _(unset; error)_       |
| `NEXTOR_SDK`                | Path to the Nextor SDK directory (the one containing `asm/`).        | `external/Nextor/sdk`  |
| `N80`                       | Path to the Nestor80 assembler.                                      | `N80` (from `PATH`)    |
| `MKNEXROM`                  | Path to the `mknexrom` tool.                                         | `mknexrom` (from `PATH`) |
| `NO_UNDOC_CPU_INSTRUCTIONS` | If set (e.g. `=1`), assemble the driver without undocumented opcodes. | _(unset)_              |

`make clean` removes all build outputs.

## License

MIT — see [LICENSE](LICENSE).
