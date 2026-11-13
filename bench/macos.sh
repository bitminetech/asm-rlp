#!/bin/sh
# Run the bench on this Mac, against the library that bench/docker.sh or
# tests/runner/docker.sh built with the pinned LLVM.
# Usage: bench/macos.sh VECTOR_DIR [--quick]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
vectors=$1
shift
case "$(uname -m)" in
  arm64)  isa=arm64 ;;
  x86_64) isa=x86_64 ;;
  *) echo "unsupported Mac: $(uname -m)" >&2; exit 2 ;;
esac
"$root/platform/macos/link-bench.sh" $isa "$root/build/macos-$isa"
"$root/build/macos-$isa/bench" run "$vectors" "$@"
