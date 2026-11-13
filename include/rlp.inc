/*
 * asm-rlp shared definitions, in assembler syntax.
 * Every core file includes this file with .include.
 * Functions and layouts are described in docs/reference/rlp.md.
 */

/* ---------------------------------------------------------------- Status codes */

/* ARCHITECTURE.md section 6. */
.set RLP_OK, 0
.set RLP_BUFFER_TOO_SMALL, 1

/* Decode refusals. Each one is a DecodingError of ethereum-rlp v0.1.6. */
.set RLP_EMPTY, 2                  /* "Cannot decode empty bytestring" */
.set RLP_TRUNCATED, 3              /* "truncated" */
.set RLP_TRAILING_BYTES, 4         /* "trailing bytes" */
.set RLP_NEGATIVE_LENGTH, 5        /* "negative length" */
.set RLP_NON_CANONICAL, 6          /* DecodingError with no message */

/* ---------------------------------------------------------------- Item kinds */

.set RLP_KIND_BYTES, 1
.set RLP_KIND_LIST, 2

/* ---------------------------------------------------------------- ByteList */

.set RLP_BL_SIZE, 0                /* total buffer size in bytes */
.set RLP_BL_OFFSET, 8              /* where the bytes start, from the buffer start */
.set RLP_BL_COUNT, 16              /* number of bytes in use */
.set RLP_BL_FIXED, 24              /* end of the fixed fields */

/* ---------------------------------------------------------------- Items */

.set RLP_ITEMS_SIZE, 0             /* total buffer size in bytes */
.set RLP_ITEMS_OFFSET, 8           /* where the Item records start, from the buffer start */
.set RLP_ITEMS_COUNT, 16           /* number of Item records */
.set RLP_ITEMS_FIXED, 24           /* end of the fixed fields */

/* Item record, 32 bytes. */
.set RLP_ITEM_KIND, 0              /* RLP_KIND_BYTES or RLP_KIND_LIST */
.set RLP_ITEM_OFFSET, 8            /* where its payload starts in the data bytes */
.set RLP_ITEM_LENGTH, 16           /* payload length in bytes */
.set RLP_ITEM_ITEMS, 24            /* items in its subtree, itself included */
.set RLP_ITEM_STRIDE, 32
.set RLP_ITEM_SHIFT, 5             /* log2 of RLP_ITEM_STRIDE */

/* ---------------------------------------------------------------- Scratch */

.set RLP_SCRATCH_SIZE, 0           /* total buffer size in bytes */
.set RLP_SCRATCH_LENGTHS, 8        /* u64 encoded length of each item, in item order */

/* ---------------------------------------------------------------- Encoding */

.set RLP_SHORT_BYTES, 0x80         /* first byte of a byte string of 0 to 55 bytes */
.set RLP_LONG_BYTES, 0xB7          /* plus the length of the length: a longer byte string */
.set RLP_SHORT_LIST, 0xC0          /* first byte of a list with 0 to 55 payload bytes */
.set RLP_LONG_LIST, 0xF7           /* plus the length of the length: a longer list */
.set RLP_SHORT_MAX, 55             /* longest payload with a one byte header */
