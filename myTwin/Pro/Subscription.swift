import Foundation
import RevenueCat

/// Whether this person has myTwin Pro, and the way to buy it.
///
/// Everything in the app that costs money to run — Dash's Gemini voice, the forecast, the
/// suggestions he puts in your calendar — asks this one object. RevenueCat keeps the
/// answer right across reinstalls and devices.
@MainActor
@Observable
final class Subscription {
    /// The entitlement set up in the RevenueCat dashboard.
    private static let entitlement = "mytwin_pro"

    private(set) var isPro = false
    /// The offering the dashboard is currently showing, and the plans inside it.
    private(set) var offering: Offering?
    private(set) var packages: [Package] = []
    private(set) var problem: String?
    private(set) var busy = false

    /// Starts RevenueCat and reads what this person already owns.
    func start() async {
        guard let key = ProKey.current else { return }        // no key yet: everything is free
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key)
        await refresh()
        await loadOfferings()
    }

    /// Asks RevenueCat what this person owns right now.
    func refresh() async {
        guard ProKey.current != nil else { return }
        let info = try? await Purchases.shared.customerInfo()
        isPro = info?.entitlements[Self.entitlement]?.isActive == true
    }

    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current
            packages = offering?.availablePackages ?? []
            if packages.isEmpty { problem = "No plans are set up in RevenueCat yet." }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Keeps up with purchases made elsewhere — another device, or the Customer Center.
    func watchForChanges() async {
        guard ProKey.current != nil else { return }
        for await info in Purchases.shared.customerInfoStream {
            isPro = info.entitlements[Self.entitlement]?.isActive == true
        }
    }

    /// Buys a plan. Quietly does nothing if the person cancels.
    func buy(_ package: Package) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return }
            isPro = result.customerInfo.entitlements[Self.entitlement]?.isActive == true
        } catch {
            problem = error.localizedDescription
        }
    }

    /// For someone who already paid on another device, or after reinstalling.
    func restore() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPro = info.entitlements[Self.entitlement]?.isActive == true
            if !isPro { problem = "Nothing to restore on this Apple Account." }
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The RevenueCat SDK key, kept beside the app rather than in the code. Unlike the Gemini
/// key this one is public by design — it identifies the app, and can do nothing on its own.
enum ProKey {
    static var current: String? {
        let key = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return key?.isEmpty == false ? key : nil
    }
}
