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
  "amd64" { $cmakeArch = "x64"; $archSlug = "amd64" }
  "x86_64" { $cmakeArch = "x64"; $archSlug = "amd64" }
  "arm64" { $cmakeArch = "ARM64"; $archSlug = "arm64" }
  "aarch64" { $cmakeArch = "ARM64"; $archSlug = "arm64" }
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
git submodule update --init --recursive

Write-Host "Building ZLMediaKit for Windows..."
cmake -S . -B build -A $cmakeArch -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_WEBRTC=OFF -DENABLE_FFMPEG=OFF
cmake --build build --config Release --parallel

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

Pop-Location

$archivePath = Join-Path $rootDir $fileName
if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
Compress-Archive -Path (Join-Path $outputDir "*") -DestinationPath $archivePath -Force
Copy-Item -Path $archivePath -Destination (Join-Path $rootDir "artifacts") -Force

Write-Host "Build success: artifacts/$fileName"
