    IF !DEF(CHARMAPS_INC)
DEF CHARMAPS_INC EQU 1

DEF charlist EQUS "\" !\\\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ\""
; Empty charmap for use with raw ASCII strings.
NEWCHARMAP default_raw
; Prepare deafult charmap for general strings.
NEWCHARMAP default
DEF charnum = 0
REPT STRLEN(charlist)
	CHARMAP STRSUB(charlist,charnum+1,1),charnum+$20
	DEF charnum += 1
ENDR
CHARMAP "\n",10

; Prepare deafult charmap for shaded strings.
NEWCHARMAP shaded
DEF charnum = 0
REPT STRLEN(charlist)
	CHARMAP STRSUB(charlist,charnum+1,1),charnum+$60
	DEF charnum += 1
ENDR
PURGE charnum
CHARMAP "\n",10

; Prepare deafult charmap for inverted strings.
NEWCHARMAP inverted
DEF charnum = 0
REPT STRLEN(charlist)
	CHARMAP STRSUB(charlist,charnum+1,1),charnum+$A0
	DEF charnum += 1
ENDR
PURGE charnum
CHARMAP "\n",10


SETCHARMAP default

; Load a r16 with a pointer to map at coordinate x,y
; LDXY r16, x, y
LDXY:	MACRO
	ld	\1,($9800+(\2)+32*(\3))
	ENDM

LDXY_L:	MACRO
	ld	LOW(\1),LOW($9800+(\2)+32*(\3))
	ENDM

LDXY2:	MACRO
	ld	\1,($9C00+(\2)+32*(\3))
	ENDM

LDXY2_L:MACRO
	ld	LOW(\1),LOW($9C00+(\2)+32*(\3))
	ENDM


	ENDC