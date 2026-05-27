; Emit GBC palette entry.
; The color components are 5 bit. (0-31)
; PAL_ENTRY R,G,B
PAL_ENTRY:	MACRO
	assert (\1)==(\1)&%11111
	assert (\2)==(\2)&%11111
	assert (\3)==(\3)&%11111
	dw	(\1) | (\2)<<5| (\3)<<10
ENDM
