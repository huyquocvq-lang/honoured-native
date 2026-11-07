package com.honoured.app.download

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.lifecycle.lifecycleScope
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ScriptHandler
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.honoured.app.R
import com.honoured.app.auth.TrustedWebOrigin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Saves files the web app offers with `<a download>` (Phase 5 M2, parity
 * matrix R6). WebView ignores those links, so Export my history used to say
 * "Export saved." with nothing saved. A document-start script, injected only
 * into the app's own origin, catches such a click on a blob: or data: link,
 * reads the bytes before the page revokes the URL, and posts them on the
 * origin-scoped `HonouredFiles` listener. The person then picks where to save
 * with the system "Save to" screen. Nothing is written without that choice.
 */
class DownloadSaver(private val activity: ComponentActivity, private val origin: TrustedWebOrigin?) {
    private var pending: SaveRequest? = null
    private val launcher: ActivityResultLauncher<SaveRequest> =
        activity.registerForActivityResult(CreateDocument()) { uri -> onPicked(uri) }

    /** True when this WebView supports both pieces; otherwise downloads stay as they were. */
    val isSupported: Boolean
        get() = origin != null &&
            WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)

    /** Per WebView, before its first load. Returns the handle to remove the script, or null. */
    @SuppressLint("RequiresFeature")
    fun install(webView: WebView): ScriptHandler? {
        val origin = origin ?: return null
        if (!isSupported) return null
        val rules = setOf(origin.listenerRule)
        WebViewCompat.addWebMessageListener(webView, JS_OBJECT, rules) { _, message, sourceOrigin, isMainFrame, _: JavaScriptReplyProxy ->
            onMessage(message, sourceOrigin, isMainFrame)
        }
        return WebViewCompat.addDocumentStartJavaScript(webView, PAGE_SCRIPT, rules)
    }

    @SuppressLint("RequiresFeature")
    fun uninstall(webView: WebView, script: ScriptHandler?) {
        runCatching { script?.remove() }
        runCatching { WebViewCompat.removeWebMessageListener(webView, JS_OBJECT) }
    }

    private fun onMessage(message: WebMessageCompat, sourceOrigin: Uri, isMainFrame: Boolean) {
        val trusted = origin ?: return
        if (!isMainFrame || !trusted.matches(sourceOrigin.scheme, sourceOrigin.host, sourceOrigin.port)) return
        val request = SaveRequest.parse(message.data) ?: return
        // One save screen at a time; a second tap while it is open is dropped.
        if (pending != null) return
        pending = request
        runCatching { launcher.launch(request) }.onFailure {
            pending = null
            toast(R.string.download_failed)
        }
    }

    private fun onPicked(uri: Uri?) {
        val request = pending ?: return
        pending = null
        if (uri == null) return // the person cancelled
        activity.lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    activity.contentResolver.openOutputStream(uri, "wt")?.use { it.write(request.bytes) } != null
                }.getOrDefault(false)
            }
            toast(if (ok) R.string.download_saved else R.string.download_failed)
        }
    }

    private fun toast(text: Int) = Toast.makeText(activity, text, Toast.LENGTH_SHORT).show()

    private class CreateDocument : ActivityResultContract<SaveRequest, Uri?>() {
        override fun createIntent(context: android.content.Context, input: SaveRequest): Intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(input.mimeType)
                .putExtra(Intent.EXTRA_TITLE, input.fileName)

        override fun parseResult(resultCode: Int, intent: Intent?): Uri? =
            if (resultCode == Activity.RESULT_OK) intent?.data else null
    }

    companion object {
        const val JS_OBJECT = "HonouredFiles"

        /** Capture phase, so it runs inside the page's own a.click(), before URL.revokeObjectURL. */
        val PAGE_SCRIPT = """
            (function () {
              if (window.__honouredDownloads) return;
              window.__honouredDownloads = true;
              document.addEventListener('click', function (e) {
                var a = e.target && e.target.closest ? e.target.closest('a[download]') : null;
                if (!a || !window.$JS_OBJECT) return;
                var href = a.href || '';
                if (href.indexOf('blob:') !== 0 && href.indexOf('data:') !== 0) return;
                e.preventDefault();
                var name = a.getAttribute('download') || 'download';
                fetch(href).then(function (r) { return r.blob(); }).then(function (b) {
                  if (b.size > ${SaveRequest.MAX_BYTES}) return null;
                  return new Promise(function (resolve, reject) {
                    var fr = new FileReader();
                    fr.onload = function () { resolve({ type: b.type, data: String(fr.result).split(',')[1] || '' }); };
                    fr.onerror = reject;
                    fr.readAsDataURL(b);
                  });
                }).then(function (f) {
                  if (!f) return;
                  window.$JS_OBJECT.postMessage(JSON.stringify({ type: '${SaveRequest.TYPE}', fileName: name, mimeType: f.type || 'application/octet-stream', base64: f.data }));
                }).catch(function () {});
              }, true);
            })();
        """.trimIndent()
    }
}
