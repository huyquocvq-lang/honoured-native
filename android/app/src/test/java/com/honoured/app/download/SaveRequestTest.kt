package com.honoured.app.download

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Base64

class SaveRequestTest {
    private val decode: (String) -> ByteArray? = { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }
    private fun msg(name: String? = "honoured-export-2026-11-07.json", mime: String? = "application/json", data: String = Base64.getEncoder().encodeToString("{}".toByteArray()), type: String = "SAVE_FILE") =
        JSONObject().put("type", type).put("fileName", name).put("mimeType", mime).put("base64", data).toString()

    @Test
    fun parsesTheExport() {
        val r = SaveRequest.parse(msg(), decode)!!
        assertEquals("honoured-export-2026-11-07.json", r.fileName)
        assertEquals("application/json", r.mimeType)
        assertArrayEquals("{}".toByteArray(), r.bytes)
    }

    @Test
    fun rejectsOtherTypesAndGarbage() {
        assertNull(SaveRequest.parse(msg(type = "SET_AUTH_SESSION"), decode))
        assertNull(SaveRequest.parse("not json", decode))
        assertNull(SaveRequest.parse(null, decode))
        assertNull(SaveRequest.parse(msg(data = "@@@"), decode))
    }

    @Test
    fun refusesOversizedFilesBeforeDecoding() {
        var decoded = false
        val huge = "A".repeat((SaveRequest.MAX_BYTES / 3 + 2) * 4)
        assertNull(SaveRequest.parse(msg(data = huge)) { decoded = true; ByteArray(0) })
        assertEquals(false, decoded)
    }

    @Test
    fun fileNamesAreFlattenedAndBounded() {
        assertEquals("passwd", SaveRequest.sanitizeFileName("../../etc/passwd"))
        assertEquals("evil.json", SaveRequest.sanitizeFileName("C:\\\\x\\\\evil.json"))
        assertEquals("ab.json", SaveRequest.sanitizeFileName("a\u0000b.json"))
        assertEquals("hidden", SaveRequest.sanitizeFileName(".hidden"))
        assertEquals("download", SaveRequest.sanitizeFileName("   "))
        assertEquals("download", SaveRequest.sanitizeFileName(null))
        assertEquals(100, SaveRequest.sanitizeFileName("x".repeat(300)).length)
    }

    @Test
    fun unknownMimeTypesFallBackToBinary() {
        assertEquals("application/octet-stream", SaveRequest.parse(msg(mime = "not a mime"), decode)!!.mimeType)
        assertEquals("application/octet-stream", SaveRequest.parse(msg(mime = null), decode)!!.mimeType)
        assertEquals("text/plain", SaveRequest.parse(msg(mime = "Text/Plain; charset=utf-8"), decode)!!.mimeType)
    }
}
