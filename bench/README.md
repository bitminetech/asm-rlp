# Bench

`bench.c` times each public function of the library on a fixed workload. It is benchmark code in C. The library is assembly.

## Run

```bash
bench/docker.sh ~/.cache/asm-rlp/vectors
```

```bash
bench/macos.sh ~/.cache/asm-rlp/vectors > results.txt
```

```bash
build/macos-arm64/bench compare base.txt new.txt
```

- Make the vectors first with [tests/generator/run.sh](../tests/generator/run.sh).
- `bench run VECTOR_DIR` prints the results.
- `bench run VECTOR_DIR --quick` takes 3 samples of one call each. It checks that the bench works, and its times are not measurements.

## Files

| File | What it does |
|---|---|
| `bench.c` | `bench run` and `bench compare` |
| `docker.sh` | Builds all 7 targets in Docker, then runs the bench on the three Linux ISAs |
| `macos.sh` | Links the bench on a Mac against the library that `docker.sh` built, then runs it |

- `docker.sh` runs the full bench for the host's own ISA, and `--quick` for the other Linux ISAs under QEMU user mode.
- [.github/workflows/ci.yml](../.github/workflows/ci.yml) runs the bench on all 7 targets and keeps each run's results as an artifact, `bench-<os>-<isa>`.

## Workload

| Case | File | What it is |
|---|---|---|
| `enr_shaped` | `generated-valid.bin` | An ENR record with the keys a consensus client sets |
| `discv5_nodes_shaped` | `generated-valid.bin` | A discv5 NODES message with 16 such records |
| `dictTest1` | `rlptests-valid.bin` | A small list of key and value pairs |
| `longList2` | `rlptests-valid.bin` | A list of 32 lists |
| `longstring2` | `rlptests-valid.bin` | A 1024 byte string |
| `nested_content_1000` | `generated-valid.bin` | Lists nested 1000 levels deep |
| `bytes_len_65536` | `generated-valid.bin` | A 65536 byte string |
| `list_payload_65536` | `generated-valid.bin` | A list of 65536 one byte strings |

- Each case times `rlp_decode`, `rlp_encode_size` and `rlp_encode`.
- Each call is checked against its case before it is timed.

## Timing

- One sample repeats a call for about 2 ms.
- Each call gets 21 samples: 3 rounds of 7. A round times every call once, so drift between rounds shows in the spread.
- The timed thread asks for one fast core: the highest QoS class on macOS, and its current core on Linux and Windows.
- Clocks: `CLOCK_UPTIME_RAW` on macOS, `CLOCK_MONOTONIC` on Linux, `QueryPerformanceCounter` on Windows.

## Results

| Line | Content |
|---|---|
| `os`, `isa`, `cpu` | The machine. `cpu` is the name the OS reports. |
| `samples` | Samples for each call, and `quick` for a `--quick` run |
| `file` | A workload file and its SHA-256, from `manifest.txt` |
| `function case bytes calls p25_ns median_ns p75_ns` | The column names, then one row for each timed call |

- `bytes`: the length of the encoding.
- `calls`: calls in one sample.
- `p25_ns`, `median_ns`, `p75_ns`: ns per call at the 25th, 50th and 75th percentile of the samples.

## Compare

- `bench compare BASE NEW` refuses two runs whose `os`, `isa`, `cpu` or workload files differ.
- `faster`: the 75th percentile of NEW is below the 25th of BASE, and the median of BASE is at least 3% above that of NEW.
- `slower`: the same, the other way round.
- `within noise`: anything else.
- Run BASE and NEW on the same machine, one after the other.
