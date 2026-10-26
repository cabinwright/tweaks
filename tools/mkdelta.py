#!/usr/bin/env python3
"""Make a delta (.lpd) that rebuilds <target> on the head unit from its own <source>.
usage: mkdelta.py <source> <target> <out.lpd>

The format is HMG Leafia Plus's (so its lpatch can apply it too): "LPD1", u32 source length,
md5 source, u32 target length, md5 target, u32 compression (1 = raw deflate), u32 payload
length, then the payload: bsdiff control triples, diff bytes and extra bytes. Applied by
patch/src/app/cabinwright/tweaks/patch/Main.kt, which writes nothing unless the source is that exact
file and the result matches. Needs bsdiff4 (pip install bsdiff4==1.3.1).
"""
import hashlib, struct, sys, zlib
import bsdiff4.core


def make(a, b):
    ctrl, diff, extra = bsdiff4.core.diff(a, b)
    body = struct.pack('<I', len(ctrl))
    body += b''.join(struct.pack('<iii', *t) for t in ctrl)
    body += struct.pack('<I', len(diff)) + diff + struct.pack('<I', len(extra)) + extra
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    payload = c.compress(body) + c.flush()
    return (b'LPD1' + struct.pack('<I', len(a)) + hashlib.md5(a).digest()
            + struct.pack('<I', len(b)) + hashlib.md5(b).digest()
            + struct.pack('<II', 1, len(payload)) + payload)


def apply(a, d):
    """Same steps as the on-car tool, as a self-check."""
    assert d[:4] == b'LPD1'
    body = zlib.decompress(d[52:], -15)
    n, = struct.unpack_from('<I', body)
    p = 4 + 12 * n
    ctrl = [struct.unpack_from('<iii', body, 4 + 12 * i) for i in range(n)]
    dl, = struct.unpack_from('<I', body, p); diff = body[p + 4:p + 4 + dl]; p += 4 + dl
    el, = struct.unpack_from('<I', body, p); extra = body[p + 4:p + 4 + el]
    out = bytearray(); op = dp = ep = 0
    for add, copy, seek in ctrl:
        for k in range(add):
            o = op + k
            out.append((diff[dp + k] + (a[o] if 0 <= o < len(a) else 0)) & 255)
        op += add; dp += add
        out += extra[ep:ep + copy]; ep += copy; op += seek
    return bytes(out)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
    d = make(a, b)
    assert apply(a, d) == b
    open(sys.argv[3], 'wb').write(d)
    print('%s  %d bytes (target %d)' % (sys.argv[3], len(d), len(b)))
