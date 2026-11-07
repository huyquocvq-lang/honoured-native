package com.honoured.app.permissions

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

/**
 * Runtime permissions for the shell: one prompt at a time, the "don't ask
 * again" state, and the app's Settings page for when the person asks for it
 * (Phase 5 M2, A5). Today only the microphone (voice memos) uses it; the
 * notification, activity-recognition and Health Connect prompts of M3–M5 go
 * through the same gate. Must be created before the activity is STARTED.
 * Main thread only.
 */
class PermissionCoordinator(private val activity: ComponentActivity) {
    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val launcher: ActivityResultLauncher<String> = activity.registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> gate.onSystemResult(granted) }

    private val gate: PermissionGate = PermissionGate(
        isGranted = { ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED },
        shouldShowRationale = { activity.shouldShowRequestPermissionRationale(it) },
        wasRequested = { prefs.getBoolean(KEY_PREFIX + it, false) },
        markRequested = { prefs.edit().putBoolean(KEY_PREFIX + it, true).apply() },
        launch = { launcher.launch(it) },
    )

    fun status(permission: String): PermissionGate.Status = gate.status(permission)

    fun request(permission: String, onResult: (PermissionGate.Outcome) -> Unit) = gate.request(permission, onResult)

    /** Only from an explicit tap: Android's page for this app, where blocked permissions are turned back on. */
    fun openAppSettings(): Boolean = try {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    fun destroy() = gate.cancel()

    private companion object {
        const val PREFS = "honoured.permissions"
        const val KEY_PREFIX = "requested."
    }
}
