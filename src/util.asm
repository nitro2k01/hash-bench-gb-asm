include "incs/hardware.inc"
; This file is meant to be viewed using tabs for indentation and tab width 8.

SECTION "Util", ROM0
; Simple, slow memcopy.
; HL=Source.
; DE=Destination.
; BC=Length.
COPY::
	ld	A,[HL+]
	ld	[DE],A
	inc	DE
	dec	BC
	ld	A,B
	or	C
	jr	nz,COPY
	ret

; Compares up to 256 bytes of memory.
; HL=String 1
; DE=String 2
; B =Length
; Return values: 
; A==0, z if the strings are equal or A!=0, nz if not equal.
; HL and DE point to the first non-matching bytes.
MEMCMP_SMALL::
:	ld	A,[DE]
	sub	[HL]
	ret	nz
	inc	DE
	inc	HL
	dec	B
	jr	nz,:-
	ret

; Clears memory in 256 byte chunks up to a page boundary.
; E=Value to clear with.
; HL=Start address.
; B=End address (Exclusive.)
; Example: To clear WRAM:
; E=0 HL=$C000 B=$E0
FASTCLEAR::
	ld	A,E
	;xor	A
	ld	C,64
.loop::
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	dec	C
	jr	nz,.loop
	ld	A,H
	cp	B
	ret	z
	jr	FASTCLEAR

; Minimal print function
MPRINT::
	ld	A,[HL+]
	or	A
	ret	z
	cp	"\n"
	jr	z,.nextrow
	push	BC
	ld	B,A
:	ld	A,B
	ld	[DE],A
	ld	A,[DE]
	cp	B
	jr	nz,:-
	pop	BC
	inc	DE
	jr	MPRINT
.nextrow
	ld	A,E
	and	$E0
	add	$20
	ld	E,A
	jr	nc,MPRINT
	inc	D
	jr	MPRINT

; Print one hexadecimal byte.
PRINTHEX::
	ld	E,A
	swap	A
	;call	PRINTHEX_DIGIT
	and	$0F
	add	$70
	cp	$7A
	jr	c,.noupper
	add	7
.noupper
	ld	[HL+],A

	ld	A,E
PRINTHEX_DIGIT::
	and	$0F
	add	$70
	cp	$7A
	jr	c,.noupper
	add	7
.noupper
	ld	[HL+],A
	ret

; Print one hexadecimal byte, using "nitrocopy".
PRINTHEX_FORCE::
	ld	E,A
	swap	A
	call	PRINTHEX_DIGIT_FORCE
	ld	A,E
PRINTHEX_DIGIT_FORCE::
	and	$0F
	add	$70
	cp	$7A
	jr	c,.noupper
	add	7
.noupper
.confirm
	ld	[HL],A
	cp	[HL]
	jr	nz,.confirm
	inc	HL
	ret

; Calculate the checksum of a 32k ROM only ROM.
; Return value
;  BC=calculated checksum.
;   A=0 if matching the header or nonzero if not.
;   z=1 if matching the header or 0 if not.
CALC_CHECKSUM_32K::
	ld	A,1
	ld	HL,$2000
	ld	[HL],A
	ld	H,L			; HL=$0000

	ld	BC,0
.loop
	; Partial unrolling for extra speed.
REPT	4
	ld	A,[HL+]
	add	C
	ld	C,A
	jr	nc,:+
	inc	B
:
	ENDR

	bit	7,H
	jr	z,.loop

	; Adjust checksum by subtracting the checksum field.
	; Assume A still contains lower byte.
	ld	HL,$014E		; Upper byte of global checksum.
	sub	[HL]
	jr	nc,:+
	dec	B
:
	inc	L			; Lower byte of global checksum.

	sub	[HL]
	jr	nc,:+
	dec	B
:
	ld	C,A			; Store lower byte of calculated checksum.

	sub	[HL]			; Compare lower byte.
	ret	nz

	dec	L			; Upper byte of global checksum.
	ld	A,B
	sub	[HL]			; Compare lower byte.
	ret

READ_JOYPAD::
	ld	A,P1F_GET_DPAD
	ldh	[rP1],A
	ldh	A,[rP1]
	ldh	A,[rP1]
	ldh	A,[rP1]
	ldh	A,[rP1]
	cpl
	and	$0F
	swap	A
	ld	B,A
	ld	A,P1F_GET_BTN
	ldh	[rP1],A
	ldh	A,[rP1]
	ldh	A,[rP1]
	ldh	A,[rP1]
	ldh	A,[rP1]
	ldh	A,[rP1]
	cpl
	and	$0F
	or	B
	ld	C,A
	ld	A,[joypad_held]
	xor	C
	and	C
	ld	[joypad_pressed],A
	ld	A,C
	ld	[joypad_held],A
	ld	A,P1F_GET_NONE
	ldh	[rP1],A
	ret
