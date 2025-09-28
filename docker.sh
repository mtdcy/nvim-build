#!/bin/bash

DOCKER_IMAGE="${DOCKER_IMAGE:-lcr.io/mtdcy/builder:alpine-3}"

opts=(
    -w "$PWD"
    -v "$PWD:$PWD"
)

docker run --rm -it "${opts[@]}" "$DOCKER_IMAGE" ./build.sh
