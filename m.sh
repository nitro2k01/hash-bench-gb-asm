mkdir -p obj
mkdir -p bin
rgbasm -oobj/gbc.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/gbc.asm &&
rgbasm -oobj/math.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/math.asm &&
rgbasm -oobj/util.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/util.asm &&
rgbasm -oobj/hashbench.o -Wno-obsolete -p 0xFF -isrc/ -ires/ -i./common/ src/hashbench.asm &&
rgblink -t -p0xFF -o bin/hashbench.gb -m bin/hashbench.map -n bin/hashbench.sym obj/hashbench.o obj/util.o obj/gbc.o obj/math.o &&
rgbfix -v -c -r4 -m0x1b -s -l 0x33 -n 1 -p0xFF -t "hashbench" bin/hashbench.gb
