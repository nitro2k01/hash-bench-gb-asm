include "incs/hardware.inc"
include "incs/charmaps.inc"
include "incs/debug.inc"
; This file is meant to be viewed using tabs for indentation and tab width 8.


SECTION "rst08", ROM0[$08]
CALL_HL::
	jp	HL

SECTION "rst38", ROM0[$38]
:	ld	b,b
	jr	:-

SECTION "Vblank", ROM0[$40]
	push	AF
	jp	HANDLE_VBL

SECTION "Serial", ROM0[$50]
	push	AF
	push	HL
	ld	HL,clock_state
	jp	HANDLE_TIMER



SECTION "Timer", ROM0[$58]
	reti

SECTION "NMI", ROM0[$80]
	reti

SECTION "Entry", ROM0[$100]
	di				; 1
	jp	ENTRY			; 4

SECTION "Header", ROM0[$104]
	ds	$150 - @, 0		; Fill up the rest of the header area with zeros and let rgbfix deal with it.

SECTION "Main", ROM0[$150]
ENTRY::
	ld	SP,STACK.top
	ldh	[gbc_flag],A

	ld	A,1
	ld	[$2000],A

	xor	A
	ld	C,LOW(clear_after_here)
:	ld	[$FF00+C],A
	inc	C
	jr	nz,:-

	; Wait for VBlank.

	; Disable LCD to load some graphics
	ld	A,LCDCF_BG8000|LCDCF_BG9C00|LCDCF_BGON
	ldh	[rLCDC],A

	call	LOAD_TILES


	; Clear OAM.
	ld	HL,$FEA0
	xor	A
:	dec	L
	ld	[HL],A
	jr	nz,:-

	; Clear the map.
	ld	HL,$9800
	ld	B,$9C			; Top byte of end address
	ld	E,L			; L==0
	call	FASTCLEAR

	; Detect whether running on GBC from previously stored value.
	ld	A,[gbc_flag]
	sub	$11
	jr	z,:+
	ld	A,$FF
:	inc	A
	ld	[gbc_flag],A

	call	nz,INIT_GBC_MINIMAL

	; Print main screen string.
	ld	HL,S_ALL
	LDXY	DE,0,0
	call	MPRINT

	ld	HL,S_TOTAL_TIME
	LDXY	DE,1,$10
	call	MPRINT

	; Misc graphics init.
	ld	A,$D0
	ldh	[rWX],A
	ldh	[rWY],A

	xor	A
	ldh	[rSCX],A
	ldh	[rSCY],A

	ld	A,%11100100
	ldh	[rBGP],A



	call	fill_workload_buffer

	ld	A,LCDCF_ON|LCDCF_BG8000|LCDCF_BG9800|LCDCF_BGON
	ldh	[rLCDC],A

	call	clock_init

	xor	A
	ldh	[rIF],A
	ld	A,IEF_VBLANK|IEF_TIMER
	ldh	[rIE],A

	ei

	; Time the whole sweep.
	ld	HL,global_startclock
	call	clock_gettime

	; Perform the sweep.
	call	perform_test_sweep

	; Record the end time and print the delta.
	; Using bench_endclock for now because it's not used any more
	; and hardcoded print_bench_time.
	; TODO: refactor that whole mess.
	ld	HL,bench_endclock
	call	clock_gettime

	ld	BC,bench_endclock
	ld	HL,global_startclock
	call	SUB_32BIT

	LDXY	HL,$c,$10
	call	print_bench_time

.el	halt
	nop
	jr	.el

perform_test_sweep::
	xor	A
	jr	.store_test_idx
.test_loop
	ldh	A,[current_test_idx]
	inc	A
.store_test_idx
	ldh	[current_test_idx],A

	ld	B,A
	add	A			; *2
	add	A			; *4
	add	B			; *5
	
	add	LOW(test_list)
	ld	L,A
	adc	HIGH(test_list)
	sub	L
	ld	H,A

	push	HL
	; Get string pointer
	ld	A,[HL+]
	ld	H,[HL]
	ld	L,A

	; Check if null pointer, if so we reached the end of the list.
	or	H
	jr	nz,.continue
	pop	HL			; Unroll and return.
	ret
.continue

	; Calculate print position.
	; XY 0,2 -> $9840. Let's deal with the Y position before multiplying.
	ldh	A,[current_test_idx]
	inc	A
	inc	A
	swap	A			; *16 TODO: we're assuming max 16 rows, 14 tests here.
	add	A			; *32, plus carry
	ld	E,A
	adc	$98
	sub	E
	ld	D,A

	call	MPRINT

	ld	HL,hash_buffer
	xor	A
	rept 16
		ld	[HL+],A
	endr

	pop	HL			; Get and re-save the table pointer.
	push	HL
	push	DE

	; Get test address.
	inc	HL
	inc	HL
	ld	A,[HL+]
	ld	H,[HL]
	ld	L,A

	; Call the actual test
	; This function also starts the benchmark timer.
	DEBUG_MSG	"%ZEROCLKS%%HL%"
.gt_before_test
	call	CALL_HL_TEST
.gt_after_test
	DEBUG_MSG	"%LASTCLKS%"

	; Get stop time.
	ld	HL,bench_endclock
	call	clock_gettime

	pop	DE
	pop	HL

	; Skip over test address, get length.
	inc	HL
	inc	HL
	inc	HL
	inc	HL
	ld	C,[HL]

	; Get current line address, and reset to the start of the line and then skip forward 6 steps to where the hash data should be written.
	ld	H,D
	ld	A,E
	and	%1110_0000
	add	6
	ld	L,A

	dec	C			; Check ==1? 
	ld	C,LOW(hash_buffer)
	jr	z,.just_one		; If length==1, print one char. If >1 print two chars as a fingerprint.
	ldh	A,[C]
	call	PRINTHEX_FORCE
	inc	C
.just_one
	ldh	A,[C]
	call	PRINTHEX_FORCE

	push	HL
	; Subtract startclock from endclock.
	ld	BC,bench_endclock
	ld	HL,bench_startclock
	call	SUB_32BIT
	pop	HL

	; Get current line address, and reset to the start of the line and then skip forward 11 steps to where the time should be written.
	ld	A,L
	and	%1110_0000
	add	11
	ld	L,A

	call	print_bench_time
if 0

	ld	A,[bench_endclock._secs_dw]
	call	PRINTHEX_FORCE

	ld	A,[bench_endclock._256ths]
	call	PRINTHEX_FORCE
	ld	A,[bench_endclock._timer]
	call	PRINTHEX_FORCE
endc

	jp	.test_loop


print_bench_time:
	; Print seconds. TODO: print in decimal instead of hex. (Or let's just yolo and hope nothing takes more than 9 seconds :) )
	ld	A,[bench_endclock._secs_dw]
	call	PRINTHEX_FORCE

	push	HL			; Push the current print pointer.
	; Do some multiplication.
	ld	HL,bench_endclock._timer
	ld	BC,1000
	call	UMUL_16_MEM16

	; Convert to decimal.
	ld	HL,mul_buffer+2
	ld	A,[HL+]
	ld	H,[HL]
	ld	L,A
	; Hundreds (aka 10ths) digits.
	ld	DE,-100
SETCHARMAP shaded
	ld	A,"0"
SETCHARMAP default
:	add	HL,DE
	jr	nc,:+
	inc	A
	jr	:-
:
	ldh	[scratch_buffer+1],A

	; Undo the last subtract. The rest of the calculation can be done with 8 bit math.
	ld	A,L
	add	100
SETCHARMAP shaded
	ld	DE,(10<<8)|"0"		; Values to use with the tens calculation
SETCHARMAP default
:	sub	D
	jr	c,:+
	inc	E
	jr	:-
:
	; Undo the last subtract. 
	add	D
SETCHARMAP shaded
	add	"0"			; This is now the value of the ones (aka thousandth) digit. Add the offset for "0".
SETCHARMAP default
	ldh	[scratch_buffer+3],A

	ld	A,E			; And finally E holds the tens (aka hundredth) digit.
	ldh	[scratch_buffer+2],A
	xor	A			; Add null termination.
	ldh	[scratch_buffer+4],A
	ld	HL,scratch_buffer	;
SETCHARMAP shaded
	ld	[HL],"."		; Add decimal point.
SETCHARMAP default

	pop	DE			; Pop the current print pointer.
	call	MPRINT
	ret

decimal_calc_digit:



CALL_HL_TEST::
	; Push the test's call address.
	push	HL

	; Start the benchmark timer.
	ld	HL,bench_startclock
	call	clock_gettime

	ld	HL,workload_buffer
	ld	DE,workload_buffer.end-workload_buffer

	; This ret jumps to the test. 
	; The test's ret returns to the test instrumentation loop.
	ret

; Subtract one little-endian 32 bit number from another.
; [BC] = [BC] - [HL]
SUB_32BIT::
	; Byte 0
	ld	A,[BC]
	sub	[HL]
	ld	[BC],A

	inc	HL
	inc	BC

	; Byte 1
	ld	A,[BC]
	sbc	[HL]
	ld	[BC],A

	inc	HL
	inc	BC

	; Byte 2
	ld	A,[BC]
	sbc	[HL]
	ld	[BC],A

	inc	HL
	inc	BC

	; Byte 3
	ld	A,[BC]
	sbc	[HL]
	ld	[BC],A

	ret

; Adjust a length setting in DE for use with a dec E/dec D loop. 
; If the E is not zero, the outer loop would have an incorrect number of iterations.
; In the worst case, if D==0, you get 256 iterations of the outer loop!
adjust_length_de::
	inc	E
	dec	E			; Zero check of E while keeping E's old value.
	ret	z
	inc	D
	ret


SECTION "test list", ROM0
test_list::
	; String, function, hash length
	dw S_CRC8
	dw hash_crc8
	db 1

	dw S_CRC16
	dw hash_crc16
	db 2

	dw S_CRC32
	dw hash_crc32
	db 4

	dw S_CRC32R
	dw hash_crc32r
	db 4

	dw S_CRC64
	dw hash_crc64
	db 8

	dw S_ADLER32
	dw hash_adler32
	db 4

	dw S_FLT16
	dw hash_flt16
	db 2

	dw S_PRSN8
	dw hash_prsn8
	db 1

	dw S_KNUTH
	dw hash_knuth
	db 4

	dw S_FNV1A
	dw hash_fnv1a32
	db 4



	dw 0

S_CRC8: db "CRC8",0
S_CRC16: db "CRC16",0
S_CRC32: db "CRC32M",0
S_CRC32R: db "CRC32R",0
S_CRC64: db "CRC64",0
S_ADLER32: db "ADL32",0
S_PRSN8: db "PRSN8",0
S_FLT16: db "FLT16",0
S_KNUTH: db "KNUTH",0
S_FNV1A: db "FNV1A",0

SECTION "hash CRC8", ROM0
; CRC-8/SMBUS (poly 0x07, init 0x00, no reflect, no xorout).
;
; The simplest CRC variant — 8-bit register, one xor + 8 shift/conditional-
; xor pairs per byte. Used by SMBus, I²C error detection, DVB-S2 frame
; headers. Bit-by-bit (no table) to keep ROM cost minimal.
; 
; Input: HL=Pointer to start of workload buffer. DE=length of workload buffer in bytes.
; Output: hash placed in hash_buffer
hash_crc8::
	call	adjust_length_de
	xor	A
	ld	B,$07			; Poly value.
.loop:	xor	[HL]
	; Full unroll for extra wroom.
	; Each iter is 4 bytes, so full unroll takes 32 bytes.
	REPT	8
		add	A		; Shift and get top bit in carry.
		jr	nc,:+
		xor	B
:
	ENDR
	inc	HL
	dec	E
	jr	nz,.loop
	dec	D
	jr	nz,.loop

	ldh	[hash_buffer],A

	ret

SECTION "hash CRC16", ROM0
; CRC-16/XMODEM (poly 0x1021, init 0x0000, no xorout, MSB-first).
;
; Table-less variant — the per-byte inner loop is 8 iterations, which is
; the slowest of the CRC implementations here but uses no ROM for tables.
; Useful as a "what does the naive case look like?" baseline.
;
; Input: HL=Pointer to start of workload buffer. DE=length of workload buffer in bytes.
; Output: hash placed in hash_buffer
hash_crc16::
	call	adjust_length_de

	; Use BC as the input pointer, and HL as the state, to be able to use add HL,HL.

	ld	B,H
	ld	C,L

	ld	HL,00

.loop:	ld	A,[BC]
	xor	H
	ld	H,A

	; Each iter is 11 bytes, so full unroll takes 88 bytes.
	rept 8
		add	HL,HL		; Shift and get top bit in carry.
		jr	nc,:+
		ld	A,L
		xor	$21
		ld	L,A
		ld	A,H
		xor	$10
		ld	H,A
:
	endr
	
	inc	BC
	dec	E
	jr	nz,.loop
	dec	D
	jr	nz,.loop

	; Store big endian to follow the same convention as the original test.
	ld	A,L
	ldh	[hash_buffer+1],A
	ld	A,H
	ldh	[hash_buffer],A

	ret

; CRC-32/IEEE 802.3 (poly 0xEDB88320 reflected, init 0xFFFFFFFF, xorout
; 0xFFFFFFFF, reflected I/O). The textbook PNG / zlib / Ethernet CRC.
;
; Table-less reflected variant — same as crc16, no ROM table. Mostly
; here so we can see how much slower 32-bit arithmetic is on the SM83
; versus ARM7. (A 256-entry table would be ~4× faster but costs 1 KiB
; of ROM and obscures the actual algorithmic cost we're trying to
; measure.)
;
; Input: HL=Pointer to start of workload buffer. DE=length of workload buffer in bytes.
; Output: hash placed in hash_buffer
SECTION "hash CRC32", ROM0
def CRC32_POLY = $EDB88320
hash_crc32::
	call	adjust_length_de

	; Use BC as the input pointer, HL as the pointer to the has output, which also acts as the state buffer.
	ld	B,H
	ld	C,L

	; Init the state.
	ld	HL,hash_buffer
	ld	A,$FF
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A

	; Use hash_buffer+4 as a temp variable for counting the 8 shifts.


.loop:	ld	HL,hash_buffer			; Point to lowest byte initially for the xor.
	ld	A,8
	ldh	[hash_buffer+4],A

	ld	A,[BC]				; Get data byte to process.
	xor	[HL]
	ld	[HL],A				; Write back to state[0].

.inner_loop
	ld	L,LOW(hash_buffer+3)		; This is ok because hash_buffer is guaranteed to be aligned.

	xor	A				; Clear carry flag, side effect of any xor.
	rept 3
		ld	A,[HL]
		rra				; Rotate through carry and write back.
		ld	[HL-],A
	endr

	; Last iteration is a bit different.
	ld	A,[HL]
	rra					; Rotate through carry and check c to see if we should xor.
	jr	nc,.no_xor			; The write jumped to increments HL. This doesn't matter though.

	; Go back the other way from the bottom.
	xor	(CRC32_POLY)&$FF
	ld	[HL+],A
	ld	A,[HL]
	xor	(CRC32_POLY>>8)&$FF
	ld	[HL+],A
	ld	A,[HL]
	xor	(CRC32_POLY>>16)&$FF
	ld	[HL+],A
	ld	A,[HL]
	xor	(CRC32_POLY>>24)&$FF
.no_xor
	ld	[HL+],A

	; Number of shifts.
	;ldh	A,[hash_buffer+4]
	;dec	A
	;ldh	[hash_buffer+4],A
	ld	L,LOW(hash_buffer+4)
	dec	[HL]
	jr	nz,.inner_loop
	
	
	inc	BC
	dec	E
	jr	nz,.loop
	dec	D
	jr	nz,.loop


	; Final conditioning. XOR with 0xFFFFFFFF
	ld	HL,hash_buffer+3
	rept 4
		ld	A,[HL]
		cpl
		ld	[HL-],A
	endr

	ret

; CRC-32 but state kept within registers and RAM used for the loop variables instead.
; Keep the hash state in BCDE and the length variables in RAM.
;
; Input: HL=Pointer to start of workload buffer. DE=length of workload buffer in bytes.
; Output: hash placed in hash_buffer
hash_crc32r::
	call	adjust_length_de

	; Use hash_buffer+5 and 6 as a temp variable for counting the 8 shifts.
	ld	A,E
	ldh	[hash_buffer+5],A
	ld	A,D
	ldh	[hash_buffer+6],A

	; Init the state.
	ld	BC,$FFFF
	ld	E,C
	ld	D,B

.loop:	; Use hash_buffer+4 as a temp variable for counting the 8 shifts.
	ld	A,8
	ldh	[hash_buffer+4],A

	ld	A,[HL+]				; Get byte from workload buffer.
	xor	E				; xor with state[0] which is in E.
	ld	E,A				; Write back to E.

.inner_loop
	srl	B				; Shift the 32 bit state one step.
	rr	C
	rr	D
	rr	E

	jr	nc,.no_xor

	ld	A,E
	xor	(CRC32_POLY)&$FF
	ld	E,A
	ld	A,D
	xor	(CRC32_POLY>>8)&$FF
	ld	D,A
	ld	A,C
	xor	(CRC32_POLY>>16)&$FF
	ld	C,A
	ld	A,B
	xor	(CRC32_POLY>>24)&$FF
	ld	B,A
.no_xor
	ldh	A,[hash_buffer+4]
	dec	A
	ldh	[hash_buffer+4],A
	jr	nz,.inner_loop

	ldh	A,[hash_buffer+5]
	dec	A
	ldh	[hash_buffer+5],A
	jr	nz,.loop
	ldh	A,[hash_buffer+6]
	dec	A
	ldh	[hash_buffer+6],A
	jr	nz,.loop


	; Final conditioning. XOR with 0xFFFFFFFF
	ld	HL,hash_buffer
	ld	A,E
	cpl
	ld	[HL+],A
	ld	A,D
	cpl
	ld	[HL+],A
	ld	A,C
	cpl
	ld	[HL+],A
	ld	A,B
	cpl
	ld	[HL+],A

	ret

; CRC-64/ECMA-182 (poly 0x42F0E1EBA9EA3693, init 0, no reflect, no xorout).
;
; The "DLT-1 / ECMA-182" variant standardised for backup-tape error
; detection. Used by btrfs, .xz container format, and a handful of
; archive formats. 64-bit CRC register, MSB-first; bit-by-bit (no
; table) to keep ROM cost minimal at the price of speed (8 conditional
; shifts per input byte).
;
; Reference: crc64(buf) = 29103DD16C9C1449 for our standard 1024-byte
; buffer. Cross-check with `crc64sum --type=ecma` if available, or
; `crcmod.predefined.mkPredefinedCrcFun('crc-64')`.
;
; Input: HL=Pointer to start of workload buffer. DE=length of workload buffer in bytes.
; Output: hash placed in hash_buffer
SECTION "hash CRC64", ROM0
def CRC64_POLY_HI = $42F0E1EB
def CRC64_POLY_LO = $A9EA3693
hash_crc64::
	call	adjust_length_de

	; Use BC as the input pointer, HL as the pointer to the has output, which also acts as the state buffer.
	ld	B,H
	ld	C,L

	; Init the state.
	ld	HL,hash_buffer
	xor	A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A

.loop:	ld	HL,hash_buffer+7		; Point to highest byte initially for the xor.
	; Use hash_buffer+8 as a temp variable for counting the 8 shifts.
	ld	A,8
	ldh	[hash_buffer+8],A

	ld	A,[BC]				; Get data byte to process.
	xor	[HL]
	ld	[HL],A				; Write back to state[7].

.inner_loop
	ld	L,LOW(hash_buffer)		; This is ok because hash_buffer is guaranteed to be aligned.

	ld	A,[HL]
	add	A				; The first shift is a logical left shift expressed as an addition.
	ld	[HL+],A

	rept 6
		ld	A,[HL]
		rla				; Rotate through carry and write back.
		ld	[HL+],A
	endr

	ld	A,[HL]
	rla					; Rotate through carry and write back.

	jr	nc,.no_xor

	; Go back the other way from the top.
	xor	(CRC64_POLY_HI>>24)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_HI>>16)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_HI>>8)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_HI)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_LO>>24)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_LO>>16)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_LO>>8)&$FF
	ld	[HL-],A
	ld	A,[HL]
	xor	(CRC64_POLY_LO)&$FF
.no_xor
	ld	[HL-],A

	; Number of shifts.
	;ldh	A,[hash_buffer+4]
	;dec	A
	;ldh	[hash_buffer+4],A
	ld	L,LOW(hash_buffer+8)
	dec	[HL]
	jr	nz,.inner_loop
	
	
	inc	BC
	dec	E
	jr	nz,.loop
	dec	D
	jr	nz,.loop


	ret

; Adler-32 (RFC 1950 — zlib's checksum). Two running 16-bit accumulators
; mod 65521, recombined into a 32-bit output. The classic "almost as
; cheap as a sum, much better collision resistance" checksum.
;
; NMAX (5552) is the largest run that keeps the inner sums inside
; uint32_t without modding every iteration — we never approach that for
; a 1024-byte block, so the mod fires exactly once at the end.
;
; Input: HL=Pointer to start of workload buffer. DE=length of workload buffer in bytes.
; Output: hash placed in hash_buffer
SECTION "hash Adler32", ROM0
def ADLER_MOD = 65521
hash_adler32::
	call	adjust_length_de

	; Use hash_buffer+5 and 6 as a temp variable for counting the 8 shifts.
	ld	A,E
	ldh	[hash_buffer+5],A
	ld	A,D
	ldh	[hash_buffer+6],A

	; Use BC as the source pointer...
	ld	B,H
	ld	C,L

	; ... because we're using DE for the A sum and HL for the B sum.
	; A=1; B=0;
	ld	DE,$0001
	ld	H,D				; Slightly faster way of initing sum B as 0.
	ld	L,D

.loop
	; Add the current workload byte to the A sum.
	ld	A,[BC]
	add	E
	ld	E,A
	jr	nc,.nomod_a
	inc	D
	jr	nz,.nomod_a			; Check for overflow, to apply the modulo.

	; Modulo needs to be applied: subtract the mod value.
	sub	LOW(ADLER_MOD)
	ld	E,A

	ld	A,D
	sbc	HIGH(ADLER_MOD)
	ld	D,A
.nomod_a
	; B += A
	add	HL,DE

	jr	nc,.nomod_b

	push	DE
	ld	DE,-ADLER_MOD
.mod_again:
	add	HL,DE
	; Because of the janky way the modulo is calculated lazily, we might need to apply a second subtraction.
	; Because mod is only applied when the 16 bit value overflows, it's possible that the A sum contains a value >ADLER_MOD
	; Then when B+=A happens, if it too holds a value >ADLER_MOD you might get an incorrect value.
	; Example: ADLER_MOD=$FFF1 by definition. A=$FFFE, B=$FFFE
	; Expected value: ($FFFE+$FFFE) % $FFF1 = $001A
	; Potential hazard: $FFFE+$FFFE=$1FFFC which is truncated to $FFFC in a 16 bit register.
	; $FFFC - $FFF1 = $000B, which is the wrong value. This would mess up the whole further calculation.
	; But this is detected here because the carry flag was set, and one more subtraction is done.
	; $000B - $FFF1 = $001A which is the correct value.
	jr	c,.mod_again
	pop	DE

.nomod_b
	inc	BC

	; Check length.
	ldh	A,[hash_buffer+5]
	dec	A
	ldh	[hash_buffer+5],A
	jr	nz,.loop
	ldh	A,[hash_buffer+6]
	dec	A
	ldh	[hash_buffer+6],A
	jr	nz,.loop

	; Move the B sum into BC since we want the B sum on the lower addresses.
	ld	C,L
	ld	B,H
	; Write desination.
	ld	HL,hash_buffer+1		; Do this becuase we have to write the lower byte first to keep the same convention as the original...
	call	.tail

	; Move the A sum into BC to fix and write it next, then fallthrough and return from the hash calculation.
	ld	C,E
	ld	B,D

.tail::
	; Final mod for the A sum, which only looks for value in the range $FFF1-FFFF.
	ld	A,C				; Preliminary writes.
:	ld	[HL-],A				; Write and go backward.
	ld	A,B
	ld	[HL+],A				; Write and go forward to the original address, in case we need to rewrite!

	inc	B				; == $ff?
	jr	nz,:+				; -> No, done.
	ld	A,C
	sub	LOW(ADLER_MOD)
	; If nc here, it means SUM_A>=$FFF1. Or, "A-$F1 > 0".
	; If so, all values are as we want them. The A register has had it exceeding paert subtracted.
	; D==0 from the $FF check.
	; Jump back and rewrite!
	jr	nc,:-
:	inc	HL				; Move the pointer to the bytes after the ones written.
	inc	HL
	ret


SECTION "hash Pearson-8", ROM0
; Pearson hashing (8-bit) — h = T[h ^ c] for each input byte, where T
; is any permutation of {0..255}. Single load + xor + table lookup per
; byte, no arithmetic. Trivially the fastest algorithm in this suite
; once the table is in ROM.
;
; Output is 8 bits — the original Pearson paper proposed extending the
; digest by re-hashing with different start states, but we report just
; the single-byte result and let the caller decide whether to chain.
;
; The permutation table here was generated via Fisher-Yates on
; range(256) seeded with 0xCAFEBABE — deterministic, no canonical
; "official" table exists for Pearson hashing.
hash_prsn8::
	call	adjust_length_de
	xor	A
	ld	B,HIGH(hash_prsn8_table)
.loop:	xor	[HL]
	ld	C,A
	ld	A,[BC]

	inc	HL
	dec	E
	jr	nz,.loop
	dec	D
	jr	nz,.loop

	ldh	[hash_buffer],A

	ret


SECTION "hash Pearson-8 aligned table", ROM0, ALIGN[8]
hash_prsn8_table:
	db $B7, $82, $BF, $E0, $03, $B6, $E9, $93,
	db $10, $61, $25, $DC, $EA, $A4, $34, $D2,
	db $1C, $7A, $E5, $22, $CB, $68, $91, $DA,
	db $EE, $97, $D8, $6A, $EB, $1D, $70, $F9,
	db $18, $AA, $F6, $B1, $B2, $71, $BB, $A6,
	db $C8, $4B, $99, $28, $D4, $F1, $42, $A9,
	db $B9, $E1, $05, $63, $48, $A5, $72, $AE,
	db $EF, $8B, $AF, $04, $81, $60, $12, $D7,
	db $6D, $07, $0A, $17, $5D, $F8, $47, $B5,
	db $E4, $3F, $86, $F3, $CA, $6C, $2F, $45,
	db $B3, $6F, $8E, $94, $9A, $B0, $EC, $08,
	db $D1, $AC, $66, $37, $A2, $50, $38, $4C,
	db $6B, $74, $29, $78, $5C, $4D, $BC, $A3,
	db $FF, $77, $E7, $39, $85, $67, $F2, $89,
	db $1F, $96, $AB, $A1, $26, $3B, $46, $E8,
	db $0F, $D6, $15, $23, $9D, $3D, $E6, $21,
	db $06, $1A, $CD, $7D, $C1, $98, $7B, $1B,
	db $C0, $A8, $59, $2E, $A7, $54, $7E, $2A,
	db $DF, $C4, $19, $30, $69, $87, $2B, $ED,
	db $F4, $F0, $24, $FB, $4E, $D5, $0B, $55,
	db $E3, $27, $11, $BD, $0D, $4F, $56, $BA,
	db $62, $01, $FC, $64, $9E, $31, $33, $AD,
	db $20, $7F, $CF, $9F, $02, $41, $9B, $36,
	db $BE, $8C, $80, $35, $D0, $13, $FA, $09,
	db $7C, $52, $D3, $5A, $92, $00, $75, $C9,
	db $58, $40, $F7, $44, $8F, $E2, $3E, $FD,
	db $A0, $C5, $57, $95, $14, $8D, $65, $73,
	db $79, $9C, $DB, $D9, $CE, $5E, $51, $B4,
	db $CC, $DE, $8A, $F5, $32, $3A, $1E, $0C,
	db $5F, $FE, $C7, $4A, $DD, $2C, $0E, $2D,
	db $83, $49, $53, $C6, $84, $6E, $88, $3C,
	db $5B, $16, $B8, $76, $C3, $43, $90, $C2,

SECTION "hash Knuth multiplicative", ROM0
; Knuth multiplicative — `h = (h XOR c) * golden` per byte. The golden
; constant 0x9E3779B1 is 2^32 / phi rounded; recommended by Knuth for
; 32-bit hash tables (TAOCP vol 3 §6.4).
def KNUTH_GOLDEN = $9E3779B1

hash_knuth::
	call	adjust_length_de
	; Use hash_buffer+5 and 6 as a temp variable for counting the 8 shifts.
	ld	A,E
	ldh	[hash_buffer+5],A
	ld	A,D
	ldh	[hash_buffer+6],A

	; Init the multiplication source buffers.
	push	HL
	ld	HL,mul_buffer
	xor	A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A

	ld	HL,mul_buffer_in_b
	ld	A,(KNUTH_GOLDEN>>0)&$FF
	ld	[HL+],A
	ld	A,(KNUTH_GOLDEN>>8)&$FF
	ld	[HL+],A
	ld	A,(KNUTH_GOLDEN>>16)&$FF
	ld	[HL+],A
	ld	A,(KNUTH_GOLDEN>>24)&$FF
	ld	[HL+],A


	pop	HL
.loop
	; Copy from the result to the source, and perform xor with the data stream.
	ldh	A,[mul_buffer._0]
	xor	[HL]
	ldh	[mul_buffer_in_a._0],A
	ldh	A,[mul_buffer._1]
	ldh	[mul_buffer_in_a._1],A
	ldh	A,[mul_buffer._2]
	ldh	[mul_buffer_in_a._2],A
	ldh	A,[mul_buffer._3]
	ldh	[mul_buffer_in_a._3],A

	;DEBUG_MSG	"%ZEROCLKS%4567"
	push	HL
	call	UMUL_32_32
	pop	HL
	;DEBUG_MSG	"%LASTCLKS%"

	inc	HL

	; Check length
	ldh	A,[hash_buffer+5]
	dec	A
	ldh	[hash_buffer+5],A
	jr	nz,.loop
	ldh	A,[hash_buffer+6]
	dec	A
	ldh	[hash_buffer+6],A
	jr	nz,.loop

	; The original test wanted this big endian, so let's do the same.
	ld	HL,hash_buffer
	ldh	A,[mul_buffer._3]
	ld	[HL+],A
	ldh	A,[mul_buffer._2]
	ld	[HL+],A
	ldh	A,[mul_buffer._1]
	ld	[HL+],A
	ldh	A,[mul_buffer._0]
	ld	[HL+],A

	ret

SECTION "hash FNV-1a 32-bit", ROM0
; FNV-1a 32-bit (Fowler-Noll-Vo). One xor + one 32-bit multiply per
; byte. Multiplication is the dominant cost on the SM83 (no MUL
; instruction — SDCC synthesises it from shifts and adds), so this
; algorithm is interesting *because* it's hostile to the GB.
;
; This is basically the same as Knuth, to the point that I'll be reusing 
; the main calculation loop.
def FNV_OFFSET = $811C9DC5
def FNV_PRIME  = $01000193
hash_fnv1a32::
	call	adjust_length_de
	; Use hash_buffer+5 and 6 as a temp variable for counting the 8 shifts.
	ld	A,E
	ldh	[hash_buffer+5],A
	ld	A,D
	ldh	[hash_buffer+6],A

	; Init the multiplication source buffers.
	push	HL
	ld	HL,mul_buffer
	ld	A,(FNV_OFFSET>>0)&$FF
	ld	[HL+],A
	ld	A,(FNV_OFFSET>>8)&$FF
	ld	[HL+],A
	ld	A,(FNV_OFFSET>>16)&$FF
	ld	[HL+],A
	ld	A,(FNV_OFFSET>>24)&$FF
	ld	[HL+],A

	ld	HL,mul_buffer_in_b
	ld	A,(FNV_PRIME>>0)&$FF
	ld	[HL+],A
	ld	A,(FNV_PRIME>>8)&$FF
	ld	[HL+],A
	ld	A,(FNV_PRIME>>16)&$FF
	ld	[HL+],A
	ld	A,(FNV_PRIME>>24)&$FF
	ld	[HL+],A

	pop	HL
	jp	hash_knuth.loop


SECTION "hash Fletcher", ROM0
; Fletcher checksums (16/32/64) — John Fletcher's 1982 design, a
; direct ancestor of Adler-32 and an easier-than-CRC alternative that
; detects almost all real-world bit errors. Two running sums:
;
;   sum_a = Σ x_i   (mod M)
;   sum_b = Σ (n - i + 1) * x_i   (mod M)   i.e. cumulative prefix sums
;   output = (sum_b << k) | sum_a
;
; with M = 2^k - 1 (255 for Fletcher-16, 65535 for Fletcher-32,
; 2^32-1 for Fletcher-64). Word size: 1 byte for F-16, 2 bytes BE for
; F-32, 4 bytes BE for F-64 (RFC 1146 specification).
;
; Reference values for the standard `(i*31+7) & 0xFF` 1024-byte buffer:
;   fletcher16 = D400
;   fletcher32 = F5F3FF00
;   fletcher64 = 9C5C1DDD807F7E81
hash_flt16::
	call	adjust_length_de

	; Use B for the first running sum and C for the second running sum.
	ld	BC,$0000

	ld	A,D
	ldh	[hash_buffer+6],A

	ld	D,1

.loop:	ld	A,[HL+]
	; Modulo 255 ($FF) is equivalent to +1 when viewing only the lower byte.
	; We want to detect any value >=$ff
	; We have two cases to worry about:
	; 1) When the value has overflown so carry is set. (>$ff)
	; 2) When exactly ==$ff.
	; sum+=[HL]
	add	B
	; This does two things:
	; 1) Add the +1 in case to apply the modulo if A with carry >=$100
	; 2) Prepare for the case that A==$FF.
	; The input value of A before adding the data byte is max $FE by definition.
	; With a worst case of $FE+$FF, you get $1FD. 
	adc	D
	; if nz, a-=1
	; z = c
	;adc	$ff
;	ccf
	adc	$ff
;	sbc	D

;	jr	z,:+
;	dec	A
;:	
	ld	B,A

	ld	A,C
	add	B
	adc	D
	adc	$ff

	ld	C,A
	


	dec	E
	jr	nz,.loop

	ldh	A,[hash_buffer+6]
	dec	A
	ldh	[hash_buffer+6],A
	jr	nz,.loop

	ld	A,B
	ldh	[hash_buffer],A
	ld	A,C
	ldh	[hash_buffer],A

	ret


SECTION "VBL handler", ROM0
HANDLE_VBL::
	pop	AF
	reti


SECTION "clock", ROM0
; Intialize the tiemkeeping functionality.
clock_init::
	xor	A
	ldh	[rTAC],A
	ldh	[clock_state._256ths],A
	ldh	[clock_state._secs_dw],A
	ldh	[clock_state._secs_dw+1],A

	; Target 1/256 ticks in the 16 kiHz mode.
	; TODO: add support for GBC.
	ld	A,$100-16384/256
	ldh	[rTMA],A
	ldh	[rTIMA],A

	ld	A,TACF_START|TACF_16KHZ
	ldh	[rTAC],A

	ret

; Get the current wall time in seconds and fractions.
; Input: HL=Start of struct to output the current time.
clock_gettime::
	ei
	nop
	nop
	di

	; The timer counts up from the reset value of $C0 to $FF before it overflows.
	; But we don't really care about the 2 top bits as they're always 1 and the real sig-figs are in bit 0-5
	; 2* "add A" acts as a multiply by 4 while discarcing the unwanted bits.
	; But at the same time the add instruction affects the zero flag, so we get a free zero check.
	; We use the zero check to check if the timer might just have overflown. 
	; This methodology relies on the fact that we keep the interrupts open as much as possible. 
	; Specifically we can't wait more than 64 M cycles between the di (last opportunity for a timer int to fire)
	; and the read from rTIMA. 
	; Otherwise, we might need a slightly more complex check.
	ldh	A,[rTIMA]
	add	A
	add	A
	jr	nz,.value_ok			; Value ok to use as is.
	ldh	A,[rIF]
	and	IEF_TIMER			; Check for a timer interrupt.
	jr	nz,clock_gettime		; Jump back and let the pending interrupt fire.
	; No interrupt. The flag check produces A==0 so we can just use the value as is.
.value_ok:
	ld	[HL+],A				; Write sub-256th fractional value.
	ldh	A,[clock_state._256ths]
	ld	[HL+],A				; Write 256th fractional value.
	ldh	A,[clock_state._secs_dw]
	ld	[HL+],A				; Write seconds low byte
	ldh	A,[clock_state._secs_dw+1]
	ld	[HL+],A				; Write seconds high byte

	reti

HANDLE_TIMER::
	inc	[HL]				; Inc 256th counter
	jr	nz,.done
	inc	L

	inc	[HL]				; Inc secs counter, lower byte.
	jr	nz,.done
	inc	L

	inc	[HL]				; Inc secs counter, upper byte.
	; TODO: we could add overflow handling here...
.done
	pop	HL
	pop	AF
	reti

SECTION "hash main", ROM0
fill_workload_buffer::
	; Described as such by dmang-dev:
	; buf[i] = (i * 31 + 7) & 0xFF for i in [0, 1024)
	; We can in principle calculate this using successive addition to avoid multiplication.
	; Also, partial unrolling (x4) so the length counter fits within an 8 bit reg.
	ld	A,7
	ld	HL,workload_buffer
	ld	BC,$001f			; B="256" length counter. C=31, repeated addition offset.
:
	REPT 4
	ld	[HL+],A
	add	C
	ENDR
	dec	B
	jr	nz,:-

	ret


SECTION "workload buffer", WRAM0, ALIGN[8]
workload_buffer:
	ds	1024
.end

SECTION "Load tiles", ROM0

LOAD_TILES:
	; Clear Nintendo logo for no particular reason.
	ld	HL,$8000
	ld	B,$82			; Top byte of end address
	ld	E,L			; L==0
	call	FASTCLEAR

	; Load a font into tile RAM.
	ld	HL,basetiles
	ld	DE,$8200
	ld	BC,basetiles.end-basetiles
	call	COPY

	; Load a second copy of font into tile RAM for use with menu highlighting.
	ld	HL,basetiles
	ld	DE,$8600
	ld	BC,basetiles.end-basetiles
	call	COPY

	; Apply shading to the second charset.
	ld	HL,$8600
	ld	B,$8A			; End tile
:	ld	[HL],$FF
	inc	L
	inc	HL
	ld	A,H
	cp	B
	jr	nz,:-

	; Load a third copy of font into tile RAM to be inverted for the caption.
	ld	HL,basetiles
	ld	DE,$8A00
	ld	BC,basetiles.end-basetiles
	call	COPY

	; Invert the third charset.
	ld	HL,$8A00
	ld	B,$8E			; End tile
:	ld	A,[HL]
	cpl
	ld	[HL+],A
	ld	A,H
	cp	B
	jr	nz,:-

	ret


SECTION "Tiles", ROM0
basetiles:
	incbin "graphics/font0.2bpp"
.end

SECTION "Strings", ROM0
S_ALL::
SETCHARMAP inverted
	db "HASHBENCH (ASM)     \n"
SETCHARMAP default
	db "ALGO  HASH TIME"
	db 0

S_TOTAL_TIME:
	db	"TOTAL TIME:"
SETCHARMAP shaded
	db "WAIT ",0
SETCHARMAP default


SECTION "Vars", WRAM0
bench_startclock::
._timer::	db
._256ths::	db
._secs_dw::	dw

bench_endclock::
._timer::	db
._256ths::	db
._secs_dw::	dw

global_startclock::
._timer::	db
._256ths::	db
._secs_dw::	dw

SECTION "Hivars", HRAM[$FF80]
gbc_flag::	db

clear_after_here:
joypad_pressed::	db
joypad_held::		db

clock_state::
._256ths::	db
._secs_dw::	dw

current_test_idx:	db

; hash_buffer should be placed to at least be aligned to its size, ie no page boundary within the buffer.
hash_buffer::	ds 16

mul_buffer::
._0:: db
._1:: db
._2:: db
._3:: db
mul_buffer_in_a:: 
._0:: db
._1:: db
._2:: db
._3:: db
mul_buffer_in_b::
._0:: db
._1:: db
._2:: db
._3:: db

scratch_buffer: ds 5

SECTION "stack", HRAM[$FFC8]
STACK:	ds 16
.top
