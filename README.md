# ZLMediaKit-Build
ZLMediaKit Build

## Build

### Linux (Docker buildx)
```bash
./build.sh --platform linux/amd64 --branch master
```

### macOS (native)
```bash
chmod +x ./build-macos.sh
./build-macos.sh --branch master --arch amd64
./build-macos.sh --branch master --arch arm64
```

### Windows (native, PowerShell)
```powershell
./build-windows.ps1 -Branch master -Arch amd64
./build-windows.ps1 -Branch master -Arch arm64
```
