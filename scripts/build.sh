#!/usr/bin/env bash
#
# build.sh - all-in-one Linux build script for the LZHAM codec.
#
# Wraps the whole flow in one place: verifies the toolchain, configures CMake,
# compiles, stages run-ready artifacts, smoke-tests the resulting binary and
# (optionally) installs it.
#
#   ./scripts/build.sh                        # dynamically linked binary + static libs
#   ./scripts/build.sh -static                # fully static binary, no shared deps
#   ./scripts/build.sh --shared               # also build the unified liblzham_x64.so
#   ./scripts/build.sh -c Debug -j 8          # debug build, 8 parallel jobs
#   ./scripts/build.sh --clean --install      # from scratch, then install to /usr/local
#
set -euo pipefail

# ---------------------------------------------------------------------------
# paths / constants
# ---------------------------------------------------------------------------

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
  SCRIPT_LINK="$(readlink "$SCRIPT_PATH")"
  case "$SCRIPT_LINK" in
    /*) SCRIPT_PATH="$SCRIPT_LINK" ;;
    *) SCRIPT_PATH="$(dirname "$SCRIPT_PATH")/$SCRIPT_LINK" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_SUBDIR="build/linux"
STAGE_SUBDIR="artifacts/linux"
TEST_SAMPLE="tests/hello_world.txt"

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
else
  C_RESET=''; C_BOLD=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''
fi

phase() { printf '\n%s==> %s%s\n' "${C_BOLD}${C_CYAN}" "$*" "${C_RESET}"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %sok%s  %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()  { printf '    %swarn%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
die()   { printf '\n%serror%s %s\n' "${C_BOLD}${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }

# Run a command, keeping a full copy in the given log file. Output is streamed
# live only with --verbose; otherwise it stays in the log, and the tail is
# printed if the command fails, so the noisy warnings this project emits with
# -Wall -Wextra don't have to be scrolled past to find the real error.
run_logged() {
  local label="$1" logfile="$2"
  shift 2
  local rc=0
  set +e
  if [ "$VERBOSE" -eq 1 ]; then
    "$@" 2>&1 | tee "$logfile"
    rc="${PIPESTATUS[0]}"
  else
    "$@" >"$logfile" 2>&1
    rc=$?
  fi
  set -e
  if [ "$rc" -ne 0 ]; then
    printf -- '\n%s%s failed (exit %s)%s\n' "${C_BOLD}${C_RED}" "$label" "$rc" "${C_RESET}" >&2
    printf -- '--- last 40 lines of %s ---\n' "$logfile" >&2
    tail -n 40 "$logfile" | sed 's/^/    /' >&2
    printf -- '--- full log: %s ---\n\n' "$logfile" >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
${C_BOLD}build.sh${C_RESET} - all-in-one Linux build script for the LZHAM codec

${C_BOLD}USAGE${C_RESET}
  ./scripts/build.sh [options]

${C_BOLD}OPTIONS${C_RESET}
  -c, --config <cfg>    CMake build type: Release (default), Debug,
                        RelWithDebInfo or MinSizeRel
  -s, -static, --static
                        Link the binary fully statically (-static). Requires a
                        static libc; on Debian/Ubuntu: apt install libc6-dev
  -j, --jobs <n>        Parallel build jobs (default: number of CPUs)
  -S, --shared          Also build the unified shared library that exposes the
                        whole public C API (liblzham_x64.so on Linux). Requires
                        the static archives to be built with -fPIC, which this
                        flag turns on. lzhamtest keeps linking statically.
  -B, --build-dir <dir> CMake build directory
                        (default: ${BUILD_SUBDIR}/<variant>)
  -o, --output <dir>    Staging root for the artifacts
                        (default: ${STAGE_SUBDIR})
  -t, --target <name>   Also build this CMake target; repeatable
  -i, --install [pfx]   Install headers + libraries to <pfx> (default:
                        /usr/local). Also copies the binary into <pfx>/bin
      --no-stage        Do not copy artifacts into the staging directory
      --no-test         Skip the post-build compress/decompress smoke test
      --strip           Strip the staged binary
      --clean           Remove the build directory before configuring
      --clean-all       Remove every ${BUILD_SUBDIR}* directory first
      --cc <compiler>   C/C++ compiler to build with (e.g. clang++)
      --verbose         Echo full compiler command lines
  -h, --help            Show this help

${C_BOLD}VARIANTS${C_RESET}
  dynamic (default)  lzhamtest linked against the system libc
  static (-static)   lzhamtest linked with -static, runs on any glibc/musl host

  Artifacts are staged as <output>/<variant>/{bin,lib,include}.

  --shared adds the unified shared library (liblzham_x64.so), which exposes the
  whole public C API from one .so. Statically linked consumers do not need it;
  it is for dlopen-based loaders and for sharing one library across binaries.

${C_BOLD}EXAMPLES${C_RESET}
  ./scripts/build.sh -j "\$(nproc)"
  ./scripts/build.sh -static -c Release --strip
  ./scripts/build.sh --shared --clean
  ./scripts/build.sh --clean -c Debug --no-test
  ./scripts/build.sh -i ~/.local --target lzhamdll
EOF
}

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------

CONFIG="Release"
STATIC_LINK=0
BUILD_SHARED=0
JOBS=""
BUILD_DIR=""
OUTPUT_DIR=""
STAGE=1
RUN_TEST=1
DO_STRIP=0
DO_CLEAN=0
DO_CLEAN_ALL=0
INSTALL=""
INSTALL_PREFIX="/usr/local"
CC_OVERRIDE=""
VERBOSE=0
EXTRA_TARGETS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config)
      [ $# -ge 2 ] || die "$1 requires a value"
      CONFIG="$2"; shift 2 ;;
    --config=*)
      CONFIG="${1#*=}"; shift ;;
    -s|-static|--static)
      STATIC_LINK=1; shift ;;
    -S|--shared)
      BUILD_SHARED=1; shift ;;
    -j|--jobs)
      [ $# -ge 2 ] || die "$1 requires a value"
      JOBS="$2"; shift 2 ;;
    --jobs=*)
      JOBS="${1#*=}"; shift ;;
    -B|--build-dir)
      [ $# -ge 2 ] || die "$1 requires a value"
      BUILD_DIR="$2"; shift 2 ;;
    --build-dir=*)
      BUILD_DIR="${1#*=}"; shift ;;
    -o|--output)
      [ $# -ge 2 ] || die "$1 requires a value"
      OUTPUT_DIR="$2"; shift 2 ;;
    --output=*)
      OUTPUT_DIR="${1#*=}"; shift ;;
    -t|--target)
      [ $# -ge 2 ] || die "$1 requires a value"
      EXTRA_TARGETS+=("$2"); shift 2 ;;
    --target=*)
      EXTRA_TARGETS+=("${1#*=}"); shift ;;
    -i|--install)
      INSTALL=1
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
        INSTALL_PREFIX="$2"; shift 2
      else
        shift
      fi ;;
    --install=*)
      INSTALL=1
      INSTALL_PREFIX="${1#*=}"; shift ;;
    --no-stage)
      STAGE=0; shift ;;
    --no-test)
      RUN_TEST=0; shift ;;
    --strip)
      DO_STRIP=1; shift ;;
    --clean)
      DO_CLEAN=1; shift ;;
    --clean-all)
      DO_CLEAN_ALL=1; shift ;;
    --cc)
      [ $# -ge 2 ] || die "$1 requires a value"
      CC_OVERRIDE="$2"; shift 2 ;;
    --cc=*)
      CC_OVERRIDE="${1#*=}"; shift ;;
    --verbose)
      VERBOSE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2 ;;
  esac
done

case "$CONFIG" in
  Release|Debug|RelWithDebInfo|MinSizeRel) ;;
  *) die "Unsupported build type \"$CONFIG\" (Release, Debug, RelWithDebInfo, MinSizeRel)" ;;
esac

VARIANT="dynamic"
[ "$STATIC_LINK" -eq 1 ] && VARIANT="static"

# Resolve relative paths against the repo root so the script behaves the same
# no matter which directory it is invoked from.
abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "$ROOT_DIR/$1" ;;
  esac
}

[ -n "$BUILD_DIR" ]  || BUILD_DIR="${BUILD_SUBDIR}/${VARIANT}"
[ -n "$OUTPUT_DIR" ] || OUTPUT_DIR="$STAGE_SUBDIR"

BUILD_DIR_ABS="$(abspath "${BUILD_DIR%/}")"
OUTPUT_DIR_ABS="$(abspath "${OUTPUT_DIR%/}")"
STAGE_DIR="$OUTPUT_DIR_ABS/$VARIANT"

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------

phase "Checking the toolchain"

[ "$(uname -s)" = "Linux" ] || die "build.sh targets Linux (detected $(uname -s)); use the scripts\\build_*.ps1 scripts on Windows"

command -v cmake >/dev/null 2>&1 || die "cmake not found. Install it (e.g. apt install cmake) and re-run."
CMAKE_VERSION="$(cmake --version | head -n 1)"
info "cmake:     ${CMAKE_VERSION}"

if command -v ninja >/dev/null 2>&1 && [ -z "${CMAKE_GENERATOR:-}" ]; then
  CMAKE_GENERATOR="Ninja"
  info "generator: Ninja"
elif command -v make >/dev/null 2>&1; then
  CMAKE_GENERATOR="Unix Makefiles"
  info "generator: Unix Makefiles"
else
  die "No supported build tool found. Install make (or ninja)."
fi

if [ -n "$CC_OVERRIDE" ]; then
  CXX_COMPILER="$CC_OVERRIDE"
  C_COMPILER="$CC_OVERRIDE"
else
  for cxx in c++ g++ clang++; do
    if command -v "$cxx" >/dev/null 2>&1; then CXX_COMPILER="$cxx"; break; fi
  done
  [ -n "${CXX_COMPILER:-}" ] || die "No C++ compiler found. Install g++ or clang++ (and a matching C compiler)."
  for cc in cc gcc clang; do
    if command -v "$cc" >/dev/null 2>&1; then C_COMPILER="$cc"; break; fi
  done
  # Clang/g++ drivers also compile C, so fall back to the C++ driver itself.
  C_COMPILER="${C_COMPILER:-$CXX_COMPILER}"
fi
info "compiler:  $CXX_COMPILER ($("$CXX_COMPILER" --version 2>/dev/null | head -n 1))"

if [ -z "$JOBS" ]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
  elif command -v getconf >/dev/null 2>&1; then
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
  else
    JOBS=4
  fi
fi
info "jobs:      ${JOBS}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lzham-build.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# A static binary needs libc.a / a static toolchain runtime to be present. Probe
# with the same threading flags the real link line uses.
if [ "$STATIC_LINK" -eq 1 ]; then
  printf 'int main(void) { return 0; }\n' > "$WORK_DIR/probe.c"
  if ! "$CXX_COMPILER" -static -pthread "$WORK_DIR/probe.c" -o "$WORK_DIR/probe" >"$WORK_DIR/probe.log" 2>&1; then
    warn "this toolchain cannot link a fully static binary:"
    sed 's/^/      /' "$WORK_DIR/probe.log" >&2 || true
    cat >&2 <<EOF

    Install a static libc and retry:
      Debian/Ubuntu   sudo apt install libc6-dev
      Fedora/RHEL     sudo dnf install glibc-static
      Alpine          apk add musl-dev   (then use: --cc musl-gcc)
EOF
    die "aborting because -static was requested"
  fi
  ok "static linking is available"
fi

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------

if [ "$DO_CLEAN_ALL" -eq 1 ]; then
  phase "Cleaning every ${BUILD_SUBDIR}* directory"
  for d in "$ROOT_DIR/${BUILD_SUBDIR}"*; do
    [ -d "$d" ] || continue
    info "removing ${d#"$ROOT_DIR"/}"
    rm -rf "$d"
  done
  ok "build directories removed"
elif [ "$DO_CLEAN" -eq 1 ]; then
  phase "Cleaning $BUILD_DIR_ABS"
  rm -rf "$BUILD_DIR_ABS"
  ok "build directory removed"
fi

# ---------------------------------------------------------------------------
# configure
# ---------------------------------------------------------------------------

phase "Configuring ($CONFIG, $VARIANT) in ${BUILD_DIR_ABS#"$ROOT_DIR"/}"

LOG_DIR="$BUILD_DIR_ABS/logs"

# lzhamdll is a static library unless BUILD_LZHAMDLL_SHARED is on. Turning it on
# needs the sub-libraries to be position independent, otherwise ld refuses to
# put their code in a .so. Both options are always passed explicitly so the build
# directory can't inherit a stale combination from a previous run.
if [ "$BUILD_SHARED" -eq 1 ]; then
  DLL_SHARED=ON; PIC=ON
else
  DLL_SHARED=OFF; PIC=OFF
fi

CMAKE_ARGS=(
  -S "$ROOT_DIR"
  -B "$BUILD_DIR_ABS"
  -G "$CMAKE_GENERATOR"
  -DCMAKE_BUILD_TYPE="$CONFIG"
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_LZHAMDLL_SHARED="$DLL_SHARED"
  -DCMAKE_POSITION_INDEPENDENT_CODE="$PIC"
  -DBUILD_X64=ON
  -DCMAKE_C_COMPILER="$C_COMPILER"
  -DCMAKE_CXX_COMPILER="$CXX_COMPILER"
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
)
[ "$VERBOSE" -eq 1 ] && CMAKE_ARGS+=(-DCMAKE_VERBOSE_MAKEFILE=ON)

if [ "$STATIC_LINK" -eq 1 ]; then
  CMAKE_ARGS+=(-DCMAKE_EXE_LINKER_FLAGS=-static)
fi

info "cmake ${CMAKE_ARGS[*]}"
mkdir -p "$LOG_DIR"
run_logged "CMake configure" "$LOG_DIR/configure.log" cmake "${CMAKE_ARGS[@]}"
ok "configure finished (log: ${LOG_DIR#"$ROOT_DIR"/}/configure.log)"

# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------

phase "Building"
BUILD_ARGS=(--build "$BUILD_DIR_ABS" --config "$CONFIG" --parallel "$JOBS")
BUILD_TARGETS=(lzhamtest)
[ "$BUILD_SHARED" -eq 1 ] && BUILD_TARGETS+=(lzhamdll)
if [ ${#EXTRA_TARGETS[@]} -gt 0 ]; then
  BUILD_TARGETS+=("${EXTRA_TARGETS[@]}")
fi
BUILD_ARGS+=(--target "${BUILD_TARGETS[@]}")
info "cmake ${BUILD_ARGS[*]}"
run_logged "Build" "$LOG_DIR/build.log" cmake "${BUILD_ARGS[@]}"
ok "build finished (log: ${LOG_DIR#"$ROOT_DIR"/}/build.log)"

# ---------------------------------------------------------------------------
# locate the products
# ---------------------------------------------------------------------------

phase "Locating artifacts"

find_artifact() {
  # -quit stops at the first hit; piping into head would risk a SIGPIPE for find,
  # which pipefail would turn into a bogus failure.
  find "$BUILD_DIR_ABS" -type f -name "$1" -not -path '*/CMakeFiles/*' -print -quit 2>/dev/null || true
}

LZHAMTEST_BIN="$(find_artifact lzhamtest)"
[ -n "$LZHAMTEST_BIN" ] || die "lzhamtest binary not found under $BUILD_DIR_ABS"
info "binary:    ${LZHAMTEST_BIN#"$BUILD_DIR_ABS"/}"

# lzhamdll names its output liblzham_x64.so, with a 'D' inserted before the
# extension in Debug configs. Build the exact name rather than globbing, so a
# stale artifact from a previous -c run can't be staged by mistake.
DLL_BASENAME="lzham_x64"
[ "$CONFIG" = "Debug" ] && DLL_BASENAME="${DLL_BASENAME}D"

LZHAM_LIBS=()
for lib in liblzhamcore.a liblzhamdecomp.a liblzhamcomp.a "lib${DLL_BASENAME}.a"; do
  p="$(find_artifact "$lib")"
  [ -n "$p" ] && LZHAM_LIBS+=("$p")
done

# The unified shared library (lzhamdll built as SHARED). The modular layout's
# lzham*.so files are not produced in this configuration.
LZHAM_SO=""
if [ "$BUILD_SHARED" -eq 1 ]; then
  LZHAM_SO="$(find_artifact "lib${DLL_BASENAME}.so")"
  [ -n "$LZHAM_SO" ] || die "lib${DLL_BASENAME}.so not found under $BUILD_DIR_ABS (did the lzhamdll target build?)"
  info "shared:    ${LZHAM_SO#"$BUILD_DIR_ABS"/}"
fi

if [ "$STATIC_LINK" -eq 1 ]; then
  if command -v file >/dev/null 2>&1; then
    file "$LZHAMTEST_BIN" | sed 's/^/    /'
  fi
  if command -v ldd >/dev/null 2>&1; then
    if ldd "$LZHAMTEST_BIN" >/dev/null 2>&1; then
      warn "the binary still has shared library dependencies:"
      ldd "$LZHAMTEST_BIN" | sed 's/^/      /' >&2
    else
      ok "binary has no shared library dependencies"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# stage
# ---------------------------------------------------------------------------

if [ "$STAGE" -eq 1 ]; then
  phase "Staging artifacts into ${STAGE_DIR#"$ROOT_DIR"/}"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/lib" "$STAGE_DIR/include"

  install -m 0755 "$LZHAMTEST_BIN" "$STAGE_DIR/bin/lzhamtest"
  ok "bin/lzhamtest"

  lib_names=""
  for lib in ${LZHAM_LIBS+"${LZHAM_LIBS[@]}"}; do
    install -m 0644 "$lib" "$STAGE_DIR/lib/$(basename "$lib")"
    lib_names+="${lib##*/} "
  done
  if [ -n "$lib_names" ]; then
    ok "lib/ (${lib_names% })"
  else
    warn "no static libraries were produced"
  fi

  if [ -n "$LZHAM_SO" ]; then
    install -m 0755 "$LZHAM_SO" "$STAGE_DIR/lib/$(basename "$LZHAM_SO")"
    ok "lib/ ($(basename "$LZHAM_SO"))"
  fi

  for hdr in lzham.h lzham_dynamic_lib.h lzham_static_lib.h lzham_exports.inc zlib.h; do
    [ -f "$ROOT_DIR/include/$hdr" ] && install -m 0644 "$ROOT_DIR/include/$hdr" "$STAGE_DIR/include/$hdr"
  done
  ok "include/"

  if [ "$DO_STRIP" -eq 1 ]; then
    if command -v strip >/dev/null 2>&1; then
      strip "$STAGE_DIR/bin/lzhamtest"
      ok "stripped bin/lzhamtest"
    else
      warn "strip not found; leaving the binary unstripped"
    fi
  fi
else
  phase "Skipping staging (--no-stage)"
fi

# ---------------------------------------------------------------------------
# smoke test
# ---------------------------------------------------------------------------

TEST_BIN="$LZHAMTEST_BIN"
[ "$STAGE" -eq 1 ] && TEST_BIN="$STAGE_DIR/bin/lzhamtest"

if [ "$RUN_TEST" -eq 1 ]; then
  phase "Smoke test (compress + decompress + compare)"

  SAMPLE="$ROOT_DIR/$TEST_SAMPLE"
  [ -f "$SAMPLE" ] || die "sample file $TEST_SAMPLE not found; re-run with --no-test to skip"

  same_file() {
    if command -v cmp >/dev/null 2>&1; then
      cmp -s "$1" "$2"
    elif command -v diff >/dev/null 2>&1; then
      diff -q "$1" "$2" >/dev/null 2>&1
    else
      [ "$(cksum <"$1")" = "$(cksum <"$2")" ]
    fi
  }

  # lzhamtest -v writes its decompression scratch file into the current working
  # directory, so run it from the scratch dir with relative paths. That keeps it
  # off the caller's CWD (which may not even be writable). All stdin/stdout
  # redirection is left to the caller.
  run_lzhamtest() {
    ( cd "$WORK_DIR" && "$@" )
  }

  info "compressing and verifying $TEST_SAMPLE"
  run_lzhamtest "$TEST_BIN" -v c "$SAMPLE" roundtrip.lzh >"$WORK_DIR/compress.log" 2>&1 \
    || { sed 's/^/      /' "$WORK_DIR/compress.log" >&2; die "compression failed"; }
  ok "compress + built-in verify"

  info "decompressing and comparing"
  run_lzhamtest "$TEST_BIN" d "$WORK_DIR/roundtrip.lzh" "$WORK_DIR/roundtrip.out" >"$WORK_DIR/decompress.log" 2>&1 \
    || { sed 's/^/      /' "$WORK_DIR/decompress.log" >&2; die "decompression failed"; }
  same_file "$WORK_DIR/roundtrip.out" "$SAMPLE" || die "decompressed output does not match $TEST_SAMPLE"
  ok "file round trip matches the original"

  info "streaming round trip (stdin -> stdout)"
  run_lzhamtest "$TEST_BIN" -S c - "$WORK_DIR/stream.lzh" <"$SAMPLE" >"$WORK_DIR/stream_c.log" 2>&1 \
    || { sed 's/^/      /' "$WORK_DIR/stream_c.log" >&2; die "streaming compression failed"; }
  run_lzhamtest "$TEST_BIN" -S d - - <"$WORK_DIR/stream.lzh" >"$WORK_DIR/stream.out" 2>"$WORK_DIR/stream_d.log" \
    || { sed 's/^/      /' "$WORK_DIR/stream_d.log" >&2; die "streaming decompression failed"; }
  same_file "$WORK_DIR/stream.out" "$SAMPLE" || die "streaming output does not match $TEST_SAMPLE"
  ok "streaming round trip matches the original"

  if [ -n "$LZHAM_SO" ]; then
    phase "Smoke test ($(basename "$LZHAM_SO"))"

    SO="$LZHAM_SO"
    [ "$STAGE" -eq 1 ] && SO="$STAGE_DIR/lib/$(basename "$LZHAM_SO")"

    # A shared object that links archives can be produced with unresolved symbols
    # and still "build" fine, so check for them explicitly.
    if command -v ldd >/dev/null 2>&1; then
      if ldd -r "$SO" 2>&1 | grep -q "undefined symbol"; then
        ldd -r "$SO" 2>&1 | grep "undefined symbol" | sed 's/^/      /' >&2
        die "$(basename "$SO") has undefined symbols"
      fi
      ok "no undefined symbols"
    fi

    # dlopen the library and push data through its zlib-compatible API.
    cat > "$WORK_DIR/so_test.cpp" <<'CPP'
// Round-trips data through the unified shared library's zlib-compatible API.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

typedef unsigned long lz_size_t;
typedef lz_size_t (*fn_bound_t)(lz_size_t);
typedef int (*fn_comp_t)(unsigned char *dst, lz_size_t *dst_len, const unsigned char *src, lz_size_t src_len);
typedef int (*fn_uncomp_t)(unsigned char *dst, lz_size_t *dst_len, const unsigned char *src, lz_size_t src_len);

template <class T> static T load(void *handle, const char *name)
{
   T fn = reinterpret_cast<T>(dlsym(handle, name));
   if (!fn) { fprintf(stderr, "missing export: %s\n", name); exit(1); }
   return fn;
}

int main(int argc, char **argv)
{
   if (argc < 2) { fprintf(stderr, "usage: so_test <shared library>\n"); return 2; }

   void *handle = dlopen(argv[1], RTLD_NOW);
   if (!handle) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }

   fn_bound_t pBound = load<fn_bound_t>(handle, "lzham_z_compressBound");
   fn_comp_t pCompress = load<fn_comp_t>(handle, "lzham_z_compress");
   fn_uncomp_t pUncompress = load<fn_uncomp_t>(handle, "lzham_z_uncompress");

   const size_t kSrcSize = 6000;
   unsigned char *src = (unsigned char *)malloc(kSrcSize);
   for (size_t i = 0; i < kSrcSize; i++)
      src[i] = (unsigned char)"hello lzham "[i % 12];

   lz_size_t bound = pBound((lz_size_t)kSrcSize);
   unsigned char *comp = (unsigned char *)malloc(bound);
   lz_size_t comp_len = bound;
   if (pCompress(comp, &comp_len, src, (lz_size_t)kSrcSize) != 0) { fprintf(stderr, "lzham_z_compress failed\n"); return 1; }

   unsigned char *out = (unsigned char *)malloc(kSrcSize * 2);
   lz_size_t out_len = kSrcSize * 2;
   if (pUncompress(out, &out_len, comp, comp_len) != 0) { fprintf(stderr, "lzham_z_uncompress failed\n"); return 1; }

   if (out_len != kSrcSize || memcmp(out, src, kSrcSize) != 0) { fprintf(stderr, "round trip mismatch\n"); return 1; }

   printf("round trip through the zlib API: %u -> %u -> %u bytes\n",
          (unsigned)kSrcSize, (unsigned)comp_len, (unsigned)out_len);
   dlclose(handle);
   return 0;
}
CPP

    # -ldl is a no-op on glibc >= 2.34 but doesn't exist at all on musl.
    if ! "$CXX_COMPILER" -O1 -o "$WORK_DIR/so_test" "$WORK_DIR/so_test.cpp" -ldl >"$WORK_DIR/so_build.log" 2>&1; then
      if ! "$CXX_COMPILER" -O1 -o "$WORK_DIR/so_test" "$WORK_DIR/so_test.cpp" >>"$WORK_DIR/so_build.log" 2>&1; then
        sed 's/^/      /' "$WORK_DIR/so_build.log" >&2
        die "could not build the shared library test harness"
      fi
    fi
    "$WORK_DIR/so_test" "$SO" | sed 's/^/    /' \
      || die "$(basename "$SO") failed the round-trip test"
  fi
else
  phase "Skipping smoke test (--no-test)"
fi

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------

if [ -n "$INSTALL" ]; then
  phase "Installing to $INSTALL_PREFIX"
  cmake --install "$BUILD_DIR_ABS" --config "$CONFIG" --prefix "$INSTALL_PREFIX"
  # lzhamtest has no install() rule of its own, so place the binary by hand.
  install -d "$INSTALL_PREFIX/bin"
  install -m 0755 "$TEST_BIN" "$INSTALL_PREFIX/bin/lzhamtest"
  ok "installed into $INSTALL_PREFIX"
fi

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------

phase "Done"
info "variant:   $VARIANT"
info "config:    $CONFIG"
info "build dir: $BUILD_DIR_ABS"
info "logs:      $LOG_DIR"
if [ "$STAGE" -eq 1 ]; then
  info "staged:    $STAGE_DIR"
  info "binary:    $STAGE_DIR/bin/lzhamtest"
  [ -n "$LZHAM_SO" ] && info "library:   $STAGE_DIR/lib/$(basename "$LZHAM_SO")"
  info "example:   $STAGE_DIR/bin/lzhamtest -v c $TEST_SAMPLE /tmp/hello.lzh"
fi
