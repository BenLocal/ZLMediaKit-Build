param(
  [string]$Tag = "latest",
  [string]$Branch = "master",
  [string]$Arch = "amd64"
)

$ErrorActionPreference = "Stop"

$rootDir = Get-Location
$workDir = Join-Path $rootDir "workdir_windows"
$srcDir = Join-Path $workDir "ZLMediaKit"
$branchSlug = $Branch -replace "/", "_"

switch ($Arch.ToLower()) {
  "amd64" { $cmakeArch = "x64"; $archSlug = "amd64"; $vcpkgTriplet = "x64-windows" }
  "x86_64" { $cmakeArch = "x64"; $archSlug = "amd64"; $vcpkgTriplet = "x64-windows" }
  "arm64" { $cmakeArch = "ARM64"; $archSlug = "arm64"; $vcpkgTriplet = "arm64-windows" }
  "aarch64" { $cmakeArch = "ARM64"; $archSlug = "arm64"; $vcpkgTriplet = "arm64-windows" }
  default { throw "不支持的架构: $Arch (仅支持: amd64, arm64)" }
}

$outputDir = Join-Path $rootDir ("zlm/" + $branchSlug + "/windows_" + $archSlug)
$fileName = "zlmediakit_${branchSlug}_windows_${archSlug}_${Tag}.zip"

if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
if (Test-Path $outputDir) { Remove-Item $outputDir -Recurse -Force }

New-Item -Path $workDir -ItemType Directory | Out-Null
New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $rootDir "artifacts") -ItemType Directory -Force | Out-Null

Write-Host "Cloning ZLMediaKit branch: $Branch"
git clone --depth=1 -b $Branch https://github.com/ZLMediaKit/ZLMediaKit.git $srcDir
Push-Location $srcDir
# ZLMediaKit's default .gitmodules points submodules at gitee.com, which rate-limits /
# blocks CI runner IPs (401 -> git prompts for a username -> non-interactive failure).
# The repo ships .gitmodules_github with the same submodules on GitHub; swap to it.
Copy-Item .gitmodules_github .gitmodules -Force
git submodule sync
git submodule update --init --recursive

if ($env:VCPKG_ROOT -and (Test-Path (Join-Path $env:VCPKG_ROOT "vcpkg.exe"))) {
  $vcpkgRoot = $env:VCPKG_ROOT
} else {
  $vcpkgRoot = Join-Path $workDir "vcpkg"
  if (-not (Test-Path $vcpkgRoot)) {
    Write-Host "Cloning vcpkg..."
    git clone --depth=1 https://github.com/microsoft/vcpkg.git $vcpkgRoot
  }
  Write-Host "Bootstrapping vcpkg..."
  & (Join-Path $vcpkgRoot "bootstrap-vcpkg.bat") -disableMetrics
}

Write-Host "Installing OpenSSL via vcpkg ($vcpkgTriplet)..."
& (Join-Path $vcpkgRoot "vcpkg.exe") install `
  "openssl:$vcpkgTriplet" `
  "ffmpeg:$vcpkgTriplet" `
  "libsrtp:$vcpkgTriplet"
if ($LASTEXITCODE -ne 0) { throw "vcpkg install failed (exit $LASTEXITCODE)" }

Write-Host "Building ZLMediaKit for Windows..."
# Pass CMAKE_POLICY_VERSION_MINIMUM via a CMake initial-cache (-C) file instead of
# -D. PowerShell's native-argument parser reads the `3.5` in a bare
# `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` token as a number and splits it into
# `...=3` + `.5`, so CMake only ever sees "3" (and discards ".5" as a stray path)
# and rejects it. Putting the value inside a .cmake file keeps the decimal off the
# PowerShell command line entirely — CMake parses the file itself. The override is
# required because ZLToolKit/ZLMediaKit declare
# cmake_minimum_required(VERSION 3.1.3...3.26) and CMake 4.x dropped <3.5 policy compat.
$policyCacheFile = Join-Path $workDir "policy-min.cmake"
Set-Content -Path $policyCacheFile -Encoding ASCII -Value 'set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)'

$cmakeArgs = @(
  '-S', '.', '-B', 'build', '-A', $cmakeArch,
  '-C', $policyCacheFile,
  '-DCMAKE_BUILD_TYPE=Release',
  '-DOPENSSL_USE_STATIC_LIBS=ON',
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkgRoot/scripts/buildsystems/vcpkg.cmake",
  "-DVCPKG_TARGET_TRIPLET=$vcpkgTriplet",
  '-DENABLE_TESTS=OFF',
  '-DENABLE_OPENSSL=ON',
  '-DENABLE_SRT=ON',
  '-DENABLE_WEBRTC=ON',
  '-DENABLE_FFMPEG=ON',
  '-DENABLE_API=ON'
)
cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed (exit $LASTEXITCODE)" }

# Build only runtime target to avoid test/api linkage issues in CI.
cmake --build build --config Release --target MediaServer --parallel
if ($LASTEXITCODE -ne 0) { throw "CMake build failed (exit $LASTEXITCODE)" }

$releaseRoot = Get-ChildItem -Path (Join-Path $srcDir "release") -Directory -Recurse | Where-Object { $_.Name -eq "Release" } | Select-Object -First 1
if (-not $releaseRoot) {
  throw "未找到 Release 输出目录"
}

New-Item -Path (Join-Path $outputDir "bin") -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $outputDir "lib") -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $outputDir "include") -ItemType Directory -Force | Out-Null

Get-ChildItem -Path $releaseRoot.FullName -Filter "MediaServer*.exe" -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $outputDir "bin") -Force
Get-ChildItem -Path $releaseRoot.FullName -Filter "*.dll" -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $outputDir "bin") -Force
Get-ChildItem -Path $releaseRoot.FullName -Filter "*.lib" -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $outputDir "lib") -Force
Copy-Item -Path (Join-Path $srcDir "api/include/*") -Destination (Join-Path $outputDir "include") -Recurse -Force

$vcpkgBin = Join-Path $vcpkgRoot ("installed/" + $vcpkgTriplet + "/bin")
if (Test-Path $vcpkgBin) {
  # Copy runtime dependencies for OpenSSL/SRTP/FFmpeg stack.
  Get-ChildItem -Path $vcpkgBin -Filter "*.dll" -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $outputDir "bin") -Force
}

Pop-Location

$archivePath = Join-Path $rootDir $fileName
if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
Compress-Archive -Path (Join-Path $outputDir "*") -DestinationPath $archivePath -Force
Copy-Item -Path $archivePath -Destination (Join-Path $rootDir "artifacts") -Force

Write-Host "Build success: artifacts/$fileName"
