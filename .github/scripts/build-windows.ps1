$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$sourceDir = $env:GITHUB_WORKSPACE
$tempDir = $env:RUNNER_TEMP
$idxWidth = $env:QMETIS_IDXTYPEWIDTH
$realWidth = $env:QMETIS_REALTYPEWIDTH
$gklibRef = $env:GKLIB_REF

if (-not $sourceDir -or -not $tempDir -or -not $idxWidth -or -not $realWidth -or -not $gklibRef) {
    throw "Required CI environment variables are missing"
}

$depsDir = Join-Path $tempDir "qmetis-deps"
$gklibSource = Join-Path $depsDir "GKlib"
$gklibBuild = Join-Path $depsDir "gklib-build"
$qmetisBuild = Join-Path $tempDir "qmetis-build"
$prefix = Join-Path $tempDir "qmetis-prefix"
$packageName = "qmetis-5.2.1-windows-x86_64-idx${idxWidth}-real${realWidth}"
$distDir = Join-Path $sourceDir "dist"
$packageDir = Join-Path $distDir $packageName

foreach ($path in @($depsDir, $qmetisBuild, $prefix, $packageDir)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $depsDir, $distDir | Out-Null

git clone --quiet https://github.com/KarypisLab/GKlib.git $gklibSource
git -C $gklibSource checkout --quiet $gklibRef

cmake -S $gklibSource -B $gklibBuild -A x64 `
    -DCMAKE_INSTALL_PREFIX="$prefix"
if ($LASTEXITCODE -ne 0) { throw "GKlib configure failed" }
cmake --build $gklibBuild --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw "GKlib build failed" }
cmake --install $gklibBuild --config Release
if ($LASTEXITCODE -ne 0) { throw "GKlib install failed" }

cmake -S $sourceDir -B $qmetisBuild -A x64 `
    -DCMAKE_INSTALL_PREFIX="$prefix" `
    -DGKLIB_PATH="$prefix" `
    -DSHARED=ON `
    -DQMETIS_BUILD_PROGRAMS=OFF `
    -DIDXTYPEWIDTH="$idxWidth" `
    -DREALTYPEWIDTH="$realWidth"
if ($LASTEXITCODE -ne 0) { throw "QMETIS configure failed" }
cmake --build $qmetisBuild --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw "QMETIS build failed" }
cmake --install $qmetisBuild --config Release
if ($LASTEXITCODE -ne 0) { throw "QMETIS install failed" }

New-Item -ItemType Directory -Force -Path `
    (Join-Path $packageDir "lib"), (Join-Path $packageDir "include") | Out-Null
Copy-Item (Join-Path $prefix "lib\qmetis.dll") (Join-Path $packageDir "lib")
Copy-Item (Join-Path $prefix "lib\qmetis.lib") (Join-Path $packageDir "lib")
Copy-Item (Join-Path $prefix "lib\metis.dll") (Join-Path $packageDir "lib")
Copy-Item (Join-Path $prefix "lib\metis.lib") (Join-Path $packageDir "lib")
Copy-Item (Join-Path $prefix "include\qmetis.h") (Join-Path $packageDir "include")
Copy-Item (Join-Path $prefix "include\metis.h") (Join-Path $packageDir "include")
Copy-Item (Join-Path $sourceDir "LICENSE"), (Join-Path $sourceDir "README.md") $packageDir

$qmetisCommit = git -C $sourceDir rev-parse HEAD
$gklibCommit = git -C $gklibSource rev-parse HEAD
$compilerConfig = Get-ChildItem -LiteralPath (Join-Path $qmetisBuild "CMakeFiles") `
    -Recurse -Filter "CMakeCCompiler.cmake" | Select-Object -First 1
$compilerVersion = "unknown"
if ($compilerConfig) {
    $versionMatch = Select-String -LiteralPath $compilerConfig.FullName `
        -Pattern '^set\(CMAKE_C_COMPILER_VERSION "([^"]+)"\)'
    if ($versionMatch) { $compilerVersion = $versionMatch.Matches[0].Groups[1].Value }
}
$compiler = "MSVC $compilerVersion"
@"
QMETIS_COMMIT=$qmetisCommit
GKLIB_COMMIT=$gklibCommit
PLATFORM=windows-x86_64
IDXTYPEWIDTH=$idxWidth
REALTYPEWIDTH=$realWidth
BUILD_TYPE=Release
COMPILER=$compiler
"@ | Set-Content -LiteralPath (Join-Path $packageDir "BUILD-INFO.txt") -Encoding ascii

python (Join-Path $sourceDir ".github\scripts\verify_library.py") `
    (Join-Path $packageDir "lib\qmetis.dll") `
    (Join-Path $packageDir "include\qmetis.h") `
    $idxWidth $realWidth
if ($LASTEXITCODE -ne 0) { throw "QMETIS API verification failed" }


$checksumTargets = Get-ChildItem -LiteralPath $packageDir -Recurse -File |
    Where-Object Name -ne "SHA256SUMS" |
    Sort-Object FullName
$checksumLines = foreach ($file in $checksumTargets) {
    $relative = [IO.Path]::GetRelativePath($packageDir, $file.FullName).Replace('\', '/')
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    "$hash  $relative"
}
$checksumLines | Set-Content -LiteralPath (Join-Path $packageDir "SHA256SUMS") -Encoding ascii

$archive = Join-Path $distDir "$packageName.zip"
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
Compress-Archive -LiteralPath $packageDir -DestinationPath $archive -CompressionLevel Optimal
Write-Host "created dist/$packageName.zip"