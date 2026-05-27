@set rgbenv=C:\Users\nitro2k01\gbdev\rgbds
@set old_prompt=%prompt%
@set prompt=$
@mkdir obj 2>nul
@mkdir bin 2>nul
%rgbenv%\rgbasm -oobj/gbc.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/gbc.asm
@if errorlevel 1 goto lbl_err
%rgbenv%\rgbasm -oobj/math.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/math.asm
@if errorlevel 1 goto lbl_err
%rgbenv%\rgbasm -oobj/util.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/util.asm
@if errorlevel 1 goto lbl_err
%rgbenv%\rgbasm -oobj/hashbench.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/hashbench.asm
@if errorlevel 1 goto lbl_err
%rgbenv%\rgblink -t -p0xFF -o bin/hashbench.gb -m bin/hashbench.map -n bin/hashbench.sym obj/hashbench.o obj/util.o obj/gbc.o obj/math.o
@if errorlevel 1 goto lbl_err
%rgbenv%\rgbfix -v -c -r4 -m0x1b -s -l 0x33 -n 1 -p0xFF -t "hashbench" bin/hashbench.gb
@if errorlevel 1 goto lbl_err
: Copy to pocket
: copy /y bin\hashbench.gb D:\Assets\gb\common
@goto lbl_end
:lbl_err
@echo Error!
:lbl_end
@set prompt=%old_prompt%