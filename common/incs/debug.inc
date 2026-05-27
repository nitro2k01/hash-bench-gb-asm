	IF !DEF(DEBUG_INC)
DEF DEBUG_INC EQU 1

include "incs/charmaps.inc"
	
DEBUG_MSG:	MACRO
	ld	D,D
	jr	:+
	dw $6464
	dw $0000
PUSHC
SETCHARMAP default_raw
	db \1
POPC
:

	ENDM

	ENDC	