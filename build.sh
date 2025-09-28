#!/bin/bash

PLATFORM="linux/amd64"
TAG="latest"
DOCKERFILE="Dockerfile"

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
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

docker buildx build --platform "$PLATFORM" \
		-t "zlmediakit:$TAG" -f "$DOCKERFILE" --output zlm/arm64 .