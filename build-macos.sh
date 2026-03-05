#!/bin/bash

set -euo pipefail

TAG="latest"
BRANCH="master"
ARCH="amd64"
ROOT_DIR="$(pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-macos.sh 只能在 macOS 上运行"
  exit 1
fi

WORK_DIR="$ROOT_DIR/workdir_macos"
SRC_DIR="$WORK_DIR/ZLMediaKit"
case "$ARCH" in
  amd64|x86_64)
    CMAKE_ARCH="x86_64"
    ARCH_SLUG="amd64"
    ;;
  arm64|aarch64)
    CMAKE_ARCH="arm64"
    ARCH_SLUG="arm64"
    ;;
  *)
    echo "不支持的架构: $ARCH (仅支持: amd64, arm64)"
    exit 1
    ;;
esac

HOST_ARCH="$(uname -m)"
if [[ "$ARCH_SLUG" == "amd64" && "$HOST_ARCH" != "x86_64" ]]; then
  echo "当前主机架构是 $HOST_ARCH，无法稳定构建 macOS amd64。请使用 x86_64 runner（如 macos-13）。"
  exit 1
fi
if [[ "$ARCH_SLUG" == "arm64" && "$HOST_ARCH" != "arm64" ]]; then
  echo "当前主机架构是 $HOST_ARCH，无法稳定构建 macOS arm64。请使用 arm64 runner。"
  exit 1
fi

OUTPUT_DIR="zlm/$(echo "$BRANCH" | tr '/' '_')/macos_${ARCH_SLUG}"
FILE_NAME="zlmediakit_$(echo "$BRANCH" | tr '/' '_')_macos_${ARCH_SLUG}_${TAG}.tar.gz"

rm -rf "$WORK_DIR" "$ROOT_DIR/$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$ROOT_DIR/$OUTPUT_DIR" "$ROOT_DIR/artifacts"

echo "Installing dependencies with brew..."
brew update
brew install cmake openssl ffmpeg srtp || true

echo "Cloning ZLMediaKit branch: $BRANCH"
git clone --depth=1 -b "$BRANCH" https://github.com/ZLMediaKit/ZLMediaKit.git "$SRC_DIR"
cd "$SRC_DIR"
git submodule update --init --recursive

mkdir -p build
cd build

echo "Building ZLMediaKit for macOS..."
cmake -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCH" \
  -DENABLE_OBJCOPY=OFF \
  -DENABLE_WEBRTC=true \
  -DENABLE_FFMPEG=true ..
make -j"$(sysctl -n hw.ncpu)"

cd "$SRC_DIR"
RELEASE_ROOT="$(find release -type d -name Release | head -n 1 || true)"
if [[ -z "$RELEASE_ROOT" ]]; then
  echo "未找到 Release 输出目录"
  exit 1
fi

mkdir -p "$ROOT_DIR/$OUTPUT_DIR/bin" "$ROOT_DIR/$OUTPUT_DIR/lib" "$ROOT_DIR/$OUTPUT_DIR/include"
cp -f "$RELEASE_ROOT"/MediaServer* "$ROOT_DIR/$OUTPUT_DIR/bin/" || true
cp -f "$RELEASE_ROOT"/*.dylib "$ROOT_DIR/$OUTPUT_DIR/lib/" || true
cp -f "$RELEASE_ROOT"/*.a "$ROOT_DIR/$OUTPUT_DIR/lib/" || true
cp -R api/include/* "$ROOT_DIR/$OUTPUT_DIR/include/"

cd "$ROOT_DIR"
tar -czvf "$FILE_NAME" -C "$OUTPUT_DIR" .
cp -f "$FILE_NAME" artifacts/

echo "Build success: artifacts/$FILE_NAME"
