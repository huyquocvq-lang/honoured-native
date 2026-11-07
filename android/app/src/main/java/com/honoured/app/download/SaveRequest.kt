package com.honoured.app.download

import android.util.Base64
import org.json.JSONObject

/**
 * A file the page asked to save (`<a download>` of a blob: or data: URL, such
 * as Settings › Export my history). WebView has no download UI of its own, so
 * the page script in [DownloadBridge] hands the bytes over instead. Pure: the
 * rules run in local unit tests.
 */
data class SaveRequest(val fileName: String, val mimeType: String, val bytes: ByteArray) {
    companion object {
        const val TYPE = "SAVE_FILE"
        const val MAX_BYTES = 10 * 1024 * 1024
        private const val MAX_NAME = 100
        private val MIME = Regex("""^[a-zA-Z0-9][a-zA-Z0-9!#$&^_.+-]{0,63}/[a-zA-Z0-9][a-zA-Z0-9!#$&^_.+-]{0,63}$""")

        /** Null for anything malformed, oversized or of another type. */
        fun parse(raw: String?, decode: (String) -> ByteArray? = ::decodeBase64): SaveRequest? {
            val json = runCatching { JSONObject(raw ?: return null) }.getOrNull() ?: return null
            if (json.optString("type") != TYPE) return null
            val base64 = json.optString("base64", "")
            // 4 base64 characters carry 3 bytes: refuse before decoding.
            if (base64.length > (MAX_BYTES / 3 + 1) * 4) return null
            val bytes = decode(base64) ?: return null
            if (bytes.size > MAX_BYTES) return null
            val mime = json.optString("mimeType").substringBefore(';').trim().lowercase()
                .takeIf { MIME.matches(it) } ?: "application/octet-stream"
            return SaveRequest(sanitizeFileName(json.optString("fileName")), mime, bytes)
        }

        /** A plain file name: no path, no control characters, bounded; never empty. */
        fun sanitizeFileName(name: String?): String {
            val base = name.orEmpty().substringAfterLast('/').substringAfterLast('\\')
            val clean = base.filter { !Character.isISOControl(it) && it !in "<>:\"|?*" }.trim().trimStart('.')
            return clean.take(MAX_NAME).ifBlank { "download" }
        }

        private fun decodeBase64(value: String): ByteArray? =
            runCatching { Base64.decode(value, Base64.DEFAULT) }.getOrNull()
    }

    override fun equals(other: Any?): Boolean =
        other is SaveRequest && fileName == other.fileName && mimeType == other.mimeType && bytes.contentEquals(other.bytes)

    override fun hashCode(): Int = (fileName.hashCode() * 31 + mimeType.hashCode()) * 31 + bytes.contentHashCode()
}
