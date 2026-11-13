#!/bin/sh
# Build every target in Docker, then run the bench for the three Linux ISAs.
# Usage: bench/docker.sh VECTOR_DIR
#
# The host's own ISA runs the full bench. The other Linux ISAs run under QEMU
# user mode with --quick: that checks the bench works there, and its times
# are not measurements.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
vectors=$(cd "$1" && pwd)
image=asm-rlp-build

docker build -q -t "$image" -f "$root/platform/linux/Dockerfile" "$root/platform/linux" >/dev/null
docker run --rm -v "$root:/src" -v "$vectors:/vectors:ro" "$image" sh -eu -c '
    platform/build-all.sh
    host=$(uname -m)
    for isa in x86_64 arm64 riscv64; do
        case $isa in
          x86_64)  machine=x86_64;  qemu=qemu-x86_64 ;;
          arm64)   machine=aarch64; qemu=qemu-aarch64 ;;
          riscv64) machine=riscv64; qemu=qemu-riscv64 ;;
        esac
        mode=""
        if [ "$machine" = "$host" ]; then qemu=""; else mode=--quick; fi
        echo "== linux $isa${qemu:+ (under $qemu, run only)}"
        $qemu build/linux-$isa/bench run /vectors $mode
    done
'
