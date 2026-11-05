package com.honoured.app.session

import android.content.Context
import com.honoured.app.AppConfig
import com.honoured.app.bridge.NativeEventStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File

/**
 * Process-wide native session services. They outlive the activity, so a
 * sign-out or a refresh in flight is not cancelled by a rotation or a
 * finishing activity, and M4 workers can use the same store and refresher.
 */
class SessionServices private constructor(context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val dir = File(context.noBackupFilesDir, "honoured")
    private val transport = HttpRefreshTransport(AppConfig.SUPABASE_URL, AppConfig.SUPABASE_ANON_KEY)

    val store = SessionStore(File(dir, "session.bin"), KeystoreSessionCipher())
    val events = NativeEventStore(File(dir, "native-events.json"))
    val registry = AccountScopedRegistry().apply { register("native-events") { events.clear() } }
    val refresher = SessionRefresher(store, transport, scope)
    val mutations = SerialMutationQueue(scope)

    /** Supabase URL (HTTPS) and anon key are present in this build. */
    val isConfigured: Boolean get() = transport.isConfigured

    companion object {
        @Volatile private var instance: SessionServices? = null

        fun get(context: Context): SessionServices =
            instance ?: synchronized(this) {
                instance ?: SessionServices(context.applicationContext).also { instance = it }
            }
    }
}
