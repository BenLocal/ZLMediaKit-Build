#!/bin/bash

PLATFORM="linux/amd64"
TAG="latest"
DOCKERFILE="Dockerfile"
BRANCH="master"

while [[ $# -gt 0 ]]; do
  case $1 in
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --dockerfile)
      DOCKERFILE="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

OUTPUT_DIR="zlm/$(echo $BRANCH | tr '/' '_')/$(echo $PLATFORM | tr '/' '_')"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
echo "Building ZLMediaKit..."
echo "platform: $PLATFORM"
echo "tag: $TAG"
echo "dockerfile: $DOCKERFILE"
echo "branch: $BRANCH"
echo "output_dir: $OUTPUT_DIR"
docker buildx build --platform "$PLATFORM" \
        --build-arg ARG_BRANCH="$BRANCH" \
		-t "zlmediakit:$TAG" -f "$DOCKERFILE" --output "$OUTPUT_DIR" .
# to .tar.gz
FILE_NAME="zlmediakit_$(echo $BRANCH | tr '/' '_')_$(echo $PLATFORM | tr '/' '_')_$TAG".tar.gz
echo "package to: $FILE_NAME"
tar -czvf "$FILE_NAME" -C "$OUTPUT_DIR" .

# copy to artifacts
mkdir -p artifacts
cp -rf "$FILE_NAME" artifacts/