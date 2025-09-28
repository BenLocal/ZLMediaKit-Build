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

local output_dir="zlm/$BRANCH/$(echo $PLATFORM | tr '/' '_')"
echo "output_dir: $output_dir"
docker buildx build --platform "$PLATFORM" \
        --build-arg ARG_BRANCH="$BRANCH" \
		-t "zlmediakit:$TAG" -f "$DOCKERFILE" --output "$output_dir" .
# to .tar.gz
local file_name="zlmediakit_$BRANCH_$(echo $PLATFORM | tr '/' '_')_$TAG".tar.gz
echo "package to: $file_name"
tar -czvf "$file_name" -C "$output_dir" .

# copy to artifacts
mkdir -p artifacts
cp -rf "$file_name" artifacts/