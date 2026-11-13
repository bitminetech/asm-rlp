# Vector generator

## Run

```bash
tests/generator/run.sh ~/.cache/asm-rlp/vectors
```

- The output folder must be outside this repo.
- It runs in the image from [platform/linux/Dockerfile](../../platform/linux/Dockerfile).
- The output folder keeps the downloads and the Python environment. A second run downloads nothing.

## Files

| File | What it holds |
|---|---|
| `run.sh` | Runs the generator in Docker |
| `generate.py` | Fetches the RLPTests files, checks their pins, makes the generated cases, writes the case files |
| `requirements.txt` | Python packages, pinned by version and hash |

## Output

| File | Cases |
|---|---|
| `rlptests-valid.bin` | Valid encodings from `rlptest.json` and `RandomRLPTests/example.json` |
| `rlptests-reject.bin` | Encodings from `invalidRLPTest.json`, with the expected refusal |
| `generated-valid.bin` | Generated encodings that ethereum-rlp v0.1.6 accepts |
| `generated-reject.bin` | Generated encodings that ethereum-rlp v0.1.6 rejects, with the expected refusal |
| `manifest.txt` | Each file, its case count and its SHA-256 |

## File format

| Part | Content |
|---|---|
| Magic | The 8 bytes `RLPVEC01` |
| Kind | u64: 1 valid, 2 reject |
| Cases | u64 count, then each case |

- u64 is 8 bytes, little endian.
- A blob is a u64 length, then that many bytes.
- Each case starts with its name as a blob, then the encoding as a blob.

| Kind | Rest of a case |
|---|---|
| 1, valid | A u64 record count, then each `Item` record that `rlp_decode` must write, as four u64 |
| 2, reject | The u64 expected status |
