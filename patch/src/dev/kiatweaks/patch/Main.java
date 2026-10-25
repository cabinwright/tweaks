package dev.kiatweaks.patch;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.zip.CRC32;
import java.util.zip.Inflater;

/**
 * Rebuilds patched system app code on the head unit from its own stock files, so nothing of
 * the manufacturer's is shipped. Run as root with app_process:
 *
 *   CLASSPATH=kiapatch.dex app_process /system/bin dev.kiatweaks.patch.Main <command> ...
 *
 *   md5 <file>                      print the file's md5
 *   delta <patch.lpd> <src> <dst>   rebuild dst from src (HMG Leafia Plus's .lpd format:
 *                                   bsdiff, raw deflate); writes nothing unless src is the
 *                                   exact original and the result matches
 *   zipadd <src.apk> <dex> <dst>    copy of src.apk with the dex added as classes.dex
 *                                   (stored); every existing entry is copied byte for byte
 *
 * Exit 0 on success, 1 with a message on stderr otherwise.
 */
public final class Main {
    private Main() {
    }

    public static void main(String[] args) {
        try {
            if (args.length == 2 && args[0].equals("md5")) {
                System.out.println(hex(md5(read(new File(args[1])))));
            } else if (args.length == 4 && args[0].equals("delta")) {
                delta(new File(args[1]), new File(args[2]), new File(args[3]));
            } else if (args.length == 4 && args[0].equals("zipadd")) {
                zipadd(new File(args[1]), new File(args[2]), new File(args[3]));
            } else {
                throw new IOException("usage: md5 <file> | delta <lpd> <src> <dst> | zipadd <apk> <dex> <dst>");
            }
        } catch (Exception e) {
            System.err.println("kiapatch: " + e.getMessage());
            System.exit(1);
        }
    }

    // ---- delta (.lpd)

    // header: "LPD1", u32 src len, md5 src, u32 dst len, md5 dst, u32 compression (1 = raw
    // deflate), u32 payload len. Body: u32 n, n x (i32 add, i32 copy, i32 seek), u32 len +
    // diff bytes, u32 len + extra bytes.
    static void delta(File lpd, File src, File dst) throws Exception {
        byte[] d = read(lpd);
        ByteBuffer h = ByteBuffer.wrap(d).order(ByteOrder.LITTLE_ENDIAN);
        if (d.length < 52 || d[0] != 'L' || d[1] != 'P' || d[2] != 'D' || d[3] != '1') throw new IOException("not a delta");
        int srcLen = h.getInt(4);
        byte[] srcMd5 = Arrays.copyOfRange(d, 8, 24);
        int dstLen = h.getInt(24);
        byte[] dstMd5 = Arrays.copyOfRange(d, 28, 44);
        int comp = h.getInt(44);
        int plen = h.getInt(48);

        byte[] a = read(src);
        if (a.length != srcLen || !Arrays.equals(md5(a), srcMd5)) {
            throw new IOException(src + " isn't the original this delta needs (md5 " + hex(md5(a)) + ")");
        }
        byte[] payload = Arrays.copyOfRange(d, 52, 52 + plen);
        byte[] body = comp == 1 ? inflate(payload) : payload;

        ByteBuffer b = ByteBuffer.wrap(body).order(ByteOrder.LITTLE_ENDIAN);
        int n = b.getInt();
        int[] ctrl = new int[n * 3];
        for (int i = 0; i < ctrl.length; i++) ctrl[i] = b.getInt();
        byte[] diff = new byte[b.getInt()];
        b.get(diff);
        byte[] extra = new byte[b.getInt()];
        b.get(extra);

        byte[] out = new byte[dstLen];
        int op = 0, dp = 0, ep = 0, w = 0;
        for (int i = 0; i < n; i++) {
            int add = ctrl[3 * i], copy = ctrl[3 * i + 1], seek = ctrl[3 * i + 2];
            if (w + add + copy > dstLen) throw new IOException("delta overruns the target");
            for (int k = 0; k < add; k++) {
                int o = op + k;
                int v = diff[dp + k];
                if (o >= 0 && o < a.length) v += a[o];
                out[w++] = (byte) v;
            }
            op += add;
            dp += add;
            System.arraycopy(extra, ep, out, w, copy);
            w += copy;
            ep += copy;
            op += seek;
        }
        if (w != dstLen || !Arrays.equals(md5(out), dstMd5)) throw new IOException("rebuilt file doesn't match the delta's result");
        write(dst, out);
    }

    // ---- zipadd

    static void zipadd(File apk, File dex, File dst) throws Exception {
        byte[] z = read(apk);
        byte[] data = read(dex);
        ByteBuffer zb = ByteBuffer.wrap(z).order(ByteOrder.LITTLE_ENDIAN);
        int eocd = -1;
        for (int i = z.length - 22; i >= Math.max(0, z.length - 22 - 65535); i--) {
            if (zb.getInt(i) == 0x06054b50) {
                eocd = i;
                break;
            }
        }
        if (eocd < 0) throw new IOException("not a zip");
        int entries = zb.getShort(eocd + 10) & 0xffff;
        int cdSize = zb.getInt(eocd + 12);
        int cdOff = zb.getInt(eocd + 16);
        for (int p = cdOff; p < cdOff + cdSize; ) {
            int nameLen = zb.getShort(p + 28) & 0xffff;
            String name = new String(z, p + 46, nameLen, "UTF-8");
            if (name.equals("classes.dex")) throw new IOException(apk + " already has classes.dex");
            p += 46 + nameLen + (zb.getShort(p + 30) & 0xffff) + (zb.getShort(p + 32) & 0xffff);
        }

        CRC32 crc = new CRC32();
        crc.update(data);
        byte[] name = "classes.dex".getBytes("UTF-8");
        // 1980-01-01 00:00, so the output is the same every time
        int dosTime = 0, dosDate = (0 << 9) | (1 << 5) | 1;

        ByteBuffer local = ByteBuffer.allocate(30 + name.length).order(ByteOrder.LITTLE_ENDIAN);
        local.putInt(0x04034b50).putShort((short) 10).putShort((short) 0).putShort((short) 0)
                .putShort((short) dosTime).putShort((short) dosDate).putInt((int) crc.getValue())
                .putInt(data.length).putInt(data.length).putShort((short) name.length).putShort((short) 0)
                .put(name);
        ByteBuffer central = ByteBuffer.allocate(46 + name.length).order(ByteOrder.LITTLE_ENDIAN);
        central.putInt(0x02014b50).putShort((short) 10).putShort((short) 10).putShort((short) 0)
                .putShort((short) 0).putShort((short) dosTime).putShort((short) dosDate)
                .putInt((int) crc.getValue()).putInt(data.length).putInt(data.length)
                .putShort((short) name.length).putShort((short) 0).putShort((short) 0)
                .putShort((short) 0).putShort((short) 0).putInt(0).putInt(cdOff).put(name);

        int newCdOff = cdOff + local.capacity() + data.length;
        int newCdSize = cdSize + central.capacity();
        ByteBuffer end = ByteBuffer.allocate(22).order(ByteOrder.LITTLE_ENDIAN);
        end.putInt(0x06054b50).putShort((short) 0).putShort((short) 0)
                .putShort((short) (entries + 1)).putShort((short) (entries + 1))
                .putInt(newCdSize).putInt(newCdOff).putShort((short) 0);

        File tmp = new File(dst.getPath() + ".tmp");
        OutputStream out = new FileOutputStream(tmp);
        try {
            out.write(z, 0, cdOff);                 // every entry, untouched
            out.write(local.array());
            out.write(data);
            out.write(z, cdOff, cdSize);            // the old central directory
            out.write(central.array());
            out.write(end.array());
        } finally {
            out.close();
        }
        if (!tmp.renameTo(dst)) throw new IOException("can't write " + dst);
    }

    // ---- helpers

    static byte[] inflate(byte[] in) throws Exception {
        Inflater inf = new Inflater(true);
        inf.setInput(in);
        ByteArrayOutputStream out = new ByteArrayOutputStream(in.length * 3);
        byte[] buf = new byte[65536];
        while (!inf.finished()) {
            int n = inf.inflate(buf);
            if (n == 0 && (inf.needsInput() || inf.needsDictionary())) throw new IOException("truncated delta");
            out.write(buf, 0, n);
        }
        inf.end();
        return out.toByteArray();
    }

    static byte[] md5(byte[] b) throws Exception {
        return MessageDigest.getInstance("MD5").digest(b);
    }

    static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x & 0xff));
        return sb.toString();
    }

    static byte[] read(File f) throws IOException {
        InputStream in = new FileInputStream(f);
        try {
            byte[] b = new byte[(int) f.length()];
            int n = 0;
            while (n < b.length) {
                int r = in.read(b, n, b.length - n);
                if (r < 0) throw new IOException("short read " + f);
                n += r;
            }
            return b;
        } finally {
            in.close();
        }
    }

    static void write(File f, byte[] b) throws IOException {
        File tmp = new File(f.getPath() + ".tmp");
        OutputStream out = new FileOutputStream(tmp);
        try {
            out.write(b);
        } finally {
            out.close();
        }
        if (!tmp.renameTo(f)) throw new IOException("can't write " + f);
    }
}
