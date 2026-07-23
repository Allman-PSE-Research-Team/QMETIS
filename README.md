# QMETIS 

QMETIS is a modularity-default fork of METIS for partitioning graphs, partitioning finite element meshes, 
and producing fill reducing orderings for sparse matrices. The algorithms implemented in upstream 
METIS are based on the multilevel recursive-bisection, multilevel k-way, and multi-constraint 
partitioning schemes developed in our lab.

##  Downloading QMETIS

Clone the QMETIS source tree using the command:
```
git clone <qmetis-repository-url>
```

## Building standalone QMETIS binaries and library

To build QMETIS you can follow the instructions below:

### Native Linux and macOS build

QMETIS requires a C compiler, CMake, Git, GNU Make, and
[GKlib](https://github.com/KarypisLab/GKlib). The commands below install GKlib
and QMETIS into a user-owned prefix, so administrator access is not required
for the installation itself.

On Ubuntu or Debian, install the build prerequisites with:

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake git
```

In a root-owned notebook or container, such as Google Colab, omit `sudo`.

On macOS, first install Apple's command-line developer tools if necessary:

```bash
xcode-select --install
```

Then install CMake and Git with Homebrew if they are not already available:
m, 
```bash
brew install cmake git
```

Choose an installation prefix and working directory. The same prefix must be
passed to GKlib and QMETIS:

```bash
export QMETIS_PREFIX="$HOME/qmetis-local"
export QMETIS_WORK="$HOME/qmetis-build"
mkdir -p "$QMETIS_PREFIX" "$QMETIS_WORK"
cd "$QMETIS_WORK"
```

Build and install GKlib:

```bash
git clone https://github.com/KarypisLab/GKlib.git
cd GKlib
make config prefix="$QMETIS_PREFIX"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
make install
```

Clone, build, and install QMETIS as a shared library:

```bash
cd "$QMETIS_WORK"
git clone https://github.com/Allman-PSE-Research-Team/METIS.git QMETIS
cd QMETIS

# Optional reproducibility pin; replace with the commit validated by your application.
# git checkout 5e7c7bc

make config shared=1 i64=1 prefix="$QMETIS_PREFIX" gklib_path="$QMETIS_PREFIX"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
make install
```

For a reproducible deployment, uncomment the `git checkout` line and use the exact
QMETIS commit validated by the application. Pinning is optional. The example
commit omits any fixes committed after it,
so use the current tested commit when newer behavior is required.

The installation normally contains:

```text
$QMETIS_PREFIX/bin
$QMETIS_PREFIX/include/qmetis.h
$QMETIS_PREFIX/lib/libqmetis.so       # Linux
$QMETIS_PREFIX/lib/libqmetis.dylib    # macOS
```

A compatibility `metis.h` and `libmetis` artifact are also installed for
existing wrappers. The exported C API remains `METIS_*`. Prefer the
`libqmetis` artifact when the wrapper accepts an explicit library path, since
the compatibility name can collide with an upstream METIS installation.

To request 64-bit graph indices and integer weights, add `i64=1` to the QMETIS
`make config` command. To request 64-bit `real_t`, add `r64=1`. Wrappers must
use data-type widths matching the compiled library.

### Native Windows build

Install Git, CMake, and Visual Studio or Visual Studio Build Tools with the
**Desktop development with C++** workload and a Windows SDK. Run the commands
below from a Developer PowerShell for the installed Visual Studio version.

First build and install GKlib. The generator name must match one listed by
`cmake --help`; Visual Studio 2022 uses `Visual Studio 17 2022`, Visual Studio 2026 uses `Visual Studio 18 2026`, while other
Visual Studio releases use their corresponding generator.

```powershell
git clone https://github.com/KarypisLab/GKlib.git
cd GKlib

cmake -S . -B build `
  -G "Visual Studio 18 2026" `
  -A x64 `
  -DCMAKE_INSTALL_PREFIX="C:\qmetis-deps"

cmake --build build --config Release
cmake --install build --config Release
```

The GKlib prefix should now contain `include\GKlib.h` and `lib\GKlib.lib`.
Use the same Visual Studio generator, architecture, and configuration for
QMETIS. In the QMETIS source directory, select the public integer and
floating-point widths in `include\metis.h`:

```c
#define IDXTYPEWIDTH 64
#define REALTYPEWIDTH 64
```

`IDXTYPEWIDTH` may be `32` or `64`; it is independent of the `-A x64` CPU
architecture. Python wrappers must be configured for the same integer width
as the compiled library.

Configure and build the primary QMETIS DLL:

```powershell
.\vsgen.bat `
  -G "Visual Studio 18 2026" `
  -A x64 `
  -DSHARED=ON `
  -DGKLIB_PATH="C:\qmetis-deps"

cmake --build build\windows --config Release --target qmetis
```

The primary output is normally:

```text
build\windows\libmetis\Release\qmetis.dll
```

To build the filename-compatible library for wrappers that require
`metis.dll`, run:

```powershell
cmake --build build\windows --config Release --target metis_compat
```

This normally produces `build\windows\libmetis\Release\metis.dll`. Both DLLs
export the existing `METIS_*` C API. Prefer `qmetis.dll` when a wrapper allows
an explicit library path, because installing `metis.dll` beside an upstream
METIS installation can cause loader-name collisions.

If CMake reports that the `v143` toolset is missing, either install the
Visual Studio 2026 C++ build tools or replace `Visual Studio 18 2026` in both
GKlib and QMETIS commands with the generator for the installed Visual Studio
version. After changing generators, configure into a fresh build directory;
CMake build directories cannot switch generators in place.

To remove a previous QMETIS Windows configuration:

```powershell
Remove-Item -LiteralPath .\build\windows -Recurse -Force
Remove-Item -LiteralPath .\build\xinclude -Recurse -Force
```

### Common configuration options are:

    cc=[compiler]     - The C compiler to use [default is determined by CMake]
    shared=1          - Build a shared library instead of a static one [off by default]
    prefix=[PATH]     - Set the installation prefix [~/local by default]
    gklib_path=[PATH] - Set the installation prefix where GKlib has been installed.
                        Pass the prefix itself (e.g., ~/local), not ~/local/lib or
                        ~/local/lib64. You can skip this if GKlib's installation prefix
                        is the same as that of QMETIS.
    i64=1             - Sets to 64 bits the width of the datatype that will store information
                        about the vertices and their adjacency lists. 
    r64=1             - Sets to 64 bits the width of the datatype that will store information 
                        about floating point numbers.

### Advanced debugging related options:

    gdb=1           - Build with support for GDB [off by default]
    debug=1         - Enable debugging support [off by default]
    assert=1        - Enable asserts [off by default]
    assert2=1       - Enable very expensive asserts [off by default]

### Other make commands

    make uninstall
         Removes all files installed by 'make install'.

    make clean
         Removes all object files but retains the configuration options.

    make distclean
         Performs clean and completely removes the build directory.


## Copyright & License Notice
Copyright 1998-2020, Regents of the University of Minnesota

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
