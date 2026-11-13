/*
 * asm-rlp for RISC-V (RISC-V ELF psABI, LP64D).
 * Requirements: docs/reference/rlp.md. Layouts: include/rlp.inc.
 *
 * Every function follows the psABI: pointer arguments, status in a0.
 * Baseline RV64GC instructions only, so byte counts are found with loops.
 * Bytes are copied one at a time, so no access is misaligned.
 * Trailing comments use #, which the RISC-V assembler requires after a register.
 */
.set ISA_RISCV64, 1
.include "rlp.inc"
.include "platform.inc"

/* dst = bytes in the RLP header for a length src: 1 below 56, else 1 + bytes of src. Uses tmp. */
.macro HEADER_SIZE dst, src, tmp
    li      \dst, 1
    li      \tmp, (RLP_SHORT_MAX + 1)
    bltu    \src, \tmp, 97f
    mv      \tmp, \src
96: srli    \tmp, \tmp, 8
    addi    \dst, \dst, 1
    bnez    \tmp, 96b
97:
.endm

/*
 * rlp_decode(encoded, items). A leaf: caller-saved registers only.
 * a2 bytes, a4 first record, a5 records that fit, a6 records written,
 * a7 position, t0 end of the current list (or of the encoding), t1 open
 * list (-1 for none), t2 1 for the first item, t3 bytes left, t5 length,
 * t6 bytes of the length, a3 payload start, a0 next position, a1 kind.
 * While a list is open, its items field holds the index of its parent.
 */
FUNCTION rlp_decode
    UNWIND_END_PROLOGUE
    ld      a2, RLP_BL_OFFSET(a0)
    add     a2, a0, a2
    ld      t0, RLP_BL_COUNT(a0)
    beqz    t0, 90f
    addi    a4, a1, RLP_ITEMS_FIXED
    ld      t5, RLP_ITEMS_SIZE(a1)
    li      t4, RLP_ITEMS_FIXED
    li      a5, 0
    bltu    t5, t4, 1f                  # under 24 bytes: no record fits
    sub     t5, t5, t4
    srli    a5, t5, RLP_ITEM_SHIFT
1:  li      a6, 0
    li      a7, 0
    li      t1, -1
    li      t2, 1

    /* The item at a7, with t3 bytes left in its list. */
10: sub     t3, t0, a7
    add     t4, a2, a7
    lbu     t4, 0(t4)
    li      t5, RLP_SHORT_BYTES
    bgeu    t4, t5, 2f
    /* One byte below 0x80: the byte itself. */
    beqz    t2, 11f
    li      t5, 1
    bne     t3, t5, 95f                 # top level, more bytes follow
11: li      t5, 1
    mv      a3, a7
    addi    a0, a7, 1
    j       30f

2:  li      t5, RLP_LONG_BYTES
    bgtu    t4, t5, 3f
    /* Byte string of 0 to 55 bytes. */
    addi    t5, t4, -RLP_SHORT_BYTES
    bgeu    t5, t3, 92f                 # 1 + length > bytes left
    beqz    t2, 21f
    addi    t6, t5, 1
    bltu    t6, t3, 93f                 # top level, bytes after it
21: li      t6, 1
    bne     t5, t6, 22f
    add     t6, a2, a7
    lbu     t6, 1(t6)
    li      a3, RLP_SHORT_BYTES
    bltu    t6, a3, 96f                 # one byte below 0x80 with a header
22: addi    a3, a7, 1
    add     a0, a3, t5
    j       30f

3:  li      t5, (RLP_LONG_BYTES + 8)
    bgtu    t4, t5, 4f
    addi    t6, t4, -RLP_LONG_BYTES
    li      a1, RLP_KIND_BYTES
    j       50f

4:  li      t5, RLP_LONG_LIST
    bgtu    t4, t5, 5f
    /* List with 0 to 55 payload bytes. */
    addi    t5, t4, -RLP_SHORT_LIST
    bgeu    t5, t3, 92f
    beqz    t2, 41f
    addi    t6, t5, 1
    bltu    t6, t3, 93f
41: addi    a3, a7, 1
    j       40f

5:  addi    t6, t4, -RLP_LONG_LIST
    li      a1, RLP_KIND_LIST

    /* Long form: t6 bytes of length follow the first byte. a1 is the kind. */
50: bgeu    t6, t3, 92f                 # the length does not fit
    add     a0, a2, a7
    addi    a0, a0, 1
    lbu     t5, 0(a0)
    beqz    t5, 96f                     # the length starts with a zero byte
    add     t4, a0, t6
    li      t5, 0
51: slli    t5, t5, 8
    lbu     a3, 0(a0)
    or      t5, t5, a3
    addi    a0, a0, 1
    bne     a0, t4, 51b
    add     a3, a7, t6
    addi    a3, a3, 1                   # payload start
    beqz    t2, 52f
    li      t4, (RLP_SHORT_MAX + 1)
    bltu    t5, t4, 96f                 # top level: short length in long form
52: sub     a0, t3, t6
    addi    a0, a0, -1                  # bytes left after the header
    bgtu    t5, a0, 92f
    beq     t5, a0, 53f
    bnez    t2, 93f
53: li      t4, (RLP_SHORT_MAX + 1)
    bltu    t5, t4, 96f                 # short length in long form
    li      t4, RLP_KIND_LIST
    beq     a1, t4, 40f
    add     a0, a3, t5

    /* A byte string: payload at a3, t5 bytes, next item at a0. */
30: bgeu    a6, a5, 91f
    slli    t4, a6, RLP_ITEM_SHIFT
    add     t4, t4, a4
    li      t6, RLP_KIND_BYTES
    sd      t6, RLP_ITEM_KIND(t4)
    sd      a3, RLP_ITEM_OFFSET(t4)
    sd      t5, RLP_ITEM_LENGTH(t4)
    li      t6, 1
    sd      t6, RLP_ITEM_ITEMS(t4)
    addi    a6, a6, 1
    mv      a7, a0
    j       60f

    /* A list: payload at a3, t5 bytes. It becomes the open list. */
40: bgeu    a6, a5, 91f
    slli    t4, a6, RLP_ITEM_SHIFT
    add     t4, t4, a4
    li      t6, RLP_KIND_LIST
    sd      t6, RLP_ITEM_KIND(t4)
    sd      a3, RLP_ITEM_OFFSET(t4)
    sd      t5, RLP_ITEM_LENGTH(t4)
    sd      t1, RLP_ITEM_ITEMS(t4)
    mv      t1, a6
    addi    a6, a6, 1
    mv      a7, a3
    add     t0, a3, t5

    /* Close every list that ends here. */
60: li      t2, 0
61: bne     a7, t0, 10b
    li      t4, -1
    beq     t1, t4, 70f
    slli    t4, t1, RLP_ITEM_SHIFT
    add     t4, t4, a4
    ld      t6, RLP_ITEM_ITEMS(t4)
    sub     t5, a6, t1
    sd      t5, RLP_ITEM_ITEMS(t4)
    mv      t1, t6
    li      t4, -1
    beq     t1, t4, 70f
    slli    t4, t1, RLP_ITEM_SHIFT
    add     t4, t4, a4
    ld      t0, RLP_ITEM_OFFSET(t4)
    ld      t5, RLP_ITEM_LENGTH(t4)
    add     t0, t0, t5
    j       61b

70: li      t4, RLP_ITEMS_FIXED
    sd      t4, (RLP_ITEMS_OFFSET - RLP_ITEMS_FIXED)(a4)
    sd      a6, (RLP_ITEMS_COUNT - RLP_ITEMS_FIXED)(a4)
    li      a0, RLP_OK
    ret
90: li      a0, RLP_EMPTY
    ret
91: li      a0, RLP_BUFFER_TOO_SMALL
    ret
92: li      a0, RLP_TRUNCATED
    ret
93: li      a0, RLP_TRAILING_BYTES
    ret
95: li      a0, RLP_NEGATIVE_LENGTH
    ret
96: li      a0, RLP_NON_CANONICAL
    ret
END_FUNCTION rlp_decode

/*
 * rlp_measure(items, data, scratch). A leaf: caller-saved registers only.
 * Writes the encoded length of every item to scratch, last item first.
 * a3 first record, a4 item, a5 data bytes, a6 lengths, a7 its record.
 */
LOCAL_FUNCTION rlp_measure
    UNWIND_END_PROLOGUE
    ld      a3, RLP_ITEMS_OFFSET(a0)
    add     a3, a0, a3
    ld      a4, RLP_ITEMS_COUNT(a0)
    ld      a5, RLP_BL_OFFSET(a1)
    add     a5, a1, a5
    ld      t0, RLP_SCRATCH_SIZE(a2)
    slli    t1, a4, 3
    addi    t1, t1, RLP_SCRATCH_LENGTHS
    bltu    t0, t1, 91f
    addi    a6, a2, RLP_SCRATCH_LENGTHS
1:  beqz    a4, 9f
    addi    a4, a4, -1
    slli    a7, a4, RLP_ITEM_SHIFT
    add     a7, a7, a3
    ld      t0, RLP_ITEM_KIND(a7)
    li      t1, RLP_KIND_BYTES
    bne     t0, t1, 3f
    /* Byte string: 1 for one byte below 0x80, else header and bytes. */
    ld      t2, RLP_ITEM_LENGTH(a7)
    bne     t2, t1, 2f
    ld      t3, RLP_ITEM_OFFSET(a7)
    add     t3, a5, t3
    lbu     t3, 0(t3)
    li      t4, RLP_SHORT_BYTES
    bgeu    t3, t4, 2f
    li      t5, 1
    j       5f
2:  HEADER_SIZE t5, t2, t3
    add     t5, t5, t2
    j       5f
    /* List: header and the encoded lengths of its children. */
3:  ld      t2, RLP_ITEM_ITEMS(a7)
    add     t2, t2, a4
    addi    t3, a4, 1
    li      t5, 0
4:  bgeu    t3, t2, 6f
    slli    t4, t3, 3
    add     t4, t4, a6
    ld      t4, 0(t4)
    add     t5, t5, t4
    slli    t4, t3, RLP_ITEM_SHIFT
    add     t4, t4, a3
    ld      t4, RLP_ITEM_ITEMS(t4)
    add     t3, t3, t4
    j       4b
6:  HEADER_SIZE t6, t5, t4
    add     t5, t5, t6
5:  slli    t4, a4, 3
    add     t4, t4, a6
    sd      t5, 0(t4)
    j       1b
9:  li      a0, RLP_OK
    ret
91: li      a0, RLP_BUFFER_TOO_SMALL
    ret
END_FUNCTION rlp_measure

/* rlp_encode_size(items, data, scratch, size). s1 scratch, s2 size. */
FUNCTION rlp_encode_size
    addi    sp, sp, -32
    UNWIND_ALLOC 32
    sd      ra, 0(sp)
    UNWIND_SAVE ra, 0
    sd      s1, 8(sp)
    UNWIND_SAVE s1, 8
    sd      s2, 16(sp)
    UNWIND_SAVE s2, 16
    UNWIND_END_PROLOGUE
    mv      s1, a2
    mv      s2, a3
    call    rlp_measure
    bnez    a0, 1f
    ld      t0, RLP_SCRATCH_LENGTHS(s1)
    addi    t0, t0, RLP_BL_FIXED
    sd      t0, 0(s2)
1:  UNWIND_BEGIN_EPILOGUE
    ld      ra, 0(sp)
    UNWIND_RESTORE ra
    ld      s1, 8(sp)
    UNWIND_RESTORE s1
    ld      s2, 16(sp)
    UNWIND_RESTORE s2
    addi    sp, sp, 32
    UNWIND_FREE 32
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_encode_size

/*
 * rlp_encode(items, data, scratch, encoded).
 * After rlp_measure: s1 first record, s2 data bytes, s3 lengths, a0 next
 * output byte, a1 record count, a2 item, a3 its record, a4 length, a5 bytes.
 */
FUNCTION rlp_encode
    addi    sp, sp, -48
    UNWIND_ALLOC 48
    sd      ra, 0(sp)
    UNWIND_SAVE ra, 0
    sd      s1, 8(sp)
    UNWIND_SAVE s1, 8
    sd      s2, 16(sp)
    UNWIND_SAVE s2, 16
    sd      s3, 24(sp)
    UNWIND_SAVE s3, 24
    sd      s4, 32(sp)
    UNWIND_SAVE s4, 32
    UNWIND_END_PROLOGUE
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    call    rlp_measure
    bnez    a0, 99f
    ld      t0, RLP_SCRATCH_LENGTHS(s3)
    ld      t1, RLP_BL_SIZE(s4)
    li      t2, RLP_BL_FIXED
    bltu    t1, t2, 91f
    sub     t1, t1, t2
    bltu    t1, t0, 91f
    sd      t2, RLP_BL_OFFSET(s4)
    sd      t0, RLP_BL_COUNT(s4)
    addi    a0, s4, RLP_BL_FIXED
    ld      a1, RLP_ITEMS_COUNT(s1)
    ld      t1, RLP_ITEMS_OFFSET(s1)
    add     s1, s1, t1
    ld      t1, RLP_BL_OFFSET(s2)
    add     s2, s2, t1
    addi    s3, s3, RLP_SCRATCH_LENGTHS
    li      a2, 0

1:  bgeu    a2, a1, 90f
    slli    a3, a2, RLP_ITEM_SHIFT
    add     a3, a3, s1
    ld      t0, RLP_ITEM_KIND(a3)
    li      t1, RLP_KIND_BYTES
    bne     t0, t1, 5f
    /* Byte string: a5 its bytes, a4 its length. */
    ld      a4, RLP_ITEM_LENGTH(a3)
    ld      a5, RLP_ITEM_OFFSET(a3)
    add     a5, a5, s2
    bne     a4, t1, 2f
    lbu     t0, 0(a5)
    li      t1, RLP_SHORT_BYTES
    bgeu    t0, t1, 2f
    sb      t0, 0(a0)
    addi    a0, a0, 1
    j       8f
2:  li      t1, (RLP_SHORT_MAX + 1)
    bgeu    a4, t1, 21f
    addi    t0, a4, RLP_SHORT_BYTES
    sb      t0, 0(a0)
    addi    a0, a0, 1
    j       3f
21: mv      t0, a4
    li      t2, 0
211: srli   t0, t0, 8
    addi    t2, t2, 1
    bnez    t0, 211b                    # t2: bytes of the length
    addi    t0, t2, RLP_LONG_BYTES
    sb      t0, 0(a0)
    addi    a0, a0, 1
    slli    t3, t2, 3
22: addi    t3, t3, -8
    srl     t0, a4, t3
    sb      t0, 0(a0)
    addi    a0, a0, 1
    bnez    t3, 22b
3:  beqz    a4, 8f
31: lbu     t0, 0(a5)
    sb      t0, 0(a0)
    addi    a5, a5, 1
    addi    a0, a0, 1
    addi    a4, a4, -1
    bnez    a4, 31b
    j       8f

    /* List: its header, from its encoded length a4. */
5:  slli    t0, a2, 3
    add     t0, t0, s3
    ld      a4, 0(t0)
    li      t1, (RLP_SHORT_MAX + 1)
    bgtu    a4, t1, 6f
    addi    t0, a4, (RLP_SHORT_LIST - 1)
    sb      t0, 0(a0)
    addi    a0, a0, 1
    j       8f
6:  li      t2, 1                       # bytes of the payload length
61: sub     t3, a4, t2
    addi    t3, t3, -1                  # payload length if t2 is right
    li      t1, 8
    beq     t2, t1, 62f
    slli    t4, t2, 3
    srl     t5, t3, t4
    beqz    t5, 62f
    addi    t2, t2, 1
    j       61b
62: addi    t0, t2, RLP_LONG_LIST
    sb      t0, 0(a0)
    addi    a0, a0, 1
    slli    t4, t2, 3
63: addi    t4, t4, -8
    srl     t0, t3, t4
    sb      t0, 0(a0)
    addi    a0, a0, 1
    bnez    t4, 63b

8:  addi    a2, a2, 1
    j       1b

90: li      a0, RLP_OK
    j       99f
91: li      a0, RLP_BUFFER_TOO_SMALL
99: UNWIND_BEGIN_EPILOGUE
    ld      ra, 0(sp)
    UNWIND_RESTORE ra
    ld      s1, 8(sp)
    UNWIND_RESTORE s1
    ld      s2, 16(sp)
    UNWIND_RESTORE s2
    ld      s3, 24(sp)
    UNWIND_RESTORE s3
    ld      s4, 32(sp)
    UNWIND_RESTORE s4
    addi    sp, sp, 48
    UNWIND_FREE 48
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_encode
