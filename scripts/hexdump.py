import sys
p='decompressed_pipe.txt'
b=open(p,'rb').read()
print('len=',len(b))
print('find hello=',b.find(b'hello'))
print('\nfirst 128 bytes:')
print(' '.join(['%02X'%x for x in b[:128]]))
