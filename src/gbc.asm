include "incs/hardware.inc"
include "gbc.inc"
; This file is meant to be viewed using tabs for indentation and tab width 8.

SECTION "GBC code", ROM0


INIT_GBC_MINIMAL::
	ld	A,1
	ldh	[rVBK],A
	; Clear the attribute map for BG 1.
	ld	HL,$9800
	ld	B,$9C			; Top byte of end address.
	ld	E,L			; L==0
	call	FASTCLEAR

	xor	A
	ldh	[rVBK],A

	; Load BG palettes.
	ld	BC,(gbc_pals.end-gbc_pals)<<8|LOW(rBCPS)
	ld	HL,gbc_pals
	call	LOAD_GBC_PALS
	; Load OAM palettes.
	ld	BC,(gbc_pals_oam.end-gbc_pals_oam)<<8|LOW(rOCPS)
	; gbc_pals_oam follow directly after gbc_pals.
;	ld	HL,gbc_pals_oam
	; Tail call and fallthtough.
;	jr	LOAD_GBC_PALS
;	ret
LOAD_GBC_PALS:
	ld	A,$80
	ld	[$FF00+C],A
	inc	C
.palloop
	ld	A,[HL+]
	ld	[$FF00+C],A
	dec	B
	jr	nz,.palloop
	ret

gbc_pals:
	PAL_ENTRY	31,31,31
	PAL_ENTRY	20,20,20
	PAL_ENTRY	11,11,11
	PAL_ENTRY	0,0,0

	;PAL_ENTRY	26,26,26
	PAL_ENTRY	13,13,13
	PAL_ENTRY	31,5,5
	PAL_ENTRY	5,5,31
	PAL_ENTRY	0,0,0

.end
gbc_pals_oam:
	PAL_ENTRY	31,31,31
	PAL_ENTRY	16,16,16
	PAL_ENTRY	31,31,31
	PAL_ENTRY	0,0,0
.end
