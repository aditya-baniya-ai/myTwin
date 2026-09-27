import RevenueCat
import RevenueCatUI
import SwiftUI

/// The paywall the person sees: the one designed in the RevenueCat dashboard when there is
/// one, and myTwin's own if the offering has none configured yet.
///
/// `hasPaywall` covers both kinds the dashboard can produce — the older single design and
/// the newer component-based one. Checking `offering.paywall` only finds the older kind,
/// which is why it's deprecated.
struct ProPaywall: View {
    let pro: Subscription
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let offering = pro.offering, offering.hasPaywall {
            // The dashboard's paywall doesn't close itself, so it lands you back where
            // you were, the same way myTwin's own does.
            RevenueCatUI.PaywallView(offering: offering)
                .onPurchaseCompleted { _ in dismiss() }
                .onRestoreCompleted { info in
                    if info.entitlements[Subscription.entitlement]?.isActive == true { dismiss() }
                }
        } else {
            PaywallView(pro: pro)
        }
    }
}

/// myTwin's own paywall, used when the dashboard offering has no paywall of its own.
/// Written in the app's voice, and honest about why these particular things cost money.
struct PaywallView: View {
    let pro: Subscription
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Package?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: BrandTitle.brand,
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("myTwin Pro").font(.title2.bold())
                    Text("Your twin stops describing your day and starts planning it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                VStack(alignment: .leading, spacing: 14) {
                    benefit("chart.line.uptrend.xyaxis", "Your energy, hour by hour",
                            "Where your peak lands and when the dip hits, today.")
                    benefit("calendar.badge.plus", "Plans that fit your day",
                            "A workout in your strongest free hour, a nap at the dip, the last coffee that still clears before bed.")
                    benefit("waveform", "Dash talks back",
                            "A natural voice and smarter answers about your sleep, energy and plans.")
                    benefit("arrow.triangle.2.circlepath", "Rescue a busy day",
                            "Adapt a flexible activity to your time and preferences, with confirmation and undo.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))

                if pro.packages.isEmpty {
                    Text("Plans are loading. If this sticks, check your connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry loading plans") { Task { await pro.loadOfferings() } }
                } else {
                    VStack(spacing: 10) {
                        ForEach(pro.packages, id: \.identifier) { package in
                            plan(package)
                        }
                    }
                }

                Text("Free either way: your energy score, today's numbers and your reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let problem = pro.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
                Button {
                    guard let package = chosen ?? pro.packages.first else { return }
                    Task {
                        await pro.buy(package)
                        if pro.isPro { dismiss() }
                    }
                } label: {
                    Text(pro.busy ? "One moment…" : "Start with Pro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(BrandTitle.brand[1])
                .disabled(pro.packages.isEmpty || pro.busy)

                HStack(spacing: 18) {
                    Button("Restore") { Task { await pro.restore(); if pro.isPro { dismiss() } } }
                    Button("Not now") { dismiss() }
                }
                .font(.footnote)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            .animation(.snappy, value: pro.problem)
        }
        // Plans may still be loading when the paywall opens, so pick again when they land.
        .onChange(of: pro.packages.count, initial: true) {
            guard chosen == nil else { return }
            chosen = pro.packages.first { $0.packageType == .annual } ?? pro.packages.first
        }
    }

    /// What to call a plan. RevenueCat knows the common ones; anything else uses the name
    /// the product was given in the dashboard.
    private func planName(_ package: Package) -> String {
        switch package.packageType {
        case .annual: "Yearly"
        case .monthly: "Monthly"
        case .weekly: "Weekly"
        case .lifetime: "Lifetime"
        case .sixMonth: "6 months"
        case .threeMonth: "3 months"
        case .twoMonth: "2 months"
        default: package.storeProduct.localizedTitle
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(BrandTitle.brand[1])
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func plan(_ package: Package) -> some View {
        let picked = chosen?.identifier == package.identifier
        return Button {
            chosen = package
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planName(package))
                        .font(.subheadline.weight(.semibold))
                    Text(package.storeProduct.localizedPriceString)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked ? BrandTitle.brand[1] : .secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(picked ? BrandTitle.brand[1] : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Stands in for something Pro unlocks: says what it is, and opens the paywall.
struct LockedCard: View {
    let title: String
    let detail: String
    let unlock: () -> Void

    var body: some View {
        Button(action: unlock) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(BrandTitle.brand[1])
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    Text("See myTwin Pro")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTitle.brand[1])
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .dashboardCard()
        }
        .buttonStyle(.plain)
    }
}

/// RevenueCat's Customer Center: cancelling, restoring, refunds and plan changes, without
/// myTwin having to build any of it.
struct ProCustomerCentre: View {
    var body: some View {
        CustomerCenterView()
    }
}
