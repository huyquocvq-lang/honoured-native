import Foundation
import RevenueCat

@MainActor
final class SubscriptionService {
    static let shared = SubscriptionService()

    private(set) var isConfigured = false

    private init() {}

    func configureIfPossible() {
        guard !isConfigured else { return }
        guard !AppConfig.revenueCatAPIKey.isEmpty else {
            print("RevenueCat iOS API key is not configured")
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: AppConfig.revenueCatAPIKey)
        isConfigured = true
    }

    func identify(appUserID: String) async -> PurchaseOutcome {
        guard isConfigured else {
            return .failed("RevenueCat is not configured")
        }
        guard !appUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("Missing RevenueCat app user ID")
        }

        return await withCheckedContinuation { continuation in
            Purchases.shared.logIn(appUserID) { customerInfo, _, error in
                if let error {
                    continuation.resume(returning: .failed(error.localizedDescription))
                    return
                }
                guard let customerInfo else {
                    continuation.resume(returning: .failed("RevenueCat login returned no customer info"))
                    return
                }
                continuation.resume(returning: .completed(self.statusPayload(customerInfo: customerInfo, source: "identify")))
            }
        }
    }

    func accessStatus() async -> [String: Any] {
        guard isConfigured else {
            return [
                "isSubscribed": false,
                "source": "revenuecat_not_configured"
            ]
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            return statusPayload(customerInfo: customerInfo, source: "revenuecat")
        } catch {
            return [
                "isSubscribed": false,
                "source": "revenuecat_error",
                "message": error.localizedDescription
            ]
        }
    }

    func purchase(packageIdentifier: String?) async -> PurchaseOutcome {
        guard isConfigured else {
            return .failed("RevenueCat is not configured")
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current else {
                return .failed("No current RevenueCat offering is configured")
            }

            let package = packageIdentifier.flatMap { id in
                offering.availablePackages.first(where: { $0.identifier == id })
            } ?? offering.availablePackages.first

            guard let package else {
                return .failed("No purchasable RevenueCat package is available")
            }

            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return .cancelled
            }

            return .completed(statusPayload(customerInfo: result.customerInfo, source: "purchase"))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> PurchaseOutcome {
        guard isConfigured else {
            return .failed("RevenueCat is not configured")
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            return .completed(statusPayload(customerInfo: customerInfo, source: "restore"))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func statusPayload(customerInfo: CustomerInfo, source: String) -> [String: Any] {
        let entitlement = customerInfo.entitlements[AppConfig.revenueCatEntitlementID]
        var payload: [String: Any] = [
            "isSubscribed": entitlement?.isActive == true,
            "entitlement": AppConfig.revenueCatEntitlementID,
            "appUserID": customerInfo.originalAppUserId,
            "source": source
        ]

        if let expirationDate = entitlement?.expirationDate {
            payload["expirationDate"] = ISO8601DateFormatter().string(from: expirationDate)
        }

        return payload
    }
}

enum PurchaseOutcome {
    case completed([String: Any])
    case cancelled
    case failed(String)
}
