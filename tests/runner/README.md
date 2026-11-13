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
| `docker.sh` | Builds all 7 targets in Docker, then runs every file on Linux x86-64, ARM64 and RISC-V |
| `macos.sh` | Links the runner on a Mac against the library that `docker.sh` built, then runs every file |

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

- Output and scratch buffers start filled with `0xA5`.
- The stack check fills the stack below the caller with a pattern before each call. After the call, it finds the lowest byte that changed.
- The runner prints the most stack each function used.
