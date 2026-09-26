# Build scripts

This folder contains helper PowerShell scripts to build the project in two ways and copy run-ready artifacts into the `artifacts/` folder.

Scripts

- `build_shared.ps1` — Configure and build a shared (DLL) build.
  - Configures with `-DBUILD_SHARED_LIBS=ON` into `build_x64_shared` by default.
  - Builds `lzhamdll` and `lzhamtest` targets.
  - Copies `lzhamtest.exe` and `lzhamdll.dll` (if produced) into the `artifacts/` directory.

- `build_static.ps1` — Configure and build a static build.
  - Configures with `-DBUILD_SHARED_LIBS=OFF` into `build_x64_static` by default.
  - Builds `lzhamtest` (statically linked) and copies it into `artifacts/`.
  - If `artifacts/lzhamtest.exe` already exists (for example produced by the shared build), the static EXE will be copied as `artifacts/lzhamtest_static.exe` so both can coexist.

Usage

From the repository root (PowerShell):

```powershell
# Build shared (DLL) copy
.\scripts\build_shared.ps1

## scripts/ — Build & test helper scripts

This README documents the helper scripts in the `scripts/` directory and the common flags they accept. The scripts are PowerShell-based and intended to be run from the repository root using PowerShell on Windows.

### Top-level scripts

- `build.sh` — All-in-one build script for Linux (bash). Wraps the whole flow: toolchain checks, CMake configure, build, artifact staging, smoke test, optional install.
  - Builds `lzhamtest` from static libraries (`-DBUILD_SHARED_LIBS=OFF`), which is the only configuration that builds on Linux — the `lzham_dynamic_lib.h` loader is Win32-only.
  - Stages run-ready artifacts into `artifacts/linux/{dynamic,static}/{bin,lib,include}` and keeps build logs under `build/linux/<variant>/logs/`.
  - Smoke-tests the result by round-tripping `tests/hello_world.txt` through both the file and the stdin/stdout streaming (`-S`) paths; with `--shared` it also `dlopen`s the built `.so` and round-trips data through its zlib-compatible API.
  - Flags:
    - `-c, --config <Release|Debug|RelWithDebInfo|MinSizeRel>` (default: Release)
    - `-s`, `-static`, `--static` — link the binary fully statically (`-static`); probes for a static libc first
    - `-S`, `--shared` — also build the unified shared library (`liblzham_x64.so`) exposing the public C API; enables `CMAKE_POSITION_INDEPENDENT_CODE` so the static archives can go into a `.so`
    - `-j, --jobs <n>`, `-B, --build-dir <dir>`, `-o, --output <dir>`, `-t, --target <name>` (repeatable)
    - `-i, --install [prefix]` — install headers, libraries and the binary (default prefix `/usr/local`)
    - `--no-stage`, `--no-test`, `--strip`, `--clean`, `--clean-all`, `--cc <compiler>`, `--verbose`, `-h`
  - Examples:
    ```bash
    ./scripts/build.sh -j "$(nproc)"          # dynamic binary + static libs
    ./scripts/build.sh -static -c Release      # fully static binary
    ./scripts/build.sh --shared                # also produce liblzham_x64.so
    ./scripts/build.sh --clean -i ~/.local     # from scratch, then install
    ```

- `build_all_artifacts.ps1` — Wrapper that builds all three variants (static, unified, modular). Key behavior and flags:
  - Runs an initial cleanup and log cleanup (unless suppressed).
  - Builds `static`, `unified`, and `shared/modular` variants (in parallel by default).
  - Produces artifacts under `artifacts\{static,unified,modular}` and writes per-build logs to `logs/` at the repository root.
  - After building, it can run the create/decompress/verify test flow (unless `-NoRunTests` or `-SkipVerify` is passed).
  - Useful flags:
    - `-Config <Debug|Release>` (default: Release)
    - `-Arch <x86|x64>` (default: x64)
    - `-NoParallel` — run builds sequentially (default is parallel jobs)
    - `-NoCleanupLog` — skip initial log cleanup
    - `-NoCleanupTests` — skip truncating `./tests` before the run
    - `-NoRunTests` — skip create/decompress steps (wrapper will still run verification unless `-SkipVerify` is also set)
    - `-SkipVerify` — skip verification entirely
    - `-CleanBuildDirs` / `-CleanBuildDirsAll` — remove build directories (or discover them across the repo)
    - `-DryRun` — where supported, show actions without performing them

- `build_static.ps1` — Configure and build the static variant (produces `artifacts/static/lzhamtest.exe`).
  - Configures with `-DBUILD_SHARED_LIBS=OFF` by default.
  - Copies the built `lzhamtest.exe` into `artifacts/static`.
  - Flags (common to build scripts):
    - `-BuildDir` (default: `build_x64_static`)
    - `-Config`, `-Arch`, `-ArtifactsDir`
    - `-NoCleanup` — skip `cleanup_artifacts.ps1`
    - `-NoCleanupLog`, `-NoCleanupTests`, `-NoRunTests` — control test/log cleanup and running
    - `-CleanBuildDirs` / `-CleanBuildDirsAll` / `-DryRun`

- `build_unified.ps1` — Configure and build a unified (DLL wrapper) layout and `lzhamtest`.
  - Uses `-DBUILD_LZHAMDLL_SHARED=ON` to build a unified DLL; static sub-libraries are produced for internal code.
  - Outputs live in `artifacts/unified`.

- `build_shared.ps1` — Configure and build the shared/modular layout (produces `artifacts/modular`).
  - Configures with `-DBUILD_SHARED_LIBS=ON` by default and copies produced DLLs and the `lzhamtest.exe` into `artifacts/modular`.

### Utility & test scripts

- `CleanBuildDirs.ps1` — Centralized helper to remove build directories. Supports passing a list of directories or using `-All` to discover `build_*` directories across the repo.
  - Supports `-DryRun` and `ShouldProcess`/`WhatIf` semantics. Preserves files matching `*_original.*`.

- `cleanup_artifacts.ps1` — Remove build-time artifacts (EXEs, DLLs) while preserving `*_original.*` files.

- `cleanup_logs.ps1` — Remove old log, .tmp, and .bak files under the repo `logs/` directory (and across the repo).

- `cleanup_tests.ps1` — Truncate the `./tests/` folder while preserving any `*_original.*` files and `hello_world.txt`. Supports `-DryRun` and `ShouldProcess`.

- `cleanup_pdbs.ps1` — Remove .pdb (debug symbol) files across the repository while preserving any `*_original.*` files.
  - Supports `-DryRun` and `ShouldProcess`/`-WhatIf` semantics. Useful when cleaning up developer-only symbol files before packaging.
  - Note: If you want to retain symbols for debugging, consider moving them to an `artifacts/symbols/` folder instead of deleting them.

- `cleanup_obj.ps1` — Remove compiled object files (`*.o`, `*.obj`) across the repository while preserving any `*_original.*` files.
  - Supports `-DryRun` and `ShouldProcess`/`-WhatIf` semantics. Useful to remove intermediate build artifacts before packaging or creating a clean source snapshot.
  - The `cleanup_all.ps1` wrapper now accepts `-PreserveObj` to skip object file cleanup when desired.

- `cleanup_cmake.ps1` — Remove CMake-generated files (`CMakeCache.txt`, `cmake_install.cmake`, and `CMakeFiles/`) found outside build directories.
  - Supports `-DryRun` and `ShouldProcess`/`-WhatIf` semantics.
  - By default the script targets CMake artifacts outside `build_*` directories. If you need to also remove CMake artifacts inside build dirs, consider running `CleanBuildDirs.ps1` or adjust the script flags.
  - The `cleanup_all.ps1` wrapper accepts `-PreserveCMake` to skip this step when needed.


- `cleanup_all.ps1` — Convenience wrapper that runs the repository cleanup helpers in order:
  1. `CleanBuildDirs.ps1` (discover/remove common `build_*` dirs or use `-All`)
  2. `cleanup_artifacts.ps1` (removes `.exe`/`.dll` unless `-KeepArtifacts` is specified)
  3. `cleanup_logs.ps1` (removes `.log`/`.tmp`/`.bak` files)
  4. `cleanup_tests.ps1` (truncates `./tests` preserving originals)
  - Flags:
    - `-All` — discover `build_*` directories and remove them
    - `-DryRun` — show actions without performing removals (where supported)
    - `-KeepArtifacts` — skip the `cleanup_artifacts.ps1` step (preserve built binaries)
  - Example:
    ```powershell
    # Dry-run discovery and all cleanup steps
    .\scripts\cleanup_all.ps1 -All -DryRun

    # Real run, but keep compiled artifacts
    .\scripts\cleanup_all.ps1 -All -KeepArtifacts
    ```

- `create_archives.ps1` — Create test archives (`.lzh`) from available `lzhamtest.exe` artifacts using the canonical `tests/hello_world.txt` sample.

- `decompress_archives.ps1` — Decompress `tests/*.lzh` archives using available `lzhamtest.exe` artifacts and compare the extracted bytes to `tests/hello_world.txt` (MD5 comparison by default).

- `verify_artifacts.ps1` — CI-oriented verification script that decompresses archives with each produced artifact and compares the SHA256 of decompressed output to the canonical sample. Returns non-zero on verification failure.

- `compress_upx.ps1` — Run UPX (--best) over produced artifacts under `./artifacts/`.
  - Behavior:
    - Prompts for the path to `upx.exe` (press Enter to use `upx` on PATH).
    - Recursively discovers `*.dll` and `*.exe` files under `./artifacts/` and skips any file whose name contains `_original.`.
    - By default runs UPX in parallel across discovered files (uses `Start-Job`). Pass `-NoParallel` to run sequentially.
  - `-Backup` — create a copy of each target named `<name>_original.<ext>` before compressing; helps preserve uncompressed binaries.
    - Prints per-file UPX output and a summary showing which files were compressed or skipped.
  - Examples:
    ```powershell
    # Run UPX in parallel (default)
    .\scripts\compress_upx.ps1

    # Run UPX sequentially
    .\scripts\compress_upx.ps1 -NoParallel
    ```
    ```powershell
    # Run UPX sequentially and create backups before compressing
    .\scripts\compress_upx.ps1 -NoParallel -Backup -UpxPath 'C:\tools\upx\upx.exe'
    ```
  - Notes:
    - The script will skip files containing `_original.` to avoid touching preserved copies. If you'd like backups before compressing, consider copying originals to `*_original.*` yourself or request an enhancement to the script to add a `-Backup` switch.
  - UPX information (displayed by the script):
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                        Ultimate Packer for eXecutables
                          Copyright (C) 1996 - 2025
UPX 5.0.2       Markus Oberhumer, Laszlo Molnar & John Reiser   Jul 20th 2025
UPX comes with ABSOLUTELY NO WARRANTY; for details visit https://upx.github.io
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ```

- `run_stream_test.ps1` / `run_stream_debug.ps1` — Helpers to exercise the streaming (stdin/stdout) test harness paths for compression/decompression with additional logging/debugging.

- `compare_bytes.ps1` — Utility to compare byte sequences or file outputs (used by some test helpers).

- `hexdump.py` — Small Python hexdump utility used by some debug helpers.

### Notes and recommendations

- Most build scripts call `cmake` and `cmake --build`; ensure CMake and a suitable MSVC toolchain are available on your PATH when running them.
- The wrapper `build_all_artifacts.ps1` is the recommended entry point for CI-style runs — it centralizes cleanup, runs builds (parallel by default), creates test archives, decompresses them centrally, and runs verification.
- Use `-NoRunTests` when you want to skip the archive create/decompress steps (for example, when running the wrapper in an environment that already has archives prepared). Use `-SkipVerify` to skip invoking `verify_artifacts.ps1` entirely.
- `CleanBuildDirs.ps1 -All` is helpful to discover and remove stale `build_*` directories created during iterative development.

### Examples

Run a full, parallel build with verification:

```powershell
.\scripts\build_all_artifacts.ps1 -Config Release -Arch x64
```

Run the wrapper but skip running test archive creation/decompression (still runs verification unless `-SkipVerify` is passed):

```powershell
.\scripts\build_all_artifacts.ps1 -NoRunTests
```

Run a single static build without truncating `tests/` and without creating archives:

```powershell
.\scripts\build_static.ps1 -NoCleanupTests -NoRunTests
```

If you need a compatibility shim for an old filename (`cleanuptests.ps1`), consider adding a tiny forwarding script that calls `cleanup_tests.ps1`. The repository now uses `cleanup_tests.ps1` as the canonical name.

If you'd like, I can also:

- Add a short `scripts/USAGE.md` with copy-paste commands for CI pipelines.
- Add a compatibility shim file `cleanuptests.ps1` that forwards to `cleanup_tests.ps1`.

If you'd like any of those, tell me which and I'll add them.
