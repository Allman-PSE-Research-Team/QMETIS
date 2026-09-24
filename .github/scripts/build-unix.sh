#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?}"
: "${RUNNER_TEMP:?}"
: "${QMETIS_PLATFORM:?}"
: "${QMETIS_IDXTYPEWIDTH:?}"
: "${QMETIS_REALTYPEWIDTH:?}"
: "${GKLIB_REF:?}"

# Do not inherit a CI runner's compiler or linker optimization overrides.
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS

case "$(uname -s)" in
  Linux) library_ext="so" ;;
  Darwin) library_ext="dylib" ;;
  *) echo "unsupported Unix platform: $(uname -s)" >&2; exit 1 ;;
esac

source_dir="$GITHUB_WORKSPACE"
deps_dir="$RUNNER_TEMP/qmetis-deps"
gklib_source="$deps_dir/GKlib"
gklib_build="$deps_dir/gklib-build"
qmetis_build="$RUNNER_TEMP/qmetis-build"
prefix="$RUNNER_TEMP/qmetis-prefix"
package_name="qmetis-5.2.1-${QMETIS_PLATFORM}-idx${QMETIS_IDXTYPEWIDTH}-real${QMETIS_REALTYPEWIDTH}"
package_dir="$source_dir/dist/$package_name"

rm -rf "$deps_dir" "$qmetis_build" "$prefix" "$package_dir"
mkdir -p "$deps_dir" "$source_dir/dist"
git clone --quiet https://github.com/KarypisLab/GKlib.git "$gklib_source"
git -C "$gklib_source" checkout --quiet "$GKLIB_REF"

cmake_args=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$prefix"
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
)
gklib_c_flags=""
portable_qmetis=OFF
if [[ "$QMETIS_PLATFORM" == "linux-x86_64" || "$QMETIS_PLATFORM" == "macos-x86_64" ]]; then
  gklib_c_flags="-march=x86-64 -mtune=generic"
  portable_qmetis=ON
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
  cmake_args+=(
    -DCMAKE_OSX_ARCHITECTURES="$(uname -m)"
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
  )
fi

cmake -S "$gklib_source" -B "$gklib_build" "${cmake_args[@]}" \
  -DCMAKE_C_FLAGS="$gklib_c_flags" -DGKLIB_BUILD_APPS=OFF
cmake --build "$gklib_build" --parallel
cmake --install "$gklib_build"

cmake -S "$source_dir" -B "$qmetis_build" \
  "${cmake_args[@]}" \
  -DCMAKE_C_FLAGS= \
  -DQMETIS_PORTABLE_X86_64="$portable_qmetis" \
  -DGKLIB_PATH="$prefix" \
  -DSHARED=ON \
  -DQMETIS_BUILD_PROGRAMS=OFF \
  -DIDXTYPEWIDTH="$QMETIS_IDXTYPEWIDTH" \
  -DREALTYPEWIDTH="$QMETIS_REALTYPEWIDTH"
cmake --build "$qmetis_build" --parallel
cmake --install "$qmetis_build"

mkdir -p "$package_dir/lib" "$package_dir/include"
cp "$prefix/lib/libqmetis.$library_ext" "$package_dir/lib/"
cp "$prefix/lib/libmetis.$library_ext" "$package_dir/lib/"
cp "$prefix/include/qmetis.h" "$package_dir/include/"
cp "$prefix/include/metis.h" "$package_dir/include/"
cp "$source_dir/LICENSE" "$source_dir/README.md" "$package_dir/"

{
  echo "QMETIS_COMMIT=$(git -C "$source_dir" rev-parse HEAD)"
  echo "GKLIB_COMMIT=$(git -C "$gklib_source" rev-parse HEAD)"
  echo "PLATFORM=$QMETIS_PLATFORM"
  echo "IDXTYPEWIDTH=$QMETIS_IDXTYPEWIDTH"
  echo "REALTYPEWIDTH=$QMETIS_REALTYPEWIDTH"
  echo "BUILD_TYPE=Release"
  echo "COMPILER=$(cmake --build "$qmetis_build" --target help >/dev/null 2>&1; cc --version 2>/dev/null | head -n 1 || clang --version | head -n 1)"
  python3 "$source_dir/.github/scripts/check_cpu_target.py" \
    "$QMETIS_PLATFORM" "$gklib_build" "$qmetis_build"
} > "$package_dir/BUILD-INFO.txt"

python3 "$source_dir/.github/scripts/verify_library.py" \
  "$package_dir/lib/libqmetis.$library_ext" \
  "$package_dir/include/qmetis.h" \
  "$QMETIS_IDXTYPEWIDTH" "$QMETIS_REALTYPEWIDTH"

if [[ "$QMETIS_PLATFORM" == "linux-x86_64" ]]; then
  qemu-x86_64 -cpu Nehalem "$(command -v python3)" \
    "$source_dir/.github/scripts/verify_library.py" \
    "$package_dir/lib/libqmetis.so" "$package_dir/include/qmetis.h" \
    "$QMETIS_IDXTYPEWIDTH" "$QMETIS_REALTYPEWIDTH"
  echo "CPU_EMULATION_TEST=qemu-x86_64 Nehalem (no AVX/AVX-512): passed" >> "$package_dir/BUILD-INFO.txt"
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
  actual_arch="$(lipo -archs "$package_dir/lib/libqmetis.dylib")"
  [[ "$actual_arch" == "$(uname -m)" ]] || { echo "unexpected architecture: $actual_arch" >&2; exit 1; }
  nm -gU "$package_dir/lib/libqmetis.dylib" | grep '_METIS_PartGraphKway' >/dev/null
  (cd "$package_dir" && shasum -a 256 lib/* include/* LICENSE README.md BUILD-INFO.txt > SHA256SUMS)
else
  file "$package_dir/lib/libqmetis.so" | grep -q 'x86-64'
  nm -D "$package_dir/lib/libqmetis.so" | grep 'METIS_PartGraphKway' >/dev/null
  (cd "$package_dir" && sha256sum lib/* include/* LICENSE README.md BUILD-INFO.txt > SHA256SUMS)
fi

tar -C "$source_dir/dist" -czf "$source_dir/dist/$package_name.tar.gz" "$package_name"
echo "created dist/$package_name.tar.gz"
