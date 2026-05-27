DEF SHORTCIRCUIT_ZERO = 0
; This file is meant to be viewed using tabs for indentation and tab width 8.

SECTION "Math", ROM0

; Reasonably fast unsigned 8bit*8bit=16bit multiplication.
; Interface: HL=H*E
; 57 M cycles (AVG, including call/ret) (before conditional ret)
; 55 M cycles (AVG, including call/ret) (after conditional ret)
UMUL_8_8::
if SHORTCIRCUIT_ZERO
	; Check if H==1.
	dec	H
	jr	z,.h_is_one

	; Check if H==0 and restore the previous dec.
	inc	H
	jr	z,.is_zero

	; Check if E==1.
	dec	E
	jr	z,.e_is_one

	; Check if E==0 and restore the previous dec.
	inc	E
	jr	z,.is_zero
ENDC
	ld	L,0			; 2
	ld	D,L			; 1
	REPT 7				; 5.5 * 7 = 44 (avg)
		add	HL,HL		; | 2
		jr	nc,:+		; | 3/2
		add	HL,DE		; | 2
:
	ENDR
					; 7/9 -> 8 (avg)
	add	HL,HL			; | 2
	ret	nc			; | 5/2
	add	HL,DE			; | 2
	ret				; | 4

if SHORTCIRCUIT_ZERO

.h_is_one:
	; HL=0E (H was already 0 from the test which we can use.)
	ld	L,E
	ret

.e_is_one:
	; HL=0H
	ld	L,H
	ld	H,E		; We know E==0 from the test.
	inc	E		; Restore the value of E if the calling code relies on it being preserved.
	ret

.is_zero:
	ld	HL,0
	ret
ENDC

; Bespoke multiplication function mainly for the time presentation.
; Uses UMUL_8_8 as a primitive for partial multiplication.
; Op1: HL points to a 16 bit value in memory to be multiplied.
; Op2: BC holds an immediate value to be multiplied.
; Output: 32 bits are written to mul_buffer in HRAM.
; [mul_buffer] = BC * [HL]
; Works like this:
; 0000aaaa <- LOW*LOW
; 00bbbb00 <- LOW*HIGH
; 00cccc00 <- HIGH*LOW
;+dddd0000 <- HIGH*HIGH
;=sum

UMUL_16_MEM16::
	ld	A,[HL+]			; Load LOW(Op1) and move pointer to HIGH(Op1)
	push	HL			; Push HIGH(Op1) for alter use.
	; LOW(Op1) * LOW(Op2)
	; Start by multiplying the lower bytes.
	ld	E,A
	ld	H,C
	call	UMUL_8_8		; HL=H*E
	; Since this is the first operation, we can simply zero fill the other two bytes of the accumulator.
	ld	A,L
	ldh	[mul_buffer],A
	ld	A,H
	ldh	[mul_buffer+1],A
	xor	A
	ldh	[mul_buffer+2],A
	ldh	[mul_buffer+3],A

	; LOW(Op1) * HIGH(Op2)
	; E is preserved from before.
	ld	H,B
	call	UMUL_8_8		; HL=H*E
	; Add result to the accumulator.
	ldh	A,[mul_buffer+1]
	add	L
	ldh	[mul_buffer+1],A

	ldh	A,[mul_buffer+2]
	adc	H
	ldh	[mul_buffer+2],A

	jr	nc,:+
	ldh	A,[mul_buffer+3]
	inc	H
	ldh	[mul_buffer+3],A
:
	
	; HIGH(Op1) *LOW(Op2)
	; Get pointer to HIGH(Op1)
	pop	HL
	ld	E,[HL]
	ld	H,C
	call	UMUL_8_8		; HL=H*E
	; Add result to the accumulator.
	ldh	A,[mul_buffer+1]
	add	L
	ldh	[mul_buffer+1],A

	ldh	A,[mul_buffer+2]
	adc	H
	ldh	[mul_buffer+2],A

	jr	nc,:+
	ldh	A,[mul_buffer+3]
	inc	H
	ldh	[mul_buffer+3],A
:

	; HIGH(Op1) *LOW(Op2)
	; E is preserved from before.
	ld	H,B
	call	UMUL_8_8		; HL=H*E

	ldh	A,[mul_buffer+2]
	add	L
	ldh	[mul_buffer+2],A

	ldh	A,[mul_buffer+3]
	adc	H
	ldh	[mul_buffer+3],A

	ret
; Multiplies two unsigned 32 bit integers into anunsigned 32 bit integer.
; Uses UMUL_8_8 as a primitive for partial multiplication.
; Input: data stored at mul_buffer_in_a and mul_buffer_in_b in HRAM.
; Output: data stored at mul_buffer
; 
; The 32 bit multiplication theoretically has 16 partial multiplication steps.
; However, because the output is only 32 bits big, some of these steps are above
; bit 31 and actually are not needed for the final result. 
;
; Matrix of the shift position needed for each part. 
;    a0 a1 a2 a3
; b0  0  1  2  3
; b1  1  2  3  x
; b2  2  3  x  x
; b3  3  x  x  x
;
; Matrix of the order of operations. 
;    a0 a1 a2 a3
; b0  0  8  1  7
; b1  9  2  6  x
; b2  3  5  x  x
; b3  4  x  x  x


; Interface: HL=H*E
; 57 M cycles (AVG, including call/ret)
;UMUL_8_8:

UMUL_32_32::
	; Do the one and only shift-0 op.
	; Op 0: a0*b0
	ldh	A,[mul_buffer_in_b._0]
	ld	E,A

	ldh	A,[mul_buffer_in_a._0]
	ld	H,A

	call	UMUL_8_8

	ld	A,L
	ldh	[mul_buffer._0],A
	ld	A,H
	ldh	[mul_buffer._1],A

	; Op 1: a2*b0
	; Doing this op in particular here is a micro-optimization.
	; 1) DE (b0) is still preserved and doesn't need to be reloaded from RAM.
	; 2) Because this the second operation, we can immediately write it to the 
	;    result without needing to add it, as long as it's shifted 2 steps.
	; We also do all shift-2 parts now. This is ok because any overflow is
	; going to be truncated anyway.
	;ldh	A,[mul_buffer_in_b._0]
	;ld	E,A

	ldh	A,[mul_buffer_in_a._2]
	ld	H,A
	call	UMUL_8_8

	ld	B,H			; Save for later addition.
	ld	C,L
	; BC now contains a2*b0

	; Op 2: a1*b1
	ldh	A,[mul_buffer_in_a._1]
	ld	E,A

	ldh	A,[mul_buffer_in_b._1]
	ld	H,A
	call	UMUL_8_8

	add	HL,BC			; Add to BC.
	ld	B,H			; Save for later addition.
	ld	C,L
	; BC now contains a2*b0 + a1*b1

	; Op 3: a0*b2
	; Put a0 in DE for later reuse.
	ldh	A,[mul_buffer_in_a._0]
	ld	E,A

	ldh	A,[mul_buffer_in_b._2]
	ld	H,A
	call	UMUL_8_8

	add	HL,BC			; Add to BC.
	ld	B,H			; Save for later addition.
	ld	C,L
	; BC now contains a2*b0 + a1*b1 + a0*b2

	; Now do all the shift-3 operations. These can likewise be added to BC
	; without regard for truncation. However, these are now 8 bit operations, 
	; since only byte 3 of the complete sum is affected.

	; Op 4: a0*b3
	; DE is already a0 from the previous op.
	;ldh	A,[mul_buffer_in_a._0]
	;ld	E,A

	ldh	A,[mul_buffer_in_b._3]
	ld	H,A

	call	UMUL_8_8

	ld	A,B
	add	L
	ld	B,A
	; BC now contains (a2*b0 + a1*b1 + a0*b2) + a0*b3

	; Op 5: a1*b2
	ldh	A,[mul_buffer_in_a._1]
	ld	E,A

	ldh	A,[mul_buffer_in_b._2]
	ld	H,A

	call	UMUL_8_8

	ld	A,B
	add	L
	ld	B,A
	; BC now contains (a2*b0 + a1*b1 + a0*b2) + a0*b3 + a1*b2

	; Op 6: a2*b1
	ldh	A,[mul_buffer_in_a._2]
	ld	E,A

	ldh	A,[mul_buffer_in_b._1]
	ld	H,A

	call	UMUL_8_8

	ld	A,B
	add	L
	ld	B,A
	; BC now contains (a2*b0 + a1*b1 + a0*b2) + a0*b3 + a1*b2 + a2*b1

	; Op 7: a3*b0
	; Put b0 in DE for later reuse.
	ldh	A,[mul_buffer_in_b._0]
	ld	E,A

	ldh	A,[mul_buffer_in_a._3]
	ld	H,A

	call	UMUL_8_8

	ld	A,B
	add	L
	; A contains 
	; BC now contains (a2*b0 + a1*b1 + a0*b2) + (a0*b3 + a1*b2 + a2*b1 + a3*b0)

	; All shift-2 and shift-3 ops done.
	; Now do the two shift-1 ops. Store the topmost byte. This may need to be
	; adjusted for carry which then becomes a memory bound operation.
	ldh	[mul_buffer._3],A

	; Now make BC contain bytes 1 and 2.
	; b3 b2 b1 b0
	; BB CC mm mm ...becomes...
	; mm BB CC mm so move C in B and load memory into C.
	ld	B,C
	ldh	A,[mul_buffer._1]
	ld	C,A

	; Op 8: a1*b0
	; DE already contains b0 from before.
	;ldh	A,[mul_buffer_in_b._0]
	;ld	E,A

	ldh	A,[mul_buffer_in_a._1]
	ld	H,A

	call	UMUL_8_8

	add	HL,BC			; Add to BC.
	ld	B,H			; Save for later addition.
	ld	C,L

	jr	nc,:+
	ld	HL,mul_buffer._3	; We're free to reuse HL now.
	inc	[HL]			; Adjust for carry.
:

	; Op 9: a0*b1
	ldh	A,[mul_buffer_in_a._0]
	ld	E,A

	ldh	A,[mul_buffer_in_b._1]
	ld	H,A

	call	UMUL_8_8
	add	HL,BC			; Add to BC.
	; Keep track of carry!

	ld	A,L
	ldh	[mul_buffer._1],A
	ld	A,H
	ldh	[mul_buffer._2],A

	; And as the last thing, adjust byte 3 for carry!
	jr	nc,:+
	ld	HL,mul_buffer._3	; We're free to reuse HL now.
	inc	[HL]			; Adjust for carry.
:

	ret

