package com.honoured.app

import android.app.Activity
import android.content.Context
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.logInWith
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith
import org.json.JSONObject

object SubscriptionService {
    private var configured = false

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
        if (!configured) {
            callback(PurchaseOutcome.Failed("RevenueCat is not configured"))
            return
        }
        if (appUserID.isBlank()) {
            callback(PurchaseOutcome.Failed("Missing RevenueCat app user ID"))
            return
        }

        Purchases.sharedInstance.logInWith(
            appUserID,
            onError = { error -> callback(PurchaseOutcome.Failed(error.message)) },
            onSuccess = { customerInfo, _ ->
                callback(PurchaseOutcome.Completed(statusPayload(customerInfo, "identify")))
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

                val selectedPackage = packageIdentifier
                    ?.let { id -> offering.availablePackages.firstOrNull { it.identifier == id } }
                    ?: offering.availablePackages.firstOrNull()

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
        return JSONObject()
            .put("isSubscribed", entitlement?.isActive == true)
            .put("entitlement", AppConfig.REVENUECAT_ENTITLEMENT_ID)
            .put("appUserID", customerInfo.originalAppUserId)
            .put("source", source)
    }
}

sealed class PurchaseOutcome {
    data class Completed(val status: JSONObject) : PurchaseOutcome()
    data object Cancelled : PurchaseOutcome()
    data class Failed(val message: String) : PurchaseOutcome()
}
