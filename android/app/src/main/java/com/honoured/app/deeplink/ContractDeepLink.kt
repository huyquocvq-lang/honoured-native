package com.honoured.app.deeplink

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.UUID

/**
 * `honoured://contract/<percent-encoded id>?day=<YYYY-MM-DD>`, the Android twin
 * of iOS `ContractDeepLink`. iOS links also carry `occurrence=<uuid>`; it is
 * accepted when valid and otherwise unused here. Opening a link only
 * navigates: the page maps the id to a contract of the account signed in now
 * and ignores anything it does not recognise, so nothing in the URL is
 * trusted. Anything malformed is dropped, never half-parsed. Pure JVM, so it
 * runs in local unit tests.
 */
object ContractDeepLink {
    const val SCHEME = "honoured"
    const val HOST = "contract"
    const val MAX_ID_LENGTH = 128
    private const val MAX_URL_LENGTH = 2048
    private val ALLOWED_QUERY = setOf("day", "occurrence")
    private val DAY_PATTERN = Regex("""^\d{4}-\d{2}-\d{2}$""")
    private val DAY_FORMAT: DateTimeFormatter =
        DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)

    data class Target(val contractId: String, val healthDay: String?)

    /** `CONTRACT_LINK_OPENED` payload: navigation fields only, never auth data. */
    fun eventPayload(target: Target, eventId: String): JSONObject = JSONObject()
        .put("eventId", eventId)
        .put("contractId", target.contractId)
        .apply { target.healthDay?.let { put("healthDay", it) } }

    fun parse(raw: String?): Target? {
        if (raw.isNullOrEmpty() || raw.length > MAX_URL_LENGTH) return null
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        if (!uri.scheme.equals(SCHEME, ignoreCase = true)) return null
        if (!uri.host.equals(HOST, ignoreCase = true)) return null
        if (uri.rawUserInfo != null || uri.port != -1 || uri.rawFragment != null) return null

        val path = uri.rawPath ?: return null
        if (!path.startsWith("/")) return null
        val segment = path.substring(1)
        if (segment.isEmpty() || segment.contains('/')) return null
        val contractId = percentDecode(segment) ?: return null
        if (!isValidIdentifier(contractId)) return null

        val query = parseQuery(uri.rawQuery) ?: return null
        val day = query["day"]
        if (day != null && !isValidHealthDay(day)) return null
        val occurrence = query["occurrence"]
        if (occurrence != null && !isValidUuid(occurrence)) return null
        return Target(contractId, day)
    }

    fun isValidIdentifier(value: String): Boolean {
        if (value.isBlank() || value.length > MAX_ID_LENGTH) return false
        if (value.toByteArray(Charsets.UTF_8).size > MAX_ID_LENGTH * 4) return false
        return value.none { Character.getType(it) == Character.CONTROL.toInt() }
    }

    /** `yyyy-MM-dd` naming a real calendar date. */
    fun isValidHealthDay(value: String): Boolean {
        if (!DAY_PATTERN.matches(value)) return false
        return runCatching { LocalDate.parse(value, DAY_FORMAT) }.isSuccess
    }

    private fun isValidUuid(value: String): Boolean =
        value.length == 36 && runCatching { UUID.fromString(value) }.isSuccess

    /** Each allowed name at most once; any other name, or a bare key, rejects the link. */
    private fun parseQuery(raw: String?): Map<String, String>? {
        if (raw == null) return emptyMap()
        if (raw.isEmpty()) return null
        val out = mutableMapOf<String, String>()
        for (pair in raw.split('&')) {
            val eq = pair.indexOf('=')
            if (eq <= 0) return null
            val name = percentDecode(pair.substring(0, eq)) ?: return null
            val value = percentDecode(pair.substring(eq + 1)) ?: return null
            if (name !in ALLOWED_QUERY || name in out || value.isEmpty()) return null
            out[name] = value
        }
        return out
    }

    /** Strict RFC 3986 percent-decoding to UTF-8; `+` stays `+`. Null on malformed input. */
    private fun percentDecode(value: String): String? {
        val bytes = ByteArrayOutputStream()
        var i = 0
        while (i < value.length) {
            val c = value[i]
            if (c == '%') {
                if (i + 2 >= value.length) return null
                val hi = Character.digit(value[i + 1], 16)
                val lo = Character.digit(value[i + 2], 16)
                if (hi < 0 || lo < 0) return null
                bytes.write(hi * 16 + lo)
                i += 3
            } else {
                // Whole code points, so a character outside the BMP (an emoji)
                // is encoded as itself; a lone surrogate rejects the link.
                val cp = value.codePointAt(i)
                if (Character.isSurrogate(c) && Character.charCount(cp) == 1) return null
                val encoded = String(Character.toChars(cp)).toByteArray(Charsets.UTF_8)
                bytes.write(encoded, 0, encoded.size)
                i += Character.charCount(cp)
            }
        }
        return try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes.toByteArray()))
                .toString()
        } catch (e: CharacterCodingException) {
            null
        }
    }
}
