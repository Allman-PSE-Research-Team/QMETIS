# QMETIS

QMETIS is a modularity-default fork of METIS for partitioning graphs, partitioning finite element meshes,
and producing fill reducing orderings for sparse matrices. The algorithms implemented in upstream
METIS are based on the multilevel recursive-bisection, multilevel k-way, and multi-constraint
partitioning schemes developed in the Karypis lab.

## Modularity objective and resolution

Both `METIS_PartGraphKway` and `METIS_PartGraphRecursive` maximize weighted
Newman-Girvan modularity by default:

```text
Q(gamma) = sum_c [L_c/m - gamma*(d_c/(2m))^2]
```

Here, `L_c` is the weight of edges internal to part `c`, `d_c` is the sum of
weighted degrees in that part, `m` is the total undirected edge weight, and
`gamma` is the modularity resolution. The default is `gamma=1`. Lower values
favor larger communities and higher values favor smaller communities.
For the same weighted undirected graph, partition, and resolution, this is the
same convention used by
`networkx.community.modularity(G, communities, weight="weight",
resolution=gamma)`. A self-loop contributes its weight once to `L_c` and twice
to the weighted degree if one is present, although the canonical METIS graph
format treats self-edges as invalid and callers should normally remove them.

Modularity is a global objective. The recursive entry point therefore uses
recursive bisection to construct a balanced initial partition and then applies
global k-way modularity refinement against the original graph. It does not
optimize independently normalized modularity on each recursive subgraph.
Target partition weights, multi-constraint balancing, imbalance limits,
contiguity, and minimum-connectivity handling remain active during the global
refinement.

The public METIS options array stores integers, so QMETIS represents `gamma`
as a fixed-point value with six decimal places:

```c
idx_t options[METIS_NOPTIONS];
METIS_SetDefaultOptions(options);
options[METIS_OPTION_MODRESOLUTION] =
    (idx_t)(1.25 * METIS_MODULARITY_RESOLUTION_SCALE + 0.5);
```

This example requests `gamma=1.25`. The option must be non-negative and fit in
the configured `idx_t`. Leaving it unset uses
`METIS_MODULARITY_RESOLUTION_SCALE`, which represents `gamma=1`.

Existing wrappers remain binary compatible because function signatures and
the `METIS_*` symbols are unchanged. A wrapper that does not know the new
option still gets `gamma=1`. To configure another value, extend the wrapper's
option enum with `METIS_OPTION_MODRESOLUTION` from `qmetis.h`, then store
`round(gamma*METIS_MODULARITY_RESOLUTION_SCALE)` in that options slot.

To request the original recursive edge-cut algorithm, set:

```c
options[METIS_OPTION_OBJTYPE] = METIS_OBJTYPE_CUT;
```

`METIS_OBJTYPE_CUT` and `METIS_OBJTYPE_VOL` also remain available through the
K-way API. Modularity returned through `objval` is
`round(Q*METIS_MODULARITY_SCALE)`, where
`METIS_MODULARITY_SCALE` is `1000000`. For example, `objval=423817` represents
`Q=0.423817`. Wrappers that return `(objval, parts)` therefore return scaled
modularity in the first element, rather than the edge-cut or communication
volume returned by stock METIS. QMETIS recomputes modularity over the complete
selected partition before producing this value.

The command-line programs are installed as `qgpmetis`, `qmpmetis`,
`qndmetis`, `qm2gmetis`, `qgraphchk`, and `qcmpfillin` to avoid confusion with
stock METIS executables. `qgpmetis` and `qmpmetis` accept `-objtype=mod` and a
decimal `-resolution=<gamma>`; modularity with `gamma=1` is already their
default graph-partitioning objective.

### Input, constraints, and optimization semantics

Like METIS, QMETIS expects an undirected graph encoded as symmetric CSR
adjacency. Graph edge and vertex weights are integer `idx_t` values; arbitrary
floating-point or negative graph weights are not accepted directly. Fractional
non-negative edge weights can be represented by multiplying all edge weights
by one common positive factor and converting them exactly to integers. Uniform
scaling does not change mathematical modularity, but the scaled values must fit
the configured `IDXTYPEWIDTH`, and approximate rounding can change the graph.

QMETIS returns exactly the requested `nparts`; it does not choose the number of
communities. Vertex and multi-constraint weights, target partition weights,
imbalance limits, contiguity, and minimum-connectivity settings remain active.
Restoring balance may require a move that reduces modularity. Consequently, a
QMETIS result can have lower modularity than an unconstrained community
detection routine even when both use the same formula. The `vsize` array does
not affect modularity and remains relevant only to the communication-volume
objective.

Modularity optimization is heuristic and does not guarantee the global
maximum. Candidate moves primarily target neighboring parts to preserve
METIS's efficient local-refinement model, and the objective inherits the
standard modularity resolution limit.

`METIS_NodeND` and the separator and ordering algorithms retain their original
node-separator objectives; the modularity default applies only to the graph
partitioning entry points described above.

##  Downloading QMETIS

Clone the QMETIS source tree using the command:
```
git clone https://github.com/Allman-PSE-Research-Team/METIS.git QMETIS
```

## Building standalone QMETIS binaries and library

To build QMETIS you can follow the instructions below:

### Automated native artifacts

The [native library workflow](.github/workflows/native-libraries.yml) builds and
verifies release libraries without requiring local access to every operating
system. It produces:

```text
qmetis-5.2.1-linux-x86_64-idx64-real32.tar.gz
qmetis-5.2.1-windows-x86_64-idx64-real32.zip
qmetis-5.2.1-macos-arm64-idx64-real32.tar.gz
qmetis-5.2.1-macos-x86_64-idx64-real32.tar.gz
qmetis-5.2.1-macos-universal2-idx64-real32.tar.gz
```

Every package includes the primary `qmetis` library, the filename-compatible
`metis` library, configured headers, licenses, build metadata, and SHA-256
checksums. CI loads each primary library and calls `METIS_PartGraphKway` before
publishing it. The universal macOS dylib is assembled from separately built
native ARM64 and Intel artifacts and is checked with `lipo`.

To build artifacts without creating a release, open **Actions**, select
**Native libraries**, choose **Run workflow**, and select the desired integer
and real widths. The default release ABI is `IDXTYPEWIDTH=64` and
`REALTYPEWIDTH=32`. Workflow artifacts are available from the completed run.

Pushing a tag beginning with `v` or `qmetis-v` builds the same matrix and
attaches all archives plus a top-level `SHA256SUMS` file to a GitHub Release:

```bash
git tag qmetis-v5.2.1-modularity.X
git push origin qmetis-v5.2.1-modularity.X
```

These archives can be embedded as native resources in a larger Python
package. The larger package must publish platform-specific wheels, or a
`universal2` macOS wheel when it embeds the universal dylib, and must configure
its wrapper for the ABI widths recorded in `BUILD-INFO.txt`.

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
QMETIS. Configure the ABI widths through CMake; do not edit `metis.h` manually.
`IDXTYPEWIDTH` may be `32` or `64` and is independent of the `-A x64` CPU
architecture. Python wrappers must use both widths selected for the library.

Configure and build the primary QMETIS DLL:

```powershell
.\vsgen.bat `
  -G "Visual Studio 18 2026" `
  -A x64 `
  -DSHARED=ON `
  -DQMETIS_BUILD_PROGRAMS=OFF `
  -DIDXTYPEWIDTH=64 `
  -DREALTYPEWIDTH=32 `
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

Direct CMake builds use `-DIDXTYPEWIDTH=32|64` and
`-DREALTYPEWIDTH=32|64`. The generated installed headers record the selected
ABI. Add `-DQMETIS_BUILD_PROGRAMS=OFF` when only the native library is needed.

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
