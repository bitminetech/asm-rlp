#!/bin/sh
# Build the library for all 7 supported targets, and the test runners and
# benches for Linux and Windows, into build/<os>-<isa>/.
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
for isa in x86_64 arm64 riscv64; do platform/linux/build.sh $isa build/linux-$isa; done
for isa in x86_64 arm64; do
    platform/windows/build.sh $isa build/windows-$isa
    platform/macos/build.sh $isa build/macos-$isa
done
