/*
 * asm-rlp for ARM64 (AAPCS64).
 * Requirements: docs/reference/rlp.md. Layouts: include/rlp.inc.
 *
 * Every function follows AAPCS64: pointer arguments, status in x0.
 * x18 is never used. rlp_decode and rlp_measure are leaves.
 * rlp_encode_size and rlp_encode keep an x29 frame record.
 */
.set ISA_ARM64, 1
.include "rlp.inc"
.include "platform.inc"

/* dst = bytes in the RLP header for a length x: 1 below 56, else 1 + bytes of x. */
.macro HEADER_SIZE dst, x
    clz     \dst, \x
    neg     \dst, \dst
    add     \dst, \dst, #(64 + 7)
    lsr     \dst, \dst, #3
    add     \dst, \dst, #1
    cmp     \x, #(RLP_SHORT_MAX + 1)
    csinc   \dst, \dst, xzr, hs
.endm

/*
 * rlp_decode(encoded, items). A leaf: x0-x17 only.
 * x2 bytes, x3 byte count, x4 first record, x5 records that fit, x6 records
 * written, x7 position, x8 end of the current list (or of the encoding),
 * x9 open list (-1 for none), x10 1 for the first item, x11 bytes left.
 * While a list is open, its items field holds the index of its parent.
 */
FUNCTION rlp_decode
    UNWIND_END_PROLOGUE
    ldr     x2, [x0, #RLP_BL_OFFSET]
    add     x2, x0, x2
    ldr     x3, [x0, #RLP_BL_COUNT]
    cbz     x3, 90f
    add     x4, x1, #RLP_ITEMS_FIXED
    ldr     x5, [x1, #RLP_ITEMS_SIZE]
    subs    x5, x5, #RLP_ITEMS_FIXED
    csel    x5, xzr, x5, lo
    lsr     x5, x5, #RLP_ITEM_SHIFT
    mov     x6, #0
    mov     x7, #0
    mov     x8, x3
    mov     x9, #-1
    mov     x10, #1

    /* The item at x7, with x11 bytes left in its list. */
1:  sub     x11, x8, x7
    ldrb    w12, [x2, x7]
    cmp     x12, #RLP_SHORT_BYTES
    b.hs    2f
    /* One byte below 0x80: the byte itself. */
    cbz     x10, 11f
    cmp     x11, #1
    b.ne    95f                         /* top level, more bytes follow */
11: mov     x13, #1
    mov     x15, x7
    add     x16, x7, #1
    b       30f

2:  cmp     x12, #RLP_LONG_BYTES
    b.hi    3f
    /* Byte string of 0 to 55 bytes. */
    sub     x13, x12, #RLP_SHORT_BYTES
    cmp     x13, x11
    b.hs    92f                         /* 1 + length > bytes left */
    cbz     x10, 21f
    add     x14, x13, #1
    cmp     x14, x11
    b.lo    93f                         /* top level, bytes after it */
21: cmp     x13, #1
    b.ne    22f
    add     x14, x7, #1
    ldrb    w14, [x2, x14]
    cmp     x14, #RLP_SHORT_BYTES
    b.lo    96f                         /* one byte below 0x80 with a header */
22: add     x15, x7, #1
    add     x16, x15, x13
    b       30f

3:  cmp     x12, #(RLP_LONG_BYTES + 8)
    b.hi    4f
    sub     x14, x12, #RLP_LONG_BYTES
    mov     x17, #RLP_KIND_BYTES
    b       50f

4:  cmp     x12, #RLP_LONG_LIST
    b.hi    5f
    /* List with 0 to 55 payload bytes. */
    sub     x13, x12, #RLP_SHORT_LIST
    cmp     x13, x11
    b.hs    92f
    cbz     x10, 41f
    add     x14, x13, #1
    cmp     x14, x11
    b.lo    93f
41: add     x15, x7, #1
    b       40f

5:  sub     x14, x12, #RLP_LONG_LIST
    mov     x17, #RLP_KIND_LIST

    /* Long form: x14 bytes of length follow the first byte. x17 is the kind. */
50: cmp     x14, x11
    b.hs    92f                         /* the length does not fit */
    add     x15, x7, #1
    ldrb    w16, [x2, x15]
    cbz     x16, 96f                    /* the length starts with a zero byte */
    add     x16, x2, x15
    mov     x13, #0
    mov     x12, x14
51: lsl     x13, x13, #8
    ldrb    w0, [x16], #1
    orr     x13, x13, x0
    subs    x12, x12, #1
    b.ne    51b
    add     x15, x15, x14               /* payload start */
    cbz     x10, 52f
    cmp     x13, #(RLP_SHORT_MAX + 1)
    b.lo    96f                         /* top level: short length in long form */
52: sub     x16, x11, #1
    sub     x16, x16, x14               /* bytes left after the header */
    cmp     x13, x16
    b.hi    92f
    cbz     x10, 53f
    b.lo    93f
53: cmp     x13, #(RLP_SHORT_MAX + 1)
    b.lo    96f                         /* short length in long form */
    cmp     x17, #RLP_KIND_LIST
    b.eq    40f
    add     x16, x15, x13

    /* A byte string: payload at x15, x13 bytes, next item at x16. */
30: cmp     x6, x5
    b.hs    91f
    add     x17, x4, x6, lsl #RLP_ITEM_SHIFT
    mov     x12, #RLP_KIND_BYTES
    mov     x14, #1
    stp     x12, x15, [x17, #RLP_ITEM_KIND]
    stp     x13, x14, [x17, #RLP_ITEM_LENGTH]
    add     x6, x6, #1
    mov     x7, x16
    b       60f

    /* A list: payload at x15, x13 bytes. It becomes the open list. */
40: cmp     x6, x5
    b.hs    91f
    add     x17, x4, x6, lsl #RLP_ITEM_SHIFT
    mov     x12, #RLP_KIND_LIST
    stp     x12, x15, [x17, #RLP_ITEM_KIND]
    stp     x13, x9, [x17, #RLP_ITEM_LENGTH]
    mov     x9, x6
    add     x6, x6, #1
    mov     x7, x15
    add     x8, x15, x13

    /* Close every list that ends here. */
60: mov     x10, #0
61: cmp     x7, x8
    b.ne    1b
    cmn     x9, #1
    b.eq    70f
    add     x17, x4, x9, lsl #RLP_ITEM_SHIFT
    ldr     x12, [x17, #RLP_ITEM_ITEMS]
    sub     x14, x6, x9
    str     x14, [x17, #RLP_ITEM_ITEMS]
    mov     x9, x12
    cmn     x9, #1
    b.eq    70f
    add     x17, x4, x9, lsl #RLP_ITEM_SHIFT
    ldp     x15, x13, [x17, #RLP_ITEM_OFFSET]
    add     x8, x15, x13
    b       61b

70: mov     x12, #RLP_ITEMS_FIXED
    stp     x12, x6, [x1, #RLP_ITEMS_OFFSET]
    mov     x0, #RLP_OK
    ret
90: mov     x0, #RLP_EMPTY
    ret
91: mov     x0, #RLP_BUFFER_TOO_SMALL
    ret
92: mov     x0, #RLP_TRUNCATED
    ret
93: mov     x0, #RLP_TRAILING_BYTES
    ret
95: mov     x0, #RLP_NEGATIVE_LENGTH
    ret
96: mov     x0, #RLP_NON_CANONICAL
    ret
END_FUNCTION rlp_decode

/*
 * rlp_measure(items, data, scratch). A leaf: x0-x17 only.
 * Writes the encoded length of every item to scratch, last item first.
 * x3 first record, x4 record count, x5 data bytes, x6 lengths, x7 item.
 */
LOCAL_FUNCTION rlp_measure
    UNWIND_END_PROLOGUE
    ldr     x3, [x0, #RLP_ITEMS_OFFSET]
    add     x3, x0, x3
    ldr     x4, [x0, #RLP_ITEMS_COUNT]
    ldr     x5, [x1, #RLP_BL_OFFSET]
    add     x5, x1, x5
    ldr     x6, [x2, #RLP_SCRATCH_SIZE]
    lsl     x7, x4, #3
    add     x7, x7, #RLP_SCRATCH_LENGTHS
    cmp     x6, x7
    b.lo    91f
    add     x6, x2, #RLP_SCRATCH_LENGTHS
    mov     x7, x4
1:  cbz     x7, 9f
    sub     x7, x7, #1
    add     x8, x3, x7, lsl #RLP_ITEM_SHIFT
    ldp     x9, x10, [x8, #RLP_ITEM_KIND]
    cmp     x9, #RLP_KIND_BYTES
    b.ne    3f
    /* Byte string: 1 for one byte below 0x80, else header and bytes. */
    ldr     x11, [x8, #RLP_ITEM_LENGTH]
    cmp     x11, #1
    b.ne    2f
    ldrb    w12, [x5, x10]
    cmp     x12, #RLP_SHORT_BYTES
    b.hs    2f
    mov     x13, #1
    b       5f
2:  HEADER_SIZE x14, x11
    add     x13, x14, x11
    b       5f
    /* List: header and the encoded lengths of its children. */
3:  ldr     x11, [x8, #RLP_ITEM_ITEMS]
    add     x11, x11, x7
    add     x12, x7, #1
    mov     x13, #0
4:  cmp     x12, x11
    b.hs    6f
    ldr     x14, [x6, x12, lsl #3]
    add     x13, x13, x14
    add     x15, x3, x12, lsl #RLP_ITEM_SHIFT
    ldr     x15, [x15, #RLP_ITEM_ITEMS]
    add     x12, x12, x15
    b       4b
6:  HEADER_SIZE x14, x13
    add     x13, x13, x14
5:  str     x13, [x6, x7, lsl #3]
    b       1b
9:  mov     x0, #RLP_OK
    ret
91: mov     x0, #RLP_BUFFER_TOO_SMALL
    ret
END_FUNCTION rlp_measure

/* rlp_encode_size(items, data, scratch, size). */
FUNCTION rlp_encode_size
    stp     x29, x30, [sp, #-32]!
    UNWIND_SAVE_FPLR_X 32
    mov     x29, sp
    UNWIND_SET_FP
    stp     x19, x20, [sp, #16]
    UNWIND_SAVE_REGP x19, x20, 16, 32
    UNWIND_END_PROLOGUE
    mov     x19, x2
    mov     x20, x3
    bl      rlp_measure
    cbnz    x0, 1f
    ldr     x9, [x19, #RLP_SCRATCH_LENGTHS]
    add     x9, x9, #RLP_BL_FIXED
    str     x9, [x20]
1:  UNWIND_BEGIN_EPILOGUE
    ldp     x19, x20, [sp, #16]
    UNWIND_RESTORE_REGP x19, x20, 16
    ldp     x29, x30, [sp], #32
    UNWIND_RESTORE_FPLR_X 32
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_encode_size

/*
 * rlp_encode(items, data, scratch, encoded).
 * After rlp_measure: x11 next output byte, x12 first record, x13 record count,
 * x14 data bytes, x15 lengths, x16 item.
 */
FUNCTION rlp_encode
    stp     x29, x30, [sp, #-48]!
    UNWIND_SAVE_FPLR_X 48
    mov     x29, sp
    UNWIND_SET_FP
    stp     x19, x20, [sp, #16]
    UNWIND_SAVE_REGP x19, x20, 16, 48
    stp     x21, x22, [sp, #32]
    UNWIND_SAVE_REGP x21, x22, 32, 48
    UNWIND_END_PROLOGUE
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    bl      rlp_measure
    cbnz    x0, 99f
    ldr     x9, [x21, #RLP_SCRATCH_LENGTHS]
    ldr     x10, [x22, #RLP_BL_SIZE]
    subs    x10, x10, #RLP_BL_FIXED
    b.lo    91f
    cmp     x10, x9
    b.lo    91f
    mov     x10, #RLP_BL_FIXED
    stp     x10, x9, [x22, #RLP_BL_OFFSET]
    add     x11, x22, #RLP_BL_FIXED
    ldr     x12, [x19, #RLP_ITEMS_OFFSET]
    add     x12, x19, x12
    ldr     x13, [x19, #RLP_ITEMS_COUNT]
    ldr     x14, [x20, #RLP_BL_OFFSET]
    add     x14, x20, x14
    add     x15, x21, #RLP_SCRATCH_LENGTHS
    mov     x16, #0

1:  cmp     x16, x13
    b.hs    90f
    add     x17, x12, x16, lsl #RLP_ITEM_SHIFT
    ldp     x2, x3, [x17, #RLP_ITEM_KIND]
    cmp     x2, #RLP_KIND_BYTES
    b.ne    5f
    /* Byte string: x3 its bytes, x4 its length. */
    ldr     x4, [x17, #RLP_ITEM_LENGTH]
    add     x3, x14, x3
    cmp     x4, #1
    b.ne    2f
    ldrb    w5, [x3]
    cmp     x5, #RLP_SHORT_BYTES
    b.hs    2f
    strb    w5, [x11], #1
    b       8f
2:  cmp     x4, #(RLP_SHORT_MAX + 1)
    b.hs    21f
    add     x5, x4, #RLP_SHORT_BYTES
    strb    w5, [x11], #1
    b       3f
21: clz     x5, x4
    neg     x5, x5
    add     x5, x5, #(64 + 7)
    lsr     x5, x5, #3                  /* bytes of the length */
    add     x6, x5, #RLP_LONG_BYTES
    strb    w6, [x11], #1
    lsl     x6, x5, #3
22: sub     x6, x6, #8
    lsr     x7, x4, x6
    strb    w7, [x11], #1
    cbnz    x6, 22b
3:  cmp     x4, #8
    b.lo    4f
    ldr     x5, [x3], #8
    str     x5, [x11], #8
    sub     x4, x4, #8
    b       3b
4:  cbz     x4, 8f
    ldrb    w5, [x3], #1
    strb    w5, [x11], #1
    sub     x4, x4, #1
    b       4b

    /* List: its header, from its encoded length x4. */
5:  ldr     x4, [x15, x16, lsl #3]
    cmp     x4, #(RLP_SHORT_MAX + 1)
    b.hi    6f
    add     x5, x4, #(RLP_SHORT_LIST - 1)
    strb    w5, [x11], #1
    b       8f
6:  mov     x5, #1                      /* bytes of the payload length */
61: sub     x6, x4, #1
    sub     x6, x6, x5                  /* payload length if x5 is right */
    cmp     x5, #8
    b.eq    62f
    lsl     x7, x5, #3
    lsr     x7, x6, x7
    cbz     x7, 62f
    add     x5, x5, #1
    b       61b
62: add     x7, x5, #RLP_LONG_LIST
    strb    w7, [x11], #1
    lsl     x7, x5, #3
63: sub     x7, x7, #8
    lsr     x2, x6, x7
    strb    w2, [x11], #1
    cbnz    x7, 63b

8:  add     x16, x16, #1
    b       1b

90: mov     x0, #RLP_OK
    b       99f
91: mov     x0, #RLP_BUFFER_TOO_SMALL
99: UNWIND_BEGIN_EPILOGUE
    ldp     x21, x22, [sp, #32]
    UNWIND_RESTORE_REGP x21, x22, 32
    ldp     x19, x20, [sp, #16]
    UNWIND_RESTORE_REGP x19, x20, 16
    ldp     x29, x30, [sp], #48
    UNWIND_RESTORE_FPLR_X 48
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_encode
