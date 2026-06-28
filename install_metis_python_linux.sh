#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Clone, build, and install METIS locally on Linux for Python use.

This script assumes there is no local METIS checkout. It clones METIS and
GKlib into a temporary directory, builds a shared libmetis.so, installs the
runtime files under a local prefix, then removes the temporary clone/build
directory.

Usage:
  bash install_metis_python_linux.sh [options]

Options:
  --prefix PATH          Install prefix. Default: $PWD/metis-local
  --metis-url URL        METIS git URL. Default: https://github.com/Allman-PSE-Research-Team/METIS.git
  --metis-ref REF        METIS branch, tag, or commit. Default: 1b0fcb0
  --gklib-url URL        GKlib git URL. Default: https://github.com/KarypisLab/GKlib.git
  --gklib-ref REF        Optional GKlib branch, tag, or commit.
  --i64                  Build METIS with 64-bit idx_t.
  --r64                  Build METIS with 64-bit real_t.
  --keep-build           Keep the temporary clone/build directory for debugging.
  -h, --help             Show this help.

Environment equivalents:
  PREFIX, METIS_URL, METIS_REF, GKLIB_URL, GKLIB_REF,
  METIS_I64=1, METIS_R64=1, KEEP_BUILD=1

After success:
  source <prefix>/metis-python-env.sh
  python3 -m pip install metis
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_c_compiler() {
  command -v cc >/dev/null 2>&1 && return 0
  command -v gcc >/dev/null 2>&1 && return 0
  command -v clang >/dev/null 2>&1 && return 0
  die "missing C compiler: install gcc, clang, or build-essential"
}

PREFIX="${PREFIX:-$PWD/metis-local}"
METIS_URL="${METIS_URL:-https://github.com/Allman-PSE-Research-Team/METIS.git}"
METIS_REF="${METIS_REF:-1b0fcb0}"
GKLIB_URL="${GKLIB_URL:-https://github.com/KarypisLab/GKlib.git}"
GKLIB_REF="${GKLIB_REF:-}"
METIS_I64="${METIS_I64:-0}"
METIS_R64="${METIS_R64:-0}"
KEEP_BUILD="${KEEP_BUILD:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix requires a path"
      PREFIX="$2"
      shift 2
      ;;
    --metis-url)
      [[ $# -ge 2 ]] || die "--metis-url requires a URL"
      METIS_URL="$2"
      shift 2
      ;;
    --metis-ref)
      [[ $# -ge 2 ]] || die "--metis-ref requires a branch, tag, or commit"
      METIS_REF="$2"
      shift 2
      ;;
    --gklib-url)
      [[ $# -ge 2 ]] || die "--gklib-url requires a URL"
      GKLIB_URL="$2"
      shift 2
      ;;
    --gklib-ref)
      [[ $# -ge 2 ]] || die "--gklib-ref requires a branch, tag, or commit"
      GKLIB_REF="$2"
      shift 2
      ;;
    --i64)
      METIS_I64=1
      shift
      ;;
    --r64)
      METIS_R64=1
      shift
      ;;
    --keep-build)
      KEEP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

need_cmd git
need_cmd make
need_cmd cmake
need_cmd mktemp
need_cmd find
need_cmd sort
need_cmd head
need_c_compiler

jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')}"
tmp_parent="${TMPDIR:-/tmp}"
workdir="$(mktemp -d "${tmp_parent%/}/metis-python-build.XXXXXX")"

cleanup() {
  local status=$?
  set +e
  if [[ "$KEEP_BUILD" != "1" && -n "${workdir:-}" && -d "$workdir" ]]; then
    rm -rf "$workdir"
  fi
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd -P)"

printf 'Install prefix: %s\n' "$PREFIX"
printf 'Temporary build directory: %s\n' "$workdir"
printf 'METIS source: %s @ %s\n' "$METIS_URL" "$METIS_REF"
printf 'GKlib source: %s%s\n' "$GKLIB_URL" "${GKLIB_REF:+ @ $GKLIB_REF}"

gklib_src="$workdir/GKlib"
metis_src="$workdir/METIS"

if [[ -n "$GKLIB_REF" ]]; then
  git clone "$GKLIB_URL" "$gklib_src"
  git -C "$gklib_src" checkout "$GKLIB_REF"
else
  git clone --depth 1 "$GKLIB_URL" "$gklib_src"
fi

git clone "$METIS_URL" "$metis_src"
git -C "$metis_src" checkout "$METIS_REF"

printf '\nBuilding GKlib...\n'
make -C "$gklib_src" config "prefix=$PREFIX"
make -C "$gklib_src" -j "$jobs" install

metis_config_args=(config "shared=1" "prefix=$PREFIX" "gklib_path=$PREFIX")
idx_width=32
real_width=32

if [[ "$METIS_I64" == "1" ]]; then
  metis_config_args+=("i64=1")
  idx_width=64
fi

if [[ "$METIS_R64" == "1" ]]; then
  metis_config_args+=("r64=1")
  real_width=64
fi

printf '\nBuilding METIS...\n'
make -C "$metis_src" "${metis_config_args[@]}"
make -C "$metis_src" -j "$jobs" install

libmetis=""
if [[ -e "$PREFIX/lib/libmetis.so" ]]; then
  libmetis="$PREFIX/lib/libmetis.so"
elif [[ -e "$PREFIX/lib64/libmetis.so" ]]; then
  libmetis="$PREFIX/lib64/libmetis.so"
else
  libmetis="$(find "$PREFIX" -name 'libmetis.so*' -print | sort | head -n 1)"
fi

[[ -n "$libmetis" ]] || die "libmetis.so was not found under $PREFIX"
[[ -f "$PREFIX/include/metis.h" ]] || die "metis.h was not found under $PREFIX/include"

lib_dir="$(cd -- "$(dirname -- "$libmetis")" && pwd -P)"
env_file="$PREFIX/metis-python-env.sh"

{
  printf '# Source this file before importing the Python "metis" package.\n'
  printf 'export METIS_DLL=%q\n' "$libmetis"
  printf 'export METIS_IDXTYPEWIDTH=%q\n' "$idx_width"
  printf 'export METIS_REALTYPEWIDTH=%q\n' "$real_width"
  printf 'export LD_LIBRARY_PATH=%q${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\n' "$lib_dir"
} > "$env_file"

printf '\nDone.\n'
printf 'Built library: %s\n' "$libmetis"
printf 'Installed header: %s\n' "$PREFIX/include/metis.h"
printf 'Python env file: %s\n' "$env_file"
printf '\nUse it with:\n'
printf '  source "%s"\n' "$env_file"
printf '  python3 -m pip install metis\n'
printf '  python3 -c "import metis; print(metis.part_graph([[1],[0]], nparts=2))"\n'
