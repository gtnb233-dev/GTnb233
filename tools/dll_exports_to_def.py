import sys, struct

def exports(path):
    d = open(path,'rb').read()
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    assert d[pe:pe+4] == b'PE\0\0'
    nsec = struct.unpack_from('<H', d, pe+6)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    dd = opt + (112 if magic == 0x20b else 96)
    exp_rva, exp_size = struct.unpack_from('<II', d, dd)
    sec_off = opt + struct.unpack_from('<H', d, pe+20)[0]
    secs = []
    for i in range(nsec):
        o = sec_off + i*40
        vsize, vaddr, rawsize, rawptr = struct.unpack_from('<IIII', d, o+8)
        secs.append((vaddr, vsize, rawptr, rawsize))
    def r2o(rva):
        for vaddr, vsize, rawptr, rawsize in secs:
            if vaddr <= rva < vaddr + max(vsize, rawsize):
                return rawptr + (rva - vaddr)
        raise ValueError(hex(rva))
    eo = r2o(exp_rva)
    (name_rva, base, nfuncs, nnames, afuncs, anames, aords) = struct.unpack_from('<IIIIIII', d, eo+12)
    out = []
    for i in range(nnames):
        nrva = struct.unpack_from('<I', d, r2o(anames) + i*4)[0]
        no = r2o(nrva)
        nm = d[no:d.index(b'\0', no)].decode()
        ordv = struct.unpack_from('<H', d, r2o(aords) + i*2)[0]
        frva = struct.unpack_from('<I', d, r2o(afuncs) + ordv*4)[0]
        if exp_rva <= frva < exp_rva + exp_size:
            continue
        out.append((ordv + base, nm))
    out.sort()
    return out

dll, defpath = sys.argv[1], sys.argv[2]
ex = exports(dll)
with open(defpath, 'w', newline='\r\n') as f:
    f.write('LIBRARY %s\nEXPORTS\n' % dll.replace('\\','/').split('/')[-1])
    for o, n in ex:
        f.write('  %s @%d\n' % (n, o))
print('exports: %d -> %s' % (len(ex), defpath))
