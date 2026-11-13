# Test runner

`runner.c` reads the case files from [tests/generator/](../generator/), calls the library for every case and compares the results. It is test code in C. The library is assembly.

## Run

```bash
tests/runner/docker.sh ~/.cache/asm-rlp/vectors
```

```bash
tests/runner/macos.sh ~/.cache/asm-rlp/vectors
```

- Make the vectors first with [tests/generator/run.sh](../generator/run.sh).
- Add file names after the folder to run only those files.

## Files

| File | What it does |
|---|---|
| `runner.c` | Runs the cases: `runner VECTOR_DIR FILE ...` |
| `abi_x86_64.s`, `abi_arm64.s`, `abi_riscv64.s` | `abi_call`, through which the runner makes every library call. Test code in assembly. |
| `docker.sh` | Builds all 7 targets in Docker, then runs every file on Linux x86-64, ARM64 and RISC-V |
| `macos.sh` | Links the runner on a Mac against the library that `docker.sh` built, then runs every file |
| `tick_tables.py` | Writes the tick table of each function into its document, from the results of every target |

- Linux ISAs other than the host's run under QEMU user mode.
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml) runs every file on all 7 targets.

## Checks

| Case | Check |
|---|---|
| Valid | `rlp_decode` writes exactly the expected records |
| Valid | `rlp_decode` with room for one record less returns `RLP_BUFFER_TOO_SMALL` |
| Valid | `rlp_encode_size` and `rlp_encode` of the records give the encoding back |
| Valid | The same, with the records at another offset, the byte strings copied elsewhere and junk in each list's `offset` and `length` |
| Valid | A scratch one entry short, or an output one byte short, returns `RLP_BUFFER_TOO_SMALL` |
| Reject | `rlp_decode` returns the expected refusal |

| Check | Fails when |
|---|---|
| Buffers | A function writes into the 64 guard bytes after any buffer |
| Stack | A call uses more than the README stack cap |
| ABI | A call changes state that the ABI says it must keep |

- Output and scratch buffers start filled with `0xA5`.
- `abi_call` paints the stack below each call. After the call, the lowest word that changed gives the stack used, the return address included on x86-64.
- The runner prints the most stack each function used.

## ABI check

- The runner makes every library call through `abi_call`.
- Before the call, `abi_call` sets each register that the callee must keep to a known value, and paints the stack below the call.
- After the call, it records the status, the kept state that changed, and the bytes of stack the call used.
- It then puts the stack pointer, the flags and the floating point control state back, so a fault fails only its function.

| ISA | Kept state it checks |
|---|---|
| x86-64 | `rbx`, `rbp`, `r12` to `r15`, `rsp`, the direction flag, `mxcsr`, the x87 control word |
| ARM64 | `x19` to `x29`, `sp`, `d8` to `d15`, `fpcr` |
| RISC-V | `s0` to `s11`, `sp`, `fs0` to `fs11`, `gp`, `tp` |

A failure prints a mask with one bit for each changed item:

- x86-64: bits 0 to 5 are `rbx`, `rbp`, `r12`, `r13`, `r14` and `r15`. Bit 60 is the x87 control word, bit 61 `mxcsr`, bit 62 the direction flag and bit 63 `rsp`.
- ARM64: bits 0 to 9 are `x19` to `x28`, and bit 10 `x29`. Bits 11 to 18 are `d8` to `d15`. Bit 61 is `fpcr` and bit 63 `sp`.
- RISC-V: bits 0 to 11 are `s0` to `s11`, and bits 12 to 23 `fs0` to `fs11`. Bit 24 is `gp`, bit 25 `tp` and bit 63 `sp`.

The record that `abi_call` reads and writes:

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `fn` | u64 | Address of the function to call |
| 8 | `arg` | 5 u64 | The arguments |
| 48 | `paint` | u64 | Bytes of stack to paint below the call, a multiple of 8 |
| 56 | `status` | u64 | The status the call returned |
| 64 | `fault` | u64 | The mask of kept state that changed |
| 72 | `stack` | u64 | Bytes of stack the call used |
| 80 | `scratch` | 32 bytes | Workspace for `abi_call` |

## Results

- The runner prints one line for each function: `FUNCTION <name> PASS` or `FUNCTION <name> FAIL`.
- `PASS`: every file with cases for the function passed, and the function stayed within the stack cap and kept what the ABI says it must.
- Valid files test `rlp_decode`, `rlp_encode_size` and `rlp_encode`. Reject files test `rlp_decode`.

## Tick tables

- CI runs `tick_tables.py` after the tests of all 7 targets.
- An OS cell gets ✅ when the runner of that target printed `PASS` for the function.
- `rlp_measure` has no cases of its own. It gets ✅ when every L2 function that calls it got ✅ on that target.
- The calls come from `build/linux-<ISA>/calls.txt`, which [platform/check.py](../../platform/check.py) writes.
- The `equal` cells stay empty: CI checks no proofs.
- On a push to `main`, CI commits the tables when they change.
