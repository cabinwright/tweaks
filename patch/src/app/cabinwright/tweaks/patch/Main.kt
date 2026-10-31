/**
 * Rebuilds patched system app code on the head unit from its own stock files, so nothing of
 * the manufacturer's is shipped. Run by a tweak, as the tweak's own uid, with app_process
 * and a dalvik-cache of its own in $TWEAK_DATA:
 *
 *   ANDROID_DATA=<dir with dalvik-cache/> CLASSPATH=tweakpatch.jar \
 *       app_process /system/bin app.cabinwright.tweaks.patch.Main <command> ...
 *
 *   md5 <file>                      print the file's md5
 *   delta <patch.lpd> <src> <dst>   rebuild dst from src (HMG Leafia Plus's .lpd format:
 *                                   bsdiff, raw deflate); writes nothing unless src is the
 *                                   exact original and the result matches
 *   zipadd <src.apk> <dex> <dst>    copy of src.apk with the dex added as classes.dex
 *                                   (stored); every existing entry is copied byte for byte
 *
 * Exit 0 on success, 1 with a message on stderr otherwise. A damaged delta or zip is refused
 * with a message, never read past its end.
 */
@file:JvmName("Main")

package app.cabinwright.tweaks.patch

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.GeneralSecurityException
import java.security.MessageDigest
import java.util.Arrays
import java.util.zip.CRC32
import java.util.zip.DataFormatException
import java.util.zip.Inflater
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    try {
        run(args)
    } catch (e: IOException) {
        fail(e)
    } catch (e: GeneralSecurityException) {
        fail(e)
    } catch (e: DataFormatException) {
        fail(e)
    }
}

private fun run(args: Array<String>) {
    if (args.size == 2 && args[0] == "md5") {
        println(hex(md5(read(File(args[1])))))
    } else if (args.size == 4 && args[0] == "delta") {
        delta(File(args[1]), File(args[2]), File(args[3]))
    } else if (args.size == 4 && args[0] == "zipadd") {
        zipadd(File(args[1]), File(args[2]), File(args[3]))
    } else {
        throw IOException("usage: md5 <file> | delta <lpd> <src> <dst> | zipadd <apk> <dex> <dst>")
    }
}

private fun fail(e: Exception) {
    System.err.println("tweakpatch: " + e.message)
    exitProcess(1)
}

// ---- delta (.lpd)

private const val LPD_HEADER = 52
private const val CONTROL_BYTES = 12

// header: "LPD1", u32 src len, md5 src, u32 dst len, md5 dst, u32 compression (1 = raw
// deflate), u32 payload len. Body: u32 n, n x (i32 add, i32 copy, i32 seek), u32 len +
// diff bytes, u32 len + extra bytes.
private fun delta(lpd: File, src: File, dst: File) {
    val d = read(lpd)
    ensure(d.size >= LPD_HEADER && String(d, 0, 4, Charsets.ISO_8859_1) == "LPD1") { "not a delta" }
    val h = ByteBuffer.wrap(d).order(ByteOrder.LITTLE_ENDIAN)
    val srcLen = h.getInt(4)
    val srcMd5 = d.copyOfRange(8, 24)
    val dstLen = h.getInt(24)
    val dstMd5 = d.copyOfRange(28, 44)
    val comp = h.getInt(44)
    val plen = h.getInt(48)
    ensure(dstLen >= 0 && plen >= 0 && plen <= Int.MAX_VALUE - LPD_HEADER) { "damaged delta" }

    val a = read(src)
    ensure(a.size == srcLen && md5(a).contentEquals(srcMd5)) {
        "$src isn't the original this delta needs (md5 ${hex(md5(a))})"
    }
    // a payload length past the end reads zeros
    val payload = Arrays.copyOfRange(d, LPD_HEADER, LPD_HEADER + plen)
    val out = rebuild(a, Body(if (comp == 1) inflate(payload) else payload), dstLen)
    ensure(md5(out).contentEquals(dstMd5)) { "rebuilt file doesn't match the delta's result" }
    write(dst, out)
}

/** bsdiff's patch step: the target from the source and the delta's body. */
private fun rebuild(a: ByteArray, body: Body, dstLen: Int): ByteArray {
    val n = body.int()
    ensure(n >= 0 && n <= body.remaining() / CONTROL_BYTES) { "truncated delta" }
    val ctrl = IntArray(n * 3) { body.int() }
    val diff = body.bytes(body.int())
    val extra = body.bytes(body.int())

    val out = ByteArray(dstLen)
    var op = 0
    var dp = 0
    var ep = 0
    var w = 0
    for (i in 0 until n) {
        val add = ctrl[3 * i]
        val copy = ctrl[3 * i + 1]
        val seek = ctrl[3 * i + 2]
        ensure(w.toLong() + add + copy <= dstLen) { "delta overruns the target" }
        ensure(add <= 0 || dp >= 0 && dp.toLong() + add <= diff.size) { "delta overruns its diff bytes" }
        for (k in 0 until add) {
            val o = op + k
            var v = diff[dp + k].toInt()
            if (o >= 0 && o < a.size) v += a[o]
            out[w++] = v.toByte()
        }
        op += add
        dp += add
        ensure(copy >= 0 && ep >= 0 && ep.toLong() + copy <= extra.size) { "delta overruns its extra bytes" }
        ensure(w.toLong() + copy <= dstLen) { "delta overruns the target" }
        System.arraycopy(extra, ep, out, w, copy)
        w += copy
        ep += copy
        op += seek
    }
    ensure(w == dstLen) { "rebuilt file doesn't match the delta's result" }
    return out
}

/** The delta's body, read in order; reading past its end is an IOException. */
private class Body(bytes: ByteArray) {
    private val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

    fun remaining(): Int = b.remaining()

    fun int(): Int {
        ensure(b.remaining() >= Int.SIZE_BYTES) { "truncated delta" }
        return b.getInt()
    }

    fun bytes(len: Int): ByteArray {
        ensure(len >= 0 && len <= b.remaining()) { "truncated delta" }
        val out = ByteArray(len)
        b.get(out)
        return out
    }
}

// ---- zipadd

private const val EOCD = 0x06054b50
private const val EOCD_SIZE = 22
private const val CENTRAL = 0x02014b50
private const val CENTRAL_SIZE = 46
private const val LOCAL = 0x04034b50
private const val LOCAL_SIZE = 30
private const val MAX_COMMENT = 65535
private const val ZIP_VERSION: Short = 10

// 1980-01-01 00:00, so the output is the same every time
private const val DOS_TIME: Short = 0
private const val DOS_DATE: Short = ((0 shl 9) or (1 shl 5) or 1).toShort()

private fun zipadd(apk: File, dex: File, dst: File) {
    val z = read(apk)
    val data = read(dex)
    val zb = ByteBuffer.wrap(z).order(ByteOrder.LITTLE_ENDIAN)
    val eocd = endRecord(z, zb)
    ensure(eocd >= 0) { "not a zip" }
    val entries = zb.getShort(eocd + 10).toInt() and 0xffff
    val cdSize = zb.getInt(eocd + 12)
    val cdOff = zb.getInt(eocd + 16)
    ensure(cdOff >= 0 && cdSize >= 0 && cdOff.toLong() + cdSize <= z.size) { "damaged zip" }
    for (name in names(z, zb, cdOff, cdSize)) ensure(name != "classes.dex") { "$apk already has classes.dex" }

    val crc = CRC32()
    crc.update(data)
    val name = "classes.dex".toByteArray(Charsets.UTF_8)

    val local = ByteBuffer.allocate(LOCAL_SIZE + name.size).order(ByteOrder.LITTLE_ENDIAN)
    local.putInt(LOCAL).putShort(ZIP_VERSION).putShort(0).putShort(0)
        .putShort(DOS_TIME).putShort(DOS_DATE).putInt(crc.value.toInt())
        .putInt(data.size).putInt(data.size).putShort(name.size.toShort()).putShort(0)
        .put(name)
    val central = ByteBuffer.allocate(CENTRAL_SIZE + name.size).order(ByteOrder.LITTLE_ENDIAN)
    central.putInt(CENTRAL).putShort(ZIP_VERSION).putShort(ZIP_VERSION).putShort(0)
        .putShort(0).putShort(DOS_TIME).putShort(DOS_DATE)
        .putInt(crc.value.toInt()).putInt(data.size).putInt(data.size)
        .putShort(name.size.toShort()).putShort(0).putShort(0)
        .putShort(0).putShort(0).putInt(0).putInt(cdOff).put(name)

    val newCdOff = cdOff + local.capacity() + data.size
    val newCdSize = cdSize + central.capacity()
    val end = ByteBuffer.allocate(EOCD_SIZE).order(ByteOrder.LITTLE_ENDIAN)
    end.putInt(EOCD).putShort(0).putShort(0)
        .putShort((entries + 1).toShort()).putShort((entries + 1).toShort())
        .putInt(newCdSize).putInt(newCdOff).putShort(0)

    val tmp = File(dst.path + ".tmp")
    val out = FileOutputStream(tmp)
    try {
        out.write(z, 0, cdOff) // every entry, untouched
        out.write(local.array())
        out.write(data)
        out.write(z, cdOff, cdSize) // the old central directory
        out.write(central.array())
        out.write(end.array())
    } finally {
        out.close()
    }
    ensure(tmp.renameTo(dst)) { "can't write $dst" }
}

/** Where the end of central directory record starts (searched from the end), or -1. */
private fun endRecord(z: ByteArray, zb: ByteBuffer): Int {
    val first = maxOf(0, z.size - EOCD_SIZE - MAX_COMMENT)
    var i = z.size - EOCD_SIZE
    while (i >= first && zb.getInt(i) != EOCD) i--
    return if (i >= first) i else -1
}

/** The entry names in a central directory; one that runs past the file's end is an IOException. */
private fun names(z: ByteArray, zb: ByteBuffer, cdOff: Int, cdSize: Int): List<String> {
    val names = ArrayList<String>()
    var p = cdOff
    while (p < cdOff + cdSize) {
        ensure(p.toLong() + CENTRAL_SIZE <= z.size) { "damaged zip" }
        val nameLen = zb.getShort(p + 28).toInt() and 0xffff
        ensure(p.toLong() + CENTRAL_SIZE + nameLen <= z.size) { "damaged zip" }
        names.add(String(z, p + CENTRAL_SIZE, nameLen, Charsets.UTF_8))
        val extraLen = zb.getShort(p + 30).toInt() and 0xffff
        val commentLen = zb.getShort(p + 32).toInt() and 0xffff
        p += CENTRAL_SIZE + nameLen + extraLen + commentLen
    }
    return names
}

// ---- helpers

private const val BUFFER = 65536

private fun inflate(input: ByteArray): ByteArray {
    val inf = Inflater(true)
    inf.setInput(input)
    val out = ByteArrayOutputStream(input.size * 3)
    val buf = ByteArray(BUFFER)
    while (!inf.finished()) {
        val n = inf.inflate(buf)
        ensure(n != 0 || !inf.needsInput() && !inf.needsDictionary()) { "truncated delta" }
        out.write(buf, 0, n)
    }
    inf.end()
    return out.toByteArray()
}

private fun md5(b: ByteArray): ByteArray = MessageDigest.getInstance("MD5").digest(b)

private const val HEX = "0123456789abcdef"

private fun hex(b: ByteArray): String {
    val sb = StringBuilder()
    for (x in b) sb.append(HEX[x.toInt() shr 4 and 0xf]).append(HEX[x.toInt() and 0xf])
    return sb.toString()
}

/** Like require(), but an IOException: a refused input, reported with [message]. */
private inline fun ensure(ok: Boolean, message: () -> String) {
    if (!ok) throw IOException(message())
}

private fun read(f: File): ByteArray {
    val input = FileInputStream(f)
    try {
        val b = ByteArray(f.length().toInt())
        var n = 0
        while (n < b.size) {
            val r = input.read(b, n, b.size - n)
            ensure(r >= 0) { "short read $f" }
            n += r
        }
        return b
    } finally {
        input.close()
    }
}

private fun write(f: File, b: ByteArray) {
    val tmp = File(f.path + ".tmp")
    val out = FileOutputStream(tmp)
    try {
        out.write(b)
    } finally {
        out.close()
    }
    ensure(tmp.renameTo(f)) { "can't write $f" }
}
