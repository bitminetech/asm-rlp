#!/bin/sh
# Build the asm-rlp library, the test runner and the bench for one Linux ISA.
# Usage: platform/linux/build.sh ISA OUT_DIR    (ISA: x86_64, arm64 or riscv64)
# Runs inside the image from platform/linux/Dockerfile.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64)  target=x86_64-linux-gnu;  march="-march=x86-64" ;;
  arm64)   target=aarch64-linux-gnu; march="-march=armv8-a" ;;
  riscv64) target=riscv64-linux-gnu; march="-march=rv64gc -mabi=lp64d" ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target $march -I"$root/include" -I"$root/platform/linux" \
    -c "$root/asm/core/$isa/rlp.s" -o "$out/rlp.o"
llvm-ar rcsD "$out/libasm-rlp.a.new" "$out/rlp.o"
mv "$out/libasm-rlp.a.new" "$out/libasm-rlp.a"

# Test runner (C), linked statically so QEMU user mode needs no target libraries.
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/runner/runner.c" "$out/libasm-rlp.a" -o "$out/runner"

# Bench (C), linked the same way.
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/bench/bench.c" "$out/libasm-rlp.a" -o "$out/bench"
