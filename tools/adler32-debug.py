import zlib

workload = [(i * 31 + 7) & 0xFF for i in range(1024*8)]
workload = [0xFF for i in range(1024*16)]

a=1
b=0
ADLER_MOD = 65521
r=0


for i in workload:
	r+=1
	a+=i
	#if a>65535:
	#	a%=ADLER_MOD
	b+=a
	#b%=ADLER_MOD
	#if b>65536*65536:
	#	print (r)

a%=ADLER_MOD
b%=ADLER_MOD

print("%04x%04x"%(b,a))
print("%08x"%zlib.adler32(bytes(workload)))

print("%08x"%zlib.adler32(open("bin/hashbench.gb","rb").read()))
