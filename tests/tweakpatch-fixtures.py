#!/usr/bin/env python3
"""Writes fixtures for tests/tweakpatch-test.sh into <dir>, with no third-party modules:

  src, dst        a source and the target a delta rebuilds from it
  good.lpd        a delta from src to dst (several control triples, a backward seek and
                  reads past the source's end, as bsdiff makes)
  bad-dst.lpd     the same delta claiming a different target md5
  short.lpd       good.lpd cut off inside the payload
  app.apk, dex    a zip (stored and deflated entries, a comment-free end record) and a dex
  zipadd.apk      what `zipadd app.apk dex` must write, byte for byte

usage: tweakpatch-fixtures.py <dir>
"""
import hashlib
import struct
import sys
import zipfile
import zlib
from pathlib import Path


def lpd(src, dst, ctrl, diff, extra, dst_md5=None):
    body = struct.pack('<I', len(ctrl)) + b''.join(struct.pack('<iii', *t) for t in ctrl)
    body += struct.pack('<I', len(diff)) + diff + struct.pack('<I', len(extra)) + extra
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    payload = c.compress(body) + c.flush()
    return (b'LPD1' + struct.pack('<I', len(src)) + hashlib.md5(src).digest()
            + struct.pack('<I', len(dst)) + (dst_md5 or hashlib.md5(dst).digest())
            + struct.pack('<II', 1, len(payload)) + payload)


def delta(src):
    """A target built from src by hand-written control triples, and the delta for it."""
    ctrl = [(40, 7, 10), (30, 0, -50), (25, 5, 200), (60, 3, 0)]
    out, diff, extra = bytearray(), bytearray(), bytearray()
    op = 0
    for i, (add, copy, seek) in enumerate(ctrl):
        for k in range(add):
            o = op + k
            want = (o * 7 + i * 31 + 5) & 255
            base = src[o] if 0 <= o < len(src) else 0
            diff.append((want - base) & 255)
            out.append(want)
        op += add
        new = bytes((i * 13 + j * 3) & 255 for j in range(copy))
        extra += new
        out += new
        op += seek
    return bytes(out), ctrl, bytes(diff), bytes(extra)


def zipadd(apk, dex):
    """classes.dex (stored, dated 1980-01-01) added after the entries, central directory kept."""
    eocd = apk.rindex(b'PK\x05\x06')
    entries, cd_size, cd_off = struct.unpack_from('<HII', apk, eocd + 10)
    name = b'classes.dex'
    crc = zlib.crc32(dex) & 0xffffffff
    local = struct.pack('<IHHHHHIIIHH', 0x04034b50, 10, 0, 0, 0, 33, crc, len(dex), len(dex), len(name), 0) + name
    central = struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 10, 10, 0, 0, 0, 33, crc, len(dex), len(dex),
                          len(name), 0, 0, 0, 0, 0, cd_off) + name
    end = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, entries + 1, entries + 1, cd_size + len(central),
                      cd_off + len(local) + len(dex), 0)
    return apk[:cd_off] + local + dex + apk[cd_off:cd_off + cd_size] + central + end


def main():
    out = Path(sys.argv[1])
    src = bytes((i * 11 + 3) & 255 for i in range(150))
    dst, ctrl, diff, extra = delta(src)
    good = lpd(src, dst, ctrl, diff, extra)
    (out / 'src').write_bytes(src)
    (out / 'dst').write_bytes(dst)
    (out / 'good.lpd').write_bytes(good)
    (out / 'bad-dst.lpd').write_bytes(lpd(src, dst, ctrl, diff, extra, b'\0' * 16))
    (out / 'short.lpd').write_bytes(good[:60])

    with zipfile.ZipFile(out / 'app.apk', 'w') as z:
        z.writestr(zipfile.ZipInfo('AndroidManifest.xml', (2026, 1, 2, 3, 4, 6)), b'<manifest/>' * 20,
                   zipfile.ZIP_DEFLATED)
        z.writestr(zipfile.ZipInfo('res/raw/a.bin', (2026, 1, 2, 3, 4, 6)), bytes(range(256)), zipfile.ZIP_STORED)
    dex = b'dex\n035\0' + bytes(range(200))
    (out / 'dex').write_bytes(dex)
    (out / 'zipadd.apk').write_bytes(zipadd((out / 'app.apk').read_bytes(), dex))


if __name__ == '__main__':
    main()
