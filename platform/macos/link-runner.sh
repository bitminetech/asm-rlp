#!/bin/sh
# Link the test runner on a Mac against the library that build.sh made.
# Usage: platform/macos/link-runner.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# The runner is test code in C. It uses the host Xcode clang and macOS SDK.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64) arch=x86_64 ;;
  arm64)  arch=arm64 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

clang -arch $arch -mmacosx-version-min=11.0 -std=c11 -O2 -Wall -Wextra -Werror \
    "$root/tests/runner/runner.c" -I"$root/platform/macos" "$root/tests/runner/abi_$isa.s" "$out/libasm-rlp.a" -o "$out/runner"
