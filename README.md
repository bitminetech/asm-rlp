# asm-rlp

Recursive-Length Prefix (RLP) for Ethereum, in assembly.

Standard: [asm-standard@2a19d3f](https://github.com/bitminetech/asm-standard/blob/2a19d3f7fa737af1c01720b6e891703e53a682aa/ARCHITECTURE.md)

## Reference

| File | Covers |
|---|---|
| [docs/reference/rlp.md](docs/reference/rlp.md) | Encode and decode |
| [include/rlp.inc](include/rlp.inc) | Constants |

## Targets

| OS | ISAs |
|---|---|
| Linux | x86-64, ARM64, RISC-V |
| Windows | x86-64, ARM64 |
| macOS | x86-64, ARM64 |

## Build tools

| Used for | Tool |
|---|---|
| Library | LLVM 23.1.5, official release (`clang`, `llvm-ar`, `lld`) |
| Windows test runner and bench | [llvm-mingw 20261104](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104) (LLVM 23.1.5) |
| macOS test runner and bench | The host Xcode clang, because it needs the macOS SDK |
| Build image | [platform/linux/Dockerfile](platform/linux/Dockerfile) on `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` |

## Tests

| Item | Location |
|---|---|
| Vector generator | [tests/generator/](tests/generator/) |
| Test runner | [tests/runner/](tests/runner/) |
| Bench | [bench/](bench/) |

## Target profile

| ISA | Instructions |
|---|---|
| x86-64 | x86-64-v1 |
| ARM64 | Armv8.0-A |
| RISC-V | RV64GC |

| Item | Value |
|---|---|
| macOS objects | Marked for macOS 11.0 or later |

## Stack

| Item | Value |
|---|---|
| Stack per call | At most 128 bytes, callees included |

## Benchmark machines

| ISA | CPU |
|---|---|
| x86-64 | The CPU of the GitHub runners `ubuntu-24.04`, `windows-2025` and `macos-15-intel`. Each bench run prints it. |
| ARM64 | The CPU of the GitHub runners `ubuntu-24.04-arm`, `windows-11-arm` and `macos-15`, and Apple M series Macs. Each bench run prints it. |
| RISC-V | Run only, under QEMU on `ubuntu-24.04-arm`. Its times are not measurements. |
