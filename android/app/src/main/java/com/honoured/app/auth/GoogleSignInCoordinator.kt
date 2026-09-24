package com.honoured.app.auth

import android.app.Activity
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import java.io.IOException

/**
 * Runs Credential Manager's "Sign in with Google" sheet (the explicit button
 * flow, never auto-select) and hands back a Google ID token for the web app to
 * verify with Supabase. Nothing here is persisted or logged.
 */
class GoogleSignInCoordinator(private val activity: Activity, private val serverClientId: String?) {
    sealed class Outcome {
        data class Success(val idToken: String) : Outcome()
        data class Failure(val failure: GoogleAuthFailure) : Outcome()
    }

    private val credentialManager by lazy { CredentialManager.create(activity) }

    val isConfigured: Boolean get() = serverClientId != null

    /** [hashedNonce] is what Google embeds in the ID token; the caller keeps the raw value. */
    suspend fun present(hashedNonce: String): Outcome {
        val clientId = serverClientId ?: return Outcome.Failure(GoogleAuthFailure.NOT_CONFIGURED)
        val option = GetSignInWithGoogleOption.Builder(clientId)
            .setNonce(hashedNonce)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val credential = try {
            credentialManager.getCredential(activity, request).credential
        } catch (e: GetCredentialException) {
            return Outcome.Failure(map(e))
        }
        val isGoogleCredential = credential is CustomCredential &&
            (credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL ||
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_SIWG_CREDENTIAL)
        if (!isGoogleCredential) {
            return Outcome.Failure(GoogleAuthFailure.PROVIDER)
        }
        return try {
            val idToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
            if (idToken.isEmpty()) Outcome.Failure(GoogleAuthFailure.PROVIDER) else Outcome.Success(idToken)
        } catch (e: GoogleIdTokenParsingException) {
            Outcome.Failure(GoogleAuthFailure.PROVIDER)
        }
    }

    /**
     * Clears the credential state providers keep for this app. It does not
     * revoke Google access and touches no other device. False on failure.
     */
    suspend fun clear(): Boolean = try {
        credentialManager.clearCredentialState(ClearCredentialStateRequest())
        true
    } catch (e: ClearCredentialException) {
        false
    }

    private fun map(e: GetCredentialException): GoogleAuthFailure = when (e) {
        is GetCredentialCancellationException -> GoogleAuthFailure.CANCELLED
        is NoCredentialException -> GoogleAuthFailure.NO_CREDENTIAL
        is GetCredentialProviderConfigurationException,
        is GetCredentialUnsupportedException -> GoogleAuthFailure.UNSUPPORTED
        else -> if (e.cause is IOException) GoogleAuthFailure.NETWORK else GoogleAuthFailure.PROVIDER
    }
}
