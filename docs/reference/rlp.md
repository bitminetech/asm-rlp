# RLP

## Contents

### Functions

- [`rlp_decode`](#function-rlp_decode): reads an RLP encoding into records.
- [`rlp_encode_size`](#function-rlp_encode_size): gives the buffer size that `rlp_encode` needs.
- [`rlp_encode`](#function-rlp_encode): writes the RLP encoding of records.
- [`rlp_measure`](#function-rlp_measure): finds the encoded length of every record.

### Types

- [`Items`](#type-items): an RLP value in memory, as records.
- [`Item`](#type-item): one byte string or list.
- [`ByteList`](#type-bytelist): a byte string with a header.
- [`Scratch`](#type-scratch): workspace for one call.

## Spec

- Document: [ethereum-rlp v0.1.6, `rlp.py`](https://github.com/ethereum/ethereum-rlp/blob/9067c50e696a6dbd604a5db6fd1b1aa144792806/src/ethereum_rlp/rlp.py).
- Section: `encode` and `decode` of `Simple` values: byte strings and lists of them.

## Function `rlp_decode`

Reads an RLP encoding into records.

### Signature

```
rlp_decode(encoded, items) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `encoded` | input | `ByteList` |
| `items` | output | `Items` |

### Returns

- `RLP_OK`: the encoding is valid and `items` holds its records.
- A decode refusal constant from [include/rlp.inc](../../include/rlp.inc): the encoding breaks a v0.1.6 rule. It names the first fault that v0.1.6 `decode` raises.
- `RLP_BUFFER_TOO_SMALL`: `items` has no room for the next record, and no fault was found before it.
- After any status other than `RLP_OK`, `items` is invalid.

### Caller must

- Pass a valid `ByteList` header in `encoded`. The bytes in it can be anything.
- Set the `size` field of `items` to its buffer size.
- Keep `items` apart from `encoded`.
- Keep `encoded` while it uses the records. They give positions in it.

### Function does

- Accepts exactly the encodings that v0.1.6 `decode` accepts.
- Checks each byte of the encoding before it uses it.
- Reads the encoding once, from start to end.
- Writes one `Item` for each byte string and list, in pre-order.
- Gives each record's `offset` as a position in the bytes of `encoded`.
- Sets `offset` of `items` to 24 and `count` to the number of records.
- Keeps the `size` field of `items`.
- Stops at the first fault, or at the first record that does not fit.

### Function never

- Reads outside the `ByteList` header and its `count` bytes.
- Writes outside `items` and its own stack.
- Copies the bytes of a byte string.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `items`: 24 + 32 × the number of records.
- `items` of 24 + 32 × the `count` of `encoded` is always enough. Every item takes at least one byte.
- Nesting depth: any. The stack use does not grow with depth.
- Stack: 56 bytes on x86-64, return address included, and none on ARM64 and RISC-V.

### ABI

- Role: L2.
- Symbol: `rlp_decode` (`_rlp_decode` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `encoded`, `items`.

## Function `rlp_encode_size`

Gives the buffer size that `rlp_encode` needs for records.

### Signature

```
rlp_encode_size(items, data, scratch, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `items` | input | `Items` |
| `data` | input | `ByteList` |
| `scratch` | scratch | `Scratch` |
| `size` | output | u64 |

### Returns

- `RLP_OK`: `size` holds the buffer size.
- `RLP_BUFFER_TOO_SMALL`: `scratch` is too small.

### Caller must

- Pass a valid `Items` value in `items`. It is not checked.
- Pass the bytes of every byte string record in `data`.
- Set the `size` field of `scratch` to its buffer size.
- Keep `size` and `scratch` apart from each other and from the inputs.

### Function does

- Writes 24 plus the length of the RLP encoding of `items` to `size`.

### Function never

- Uses the `offset` and `length` of a list record. They can hold anything.
- Writes outside `size`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `scratch`: 8 + 8 × the number of records.
- Stack: 40 bytes on x86-64, return addresses included, 32 on ARM64 and 32 on RISC-V.

### ABI

- Role: L2.
- Symbol: `rlp_encode_size` (`_rlp_encode_size` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `items`, `data`, `scratch`, `size`.

## Function `rlp_encode`

Writes the RLP encoding of records.

### Signature

```
rlp_encode(items, data, scratch, encoded) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `items` | input | `Items` |
| `data` | input | `ByteList` |
| `scratch` | scratch | `Scratch` |
| `encoded` | output | `ByteList` |

### Returns

- `RLP_OK`: `encoded` holds the encoding.
- `RLP_BUFFER_TOO_SMALL`: `scratch` or `encoded` is too small. `encoded` is then invalid.

### Caller must

- Pass a valid `Items` value in `items`. It is not checked.
- Pass the bytes of every byte string record in `data`.
- Set the `size` field of `encoded` and of `scratch` to their buffer sizes.
- Keep `encoded` and `scratch` apart from each other and from the inputs.

### Function does

- Checks `scratch`, then `encoded`.
- Writes the encoding that v0.1.6 `encode` gives for the byte strings and lists of `items`.
- Writes one byte below 0x80 as itself.
- Sets `offset` of `encoded` to 24 and `count` to the encoding length.
- Keeps the `size` field of `encoded`.

### Function never

- Uses the `offset` and `length` of a list record. They can hold anything.
- Writes outside `encoded`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `encoded`: the size that `rlp_encode_size` gives.
- `scratch`: 8 + 8 × the number of records.
- Stack: 72 bytes on x86-64, return addresses included, 48 on ARM64 and 48 on RISC-V.

### ABI

- Role: L2.
- Symbol: `rlp_encode` (`_rlp_encode` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `items`, `data`, `scratch`, `encoded`.

## Function `rlp_measure`

Finds the encoded length of every record.

### Signature

```
rlp_measure(items, data, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `items` | input | `Items` |
| `data` | input | `ByteList` |
| `scratch` | scratch | `Scratch` |

### Returns

- `RLP_OK`: `scratch` holds the length of every record.
- `RLP_BUFFER_TOO_SMALL`: `scratch` is too small.

### Caller must

- Pass a valid `Items` value in `items`.
- Pass the bytes of every byte string record in `data`.
- Set the `size` field of `scratch` to its buffer size.

### Function does

- Walks the records from last to first, so each list finds its children's lengths ready.
- Writes the RLP encoding length of record `i` to entry `i` of `lengths` in `scratch`.

### Function never

- Writes outside `scratch`.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack of its own: none. On x86-64 the call adds its 8 byte return address.

### ABI

- Role: L0.
- Symbol: `rlp_measure`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `items`, `data`, `scratch`.

## Type `Items`

An RLP value in memory: one `Item` record for each byte string and list.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes |
| 8 | `offset` | u64 | Where the records start, from the buffer start |
| 16 | `count` | u64 | Number of records |

### Rules

- The buffer starts at a multiple of 8.
- `offset` is at least 24 and a multiple of 8.
- `offset + 32 × count` is at most `size`.
- The records are in pre-order: a list comes before its children.
- The first record is the whole value.
- The first child of the list at index `i` is at index `i + 1`.
- Each next child is at the index of the one before plus that one's `items`.
- Valid when these rules hold, `count` is at least 1, and the `items` of the first record is `count`.

## Type `Item`

One byte string or list.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `RLP_KIND_BYTES` or `RLP_KIND_LIST` |
| 8 | `offset` | u64 | Where its payload starts in the data bytes |
| 16 | `length` | u64 | Payload length in bytes |
| 24 | `items` | u64 | Records in its subtree, itself included |

### Rules

- 32 bytes.
- The payload of a byte string is the string.
- The payload of a list is the encodings of its children.
- A byte string has `items` 1.
- A one byte string below 0x80 is encoded as that byte, so its `offset` is that byte.

## Type `ByteList`

A byte string with a 24 byte header.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes |
| 8 | `offset` | u64 | Where the bytes start, from the buffer start |
| 16 | `count` | u64 | Number of bytes in use |

### Rules

- The buffer starts at a multiple of 8.
- `offset` is at least 24 and a multiple of 8.
- `offset + count` is at most `size`.
- Bytes after `count` are unused. Functions do not read them.

## Type `Scratch`

Workspace for one call.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes, this field included |
| 8 | `lengths` | u64 for each record | The encoded length of each record |

### Rules

- The buffer starts at a multiple of 8.
- The caller sets only `size`. The rest is workspace.
- The old contents of the workspace do not change any result.

## Test vectors

- ethereum/tests v17.2, `RLPTests`.
  - Commit: [c67e485](https://github.com/ethereum/tests/tree/c67e485ff8b5be9abc8ad15345ec21aa22e290d9/RLPTests)
  - `rlptest.json`, SHA-256: `dd11055db749a21d8ee7aae7810ac30d19a89e2c6dadba9967f7bd567ad5fc00`
  - `invalidRLPTest.json`, SHA-256: `f90bf5745d21bfa7fbfeabaf5b6d1c66bae10051b1c0a054eecd424d488385d7`
  - `RandomRLPTests/example.json`, SHA-256: `1000fba8f0b749abb16af29a44ef0ab13b54b5ef35a93088d2c6988c8adfbe7f`
  - Check: v0.1.6 `encode` of each valid `in` gives its `out`.
  - Expected records: v0.1.6 `decode` of `out`.
  - Expected refusals: the constant of the `DecodingError` that v0.1.6 `decode` raises.
- Generated vectors: [tests/generator/generate.py](../../tests/generator/generate.py).
  - Inputs: byte strings and lists at every header boundary, nesting up to 3000 levels, ENR and discv5 shaped values, 3000 random values, crafted refusals, and cut, extended and one byte changed copies of small encodings.
  - Expected results: v0.1.6 `decode`, and v0.1.6 `encode` of what it decodes.
  - Every decode refusal constant has cases.
  - Nesting stops at 3000 levels: v0.1.6 fails with a `RecursionError` at 4000 levels in Python 3.13.

## Results

<!-- CI generates the tick table for each function here. -->

### `rlp_decode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `rlp_encode_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `rlp_encode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `rlp_measure`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
