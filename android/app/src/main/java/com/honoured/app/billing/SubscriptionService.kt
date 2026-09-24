package com.honoured.app.billing

import android.app.Activity
import android.content.Context
import com.honoured.app.AppConfig
import com.honoured.app.BuildConfig
import com.honoured.app.auth.SerialCallbackQueue
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.logInWith
import com.revenuecat.purchases.logOutWith
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith
import org.json.JSONObject

object SubscriptionService {
    private var configured = false

    /**
     * identify and logout change the one RevenueCat identity on this device.
     * They run strictly in request order, so a slow logout for the previous
     * account can never finish after the next account's sign-in.
     */
    private val identityQueue = SerialCallbackQueue()

    /** True when RevenueCat is currently bound to exactly this app user. */
    fun isIdentified(appUserID: String): Boolean =
        configured && Purchases.sharedInstance.appUserID == appUserID.trim()

    val isAnonymous: Boolean
        get() = !configured || Purchases.sharedInstance.appUserID.startsWith("\$RCAnonymousID:")

    fun configureIfPossible(context: Context) {
        if (configured) return
        val apiKey = BuildConfig.REVENUECAT_ANDROID_API_KEY.trim()
        if (apiKey.isEmpty()) {
            return
        }

        if (BuildConfig.DEBUG) {
            Purchases.logLevel = LogLevel.DEBUG
        }

        Purchases.configure(
            PurchasesConfiguration.Builder(context.applicationContext, apiKey).build()
        )
        configured = true
    }

    fun identify(appUserID: String, callback: (PurchaseOutcome) -> Unit) {
        identityQueue.enqueue { done ->
            identifyNow(appUserID) { outcome ->
                callback(outcome)
                done()
            }
        }
    }

    private fun identifyNow(appUserID: String, callback: (PurchaseOutcome) -> Unit) {
        if (!configured) {
            callback(PurchaseOutcome.Failed("RevenueCat is not configured"))
            return
        }
        val userId = appUserID.trim()
        if (userId.isBlank()) {
            callback(PurchaseOutcome.Failed("Missing RevenueCat app user ID"))
            return
        }

        if (Purchases.sharedInstance.appUserID == userId) {
            // Identity is already bound. Avoid an unnecessary CustomerInfo
            // request before every purchase; purchaseWith returns the
            // authoritative CustomerInfo when the store finishes.
            callback(
                PurchaseOutcome.Completed(
                    JSONObject()
                        .put("identified", true)
                        .put("appUserID", userId)
                        .put("source", "already_identified")
                )
            )
            return
        }

        Purchases.sharedInstance.logInWith(
            userId,
            onError = { error -> callback(PurchaseOutcome.Failed(error.message)) },
            onSuccess = { customerInfo, _ ->
                callback(PurchaseOutcome.Completed(statusPayload(customerInfo, "identify")))
            }
        )
    }

    fun logout(callback: (PurchaseOutcome) -> Unit) {
        identityQueue.enqueue { done ->
            logoutNow { outcome ->
                callback(outcome)
                done()
            }
        }
    }

    private fun logoutNow(callback: (PurchaseOutcome) -> Unit) {
        if (!configured) {
            callback(PurchaseOutcome.Failed("RevenueCat is not configured"))
            return
        }

        if (Purchases.sharedInstance.appUserID.startsWith("\$RCAnonymousID:")) {
            callback(
                PurchaseOutcome.Completed(
                    JSONObject()
                        .put("isSubscribed", false)
                        .put("source", "already_anonymous")
                )
            )
            return
        }

        Purchases.sharedInstance.logOutWith(
            onError = { error -> callback(PurchaseOutcome.Failed(error.message)) },
            onSuccess = { customerInfo ->
                callback(PurchaseOutcome.Completed(statusPayload(customerInfo, "logout")))
            }
        )
    }

    fun checkAccess(callback: (JSONObject) -> Unit) {
        if (!configured) {
            callback(
                JSONObject()
                    .put("isSubscribed", false)
                    .put("source", "revenuecat_not_configured")
            )
            return
        }

        Purchases.sharedInstance.getCustomerInfoWith(
            onError = { error ->
                callback(
                    JSONObject()
                        .put("isSubscribed", false)
                        .put("source", "revenuecat_error")
                        .put("message", error.message)
                )
            },
            onSuccess = { info -> callback(statusPayload(info, "revenuecat")) }
        )
    }

    fun purchase(activity: Activity, packageIdentifier: String?, callback: (PurchaseOutcome) -> Unit) {
        if (!configured) {
            callback(PurchaseOutcome.Failed("RevenueCat is not configured"))
            return
        }

        Purchases.sharedInstance.getOfferingsWith(
            onError = { error -> callback(PurchaseOutcome.Failed(error.message)) },
            onSuccess = { offerings ->
                val offering = offerings.current
                if (offering == null) {
                    callback(PurchaseOutcome.Failed("No current RevenueCat offering is configured"))
                    return@getOfferingsWith
                }

                val selectedPackage = if (!packageIdentifier.isNullOrBlank()) {
                    offering.availablePackages.firstOrNull { it.identifier == packageIdentifier }
                        ?: run {
                            callback(PurchaseOutcome.Failed("RevenueCat package not found: $packageIdentifier"))
                            return@getOfferingsWith
                        }
                } else {
                    offering.availablePackages.firstOrNull()
                }

                if (selectedPackage == null) {
                    callback(PurchaseOutcome.Failed("No purchasable RevenueCat package is available"))
                    return@getOfferingsWith
                }

                Purchases.sharedInstance.purchaseWith(
                    PurchaseParams.Builder(activity, selectedPackage).build(),
                    onError = { error, userCancelled ->
                        if (userCancelled) callback(PurchaseOutcome.Cancelled)
                        else callback(PurchaseOutcome.Failed(error.message))
                    },
                    onSuccess = { _, customerInfo ->
                        callback(PurchaseOutcome.Completed(statusPayload(customerInfo, "purchase")))
                    }
                )
            }
        )
    }

    fun restore(callback: (PurchaseOutcome) -> Unit) {
        if (!configured) {
            callback(PurchaseOutcome.Failed("RevenueCat is not configured"))
            return
        }

        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error -> callback(PurchaseOutcome.Failed(error.message)) },
            onSuccess = { customerInfo ->
                callback(PurchaseOutcome.Completed(statusPayload(customerInfo, "restore")))
            }
        )
    }

    private fun statusPayload(customerInfo: CustomerInfo, source: String): JSONObject {
        val entitlement = customerInfo.entitlements[AppConfig.REVENUECAT_ENTITLEMENT_ID]
        val payload = JSONObject()
            .put("isSubscribed", entitlement?.isActive == true)
            .put("entitlement", AppConfig.REVENUECAT_ENTITLEMENT_ID)
            .put("appUserID", Purchases.sharedInstance.appUserID)
            .put("source", source)
        entitlement?.expirationDate?.let { payload.put("expiresAt", it.toInstant().toString()) }
        entitlement?.productIdentifier?.let { payload.put("productId", it) }
        return payload
    }
}

sealed class PurchaseOutcome {
    data class Completed(val status: JSONObject) : PurchaseOutcome()
    data object Cancelled : PurchaseOutcome()
    data class Failed(val message: String) : PurchaseOutcome()
}
