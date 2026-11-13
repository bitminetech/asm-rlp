/*
 * asm-rlp for x86-64 (System V AMD64 psABI). AT&T syntax.
 * Requirements: docs/reference/rlp.md. Layouts: include/rlp.inc.
 *
 * Every function follows the System V ABI: pointer arguments, status in rax.
 * Baseline x86-64 instructions only. rlp_measure is a leaf that saves nothing.
 */
.set ISA_X86_64, 1
.include "rlp.inc"
.include "platform.inc"

/* Save rbx, rbp and r12-r15. With the return address, rsp is then 16-byte aligned less 8. */
.macro SAVE6
    push    %rbx
    UNWIND_PUSH %rbx
    push    %rbp
    UNWIND_PUSH %rbp
    push    %r12
    UNWIND_PUSH %r12
    push    %r13
    UNWIND_PUSH %r13
    push    %r14
    UNWIND_PUSH %r14
    push    %r15
    UNWIND_PUSH %r15
.endm

.macro RESTORE6
    pop     %r15
    UNWIND_POP %r15
    pop     %r14
    UNWIND_POP %r14
    pop     %r13
    UNWIND_POP %r13
    pop     %r12
    UNWIND_POP %r12
    pop     %rbp
    UNWIND_POP %rbp
    pop     %rbx
    UNWIND_POP %rbx
.endm

/* dst = bytes in the RLP header for a length src: 1 below 56, else 1 + bytes of src. */
.macro HEADER_SIZE dst, src
    mov     $1, \dst
    cmp     $(RLP_SHORT_MAX + 1), \src
    jb      97f
    bsr     \src, \dst
    shr     $3, \dst
    add     $2, \dst
97:
.endm

/*
 * rlp_decode(encoded, items).
 * rdx bytes, r9 first record, r10 records that fit, r11 records written,
 * rcx position, rbx end of the current list (or of the encoding), rbp open
 * list (-1 for none), r12 1 for the first item, r13 bytes left, r14 length,
 * r15 bytes of the length, rdi payload start, r8 next position, rsi kind.
 * While a list is open, its items field holds the index of its parent.
 */
FUNCTION rlp_decode
    SAVE6
    UNWIND_END_PROLOGUE
    mov     RLP_BL_OFFSET(%rdi), %rdx
    add     %rdi, %rdx
    mov     RLP_BL_COUNT(%rdi), %rbx
    mov     $RLP_EMPTY, %eax
    test    %rbx, %rbx
    jz      99f
    lea     RLP_ITEMS_FIXED(%rsi), %r9
    mov     RLP_ITEMS_SIZE(%rsi), %r10
    xor     %eax, %eax
    sub     $RLP_ITEMS_FIXED, %r10
    cmovb   %rax, %r10
    shr     $RLP_ITEM_SHIFT, %r10
    xor     %r11d, %r11d
    xor     %ecx, %ecx
    mov     $-1, %rbp
    mov     $1, %r12d

    /* The item at rcx, with r13 bytes left in its list. */
1:  mov     %rbx, %r13
    sub     %rcx, %r13
    movzbl  (%rdx,%rcx), %eax
    cmp     $RLP_SHORT_BYTES, %eax
    jae     2f
    /* One byte below 0x80: the byte itself. */
    test    %r12, %r12
    jz      11f
    cmp     $1, %r13
    jne     95f                         /* top level, more bytes follow */
11: mov     $1, %r14d
    mov     %rcx, %rdi
    lea     1(%rcx), %r8
    jmp     30f

2:  cmp     $RLP_LONG_BYTES, %eax
    ja      3f
    /* Byte string of 0 to 55 bytes. */
    lea     -RLP_SHORT_BYTES(%rax), %r14
    cmp     %r13, %r14
    jae     92f                         /* 1 + length > bytes left */
    test    %r12, %r12
    jz      21f
    lea     1(%r14), %r15
    cmp     %r13, %r15
    jb      93f                         /* top level, bytes after it */
21: cmp     $1, %r14
    jne     22f
    movzbl  1(%rdx,%rcx), %r15d
    cmp     $RLP_SHORT_BYTES, %r15d
    jb      96f                         /* one byte below 0x80 with a header */
22: lea     1(%rcx), %rdi
    lea     (%rdi,%r14), %r8
    jmp     30f

3:  cmp     $(RLP_LONG_BYTES + 8), %eax
    ja      4f
    lea     -RLP_LONG_BYTES(%rax), %r15
    mov     $RLP_KIND_BYTES, %esi
    jmp     50f

4:  cmp     $RLP_LONG_LIST, %eax
    ja      5f
    /* List with 0 to 55 payload bytes. */
    lea     -RLP_SHORT_LIST(%rax), %r14
    cmp     %r13, %r14
    jae     92f
    test    %r12, %r12
    jz      41f
    lea     1(%r14), %r15
    cmp     %r13, %r15
    jb      93f
41: lea     1(%rcx), %rdi
    jmp     40f

5:  lea     -RLP_LONG_LIST(%rax), %r15
    mov     $RLP_KIND_LIST, %esi

    /* Long form: r15 bytes of length follow the first byte. rsi is the kind. */
50: cmp     %r13, %r15
    jae     92f                         /* the length does not fit */
    lea     1(%rcx), %rdi
    cmpb    $0, (%rdx,%rdi)
    je      96f                         /* the length starts with a zero byte */
    lea     (%rdx,%rdi), %r8
    lea     (%r8,%r15), %rax
    xor     %r14d, %r14d
51: shl     $8, %r14
    movb    (%r8), %r14b
    inc     %r8
    cmp     %rax, %r8
    jne     51b
    add     %r15, %rdi                  /* payload start */
    test    %r12, %r12
    jz      52f
    cmp     $(RLP_SHORT_MAX + 1), %r14
    jb      96f                         /* top level: short length in long form */
52: mov     %r13, %r8
    sub     $1, %r8
    sub     %r15, %r8                   /* bytes left after the header */
    cmp     %r8, %r14
    ja      92f
    jae     53f
    test    %r12, %r12
    jnz     93f
53: cmp     $(RLP_SHORT_MAX + 1), %r14
    jb      96f                         /* short length in long form */
    cmp     $RLP_KIND_LIST, %esi
    je      40f
    lea     (%rdi,%r14), %r8

    /* A byte string: payload at rdi, r14 bytes, next item at r8. */
30: cmp     %r10, %r11
    jae     91f
    mov     %r11, %rax
    shl     $RLP_ITEM_SHIFT, %rax
    add     %r9, %rax
    movq    $RLP_KIND_BYTES, RLP_ITEM_KIND(%rax)
    mov     %rdi, RLP_ITEM_OFFSET(%rax)
    mov     %r14, RLP_ITEM_LENGTH(%rax)
    movq    $1, RLP_ITEM_ITEMS(%rax)
    inc     %r11
    mov     %r8, %rcx
    jmp     60f

    /* A list: payload at rdi, r14 bytes. It becomes the open list. */
40: cmp     %r10, %r11
    jae     91f
    mov     %r11, %rax
    shl     $RLP_ITEM_SHIFT, %rax
    add     %r9, %rax
    movq    $RLP_KIND_LIST, RLP_ITEM_KIND(%rax)
    mov     %rdi, RLP_ITEM_OFFSET(%rax)
    mov     %r14, RLP_ITEM_LENGTH(%rax)
    mov     %rbp, RLP_ITEM_ITEMS(%rax)
    mov     %r11, %rbp
    inc     %r11
    mov     %rdi, %rcx
    lea     (%rdi,%r14), %rbx

    /* Close every list that ends here. */
60: xor     %r12d, %r12d
61: cmp     %rbx, %rcx
    jne     1b
    cmp     $-1, %rbp
    je      70f
    mov     %rbp, %rax
    shl     $RLP_ITEM_SHIFT, %rax
    add     %r9, %rax
    mov     RLP_ITEM_ITEMS(%rax), %r8
    mov     %r11, %r15
    sub     %rbp, %r15
    mov     %r15, RLP_ITEM_ITEMS(%rax)
    mov     %r8, %rbp
    cmp     $-1, %rbp
    je      70f
    mov     %rbp, %rax
    shl     $RLP_ITEM_SHIFT, %rax
    add     %r9, %rax
    mov     RLP_ITEM_OFFSET(%rax), %rbx
    add     RLP_ITEM_LENGTH(%rax), %rbx
    jmp     61b

70: movq    $RLP_ITEMS_FIXED, (RLP_ITEMS_OFFSET - RLP_ITEMS_FIXED)(%r9)
    mov     %r11, (RLP_ITEMS_COUNT - RLP_ITEMS_FIXED)(%r9)
    xor     %eax, %eax
    jmp     99f
91: mov     $RLP_BUFFER_TOO_SMALL, %eax
    jmp     99f
92: mov     $RLP_TRUNCATED, %eax
    jmp     99f
93: mov     $RLP_TRAILING_BYTES, %eax
    jmp     99f
95: mov     $RLP_NEGATIVE_LENGTH, %eax
    jmp     99f
96: mov     $RLP_NON_CANONICAL, %eax
99: UNWIND_BEGIN_EPILOGUE
    RESTORE6
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_decode

/*
 * rlp_measure(items, data, scratch). A leaf: caller-saved registers only.
 * Writes the encoded length of every item to scratch, last item first.
 * r8 first record, rsi data bytes, rdx lengths, r9 item, r10 its record.
 */
LOCAL_FUNCTION rlp_measure
    UNWIND_END_PROLOGUE
    mov     RLP_ITEMS_OFFSET(%rdi), %r8
    add     %rdi, %r8
    mov     RLP_ITEMS_COUNT(%rdi), %r9
    mov     RLP_BL_OFFSET(%rsi), %rax
    add     %rax, %rsi
    lea     RLP_SCRATCH_LENGTHS(,%r9,8), %rax
    cmp     %rax, RLP_SCRATCH_SIZE(%rdx)
    jb      91f
    add     $RLP_SCRATCH_LENGTHS, %rdx
1:  test    %r9, %r9
    jz      9f
    dec     %r9
    mov     %r9, %r10
    shl     $RLP_ITEM_SHIFT, %r10
    add     %r8, %r10
    cmpq    $RLP_KIND_BYTES, RLP_ITEM_KIND(%r10)
    jne     3f
    /* Byte string: 1 for one byte below 0x80, else header and bytes. */
    mov     RLP_ITEM_LENGTH(%r10), %r11
    cmp     $1, %r11
    jne     2f
    mov     RLP_ITEM_OFFSET(%r10), %rax
    cmpb    $RLP_SHORT_BYTES, (%rsi,%rax)
    jae     2f
    mov     $1, %edi
    jmp     5f
2:  HEADER_SIZE %rax, %r11
    lea     (%rax,%r11), %rdi
    jmp     5f
    /* List: header and the encoded lengths of its children. */
3:  mov     RLP_ITEM_ITEMS(%r10), %r11
    add     %r9, %r11
    lea     1(%r9), %rcx
    xor     %edi, %edi
4:  cmp     %r11, %rcx
    jae     6f
    add     (%rdx,%rcx,8), %rdi
    mov     %rcx, %rax
    shl     $RLP_ITEM_SHIFT, %rax
    add     RLP_ITEM_ITEMS(%r8,%rax), %rcx
    jmp     4b
6:  HEADER_SIZE %rax, %rdi
    add     %rax, %rdi
5:  mov     %rdi, (%rdx,%r9,8)
    jmp     1b
9:  xor     %eax, %eax
    ret
91: mov     $RLP_BUFFER_TOO_SMALL, %eax
    ret
END_FUNCTION rlp_measure

/* rlp_encode_size(items, data, scratch, size). rbx scratch, rbp size. */
FUNCTION rlp_encode_size
    push    %rbx
    UNWIND_PUSH %rbx
    push    %rbp
    UNWIND_PUSH %rbp
    sub     $8, %rsp
    UNWIND_ALLOC 8
    UNWIND_END_PROLOGUE
    mov     %rdx, %rbx
    mov     %rcx, %rbp
    call    rlp_measure
    test    %rax, %rax
    jnz     1f
    mov     RLP_SCRATCH_LENGTHS(%rbx), %rcx
    add     $RLP_BL_FIXED, %rcx
    mov     %rcx, (%rbp)
1:  UNWIND_BEGIN_EPILOGUE
    add     $8, %rsp
    UNWIND_FREE 8
    pop     %rbp
    UNWIND_POP %rbp
    pop     %rbx
    UNWIND_POP %rbx
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_encode_size

/*
 * rlp_encode(items, data, scratch, encoded).
 * After rlp_measure: r12 first record, r13 record count, rbx data bytes,
 * rbp lengths, r14 next output byte, r15 item, r9 length, rdx bytes of a length.
 */
FUNCTION rlp_encode
    SAVE6
    sub     $8, %rsp
    UNWIND_ALLOC 8
    UNWIND_END_PROLOGUE
    mov     %rdi, %r12
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r13
    call    rlp_measure
    test    %rax, %rax
    jnz     99f
    mov     RLP_SCRATCH_LENGTHS(%rbp), %r9
    mov     RLP_BL_SIZE(%r13), %r10
    sub     $RLP_BL_FIXED, %r10
    jb      91f
    cmp     %r9, %r10
    jb      91f
    movq    $RLP_BL_FIXED, RLP_BL_OFFSET(%r13)
    mov     %r9, RLP_BL_COUNT(%r13)
    lea     RLP_BL_FIXED(%r13), %r14
    mov     RLP_ITEMS_OFFSET(%r12), %rax
    mov     RLP_ITEMS_COUNT(%r12), %r13
    add     %rax, %r12
    mov     RLP_BL_OFFSET(%rbx), %rax
    add     %rax, %rbx
    add     $RLP_SCRATCH_LENGTHS, %rbp
    xor     %r15d, %r15d

1:  cmp     %r13, %r15
    jae     90f
    mov     %r15, %r10
    shl     $RLP_ITEM_SHIFT, %r10
    add     %r12, %r10
    cmpq    $RLP_KIND_BYTES, RLP_ITEM_KIND(%r10)
    jne     5f
    /* Byte string: rsi its bytes, r9 its length. */
    mov     RLP_ITEM_LENGTH(%r10), %r9
    mov     RLP_ITEM_OFFSET(%r10), %rsi
    add     %rbx, %rsi
    cmp     $1, %r9
    jne     2f
    movzbl  (%rsi), %eax
    cmp     $RLP_SHORT_BYTES, %eax
    jae     2f
    mov     %al, (%r14)
    inc     %r14
    jmp     8f
2:  cmp     $(RLP_SHORT_MAX + 1), %r9
    jae     21f
    lea     RLP_SHORT_BYTES(%r9), %eax
    mov     %al, (%r14)
    inc     %r14
    jmp     3f
21: bsr     %r9, %rdx
    shr     $3, %rdx
    inc     %rdx                        /* bytes of the length */
    lea     RLP_LONG_BYTES(%rdx), %eax
    mov     %al, (%r14)
    inc     %r14
    lea     (,%rdx,8), %rcx
22: sub     $8, %rcx
    mov     %r9, %rax
    shr     %cl, %rax
    mov     %al, (%r14)
    inc     %r14
    test    %rcx, %rcx
    jnz     22b
3:  cmp     $8, %r9
    jb      4f
    mov     (%rsi), %rax
    mov     %rax, (%r14)
    add     $8, %rsi
    add     $8, %r14
    sub     $8, %r9
    jmp     3b
4:  test    %r9, %r9
    jz      8f
    movzbl  (%rsi), %eax
    mov     %al, (%r14)
    inc     %rsi
    inc     %r14
    dec     %r9
    jmp     4b

    /* List: its header, from its encoded length r9. */
5:  mov     (%rbp,%r15,8), %r9
    cmp     $(RLP_SHORT_MAX + 1), %r9
    ja      6f
    lea     (RLP_SHORT_LIST - 1)(%r9), %eax
    mov     %al, (%r14)
    inc     %r14
    jmp     8f
6:  mov     $1, %edx                    /* bytes of the payload length */
61: mov     %r9, %r8
    sub     $1, %r8
    sub     %rdx, %r8                   /* payload length if rdx is right */
    cmp     $8, %rdx
    je      62f
    lea     (,%rdx,8), %rcx
    mov     %r8, %rax
    shr     %cl, %rax
    test    %rax, %rax
    jz      62f
    inc     %rdx
    jmp     61b
62: lea     RLP_LONG_LIST(%rdx), %eax
    mov     %al, (%r14)
    inc     %r14
    lea     (,%rdx,8), %rcx
63: sub     $8, %rcx
    mov     %r8, %rax
    shr     %cl, %rax
    mov     %al, (%r14)
    inc     %r14
    test    %rcx, %rcx
    jnz     63b

8:  inc     %r15
    jmp     1b

90: xor     %eax, %eax
    jmp     99f
91: mov     $RLP_BUFFER_TOO_SMALL, %eax
99: UNWIND_BEGIN_EPILOGUE
    add     $8, %rsp
    UNWIND_FREE 8
    RESTORE6
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION rlp_encode
