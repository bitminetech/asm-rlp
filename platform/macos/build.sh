#!/bin/sh
# Build the asm-rlp library for one macOS ISA.
# Usage: platform/macos/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, so the library uses the
# pinned LLVM. link-runner.sh and link-bench.sh link the test runner and the bench on a Mac.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64) target=x86_64-apple-macos11 ;;
  arm64)  target=arm64-apple-macos11 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target -I"$root/include" -I"$root/platform/macos" \
    -c "$root/asm/core/$isa/rlp.s" -o "$out/rlp.o"
llvm-ar --format=darwin rcsD "$out/libasm-rlp.a.new" "$out/rlp.o"
mv "$out/libasm-rlp.a.new" "$out/libasm-rlp.a"
